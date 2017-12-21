// VGA colour demultiplexer module (5-bit colour value to 24-bit RGB)
//
// (C) Thomas Oldbury 2017

module vga_colour(
	cin,
	cout_r, cout_g, cout_b, c_mask
);

// Inputs
input [4:0] cin;

// Outputs
output reg [7:0] cout_r;
output reg [7:0] cout_g;
output reg [7:0] cout_b;
output reg c_mask;				// bit set to indicate that the colour is the transparent key (10000)

// Multiplexer - async logic
always @(*) begin

	cout_r = 0;
	cout_g = 0;
	cout_b = 0;
	c_mask = 1;

	case(cin)
	
		// First block of colours is ordered to make synthesising somewhat simpler
		// as logic should essentially reduce into a load of AND and OR gates
		// Colours are encoded 00BGR, e.g. yellow is 00011
		
		// 00000: black (not implemented - default state)
		
		// 00001: red
		5'b00001: cout_r = 255;
		
		// 00010: green
		5'b00010: cout_g = 255;
		
		// 00011: blue
		5'b00100: cout_b = 255;
		
		// 00011: yellow
		5'b00011: begin
			cout_r = 255;
			cout_g = 255;
			end
		
		// 00101: magneta
		5'b00101: begin
			cout_r = 255;
			cout_b = 255;
			end
		
		// 00110: cyan
		5'b00110: begin
			cout_g = 255;
			cout_b = 255;
			end
		
		// 00111: white
		5'b00111: begin
			cout_r = 255;
			cout_g = 255;
			cout_b = 255;
			end
		
		// Second block of colours are encoded in a similar fashion
		// 01 = lighter colour (mix white) with 01BGR encoding remaining colours
		
		// 01000: midgrey (50%)
		5'b01000: begin
			cout_r = 127;
			cout_g = 127;
			cout_b = 127;
			end
	
		// 01001: lightred / salmon
		5'b01001: begin
			cout_r = 255;
			cout_g = 127;
			cout_b = 127;
			end
	
		// 01010: lightgreen / mint
		5'b01010: begin
			cout_r = 127;
			cout_g = 255;
			cout_b = 127;
			end
	
		// 01100: purple
		5'b01100: begin
			cout_r = 127;
			cout_g = 127;
			cout_b = 255;
			end
	
		// 01101: hotpink
		5'b01101: begin
			cout_r = 255;
			cout_g = 127;
			cout_b = 255;
			end
	
		// 01011: lightyellow
		5'b01011: begin
			cout_r = 255;
			cout_g = 255;
			cout_b = 127;
			end
	
		// 01110: lightcyan
		5'b01110: begin
			cout_r = 127;
			cout_g = 255;
			cout_b = 255;
			end
	
		// 01111: white (duplicate for synthesis simplicity)
		5'b01111: begin
			cout_r = 255;
			cout_g = 255;
			cout_b = 255;
			end
		
		// Third block of colours are encoded in a similar fashion
		// 10 = darker colour (mix black) with 10RGB encoding remaining colours
		5'b10000: begin
			cout_r = 0;
			cout_g = 0;
			cout_b = 0;
			end
		
		// 10001: darkred / bloodred
		5'b10001: begin
			cout_r = 127;
			cout_g = 0;
			cout_b = 0;
			end
		
		// 10010: darkgreen / emerald
		5'b10010: begin
			cout_r = 0;
			cout_g = 127;
			cout_b = 0;
			end
		
		// 10100: darkblue / navy
		5'b10100: begin
			cout_r = 0;
			cout_g = 0;
			cout_b = 127;
			end
	
		// Special colours follow: likely to be implemented using special LUTs or slightly more
		// complex logic
		// 11000: Transparency mask, signals that no colour be rendered at the current
		// pixel (OR with zero)
		5'b11000: begin
			cout_r = 0;
			cout_g = 0;
			cout_b = 0;
			c_mask = 0;
			end
		
		// 11001: darkest grey (6.25%)
		5'b11001: begin
			cout_r = 15;
			cout_g = 15;
			cout_b = 15;
			end
		
		// 11010: darker grey (12.5%)
		5'b11010: begin
			cout_r = 31;
			cout_g = 31;
			cout_b = 31;
			end
		
		// 11011: lightblue (for channel selection)
		5'b11011: begin
			cout_r = 127;
			cout_g = 200;
			cout_b = 255;
			end
		
		// 11100: mid-dark grey (37.5%)
		5'b11100: begin
			cout_r = 95;
			cout_g = 95;
			cout_b = 95;
			end
	
		// 11101: orange
		5'b11101: begin
			cout_r = 255;
			cout_g = 127;
			cout_b = 63;
			end

		// 11111: white (duplicate for synthesis simplicity)
		5'b11111: begin
			cout_r = 255;
			cout_g = 255;
			cout_b = 255;
			end
		
		// Default colours render to black
		default: begin
			cout_r = 0;
			cout_g = 0;
			cout_b = 0;
			end
		
	endcase
	
end

endmodule
