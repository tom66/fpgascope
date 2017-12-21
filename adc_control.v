// This module controls the ADC
//
// Two clocks are generated
//   - Trigger clock is continuously sampling the ADC at 1/2 rate from master clock
//   - Acquisition clock latches Nth data from trigger if trigger event occurs
//
// It also handles generation of acquisition control and trigger signals
//
// (C) Thomas Oldbury 2017

// -- Definitions --
module adc_control (
	// clock
	clkin,
	divider_acq_clk,
	// control in
	run_in,
	stop_in,
	// state return to display controller
	state_runmode,					// 0 = STOPPED, 1 = RUNNING
	state_trig,						// 0 = Waiting for Trigger, 1 = Triggered, 2 = Auto Triggered
	// state output (debug)
	debug_led,
	// trigger settings
	trig_mode,						// 0 = normal, 1 = auto, 2 = single
	trig_lvl,
	trig_type,
	trig_noiserej,
	// ADC
	adc_clkout_a,
	adc_clkout_b,
	adc_unlatched_data_a,
	adc_unlatched_data_b,
	adcoen_a,
	adcoen_b,
	// ramout signals
	clk_ramout,
	addr_ramout_a,
	addr_ramout_b,
	wr_en_ramout,
	data_wr_ramout_a,
	data_wr_ramout_b
);

parameter TRIG_NORM = 0;
parameter TRIG_AUTO = 1;
parameter TRIG_SINGLE = 2;					

parameter TRIG_STATE_WAIT = 0;
parameter TRIG_STATE_TRIGD = 1;
parameter TRIG_STATE_AUTO = 2;
parameter TRIG_STATE_DONE = 3;			// only in SINGLE mode

parameter CLK_DIV_WIDTH = 24;
parameter ADC_WIDTH = 14;
parameter ACQ_MAX_SAMPLES = 1024;		// max 1024 samples
parameter ACQ_COUNTER_WIDTH = 12;		// up to 12 bits wide

parameter AUTO_MODE_DELAY = 60000000;	// delay before auto mode trigger
parameter AUTO_MODE_FAST = 2500000;		// delay between triggers after first auto mode trigger
parameter NO_TRIG_DELAY = 50000;			// delay before "Trig?" in any mode
parameter HOLD_OFF_DELAY = 4;				// Hold-off before next trigger in clock cycles

// States that our acquisition engine can be in
parameter STATE_STOPPED = 0;				// Not currently acquiring; waiting for RUN signal
parameter STATE_WAIT_FOR_TRIG = 1;		// Waiting for trigger event to begin acquisition
parameter STATE_ACQUIRE = 2;				// Acquiring data until number of samples is reached
parameter STATE_HOLD_OFF = 3;				// Post-trigger hold-off before rearm state
parameter STATE_POST_TRIG = 4;			// Post-trigger handling (immediately jumps back to WAIT_FOR_TRIG if STOP flag not set)

// Hysteresis levels
parameter HYST_NOISEREJ_ON = 200;		// determined empirically to reduce jitter with noisy inputs
parameter HYST_NOISEREJ_OFF = 12;		// small hysteresis level as minimum

input [CLK_DIV_WIDTH - 1:0] divider_acq_clk;
input [ADC_WIDTH - 1:0] adc_unlatched_data_a;
input [ADC_WIDTH - 1:0] adc_unlatched_data_b;
input clkin;
wire clktrig;
wire clkacq;

// ADC clock and output enables
output adc_clkout_a;
output adc_clkout_b;
output adcoen_a;
output adcoen_b;

// state control and feedback
input run_in, stop_in;
output reg state_runmode;
output reg [2:0] state_trig;
input [1:0] trig_mode;
input [15:0] trig_lvl;
input [2:0] trig_type;			// 1 = pos, 2 = neg, 3 = both, other states unused
input trig_noiserej;				// hysteresis enable

// debug LEDs for state machine
output reg [7:0] debug_led;

// ramout signals
output wire clk_ramout;
output reg [ACQ_COUNTER_WIDTH - 1:0] addr_ramout_a;
output reg [ACQ_COUNTER_WIDTH - 1:0] addr_ramout_b;
output reg wr_en_ramout;
output reg [ADC_WIDTH - 1:0] data_wr_ramout_a;
output reg [ADC_WIDTH - 1:0] data_wr_ramout_b;

// Drive RAM clock. 1:1 of clkin. If you forget this, it will not generate a clock signal, but will not fail.
// It will then complain that you have an asychronous read and spend 12 minutes implementing your blockram
// into something like 14,000 latches and use about 20% of the FPGA's logic area.
// So don't forget it.
assign clk_ramout = clkin;

// XXX: trigger, unused (delete?)
reg trig_en;
wire trig_out;

// hold-off counter
reg [15:0] hold_off;

// trigger timeout
reg [31:0] trig_timeout;
reg trig_auto_rapid;
reg auto_trig_gen;

// acquisition index counter
reg [ACQ_COUNTER_WIDTH - 1:0] acq_index;

// state machine for acquisition engine
reg [2:0] acq_state;

// -- Functional Implementation --

// Generate acquisition clock (~1-25MHz, divide by 2~25)
adc_clock_gen cg1 (
	.clkin(clkin),
	.clkout(clkacq),
	.reset(0),
	.enable(1),
	.divider(divider_acq_clk)
);

