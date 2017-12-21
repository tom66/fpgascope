// Character generator
//
// Interfaces with VGA module to control display
//
// An external BlockRAM is implemented to store characters; they should be written there
//
// (C) Thomas Oldbury 2017

module vga_chargen(
	// main clock
	clk_in,
	// vga interface
	vga_x, vga_y,
	charout_r, charout_g, charout_b,
	// character RAM interface (80x30 8-bit table of characters, 
	// stored in column-row format)
	// characters are read by this module and written by other modules
	addr_charram,
	data_charram,
	// attribute RAM interface - addresses are identical
	// attributes are read by this module and written by other modules
	addr_attrram,
	data_attrram
);

parameter CHAR_W = 8;
parameter CHAR_H = 16;
parameter CHAR_NUM_COLS = 80;
parameter BLINK_4HZ_DIV = 2500000;

// Clock input: character generator uses RAM and ROM, so needs a clock
input clk_in;

// VGA control inputs
input [9:0] vga_x;		// current x - connect to pix_x
input [9:0] vga_y;		// current y - connect to pix_y

// Video drive bus: OR with final output
output reg [7:0] charout_r;
output reg [7:0] charout_g;
output reg [7:0] charout_b;

// Character RAM interface 
output reg [11:0] addr_charram;
input [6:0] data_charram;
// Attribute RAM interface
output reg [11:0] addr_attrram;
input [7:0] data_attrram;

// Blink counter and outputs
reg [25:0] blink_ctr;
reg blink_4hz;
reg blink_2hz;
reg blink_1hz;
reg blink_mux;

// Local state
reg [6:0] char;
reg [3:0] col;
reg [4:0] row;
reg [7:0] mask;
wire [7:0] pix_data;
reg [4:0] colour_bits;
reg [7:0] fg_red;
reg [7:0] fg_green;
reg [7:0] fg_blue;
reg [7:0] bg_red;
reg [7:0] bg_green;
reg [7:0] bg_blue;

// Colour demux logic.
wire [7:0] col_r_gen;
wire [7:0] col_g_gen;
wire [7:0] col_b_gen;
wire cm;

// Character ROM
vga_charrom charrom (
	.char(char), 
	.row(row), 
	.outport(pix_data)
);

// Colour generator
vga_colour vgacol0(
	.cin(colour_bits),
	.cout_r(col_r_gen),
	.cout_g(col_g_gen),
	.cout_b(col_b_gen),
	.c_mask(cm)
);

always @(negedge clk_in) begin

	// Generate 4Hz, 2Hz and 1Hz blink sources
	blink_ctr <= blink_ctr + 1;
	
	if (blink_ctr == BLINK_4HZ_DIV) begin
		blink_ctr <= 0;
		blink_4hz = !blink_4hz;
		if (blink_4hz == 0) begin
			blink_2hz = !blink_2hz;
			if (blink_2hz == 0) begin
				blink_1hz = !blink_1hz;
			end;
		end;
	end;

	// Compute which character the current pixel refers to
	// and read this character from the ROM and get the pixel line
	addr_charram = ((vga_x / CHAR_W) + ((vga_y / CHAR_H) * CHAR_NUM_COLS));
	addr_attrram = addr_charram;
	
	// Determine the foreground and background colours to use
	colour_bits = data_attrram & 8'h1f;
	
	// Decode this address into a character and load that character from the char rom
	char <= data_charram;
	col = vga_x & (CHAR_W - 1);
	row = vga_y & (CHAR_H - 1);
	mask = 8'h80 >> (col - 1);
	
	// Decode blink mode bits to generate blink mask
	case (data_attrram & 8'b11000000)
		8'b00000000: blink_mux = 1;
		8'b01000000: blink_mux = blink_1hz;
		8'b10000000: blink_mux = blink_2hz;
		8'b11000000: blink_mux = blink_4hz;
	endcase
		
	// Do we draw the pixels?
	if ((cm) && (char != 0)) begin
		// Decode foreground and background colours according to inverse bit
		// Inverse bit flips foreground and background drawing
		if (data_attrram & 8'b00100000) begin
			if (blink_mux) begin
				fg_red = 0;
				fg_green = 0;
				fg_blue = 0;
				bg_red = col_r_gen;
				bg_green = col_g_gen;
				bg_blue = col_b_gen;
			end else begin
				fg_red = col_r_gen;
				fg_green = col_g_gen;
				fg_blue = col_b_gen;
				bg_red = 0;
				bg_green = 0;
				bg_blue = 0;
			end
		end else begin
			if (blink_mux) begin
				fg_red = col_r_gen;
				fg_green = col_g_gen;
				fg_blue = col_b_gen;
				bg_red = 0;
				bg_green = 0;
				bg_blue = 0;
			end else begin
				fg_red = 0;
				fg_green = 0;
				fg_blue = 0;
				bg_red = 0;
				bg_green = 0;
				bg_blue = 0;
			end
		end
	
		// Plot the pixel
		if (pix_data & mask) begin
			charout_r = fg_red;
			charout_g = fg_green;
			charout_b = fg_blue;
		end else begin
			charout_r = bg_red;
			charout_g = bg_green;
			charout_b = bg_blue;
		end
	end else begin
		charout_r = 0;
		charout_g = 0;
		charout_b = 0;
	end
	
end

endmodule

