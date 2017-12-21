/*
*	comparator.v
*	created: 29/03/2017
*	By: Sam Leitch, modifications by Tom Oldbury
*	Description: Basic comparator module, takes in data from adc and compares
*					 it to reference voltage. To be used in trigger functions.
*/



module comparator (

	input clkIn,
	input[13:0] threshold,
	input[13:0] hysteresis,
	input[13:0] adc_data,
	output reg q,
	output reg z	// output in dead zone

);


	always @(posedge clkIn) begin

		if (adc_data > (threshold + hysteresis)) begin
		
			q <= 1;
			z <= 0;
		
		end
		
		else if (adc_data < (threshold - hysteresis)) begin
		
			q <= 0;
			z <= 0;
		
		end 
		
		else begin
		
			z <= 1;
		
		end;
	
	end


endmodule
