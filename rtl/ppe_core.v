// -----------------------------------------------------------------------------
// File       : ppe_core.v
// Author     : Codex
// Description: PPE core for 4-lane packet scheduling, dependency, and reorder.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module ppe_core #(
    parameter integer PACKET_W  = 128,
    parameter integer RESULT_W  = 128,
    parameter integer ROB_DEPTH = 16,
    parameter integer ROB_AW    = 4
) (
    input                         clk,
    input                         rst_n,

    input                         in_valid0,
    input      [PACKET_W-1:0]     in_packet0,
    input      [4:0]              in_desc0,
    input                         in_valid1,
    input      [PACKET_W-1:0]     in_packet1,
    input      [4:0]              in_desc1,
    input                         in_valid2,
    input      [PACKET_W-1:0]     in_packet2,
    input      [4:0]              in_desc2,
    input                         in_valid3,
    input      [PACKET_W-1:0]     in_packet3,
    input      [4:0]              in_desc3,
    output reg                    bkps,

    output reg                    out_valid0,
    output reg [PACKET_W-1:0]     out_packet0,
    output reg                    out_valid1,
    output reg [PACKET_W-1:0]     out_packet1,
    output reg                    out_valid2,
    output reg [PACKET_W-1:0]     out_packet2,
    output reg                    out_valid3,
    output reg [PACKET_W-1:0]     out_packet3,

    output reg                    fe_in_valid0,
    input                         fe_in_ready0,
    output reg [PACKET_W-1:0]     fe_in_packet0,
    output reg                    fe_in_valid1,
    input                         fe_in_ready1,
    output reg [PACKET_W-1:0]     fe_in_packet1,
    output reg                    fe_in_valid2,
    input                         fe_in_ready2,
    output reg [PACKET_W-1:0]     fe_in_packet2,
    output reg                    fe_in_valid3,
    input                         fe_in_ready3,
    output reg [PACKET_W-1:0]     fe_in_packet3,

    input                         fe_out_valid0,
    output                        fe_out_ready0,
    input      [PACKET_W-1:0]     fe_out_packet0,
    input      [RESULT_W-1:0]     fe_out_result0,
    input                         fe_out_valid1,
    output                        fe_out_ready1,
    input      [PACKET_W-1:0]     fe_out_packet1,
    input      [RESULT_W-1:0]     fe_out_result1,
    input                         fe_out_valid2,
    output                        fe_out_ready2,
    input      [PACKET_W-1:0]     fe_out_packet2,
    input      [RESULT_W-1:0]     fe_out_result2,
    input                         fe_out_valid3,
    output                        fe_out_ready3,
    input      [PACKET_W-1:0]     fe_out_packet3,
    input      [RESULT_W-1:0]     fe_out_result3
);

    localparam [2:0] ST_EMPTY      = 3'd0;
    localparam [2:0] ST_WAIT_DELAY = 3'd1;
    localparam [2:0] ST_WAIT_DEP   = 3'd2;
    localparam [2:0] ST_READY_FE   = 3'd3;
    localparam [2:0] ST_IN_FE      = 3'd4;
    localparam [2:0] ST_DONE       = 3'd5;

    reg                         rob_valid   [0:ROB_DEPTH-1];
    reg [2:0]                   rob_state   [0:ROB_DEPTH-1];
    reg [31:0]                  rob_seq     [0:ROB_DEPTH-1];
    reg [PACKET_W-1:0]          rob_packet  [0:ROB_DEPTH-1];
    reg [PACKET_W-1:0]          rob_out_pkt [0:ROB_DEPTH-1];
    reg [2:0]                   rob_dep     [0:ROB_DEPTH-1];
    reg [1:0]                   rob_delay   [0:ROB_DEPTH-1];

    reg                         res_valid   [0:7];
    reg [31:0]                  res_seq     [0:7];
    reg [RESULT_W-1:0]          res_data    [0:7];

    reg                         fe_busy     [0:3];
    reg [ROB_AW-1:0]            fe_rob_idx  [0:3];

    reg                         started;
    reg                         fatal_stall;
    reg [31:0]                  next_output_seq;
    reg [1:0]                   out_start_lane;

    reg                         sched_valid [0:3];
    reg [ROB_AW-1:0]            sched_idx   [0:3];
    reg [ROB_DEPTH-1:0]         sched_mask;
    reg [7:0]                   sched_res_mask;

    integer i;
    integer j;
    integer free_count;
    integer input_count;
    integer emit_count;
    integer found_idx;
    reg [1:0] lane_sel;

    reg [31:0]                  seq_tmp;
    reg [4:0]                   desc_tmp;
    reg [PACKET_W-1:0]          pkt_tmp;
    reg [ROB_AW-1:0]            rob_idx_tmp;
    reg [2:0]                   res_slot_tmp;
    reg [31:0]                  min_seq;
    reg                         min_found;
    reg                         dep_hit;
    reg [RESULT_W-1:0]          dep_result;
    reg [PACKET_W-1:0]          dispatch_packet;

    assign fe_out_ready0 = 1'b1;
    assign fe_out_ready1 = 1'b1;
    assign fe_out_ready2 = 1'b1;
    assign fe_out_ready3 = 1'b1;

    function [PACKET_W-1:0] lane_packet;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: lane_packet = in_packet0;
                2'd1: lane_packet = in_packet1;
                2'd2: lane_packet = in_packet2;
                default: lane_packet = in_packet3;
            endcase
        end
    endfunction

    function [4:0] lane_desc;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: lane_desc = in_desc0;
                2'd1: lane_desc = in_desc1;
                2'd2: lane_desc = in_desc2;
                default: lane_desc = in_desc3;
            endcase
        end
    endfunction

    function lane_valid;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: lane_valid = in_valid0;
                2'd1: lane_valid = in_valid1;
                2'd2: lane_valid = in_valid2;
                default: lane_valid = in_valid3;
            endcase
        end
    endfunction

    function pending_dep_on;
        input [31:0] target_seq;
        integer p;
        begin
            pending_dep_on = 1'b0;
            for (p = 0; p < ROB_DEPTH; p = p + 1) begin
                if (rob_valid[p] &&
                    (rob_dep[p] != 3'd0) &&
                    ((rob_state[p] == ST_WAIT_DELAY) ||
                     (rob_state[p] == ST_WAIT_DEP) ||
                     (rob_state[p] == ST_READY_FE)) &&
                    ((rob_seq[p] - {29'd0, rob_dep[p]}) == target_seq)) begin
                    pending_dep_on = 1'b1;
                end
            end
        end
    endfunction

    function result_slot_safe;
        input [31:0] new_seq;
        reg [2:0] slot;
        begin
            slot = new_seq[2:0];
            result_slot_safe = 1'b1;
            if (res_valid[slot] && (res_seq[slot] != new_seq)) begin
                result_slot_safe = !pending_dep_on(res_seq[slot]);
            end
        end
    endfunction

    always @(*) begin
        free_count  = 0;
        input_count = 0;

        for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            if (!rob_valid[i]) begin
                free_count = free_count + 1;
            end
        end

        if (in_valid0) input_count = input_count + 1;
        if (in_valid1) input_count = input_count + 1;
        if (in_valid2) input_count = input_count + 1;
        if (in_valid3) input_count = input_count + 1;

        bkps = fatal_stall || (free_count < input_count);
    end

    task find_result;
        input [31:0] target_seq;
        output       hit;
        output [RESULT_W-1:0] data;
        integer r;
        begin
            hit  = 1'b0;
            data = {RESULT_W{1'b0}};
            for (r = 0; r < 8; r = r + 1) begin
                if (res_valid[r] && (res_seq[r] == target_seq)) begin
                    hit  = 1'b1;
                    data = res_data[r];
                end
            end
        end
    endtask

    always @(*) begin
        fe_in_valid0  = 1'b0;
        fe_in_valid1  = 1'b0;
        fe_in_valid2  = 1'b0;
        fe_in_valid3  = 1'b0;
        fe_in_packet0 = {PACKET_W{1'b0}};
        fe_in_packet1 = {PACKET_W{1'b0}};
        fe_in_packet2 = {PACKET_W{1'b0}};
        fe_in_packet3 = {PACKET_W{1'b0}};

        sched_valid[0] = 1'b0;
        sched_valid[1] = 1'b0;
        sched_valid[2] = 1'b0;
        sched_valid[3] = 1'b0;
        sched_idx[0]   = {ROB_AW{1'b0}};
        sched_idx[1]   = {ROB_AW{1'b0}};
        sched_idx[2]   = {ROB_AW{1'b0}};
        sched_idx[3]   = {ROB_AW{1'b0}};
        sched_mask     = {ROB_DEPTH{1'b0}};
        sched_res_mask = 8'h00;

        for (i = 0; i < 4; i = i + 1) begin
            if (!fatal_stall && !fe_busy[i] &&
                ((i == 0 && fe_in_ready0) ||
                 (i == 1 && fe_in_ready1) ||
                 (i == 2 && fe_in_ready2) ||
                 (i == 3 && fe_in_ready3))) begin

                for (j = 0; j < ROB_DEPTH; j = j + 1) begin
                    if (rob_valid[j] && (rob_state[j] == ST_READY_FE) &&
                        !sched_mask[j] && !sched_valid[i] &&
                        !sched_res_mask[rob_seq[j][2:0]]) begin

                        dep_hit    = 1'b0;
                        dep_result = {RESULT_W{1'b0}};

                        if (rob_dep[j] == 3'd0) begin
                            dep_hit = 1'b1;
                        end else begin
                            find_result(rob_seq[j] - {29'd0, rob_dep[j]},
                                        dep_hit, dep_result);
                        end

                        if (dep_hit && result_slot_safe(rob_seq[j])) begin
                            dispatch_packet = rob_packet[j];
                            if (rob_dep[j] != 3'd0) begin
                                dispatch_packet[127:32] =
                                    rob_packet[j][127:32] ^ dep_result[127:32];
                                dispatch_packet[31:0] = rob_packet[j][31:0];
                            end

                            sched_valid[i] = 1'b1;
                            sched_idx[i]   = j[ROB_AW-1:0];
                            sched_mask[j]  = 1'b1;
                            sched_res_mask[rob_seq[j][2:0]] = 1'b1;

                            case (i)
                                0: begin
                                    fe_in_valid0  = 1'b1;
                                    fe_in_packet0 = dispatch_packet;
                                end
                                1: begin
                                    fe_in_valid1  = 1'b1;
                                    fe_in_packet1 = dispatch_packet;
                                end
                                2: begin
                                    fe_in_valid2  = 1'b1;
                                    fe_in_packet2 = dispatch_packet;
                                end
                                default: begin
                                    fe_in_valid3  = 1'b1;
                                    fe_in_packet3 = dispatch_packet;
                                end
                            endcase
                        end
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            started         <= 1'b0;
            fatal_stall     <= 1'b0;
            next_output_seq <= 32'd0;
            out_start_lane  <= 2'd0;

            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;
            out_packet0 <= {PACKET_W{1'b0}};
            out_packet1 <= {PACKET_W{1'b0}};
            out_packet2 <= {PACKET_W{1'b0}};
            out_packet3 <= {PACKET_W{1'b0}};

            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                rob_valid[i]   <= 1'b0;
                rob_state[i]   <= ST_EMPTY;
                rob_seq[i]     <= 32'd0;
                rob_packet[i]  <= {PACKET_W{1'b0}};
                rob_out_pkt[i] <= {PACKET_W{1'b0}};
                rob_dep[i]     <= 3'd0;
                rob_delay[i]   <= 2'd0;
            end

            for (i = 0; i < 8; i = i + 1) begin
                res_valid[i] <= 1'b0;
                res_seq[i]   <= 32'd0;
                res_data[i]  <= {RESULT_W{1'b0}};
            end

            for (i = 0; i < 4; i = i + 1) begin
                fe_busy[i]    <= 1'b0;
                fe_rob_idx[i] <= {ROB_AW{1'b0}};
            end
        end else begin
            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;
            out_packet0 <= {PACKET_W{1'b0}};
            out_packet1 <= {PACKET_W{1'b0}};
            out_packet2 <= {PACKET_W{1'b0}};
            out_packet3 <= {PACKET_W{1'b0}};

            /* FE return path: single inflight per FE, FE index holds ROB tag. */
            if (fe_out_valid0 && fe_out_ready0) begin
                if (fe_busy[0]) begin
                    rob_idx_tmp = fe_rob_idx[0];
                    res_slot_tmp = rob_seq[rob_idx_tmp][2:0];
                    if (res_valid[res_slot_tmp] &&
                        (res_seq[res_slot_tmp] != rob_seq[rob_idx_tmp]) &&
                        pending_dep_on(res_seq[res_slot_tmp])) begin
                        fatal_stall <= 1'b1;
                    end else begin
                        rob_out_pkt[rob_idx_tmp] <= fe_out_packet0;
                        rob_state[rob_idx_tmp]   <= ST_DONE;
                        res_valid[res_slot_tmp]  <= 1'b1;
                        res_seq[res_slot_tmp]    <= rob_seq[rob_idx_tmp];
                        res_data[res_slot_tmp]   <= fe_out_result0;
                        fe_busy[0] <= 1'b0;
                    end
                end else begin
                    fatal_stall <= 1'b1;
                end
            end

            if (fe_out_valid1 && fe_out_ready1) begin
                if (fe_busy[1]) begin
                    rob_idx_tmp = fe_rob_idx[1];
                    res_slot_tmp = rob_seq[rob_idx_tmp][2:0];
                    if (res_valid[res_slot_tmp] &&
                        (res_seq[res_slot_tmp] != rob_seq[rob_idx_tmp]) &&
                        pending_dep_on(res_seq[res_slot_tmp])) begin
                        fatal_stall <= 1'b1;
                    end else begin
                        rob_out_pkt[rob_idx_tmp] <= fe_out_packet1;
                        rob_state[rob_idx_tmp]   <= ST_DONE;
                        res_valid[res_slot_tmp]  <= 1'b1;
                        res_seq[res_slot_tmp]    <= rob_seq[rob_idx_tmp];
                        res_data[res_slot_tmp]   <= fe_out_result1;
                        fe_busy[1] <= 1'b0;
                    end
                end else begin
                    fatal_stall <= 1'b1;
                end
            end

            if (fe_out_valid2 && fe_out_ready2) begin
                if (fe_busy[2]) begin
                    rob_idx_tmp = fe_rob_idx[2];
                    res_slot_tmp = rob_seq[rob_idx_tmp][2:0];
                    if (res_valid[res_slot_tmp] &&
                        (res_seq[res_slot_tmp] != rob_seq[rob_idx_tmp]) &&
                        pending_dep_on(res_seq[res_slot_tmp])) begin
                        fatal_stall <= 1'b1;
                    end else begin
                        rob_out_pkt[rob_idx_tmp] <= fe_out_packet2;
                        rob_state[rob_idx_tmp]   <= ST_DONE;
                        res_valid[res_slot_tmp]  <= 1'b1;
                        res_seq[res_slot_tmp]    <= rob_seq[rob_idx_tmp];
                        res_data[res_slot_tmp]   <= fe_out_result2;
                        fe_busy[2] <= 1'b0;
                    end
                end else begin
                    fatal_stall <= 1'b1;
                end
            end

            if (fe_out_valid3 && fe_out_ready3) begin
                if (fe_busy[3]) begin
                    rob_idx_tmp = fe_rob_idx[3];
                    res_slot_tmp = rob_seq[rob_idx_tmp][2:0];
                    if (res_valid[res_slot_tmp] &&
                        (res_seq[res_slot_tmp] != rob_seq[rob_idx_tmp]) &&
                        pending_dep_on(res_seq[res_slot_tmp])) begin
                        fatal_stall <= 1'b1;
                    end else begin
                        rob_out_pkt[rob_idx_tmp] <= fe_out_packet3;
                        rob_state[rob_idx_tmp]   <= ST_DONE;
                        res_valid[res_slot_tmp]  <= 1'b1;
                        res_seq[res_slot_tmp]    <= rob_seq[rob_idx_tmp];
                        res_data[res_slot_tmp]   <= fe_out_result3;
                        fe_busy[3] <= 1'b0;
                    end
                end else begin
                    fatal_stall <= 1'b1;
                end
            end

            /* Delay and dependency path. */
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                if (rob_valid[i]) begin
                    if (rob_state[i] == ST_WAIT_DELAY) begin
                        if (rob_delay[i] != 2'd0) begin
                            rob_delay[i] <= rob_delay[i] - 2'd1;
                        end else if (rob_dep[i] == 3'd0) begin
                            rob_state[i] <= ST_READY_FE;
                        end else begin
                            rob_state[i] <= ST_WAIT_DEP;
                        end
                    end else if (rob_state[i] == ST_WAIT_DEP) begin
                        find_result(rob_seq[i] - {29'd0, rob_dep[i]},
                                    dep_hit, dep_result);
                        if (dep_hit) begin
                            rob_state[i] <= ST_READY_FE;
                        end
                    end
                end
            end

            /* Dispatch handshake path. */
            if (fe_in_valid0 && fe_in_ready0) begin
                rob_state[sched_idx[0]] <= ST_IN_FE;
                fe_busy[0]              <= 1'b1;
                fe_rob_idx[0]           <= sched_idx[0];
            end
            if (fe_in_valid1 && fe_in_ready1) begin
                rob_state[sched_idx[1]] <= ST_IN_FE;
                fe_busy[1]              <= 1'b1;
                fe_rob_idx[1]           <= sched_idx[1];
            end
            if (fe_in_valid2 && fe_in_ready2) begin
                rob_state[sched_idx[2]] <= ST_IN_FE;
                fe_busy[2]              <= 1'b1;
                fe_rob_idx[2]           <= sched_idx[2];
            end
            if (fe_in_valid3 && fe_in_ready3) begin
                rob_state[sched_idx[3]] <= ST_IN_FE;
                fe_busy[3]              <= 1'b1;
                fe_rob_idx[3]           <= sched_idx[3];
            end

            /* Strict output path. */
            emit_count = 0;
            for (i = 0; i < 4; i = i + 1) begin
                found_idx = -1;
                for (j = 0; j < ROB_DEPTH; j = j + 1) begin
                    if (rob_valid[j] && (rob_state[j] == ST_DONE) &&
                        (rob_seq[j] == (next_output_seq + emit_count[31:0]))) begin
                        found_idx = j;
                    end
                end

                if (found_idx >= 0) begin
                    lane_sel = out_start_lane + emit_count[1:0];
                    case (lane_sel)
                        0: begin
                            out_valid0 <= 1'b1;
                            out_packet0 <= rob_out_pkt[found_idx];
                        end
                        1: begin
                            out_valid1 <= 1'b1;
                            out_packet1 <= rob_out_pkt[found_idx];
                        end
                        2: begin
                            out_valid2 <= 1'b1;
                            out_packet2 <= rob_out_pkt[found_idx];
                        end
                        default: begin
                            out_valid3 <= 1'b1;
                            out_packet3 <= rob_out_pkt[found_idx];
                        end
                    endcase

                    rob_valid[found_idx] <= 1'b0;
                    rob_state[found_idx] <= ST_EMPTY;
                    emit_count = emit_count + 1;
                end
            end

            if (emit_count != 0) begin
                next_output_seq <= next_output_seq + emit_count[31:0];
                out_start_lane  <= out_start_lane + emit_count[1:0];
            end

            /* Input collector path. */
            if (!bkps) begin
                min_found = 1'b0;
                min_seq   = 32'hffff_ffff;
                for (i = 0; i < 4; i = i + 1) begin
                    if (lane_valid(i[1:0])) begin
                        pkt_tmp = lane_packet(i[1:0]);
                        seq_tmp = pkt_tmp[31:0];
                        if (!min_found || (seq_tmp < min_seq)) begin
                            min_found = 1'b1;
                            min_seq   = seq_tmp;
                        end
                    end
                end

                if (!started && min_found) begin
                    started         <= 1'b1;
                    next_output_seq <= min_seq;
                end

                for (i = 0; i < 4; i = i + 1) begin
                    if (lane_valid(i[1:0])) begin
                        pkt_tmp     = lane_packet(i[1:0]);
                        seq_tmp     = pkt_tmp[31:0];
                        desc_tmp    = lane_desc(i[1:0]);
                        rob_idx_tmp = seq_tmp[ROB_AW-1:0];

                        if (rob_valid[rob_idx_tmp]) begin
                            fatal_stall <= 1'b1;
                        end else begin
                            rob_valid[rob_idx_tmp]   <= 1'b1;
                            rob_seq[rob_idx_tmp]     <= seq_tmp;
                            rob_packet[rob_idx_tmp]  <= pkt_tmp;
                            rob_out_pkt[rob_idx_tmp] <= {PACKET_W{1'b0}};
                            rob_dep[rob_idx_tmp]     <= desc_tmp[4:2];
                            rob_delay[rob_idx_tmp]   <= desc_tmp[1:0];

                            if (desc_tmp[1:0] != 2'd0) begin
                                rob_state[rob_idx_tmp] <= ST_WAIT_DELAY;
                            end else if (desc_tmp[4:2] != 3'd0) begin
                                rob_state[rob_idx_tmp] <= ST_WAIT_DEP;
                            end else begin
                                rob_state[rob_idx_tmp] <= ST_READY_FE;
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
