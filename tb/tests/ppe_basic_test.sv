// -----------------------------------------------------------------------------
// File       : ppe_basic_test.sv
// Author     : Codex
// Description: PPE basic UVM smoke test.
// -----------------------------------------------------------------------------

`ifndef PPE_BASIC_TEST_SV
`define PPE_BASIC_TEST_SV

class ppe_basic_test extends uvm_test;
    `uvm_component_utils(ppe_basic_test)

    ppe_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        ppe_basic_seq seq;

        phase.raise_objection(this);
        seq = ppe_basic_seq::type_id::create("seq");
        seq.start(env.master_agent.seqr);
        #1000ns;
        phase.drop_objection(this);
    endtask
endclass

`endif
