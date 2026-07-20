//------------------------------------------------------------------------------
// FE fixed-latency, multi-inflight pipeline test using the shared UVM top.
// Stimulus is owned by ppe_fe_pipeline_seq; this test only observes and checks.
//------------------------------------------------------------------------------

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
        ppe_fe_pipeline_seq seq;

        phase.raise_objection(this);
        seq = ppe_fe_pipeline_seq::type_id::create("seq");
        seq.vif = vif;

        fork
            seq.start(null);
            monitor_pipeline(seq);
        join

        if ((request_count != 12) || (response_count != 12) ||
            (due_cycle_q.size() != 0) || (expected_data_q.size() != 0)) begin
            `uvm_error("FE_COUNT", $sformatf(
                "requests=%0d responses=%0d due_pending=%0d data_pending=%0d",
                request_count, response_count, due_cycle_q.size(),
                expected_data_q.size()))
        end
        phase.drop_objection(this);
    endtask

    task monitor_pipeline(ppe_fe_pipeline_seq seq);
        bit [127:0] vip_data_in;

        @(posedge vif.rst_n);
        forever begin
            @(posedge vif.clk);
            cycle_count++;
            check_output();

            if (vif.fe_probe_in_valid) begin
                vip_data_in = vif.fe_probe_in_data ^
                              (vif.fe_probe_dep_valid
                               ? vif.fe_probe_dep_data : 128'b0);
                due_cycle_q.push_back(
                    cycle_count + vif.fe_probe_delay + 1);
                expected_data_q.push_back(
                    ppe_fe_vip::predict(vip_data_in, vif.fe_probe_delay));
                request_count++;
            end

            if (seq.done && (due_cycle_q.size() == 0)) begin
                break;
            end
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
                `uvm_error("FE_DATA", $sformatf(
                    "cycle=%0d data mismatch", cycle_count))
            end
            response_count++;
        end
    endtask

endclass

`endif
