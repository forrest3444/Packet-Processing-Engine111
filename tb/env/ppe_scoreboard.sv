// -----------------------------------------------------------------------------
// File       : ppe_scoreboard.sv
// Author     : Codex
// Description: Minimal PPE scoreboard.
// -----------------------------------------------------------------------------

`ifndef PPE_SCOREBOARD_SV
`define PPE_SCOREBOARD_SV

`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_out)

class ppe_scoreboard extends uvm_component;
    `uvm_component_utils(ppe_scoreboard)

    uvm_analysis_imp_exp #(ppe_item, ppe_scoreboard) exp_imp;
    uvm_analysis_imp_out #(ppe_out_item, ppe_scoreboard) out_imp;

    int unsigned exp_total;
    int unsigned got_total;
    int unsigned exp_seq;
    int unsigned exp_lane;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        exp_imp = new("exp_imp", this);
        out_imp = new("out_imp", this);
    endfunction

    function void write_exp(ppe_item tr);
        foreach (tr.valid[i]) begin
            if (tr.valid[i]) begin
                exp_total++;
            end
        end
    endfunction

    function void write_out(ppe_out_item item);
        if (item.seq !== exp_seq[31:0]) begin
            `uvm_error("SEQ", $sformatf("output seq got=%0d expected=%0d",
                       item.seq, exp_seq))
        end

        if (item.lane !== exp_lane[1:0]) begin
            `uvm_error("LANE", $sformatf("output lane got=%0d expected=%0d",
                       item.lane, exp_lane[1:0]))
        end

        got_total++;
        exp_seq++;
        exp_lane = (exp_lane + 1) & 3;
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (got_total != exp_total) begin
            `uvm_error("COUNT", $sformatf("output count got=%0d expected=%0d",
                       got_total, exp_total))
        end
    endfunction
endclass

`endif