// Trigger (channel A only - later a mux to switch channels and trigger types)
edge_Trig tr0(
	.clkIn(clkin),
	.trigLvl(trig_lvl),
	.trigHyst((trig_noiserej) ? HYST_NOISEREJ_ON : HYST_NOISEREJ_OFF),
	.adc_data(adc_unlatched_data_a),
	.type(trig_type),			
	.enable(trig_en),
	.q(trig_out)
);

// Enable ADC outputs (active LOW)
assign adcoen_a = 1'b0;
assign adcoen_b = 1'b0;

// Drive ADC clocks
assign adc_clkout_a = clkacq;
assign adc_clkout_b = clkacq;

// On acquisition clock negedge, process state machine
always @(negedge clkacq) begin

	// If we are STOPPED, we goto WAIT_FOR_TRIG if run_in is HIGH
	// (Very simple RUN/STOP control, could also add a SINGLE mode.)
	if (acq_state == STATE_STOPPED) begin
		debug_led = 5'b00001;
		state_runmode <= 0;
		if (run_in) begin
			state_runmode <= 1;
			acq_state = STATE_WAIT_FOR_TRIG;
		end
	end
	
	// Wait for a trigger edge, then jump to next state
	if (acq_state == STATE_WAIT_FOR_TRIG) begin
		trig_en <= 1;
		debug_led = 5'b00010;
		
		// If we get a stop request now, jump back to STOP
		// Otherwise check for a comparator event
		if (stop_in) begin
			acq_state = STATE_STOPPED;
		end else if (trig_out || auto_trig_gen) begin 
			trig_en <= 0;
			acq_index <= 0;
			addr_ramout_a = 0;
			addr_ramout_b = 0;
			acq_state = STATE_ACQUIRE;
			if (!auto_trig_gen) begin
				state_trig <= TRIG_STATE_TRIGD;
			end;
			auto_trig_gen <= 0;
		end
		
		// While we are waiting for a trigger event increment a timer
		// If the timer overflows in AUTO mode then force a trigger but 
		// do not set the TRIG'D output (set the AUTO output instead)
		trig_timeout <= trig_timeout + divider_acq_clk + 1;
		
		if ((trig_mode == TRIG_AUTO) && (trig_timeout > AUTO_MODE_FAST) && (trig_auto_rapid == 1)) begin
			// jump to acquire state
			trig_timeout <= 0;
			state_trig <= TRIG_STATE_AUTO;
			auto_trig_gen <= 1;
			trig_auto_rapid <= 1;
		end else if ((trig_mode == TRIG_AUTO) && (trig_timeout > AUTO_MODE_DELAY) && (trig_auto_rapid == 0)) begin
			// jump to acquire state, change flag to rapid auto mode
			trig_timeout <= 0;
			state_trig <= TRIG_STATE_AUTO;
			trig_auto_rapid <= 1;
			auto_trig_gen <= 1;
		end else if ((trig_timeout > NO_TRIG_DELAY) && (trig_mode != TRIG_AUTO)) begin
			// Set wait flag after first window expires
			state_trig <= TRIG_STATE_WAIT;
		end
	end
	
	// Acquire data and write it into the main ramout
	if (acq_state == STATE_ACQUIRE) begin
		trig_timeout <= 0;
		debug_led = 5'b00100;
		if (acq_index == ACQ_MAX_SAMPLES) begin
			acq_state = STATE_HOLD_OFF;
			hold_off <= HOLD_OFF_DELAY;
			wr_en_ramout = 0;
		end else begin
			// Move counters. These are effectively the same number, but keeping them
			// separate allows us to implement an interleaved acquisition memory in the future,
			// or a pre/post trigger.
			addr_ramout_a = addr_ramout_a + 1;
			addr_ramout_b = addr_ramout_b + 1;
			acq_index <= acq_index + 1;
			
			// Store the data acquired from the ADC 
			wr_en_ramout = 1;
			data_wr_ramout_a = adc_unlatched_data_a;
			data_wr_ramout_b = adc_unlatched_data_b; 
		end
	end
	
	// There is a hold-off delay of some number of clock cycles below changing state.
	// This reduces the likelihood that we will re-trigger on our signal alias.
	if (acq_state == STATE_HOLD_OFF) begin
		hold_off <= hold_off - 1;
		debug_led = 5'b01000;
		if (hold_off == 0) begin
			acq_state = STATE_POST_TRIG;
		end;
	end;
	
	// End state, rearms acquisition back to STATE_WAIT_FOR_TRIG if stop_in not asserted
	// If stop_in is asserted then drops to STATE_STOPPED which will wait for run_in
	// Also checks for SINGLE state, if we are in SINGLE mode then it disarms the trigger
	// and sets the SINGLE DONE flag.   To exit SINGLE mode, run_in must be driven high.
	if (acq_state == STATE_POST_TRIG) begin
		if (trig_mode == TRIG_SINGLE) begin
			state_trig <= TRIG_STATE_DONE;
			acq_state = STATE_STOPPED;
		end else begin
			debug_led = 5'b10000;
			if (stop_in) begin
				acq_state = STATE_STOPPED;
			end else begin
				acq_state = STATE_WAIT_FOR_TRIG;
			end
		end
	end

end

endmodule
