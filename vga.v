// VGA sync/pixel controller for oscilloscope 
//
// VGA resolution is 640 x 480 @ 60Hz
//
// (C) Thomas Oldbury 2017

module vga(
	inclk, h_sync, v_sync,
	out_r, out_g, out_b, blankn, syncn, outclk,
	// interface ports
	pix_h, pix_v, drvclk,
	r_pix_write_bus, 
	g_pix_write_bus,
	b_pix_write_bus,
	frame_counter
);

// States that our sync (H or V) state machines can occupy
parameter SYNC = 0;
parameter BACKPORCH = 1;
parameter ACTIVE = 2;
parameter FRONTPORCH = 3;

// Parameters below from with some adjustments:
//  http://martin.hinner.info/vga/timing.html

// This VGA module generates a 640x480 pixel, 60Hz display
// It's not perfect - the pixel clock is 25MHz instead of 25.175MHz
// But it's close enough that monitors should be ok with it

// Parameters relative to pixel clock counter 
// Cumulative timings, point at which to switch to next state
parameter vga_h_sync_pulse = 94;
parameter vga_h_back_porch = 145;
parameter vga_h_pixels = 784;
parameter vga_h_front_porch = 805;

// Parameters relative to line counter 
// Cumulative timings, point at which to switch to next state
parameter vga_v_sync_pulse = 3;
parameter vga_v_back_porch = 33;
parameter vga_v_rows = 512;
parameter vga_v_front_porch = 530;

// Divided clock source
output reg drvclk;

// State machine for horizontal and vertical
reg [1:0] state_h;
reg [1:0] state_v;

// Counters for tracking the horizontal and vertical state transitions
reg [9:0] ctr_h;
reg [9:0] ctr_v; 

// Pixel addresses if in ACTIVE state (undefined if not in ACTIVE state)
output reg [9:0] pix_h; 
output reg [9:0] pix_v;

// Frame counter, increments per frame, 32 bit (overflow ~2.2 years)
output reg [31:0] frame_counter;

// Tristate "bus" to write data to, pixels are OR'd with each other
// to produce the correct value for each pixel seen on the display
// This is a port input to the VGA controller
input wire [7:0] r_pix_write_bus;
input wire [7:0] g_pix_write_bus;
input wire [7:0] b_pix_write_bus;

// DAC clock enable (TODO: toggle during active state to reduce power consumption)
reg clken;

// Inputs to the module
input inclk;

// VGA output signals, 8-bit RGB plus blanking, clock and sync-on-green signal (always low)
output reg h_sync, v_sync;
output reg blankn, syncn;
output wire outclk;
output reg [7:0] out_r;
output reg [7:0] out_g;
output reg [7:0] out_b;

assign outclk = drvclk & clken;

// Scope screen parameters
parameter SCOPE_SCRN_XOFF = 32;
parameter SCOPE_SCRN_YOFF = 32;
parameter SCOPE_SCRN_XSIZE	= 512;
parameter SCOPE_SCRN_YSIZE	= 384;
parameter SCOPE_V_GRATICLES = 12;
parameter SCOPE_H_GRATICLES = 16;
parameter SCOPE_GRAT_SIZE = 32;

// Divide inclk by two to get 25MHz reference pixel clock
always @(negedge inclk) begin
	drvclk <= !drvclk;
end

// On negative edge of drvclk update state or counters. Video
// generation is also handled here.
always @(negedge drvclk) begin

	// syncN is always low as we do not use sync-on-green
	syncn <= 0;
	
	// default states for our registers
	clken <= 1;
	h_sync <= 1;
	
	// blank outputs during blank
	if (blankn == 0) begin
		out_r <= 0;
		out_g <= 0;
		out_b <= 0;
	end else begin
		// commit pixels
		out_r <= (r_pix_write_bus);
		out_g <= (g_pix_write_bus);
		out_b <= (b_pix_write_bus);
	end
	
	// handle HSYNC pulse generation
	if (state_h == SYNC) begin
		blankn <= 0;
		h_sync <= 0;
		ctr_h <= ctr_h + 1;
		// jump to next state?
		if (ctr_h > vga_h_sync_pulse) begin
			state_h <= BACKPORCH;
		end
	end
	
	if (state_h == BACKPORCH) begin
		blankn <= 0;
		ctr_h <= ctr_h + 1;
		if (ctr_h > vga_h_back_porch) begin
			state_h <= ACTIVE;
		end
	end
	
	if (state_h == ACTIVE) begin
		// unblank video if in ACTIVE region of vertical scan
		if (state_v == ACTIVE) begin
			blankn <= 1;
		end
		
		// wait for state transitition
		ctr_h <= ctr_h + 1;
		pix_h <= pix_h + 1;
		if (ctr_h > vga_h_pixels) begin
			state_h <= FRONTPORCH;
		end
	end
	
	// on front porch transition to sync increment vertical counter
	if (state_h == FRONTPORCH) begin
		ctr_h <= ctr_h + 1;
		
		// Blank output to generate correct sync signal
		blankn <= 0;
		out_r <= 0;
		out_g <= 0;
		out_b <= 0;
		
		// wait for overflow to reset back to SYNC
		if (ctr_h > vga_h_front_porch) begin
			state_h <= SYNC;
			ctr_h <= 0;
			pix_h <= 0;
		end else begin
			ctr_h <= ctr_h + 1;
		end
	end
	
	// handle VSYNC generation at beginning of HSYNC field
	// VSYNC should remain in the same state throughout a full line
	if (ctr_h == 0) begin
		// increment v counter
		ctr_v <= ctr_v + 1;
		
		if (state_v == SYNC) begin
			v_sync <= 0;
			// jump to next state?
			if (ctr_v > vga_v_sync_pulse) begin
				state_v <= BACKPORCH;
			end
		end
		
		if (state_v == BACKPORCH) begin
			v_sync <= 1;
			if (ctr_v > vga_v_back_porch) begin
				state_v <= ACTIVE;
			end
		end
		
		if (state_v == ACTIVE) begin
			v_sync <= 1;
			pix_v <= pix_v + 1;
			if (ctr_v > vga_v_rows) begin
				state_v <= FRONTPORCH;
			end
		end
		
		// handle V frontporch; resets state machine and zeros row counter
		if (state_v == FRONTPORCH) begin
			v_sync <= 1;
			if (ctr_v > vga_v_front_porch) begin
				state_v <= SYNC;
				ctr_v <= 0;
				pix_v <= 0;
				frame_counter <= frame_counter + 1;
			end
		end
	end
	
end

endmodule
