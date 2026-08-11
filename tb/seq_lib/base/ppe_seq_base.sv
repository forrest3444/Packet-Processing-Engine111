// -----------------------------------------------------------------------------
// File       : ppe_seq_base.sv
// Description: Common transaction helpers for PPE sequences.
// -----------------------------------------------------------------------------

`ifndef PPE_SEQ_BASE_SV
`define PPE_SEQ_BASE_SV

class ppe_seq_base extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_seq_base)

    // Generation counters are also used by the common random test base.
    int unsigned generated_batch_count;
    int unsigned generated_packet_count;

    function new(string name = "ppe_seq_base");
        super.new(name);
        reset_generation_state();
    endfunction

    function void reset_generation_state();
        generated_batch_count  = 0;
        generated_packet_count = 0;
    endfunction

    // Initialize every lane so invalid lanes never carry stale metadata.
    function void clear_item(ppe_item tr);
        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            tr.valid[lane]  = 1'b0;
            tr.seq[lane]    = '0;
            tr.packet[lane] = '0;
            tr.desc[lane]   = '0;
        end
    endfunction

    function bit [PACKET_W-1:0] make_packet(bit [31:0] logical_seq);
        make_packet = {32'hcafe_0000 ^ logical_seq,
                       32'h1234_0000 + logical_seq,
                       32'h55aa_0000 ^ (logical_seq << 1),
                       logical_seq};
    endfunction

    function bit [TB_DESC_W-1:0] make_desc(bit [2:0] dep_offset,
                                            bit [1:0] delay_class);
        make_desc = '0;
        make_desc[1:0] = delay_class;
        make_desc[4:2] = dep_offset;
    endfunction

    function void fill_valid_lane(ppe_item tr, int unsigned lane,
                                  int unsigned logical_seq,
                                  bit [2:0] dep_offset,
                                  bit [1:0] delay_class);
        if (lane >= TB_N) begin
            `uvm_fatal("SEQ_LANE", $sformatf(
                "lane=%0d is outside configured width=%0d", lane, TB_N))
        end
        tr.valid[lane]  = 1'b1;
        tr.seq[lane]    = logical_seq;
        tr.packet[lane] = make_packet(logical_seq);
        tr.desc[lane]   = make_desc(dep_offset, delay_class);
        generated_packet_count++;
    endfunction

    virtual task body();
        `uvm_fatal("BASE_SEQ", "ppe_seq_base must be extended before use")
    endtask
endclass

`endif
