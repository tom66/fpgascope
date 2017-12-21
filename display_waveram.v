// Display waveform memory: 1024 sample dual port memory
//
// This infers a dual port block RAM on the FPGA fabric, if done right
//
// (C) Thomas Oldbury 2017

module display_waveram(
	// PORT A
	clk_a, 			// clock, negedge triggered
	addr_a,	 		// address
	wr_en_a, 		// write enable
	rd_en_a, 		// read enable (unused)
	data_rd_a,		// data read out
	data_wr_a,		// data write in
	
	// PORT B
	clk_b, 			// clock, negedge triggered
	addr_b,	 		// address
	wr_en_b, 		// write enable
	rd_en_b, 		// read enable (unused)
	data_rd_b,		// data read out
	data_wr_b		// data write in
);

parameter n_entries = 1024;
parameter bit_width = 14;

// port A and B i/o
output reg [bit_width - 1:0] data_rd_a;
input [bit_width - 1:0] data_wr_a;
input [bit_width - 1:0] addr_a;
input clk_a, wr_en_a, rd_en_a;

output reg [bit_width - 1:0] data_rd_b;
input [bit_width - 1:0] data_wr_b;
input [bit_width - 1:0] addr_b;
input clk_b, wr_en_b, rd_en_b;

// memory block - should be inferred by FPGA compiler as blockram
reg [bit_width-1:0] wave_blockram[n_entries - 1:0];

// PORT A read/write on clk_a falling edge
always @(negedge clk_a) begin

	if (wr_en_a == 1) begin
		// write data to blockram
		wave_blockram[addr_a] <= data_wr_a;
		data_rd_a <= 0;
	end else begin
		// read data from blockram
		data_rd_a <= wave_blockram[addr_a];
	end;

end

// PORT B read/write on clk_b falling edge
always @(negedge clk_b) begin

	if (wr_en_b == 1) begin
		// write data to blockram
		wave_blockram[addr_b] <= data_wr_b;
		data_rd_b <= 0;
	end else begin
		// read data from blockram
		data_rd_b <= wave_blockram[addr_b];
	end;

end

endmodule
