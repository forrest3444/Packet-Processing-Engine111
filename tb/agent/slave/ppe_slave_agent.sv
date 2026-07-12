// -----------------------------------------------------------------------------
// File       : ppe_slave_agent.sv
// Author     : Codex
// Description: PPE passive slave agent.
// -----------------------------------------------------------------------------

`ifndef PPE_SLAVE_AGENT_SV
`define PPE_SLAVE_AGENT_SV

class ppe_slave_agent extends uvm_agent;
    `uvm_component_utils(ppe_slave_agent)

    ppe_out_monitor mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = ppe_out_monitor::type_id::create("mon", this);
    endfunction
endclass

`endif
