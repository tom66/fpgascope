// VGA vertical line module
//
// This module generates pixels that are part of a vertical line defined by x and y0, y1.
// Colour and a dash factor can also be specified.
//
// (C) Thomas Oldbury 2017

module vga_vline(
	xin, yin,
	x, y0, y1, 
	colour,
	dot_mode,	// 0 = solid, 1 = dots every 4th pixel (graticle), 2 = dashes 8 pixels on, 8 pixels off (dashed
	writeout_r, writeout_g, writeout_b
);

// Inputs
input [9:0] xin;			// current x - connect to pix_x
input [9:0] yin;			// current y - connect to pix_y
input [9:0] x;				// geometry extent x
input [9:0] y0;			// geometry extent y1
input [9:0] y1;			// geometry extent y1
input [1:0] dot_mode;	// dotmode 0-2
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

// Fully async logic.
// At 25MHz pixel clock, our logic timings aren't too tight...
always @(*) begin

	// if w/in bounds & colour not transparent writeout the colour
	if ((yin >= y0) && (yin <= y1) && (x == xin)) begin
		if (cm) begin
			case (dot_mode)
				2'b00: begin
					writeout_r = col_r_gen;
					writeout_g = col_g_gen;
					writeout_b = col_b_gen;
				end
					
				2'b01: begin
					// every 4th pixel written
					if ((yin & 3) == 0) begin
						writeout_r = col_r_gen;
						writeout_g = col_g_gen;
						writeout_b = col_b_gen;
					end else begin
						writeout_r = 8'bZZZZZZZZ;
						writeout_g = 8'bZZZZZZZZ;
						writeout_b = 8'bZZZZZZZZ;
					end
				end
					
				2'b10: begin
					// every 8 pixels written
					if ((yin & 8'h08) == 0) begin
						writeout_r = col_r_gen;
						writeout_g = col_g_gen;
						writeout_b = col_b_gen;
					end else begin
						writeout_r = 8'bZZZZZZZZ;
						writeout_g = 8'bZZZZZZZZ;
						writeout_b = 8'bZZZZZZZZ;
					end
				end
			endcase
		end else begin
			writeout_r = 8'bZZZZZZZZ;
			writeout_g = 8'bZZZZZZZZ;
			writeout_b = 8'bZZZZZZZZ;
		end
	end else begin
		writeout_r = 8'bZZZZZZZZ;
		writeout_g = 8'bZZZZZZZZ;
		writeout_b = 8'bZZZZZZZZ;
	end 

end

endmodule
