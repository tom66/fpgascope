// VGA rectangle module
//
// This module generates pixels that represent the outline of a rectangle
// Coords of x0,y0 representing top left and x1,y1 representing bottom right 
// should be provided.
//
// Dot mode not implemented (mode always 00) due to edge artefacts and to 
// simplify the logic chain.
//
// (C) Thomas Oldbury 2017

module vga_rectangle(
	xin, yin,
	x0, x1, y0, y1, 
	colour,
	writeout_r, writeout_g, writeout_b
);

// Inputs
input [9:0] xin;			// current x - connect to pix_x
input [9:0] yin;			// current y - connect to pix_y
input [9:0] x0;			// geometry extent x0
input [9:0] y0;			// geometry extent y0
input [9:0] x1;			// geometry extent x1
input [9:0] y1;			// geometry extent y1
input [4:0] colour;		// colour input - passed to a vga_colour instance

// Outputs
output reg [7:0] writeout_r;
output reg [7:0] writeout_g;
output reg [7:0] writeout_b;

// Colour demux logic.
wire [7:0] col_r_gen;
wire [7:0] col_g_gen;
wire [7:0] col_b_gen;
wire cm;

vga_colour vgacol0(
	.cin(colour),
	.cout_r(col_r_gen),
	.cout_g(col_g_gen),
	.cout_b(col_b_gen),
	.c_mask(cm)
);

always @(*) begin

	writeout_r = 8'bZZZZZZZZ; 
	writeout_g = 8'bZZZZZZZZ; 
	writeout_b = 8'bZZZZZZZZ; 
	
	if ((xin >= x0) && (xin <= x1) && ((yin == y0) || (yin == y1))) begin
		if (cm) begin
			writeout_r = col_r_gen;
			writeout_g = col_g_gen;
			writeout_b = col_b_gen;
		end
	end 
	
	if ((yin >= y0) && (yin <= y1) && ((xin == x0) || (xin == x1))) begin
		if (cm) begin
			writeout_r = col_r_gen;
			writeout_g = col_g_gen;
			writeout_b = col_b_gen;
		end
	end 
	
end

endmodule
