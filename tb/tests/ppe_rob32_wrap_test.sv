//------------------------------------------------------------------------------
// ROB32 full-occupancy and tag-wrap test.
//------------------------------------------------------------------------------

`ifndef PPE_ROB32_WRAP_TEST_SV
`define PPE_ROB32_WRAP_TEST_SV

class ppe_rob32_wrap_test extends uvm_test;
    `uvm_component_utils(ppe_rob32_wrap_test)

    localparam int unsigned PACKET_COUNT   = 128;
    localparam int unsigned TIMEOUT_CYCLES = 5000;

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned occupancy_peak;
    int unsigned retired_count;
    bit          saw_tag_max;
    bit          saw_tag_wrap;
    bit          completed;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_rob32_wrap_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_rob32_wrap_seq seq;

        phase.raise_objection(this);
        seq = ppe_rob32_wrap_seq::type_id::create("seq");
        fork
            seq.start(env.master_agent.seqr);
            monitor_progress();
        join

        @(negedge vif.clk);
        if (!completed) begin
            `uvm_error("ROB32_TIMEOUT", $sformatf(
                "retired=%0d expected=%0d", retired_count, PACKET_COUNT))
        end
        if (occupancy_peak != 32) begin
            `uvm_error("ROB32_OCC", $sformatf(
                "peak occupancy=%0d expected=32", occupancy_peak))
        end
        if (!saw_tag_wrap) begin
            `uvm_error("ROB32_WRAP", "did not observe completion tag 63 -> 0")
        end
        if ((env.scb.exp_total != PACKET_COUNT)
            || (env.scb.got_total != PACKET_COUNT)) begin
            `uvm_error("ROB32_SCOREBOARD", $sformatf(
                "expected=%0d received=%0d", env.scb.exp_total,
                env.scb.got_total))
        end

        `uvm_info("ROB32_METRIC", $sformatf(
            "packets=%0d occupancy_peak=%0d tag_wrap=%0b",
            PACKET_COUNT, occupancy_peak, saw_tag_wrap), UVM_NONE)
        phase.drop_objection(this);
    endtask

    task monitor_progress();
        repeat (TIMEOUT_CYCLES) begin
            @(posedge vif.clk);
            if (vif.dbg_rob_occupancy > occupancy_peak) begin
                occupancy_peak = vif.dbg_rob_occupancy;
            end

            for (int unsigned fe = 0; fe < TB_N; fe++) begin
                if (vif.dbg_wb_valid[fe]) begin
                    if (vif.dbg_wb_seq_tag[fe*TB_SEQ_W +: TB_SEQ_W]
                        == {TB_SEQ_W{1'b1}}) begin
                        saw_tag_max = 1'b1;
                    end
                    if (saw_tag_max
                        && (vif.dbg_wb_seq_tag[fe*TB_SEQ_W +: TB_SEQ_W]
                            == '0)) begin
                        saw_tag_wrap = 1'b1;
                    end
                end
            end

            retired_count += count_n(vif.out_valid);
            if (retired_count >= PACKET_COUNT) begin
                completed = 1'b1;
                break;
            end
        end
    endtask

    function int unsigned count_n(bit [TB_N-1:0] value);
        count_n = 0;
        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            count_n += value[lane];
        end
    endfunction

endclass

`endif
