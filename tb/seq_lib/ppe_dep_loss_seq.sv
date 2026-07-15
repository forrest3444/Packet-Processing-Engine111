// -----------------------------------------------------------------------------
// Directed sequence for cache overwrite after dependency wakeup.
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

        // S1 waits for long-latency S0. S2/S3 keep three FEs occupied.
        tr = ppe_item::type_id::create("s0_to_s3");
        start_item(tr);
        tr.valid  = '{1'b1, 1'b1, 1'b1, 1'b1};
        tr.seq    = '{0, 1, 2, 3};
        tr.packet = '{make_packet(0), make_packet(1),
                      make_packet(2), make_packet(3)};
        tr.desc   = '{5'b000_11, 5'b001_00, 5'b000_11, 5'b000_11};
        finish_item(tr);

        // S4-S7 all wait for S0, leaving the fourth FE available for S8.
        tr = ppe_item::type_id::create("s4_to_s7_wait_s0");
        start_item(tr);
        tr.valid  = '{1'b1, 1'b1, 1'b1, 1'b1};
        tr.seq    = '{4, 5, 6, 7};
        tr.packet = '{make_packet(4), make_packet(5),
                      make_packet(6), make_packet(7)};
        tr.desc   = '{5'b100_00, 5'b101_00, 5'b110_00, 5'b111_00};
        finish_item(tr);

        // S8 shares cache residue 0 with S0 and returns one cycle after S0.
        tr = ppe_item::type_id::create("s8_cache_overwriter");
        start_item(tr);
        tr.valid  = '{1'b1, 1'b0, 1'b0, 1'b0};
        tr.seq    = '{8, 0, 0, 0};
        tr.packet = '{make_packet(8), '0, '0, '0};
        tr.desc   = '{5'b000_10, 5'b000_00, 5'b000_00, 5'b000_00};
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
