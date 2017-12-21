// -- Definitions --
module adc_clock_gen (
	clkin,
	reset,
	enable,
	divider,
	clkout
);

// Source clock input (50MHz)
input clkin;

// Enable: a low drives clock low, high enables clock
input enable;

// Reset: active high
input reset;

// Divider, sets time base & sample rate. Can divide 50MHz clock down by 2^23 to reach ~2SPS (~20s/div).
// Minimum divider value is 0, which divides input clock by 2.
input [23:0] divider;

// Output clock
output reg clkout;

// Internal state machine
reg [23:0] counter;
reg state;

// -- Functional Implementation --
always @(posedge clkin or posedge reset)
begin

	if (reset) begin
		counter = 0;
	end else begin
		clkout <= state & enable;
		if (counter == divider) begin
			counter = 0;
			state <= ~state;
		end else begin
			counter = counter + 1;
		end;
	end

end

endmodule
