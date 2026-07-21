set clk_period 3.333
set io_delay 0.200
set clk_uncertainty 0.050

create_clock -name core_clock -period $clk_period [get_ports clk_i]
create_clock -name io_clock -period $clk_period

set_clock_uncertainty $clk_uncertainty [get_clocks core_clock]
set_clock_uncertainty $clk_uncertainty [get_clocks io_clock]

set_input_delay $io_delay -clock io_clock \
    [get_ports {rst_ni valid_i operand_a_i operand_b_i}]
set_output_delay $io_delay -clock io_clock \
    [get_ports {product_valid_o product_o}]

set_false_path -from [get_ports rst_ni]
