// -----------------------------------------------------------------------------
// FE fixed-latency, multi-inflight pipeline test using the shared UVM top.
// -----------------------------------------------------------------------------

`ifndef PPE_FE_PIPELINE_TEST_SV
`define PPE_FE_PIPELINE_TEST_SV

class ppe_fe_pipeline_test extends uvm_test;
    `uvm_component_utils(ppe_fe_pipeline_test)

    ppe_vif_t vif;
    int unsigned cycle_count;
    int unsigned request_count;
    int unsigned response_count;
    int unsigned due_cycle_q[$];
    bit [127:0] expected_data_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_fe_pipeline_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        int unsigned index;

        phase.raise_objection(this);
        vif.fe_probe_in_valid = 1'b0;
        @(posedge vif.rst_n);

        // Four requests are simultaneously in flight; later inputs overlap outputs.
        for (index = 0; index < 8; index++) begin
            drive_cycle(1'b1, 2'd3, index);
        end
        repeat (5) drive_cycle(1'b0, 2'd0, 0);

        // Exercise exact 1/2/3/4-cycle latency mappings without output collisions.
        drive_cycle(1'b1, 2'd0, 105);
        drive_cycle(1'b1, 2'd1, 101);
        drive_cycle(1'b1, 2'd2, 102);
        drive_cycle(1'b1, 2'd3, 103);
        repeat (5) drive_cycle(1'b0, 2'd0, 0);

        if ((request_count != 12) || (response_count != 12) ||
            (due_cycle_q.size() != 0) || (expected_data_q.size() != 0)) begin
            `uvm_error("FE_COUNT", $sformatf(
                "requests=%0d responses=%0d due_pending=%0d data_pending=%0d",
                request_count, response_count, due_cycle_q.size(),
                expected_data_q.size()))
        end
        phase.drop_objection(this);
    endtask

    task drive_cycle(bit valid, bit [1:0] delay, int unsigned index);
        bit [127:0] packet;
        bit [127:0] dependency;
        bit [127:0] vip_data_in;

        @(negedge vif.clk);
        packet = make_data(index);
        dependency = make_dependency(index);
        vif.fe_probe_in_valid = valid;
        vif.fe_probe_in_data = packet;
        vif.fe_probe_dep_valid = valid && index[0];
        vif.fe_probe_dep_data = dependency;
        vif.fe_probe_delay = delay;

        @(posedge vif.clk);
        cycle_count++;
        check_output();
        if (valid) begin
            vip_data_in = packet ^ (index[0] ? dependency : 128'b0);
            due_cycle_q.push_back(cycle_count + delay + 1);
            expected_data_q.push_back(ppe_fe_vip::predict(vip_data_in, delay));
            request_count++;
        end
    endtask

    task check_output();
        bit expected_valid;
        bit [127:0] expected;

        expected_valid = (due_cycle_q.size() != 0) &&
                         (due_cycle_q[0] == cycle_count);
        if (vif.fe_probe_out_valid !== expected_valid) begin
            `uvm_error("FE_VALID", $sformatf(
                "cycle=%0d got_valid=%0b expected_valid=%0b",
                cycle_count, vif.fe_probe_out_valid, expected_valid))
        end
        if (expected_valid) begin
            due_cycle_q.pop_front();
            expected = expected_data_q.pop_front();
            if (vif.fe_probe_out_data !== expected) begin
                `uvm_error("FE_DATA", $sformatf("cycle=%0d data mismatch",
                                                cycle_count))
            end
            response_count++;
        end
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
