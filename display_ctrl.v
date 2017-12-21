// Display controller for oscilloscope
//
// Interfaces with VGA module to control display
// 
// Also draws waveform - basic principle of operation is to read waveram 
// on each X pixel and check if the resulting wave value is w/in bounds
// for that pixel
//
// (C) Thomas Oldbury 2017

module display_ctrl(
	clk_main,
	// VGA module feedthrough: pixel information and write bus
	pix_clk, pix_h, pix_v, 
	r_pix_write_bus, 
	g_pix_write_bus, 
	b_pix_write_bus,
	frame_counter,
	// Debug state
	debug_led,
	// PS/2 keyboard interface
	dat_keyboard,
	clk_keyboard,
	// Oscilloscope acq control signals
	run_out,
	stop_out,
	trig_mode,
	trig_type,
	trig_lvl,
	trig_noiserej,
	time_div_clk_divider,
	// Oscilloscope acq system state
	state_runmode,								// 0 = STOPPED, 1 = RUNNING				
	state_trig,	
	// Waveform RAM memory feedthrough
	clk_ram,
	addr_waveram_a,
	addr_waveram_b,
	rd_en_waveram,
	data_rd_waveram_a,
	data_rd_waveram_b,
	// Character generator memory for writing to the display
	addr_charram,
	wr_en_charram,
	data_wr_charram,
	// Attribute generator memory for character grid
	addr_attrram,
	wr_en_attrram,
	data_wr_attrram
);

// Display limits
parameter DISP_WIDTH = 640;
parameter DISP_HEIGHT = 480;

// Scope screen parameters
parameter SCOPE_SCRN_XOFF = 32;
parameter SCOPE_SCRN_YOFF = 32;
parameter SCOPE_SCRN_XSIZE	= 512;
parameter SCOPE_SCRN_YSIZE	= 384;
parameter SCOPE_SCRN_YSIZE_WAVE = 512;
parameter SCOPE_WAVE_OFFSET = 2048;
parameter SCOPE_V_GRATICLES = 12;
parameter SCOPE_H_GRATICLES = 16;
parameter SCOPE_GRAT_SIZE = 32;
parameter SCOPE_Y_MID = 8192;
parameter SCOPE_Y_MAX = 16384;

// ADC correction factor
parameter ADC_OFFSET_CHA = 12;
parameter ADC_OFFSET_CHB = 12;

// Clipping points
parameter SCOPE_Y_MAX_DISP = 14288; 	// 14335
parameter SCOPE_Y_MIN_DISP = 2048;

// String printer state machine
parameter STR_PRINT_NAME = 0;
parameter STR_PRINT_RUN_STOP = 1;
parameter STR_PRINT_TRIG_STATUS = 2;
parameter STR_PRINT_CHAN_INFO_A = 3;
parameter STR_PRINT_CHAN_INFO_B = 4;
parameter STR_PRINT_TIMEBASE = 5;
parameter STR_PRINT_TRIG_TYPE = 6;
parameter STR_PRINT_TRIG_TYPE_2ND = 7;
parameter STR_PRINT_TIME = 8;
parameter STR_PRINT_DEBUG = 9;
parameter STR_PRINT_CREDIT = 10;
parameter STR_PRINT_EOF = 255;

// How many clock ticks per second (divided)
parameter CLOCK_TICKS_PER_SEC = 50000000;

// PS/2 clock divider (2048 to get 12.2kHz - spec is 10-16.7kHz)
// The divider is a power-of-two to simplify the logic implementation
parameter PS2_CLOCK_DIV = 2048;

// A >60us delay between transfers for PS/2 clock which is 4096
parameter PS2_CLOCK_WAIT = 4096;
parameter PS2_CYC_COUNTER = 20;

// Keyboard scanned every 200ms to avoid key repeat issues
parameter KEYBD_SCAN_CTR = 10000000;

// Max string length (16 chars) for print function
parameter MAX_STRING = 16;

input clk_main;

// State
reg [7:0] str_state;
reg [13:0] wave_y_value;
reg [13:0] wave_y_value_next;
reg [13:0] wave_x_addr;
reg [7:0] r_pix_wave;	
reg [7:0] g_pix_wave;	
reg [7:0] b_pix_wave;
reg [15:0] count;
reg [15:0] writepos;
reg [12:0] ps2_div_ctr;
reg cha_enabled;
reg chb_enabled;
reg dot_mode;

// Trigger level and type
output reg [15:0] trig_lvl;
output reg [1:0] trig_type;					// 1 = rising, 2 = falling, 3 = both
output reg [1:0] trig_mode;					// 0 = normal, 1 = auto, 2 = single
output reg trig_noiserej;						// 0 = noise reject off, 1 = noise reject on (hysteresis)

// Acquisition front end state
input state_runmode;
input [2:0] state_trig;

// Acquisition control
output reg run_out;
output reg stop_out;

// WaveRAM interface
input wire clk_ram;
output reg [9:0] addr_waveram_a;
output reg [9:0] addr_waveram_b;
output reg rd_en_waveram;
input [13:0] data_rd_waveram_a;
input [13:0] data_rd_waveram_b;

// CharRAM interface (including attributes)
output reg [11:0] addr_charram;
output reg wr_en_charram;
output reg [6:0] data_wr_charram;
output reg [11:0] addr_attrram;
output reg wr_en_attrram;
output reg [6:0] data_wr_attrram;

// VGA interface ports
input pix_clk;
input [31:0] frame_counter;
input [9:0] pix_h;		
input [9:0] pix_v;	
output wire [7:0] r_pix_write_bus;	
output wire [7:0] g_pix_write_bus;	
output wire [7:0] b_pix_write_bus;	

// Debug state - drives LEDs
output reg [7:0] debug_led;

// Graphic layers which are OR'd together to produce output
wire [7:0] r_pix_write_graphic_bus;	
wire [7:0] g_pix_write_graphic_bus;	
wire [7:0] b_pix_write_graphic_bus;	
reg [7:0] r_pix_write_wave;	
reg [7:0] g_pix_write_wave;	
reg [7:0] b_pix_write_wave;	

