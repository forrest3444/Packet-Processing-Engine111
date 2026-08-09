// -----------------------------------------------------------------------------
// Directed sequence for authoritative retired-history timing.
// -----------------------------------------------------------------------------

`ifndef PPE_DEP_LOSS_SEQ_SV
`define PPE_DEP_LOSS_SEQ_SV

class ppe_dep_loss_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_dep_loss_seq)

    function new(string name = "ppe_dep_loss_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned lane;

        // S1 waits for long-latency S0. S2/S3 keep three FEs occupied.
        tr = ppe_item::type_id::create("s0_to_s3");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane]  = 1'b1;
            tr.seq[lane]    = lane;
            tr.packet[lane] = make_packet(lane);
            tr.desc[lane]   = (lane == 1) ? 5'b001_00 : 5'b000_11;
        end
        finish_item(tr);

        // S4-S7 all wait for S0, leaving the fourth FE available for S8.
        tr = ppe_item::type_id::create("s4_to_s7_wait_s0");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane]  = 1'b1;
            tr.seq[lane]    = lane + 4;
            tr.packet[lane] = make_packet(tr.seq[lane]);
            tr.desc[lane]   = {lane + 4, 2'b00};
        end
        finish_item(tr);

        // S8 shares history bank 0 with S0 and returns after S0. Its completion
        // must not overwrite the bank; only its later retirement may do so.
        tr = ppe_item::type_id::create("s8_cache_overwriter");
        start_item(tr);
        for (lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane]  = (lane == 0);
            tr.seq[lane]    = (lane == 0) ? 8 : 0;
            tr.packet[lane] = (lane == 0) ? make_packet(8) : '0;
            tr.desc[lane]   = (lane == 0) ? 5'b000_10 : 5'b000_00;
        end
        finish_item(tr);
    endtask

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'hd15c_0000 ^ seq,
                       32'h5a5a_0000 + seq,
                       32'ha55a_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
