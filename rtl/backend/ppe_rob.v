`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Active reorder buffer, authoritative dependency storage, and retirement.
//------------------------------------------------------------------------------
module PPE_ROB #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W
) (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,
    input  wire [`PPE_N-1:0]                         alloc_reserve_valid_i,
    output reg                                       alloc_reserve_ready_o,
    input  wire [`PPE_N-1:0]                         alloc_commit_valid_i,
    input  wire [`PPE_N*`PPE_SEQ_W-1:0]              alloc_seq_tag_i,
    input  wire [`PPE_N*PACKET_W-1:0]                alloc_packet_i,
    input  wire [`PPE_N-1:0]                         dep_status_valid_i,
    input  wire [`PPE_N*`PPE_SEQ_W-1:0]              dep_status_target_seq_tag_i,
    output reg  [`PPE_N-1:0]                         dep_status_available_o,
    input  wire [`PPE_ISSUE_WIDTH-1:0]               prefetch_valid_i,
    input  wire [`PPE_ISSUE_WIDTH*`PPE_SEQ_W-1:0]    prefetch_seq_tag_i,
    input  wire [`PPE_ISSUE_WIDTH-1:0]               prefetch_dep_required_i,
    input  wire [`PPE_ISSUE_WIDTH*`PPE_SEQ_W-1:0]    prefetch_target_seq_tag_i,
    output wire [`PPE_ISSUE_WIDTH*PACKET_W-1:0]      prefetch_packet_o,
    output wire [`PPE_ISSUE_WIDTH*PACKET_W-1:0]      prefetch_dep_data_o,
    input  wire [`PPE_FE_NUM-1:0]                    wb_valid_i,
    input  wire [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         wb_seq_tag_i,
    input  wire [`PPE_FE_NUM*PACKET_W-1:0]           wb_data_i,
    output reg  [`PPE_N-1:0]                         retire_valid_o,
    output reg  [`PPE_N*PACKET_W-1:0]                retire_data_o
);

    localparam integer N                = `PPE_N;
    localparam integer FE_NUM           = `PPE_FE_NUM;
    localparam integer ROB_DEPTH        = `PPE_ROB_DEPTH;
    localparam integer ISSUE_WIDTH      = `PPE_ISSUE_WIDTH;
    localparam integer RESULT_BANKS     = `PPE_RESULT_BANKS;
    localparam integer SEQ_W            = `PPE_SEQ_W;
    localparam integer ROB_ID_W         = `PPE_ROB_ID_W;
    localparam integer HISTORY_ID_W     = `PPE_HISTORY_ID_W;
    localparam integer LANE_COUNT_W     = 3;
    localparam integer OCCUPANCY_W      = 6;
    localparam integer DATA_BANK_NUM    = N;
    localparam integer DATA_BANK_W      = 2;
    localparam integer DATA_ROW_NUM     = ROB_DEPTH / DATA_BANK_NUM;
    localparam integer DATA_ROW_W       = 3;
    localparam integer ROB_TAG_HI_W     = SEQ_W - ROB_ID_W;
    localparam integer HISTORY_TAG_HI_W = SEQ_W - HISTORY_ID_W;

    reg [ROB_DEPTH-1:0] rob_valid_q;
    reg [ROB_DEPTH-1:0] rob_result_valid_q;
    reg [ROB_TAG_HI_W-1:0] rob_tag_hi_q [0:ROB_DEPTH-1];
    wire [SEQ_W-1:0] rob_seq_tag_q [0:ROB_DEPTH-1];
    reg [DATA_ROW_NUM*PACKET_W-1:0] rob_data_q [0:DATA_BANK_NUM-1];

    reg [RESULT_BANKS-1:0] history_valid_q;
    reg [HISTORY_TAG_HI_W-1:0] history_tag_hi_q [0:RESULT_BANKS-1];
    wire [SEQ_W-1:0] history_seq_tag_q [0:RESULT_BANKS-1];
    reg [PACKET_W-1:0] history_data_q [0:RESULT_BANKS-1];

    genvar view_idx;
    generate
        for (view_idx = 0; view_idx < ROB_DEPTH;
             view_idx = view_idx + 1) begin : gen_rob_tag_view
            assign rob_seq_tag_q[view_idx] =
                {rob_tag_hi_q[view_idx], view_idx[ROB_ID_W-1:0]};
        end
        for (view_idx = 0; view_idx < RESULT_BANKS;
             view_idx = view_idx + 1) begin : gen_history_tag_view
            assign history_seq_tag_q[view_idx] =
                {history_tag_hi_q[view_idx],
                 view_idx[HISTORY_ID_W-1:0]};
        end
    endgenerate

    reg [DATA_BANK_W-1:0] retire_head_bank_q;
    reg [DATA_ROW_W-1:0] retire_bank_row_q [0:DATA_BANK_NUM-1];
    wire [ROB_ID_W-1:0] head_ptr_q;
    reg [OCCUPANCY_W-1:0] occupancy_q;
    reg [LANE_COUNT_W-1:0] retire_count;
    reg [OCCUPANCY_W-1:0] occupancy_after_retire;
    reg [OCCUPANCY_W-1:0] occupancy_next;

    reg [FE_NUM-1:0] wb_commit;
    reg [ROB_ID_W-1:0] wb_rob_id [0:FE_NUM-1];
    reg [ROB_ID_W-1:0] alloc_rob_id [0:N-1];
    reg [ROB_ID_W-1:0] retire_rob_id [0:N-1];
    reg [SEQ_W-1:0] retire_seq_tag [0:N-1];
    wire [N-1:0] alloc_commit;
    reg [N-1:0] retire_pending_valid_q;
    reg [ROB_ID_W-1:0] retire_pending_rob_id_q [0:N-1];
    reg [SEQ_W-1:0] retire_pending_seq_tag_q [0:N-1];
    reg [PACKET_W-1:0] retire_pending_data_q [0:N-1];
    reg [LANE_COUNT_W-1:0] retire_count_q;

    reg [FE_NUM-1:0] wb_entry_commit [0:ROB_DEPTH-1];
    reg [ROB_DEPTH-1:0] data_entry_write_en;
    reg [2*PACKET_W-1:0] data_entry_write_pair [0:ROB_DEPTH-1];
    reg [PACKET_W-1:0] data_entry_write_data [0:ROB_DEPTH-1];

    reg [DATA_BANK_NUM-1:0] alloc_data_valid_q;
    reg [DATA_ROW_W-1:0] alloc_data_row_q [0:DATA_BANK_NUM-1];
    reg [PACKET_W-1:0] alloc_data_q [0:DATA_BANK_NUM-1];
    reg [DATA_BANK_NUM-1:0] alloc_data_capture_en;
    reg [DATA_BANK_NUM-1:0] alloc_data_capture_valid;
    reg [DATA_ROW_W-1:0] alloc_data_capture_row [0:DATA_BANK_NUM-1];
    reg [PACKET_W-1:0] alloc_data_capture [0:DATA_BANK_NUM-1];

    reg [RESULT_BANKS-1:0] history_write_en;
    reg [SEQ_W-1:0] history_write_seq_tag [0:RESULT_BANKS-1];
    reg [PACKET_W-1:0] history_write_data [0:RESULT_BANKS-1];

    reg [DATA_BANK_NUM*PACKET_W-1:0] retire_bank_data;
    reg [DATA_BANK_NUM*PACKET_W-1:0] retire_rotate_one_data;
    reg [DATA_ROW_NUM-1:0] rob_done_bank [0:DATA_BANK_NUM-1];
    reg [DATA_BANK_NUM-1:0] retire_bank_done;
    reg [DATA_BANK_NUM-1:0] retire_rotate_one_done;
    reg [N-1:0] retire_raw_done;
    reg [DATA_BANK_NUM*ROB_ID_W-1:0] retire_bank_rob_id;
    reg [DATA_BANK_NUM*ROB_ID_W-1:0] retire_rotate_one_rob_id;
    reg [DATA_BANK_NUM*ROB_TAG_HI_W-1:0] retire_bank_tag_hi;
    reg [DATA_BANK_NUM*ROB_TAG_HI_W-1:0] retire_rotate_one_tag_hi;
    reg [N*ROB_TAG_HI_W-1:0] retire_raw_tag_hi;
    reg [DATA_BANK_NUM-1:0] retire_inverse_two_valid;
    reg [DATA_BANK_NUM-1:0] retire_bank_advance;

    reg [N-1:0] dep_status_active_match;
    reg [N-1:0] dep_status_active_available;
    reg [N-1:0] dep_status_history_match;
    reg [ISSUE_WIDTH-1:0] issue_dep_active_match;
    reg [ISSUE_WIDTH-1:0] issue_dep_active_available;
    reg [ISSUE_WIDTH-1:0] issue_dep_history_match;
    reg [ISSUE_WIDTH*PACKET_W-1:0] issue_dep_active_data;
    reg [ISSUE_WIDTH*PACKET_W-1:0] issue_dep_history_data;
    reg [ISSUE_WIDTH*FE_NUM-1:0] issue_dep_wb_match;
    reg [ISSUE_WIDTH-1:0] issue_dep_wb_any;
    reg [ISSUE_WIDTH*2*PACKET_W-1:0] issue_dep_wb_pair_data;
    reg [ISSUE_WIDTH*PACKET_W-1:0] issue_dep_wb_data;
    reg [ISSUE_WIDTH*PACKET_W-1:0] issue_packet_d;
    reg [ISSUE_WIDTH*PACKET_W-1:0] issue_dep_data_d;

    reg [DATA_BANK_NUM-1:0] source_bank_req_valid;
    reg [DATA_ROW_W-1:0] source_bank_req_row [0:DATA_BANK_NUM-1];
    reg [ROB_TAG_HI_W-1:0] source_bank_req_tag_hi [0:DATA_BANK_NUM-1];
    reg [DATA_BANK_NUM-1:0] source_bank_data_valid;
    reg [PACKET_W-1:0] source_bank_data [0:DATA_BANK_NUM-1];

    function [PACKET_W-1:0] rob_data_read;
        input [ROB_ID_W-1:0] rob_id;
        begin
            rob_data_read =
                rob_data_q[rob_id[DATA_BANK_W-1:0]][
                    rob_id[ROB_ID_W-1:DATA_BANK_W]*PACKET_W
                    +: PACKET_W];
        end
    endfunction

    integer done_bank;
    integer done_row;
    always @* begin : done_bank_decode
        for (done_bank = 0; done_bank < DATA_BANK_NUM;
             done_bank = done_bank + 1) begin
            rob_done_bank[done_bank] = {DATA_ROW_NUM{1'b0}};
            for (done_row = 0; done_row < DATA_ROW_NUM;
                 done_row = done_row + 1) begin
                rob_done_bank[done_bank][done_row] =
                    rob_valid_q[done_row*DATA_BANK_NUM+done_bank]
                    && rob_result_valid_q[
                        done_row*DATA_BANK_NUM+done_bank];
            end
        end
    end

    assign head_ptr_q =
        {retire_bank_row_q[retire_head_bank_q], retire_head_bank_q};
    assign alloc_commit = alloc_commit_valid_i;

    always @* begin : allocation_request_decode
        integer lane_idx;
        for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
            alloc_rob_id[lane_idx] =
                alloc_seq_tag_i[lane_idx*SEQ_W +: ROB_ID_W];
        end
    end

    always @* begin : allocation_data_capture
        integer alloc_idx;
        integer bank_idx;
        reg [DATA_BANK_W-1:0] alloc_bank;

        alloc_data_capture_en = {DATA_BANK_NUM{1'b0}};
        alloc_data_capture_valid = {DATA_BANK_NUM{1'b0}};
        alloc_bank = {DATA_BANK_W{1'b0}};
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            alloc_data_capture_row[bank_idx] = {DATA_ROW_W{1'b0}};
            alloc_data_capture[bank_idx] = {PACKET_W{1'b0}};
        end
        for (alloc_idx = 0; alloc_idx < N; alloc_idx = alloc_idx + 1) begin
            alloc_bank = alloc_rob_id[alloc_idx][DATA_BANK_W-1:0];
            if (alloc_commit_valid_i[alloc_idx]) begin
                alloc_data_capture_en[alloc_bank] = 1'b1;
                alloc_data_capture_row[alloc_bank] =
                    alloc_rob_id[alloc_idx][
                        ROB_ID_W-1:DATA_BANK_W];
                alloc_data_capture[alloc_bank] =
                    alloc_packet_i[alloc_idx*PACKET_W +: PACKET_W];
            end
            if (alloc_commit[alloc_idx]) begin
                alloc_data_capture_valid[alloc_bank] = 1'b1;
            end
        end
    end

    always @* begin : writeback_qualification
        integer wb_idx;
        integer entry_idx;

        wb_commit = {FE_NUM{1'b0}};
        data_entry_write_en = {ROB_DEPTH{1'b0}};
        for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
            wb_rob_id[wb_idx] =
                wb_seq_tag_i[wb_idx*SEQ_W +: ROB_ID_W];
            wb_commit[wb_idx] =
                wb_valid_i[wb_idx]
                && rob_valid_q[wb_rob_id[wb_idx]]
                && (rob_tag_hi_q[wb_rob_id[wb_idx]]
                    == wb_seq_tag_i[
                        wb_idx*SEQ_W+ROB_ID_W +: ROB_TAG_HI_W])
                && !rob_result_valid_q[wb_rob_id[wb_idx]];
        end
        for (entry_idx = 0; entry_idx < ROB_DEPTH;
             entry_idx = entry_idx + 1) begin
            for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
                wb_entry_commit[entry_idx][wb_idx] =
                    wb_commit[wb_idx]
                    && (wb_rob_id[wb_idx]
                        == entry_idx[ROB_ID_W-1:0]);
            end
            data_entry_write_en[entry_idx] =
                |wb_entry_commit[entry_idx];
            data_entry_write_pair[entry_idx][0 +: PACKET_W] =
                (wb_data_i[0*PACKET_W +: PACKET_W]
                 & {PACKET_W{wb_entry_commit[entry_idx][0]}})
                | (wb_data_i[1*PACKET_W +: PACKET_W]
                   & {PACKET_W{wb_entry_commit[entry_idx][1]}});
            data_entry_write_pair[entry_idx][PACKET_W +: PACKET_W] =
                (wb_data_i[2*PACKET_W +: PACKET_W]
                 & {PACKET_W{wb_entry_commit[entry_idx][2]}})
                | (wb_data_i[3*PACKET_W +: PACKET_W]
                   & {PACKET_W{wb_entry_commit[entry_idx][3]}});
            data_entry_write_data[entry_idx] =
                data_entry_write_pair[entry_idx][0 +: PACKET_W]
                | data_entry_write_pair[entry_idx][
                    PACKET_W +: PACKET_W];
        end
    end

    always @* begin : retirement_scan
        integer bank_idx;
        integer retire_idx;

        retire_bank_done = {DATA_BANK_NUM{1'b0}};
        retire_rotate_one_done = {DATA_BANK_NUM{1'b0}};
        retire_raw_done = {N{1'b0}};
        retire_valid_o = {N{1'b0}};
        retire_count = {LANE_COUNT_W{1'b0}};
        retire_bank_rob_id = {DATA_BANK_NUM*ROB_ID_W{1'b0}};
        retire_rotate_one_rob_id = {DATA_BANK_NUM*ROB_ID_W{1'b0}};
        retire_bank_tag_hi = {DATA_BANK_NUM*ROB_TAG_HI_W{1'b0}};
        retire_rotate_one_tag_hi =
            {DATA_BANK_NUM*ROB_TAG_HI_W{1'b0}};
        retire_raw_tag_hi = {N*ROB_TAG_HI_W{1'b0}};
        retire_inverse_two_valid = {DATA_BANK_NUM{1'b0}};
        retire_bank_advance = {DATA_BANK_NUM{1'b0}};

        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            retire_bank_done[bank_idx] =
                rob_done_bank[bank_idx][retire_bank_row_q[bank_idx]];
            retire_bank_rob_id[bank_idx*ROB_ID_W +: ROB_ID_W] =
                {retire_bank_row_q[bank_idx],
                 bank_idx[DATA_BANK_W-1:0]};
            retire_bank_tag_hi[
                bank_idx*ROB_TAG_HI_W +: ROB_TAG_HI_W] =
                rob_tag_hi_q[
                    {retire_bank_row_q[bank_idx],
                     bank_idx[DATA_BANK_W-1:0]}];
        end

        retire_rotate_one_done = retire_bank_done;
        retire_rotate_one_rob_id = retire_bank_rob_id;
        retire_rotate_one_tag_hi = retire_bank_tag_hi;
        if (retire_head_bank_q[0]) begin
            retire_rotate_one_done =
                {retire_bank_done[0], retire_bank_done[3:1]};
            retire_rotate_one_rob_id =
                {retire_bank_rob_id[ROB_ID_W-1:0],
                 retire_bank_rob_id[4*ROB_ID_W-1:ROB_ID_W]};
            retire_rotate_one_tag_hi =
                {retire_bank_tag_hi[ROB_TAG_HI_W-1:0],
                 retire_bank_tag_hi[
                    4*ROB_TAG_HI_W-1:ROB_TAG_HI_W]};
        end

        retire_raw_done = retire_rotate_one_done;
        for (retire_idx = 0; retire_idx < N;
             retire_idx = retire_idx + 1) begin
            retire_rob_id[retire_idx] =
                retire_rotate_one_rob_id[
                    retire_idx*ROB_ID_W +: ROB_ID_W];
        end
        retire_raw_tag_hi = retire_rotate_one_tag_hi;
        if (retire_head_bank_q[1]) begin
            retire_raw_done =
                {retire_rotate_one_done[1:0],
                 retire_rotate_one_done[3:2]};
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1) begin
                retire_rob_id[retire_idx] =
                    retire_rotate_one_rob_id[
                        ((retire_idx+2)%N)*ROB_ID_W +: ROB_ID_W];
            end
            retire_raw_tag_hi =
                {retire_rotate_one_tag_hi[2*ROB_TAG_HI_W-1:0],
                 retire_rotate_one_tag_hi[
                    4*ROB_TAG_HI_W-1:2*ROB_TAG_HI_W]};
        end

        retire_valid_o[0] = retire_raw_done[0];
        retire_valid_o[1] = retire_valid_o[0] && retire_raw_done[1];
        retire_valid_o[2] = retire_valid_o[1] && retire_raw_done[2];
        retire_valid_o[3] = retire_valid_o[2] && retire_raw_done[3];
        case (retire_valid_o)
            4'b0000: retire_count = 3'd0;
            4'b0001: retire_count = 3'd1;
            4'b0011: retire_count = 3'd2;
            4'b0111: retire_count = 3'd3;
            4'b1111: retire_count = 3'd4;
            default: retire_count = 3'd0;
        endcase

        retire_inverse_two_valid = retire_valid_o;
        if (retire_head_bank_q[1]) begin
            retire_inverse_two_valid =
                {retire_valid_o[1:0], retire_valid_o[3:2]};
        end
        retire_bank_advance = retire_inverse_two_valid;
        if (retire_head_bank_q[0]) begin
            retire_bank_advance =
                {retire_inverse_two_valid[2:0],
                 retire_inverse_two_valid[3]};
        end
        for (retire_idx = 0; retire_idx < N;
             retire_idx = retire_idx + 1) begin
            retire_seq_tag[retire_idx] =
                {retire_raw_tag_hi[
                     retire_idx*ROB_TAG_HI_W +: ROB_TAG_HI_W],
                 retire_rob_id[retire_idx]};
        end
    end

    always @* begin : retirement_data_read
        integer bank_idx;

        retire_bank_data = {DATA_BANK_NUM*PACKET_W{1'b0}};
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            retire_bank_data[bank_idx*PACKET_W +: PACKET_W] =
                rob_data_q[bank_idx][
                    retire_bank_row_q[bank_idx]*PACKET_W +: PACKET_W];
        end
        retire_rotate_one_data = retire_bank_data;
        if (retire_head_bank_q[0]) begin
            retire_rotate_one_data =
                {retire_bank_data[PACKET_W-1:0],
                 retire_bank_data[4*PACKET_W-1:PACKET_W]};
        end
        retire_data_o = retire_rotate_one_data;
        if (retire_head_bank_q[1]) begin
            retire_data_o =
                {retire_rotate_one_data[2*PACKET_W-1:0],
                 retire_rotate_one_data[
                    4*PACKET_W-1:2*PACKET_W]};
        end
    end

    always @* begin : history_write_decode
        integer history_idx;
        integer retire_idx;

        history_write_en = {RESULT_BANKS{1'b0}};
        for (history_idx = 0; history_idx < RESULT_BANKS;
             history_idx = history_idx + 1) begin
            history_write_seq_tag[history_idx] = {SEQ_W{1'b0}};
            history_write_data[history_idx] = {PACKET_W{1'b0}};
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1) begin
                if (retire_pending_valid_q[retire_idx]
                    && (retire_pending_seq_tag_q[retire_idx][
                            HISTORY_ID_W-1:0]
                        == history_idx[HISTORY_ID_W-1:0])) begin
                    history_write_en[history_idx] = 1'b1;
                    history_write_seq_tag[history_idx] =
                        retire_pending_seq_tag_q[retire_idx];
                    history_write_data[history_idx] =
                        retire_pending_data_q[retire_idx];
                end
            end
        end
    end

    always @* begin : allocation_capacity
        occupancy_after_retire =
            occupancy_q
            - {{(OCCUPANCY_W-LANE_COUNT_W){1'b0}}, retire_count_q};
        occupancy_next = occupancy_after_retire;
        alloc_reserve_ready_o = 1'b0;
        case (alloc_reserve_valid_i)
            4'b0000: begin end
            4'b0001, 4'b0010, 4'b0100, 4'b1000:
                if (occupancy_after_retire <= 6'd31) begin
                    alloc_reserve_ready_o = 1'b1;
                    occupancy_next = occupancy_after_retire + 6'd1;
                end
            4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100:
                if (occupancy_after_retire <= 6'd30) begin
                    alloc_reserve_ready_o = 1'b1;
                    occupancy_next = occupancy_after_retire + 6'd2;
                end
            4'b0111, 4'b1011, 4'b1101, 4'b1110:
                if (occupancy_after_retire <= 6'd29) begin
                    alloc_reserve_ready_o = 1'b1;
                    occupancy_next = occupancy_after_retire + 6'd3;
                end
            4'b1111:
                if (occupancy_after_retire <= 6'd28) begin
                    alloc_reserve_ready_o = 1'b1;
                    occupancy_next = occupancy_after_retire + 6'd4;
                end
            default: alloc_reserve_ready_o = 1'b0;
        endcase
    end

    always @* begin : issue_source_read
        integer bank_idx;
        integer read_idx;
        reg [DATA_BANK_W-1:0] source_bank;
        reg [ROB_ID_W-1:0] source_rob_id;

        source_bank_req_valid = {DATA_BANK_NUM{1'b0}};
        source_bank_data_valid = {DATA_BANK_NUM{1'b0}};
        issue_packet_d = {ISSUE_WIDTH*PACKET_W{1'b0}};
        source_rob_id = {ROB_ID_W{1'b0}};
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            source_bank_req_row[bank_idx] = {DATA_ROW_W{1'b0}};
            source_bank_req_tag_hi[bank_idx] = {ROB_TAG_HI_W{1'b0}};
            source_bank_data[bank_idx] = {PACKET_W{1'b0}};
            for (read_idx = 0; read_idx < ISSUE_WIDTH;
                 read_idx = read_idx + 1) begin
                if (prefetch_valid_i[read_idx]
                    && (prefetch_seq_tag_i[
                            read_idx*SEQ_W +: DATA_BANK_W]
                        == bank_idx[DATA_BANK_W-1:0])) begin
                    source_bank_req_valid[bank_idx] = 1'b1;
                    source_bank_req_row[bank_idx] =
                        prefetch_seq_tag_i[
                            read_idx*SEQ_W+DATA_BANK_W +: DATA_ROW_W];
                    source_bank_req_tag_hi[bank_idx] =
                        prefetch_seq_tag_i[
                            read_idx*SEQ_W+ROB_ID_W +: ROB_TAG_HI_W];
                end
            end
            source_rob_id =
                {source_bank_req_row[bank_idx],
                 bank_idx[DATA_BANK_W-1:0]};
            if (source_bank_req_valid[bank_idx]
                && rob_valid_q[source_rob_id]
                && (rob_tag_hi_q[source_rob_id]
                    == source_bank_req_tag_hi[bank_idx])
                && !rob_result_valid_q[source_rob_id]) begin
                source_bank_data_valid[bank_idx] = 1'b1;
                source_bank_data[bank_idx] =
                    rob_data_q[bank_idx][
                        source_bank_req_row[bank_idx]*PACKET_W
                        +: PACKET_W];
            end
        end
        for (read_idx = 0; read_idx < ISSUE_WIDTH;
             read_idx = read_idx + 1) begin
            source_bank =
                prefetch_seq_tag_i[read_idx*SEQ_W +: DATA_BANK_W];
            if (prefetch_valid_i[read_idx]
                && source_bank_data_valid[source_bank]) begin
                issue_packet_d[read_idx*PACKET_W +: PACKET_W] =
                    source_bank_data[source_bank];
            end
        end
    end

    always @* begin : dependency_lookup_decode
        integer query_idx;
        reg [ROB_ID_W-1:0] target_rob_id;
        reg [HISTORY_ID_W-1:0] history_id;

        dep_status_active_match = {N{1'b0}};
        dep_status_active_available = {N{1'b0}};
        dep_status_history_match = {N{1'b0}};
        issue_dep_active_match = {ISSUE_WIDTH{1'b0}};
        issue_dep_active_available = {ISSUE_WIDTH{1'b0}};
        issue_dep_history_match = {ISSUE_WIDTH{1'b0}};
        issue_dep_active_data = {ISSUE_WIDTH*PACKET_W{1'b0}};
        issue_dep_history_data = {ISSUE_WIDTH*PACKET_W{1'b0}};

        for (query_idx = 0; query_idx < N; query_idx = query_idx + 1) begin
            target_rob_id = dep_status_target_seq_tag_i[
                query_idx*SEQ_W +: ROB_ID_W];
            history_id = dep_status_target_seq_tag_i[
                query_idx*SEQ_W +: HISTORY_ID_W];
            if (dep_status_valid_i[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == dep_status_target_seq_tag_i[
                            query_idx*SEQ_W+ROB_ID_W
                            +: ROB_TAG_HI_W])) begin
                    dep_status_active_match[query_idx] = 1'b1;
                    dep_status_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                end
                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == dep_status_target_seq_tag_i[
                            query_idx*SEQ_W+HISTORY_ID_W
                            +: HISTORY_TAG_HI_W])) begin
                    dep_status_history_match[query_idx] = 1'b1;
                end
            end
        end
        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            target_rob_id = prefetch_target_seq_tag_i[
                query_idx*SEQ_W +: ROB_ID_W];
            history_id = prefetch_target_seq_tag_i[
                query_idx*SEQ_W +: HISTORY_ID_W];
            if (prefetch_valid_i[query_idx]
                && prefetch_dep_required_i[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == prefetch_target_seq_tag_i[
                            query_idx*SEQ_W+ROB_ID_W
                            +: ROB_TAG_HI_W])) begin
                    issue_dep_active_match[query_idx] = 1'b1;
                    issue_dep_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                    if (rob_result_valid_q[target_rob_id]) begin
                        issue_dep_active_data[
                            query_idx*PACKET_W +: PACKET_W] =
                            rob_data_read(target_rob_id);
                    end
                end
                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == prefetch_target_seq_tag_i[
                            query_idx*SEQ_W+HISTORY_ID_W
                            +: HISTORY_TAG_HI_W])) begin
                    issue_dep_history_match[query_idx] = 1'b1;
                    issue_dep_history_data[
                        query_idx*PACKET_W +: PACKET_W] =
                        history_data_q[history_id];
                end
            end
        end
    end

    always @* begin : dependency_status_resolve
        integer query_idx;
        integer wb_idx;
        reg [ROB_ID_W-1:0] target_rob_id;
        reg source_resolved;

        dep_status_available_o = {N{1'b0}};
        source_resolved = 1'b0;
        for (query_idx = 0; query_idx < N; query_idx = query_idx + 1) begin
            source_resolved = 1'b0;
            target_rob_id = dep_status_target_seq_tag_i[
                query_idx*SEQ_W +: ROB_ID_W];
            if (dep_status_valid_i[query_idx]) begin
                for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
                    if (!source_resolved
                        && wb_commit[wb_idx]
                        && (wb_rob_id[wb_idx] == target_rob_id)
                        && (wb_seq_tag_i[wb_idx*SEQ_W +: SEQ_W]
                            == dep_status_target_seq_tag_i[
                                query_idx*SEQ_W +: SEQ_W])) begin
                        source_resolved = 1'b1;
                        dep_status_available_o[query_idx] = 1'b1;
                    end
                end
                if (!source_resolved
                    && dep_status_active_match[query_idx]) begin
                    source_resolved = 1'b1;
                    dep_status_available_o[query_idx] =
                        dep_status_active_available[query_idx];
                end
                if (!source_resolved
                    && dep_status_history_match[query_idx]) begin
                    dep_status_available_o[query_idx] = 1'b1;
                end
            end
        end
    end

    always @* begin : dependency_completion_bypass
        integer query_idx;
        integer wb_idx;

        issue_dep_wb_match = {ISSUE_WIDTH*FE_NUM{1'b0}};
        issue_dep_wb_any = {ISSUE_WIDTH{1'b0}};
        issue_dep_wb_pair_data = {ISSUE_WIDTH*2*PACKET_W{1'b0}};
        issue_dep_wb_data = {ISSUE_WIDTH*PACKET_W{1'b0}};
        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
                issue_dep_wb_match[query_idx*FE_NUM+wb_idx] =
                    prefetch_valid_i[query_idx]
                    && prefetch_dep_required_i[query_idx]
                    && wb_commit[wb_idx]
                    && (wb_seq_tag_i[wb_idx*SEQ_W +: SEQ_W]
                        == prefetch_target_seq_tag_i[
                            query_idx*SEQ_W +: SEQ_W]);
            end
            issue_dep_wb_any[query_idx] =
                |issue_dep_wb_match[query_idx*FE_NUM +: FE_NUM];
            issue_dep_wb_pair_data[
                (query_idx*2+0)*PACKET_W +: PACKET_W] =
                (wb_data_i[0*PACKET_W +: PACKET_W]
                 & {PACKET_W{issue_dep_wb_match[query_idx*FE_NUM+0]}})
                | (wb_data_i[1*PACKET_W +: PACKET_W]
                   & {PACKET_W{issue_dep_wb_match[query_idx*FE_NUM+1]}});
            issue_dep_wb_pair_data[
                (query_idx*2+1)*PACKET_W +: PACKET_W] =
                (wb_data_i[2*PACKET_W +: PACKET_W]
                 & {PACKET_W{issue_dep_wb_match[query_idx*FE_NUM+2]}})
                | (wb_data_i[3*PACKET_W +: PACKET_W]
                   & {PACKET_W{issue_dep_wb_match[query_idx*FE_NUM+3]}});
            issue_dep_wb_data[query_idx*PACKET_W +: PACKET_W] =
                issue_dep_wb_pair_data[
                    (query_idx*2+0)*PACKET_W +: PACKET_W]
                | issue_dep_wb_pair_data[
                    (query_idx*2+1)*PACKET_W +: PACKET_W];
        end
    end

    always @* begin : dependency_data_resolve
        integer query_idx;

        issue_dep_data_d = {ISSUE_WIDTH*PACKET_W{1'b0}};
        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            if (prefetch_valid_i[query_idx]
                && prefetch_dep_required_i[query_idx]) begin
                if (issue_dep_wb_any[query_idx]) begin
                    issue_dep_data_d[
                        query_idx*PACKET_W +: PACKET_W] =
                        issue_dep_wb_data[
                            query_idx*PACKET_W +: PACKET_W];
                end else if (issue_dep_active_match[query_idx]) begin
                    if (issue_dep_active_available[query_idx]) begin
                        issue_dep_data_d[
                            query_idx*PACKET_W +: PACKET_W] =
                            issue_dep_active_data[
                                query_idx*PACKET_W +: PACKET_W];
                    end
                end else if (issue_dep_history_match[query_idx]) begin
                    issue_dep_data_d[
                        query_idx*PACKET_W +: PACKET_W] =
                        issue_dep_history_data[
                            query_idx*PACKET_W +: PACKET_W];
                end
            end
        end
    end

    assign prefetch_packet_o = issue_packet_d;
    assign prefetch_dep_data_o = issue_dep_data_d;

    always @(posedge clk_i or negedge rst_ni) begin : rob_metadata_update
        integer wb_idx;
        integer retire_idx;
        integer alloc_idx;

        if (!rst_ni) begin
            rob_valid_q <= {ROB_DEPTH{1'b0}};
            rob_result_valid_q <= {ROB_DEPTH{1'b0}};
        end else begin
            for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1)
                if (wb_commit[wb_idx])
                    rob_result_valid_q[wb_rob_id[wb_idx]] <= 1'b1;
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1)
                if (retire_pending_valid_q[retire_idx]) begin
                    rob_valid_q[retire_pending_rob_id_q[retire_idx]] <= 1'b0;
                    rob_result_valid_q[
                        retire_pending_rob_id_q[retire_idx]] <= 1'b0;
                end
            for (alloc_idx = 0; alloc_idx < N;
                 alloc_idx = alloc_idx + 1)
                if (alloc_commit[alloc_idx]) begin
                    rob_valid_q[alloc_rob_id[alloc_idx]] <= 1'b1;
                    rob_tag_hi_q[alloc_rob_id[alloc_idx]] <=
                        alloc_seq_tag_i[
                            alloc_idx*SEQ_W+ROB_ID_W +: ROB_TAG_HI_W];
                    rob_result_valid_q[alloc_rob_id[alloc_idx]] <= 1'b0;
                end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : retire_pending_control
        integer retire_idx;

        if (!rst_ni) begin
            retire_pending_valid_q <= {N{1'b0}};
            retire_count_q <= {LANE_COUNT_W{1'b0}};
        end else begin
            retire_pending_valid_q <= retire_valid_o;
            retire_count_q <= retire_count;
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1)
                if (retire_valid_o[retire_idx]) begin
                    retire_pending_rob_id_q[retire_idx] <=
                        retire_rob_id[retire_idx];
                    retire_pending_seq_tag_q[retire_idx] <=
                        retire_seq_tag[retire_idx];
                end
        end
    end

    always @(posedge clk_i) begin : retire_pending_data
        integer retire_idx;
        for (retire_idx = 0; retire_idx < N;
             retire_idx = retire_idx + 1)
            if (retire_valid_o[retire_idx])
                retire_pending_data_q[retire_idx] <=
                    retire_data_o[retire_idx*PACKET_W +: PACKET_W];
    end

    always @(posedge clk_i or negedge rst_ni) begin : alloc_data_control
        integer bank_idx;
        if (!rst_ni) begin
            alloc_data_valid_q <= {DATA_BANK_NUM{1'b0}};
        end else begin
            alloc_data_valid_q <= alloc_data_capture_valid;
            for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
                 bank_idx = bank_idx + 1)
                if (alloc_data_capture_en[bank_idx])
                    alloc_data_row_q[bank_idx] <=
                        alloc_data_capture_row[bank_idx];
        end
    end

    always @(posedge clk_i) begin : alloc_data_payload
        integer bank_idx;
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1)
            if (alloc_data_capture_en[bank_idx])
                alloc_data_q[bank_idx] <= alloc_data_capture[bank_idx];
    end

    always @(posedge clk_i) begin : rob_data_update
        integer bank_idx;
        integer row_idx;
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1)
            for (row_idx = 0; row_idx < DATA_ROW_NUM;
                 row_idx = row_idx + 1) begin
                if (data_entry_write_en[
                        row_idx*DATA_BANK_NUM+bank_idx])
                    rob_data_q[bank_idx][row_idx*PACKET_W +: PACKET_W]
                        <= data_entry_write_data[
                            row_idx*DATA_BANK_NUM+bank_idx];
                if (alloc_data_valid_q[bank_idx]
                    && (alloc_data_row_q[bank_idx]
                        == row_idx[DATA_ROW_W-1:0]))
                    rob_data_q[bank_idx][row_idx*PACKET_W +: PACKET_W]
                        <= alloc_data_q[bank_idx];
            end
    end

    always @(posedge clk_i or negedge rst_ni)
        begin : history_metadata_update
        integer history_idx;
        if (!rst_ni) begin
            history_valid_q <= {RESULT_BANKS{1'b0}};
        end else begin
            for (history_idx = 0; history_idx < RESULT_BANKS;
                 history_idx = history_idx + 1)
                if (history_write_en[history_idx]) begin
                    history_valid_q[history_idx] <= 1'b1;
                    history_tag_hi_q[history_idx] <=
                        history_write_seq_tag[history_idx][
                            SEQ_W-1:HISTORY_ID_W];
                end
        end
    end

    always @(posedge clk_i) begin : history_data_update
        integer history_idx;
        for (history_idx = 0; history_idx < RESULT_BANKS;
             history_idx = history_idx + 1)
            if (history_write_en[history_idx])
                history_data_q[history_idx] <= history_write_data[history_idx];
    end

    always @(posedge clk_i or negedge rst_ni) begin : rob_control_update
        integer bank_idx;
        if (!rst_ni) begin
            retire_head_bank_q <= {DATA_BANK_W{1'b0}};
            occupancy_q <= {OCCUPANCY_W{1'b0}};
            for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
                 bank_idx = bank_idx + 1)
                retire_bank_row_q[bank_idx] <= {DATA_ROW_W{1'b0}};
        end else begin
            if (retire_count != {LANE_COUNT_W{1'b0}})
                retire_head_bank_q <= retire_head_bank_q
                                      + retire_count[DATA_BANK_W-1:0];
            for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
                 bank_idx = bank_idx + 1)
                if (retire_bank_advance[bank_idx])
                    retire_bank_row_q[bank_idx] <=
                        retire_bank_row_q[bank_idx] + 3'd1;
            occupancy_q <= occupancy_next;
        end
    end

endmodule

`default_nettype wire