// Time since start stored in "BCD" format
reg [27:0] sec_ctr;
reg [3:0] hour_tens;
reg [3:0] hour_ones;
reg [3:0] min_tens;
reg [3:0] min_ones;
reg [3:0] sec_tens;
reg [3:0] sec_ones;

// PS/2 interface
input dat_keyboard;
input clk_keyboard;
reg key_code_available;			// code has been emitted by keyboard
reg key_ready;						// data ready to read from key_data
reg [7:0] key_data;
wire [7:0] key_code_raw;
reg [7:0] key_code_raw_old;
reg [7:0] key_hexU;
reg [7:0] key_hexL;
reg [31:0] key_tick_ctr;

// Volt/div state for channels. We have no physical attenuator so this is implemented by multiplies.
// Volt/div increments are: 1mV/div, 2mV/div, 5mV/div, 10mV/div, 20mV/div, 50mV/div, 100mV/div, 200mV/div and 500mV/div
reg [8:0] ch_a_volt_div;	// div scale in 5-500 (mV/div)
reg [8:0] ch_b_volt_div;
reg [3:0] ch_a_volt_idx; 	// 0 - 9, 0 = 5mV/div
reg [3:0] ch_b_volt_idx;
// Character arrays for above
reg [7:0] ch_a_volt_div_char [2:0];
reg [7:0] ch_b_volt_div_char [2:0];

// Time/div state for timebase. Acquisition clock is implemented using clock divider.
// Supported time/div increments are: 1.25us/div, 2.5us/div, 5us/div, 10us/div, 20us/div and 50us/div
// Clock divider value is passed to acquisition engine to generate correct clock.
reg [7:0] time_div_char [3:0];
reg [3:0] time_div_idx;
output reg [7:0] time_div_clk_divider;

