`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Unified pre-issue state, candidate matching, operand gather, and FE calendar.
//------------------------------------------------------------------------------
module PPE_SCHEDULER #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W
) (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,
    input  wire [`PPE_ROB_BANK_ROW_W-1:0]            ready_bank_head_row_i
                                                     [0:`PPE_READY_ENQUEUE_WIDTH-1],
    input  wire [`PPE_N-1:0]                         issue_alloc_valid_i,
    input  wire [`PPE_SEQ_W-1:0]                     alloc_seq_tag_i [0:`PPE_N-1],
    input  wire [`PPE_SEQ_W-1:0]                     alloc_target_seq_tag_i [0:`PPE_N-1],
    input  wire [`PPE_DELAY_W-1:0]                   alloc_delay_i [0:`PPE_N-1],
    input  wire [`PPE_N-1:0]                         alloc_dep_required_i,
    output reg  [`PPE_N-1:0]                         dep_status_valid_o,
    output reg  [`PPE_SEQ_W-1:0]                     dep_status_target_seq_tag_o [0:`PPE_N-1],
    input  wire [`PPE_N-1:0]                         dep_status_available_i,
    input  wire [`PPE_FE_NUM-1:0]                    completion_valid_i,
    input  wire [`PPE_SEQ_W-1:0]                     completion_seq_tag_i [0:`PPE_FE_NUM-1],
    output reg  [`PPE_ROB_BANK_ROW_W-1:0]            source_bank_row_o [0:`PPE_N-1],
    output reg  [`PPE_ROB_TAG_HI_W-1:0]              source_bank_tag_hi_o [0:`PPE_N-1],
    input  wire [PACKET_W-1:0]                       source_bank_packet_i [0:`PPE_N-1],
    output reg  [`PPE_FE_NUM-1:0]                    gather_dep_required_o,
    output reg  [`PPE_SEQ_W-1:0]                     gather_target_seq_tag_o [0:`PPE_FE_NUM-1],
    input  wire [PACKET_W-1:0]                       gather_dep_data_i [0:`PPE_FE_NUM-1],
    output reg  [`PPE_FE_NUM-1:0]                    issue_valid_o,
    output reg  [PACKET_W-1:0]                       issue_packet_o [0:`PPE_FE_NUM-1],
    output reg  [`PPE_DELAY_W-1:0]                   issue_delay_o [0:`PPE_FE_NUM-1],
    output reg  [`PPE_FE_NUM-1:0]                    issue_dep_required_o,
    output reg  [PACKET_W-1:0]                       issue_dep_data_o [0:`PPE_FE_NUM-1],
    input  wire [`PPE_FE_NUM-1:0]                    fe_out_valid_i,
    output reg  [`PPE_FE_NUM-1:0]                    completion_valid_o,
    output reg  [`PPE_SEQ_W-1:0]                     completion_seq_tag_o [0:`PPE_FE_NUM-1],
    output reg  [`PPE_FE_NUM-1:0]                    wb_pre_valid_o,
    output reg  [`PPE_SEQ_W-1:0]                     wb_pre_seq_tag_o [0:`PPE_FE_NUM-1],
    output reg  [`PPE_ROB_DEPTH-1:0]                 wb_pre_entry_onehot_o [0:`PPE_FE_NUM-1]
);

    localparam integer N                 = `PPE_N;
    localparam integer FE_NUM            = `PPE_FE_NUM;
    localparam integer ISSUE_DEPTH       = `PPE_ISSUE_DEPTH;
    localparam integer CAND_WINDOW_DEPTH = `PPE_CAND_WINDOW_DEPTH;
    localparam integer READY_ENQUEUE_WIDTH =
        `PPE_READY_ENQUEUE_WIDTH;
    localparam integer SEQ_W             = `PPE_SEQ_W;
    localparam integer DELAY_W           = `PPE_DELAY_W;
    localparam integer ROB_ID_W          = `PPE_ROB_ID_W;
    localparam integer ROB_TAG_HI_W      = `PPE_ROB_TAG_HI_W;
    localparam integer DATA_BANK_W       = 2;
    localparam integer MAX_DEP           = `PPE_MAX_DEP;

    localparam [1:0] ISSUE_FREE     = 2'd0;
    localparam [1:0] ISSUE_WAIT_DEP = 2'd1;
    localparam [1:0] ISSUE_READY    = 2'd2;
    localparam [1:0] ISSUE_SELECTED = 2'd3;

    localparam integer CAND_ID_W    = 3;
    localparam integer ADMIT_BANKS  = READY_ENQUEUE_WIDTH;
    localparam integer ADMIT_BANK_W = 2;
    localparam integer ADMIT_ROWS   = ISSUE_DEPTH / ADMIT_BANKS;
    localparam integer ADMIT_ROW_W  = 3;
    localparam integer RETURN_FUTURE_DEPTH = `PPE_RETURN_FUTURE_DEPTH;

    reg [1:0]         issue_state_q          [0:ISSUE_DEPTH-1];
    reg [SEQ_W-1:0]   issue_seq_tag_q        [0:ISSUE_DEPTH-1];
    reg [SEQ_W-1:0]   issue_target_seq_tag_q [0:ISSUE_DEPTH-1];
    reg [DELAY_W-1:0] issue_delay_q          [0:ISSUE_DEPTH-1];
    reg               issue_dep_required_q   [0:ISSUE_DEPTH-1];

    reg [CAND_WINDOW_DEPTH-1:0] candidate_valid_q;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_valid_d;
    reg [SEQ_W-1:0] candidate_seq_tag_q [0:CAND_WINDOW_DEPTH-1];
    reg [SEQ_W-1:0] candidate_seq_tag_d [0:CAND_WINDOW_DEPTH-1];
    reg [SEQ_W-1:0] candidate_target_seq_tag_q
        [0:CAND_WINDOW_DEPTH-1];
    reg [SEQ_W-1:0] candidate_target_seq_tag_d
        [0:CAND_WINDOW_DEPTH-1];
    reg [DELAY_W-1:0] candidate_delay_q [0:CAND_WINDOW_DEPTH-1];
    reg [DELAY_W-1:0] candidate_delay_d [0:CAND_WINDOW_DEPTH-1];
    reg [CAND_WINDOW_DEPTH-1:0] candidate_dep_required_q;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_dep_required_d;
    reg [ISSUE_DEPTH-1:0] candidate_present_q;
    reg [ISSUE_DEPTH-1:0] candidate_present_d;

    reg [FE_NUM-1:0] selected_valid_q;
    reg [SEQ_W-1:0] selected_seq_tag_q [0:FE_NUM-1];
    reg [DELAY_W-1:0] selected_delay_q [0:FE_NUM-1];
    reg [FE_NUM-1:0] selected_dep_required_q;
    reg [PACKET_W-1:0] selected_packet_q [0:FE_NUM-1];
    reg [PACKET_W-1:0] selected_dep_data_q [0:FE_NUM-1];

    reg [ISSUE_DEPTH-1:0] wake_hit;
    reg [ADMIT_BANKS-1:0] alloc_bank_write_en;
    reg [ADMIT_ROW_W-1:0] alloc_bank_row [0:ADMIT_BANKS-1];
    reg [SEQ_W-1:0] alloc_bank_seq_tag [0:ADMIT_BANKS-1];
    reg [DELAY_W-1:0] alloc_bank_delay [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] alloc_bank_dep_required;
    reg [ISSUE_DEPTH-1:0] alloc_entry_write_en;
    reg [SEQ_W-1:0] alloc_entry_seq_tag [0:ISSUE_DEPTH-1];
    reg [DELAY_W-1:0] alloc_entry_delay [0:ISSUE_DEPTH-1];
    reg [ISSUE_DEPTH-1:0] alloc_entry_dep_required;

    reg [N-1:0] dep_status_valid_q;
    reg [SEQ_W-1:0] dep_status_target_seq_tag_q [0:N-1];
    reg [SEQ_W-1:0] dep_status_consumer_seq_tag_q [0:N-1];
    reg [ROB_ID_W-1:0] dep_status_consumer_id_q [0:N-1];
    reg [ISSUE_DEPTH-1:0] dep_status_pending_entry;
    reg [ISSUE_DEPTH-1:0] dep_status_available_entry;
    reg [SEQ_W-1:0] dep_status_target_entry [0:ISSUE_DEPTH-1];

    reg [MAX_DEP-1:0] waiter_q [0:ISSUE_DEPTH-1];
    reg [MAX_DEP-1:0] waiter_set [0:ISSUE_DEPTH-1];
    reg [N-1:0] waiter_set_valid;
    reg [ROB_ID_W-1:0] waiter_set_producer_id [0:N-1];
    reg [MAX_DEP-1:0] waiter_set_offset [0:N-1];
    reg [MAX_DEP-1:0] waiter_take [0:ISSUE_DEPTH-1];
    reg [ISSUE_DEPTH-1:0] waiter_clear;
    reg [ISSUE_DEPTH-1:0] early_wake_hit_d;
    reg [ISSUE_DEPTH-1:0] early_wake_hit_q;
    reg [ISSUE_DEPTH-1:0] early_wake_delay_d;
    reg [ISSUE_DEPTH-1:0] early_wake_delay_q;

    reg [ISSUE_DEPTH-1:0] selected_release_hit;
    reg [ISSUE_DEPTH-1:0] eligible_ready;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_remove;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_pending;
    reg [ISSUE_DEPTH-1:0] select_entry_hit;
    reg [ROB_ID_W-1:0] select_entry_id [0:FE_NUM-1];

    reg [ADMIT_ROWS-1:0] bank_ready [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] bank_winner_valid;
    reg [ADMIT_ROW_W-1:0] bank_winner_row [0:ADMIT_BANKS-1];
    reg [SEQ_W-1:0] bank_winner_seq_tag [0:ADMIT_BANKS-1];
    reg [SEQ_W-1:0] bank_winner_target_seq_tag [0:ADMIT_BANKS-1];
    reg [DELAY_W-1:0] bank_winner_delay [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] bank_winner_dep_required;

    reg [FE_NUM-1:0] shortlist_valid_d;
    reg [CAND_WINDOW_DEPTH-1:0] shortlist_onehot_d [0:FE_NUM-1];
    reg [SEQ_W-1:0] shortlist_seq_tag_d [0:FE_NUM-1];
    reg [SEQ_W-1:0] shortlist_target_seq_tag_d [0:FE_NUM-1];
    reg [DELAY_W-1:0] shortlist_delay_d [0:FE_NUM-1];
    reg [FE_NUM-1:0] shortlist_dep_required_d;
    reg [1:0] shortlist_legal [0:FE_NUM-1];
    reg [2:0] shortlist_pending_block [0:FE_NUM-1];
    reg [1:0] candidate_legal [0:CAND_WINDOW_DEPTH-1];
    reg [2:0] candidate_pending_block [0:CAND_WINDOW_DEPTH-1];
    reg [FE_NUM-1:0] grant_valid_d;
    reg [CAND_WINDOW_DEPTH-1:0] grant_onehot_d;
    reg [SEQ_W-1:0] grant_seq_tag_d [0:FE_NUM-1];
    reg [SEQ_W-1:0] grant_target_seq_tag_d [0:FE_NUM-1];
    reg [DELAY_W-1:0] grant_delay_d [0:FE_NUM-1];
    reg [FE_NUM-1:0] grant_dep_required_d;
    reg [2:0] grant_pending_block_d [0:FE_NUM-1];
    reg [FE_NUM-1:0] grant_valid_q;
    reg [CAND_WINDOW_DEPTH-1:0] grant_onehot_q;
    reg [SEQ_W-1:0] grant_seq_tag_q [0:FE_NUM-1];
    reg [SEQ_W-1:0] grant_target_seq_tag_q [0:FE_NUM-1];
    reg [DELAY_W-1:0] grant_delay_q [0:FE_NUM-1];
    reg [FE_NUM-1:0] grant_dep_required_q;
    reg [2:0] grant_pending_block_q [0:FE_NUM-1];
    reg [ADMIT_ROW_W-1:0] source_bank_row_d [0:ADMIT_BANKS-1];
    reg [ROB_TAG_HI_W-1:0] source_bank_tag_hi_d [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] source_bank_update_en;
    reg [RETURN_FUTURE_DEPTH-1:0] future_valid_q [0:FE_NUM-1];
    reg [SEQ_W-1:0] future_seq_tag_q [0:FE_NUM-1]
                                     [0:RETURN_FUTURE_DEPTH-1];
    reg [FE_NUM-1:0] candidate_way_rr_q;
    reg [1:0] group_rr_q;

    // {candidate1->FE1, candidate1->FE0,
    //  candidate0->FE1, candidate0->FE0}
    function [3:0] local_pair_match;
        input       valid0;
        input       valid1;
        input [1:0] legal0;
        input [1:0] legal1;
        input       rr;
        reg         straight;
        reg         cross_map;
        begin
            local_pair_match = 4'b0000;
            straight = valid0 && valid1 && legal0[0] && legal1[1];
            cross_map = valid0 && valid1 && legal0[1] && legal1[0];

            if (straight || cross_map) begin
                if (straight && (!cross_map || !rr)) begin
                    local_pair_match[0] = 1'b1;
                    local_pair_match[3] = 1'b1;
                end else begin
                    local_pair_match[1] = 1'b1;
                    local_pair_match[2] = 1'b1;
                end
            end else if (!rr) begin
                if (valid0 && (|legal0)) begin
                    if (legal0[0]) local_pair_match[0] = 1'b1;
                    else           local_pair_match[1] = 1'b1;
                end else if (valid1 && (|legal1)) begin
                    if (legal1[1]) local_pair_match[3] = 1'b1;
                    else           local_pair_match[2] = 1'b1;
                end
            end else begin
                if (valid1 && (|legal1)) begin
                    if (legal1[0]) local_pair_match[2] = 1'b1;
                    else           local_pair_match[3] = 1'b1;
                end else if (valid0 && (|legal0)) begin
                    if (legal0[1]) local_pair_match[1] = 1'b1;
                    else           local_pair_match[0] = 1'b1;
                end
            end
        end
    endfunction

    function [ADMIT_ROW_W:0] select_ready_row;
        input [ADMIT_ROWS-1:0] ready;
        input [ADMIT_ROW_W-1:0] start;
        reg found;
        reg [ADMIT_ROW_W-1:0] row;
        begin
            found = 1'b1;
            row   = {ADMIT_ROW_W{1'b0}};
            case (start)
                3'd0: begin
                    if      (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else found = 1'b0;
                end
                3'd1: begin
                    if      (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else found = 1'b0;
                end
                3'd2: begin
                    if      (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else found = 1'b0;
                end
                3'd3: begin
                    if      (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else found = 1'b0;
                end
                3'd4: begin
                    if      (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else found = 1'b0;
                end
                3'd5: begin
                    if      (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else found = 1'b0;
                end
                3'd6: begin
                    if      (ready[6]) row = 3'd6;
                    else if (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else found = 1'b0;
                end
                default: begin
                    if      (ready[7]) row = 3'd7;
                    else if (ready[0]) row = 3'd0;
                    else if (ready[1]) row = 3'd1;
                    else if (ready[2]) row = 3'd2;
                    else if (ready[3]) row = 3'd3;
                    else if (ready[4]) row = 3'd4;
                    else if (ready[5]) row = 3'd5;
                    else if (ready[6]) row = 3'd6;
                    else found = 1'b0;
                end
            endcase
            select_ready_row = {found, row};
        end
    endfunction

    always @* begin : allocation_bank_route
        integer bank;
        integer lane;
        reg lane_hit;

        alloc_bank_write_en     = {ADMIT_BANKS{1'b0}};
        alloc_bank_dep_required = {ADMIT_BANKS{1'b0}};
        lane_hit                = 1'b0;

        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            alloc_bank_row[bank]     = {ADMIT_ROW_W{1'b0}};
            alloc_bank_seq_tag[bank] = {SEQ_W{1'b0}};
            alloc_bank_delay[bank]   = {DELAY_W{1'b0}};
            for (lane = 0; lane < N; lane = lane + 1) begin
                lane_hit =
                    issue_alloc_valid_i[lane]
                    && (alloc_seq_tag_i[lane][ADMIT_BANK_W-1:0]
                        == bank[ADMIT_BANK_W-1:0]);
                alloc_bank_write_en[bank] =
                    alloc_bank_write_en[bank] | lane_hit;
                alloc_bank_row[bank] =
                    alloc_bank_row[bank]
                    | (alloc_seq_tag_i[lane][
                            ADMIT_BANK_W +: ADMIT_ROW_W]
                       & {ADMIT_ROW_W{lane_hit}});
                alloc_bank_seq_tag[bank] =
                    alloc_bank_seq_tag[bank]
                    | (alloc_seq_tag_i[lane]
                       & {SEQ_W{lane_hit}});
                alloc_bank_delay[bank] =
                    alloc_bank_delay[bank]
                    | (alloc_delay_i[lane]
                       & {DELAY_W{lane_hit}});
                alloc_bank_dep_required[bank] =
                    alloc_bank_dep_required[bank]
                    | (alloc_dep_required_i[lane] & lane_hit);
            end
        end
    end

    always @* begin : allocation_row_decode
        integer bank;
        integer row;
        integer entry;

        alloc_entry_write_en     = {ISSUE_DEPTH{1'b0}};
        alloc_entry_dep_required = {ISSUE_DEPTH{1'b0}};
        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            alloc_entry_seq_tag[entry] = {SEQ_W{1'b0}};
            alloc_entry_delay[entry]   = {DELAY_W{1'b0}};
        end

        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            for (row = 0; row < ADMIT_ROWS; row = row + 1) begin
                entry = (row * ADMIT_BANKS) + bank;
                alloc_entry_write_en[entry] =
                    alloc_bank_write_en[bank]
                    && (alloc_bank_row[bank]
                        == row[ADMIT_ROW_W-1:0]);
                alloc_entry_seq_tag[entry] = alloc_bank_seq_tag[bank];
                alloc_entry_delay[entry] = alloc_bank_delay[bank];
                alloc_entry_dep_required[entry] =
                    alloc_bank_dep_required[bank];
            end
        end
    end

    always @* begin : dependency_status_request
        integer lane;

        dep_status_valid_o          = {N{1'b0}};
        for (lane = 0; lane < N; lane = lane + 1) begin
            dep_status_valid_o[lane] = dep_status_valid_q[lane];
            dep_status_target_seq_tag_o[lane] = {SEQ_W{1'b0}};
            if (dep_status_valid_q[lane]) begin
                dep_status_target_seq_tag_o[lane] =
                    dep_status_target_seq_tag_q[lane];
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni)
        begin : dependency_status_pipeline
        integer lane;

        if (!rst_ni) begin
            dep_status_valid_q <= {N{1'b0}};
        end else begin
            for (lane = 0; lane < N; lane = lane + 1) begin
                dep_status_valid_q[lane] <=
                    issue_alloc_valid_i[lane]
                    && alloc_dep_required_i[lane];
                if (issue_alloc_valid_i[lane]
                    && alloc_dep_required_i[lane]) begin
                    dep_status_target_seq_tag_q[lane] <=
                        alloc_target_seq_tag_i[lane];
                    dep_status_consumer_seq_tag_q[lane] <=
                        alloc_seq_tag_i[lane];
                    dep_status_consumer_id_q[lane] <=
                        alloc_seq_tag_i[lane][ROB_ID_W-1:0];
                end
            end
        end
    end

    always @* begin : reverse_waiter_registration
        integer lane;
        integer producer;

        waiter_set_valid = {N{1'b0}};
        for (lane = 0; lane < N; lane = lane + 1) begin
            waiter_set_producer_id[lane] =
                dep_status_target_seq_tag_q[lane][ROB_ID_W-1:0];
            waiter_set_offset[lane] = {MAX_DEP{1'b0}};
            if (dep_status_valid_q[lane]
                && !dep_status_available_i[lane]) begin
                waiter_set_valid[lane] = 1'b1;
                case (dep_status_consumer_seq_tag_q[lane]
                      - dep_status_target_seq_tag_q[lane])
                    6'd1: waiter_set_offset[lane][0] = 1'b1;
                    6'd2: waiter_set_offset[lane][1] = 1'b1;
                    6'd3: waiter_set_offset[lane][2] = 1'b1;
                    6'd4: waiter_set_offset[lane][3] = 1'b1;
                    6'd5: waiter_set_offset[lane][4] = 1'b1;
                    6'd6: waiter_set_offset[lane][5] = 1'b1;
                    6'd7: waiter_set_offset[lane][6] = 1'b1;
                    default: waiter_set_valid[lane] = 1'b0;
                endcase
            end
        end

        for (producer = 0; producer < ISSUE_DEPTH;
             producer = producer + 1) begin
            waiter_set[producer] = {MAX_DEP{1'b0}};
            for (lane = 0; lane < N; lane = lane + 1) begin
                if (waiter_set_valid[lane]
                    && (waiter_set_producer_id[lane]
                        == producer[ROB_ID_W-1:0])) begin
                    waiter_set[producer] = waiter_set[producer]
                                                 | waiter_set_offset[lane];
                end
            end
        end
    end

    always @* begin : reverse_waiter_early_wakeup
        integer fe;
        integer offset;
        integer producer;

        early_wake_hit_d   = {ISSUE_DEPTH{1'b0}};
        early_wake_delay_d = {ISSUE_DEPTH{1'b0}};
        for (producer = 0; producer < ISSUE_DEPTH;
             producer = producer + 1) begin
            waiter_take[producer] = {MAX_DEP{1'b0}};
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (grant_valid_q[fe]
                    && (grant_seq_tag_q[fe][ROB_ID_W-1:0]
                        == producer[ROB_ID_W-1:0])
                    && (issue_seq_tag_q[producer]
                        == grant_seq_tag_q[fe])) begin
                    waiter_take[producer] = waiter_take[producer]
                                                   | waiter_q[producer];
                    for (offset = 1; offset <= MAX_DEP;
                         offset = offset + 1) begin
                        if (waiter_q[producer][offset-1]) begin
                            if (grant_delay_q[fe] == 2'd3) begin
                                early_wake_delay_d[
                                    (producer + offset) % ISSUE_DEPTH] = 1'b1;
                            end else begin
                                early_wake_hit_d[
                                    (producer + offset) % ISSUE_DEPTH] = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end

    always @* begin : reverse_waiter_clear_decode
        integer fe;
        integer producer;

        waiter_clear = alloc_entry_write_en;
        for (producer = 0; producer < ISSUE_DEPTH;
             producer = producer + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (completion_valid_i[fe]
                    && (completion_seq_tag_i[fe][ROB_ID_W-1:0]
                        == producer[ROB_ID_W-1:0])
                    && (issue_seq_tag_q[producer]
                        == completion_seq_tag_i[fe])) begin
                    waiter_clear[producer] = 1'b1;
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : reverse_waiter_state
        integer producer;

        if (!rst_ni) begin
            early_wake_hit_q   <= {ISSUE_DEPTH{1'b0}};
            early_wake_delay_q <= {ISSUE_DEPTH{1'b0}};
            for (producer = 0; producer < ISSUE_DEPTH;
                 producer = producer + 1) begin
                waiter_q[producer] <= {MAX_DEP{1'b0}};
            end
        end else begin
            early_wake_hit_q   <= early_wake_hit_d | early_wake_delay_q;
            early_wake_delay_q <= early_wake_delay_d;
            for (producer = 0; producer < ISSUE_DEPTH;
                 producer = producer + 1) begin
                if (waiter_clear[producer]) begin
                    waiter_q[producer] <= {MAX_DEP{1'b0}};
                end else begin
                    waiter_q[producer] <=
                        (waiter_q[producer] & ~waiter_take[producer])
                        | waiter_set[producer];
                end
            end
        end
    end

    always @* begin : dependency_status_pending_decode
        integer entry;
        integer lane;

        dep_status_pending_entry   = {ISSUE_DEPTH{1'b0}};
        dep_status_available_entry = {ISSUE_DEPTH{1'b0}};
        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            dep_status_target_entry[entry] = {SEQ_W{1'b0}};
        end
        for (lane = 0; lane < N; lane = lane + 1) begin
            if (dep_status_valid_q[lane]) begin
                dep_status_pending_entry[
                    dep_status_consumer_id_q[lane]] = 1'b1;
                dep_status_available_entry[
                    dep_status_consumer_id_q[lane]] =
                    dep_status_available_i[lane];
                dep_status_target_entry[
                    dep_status_consumer_id_q[lane]] =
                    dep_status_target_seq_tag_q[lane];
            end
        end
    end

    always @* begin : selected_release_decode
        integer entry;
        integer fe;

        selected_release_hit = {ISSUE_DEPTH{1'b0}};
        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (selected_valid_q[fe]
                    && (selected_seq_tag_q[fe][ROB_ID_W-1:0]
                        == entry[ROB_ID_W-1:0])) begin
                    selected_release_hit[entry] = 1'b1;
                end
            end
        end
    end

    always @* begin : completion_wakeup_scan
        integer entry;
        integer fe;

        wake_hit = {ISSUE_DEPTH{1'b0}};
        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (completion_valid_i[fe]
                    && (issue_state_q[entry] == ISSUE_WAIT_DEP)
                    && !dep_status_pending_entry[entry]
                    && (issue_target_seq_tag_q[entry]
                        == completion_seq_tag_i[fe])) begin
                    wake_hit[entry] = 1'b1;
                end
            end
        end
    end

    always @* begin : candidate_way_legality
        integer bank;
        integer slot;
        integer way;
        integer fe;
        reg [1:0] legal;

        legal                   = 2'b00;

        for (slot = 0; slot < CAND_WINDOW_DEPTH; slot = slot + 1) begin
            candidate_legal[slot] = 2'b00;
            candidate_pending_block[slot] = 3'b000;
        end

        for (bank = 0; bank < FE_NUM; bank = bank + 1) begin
            for (way = 0; way < 2; way = way + 1) begin
                slot  = (way * FE_NUM) + bank;
                legal = 2'b00;
                case (candidate_delay_q[slot])
                    2'd0: begin
                        for (fe = 0; fe < 2; fe = fe + 1) begin
                            if ((bank == 0) || (bank == 2)) begin
                                legal[fe] = !future_valid_q[fe][3]
                                    && !grant_pending_block_q[fe][0];
                            end else begin
                                legal[fe] = !future_valid_q[fe+2][3]
                                    && !grant_pending_block_q[fe+2][0];
                            end
                        end
                    end
                    2'd1: begin
                        candidate_pending_block[slot][0] = 1'b1;
                        for (fe = 0; fe < 2; fe = fe + 1) begin
                            if ((bank == 0) || (bank == 2)) begin
                                legal[fe] = !future_valid_q[fe][4]
                                    && !grant_pending_block_q[fe][1];
                            end else begin
                                legal[fe] = !future_valid_q[fe+2][4]
                                    && !grant_pending_block_q[fe+2][1];
                            end
                        end
                    end
                    2'd2: begin
                        candidate_pending_block[slot][1] = 1'b1;
                        for (fe = 0; fe < 2; fe = fe + 1) begin
                            if ((bank == 0) || (bank == 2)) begin
                                legal[fe] = !future_valid_q[fe][5]
                                    && !grant_pending_block_q[fe][2];
                            end else begin
                                legal[fe] = !future_valid_q[fe+2][5]
                                    && !grant_pending_block_q[fe+2][2];
                            end
                        end
                    end
                    default: begin
                        legal = 2'b11;
                        candidate_pending_block[slot][2] = 1'b1;
                    end
                endcase
                candidate_legal[slot] = legal;
            end
        end
    end

    always @* begin : candidate_shortlist
        integer bank;
        integer slot;
        reg way0_available;
        reg way1_available;
        reg way0_legal;
        reg way1_legal;

        shortlist_valid_d        = {FE_NUM{1'b0}};
        shortlist_dep_required_d = {FE_NUM{1'b0}};
        candidate_pending        = grant_onehot_q;
        way0_available           = 1'b0;
        way1_available           = 1'b0;
        way0_legal               = 1'b0;
        way1_legal               = 1'b0;

        for (bank = 0; bank < FE_NUM; bank = bank + 1) begin
            shortlist_seq_tag_d[bank]        = {SEQ_W{1'b0}};
            shortlist_target_seq_tag_d[bank] = {SEQ_W{1'b0}};
            shortlist_delay_d[bank]          = {DELAY_W{1'b0}};
            shortlist_onehot_d[bank]         = {CAND_WINDOW_DEPTH{1'b0}};
            shortlist_legal[bank]            = 2'b00;
            shortlist_pending_block[bank]    = 3'b000;
            way0_available = candidate_valid_q[bank]
                && !candidate_pending[bank];
            way1_available = candidate_valid_q[FE_NUM+bank]
                && !candidate_pending[FE_NUM+bank];
            way0_legal = way0_available
                && (|candidate_legal[bank]);
            way1_legal = way1_available
                && (|candidate_legal[FE_NUM+bank]);
            slot = bank;
            if (way1_legal
                && (!way0_legal || candidate_way_rr_q[bank])) begin
                slot = FE_NUM + bank;
            end

            if (way0_legal || way1_legal) begin
                shortlist_valid_d[bank] = 1'b1;
                shortlist_onehot_d[bank][slot] = 1'b1;
                shortlist_seq_tag_d[bank] = candidate_seq_tag_q[slot];
                shortlist_target_seq_tag_d[bank] =
                    candidate_target_seq_tag_q[slot];
                shortlist_delay_d[bank] = candidate_delay_q[slot];
                shortlist_dep_required_d[bank] =
                    candidate_dep_required_q[slot];
                shortlist_legal[bank] = candidate_legal[slot];
                shortlist_pending_block[bank] =
                    candidate_pending_block[slot];
            end
        end
    end

    always @* begin : fixed_local_pair_match
        integer candidate;
        integer fe;
        reg [FE_NUM-1:0] accept [0:FE_NUM-1];
        reg [3:0] even_match;
        reg [3:0] odd_match;

        for (candidate = 0; candidate < FE_NUM;
             candidate = candidate + 1) begin
            accept[candidate] = {FE_NUM{1'b0}};
        end
        even_match        = local_pair_match(
            shortlist_valid_d[0], shortlist_valid_d[2],
            shortlist_legal[0], shortlist_legal[2], group_rr_q[0]);
        odd_match         = local_pair_match(
            shortlist_valid_d[1], shortlist_valid_d[3],
            shortlist_legal[1], shortlist_legal[3], group_rr_q[1]);

        accept[0][0] = even_match[0];
        accept[0][1] = even_match[1];
        accept[2][0] = even_match[2];
        accept[2][1] = even_match[3];
        accept[1][2] = odd_match[0];
        accept[1][3] = odd_match[1];
        accept[3][2] = odd_match[2];
        accept[3][3] = odd_match[3];

        grant_valid_d     = {FE_NUM{1'b0}};
        grant_onehot_d    = {CAND_WINDOW_DEPTH{1'b0}};
        grant_dep_required_d = {FE_NUM{1'b0}};
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            grant_seq_tag_d[fe]        = {SEQ_W{1'b0}};
            grant_target_seq_tag_d[fe] = {SEQ_W{1'b0}};
            grant_delay_d[fe]          = {DELAY_W{1'b0}};
            grant_pending_block_d[fe]  = 3'b000;
        end

        for (fe = 0; fe < FE_NUM; fe = fe + 1)
            for (candidate = 0; candidate < FE_NUM;
                 candidate = candidate + 1)
                if (accept[candidate][fe]) begin
                    grant_valid_d[fe] = 1'b1;
                    grant_onehot_d = grant_onehot_d
                        | shortlist_onehot_d[candidate];
                    grant_pending_block_d[fe] =
                        shortlist_pending_block[candidate];
                    grant_seq_tag_d[fe] = shortlist_seq_tag_d[candidate];
                    grant_target_seq_tag_d[fe] =
                        shortlist_target_seq_tag_d[candidate];
                    grant_delay_d[fe] = shortlist_delay_d[candidate];
                    grant_dep_required_d[fe] =
                        shortlist_dep_required_d[candidate];
                end
    end

    always @* begin : source_bank_request_decode
        integer bank;
        integer fe;
        reg [DATA_BANK_W-1:0] source_bank;

        source_bank_update_en = {ADMIT_BANKS{1'b0}};
        source_bank = {DATA_BANK_W{1'b0}};
        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            source_bank_row_d[bank] = {ADMIT_ROW_W{1'b0}};
            source_bank_tag_hi_d[bank] = {ROB_TAG_HI_W{1'b0}};
        end
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            source_bank = grant_seq_tag_d[fe][DATA_BANK_W-1:0];
            if (grant_valid_d[fe]) begin
                source_bank_update_en[source_bank] = 1'b1;
                source_bank_row_d[source_bank] =
                    grant_seq_tag_d[fe][DATA_BANK_W +: ADMIT_ROW_W];
                source_bank_tag_hi_d[source_bank] =
                    grant_seq_tag_d[fe][ROB_ID_W +: ROB_TAG_HI_W];
            end
        end
    end

    always @* begin : candidate_removal_decode
        integer fe;
        integer entry;

        candidate_remove = grant_onehot_q;
        select_entry_hit = {ISSUE_DEPTH{1'b0}};
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            select_entry_id[fe]       = {ROB_ID_W{1'b0}};
            if (grant_valid_q[fe]) begin
                select_entry_id[fe] =
                    grant_seq_tag_q[fe][ROB_ID_W-1:0];
            end
        end

        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (grant_valid_q[fe]
                    && (select_entry_id[fe]
                        == entry[ROB_ID_W-1:0])) begin
                    select_entry_hit[entry] = 1'b1;
                end
            end
        end
    end

    always @* begin : ready_eligibility
        integer entry;
        integer bank;
        integer row;

        eligible_ready = {ISSUE_DEPTH{1'b0}};
        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            bank_ready[bank] = {ADMIT_ROWS{1'b0}};
        end

        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            eligible_ready[entry] =
                (issue_state_q[entry] == ISSUE_READY)
                && !candidate_present_q[entry];
        end
        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            for (row = 0; row < ADMIT_ROWS; row = row + 1) begin
                bank_ready[bank][row] =
                    eligible_ready[(row * ADMIT_BANKS) + bank];
            end
        end
    end

    always @* begin : ready_bank_nomination
        integer bank;
        reg vacancy;
        reg [ADMIT_ROW_W:0] row_select;
        reg [ROB_ID_W-1:0] winner_id;

        bank_winner_valid        = {ADMIT_BANKS{1'b0}};
        bank_winner_dep_required = {ADMIT_BANKS{1'b0}};
        vacancy   = 1'b0;
        row_select = {(ADMIT_ROW_W+1){1'b0}};
        winner_id = {ROB_ID_W{1'b0}};

        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            vacancy =
                !candidate_valid_q[bank]
                || !candidate_valid_q[ADMIT_BANKS+bank]
                || candidate_remove[bank]
                || candidate_remove[ADMIT_BANKS+bank];
            bank_winner_seq_tag[bank] = {SEQ_W{1'b0}};
            bank_winner_target_seq_tag[bank] = {SEQ_W{1'b0}};
            bank_winner_delay[bank] = {DELAY_W{1'b0}};
            bank_winner_row[bank] = {ADMIT_ROW_W{1'b0}};
            row_select = select_ready_row(
                bank_ready[bank],
                ready_bank_head_row_i[bank]);
            winner_id  = {ROB_ID_W{1'b0}};

            if (vacancy) begin
                bank_winner_valid[bank] = row_select[ADMIT_ROW_W];
                bank_winner_row[bank] =
                    row_select[ADMIT_ROW_W-1:0];
                winner_id =
                    {bank_winner_row[bank],
                     bank[ADMIT_BANK_W-1:0]};
                if (bank_winner_valid[bank]) begin
                    bank_winner_seq_tag[bank] =
                        issue_seq_tag_q[winner_id];
                    bank_winner_target_seq_tag[bank] =
                        issue_target_seq_tag_q[winner_id];
                    bank_winner_delay[bank] =
                        issue_delay_q[winner_id];
                    bank_winner_dep_required[bank] =
                        issue_dep_required_q[winner_id];
                end else if (alloc_bank_write_en[bank]
                             && !alloc_bank_dep_required[bank]) begin
                    bank_winner_valid[bank] = 1'b1;
                    bank_winner_row[bank] = alloc_bank_row[bank];
                    bank_winner_seq_tag[bank] =
                        alloc_bank_seq_tag[bank];
                    bank_winner_target_seq_tag[bank] = {SEQ_W{1'b0}};
                    bank_winner_delay[bank] = alloc_bank_delay[bank];
                    bank_winner_dep_required[bank] = 1'b0;
                end
            end
        end
    end

    always @* begin : candidate_bank_next
        integer slot;
        integer bank;
        reg [CAND_ID_W-1:0] fill_slot;
        reg fill_valid;

        candidate_valid_d = candidate_valid_q;
        candidate_present_d = candidate_present_q & ~select_entry_hit;
        candidate_dep_required_d = candidate_dep_required_q;
        fill_slot  = {CAND_ID_W{1'b0}};
        fill_valid = 1'b0;

        for (slot = 0; slot < CAND_WINDOW_DEPTH; slot = slot + 1) begin
            candidate_seq_tag_d[slot] = candidate_seq_tag_q[slot];
            candidate_target_seq_tag_d[slot] =
                candidate_target_seq_tag_q[slot];
            candidate_delay_d[slot] = candidate_delay_q[slot];
            if (candidate_remove[slot]) begin
                candidate_valid_d[slot] = 1'b0;
            end
        end

        for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
            fill_slot  = bank[CAND_ID_W-1:0];
            fill_valid = 1'b0;
            if (!candidate_valid_q[bank] || candidate_remove[bank]) begin
                fill_slot  = bank[CAND_ID_W-1:0];
                fill_valid = bank_winner_valid[bank];
            end else if (!candidate_valid_q[ADMIT_BANKS+bank]
                         || candidate_remove[ADMIT_BANKS+bank]) begin
                fill_slot = {1'b1, bank[ADMIT_BANK_W-1:0]};
                fill_valid = bank_winner_valid[bank];
            end

            if (fill_valid) begin
                candidate_valid_d[fill_slot] = 1'b1;
                candidate_seq_tag_d[fill_slot] =
                    bank_winner_seq_tag[bank];
                candidate_target_seq_tag_d[fill_slot] =
                    bank_winner_target_seq_tag[bank];
                candidate_delay_d[fill_slot] =
                    bank_winner_delay[bank];
                candidate_dep_required_d[fill_slot] =
                    bank_winner_dep_required[bank];
                candidate_present_d[
                    (bank_winner_row[bank] * ADMIT_BANKS) + bank] = 1'b1;
            end
        end
    end

    always @* begin : interface_outputs
        integer fe;

        gather_dep_required_o   = grant_dep_required_q;
        issue_valid_o           = selected_valid_q;
        issue_dep_required_o    = {FE_NUM{1'b0}};
        completion_valid_o      = {FE_NUM{1'b0}};

        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            gather_target_seq_tag_o[fe] = grant_target_seq_tag_q[fe];
            issue_packet_o[fe]          = {PACKET_W{1'b0}};
            issue_delay_o[fe]           = {DELAY_W{1'b0}};
            issue_dep_data_o[fe]        = {PACKET_W{1'b0}};
            completion_seq_tag_o[fe]    = {SEQ_W{1'b0}};
            if (selected_valid_q[fe]) begin
                issue_packet_o[fe] = selected_packet_q[fe];
                issue_delay_o[fe] = selected_delay_q[fe];
                issue_dep_required_o[fe] =
                    selected_dep_required_q[fe];
                issue_dep_data_o[fe] = selected_dep_data_q[fe];
            end
            completion_valid_o[fe] =
                fe_out_valid_i[fe] && future_valid_q[fe][0];
            if (future_valid_q[fe][0]) begin
                completion_seq_tag_o[fe] = future_seq_tag_q[fe][0];
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : issue_entry_state
        integer entry;

        if (!rst_ni) begin
            for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
                issue_state_q[entry] <= ISSUE_FREE;
            end
        end else begin
            for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
                if (selected_release_hit[entry]) begin
                    issue_state_q[entry] <= ISSUE_FREE;
                end
                if (wake_hit[entry]) begin
                    issue_state_q[entry] <= ISSUE_READY;
                end
                if (early_wake_hit_q[entry]
                    && (issue_state_q[entry] == ISSUE_WAIT_DEP)
                    && !dep_status_pending_entry[entry]) begin
                    issue_state_q[entry] <= ISSUE_READY;
                end
                if (dep_status_available_entry[entry]
                    && (issue_state_q[entry] == ISSUE_WAIT_DEP)) begin
                    issue_state_q[entry] <= ISSUE_READY;
                end
                if (select_entry_hit[entry]) begin
                    issue_state_q[entry] <= ISSUE_SELECTED;
                end
                if (alloc_entry_write_en[entry]) begin
                    issue_state_q[entry] <=
                        alloc_entry_dep_required[entry]
                        ? ISSUE_WAIT_DEP : ISSUE_READY;
                end
            end
        end
    end

    always @(posedge clk_i) begin : issue_entry_metadata
        integer entry;

        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            if (alloc_entry_write_en[entry]) begin
                issue_seq_tag_q[entry] <= alloc_entry_seq_tag[entry];
                issue_delay_q[entry] <= alloc_entry_delay[entry];
                issue_dep_required_q[entry] <=
                    alloc_entry_dep_required[entry];
            end
            if (dep_status_pending_entry[entry]) begin
                issue_target_seq_tag_q[entry] <=
                    dep_status_target_entry[entry];
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : selected_metadata
        integer fe;

        if (!rst_ni) begin
            selected_valid_q <= {FE_NUM{1'b0}};
        end else begin
            selected_valid_q <= grant_valid_q;
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                selected_seq_tag_q[fe] <= grant_seq_tag_q[fe];
                selected_delay_q[fe] <= grant_delay_q[fe];
                selected_dep_required_q[fe] <= grant_dep_required_q[fe];
                case (grant_seq_tag_q[fe][DATA_BANK_W-1:0])
                    2'd0: selected_packet_q[fe] <= source_bank_packet_i[0];
                    2'd1: selected_packet_q[fe] <= source_bank_packet_i[1];
                    2'd2: selected_packet_q[fe] <= source_bank_packet_i[2];
                    default:
                        selected_packet_q[fe] <= source_bank_packet_i[3];
                endcase
                selected_dep_data_q[fe] <= gather_dep_data_i[fe];
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : grant_state
        integer bank;
        integer fe;

        if (!rst_ni) begin
            grant_valid_q         <= {FE_NUM{1'b0}};
            grant_onehot_q        <= {CAND_WINDOW_DEPTH{1'b0}};
            grant_dep_required_q  <= {FE_NUM{1'b0}};
            candidate_way_rr_q    <= {FE_NUM{1'b0}};
            group_rr_q            <= 2'b00;
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                grant_pending_block_q[fe] <= 3'b000;
            end
        end else begin
            grant_valid_q         <= grant_valid_d;
            grant_onehot_q        <= grant_onehot_d;
            candidate_way_rr_q    <= ~candidate_way_rr_q;
            group_rr_q            <= ~group_rr_q;
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                grant_pending_block_q[fe] <= grant_pending_block_d[fe];
                if (grant_valid_d[fe]) begin
                    grant_seq_tag_q[fe] <= grant_seq_tag_d[fe];
                    grant_target_seq_tag_q[fe] <=
                        grant_target_seq_tag_d[fe];
                    grant_delay_q[fe] <= grant_delay_d[fe];
                    grant_dep_required_q[fe] <=
                        grant_dep_required_d[fe];
                end
            end
            for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
                if (source_bank_update_en[bank]) begin
                    source_bank_row_o[bank] <= source_bank_row_d[bank];
                    source_bank_tag_hi_o[bank] <=
                        source_bank_tag_hi_d[bank];
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : writeback_predecode
        integer fe;

        if (!rst_ni) begin
            wb_pre_valid_o <= {FE_NUM{1'b0}};
        end else begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                wb_pre_valid_o[fe] <= future_valid_q[fe][1];
                if (future_valid_q[fe][1]) begin
                    wb_pre_seq_tag_o[fe] <= future_seq_tag_q[fe][1];
                    wb_pre_entry_onehot_o[fe] <=
                        {{(ISSUE_DEPTH-1){1'b0}}, 1'b1}
                        << future_seq_tag_q[fe][1][ROB_ID_W-1:0];
                end
            end
        end
    end

    genvar future_fe;
    generate
        for (future_fe = 0; future_fe < FE_NUM;
             future_fe = future_fe + 1) begin : g_future_table
            integer slot;

            always @(posedge clk_i or negedge rst_ni) begin : state
                if (!rst_ni) begin
                    future_valid_q[future_fe] <=
                        {RETURN_FUTURE_DEPTH{1'b0}};
                end else begin
                    for (slot = 0; slot < RETURN_FUTURE_DEPTH-1;
                         slot = slot + 1) begin
                        future_valid_q[future_fe][slot] <=
                            future_valid_q[future_fe][slot+1];
                        if (future_valid_q[future_fe][slot+1]) begin
                            future_seq_tag_q[future_fe][slot] <=
                                future_seq_tag_q[future_fe][slot+1];
                        end
                    end
                    future_valid_q[future_fe]
                        [RETURN_FUTURE_DEPTH-1] <= 1'b0;
                    if (grant_valid_q[future_fe]) begin
                        case (grant_delay_q[future_fe])
                            2'd0: begin
                                future_valid_q[future_fe][1] <= 1'b1;
                                future_seq_tag_q[future_fe][1] <=
                                    grant_seq_tag_q[future_fe];
                            end
                            2'd1: begin
                                future_valid_q[future_fe][2] <= 1'b1;
                                future_seq_tag_q[future_fe][2] <=
                                    grant_seq_tag_q[future_fe];
                            end
                            2'd2: begin
                                future_valid_q[future_fe][3] <= 1'b1;
                                future_seq_tag_q[future_fe][3] <=
                                    grant_seq_tag_q[future_fe];
                            end
                            default: begin
                                future_valid_q[future_fe][4] <= 1'b1;
                                future_seq_tag_q[future_fe][4] <=
                                    grant_seq_tag_q[future_fe];
                            end
                        endcase
                    end
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_ni) begin : candidate_state
        integer slot;

        if (!rst_ni) begin
            candidate_valid_q <= {CAND_WINDOW_DEPTH{1'b0}};
            candidate_present_q <= {ISSUE_DEPTH{1'b0}};
            candidate_dep_required_q <= {CAND_WINDOW_DEPTH{1'b0}};
        end else begin
            candidate_valid_q <= candidate_valid_d;
            candidate_present_q <= candidate_present_d;
            candidate_dep_required_q <= candidate_dep_required_d;
            for (slot = 0; slot < CAND_WINDOW_DEPTH; slot = slot + 1) begin
                if (candidate_valid_d[slot]
                    && (!candidate_valid_q[slot]
                        || candidate_remove[slot]
                        || (candidate_seq_tag_d[slot]
                            != candidate_seq_tag_q[slot]))) begin
                    candidate_seq_tag_q[slot] <= candidate_seq_tag_d[slot];
                    candidate_target_seq_tag_q[slot] <=
                        candidate_target_seq_tag_d[slot];
                    candidate_delay_q[slot] <= candidate_delay_d[slot];
                end
            end
        end
    end

endmodule

`default_nettype wire
