//------------------------------------------------------------------------------
// Ingress elastic-buffer stress stimulus.
//
// Periodic empty batches and changing invalid-lane data exercise the registered
// input boundary. A legal dependency-distance-one stream fills the ROB and
// forces repeated registered-backpressure transitions.
//------------------------------------------------------------------------------

`ifndef PPE_INGRESS_ELASTIC_STRESS_SEQ_SV
`define PPE_INGRESS_ELASTIC_STRESS_SEQ_SV

class ppe_ingress_elastic_stress_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_ingress_elastic_stress_seq)

    localparam int unsigned PACKET_COUNT = 256;

    function new(string name = "ppe_ingress_elastic_stress_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned source_beat;
        int unsigned packet_seq;
        bit [3:0] lane_mask;

        source_beat = 0;
        packet_seq = 0;

        while (packet_seq < PACKET_COUNT) begin
            tr = ppe_item::type_id::create(
                $sformatf("ingress_stress_beat_%0d", source_beat));
            start_item(tr);
            initialize_item(tr, source_beat);

            // Every seventh source beat is an all-invalid captured batch.
            if ((source_beat % 7) != 3) begin
                unique case (source_beat % 4)
                    0: lane_mask = 4'b1111;
                    1: lane_mask = 4'b0101;
                    2: lane_mask = 4'b1010;
                    default: lane_mask = 4'b1001;
                endcase

                for (int unsigned lane = 0; lane < 4; lane++) begin
                    if (lane_mask[lane] && (packet_seq < PACKET_COUNT)) begin
                        fill_valid_lane(tr, lane, packet_seq);
                        packet_seq++;
                    end
                end
            end

            finish_item(tr);
            source_beat++;
        end
    endtask

    function void initialize_item(ppe_item tr, int unsigned source_beat);
        for (int unsigned lane = 0; lane < 4; lane++) begin
            tr.valid[lane] = 1'b0;
            tr.seq[lane] = 32'hde00_0000 | (source_beat << 2) | lane;
            tr.packet[lane] = make_packet(tr.seq[lane])
                              ^ {4{32'hf00d_0000 | source_beat}};
            tr.desc[lane] = {source_beat[2:0], lane[1:0]};
        end
    endfunction

    function void fill_valid_lane(ppe_item tr, int unsigned lane,
                                  int unsigned packet_seq);
        bit [2:0] dep_offset;
        bit [1:0] delay;

        dep_offset = (packet_seq == 0) ? 3'd0 : 3'd1;
        delay = packet_seq[1:0];
        tr.valid[lane] = 1'b1;
        tr.seq[lane] = packet_seq;
        tr.packet[lane] = make_packet(packet_seq);
        tr.desc[lane] = {dep_offset, delay};
    endfunction

    function bit [127:0] make_packet(bit [31:0] packet_seq);
        make_packet = {32'he1a5_0000 ^ packet_seq,
                       32'h5107_0000 + packet_seq,
                       32'hb00f_0000 ^ (packet_seq << 1),
                       packet_seq};
    endfunction

endclass

`endif
