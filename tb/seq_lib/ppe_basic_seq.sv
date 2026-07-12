// -----------------------------------------------------------------------------
// File       : ppe_basic_seq.sv
// Author     : Codex
// Description: Short smoke sequence for PPE UVM bring-up.
// -----------------------------------------------------------------------------

`ifndef PPE_BASIC_SEQ_SV
`define PPE_BASIC_SEQ_SV

class ppe_basic_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_basic_seq)

    function new(string name = "ppe_basic_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned base_seq;

        base_seq = 0;
        repeat (3) begin
            tr = ppe_item::type_id::create("tr");
            start_item(tr);

            foreach (tr.valid[i]) begin
                tr.valid[i] = 1'b1;
                tr.desc[i]  = 5'd0;
            end

            /* Shuffle seq across physical lanes. */
            tr.seq[0] = base_seq + 2;
            tr.seq[1] = base_seq + 0;
            tr.seq[2] = base_seq + 3;
            tr.seq[3] = base_seq + 1;

            finish_item(tr);
            base_seq += 4;
        end
    endtask
endclass

`endif
