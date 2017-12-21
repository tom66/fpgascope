/*
*	edge_Trig.v
*	created: 29/03/2017
*	By: Sam Leitch  
*	Description: Edge trigger using comparator
*
*/

module edge_Trig(

	input clkIn,
	input[13:0] trigLvl,
	input[13:0] adc_data,
	input[13:0] trigHyst,
	input[2:0]	type,
	input			enable,
	output reg q

);


	wire compEvent;
	wire qStore;
	reg  qStorePos;
	reg  qStoreNeg;
	wire deadZone;

	comparator triggerComp (
	
		.clkIn(clkIn),
		.threshold(trigLvl),
		.hysteresis(trigHyst),
		.adc_data(adc_data),
		.q(compEvent),
		.z(deadZone),
	
	);
	
	initial begin
		qStorePos <= 0;
		qStoreNeg <= 0;
	end
	
	assign qStore = qStorePos | qStoreNeg;
	
	always @(posedge compEvent) begin	
		
		if ((type == 3'd1 || type == 3'd3)) begin //trigger on positive edge or any edge
			
			qStorePos <= 1 & enable;
			
		end
		
	end
	
	
	always @(negedge compEvent) begin
	
		if ((type == 3'd2 || type == 3'd3)) begin //trigger on negative edge or any edge
		
			qStoreNeg <= 1 & enable;
		
		end

	end
	
	//or(qStore,qStorePos,qStoreNeg);
	
	
	always @(posedge clkIn) begin
	
		if (type == 3'd0) begin		//Never trigger
		
			q = 0;
		
		end
		
		else if (type == 3'd4) begin	//always Trigger
		
			q = 1;
		
		end
		
		else begin
			
			// only if trigger outside of hysteresis range
			if (deadZone == 0) begin
				q = qStore;
			end
		
		end
	
	end
	
endmodule