// Background fill to ensure there is a default state of black
vga_fillarea vga_bg_fill (
	.xin(pix_h),
	.yin(pix_v),
	.x0(0),
	.y0(0),
	.x1(640),
	.y1(480),
	.colour(5'b00000),
	.writeout_r(r_pix_write_graphic_bus),
	.writeout_g(g_pix_write_graphic_bus),
	.writeout_b(b_pix_write_graphic_bus)
);

// Outline rectangle of whole screen - allows LCD monitor to auto adjust correctly
vga_rectangle vgarect_scope_graticle_border (
	.xin(pix_h),
	.yin(pix_v),
	.x0(1),
	.y0(1),
	.x1(639),
	.y1(479),
	.colour(5'b01000),
	.writeout_r(r_pix_write_graphic_bus),
	.writeout_g(g_pix_write_graphic_bus),
	.writeout_b(b_pix_write_graphic_bus)
);

// Outline rectangle of scope screen
vga_rectangle vgarect_display_vga_outline (
	.xin(pix_h),
	.yin(pix_v),
	.x0(SCOPE_SCRN_XOFF),
	.y0(SCOPE_SCRN_YOFF),
	.x1(SCOPE_SCRN_XOFF + SCOPE_SCRN_XSIZE),
	.y1(SCOPE_SCRN_YOFF + SCOPE_SCRN_YSIZE),
	.colour(5'b00111),
	.writeout_r(r_pix_write_graphic_bus),
	.writeout_g(g_pix_write_graphic_bus),
	.writeout_b(b_pix_write_graphic_bus)
);

// Generate the graticles
genvar i;
generate
	
	for (i = 0; i < SCOPE_V_GRATICLES; i = i + 1) begin: loopv
		vga_hline (
			.xin(pix_h),
			.yin(pix_v),
			.x0(SCOPE_SCRN_XOFF),
			.x1(SCOPE_SCRN_XOFF + SCOPE_SCRN_XSIZE),
			.y(SCOPE_SCRN_YOFF + (i * SCOPE_GRAT_SIZE)),
			.colour(5'b01000),
			.dot_mode(2'b01),
			.writeout_r(r_pix_write_graphic_bus),
			.writeout_g(g_pix_write_graphic_bus),
			.writeout_b(b_pix_write_graphic_bus)
		);
	end
	
	for (i = 0; i < SCOPE_H_GRATICLES; i = i + 1) begin: looph
		vga_vline (
			.xin(pix_h),
			.yin(pix_v),
			.x(SCOPE_SCRN_XOFF + (i * SCOPE_GRAT_SIZE)),
			.y0(SCOPE_SCRN_YOFF),
			.y1(SCOPE_SCRN_YOFF + SCOPE_SCRN_YSIZE),
			.colour(5'b01000),
			.dot_mode(2'b01),
			.writeout_r(r_pix_write_graphic_bus),
			.writeout_g(g_pix_write_graphic_bus),
			.writeout_b(b_pix_write_graphic_bus)
		);
	end

endgenerate 

// Test lines for VGA controller
vga_hline vgahline_test_line_0 (
	.xin(pix_h),
	.yin(pix_v),
	.x0(SCOPE_SCRN_XOFF),
	.x1(SCOPE_SCRN_XOFF + SCOPE_SCRN_XSIZE),
	.y(SCOPE_SCRN_YOFF - 20),
	.dot_mode(2'b00),
	.colour(5'b00001),
	.writeout_r(r_pix_write_graphic_bus),
	.writeout_g(g_pix_write_graphic_bus),
	.writeout_b(b_pix_write_graphic_bus)
);

vga_hline vgahline_test_line_1 (
	.xin(pix_h),
	.yin(pix_v),
	.x0(SCOPE_SCRN_XOFF),
	.x1(SCOPE_SCRN_XOFF + SCOPE_SCRN_XSIZE),
	.y(SCOPE_SCRN_YOFF - 30),
	.dot_mode(2'b00),
	.colour(5'b00010),
	.writeout_r(r_pix_write_graphic_bus),
	.writeout_g(g_pix_write_graphic_bus),
	.writeout_b(b_pix_write_graphic_bus)
);

assign r_pix_write_bus = r_pix_write_graphic_bus | r_pix_write_wave;
assign g_pix_write_bus = g_pix_write_graphic_bus | g_pix_write_wave;
assign b_pix_write_bus = b_pix_write_graphic_bus | b_pix_write_wave;

// PS/2 keyboard interface (external IP)
// No write-back to keyboard, simple interface only
ps2key ps2_keyboard (
	.clk50(clk_main),
	.kin(dat_keyboard),
	.kclk(clk_keyboard),	
	.code(key_code_raw)
);
	
// Initial state
initial begin

	run_out <= 1;
	ch_a_volt_idx <= 8;
	ch_b_volt_idx <= 8;
	time_div_idx <= 0;
	cha_enabled <= 1;
	chb_enabled <= 1;
	trig_lvl <= 8192;
	trig_type <= 1;

end

// Keyboard handler and string writer - handles the string state machine and keyboard-driven system control
// Could probably run at a lower sub clock - no need to rewrite ~1,000,000 times a second!
always @(negedge clk_main) begin

	// These flags are cleared on acknowledgement of state change,
	// and only set when a signal needs to be sent to the acquisition controller.
	if (state_runmode == 0) begin
		stop_out <= 0;
	end;
	if (state_runmode == 1) begin
		run_out <= 0;
	end;
	
	// If both channels are disabled then stop acquisition
	if (!cha_enabled && !chb_enabled) begin
		stop_out <= 1;
	end;

	// Latch a change in key_code into our register
	// We only work on MAKE events for simplicity, with a simple 1-byte code
	// Code F0h causes the next byte to be skipped;
	// Code E0h causes the next two bytes to be skipped.
	if (key_code_raw != key_code_raw_old) begin
		key_code_available <= 1;
		key_code_raw_old <= key_code_raw;
	end;
	
	if (key_code_available) begin
		key_code_available <= 0;
		
		if ((key_code_raw != 8'hf0) && (key_code_raw != 8'he0)) begin
			key_ready <= 1;
			key_data <= key_code_raw;
		end;
	end;

	wr_en_charram <= 1;
	wr_en_attrram <= 1;

	// I can't think of a better way to print strings!! 
	// But man is this ugly.
	// I apologise in advance if it induces cancer.
	
	// The name of this fine instrument
	if (str_state == STR_PRINT_NAME) begin
		if (count < 22) begin
			wr_en_charram <= 1;
			case (count)
				0:		data_wr_charram <= "S";
				1:		data_wr_charram <= "c";
				2:		data_wr_charram <= "o";
				3:		data_wr_charram <= "p";
				4:		data_wr_charram <= "y";
				5:		data_wr_charram <= " ";
				6:		data_wr_charram <= "M";
				7:		data_wr_charram <= "c";
				8:		data_wr_charram <= "S";
				9:		data_wr_charram <= "c";
				10:	data_wr_charram <= "o";
				11:	data_wr_charram <= "p";
				12:	data_wr_charram <= "e";
				13:	data_wr_charram <= "F";
				14:	data_wr_charram <= "a";
				15:	data_wr_charram <= "c";
				16:	data_wr_charram <= "e";
				17:	data_wr_charram <= " ";
				18:	data_wr_charram <= "b";
				19:	data_wr_charram <= "e";
				20:	data_wr_charram <= "t";
				21:	data_wr_charram <= "a";
			endcase
			if (count > 17) begin
				data_wr_attrram <= 8'b00000111;
			end else begin
				data_wr_attrram <= 8'b00001001;
			end;
			addr_charram = 84 + count;
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_RUN_STOP;
			count <= 0;
		end;
	end;
	
	// Run/Stop status
	if (str_state == STR_PRINT_RUN_STOP) begin
		if (count < 5) begin
			if (state_runmode == 0) begin
				case (count)
					0:		data_wr_charram <= "S";
					1:		data_wr_charram <= "t";
					2:		data_wr_charram <= "o";
					3:		data_wr_charram <= "p";
					4:		data_wr_charram <= 0;
				endcase
				// Inverted Red
				data_wr_attrram <= 8'b00100001;
			end else begin
				case (count)
					0:		data_wr_charram <= 0;
					1:		data_wr_charram <= "R";
					2:		data_wr_charram <= "u";
					3:		data_wr_charram <= "n";
					4:		data_wr_charram <= 0;
				endcase
				// Inverted Green
				data_wr_attrram <= 8'b00100010;
			end;
			addr_charram = 144 + count;
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_TRIG_STATUS;
			count <= 0;
		end;
	end;
	
	// Trigger system status (Trig'd, Auto Trig'd, etc.)
	if (str_state == STR_PRINT_TRIG_STATUS) begin
		if (count < 12) begin
			if (state_runmode == 1) begin
				// Trig Wait (shows as 'Trig?')
				if (state_trig == 0) begin
					case (count)
						0:		data_wr_charram <= "T";
						1:		data_wr_charram <= "r";
						2:		data_wr_charram <= "i";
						3:		data_wr_charram <= "g";
						4:		data_wr_charram <= "?";
						5:		data_wr_charram <= 0;
					endcase
					data_wr_attrram <= 8'b11100011; // Inverted Flashing Yellow
				end
				
				// Trig Acquired (shows as Trig'd)
				if (state_trig == 1) begin
					case (count)
						0:		data_wr_charram <= "T";
						1:		data_wr_charram <= "r";
						2:		data_wr_charram <= "i";
						3:		data_wr_charram <= "g";
						4:		data_wr_charram <= "'";
						5:		data_wr_charram <= "d";
						6:		data_wr_charram <= 0;
					endcase
					data_wr_attrram <= 8'b00000010; // Green
				end
				
				// Auto Trig Acquired (shows as Auto Trig'd)
				if (state_trig == 2) begin
					case (count)
						0:		data_wr_charram <= "A";
						1:		data_wr_charram <= "u";
						2:		data_wr_charram <= "t";
						3:		data_wr_charram <= "o";
						4:		data_wr_charram <= " ";
						5:		data_wr_charram <= "T";
						6:		data_wr_charram <= "r";
						7:		data_wr_charram <= "i";
						8:		data_wr_charram <= "g";
						9:		data_wr_charram <= 0;
					endcase
					data_wr_attrram <= 8'b10111101; // Inverse Flashing Orange
				end
			end else if (trig_mode == 2) begin  // Single mode
				// If stopped show DONE after SINGLE event if we got an event,
				// otherwise, show "TRIG?"
				if (state_trig == 3) begin
					case (count)
						0:		data_wr_charram <= "D";
						1:		data_wr_charram <= "o";
						2:		data_wr_charram <= "n";
						3:		data_wr_charram <= "e";
						4:		data_wr_charram <= " ";
						5:		data_wr_charram <= "S";
						6:		data_wr_charram <= "i";
						7:		data_wr_charram <= "n";
						8:		data_wr_charram <= "g";
						9:		data_wr_charram <= "l";
						10:	data_wr_charram <= "e";
						11:	data_wr_charram <= 0;
					endcase
					data_wr_attrram <= 8'b10000010; // Flashing Green
				end else begin
					case (count)
						0:		data_wr_charram <= "T";
						1:		data_wr_charram <= "r";
						2:		data_wr_charram <= "i";
						3:		data_wr_charram <= "g";
						4:		data_wr_charram <= "?";
						5:		data_wr_charram <= 0;
					endcase
					data_wr_attrram <= 8'b11100011; // Inverted Flashing Yellow
				end;
			end;
			// Write chars to char RAM
			addr_charram = 124 + count;
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_CHAN_INFO_A;
			count <= 0;
		end;
	end;
	
	// Channel info: A
	// Compute attenuation string and scale factor
	case (ch_a_volt_idx) 
		0: begin
				// 1mV/div
				scale_y_a_mult = 102400;
				trig_incr_a = 1;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = " ";
				ch_a_volt_div_char[2] = "1";
			end
			
		1: begin
				// 2mV/div
				scale_y_a_mult = 51200;
				trig_incr_a = 2;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = " ";
				ch_a_volt_div_char[2] = "2";
			end
			
		2: begin
				// 5mV/div
				scale_y_a_mult = 20480;
				trig_incr_a = 5;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = " ";
				ch_a_volt_div_char[2] = "5";
			end
			
		3: begin
				// 10mV/div
				scale_y_a_mult = 10240;
				trig_incr_a = 10;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = "1";
				ch_a_volt_div_char[2] = "0";
			end
			
		4: begin
				// 20mV/div
				scale_y_a_mult = 5120;
				trig_incr_a = 20;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = "2";
				ch_a_volt_div_char[2] = "0";
			end
			
		5: begin
				// 50mV/div
				scale_y_a_mult = 2048;
				trig_incr_a = 50;
				ch_a_volt_div_char[0] = " ";
				ch_a_volt_div_char[1] = "5";
				ch_a_volt_div_char[2] = "0";
			end
			
		6: begin
				// 100mV/div
				scale_y_a_mult = 1024;
				trig_incr_a = 100;
				ch_a_volt_div_char[0] = "1";
				ch_a_volt_div_char[1] = "0";
				ch_a_volt_div_char[2] = "0";
			end
			
		7: begin
				// 200mV/div
				scale_y_a_mult = 512;
				trig_incr_a = 200;
				ch_a_volt_div_char[0] = "2";
				ch_a_volt_div_char[1] = "0";
				ch_a_volt_div_char[2] = "0";
			end
			
		8: begin
				// 500mV/div
				scale_y_a_mult = 204;
				trig_incr_a = 200;
				ch_a_volt_div_char[0] = "5";
				ch_a_volt_div_char[1] = "0";
				ch_a_volt_div_char[2] = "0";
			end
	endcase
	
	// Draw channel info
	if (str_state == STR_PRINT_CHAN_INFO_A) begin
		if (count < 18) begin
			case (count)
				0:		data_wr_charram <= "C";
				1:		data_wr_charram <= "h";
				2:		data_wr_charram <= "A";
				3:		data_wr_charram <= " ";
				4:		data_wr_charram <= ch_a_volt_div_char[0];
				5:		data_wr_charram <= ch_a_volt_div_char[1];
				6:		data_wr_charram <= ch_a_volt_div_char[2];
				7:		data_wr_charram <= "m";
				8:		data_wr_charram <= "V";
				9:		data_wr_charram <= "/";
				10:	data_wr_charram <= "d";
				11:	data_wr_charram <= "i";
				12:	data_wr_charram <= "v";
				13:	data_wr_charram <= " ";
				14:	data_wr_charram <= "A";
				15:	data_wr_charram <= "C";
				16:	data_wr_charram <= "~";
				17:	data_wr_charram <= 0;
			endcase
			// "ChA" is inverse, other characters regular. All chars in LtYellow.
			// If channel is disabled it goes dark grey.
			if (cha_enabled) begin
				if (count > 2) begin
					data_wr_attrram <= 8'b00001011;
				end else begin
					data_wr_attrram <= 8'b00101011;
				end;
			end else begin
				data_wr_attrram <= 8'b00011010;
			end;
			addr_charram = 2084 + count; // Bottom left corner of scope graticle plus one row
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_CHAN_INFO_B;
			count <= 0;
		end;
	end;
	
	// Channel info: B
	// Compute attenuation string and scale factor
	case (ch_b_volt_idx) 
		0: begin
				// 1mV/div
				scale_y_b_mult = 102400;
				trig_incr_b = 100;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = " ";
				ch_b_volt_div_char[2] = "1";
			end
			
		1: begin
				// 2mV/div
				scale_y_b_mult = 51200;
				trig_incr_b = 50;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = " ";
				ch_b_volt_div_char[2] = "2";
			end
			
		2: begin
				// 5mV/div
				scale_y_b_mult = 20480;
				trig_incr_b = 25;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = " ";
				ch_b_volt_div_char[2] = "5";
			end
			
		3: begin
				// 10mV/div
				scale_y_b_mult = 10240;
				trig_incr_b = 25;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = "1";
				ch_b_volt_div_char[2] = "0";
			end
			
		4: begin
				// 20mV/div
				scale_y_b_mult = 5120;
				trig_incr_b = 25;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = "2";
				ch_b_volt_div_char[2] = "0";
			end
			
		5: begin
				// 50mV/div
				scale_y_b_mult = 2048;
				trig_incr_b = 50;
				ch_b_volt_div_char[0] = " ";
				ch_b_volt_div_char[1] = "5";
				ch_b_volt_div_char[2] = "0";
			end
			
		6: begin
				// 100mV/div
				scale_y_b_mult = 1024;
				trig_incr_b = 75;
				ch_b_volt_div_char[0] = "1";
				ch_b_volt_div_char[1] = "0";
				ch_b_volt_div_char[2] = "0";
			end
			
		7: begin
				// 200mV/div
				scale_y_b_mult = 512;
				trig_incr_b = 100;
				ch_b_volt_div_char[0] = "2";
				ch_b_volt_div_char[1] = "0";
				ch_b_volt_div_char[2] = "0";
			end
			
		8: begin
				// 500mV/div
				scale_y_b_mult = 204;
				trig_incr_b = 200;
				ch_b_volt_div_char[0] = "5";
				ch_b_volt_div_char[1] = "0";
				ch_b_volt_div_char[2] = "0";
			end
	endcase
	
	if (str_state == STR_PRINT_CHAN_INFO_B) begin
		if (count < 18) begin
			case (count)
				0:		data_wr_charram <= "C";
				1:		data_wr_charram <= "h";
				2:		data_wr_charram <= "B";
				3:		data_wr_charram <= " ";
				4:		data_wr_charram <= ch_b_volt_div_char[0];
				5:		data_wr_charram <= ch_b_volt_div_char[1];
				6:		data_wr_charram <= ch_b_volt_div_char[2];
				7:		data_wr_charram <= "m";
				8:		data_wr_charram <= "V";
				9:		data_wr_charram <= "/";
				10:	data_wr_charram <= "d";
				11:	data_wr_charram <= "i";
				12:	data_wr_charram <= "v";
				13:	data_wr_charram <= " ";
				14:	data_wr_charram <= "A";
				15:	data_wr_charram <= "C";
				16:	data_wr_charram <= "~";
				17:	data_wr_charram <= 0;
			endcase
			// "ChB" is inverse, other characters regular. All chars in LtBlue.
			// If channel is disabled it goes dark grey.
			if (chb_enabled) begin
				if (count > 2) begin
					data_wr_attrram <= 8'b00011011;
				end else begin
					data_wr_attrram <= 8'b00111011;
				end;
			end else begin
				data_wr_attrram <= 8'b00011010;
			end;
			addr_charram = 2164 + count; // Below ChA
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_TIMEBASE;
			count <= 0;
		end;
	end;
	
	// Write the current timebase
	// Decode timebase and divider
	case (time_div_idx) 
		0: begin
				// 1.25us/div
				time_div_clk_divider = 0;
				time_div_char[0] = "1";
				time_div_char[1] = ".";
				time_div_char[2] = "2";
				time_div_char[3] = "5";
			end
			
		1: begin
				// 2.50us/div
				time_div_clk_divider = 1;
				time_div_char[0] = "2";
				time_div_char[1] = ".";
				time_div_char[2] = "5";
				time_div_char[3] = "0";
			end
			
		2: begin
				// 5us/div
				time_div_clk_divider = 3;
				time_div_char[0] = 0;
				time_div_char[1] = 0;
				time_div_char[2] = 0;
				time_div_char[3] = "5";
			end
			
		3: begin
				// 10us/div
				time_div_clk_divider = 7;
				time_div_char[0] = 0;
				time_div_char[1] = 0;
				time_div_char[2] = "1";
				time_div_char[3] = "0";
			end
			
		4: begin
				// 20us/div
				time_div_clk_divider = 15;
				time_div_char[0] = 0;
				time_div_char[1] = 0;
				time_div_char[2] = "2";
				time_div_char[3] = "0";
			end
			
		5: begin
				// 50us/div
				time_div_clk_divider = 31;
				time_div_char[0] = 0;
				time_div_char[1] = 0;
				time_div_char[2] = "5";
				time_div_char[3] = "0";
			end
			
		6: begin
				// 100us/div
				time_div_clk_divider = 63;
				time_div_char[0] = 0;
				time_div_char[1] = "1";
				time_div_char[2] = "0";
				time_div_char[3] = "0";
			end
	endcase 
	
	if (str_state == STR_PRINT_TIMEBASE) begin
		if (count < 15) begin
			case (count)
				0:		data_wr_charram <= "H";
				1:		data_wr_charram <= "o";
				2:		data_wr_charram <= "r";
				3:		data_wr_charram <= " ";
				4:		data_wr_charram <= time_div_char[0];
				5:		data_wr_charram <= time_div_char[1];
				6:		data_wr_charram <= time_div_char[2];
				7:		data_wr_charram <= time_div_char[3];
				8:		data_wr_charram <= 5; // micro
				9:		data_wr_charram <= "s";
				10:	data_wr_charram <= "/";
				11:	data_wr_charram <= "d";
				12:	data_wr_charram <= "i";
				13:	data_wr_charram <= "v";
				14:	data_wr_charram <= 0;
			endcase
			data_wr_attrram <= 8'b00001101; 	// HotPink
			addr_charram = 2110 + count;		// Centred below the waveform
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_TRIG_TYPE;
			count <= 0;
		end;
	end;
	
	// The type of the trigger: Rising or Falling Edge Trigger
	if (str_state == STR_PRINT_TRIG_TYPE) begin
		if (count < 20) begin
			case (count)
				0:		data_wr_charram <= 21;		// noise reject symbol 
				1:		data_wr_charram <= "N";
				2:		data_wr_charram <= "R";		
				3:		data_wr_charram <= 0;
				4:		data_wr_charram <= (trig_type != 2) ? ((trig_type != 3) ? 14 : 2) : 12;
				5:		data_wr_charram <= 0;
				6:		data_wr_charram <= "E";
				7:		data_wr_charram <= "d";
				8:		data_wr_charram <= "g";
				9:		data_wr_charram <= "e";
				10:	data_wr_charram <= 0;
				11:	data_wr_charram <= "T";
				12:	data_wr_charram <= "r";
				13:	data_wr_charram <= "i";
				14:	data_wr_charram <= "g";
				15:	data_wr_charram <= " ";
				16:	data_wr_charram <= "C";
				17:	data_wr_charram <= "h";
				18:	data_wr_charram <= "A";
				19:	data_wr_charram <= 0;
			endcase
			// If noisereject disabled, hide noise reject characters 
			if ((count < 3) && (!trig_noiserej)) begin
				data_wr_charram <= 0;
			end;
			data_wr_attrram <= 8'b00001110;
			addr_charram = 2129 + count; // Right-aligned along bottom edge of scope grid
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_TRIG_TYPE_2ND;
			count <= 0;
		end;
	end;
	
	// Second line for type of trigger (makes address increment easier
	if (str_state == STR_PRINT_TRIG_TYPE_2ND) begin
		if (count < 11) begin
			if (trig_mode == 0) begin 					// Normal trigger (No auto mode)
				case (count)
					0:		data_wr_charram <= "N";
					1:		data_wr_charram <= "o";
					2:		data_wr_charram <= "r";
					3:		data_wr_charram <= "m";
					4:		data_wr_charram <= "a";
					5:		data_wr_charram <= "l";
					6:		data_wr_charram <= 0;
				endcase
			end else if (trig_mode == 1) begin	 	// Auto trigger (Re-triggers after timeout if no trigger occurs)
				case (count)
					0:		data_wr_charram <= 0;
					1:		data_wr_charram <= 0;
					2:		data_wr_charram <= "A";
					3:		data_wr_charram <= "u";
					4:		data_wr_charram <= "t";
					5:		data_wr_charram <= "o";
					6:		data_wr_charram <= 0;
				endcase
			end else if (trig_mode == 2) begin 		// Single trigger (Stops after first trigger event)
				case (count)
					0:		data_wr_charram <= "S";
					1:		data_wr_charram <= "i";
					2:		data_wr_charram <= "n";
					3:		data_wr_charram <= "g";
					4:		data_wr_charram <= "l";
					5:		data_wr_charram <= "e";
					6:		data_wr_charram <= 0;
				endcase
			end;
			data_wr_attrram <= 8'b00000111;
			addr_charram = 2222 + count; // Below other trigger info
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_TIME;
			count <= 0;
		end;
	end;
	
	// The time since start
	// Modelled on some Tek scopes which show actual time, although we don't have an RTC
	if (str_state == STR_PRINT_TIME) begin
		if (count < 8) begin
			case (count)
				0:		data_wr_charram <= "0" + (hour_tens);
				1:		data_wr_charram <= "0" + (hour_ones);
				2:		data_wr_charram <= ":";
				3:		data_wr_charram <= "0" + (min_tens);
				4:		data_wr_charram <= "0" + (min_ones);
				5:		data_wr_charram <= ":";
				6:		data_wr_charram <= "0" + (sec_tens);
				7:		data_wr_charram <= "0" + (sec_ones);
				8:		data_wr_charram <= 0;
			endcase
			// White, but colons are set to blink at 2Hz
			if ((count == 2) || (count == 5)) begin
				data_wr_attrram <= 8'b10000111;
			end else begin
				data_wr_attrram <= 8'b00000111;
			end;
			addr_charram = 2272 + count; // Centred along bottom of display
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_DEBUG;
			count <= 0;
		end;
	end;
	
	// Print debug info (PS/2 key for now)
	if (str_state == STR_PRINT_DEBUG) begin
		if (count < 5) begin
			// Decode keyboard value into two hex digits
			case (key_data & 8'hf0) 
				8'h00: key_hexU <= "0";
				8'h10: key_hexU <= "1";
				8'h20: key_hexU <= "2";
				8'h30: key_hexU <= "3";
				8'h40: key_hexU <= "4";
				8'h50: key_hexU <= "5";
				8'h60: key_hexU <= "6";
				8'h70: key_hexU <= "7";
				8'h80: key_hexU <= "8";
				8'h90: key_hexU <= "9";
				8'ha0: key_hexU <= "a";
				8'hb0: key_hexU <= "b";
				8'hc0: key_hexU <= "c";
				8'hd0: key_hexU <= "d";
				8'he0: key_hexU <= "e";
				8'hf0: key_hexU <= "f";
			endcase
			case (key_data & 8'h0f) 
				8'h00: key_hexL <= "0";
				8'h01: key_hexL <= "1";
				8'h02: key_hexL <= "2";
				8'h03: key_hexL <= "3";
				8'h04: key_hexL <= "4";
				8'h05: key_hexL <= "5";
				8'h06: key_hexL <= "6";
				8'h07: key_hexL <= "7";
				8'h08: key_hexL <= "8";
				8'h09: key_hexL <= "9";
				8'h0a: key_hexL <= "a";
				8'h0b: key_hexL <= "b";
				8'h0c: key_hexL <= "c";
				8'h0d: key_hexL <= "d";
				8'h0e: key_hexL <= "e";
				8'h0f: key_hexL <= "f";
			endcase
			// Print hex digits plus the key skip counter
			case (count)
				0:		data_wr_charram <= key_hexU;
				1:		data_wr_charram <= key_hexL;
				2:		data_wr_charram <= " ";
				3:		data_wr_charram <= "0" + key_ready;
				4:		data_wr_charram <= 0;
			endcase
			// White, no blink
			data_wr_attrram <= 8'b00000111;
			addr_charram = 2304 + count; // Bottom edge of screen
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_CREDIT;
			count <= 0;
		end;
	end;
	
	// Print credit
	if (str_state == STR_PRINT_CREDIT) begin
		if (count < 15) begin
			// Print hex digits plus the key skip counter
			case (count)
				0:		data_wr_charram <= "(";
				1:		data_wr_charram <= "C";
				2:		data_wr_charram <= ")";
				3:		data_wr_charram <= 0;
				4:		data_wr_charram <= "2";
				5:		data_wr_charram <= "0";
				6:		data_wr_charram <= "1";
				7:		data_wr_charram <= "7";
				8:		data_wr_charram <= 0;
				9:		data_wr_charram <= "T";
				10:	data_wr_charram <= ".";
				11:	data_wr_charram <= "G"; 
				12:	data_wr_charram <= ".";
				13:	data_wr_charram <= "O";
				14:	data_wr_charram <= ".";
				15:	data_wr_charram <= 0;
			endcase
			// White, no blink
			data_wr_attrram <= 8'b00000111;
			if (count > 7) begin
				addr_charram = 302 + count; // next row, minus 7 pixels 
			end else begin
				addr_charram = 229 + count; 
			end;
			addr_attrram = addr_charram;
			count <= count + 1;
		end else begin
			str_state <= STR_PRINT_EOF;
			count <= 0;
		end;
	end;
	
	// Reset state machine
	if (str_state == STR_PRINT_EOF) begin
		str_state <= STR_PRINT_NAME;
		count <= 0;
	end;
	
	// Handle keyboard events - Only handle events every X ms to avoid bounce issues
	key_tick_ctr <= key_tick_ctr + 1;
	trig_incr <= trig_incr_a;
	
	if (key_tick_ctr == KEYBD_SCAN_CTR) begin
		key_tick_ctr <= 0;
		if (key_ready) begin
			case (key_data)
				// 'D' changes attenuation of Channel A to next highest step
				// All attenuation changes cause a re-start of acquisition, if stopped
				8'h23: begin
						if (ch_a_volt_idx < 8) begin
							ch_a_volt_idx = ch_a_volt_idx + 1;
							run_out <= 1;
						end
					end
				
				// 'C' changes attenuation of Channel A to next lowest step
				8'h21: begin
						if (ch_a_volt_idx > 0) begin
							ch_a_volt_idx = ch_a_volt_idx - 1;
							run_out <= 1;
						end
					end
				
				// 'F' changes attenuation of Channel B to next highest step
				8'h2b: begin
						if (ch_b_volt_idx < 8) begin
							ch_b_volt_idx = ch_b_volt_idx + 1;
							run_out <= 1;
						end
					end
				
				// 'V' changes attenuation of Channel B to next lowest step
				8'h2a: begin
						if (ch_b_volt_idx > 0) begin
							ch_b_volt_idx = ch_b_volt_idx - 1;
							run_out <= 1;
						end
					end
				
				// Up/Down arrow keys change horizontal divisions
				// All timebase changes cause a re-start of acquisition, if stopped
				8'h72: begin
						if (time_div_idx > 0) begin
							time_div_idx = time_div_idx - 1;
							run_out <= 1;
						end
					end
					
				8'h75: begin
						if (time_div_idx < 6) begin
							time_div_idx = time_div_idx + 1;
							run_out <= 1;
						end
					end
				
				// Tab controls RUN/STOP, CapsLock triggers SINGLE mode (TODO)
				8'h0d: begin
						// If we are STOPPED, generate a RUN signal (cleared on next clock cycle)
						if (state_runmode == 0) begin
							run_out <= 1;
						end;
						
						// If we are RUNNING, generate a STOP signal (cleared on next clock cycle)
						if (state_runmode == 1) begin
							stop_out <= 1;
						end;
					end
				
				// "E" toggles trigger edge (Rise/Fall/Both)
				8'h24: begin
						if (trig_type < 3) begin
							trig_type <= trig_type + 1;
						end else begin
							trig_type <= 1;
						end
					end
				
				// "N" toggles noise reject mode
				8'h31: begin
						trig_noiserej = !trig_noiserej;
					end
					
				// "L" toggles dot/line mode
				8'h4b: dot_mode <= !dot_mode;
				
				// "A" and "Z" control trigger level, "Q" resets to zero
				8'h1c: begin
						if (trig_lvl > trig_incr) begin
							trig_lvl <= trig_lvl - trig_incr;
						end else begin
							trig_lvl <= 1;
						end
					end
					
				8'h1a: begin
						if (trig_lvl < SCOPE_Y_MAX) begin
							trig_lvl <= trig_lvl + trig_incr;
						end else begin
							trig_lvl <= SCOPE_Y_MAX - 1;
						end
					end
					
				8'h15: begin
						trig_lvl <= SCOPE_Y_MAX / 2;
					end
					
				// "M" toggles trigger mode (Normal/Auto/Single)
				8'h3a: begin
						trig_mode <= trig_mode + 1;
						if (trig_mode == 2) begin
							trig_mode <= 0;
						end
					end
				
				// 1 and 2 are channel A and B enables
				8'h16: cha_enabled <= !cha_enabled;
				8'h1e: chb_enabled <= !chb_enabled;
			endcase
			key_ready <= 0;
		end;
	end;
	
	// Increment time counter
	sec_ctr <= sec_ctr + 1;
	if (sec_ctr == CLOCK_TICKS_PER_SEC) begin
		sec_ctr <= 0;
		// Timer is implemented as BCD. We overflow the units, then tens, then minute units, etc.
		// This avoids costly modulus operations (requiring ~500 LEs and constraining device timing.)
		sec_ones <= sec_ones + 1;
		if (sec_ones == 9) begin
			sec_ones <= 0;
			sec_tens <= sec_tens + 1;
			if (sec_tens == 5) begin
				sec_tens <= 0;
				min_ones <= min_ones + 1;
				if (min_ones == 9) begin
					min_ones <= 0;
					min_tens <= min_tens + 1;
					if (min_tens == 5) begin
						min_tens <= 0;
						hour_ones <= hour_ones + 1;
						// have to be a little smart here to handle 24
						if ((hour_tens == 2) && (hour_ones == 3)) begin
							hour_tens <= 0;
							hour_ones <= 0;
						end else if (hour_ones == 9) begin
							hour_ones <= 0;
							hour_tens <= hour_tens + 1;
						end;
					end;
				end;
			end;
		end;
	end;
	
end

// Scaled Y values
// Integer types, signed 32-bit
integer trig_lvl_int, trig_y;
integer trig_incr, trig_incr_a, trig_incr_b;
integer scale_y_a, scale_y_b;
integer wave_y_a, wave_y_b;
// Scale factors for volt/div scale (multiplied by 512)
integer scale_y_a_mult, scale_y_b_mult;

// Last Y wave value and last Y coord; used to draw lines between dots
// Current Y coord and last Y coord must match to calculate plot
integer scale_y_a_last, scale_y_b_last;
reg [9:0] last_y;

// Draw the waveform: this operates at the pixel clock because we want only one new
// sample per pixel we land on. 
always @(negedge pix_clk) begin
	
	rd_en_waveram = 0;
	r_pix_write_wave = 8'h00;
	g_pix_write_wave = 8'h00;
	b_pix_write_wave = 8'h00;
	
	// Are we in Y bounds of scope display?
	if ((pix_v >= SCOPE_SCRN_YOFF) && (pix_v < (SCOPE_SCRN_YOFF + SCOPE_SCRN_YSIZE))) begin
	
		// Are we in X bounds of scope display?
		if ((pix_h >= SCOPE_SCRN_XOFF) && (pix_h < (SCOPE_SCRN_XOFF + SCOPE_SCRN_XSIZE))) begin
			
			// Compute waveform value for this Y and the one above it (i.e. the numerical value that the 
			// waveform value would need to occupy to be drawn here)
			// Waveform is divided by 512 to simplify logic - out of range values are clipped
			// This essentially simplifies to reading only the upper 8 bits of memory in the RAM..
			// If we implement automatic measurements then we need to use the full 14 bits, but the display
			// only utilises 8 bits.
			wave_y_value = (((pix_v - SCOPE_SCRN_YOFF) * 16384) / SCOPE_SCRN_YSIZE_WAVE) + SCOPE_WAVE_OFFSET;
			wave_y_value_next = (((pix_v + 1 - SCOPE_SCRN_YOFF) * 16384) / SCOPE_SCRN_YSIZE_WAVE) + SCOPE_WAVE_OFFSET;

			// Compute the address to read from RAM for this X
			// Upper 512 samples ignored for now - could be used to implement basic post-trigger
			wave_x_addr = (pix_h - SCOPE_SCRN_XOFF);
			
			// Drive the read and test the pixel
			addr_waveram_a = wave_x_addr;
			addr_waveram_b = wave_x_addr;
			rd_en_waveram = 1;
			
			// Scale the Y values according to the attenuation (and later, the offset)
			// Scale factors are multiplied by 1024x to make attenuation and gain possible
			wave_y_a = data_rd_waveram_a; // Implicit cast to signed integer
			wave_y_b = data_rd_waveram_b;
			scale_y_a = (((wave_y_a - SCOPE_Y_MID + ADC_OFFSET_CHA) * scale_y_a_mult) >>> 9) + SCOPE_Y_MID;
			scale_y_b = (((wave_y_b - SCOPE_Y_MID + ADC_OFFSET_CHB) * scale_y_b_mult) >>> 9) + SCOPE_Y_MID;
			
			if (scale_y_a >= SCOPE_Y_MAX_DISP) begin
				scale_y_a = SCOPE_Y_MAX_DISP - 1;
			end;
			if (scale_y_a <= SCOPE_Y_MIN_DISP) begin
				scale_y_a = SCOPE_Y_MIN_DISP + 1;
			end;
			if (scale_y_b >= SCOPE_Y_MAX_DISP) begin
				scale_y_b = SCOPE_Y_MAX_DISP - 1;
			end;
			if (scale_y_b <= SCOPE_Y_MIN_DISP) begin
				scale_y_b = SCOPE_Y_MIN_DISP + 1;
			end;
			
			if (cha_enabled) begin
				// Draw lines between dots if not in dot mode and last Y is same as this Y, 
				// and the X is more than two pixels into the screen
				if ((dot_mode) && (last_y == pix_v) && ((pix_h - SCOPE_SCRN_XOFF) > 2)) begin
					// Lines down: drawn from last Y value to next
					if (((SCOPE_Y_MAX - scale_y_a_last) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_a) <= wave_y_value)) begin
						// Draw the pixel: darker yellow for channel A line
						r_pix_write_wave = 200;
						g_pix_write_wave = 200;
						b_pix_write_wave = 50;
					end
					
					// Lines up: drawn from next Y value to last
					if (((SCOPE_Y_MAX - scale_y_a) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_a_last) <= wave_y_value)) begin
						// Draw the pixel: darker yellow for channel A line
						r_pix_write_wave = 200;
						g_pix_write_wave = 200;
						b_pix_write_wave = 50;
					end
				end
				
				if (((SCOPE_Y_MAX - scale_y_a) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_a) <= wave_y_value_next)) begin
					// Draw the pixel: yellow for channel A
					r_pix_write_wave = r_pix_write_wave | 255;
					g_pix_write_wave = g_pix_write_wave | 255;
					b_pix_write_wave = b_pix_write_wave | 127;
				end
			end
			
			if (chb_enabled) begin
				// Draw lines between dots
				if ((dot_mode) && (last_y == pix_v) && ((pix_h - SCOPE_SCRN_XOFF) > 1)) begin
					// Lines down: drawn from last Y value to next
					if (((SCOPE_Y_MAX - scale_y_b_last) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_b) <= wave_y_value)) begin
						// Draw the pixel: darker blue for channel A line
						r_pix_write_wave = 50;
						g_pix_write_wave = 50;
						b_pix_write_wave = 200;
					end
					
					// Lines up: drawn from next Y value to last
					if (((SCOPE_Y_MAX - scale_y_b) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_b_last) <= wave_y_value)) begin
						// Draw the pixel: darker yellow for channel A line
						r_pix_write_wave = 50;
						g_pix_write_wave = 50;
						b_pix_write_wave = 200;
					end
				end
				
				if (((SCOPE_Y_MAX - scale_y_b) > wave_y_value) && ((SCOPE_Y_MAX - scale_y_b) <= wave_y_value_next)) begin
					// Draw the pixel: blue for channel B
					r_pix_write_wave = 127;
					g_pix_write_wave = 200;
					b_pix_write_wave = 255;
				end
			end
			
			// Draw trigger level as orange line, overlaying trace
			trig_lvl_int = trig_lvl;
			trig_y = (((trig_lvl_int - SCOPE_Y_MID) * scale_y_a_mult) >>> 9) + SCOPE_Y_MID;
			
			if ((trig_y > wave_y_value) && (trig_y <= wave_y_value_next)) begin
				r_pix_write_wave = r_pix_write_wave | 255;
				g_pix_write_wave = g_pix_write_wave | 127;
				b_pix_write_wave = b_pix_write_wave | 63;
			end
			
			// Store the last data packet and the last display Y value
			scale_y_a_last = scale_y_a;
			scale_y_b_last = scale_y_b;
			last_y = pix_v;
			
		end
	
	end

end

endmodule
