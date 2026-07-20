//------------------------------------------------------------------------------
// ROB32 saturation and sequence-wrap stimulus.
//
// A dependency-distance-one stream deliberately limits retirement progress so
// the 32-entry ROB fills. The stream is long enough to cross the 6-bit sequence
// tag boundary twice while the normal driver supplies continuous 4-wide input.
//------------------------------------------------------------------------------

`ifndef PPE_ROB32_WRAP_SEQ_SV
`define PPE_ROB32_WRAP_SEQ_SV

class ppe_rob32_wrap_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_rob32_wrap_seq)

    localparam int unsigned PACKET_COUNT = 128;
    localparam int unsigned BATCH_COUNT  = PACKET_COUNT / 4;

    function new(string name = "ppe_rob32_wrap_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;

        for (int unsigned batch = 0; batch < BATCH_COUNT; batch++) begin
            tr = ppe_item::type_id::create(
                $sformatf("rob32_wrap_batch_%0d", batch));
            start_item(tr);
            for (int unsigned lane = 0; lane < 4; lane++) begin
                int unsigned packet_seq;

                packet_seq = (batch * 4) + lane;
                tr.valid[lane]  = 1'b1;
                tr.seq[lane]    = packet_seq;
                tr.packet[lane] = make_packet(packet_seq);
                tr.desc[lane]   = (packet_seq == 0)
                                  ? 5'b000_00 : 5'b001_00;
            end
            finish_item(tr);
        end
    endtask

    function bit [127:0] make_packet(bit [31:0] packet_seq);
        make_packet = {32'h3200_0000 ^ packet_seq,
                       32'h6400_0000 + packet_seq,
                       32'h9600_0000 ^ (packet_seq << 1),
                       packet_seq};
    endfunction

endclass

`endif
