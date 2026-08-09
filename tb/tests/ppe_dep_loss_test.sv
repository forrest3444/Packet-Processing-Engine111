// -----------------------------------------------------------------------------
// Checks dependency wakeup and retirement-only authoritative history updates.
// -----------------------------------------------------------------------------

`ifndef PPE_DEP_LOSS_TEST_SV
`define PPE_DEP_LOSS_TEST_SV

class ppe_dep_loss_test extends uvm_test;
    `uvm_component_utils(ppe_dep_loss_test)

    localparam bit [2:0] ST_WAIT_DEP = 3'd2;

    ppe_env   env;
    ppe_vif_t vif;
    bit       wait_seen;
    bit       s0_wakeup_seen;
    bit       s0_history_seen;
    bit       s8_completion_seen;
    bit       s8_completion_preserved_history;
    bit       s8_retire_history_seen;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_dep_loss_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_dep_loss_seq seq;
        bit completed;

        phase.raise_objection(this);
        seq = ppe_dep_loss_seq::type_id::create("seq");

        fork
            seq.start(env.master_agent.seqr);
            begin
                repeat (300) begin
                    @(negedge vif.clk);
                    sample_risk_window();
                    if (env.scb.got_total == 9) begin
                        completed = 1'b1;
                        break;
                    end
                end
            end
        join

        if (!completed) begin
            `uvm_error("DEP_TIMEOUT", $sformatf(
                "nine expected packets did not complete: got=%0d state1=%0d history0_tag=%0d rob0=%0b:%0d result0=%0b:%0d head=%0d",
                env.scb.got_total, vif.dbg_entry1_state,
                vif.dbg_cache0_seq_tag, vif.dbg_rob0_valid,
                vif.dbg_rob0_seq_tag, vif.dbg_result0_valid,
                vif.dbg_result0_seq_tag, vif.dbg_head_ptr))
        end
        if (!wait_seen) begin
            `uvm_error("DEP_SETUP", "S1 never entered WAIT_DEP")
        end
        if (!s0_wakeup_seen) begin
            `uvm_error("DEP_WAKE", "S0 writeback did not broadcast to a waiting S1")
        end
        if (!s0_history_seen) begin
            `uvm_error("DEP_HISTORY", "S0 retirement did not populate history bank 0")
        end
        if (!s8_completion_seen || !s8_completion_preserved_history) begin
            `uvm_error("DEP_HISTORY", "S8 completion overwrote history before retirement")
        end
        if (!s8_retire_history_seen) begin
            `uvm_error("DEP_HISTORY", "S8 retirement did not update history bank 0")
        end
        phase.drop_objection(this);
    endtask

    task sample_risk_window();
        int fe;

        if (vif.dbg_entry1_state == ST_WAIT_DEP) begin
            if (!wait_seen) begin
                `uvm_info("DEP_TRACE", "S1 entered WAIT_DEP", UVM_MEDIUM)
            end
            wait_seen = 1'b1;
        end
        for (fe = 0; fe < TB_N; fe++) begin
            if (vif.dbg_wb_valid[fe] &&
                (vif.dbg_wb_seq_tag[fe*TB_SEQ_W +: TB_SEQ_W] == '0)
                && wait_seen) begin
                if (!s0_wakeup_seen) begin
                    `uvm_info("DEP_TRACE", $sformatf(
                        "S0 writeback broadcast while cache0 tag=%0d state1=%0d",
                        vif.dbg_cache0_seq_tag, vif.dbg_entry1_state), UVM_MEDIUM)
                end
                s0_wakeup_seen = 1'b1;
            end
            if (vif.dbg_wb_valid[fe] &&
                (vif.dbg_wb_seq_tag[fe*TB_SEQ_W +: TB_SEQ_W]
                 == TB_SEQ_W'(8)) && s0_wakeup_seen) begin
                if (!s8_completion_seen) begin
                    `uvm_info("DEP_TRACE", $sformatf(
                        "S8 completed while history0 tag=%0d state1=%0d",
                        vif.dbg_cache0_seq_tag,
                        vif.dbg_entry1_state), UVM_MEDIUM)
                end
                s8_completion_seen = 1'b1;
                // S0 may not have retired yet. Both an invalid bank and a
                // valid S0 tag are legal; S8's completion must not install S8.
                if (!vif.dbg_cache0_valid
                    || (vif.dbg_cache0_seq_tag != TB_SEQ_W'(8))) begin
                    s8_completion_preserved_history = 1'b1;
                end
            end
        end
        if (vif.dbg_cache0_valid && (vif.dbg_cache0_seq_tag == '0)) begin
            s0_history_seen = 1'b1;
        end
        if (s8_completion_seen && vif.dbg_cache0_valid
            && (vif.dbg_cache0_seq_tag == TB_SEQ_W'(8))) begin
            s8_retire_history_seen = 1'b1;
        end
    endtask
endclass

`endif
