// -----------------------------------------------------------------------------
// PPE accepted-input monitor.
// -----------------------------------------------------------------------------

`ifndef PPE_IN_MONITOR_SV
`define PPE_IN_MONITOR_SV

class ppe_in_monitor extends uvm_component;
    `uvm_component_utils(ppe_in_monitor)

    ppe_vif_t vif;
    uvm_analysis_port #(ppe_item) ap;
    int unsigned accepted_batches;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_in_monitor cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_item tr;

        accepted_batches = 0;
        forever begin
            @(posedge vif.clk or negedge vif.rst_n);
            if (!vif.rst_n) begin
                accepted_batches = 0;
            end else if (!vif.bkps && (|vif.in_valid)) begin
                tr = ppe_item::type_id::create(
                    $sformatf("accepted_batch_%0d", accepted_batches));
                for (int unsigned lane = 0; lane < TB_N; lane++) begin
                    tr.valid[lane]  = vif.in_valid[lane];
                    tr.packet[lane] = vif.in_packet[lane];
                    tr.desc[lane]   = vif.in_desc[lane];
                    tr.seq[lane]    = '0;
                end
                accepted_batches++;
                ap.write(tr);
            end
        end
    endtask
endclass

`endif
