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
        int unsigned lane;

        tr = ppe_item::type_id::create("full_batch");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane] = 1'b1;
            tr.seq[lane] = lane;
            tr.packet[lane] = make_packet(lane);
            case (lane)
                0: tr.desc[lane] = 5'b000_11;
                1: tr.desc[lane] = 5'b001_00;
                2: tr.desc[lane] = 5'b000_01;
                default: tr.desc[lane] = 5'b010_00;
            endcase
        end
        finish_item(tr);

        tr = ppe_item::type_id::create("sparse_batch");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane] = (lane != 2);
            tr.seq[lane] = (lane == 2) ? 32'hdead : (lane + 4);
            tr.packet[lane] = make_packet(tr.seq[lane]);
            case (lane)
                0: tr.desc[lane] = 5'b001_10;
                3: tr.desc[lane] = 5'b010_01;
                default: tr.desc[lane] = 5'b000_00;
            endcase
        end
        finish_item(tr);

        tr = ppe_item::type_id::create("wrap_bank_batch");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane] = (lane == 0) || (lane == 2);
            case (lane)
                0: begin
                    tr.seq[lane] = 7;
                    tr.desc[lane] = 5'b001_00;
                end
                2: begin
                    tr.seq[lane] = 8;
                    tr.desc[lane] = 5'b000_11;
                end
                1: begin
                    tr.seq[lane] = 32'hbeef;
                    tr.desc[lane] = 5'b000_00;
                end
                default: begin
                    tr.seq[lane] = 32'hfeed;
                    tr.desc[lane] = 5'b000_00;
                end
            endcase
            tr.packet[lane] = make_packet(tr.seq[lane]);
        end
        finish_item(tr);
    endtask

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'hcafe_0000 ^ seq,
                       32'h1234_0000 + seq,
                       32'h55aa_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
