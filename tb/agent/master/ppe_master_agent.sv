// -----------------------------------------------------------------------------
// File       : ppe_master_agent.sv
// Author     : Codex
// Description: PPE active master agent.
// -----------------------------------------------------------------------------

`ifndef PPE_MASTER_AGENT_SV
`define PPE_MASTER_AGENT_SV

class ppe_master_agent extends uvm_agent;
    `uvm_component_utils(ppe_master_agent)

    uvm_sequencer #(ppe_item) seqr;
    ppe_driver               drv;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = uvm_sequencer #(ppe_item)::type_id::create("seqr", this);
        drv  = ppe_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass

`endif
