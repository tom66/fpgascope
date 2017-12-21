// FPGAscope
//
// Main entry point (hey, this isn't C!)
//
// (C) Thomas Oldbury 2017

// -- Definitions --
module main (
	clkin,
	clkout_a,
	clkout_b,
	adcoen_a,
	adcoen_b,
	adc_data_a,
	adc_data_b,
	led_comp_test,
	debug_led_out,
	vga_h_sync,
	vga_v_sync,
	vga_blankn,
	vga_syncn,
	vga_dacclk,
	vga_rout,
	vga_gout,
	vga_bout,
	ps2_dat_in,
	ps2_clk_in
);

wire clkout; // XXX: used? (eliminate?)

// Module I/O
input clkin;
output clkout_a;
output clkout_b;
output adcoen_a;
output adcoen_b;
input [13:0] adc_data_a;
input [13:0] adc_data_b;
output [7:0] debug_led_out;
output led_comp_test;

// VGA real world signals (routed directly from VGA module)
output vga_h_sync, vga_v_sync;
output vga_syncn, vga_blankn;
output vga_dacclk;
output [7:0] vga_rout;
output [7:0] vga_gout;
output [7:0] vga_bout;

// VGA controller signals
wire vga_pixclk;
wire [31:0] vga_frame;
wire [9:0] vga_x;
wire [9:0] vga_y;
wire [7:0] vga_r_bus;
wire [7:0] vga_g_bus;
wire [7:0] vga_b_bus;

// Character generator nets
wire [7:0] vga_r_bus_char;
wire [7:0] vga_g_bus_char;
wire [7:0] vga_b_bus_char;
wire [7:0] vga_r_bus_graphics;
wire [7:0] vga_g_bus_graphics;
wire [7:0] vga_b_bus_graphics;

assign vga_r_bus = vga_r_bus_char | vga_r_bus_graphics;
assign vga_g_bus = vga_g_bus_char | vga_g_bus_graphics;
assign vga_b_bus = vga_b_bus_char | vga_b_bus_graphics;

// Character RAM nets
wire [11:0] charram_addr_a;
wire [11:0] charram_addr_b;
wire [6:0] charram_data_a_write;
wire [6:0] charram_data_b_read;
wire charram_write_en;
wire [11:0] attrram_addr_a;
wire [11:0] attrram_addr_b;
wire [6:0] attrram_data_a_write;
wire [6:0] attrram_data_b_read;
wire attrram_write_en;

// Waveform RAM registers and signals
wire clkacq;
wire [11:0] sample_ram_addr_a_acq;
wire [11:0] sample_ram_addr_b_acq;
wire [11:0] sample_ram_addr_a_disp;
wire [11:0] sample_ram_addr_b_disp;
wire sample_ram_wr_acq;
wire sample_ram_rd_disp;
wire [13:0] sample_ram_dataout_a_disp;
wire [13:0] sample_ram_dataout_b_disp;
wire [13:0] sample_ram_datain_a_acq;
wire [13:0] sample_ram_datain_b_acq;

// PS/2 interface
input ps2_dat_in;
input ps2_clk_in;

// Nets between modules
wire state_runmode;
wire [2:0] state_trig;
wire run_sig;
wire stop_sig;
wire [1:0] trig_mode;
wire [15:0] trig_lvl;
wire [2:0] trig_type;		// 1 = positive, 2 = negative, 3 = both
wire [7:0] acq_divider;
wire trig_noiserej;

// Debug output
assign debug_led_out = debug_led;

// -- Module Implementations --

adc_control actrl0 (
	// Clock control interface
	.clkin(clkin),
	.divider_acq_clk(acq_divider),
	// run/stop signals hard wired
	.run_in(run_sig),
	.stop_in(stop_sig),
	// Debug outputs
	//.debug_led(debug_led_out),
	// acquisition system state
	.state_runmode(state_runmode),					
	.state_trig(state_trig),	
	// trigger settings (Edge trigger only)
	.trig_mode(trig_mode),
	.trig_type(trig_type),
	.trig_lvl(trig_lvl),
	.trig_noiserej(trig_noiserej), 
	// ADC interface
	.adcoen_a(adcoen_a),
	.adcoen_b(adcoen_b),
	.adc_unlatched_data_a(adc_data_a),
	.adc_unlatched_data_b(adc_data_b),
	.adc_clkout_a(clkout_a),
	.adc_clkout_b(clkout_b),
	// RAM interface for channel A and B
	.clk_ramout(clkacq),
	.addr_ramout_a(sample_ram_addr_a_acq),
	.addr_ramout_b(sample_ram_addr_b_acq),
	.wr_en_ramout(sample_ram_wr_acq),
	.data_wr_ramout_a(sample_ram_datain_a_acq),
	.data_wr_ramout_b(sample_ram_datain_b_acq)
);

// Test comparator
comparator testcomp0 (
	.clkIn(clkin),
	.threshold(8192),
	.hysteresis(300),
	.adc_data(adc_data_a),
	.q(led_comp_test)
);

