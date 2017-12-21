// Attribute generator RAM for character generator
// Stores the character attributes used by the character blitter
//
// Implemented as a ~2.4K 8-bit dual port RAM
//
// Attribute layout:
//    BBIccccc
//
// 	BB = Blink rate 		(00=always on, 01=1Hz, 10=2Hz, 11=4Hz)
//  	 I = Inverse colours (0 = not inverse, 1 = inverse)
// ccccc = Colour value, passed to vga_colour module to determine R/G/B of foreground
//
// (C) Thomas Oldbury 2017

module vga_attrram(
	// PORT A
	clk_a, 			// clock, negedge triggered
	addr_a,	 		// address
	wr_en_a, 		// write enable
	data_wr_a,		// data write in
	
	// PORT B
	clk_b, 			// clock, negedge triggered
	addr_b,	 		// address
	data_rd_b		// data read out
);

parameter n_entries = 2400;
parameter bit_width = 8;
parameter addr_width = 12;

// port A and B i/o
input [bit_width - 1:0] data_wr_a;
input [addr_width - 1:0] addr_a;
input clk_a, wr_en_a;

output reg [bit_width - 1:0] data_rd_b;
input [addr_width - 1:0] addr_b;
input clk_b;

// memory block - should be inferred by FPGA compiler as blockram
reg [bit_width-1:0] addr_blockram[n_entries - 1:0];

// PORT A write on clk_a falling edge if write_en enabled
always @(negedge clk_a) begin

	if (wr_en_a == 1) begin
		// write data to blockram
		addr_blockram[addr_a] <= data_wr_a;
	end

end

// PORT B read on clk_b falling edge
always @(negedge clk_b) begin

	// read data from blockram
	data_rd_b <= addr_blockram[addr_b];

end

endmodule
