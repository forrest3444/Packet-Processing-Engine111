// -----------------------------------------------------------------------------
// File       : ppe_test_base.sv
// Description: Common UVM test ownership and scoreboard drain handling.
// -----------------------------------------------------------------------------

`ifndef PPE_TEST_BASE_SV
`define PPE_TEST_BASE_SV

class ppe_test_base extends uvm_test;
    `uvm_component_utils(ppe_test_base)

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned drain_timeout_cycles;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        drain_timeout_cycles = 200000;
    endfunction

    function void build_phase(uvm_phase phase);
        int requested_timeout;

        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_test_base cannot get vif")
        end
        if ($value$plusargs("PPE_DRAIN_TIMEOUT=%d", requested_timeout)) begin
            if (requested_timeout <= 0) begin
                `uvm_fatal("TEST_CONFIG", $sformatf(
                    "PPE_DRAIN_TIMEOUT=%0d must be positive",
                    requested_timeout))
            end
            drain_timeout_cycles = requested_timeout;
        end
    endfunction

    virtual function ppe_seq_base create_sequence();
        return null;
    endfunction

    virtual task run_phase(uvm_phase phase);
        ppe_seq_base seq;

        seq = create_sequence();
        if (seq == null) begin
            `uvm_fatal("NO_SEQUENCE", "derived test did not create a sequence")
        end

        phase.raise_objection(this);
        seq.start(env.master_agent.seqr);
        wait_for_drain(seq);
        @(negedge vif.clk);
        check_sequence_results(seq);
        phase.drop_objection(this);
    endtask

    virtual task wait_for_drain(ppe_seq_base seq);
        bit drained;

        drained = 1'b0;
        for (int unsigned cycle = 0; cycle < drain_timeout_cycles; cycle++) begin
            @(posedge vif.clk);
            if ((env.scb.exp_total == seq.generated_packet_count)
                && (env.scb.got_total == env.scb.exp_total)
                && (env.scb.expected_q.size() == 0)) begin
                drained = 1'b1;
                break;
            end
        end
        if (!drained) begin
            `uvm_error("DRAIN_TIMEOUT", $sformatf(
                "generated=%0d expected=%0d received=%0d pending=%0d",
                seq.generated_packet_count, env.scb.exp_total,
                env.scb.got_total, env.scb.expected_q.size()))
        end
    endtask

    virtual function void check_sequence_results(ppe_seq_base seq);
        if (env.scb.exp_total != seq.generated_packet_count) begin
            `uvm_error("SEQ_COUNT", $sformatf(
                "scoreboard expected=%0d generated=%0d",
                env.scb.exp_total, seq.generated_packet_count))
        end
        if (env.scb.got_total != seq.generated_packet_count) begin
            `uvm_error("SEQ_OUTPUT", $sformatf(
                "scoreboard received=%0d generated=%0d",
                env.scb.got_total, seq.generated_packet_count))
        end
        if (env.scb.expected_q.size() != 0) begin
            `uvm_error("SEQ_PENDING", $sformatf(
                "scoreboard pending=%0d", env.scb.expected_q.size()))
        end
    endfunction
endclass

`endif
