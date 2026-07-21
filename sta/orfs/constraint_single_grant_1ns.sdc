set clk_period 1.000
set io_delay 0.200
set clk_uncertainty 0.050

create_clock -name core_clock -period $clk_period [get_ports clk_i]
create_clock -name io_clock -period $clk_period

set_clock_uncertainty $clk_uncertainty [get_clocks core_clock]
set_clock_uncertainty $clk_uncertainty [get_clocks io_clock]

set_input_delay $io_delay -clock io_clock \
    [get_ports {rst_ni candidate_valid_i candidate_seq_tag_i \
                legal_fe_mask_i class_rr_ptr_i fe_rr_ptr_i}]
set_output_delay $io_delay -clock io_clock \
    [get_ports {grant_valid_o grant_seq_tag_o grant_class_o grant_fe_o}]

set_false_path -from [get_ports rst_ni]
