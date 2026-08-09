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

        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            vif.in_valid[lane]  <= tr.valid[lane];
            vif.in_packet[lane] <= tr.packet[lane];
            vif.in_desc[lane]   <= tr.desc[lane];
        end

        do begin
            @(posedge vif.clk);
        end while (vif.bkps);
        vif.clear_inputs();
    endtask

endclass

`endif
