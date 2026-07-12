// -----------------------------------------------------------------------------
// File       : ppe_out_monitor.sv
// Author     : Codex
// Description: PPE slave output monitor.
// -----------------------------------------------------------------------------

`ifndef PPE_OUT_MONITOR_SV
`define PPE_OUT_MONITOR_SV

class ppe_out_monitor extends uvm_component;
    `uvm_component_utils(ppe_out_monitor)

    ppe_vif_t vif;
    uvm_analysis_port #(ppe_out_item) out_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        out_ap = new("out_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_out_monitor cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);
        forever begin
            @(posedge vif.clk);
            sample_lane(2'd0, vif.out_valid0, vif.out_packet0);
            sample_lane(2'd1, vif.out_valid1, vif.out_packet1);
            sample_lane(2'd2, vif.out_valid2, vif.out_packet2);
            sample_lane(2'd3, vif.out_valid3, vif.out_packet3);
        end
    endtask

    task sample_lane(bit [1:0] lane, bit valid, bit [PACKET_W-1:0] packet);
        ppe_out_item item;
        if (valid) begin
            item = ppe_out_item::type_id::create("item");
            item.lane = lane;
            item.seq  = packet[31:0];
            out_ap.write(item);
        end
    endtask
endclass

`endif