// VGA controller
vga vga0(
	// clock reference
	.inclk(clkin),
	// signals to real world
	.h_sync(vga_h_sync),
	.v_sync(vga_v_sync),
	.out_r(vga_rout), 
	.out_g(vga_gout), 
	.out_b(vga_bout), 
	.blankn(vga_blankn), 
	.syncn(vga_syncn),
	.outclk(vga_dacclk),
	.drvclk(vga_pixclk),
	// bus interface
	.pix_h(vga_x),
	.pix_v(vga_y),
	.r_pix_write_bus(vga_r_bus),
	.g_pix_write_bus(vga_g_bus),
	.b_pix_write_bus(vga_b_bus),
	.frame_counter(vga_frame)
);

// VGA character RAM for character generator
// Dual port RAM with one write port and one read port
vga_charram vga_charram0(
	// PORT A
	.clk_a(clkin),
	.addr_a(charram_addr_a),
	.wr_en_a(charram_write_en),
	.data_wr_a(charram_data_a_write),
	// PORT B
	.clk_b(clkin),
	.addr_b(charram_addr_b),
	.data_rd_b(charram_data_b_read)
);

vga_attrram vga_attrram0(
	// PORT A
	.clk_a(clkin),
	.addr_a(attrram_addr_a),
	.wr_en_a(attrram_write_en),
	.data_wr_a(attrram_data_a_write),
	// PORT B
	.clk_b(clkin),
	.addr_b(attrram_addr_b),
	.data_rd_b(attrram_data_b_read)
);

vga_chargen vga_chargen0(
	// clock reference
	.clk_in(clkin),
	// bus interface
	.vga_x(vga_x),
	.vga_y(vga_y),
	.charout_r(vga_r_bus_char),
	.charout_g(vga_g_bus_char),
	.charout_b(vga_b_bus_char),
	// RAM interface
	.addr_charram(charram_addr_b),
	.data_charram(charram_data_b_read),
	.addr_attrram(attrram_addr_b),
	.data_attrram(attrram_data_b_read)
);

// Oscilloscope display controller
display_ctrl oscope_disp_ctrl(	
	// Main clock
	.clk_main(clkin),
	// Oscilloscope acq system state
	.state_runmode(state_runmode),					
	.state_trig(state_trig),	
	// Oscilloscope control signals
	.run_out(run_sig),
	.stop_out(stop_sig),
	.trig_mode(trig_mode),
	.trig_type(trig_type),
	.trig_lvl(trig_lvl),
	.trig_noiserej(trig_noiserej),
	.time_div_clk_divider(acq_divider),
	// debug state
	.debug_led(debug_led),
	// PS/2 interface (connect to PS2_DAT and PS2_CLK)
	.dat_keyboard(ps2_dat_in),
	.clk_keyboard(ps2_clk_in),
	// VGA controller interface (including pixel clock)
	.pix_h(vga_x),
	.pix_v(vga_y),
	.pix_clk(vga_pixclk),
	.r_pix_write_bus(vga_r_bus_graphics),
	.g_pix_write_bus(vga_g_bus_graphics),
	.b_pix_write_bus(vga_b_bus_graphics),
	// Wave RAM interface
	.clk_ram(clkin),
	.addr_waveram_a(sample_ram_addr_a_disp),
	.addr_waveram_b(sample_ram_addr_b_disp),
	.rd_en_waveram(sample_ram_rd_disp),
	.data_rd_waveram_a(sample_ram_dataout_a_disp),
	.data_rd_waveram_b(sample_ram_dataout_b_disp),
	.frame_counter(vga_frame),
	// Character RAM interface
	.addr_charram(charram_addr_a),
	.wr_en_charram(charram_write_en),
	.data_wr_charram(charram_data_a_write),
	// Attribute RAM interface
	.addr_attrram(attrram_addr_a),
	.wr_en_attrram(attrram_write_en),
	.data_wr_attrram(attrram_data_a_write)
);

// Buffered display acquisition memory for waveform
// Updated by the acquisition controller after a trigger, so we should
// see a continuous waveform where possible.
// Implemented as dual port RAM on the FPGA fabric

display_waveram buff_waveA (
	// Port A: acquisition write only
	.clk_a(clkin),
	.addr_a(sample_ram_addr_a_acq),
	.wr_en_a(sample_ram_wr_acq),
	.rd_en_a(0),
	.data_wr_a(sample_ram_datain_a_acq),
	
	// Port B: display read only
	.clk_b(clkin),
	.addr_b(sample_ram_addr_a_disp),
	.wr_en_b(0),
	.rd_en_b(sample_ram_rd_disp),
	.data_rd_b(sample_ram_dataout_a_disp)
);

display_waveram buff_waveB (
	// Port A: acquisition write only
	.clk_a(clkin),
	.addr_a(sample_ram_addr_b_acq),
	.wr_en_a(sample_ram_wr_acq),
	.rd_en_a(0),
	.data_wr_a(sample_ram_datain_b_acq),
	
	// Port B: display read only
	.clk_b(clkin),
	.addr_b(sample_ram_addr_b_disp),
	.wr_en_b(0),
	.rd_en_b(sample_ram_rd_disp),
	.data_rd_b(sample_ram_dataout_b_disp)
);

endmodule
