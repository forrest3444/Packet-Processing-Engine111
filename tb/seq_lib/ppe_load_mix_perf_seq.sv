// -----------------------------------------------------------------------------
// Exact-ratio medium/heavy offered-load stimulus with randomized delay and deps.
// -----------------------------------------------------------------------------

`ifndef PPE_LOAD_MIX_PERF_SEQ_SV
`define PPE_LOAD_MIX_PERF_SEQ_SV

class ppe_load_mix_perf_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_load_mix_perf_seq)

    localparam int unsigned MEDIUM_PACKETS = 378;
    localparam int unsigned MEDIUM_BEATS   = 189;
    localparam int unsigned HEAVY_PACKETS  = 756;
    localparam int unsigned HEAVY_BEATS    = 210;

    bit [2:0] dep_pool[21];
    int unsigned dep_index = 21;
    int unsigned dep_block;
    int unsigned dep_per_21 = 7;

    function new(string name = "ppe_load_mix_perf_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned beat;
        int unsigned lane;
        int unsigned seq;
        int unsigned valid_count;
        bit [3:0] lane_mask;

        seq = 0;
        void'($value$plusargs("MIXED_DEP_PER_21=%d", dep_per_21));
        if (dep_per_21 > 21) begin
            `uvm_fatal("LOAD_DEP_CONFIG", $sformatf(
                "MIXED_DEP_PER_21=%0d must be in 0..21", dep_per_21))
        end

        // Medium load: two of four input ports are valid on every source beat.
        for (beat = 0; beat < MEDIUM_BEATS; beat++) begin
            lane_mask = choose_lane_mask(2);
            tr = ppe_item::type_id::create($sformatf("medium_beat_%0d", beat));
            start_item(tr);
            clear_item(tr);
            for (lane = 0; lane < 4; lane++) begin
                if (lane_mask[lane]) begin
                    fill_lane(tr, lane, seq);
                    seq++;
                end
            end
            finish_item(tr);
        end

        // Three full beats and two 3-packet beats per five heavy source beats.
        for (beat = 0; beat < HEAVY_BEATS; beat++) begin
            valid_count = ((beat % 5) < 3) ? 4 : 3;
            lane_mask = choose_lane_mask(valid_count);
            tr = ppe_item::type_id::create($sformatf("heavy_beat_%0d", beat));
            start_item(tr);
            clear_item(tr);
            for (lane = 0; lane < 4; lane++) begin
                if (lane_mask[lane]) begin
                    fill_lane(tr, lane, seq);
                    seq++;
                end
            end
            finish_item(tr);
        end

        if (seq != (MEDIUM_PACKETS + HEAVY_PACKETS)) begin
            `uvm_fatal("LOAD_SEQ_COUNT", $sformatf(
                "generated=%0d expected=%0d", seq,
                MEDIUM_PACKETS + HEAVY_PACKETS))
        end
    endtask

    function void clear_item(ppe_item tr);
        tr.valid = '{1'b0, 1'b0, 1'b0, 1'b0};
        tr.seq = '{0, 0, 0, 0};
        tr.packet = '{'0, '0, '0, '0};
        tr.desc = '{5'b0, 5'b0, 5'b0, 5'b0};
    endfunction

    function void fill_lane(ppe_item tr, int unsigned lane,
                            int unsigned seq);
        bit [2:0] dep_offset;
        bit [1:0] delay;

        dep_offset = next_dependency();
        delay = $urandom_range(3, 0);
        tr.valid[lane] = 1'b1;
        tr.seq[lane] = seq;
        tr.packet[lane] = make_packet(seq);
        tr.desc[lane] = {dep_offset, delay};
    endfunction

    function bit [3:0] choose_lane_mask(int unsigned count);
        bit [3:0] mask;
        int unsigned lane;
        int unsigned picked;

        mask = 4'b0000;
        picked = 0;
        while (picked < count) begin
            lane = $urandom_range(3, 0);
            if (!mask[lane]) begin
                mask[lane] = 1'b1;
                picked++;
            end
        end
        return mask;
    endfunction

    function bit [2:0] next_dependency();
        if (dep_index == 21) begin
            refill_dependency_pool();
        end
        next_dependency = dep_pool[dep_index];
        dep_index++;
    endfunction

    function void refill_dependency_pool();
        bit [2:0] swap_value;
        int unsigned i;
        int unsigned j;

        for (i = 0; i < (21 - dep_per_21); i++) begin
            dep_pool[i] = 3'd0;
        end
        for (i = 0; i < dep_per_21; i++) begin
            dep_pool[(21 - dep_per_21) + i] = (i % 7) + 1;
        end

        // Keep the first group ordered so every nonzero offset has history.
        if (dep_block != 0) begin
            for (i = 20; i > 0; i--) begin
                j = $urandom_range(i, 0);
                swap_value = dep_pool[i];
                dep_pool[i] = dep_pool[j];
                dep_pool[j] = swap_value;
            end
        end
        dep_index = 0;
        dep_block++;
    endfunction

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'h10ad_0000 ^ seq,
                       32'h5000_0000 + seq,
                       32'h900d_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
