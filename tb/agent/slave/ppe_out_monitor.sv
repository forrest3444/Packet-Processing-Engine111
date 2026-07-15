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
    bit [1:0] start_lane;

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
        int unsigned valid_count;
        int unsigned index;
        bit [1:0] lane;

        @(posedge vif.rst_n);
        start_lane = 2'd0;
        forever begin
            @(posedge vif.clk);
            valid_count = vif.out_valid0 + vif.out_valid1 +
                          vif.out_valid2 + vif.out_valid3;
            for (index = 0; index < valid_count; index++) begin
                lane = start_lane + index[1:0];
                case (lane)
                    2'd0: sample_lane(lane, vif.out_valid0, vif.out_packet0);
                    2'd1: sample_lane(lane, vif.out_valid1, vif.out_packet1);
                    2'd2: sample_lane(lane, vif.out_valid2, vif.out_packet2);
                    default: sample_lane(lane, vif.out_valid3, vif.out_packet3);
                endcase
            end
            start_lane += valid_count[1:0];
        end
    endtask

    task sample_lane(bit [1:0] lane, bit valid, bit [PACKET_W-1:0] packet);
        ppe_out_item item;
        if (valid) begin
            item = ppe_out_item::type_id::create("item");
            item.lane = lane;
            item.packet = packet;
            out_ap.write(item);
        end else begin
            `uvm_error("OUT_HOLE", $sformatf("missing output at logical lane %0d", lane))
        end
    endtask
endclass

`endif
