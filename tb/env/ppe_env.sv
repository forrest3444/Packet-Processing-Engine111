// -----------------------------------------------------------------------------
// File       : ppe_env.sv
// Author     : Codex
// Description: PPE minimal UVM environment.
// -----------------------------------------------------------------------------

`ifndef PPE_ENV_SV
`define PPE_ENV_SV

class ppe_env extends uvm_env;
    `uvm_component_utils(ppe_env)

    ppe_master_agent master_agent;
    ppe_slave_agent  slave_agent;
    ppe_scoreboard   scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_agent = ppe_master_agent::type_id::create("master_agent", this);
        slave_agent  = ppe_slave_agent::type_id::create("slave_agent", this);
        scb          = ppe_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        master_agent.mon.ap.connect(scb.in_imp);
        slave_agent.mon.out_ap.connect(scb.out_imp);
    endfunction
endclass

`endif
