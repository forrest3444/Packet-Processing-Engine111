//------------------------------------------------------------------------------
// FE probe stimulus sequence.
//
// Drives the standalone FE probe through its virtual interface. All response
// observation and pass/fail checking remain in ppe_fe_pipeline_test.
//------------------------------------------------------------------------------

`ifndef PPE_FE_PIPELINE_SEQ_SV
`define PPE_FE_PIPELINE_SEQ_SV

class ppe_fe_pipeline_seq extends uvm_sequence;
    `uvm_object_utils(ppe_fe_pipeline_seq)

    ppe_vif_t vif;
    bit       done;

    function new(string name = "ppe_fe_pipeline_seq");
        super.new(name);
    endfunction

    task body();
        done = 1'b0;
        if (vif == null) begin
            `uvm_fatal("NOVIF", "ppe_fe_pipeline_seq requires vif")
        end

        vif.fe_probe_in_valid = 1'b0;
        @(posedge vif.rst_n);

        // Four-cycle requests overlap in flight and with prior outputs.
        for (int unsigned index = 0; index < 8; index++) begin
            drive_cycle(1'b1, 2'd3, index);
        end
        repeat (5) drive_cycle(1'b0, 2'd0, 0);

        // Exercise exact 1/2/3/4-cycle mappings without return collisions.
        drive_cycle(1'b1, 2'd0, 105);
        drive_cycle(1'b1, 2'd1, 101);
        drive_cycle(1'b1, 2'd2, 102);
        drive_cycle(1'b1, 2'd3, 103);
        repeat (5) drive_cycle(1'b0, 2'd0, 0);

        @(negedge vif.clk);
        vif.fe_probe_in_valid = 1'b0;
        done = 1'b1;
    endtask

    task drive_cycle(bit valid, bit [1:0] delay, int unsigned index);
        @(negedge vif.clk);
        vif.fe_probe_in_valid = valid;
        vif.fe_probe_in_data = make_data(index);
        vif.fe_probe_dep_valid = valid && index[0];
        vif.fe_probe_dep_data = make_dependency(index);
        vif.fe_probe_delay = delay;
        @(posedge vif.clk);
    endtask

    function bit [127:0] make_data(bit [31:0] index);
        make_data = {32'hfe00_0000 ^ index, 32'h1234_0000 + index,
                     32'h5678_0000 ^ (index << 1), index};
    endfunction

    function bit [127:0] make_dependency(bit [31:0] index);
        make_dependency = {32'h0bad_0000 + index, 32'hcafe_0000 ^ index,
                           32'h55aa_0000 + index, 32'ha5a5_0000 ^ index};
    endfunction

endclass

`endif
