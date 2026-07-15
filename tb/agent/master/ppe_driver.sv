// -----------------------------------------------------------------------------
// File       : ppe_driver.sv
// Author     : Codex
// Description: PPE master input driver.
// -----------------------------------------------------------------------------

`ifndef PPE_DRIVER_SV
`define PPE_DRIVER_SV

class ppe_driver extends uvm_driver #(ppe_item);
    `uvm_component_utils(ppe_driver)

    ppe_vif_t vif;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_driver cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_item tr;

        vif.clear_inputs();
        @(posedge vif.rst_n);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(tr);
            drive_item(tr);
            seq_item_port.item_done();
        end
    endtask

    task drive_item(ppe_item tr);
        wait (!vif.bkps);

        vif.in_valid0  <= tr.valid[0];
        vif.in_packet0 <= tr.packet[0];
        vif.in_desc0   <= tr.desc[0];
        vif.in_valid1  <= tr.valid[1];
        vif.in_packet1 <= tr.packet[1];
        vif.in_desc1   <= tr.desc[1];
        vif.in_valid2  <= tr.valid[2];
        vif.in_packet2 <= tr.packet[2];
        vif.in_desc2   <= tr.desc[2];
        vif.in_valid3  <= tr.valid[3];
        vif.in_packet3 <= tr.packet[3];
        vif.in_desc3   <= tr.desc[3];

        do begin
            @(posedge vif.clk);
        end while (vif.bkps);
        vif.clear_inputs();
    endtask

endclass

`endif
