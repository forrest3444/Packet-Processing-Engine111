`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// ROB-indexed pre-issue state, dependency wakeup, and local candidate banks.
//------------------------------------------------------------------------------
module PPE_ISSUE_TABLE #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W
) (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,
    input  wire [`PPE_N-1:0]                         issue_alloc_valid_i,
    input  wire [`PPE_N*`PPE_SEQ_W-1:0]              alloc_seq_tag_i,
    input  wire [`PPE_N*`PPE_SEQ_W-1:0]              alloc_target_seq_tag_i,
    input  wire [`PPE_N*`PPE_DELAY_W-1:0]            alloc_delay_i,
    input  wire [`PPE_N-1:0]                         alloc_dep_required_i,
    output reg  [`PPE_N-1:0]                         dep_status_valid_o,
    output reg  [`PPE_N*`PPE_SEQ_W-1:0]              dep_status_target_seq_tag_o,
    input  wire [`PPE_N-1:0]                         dep_status_available_i,
    input  wire [`PPE_FE_NUM-1:0]                    completion_valid_i,
    input  wire [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         completion_seq_tag_i,
    output reg  [`PPE_CAND_WINDOW_DEPTH-1:0]         candidate_valid_o,
    output reg  [`PPE_CAND_WINDOW_DEPTH*`PPE_SEQ_W-1:0]
                                                    candidate_seq_tag_o,
    output reg  [`PPE_CAND_WINDOW_DEPTH*`PPE_DELAY_W-1:0]
                                                    candidate_delay_o,
    input  wire [`PPE_FE_NUM-1:0]                    select_valid_i,
    input  wire [`PPE_FE_NUM*`PPE_CAND_WINDOW_DEPTH-1:0]
                                                    select_candidate_onehot_i,
    output reg  [`PPE_FE_NUM-1:0]                    prefetch_valid_o,
    output reg  [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         prefetch_seq_tag_o,
    output reg  [`PPE_FE_NUM-1:0]                    prefetch_dep_required_o,
    output reg  [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         prefetch_target_seq_tag_o,
    input  wire [`PPE_FE_NUM*PACKET_W-1:0]           prefetch_packet_i,
    input  wire [`PPE_FE_NUM*PACKET_W-1:0]           prefetch_dep_data_i,
    output reg  [`PPE_FE_NUM-1:0]                    issue_valid_o,
    output reg  [`PPE_FE_NUM*PACKET_W-1:0]           issue_packet_o,
    output reg  [`PPE_FE_NUM*`PPE_DELAY_W-1:0]       issue_delay_o,
    output reg  [`PPE_FE_NUM-1:0]                    issue_dep_required_o,
    output reg  [`PPE_FE_NUM*PACKET_W-1:0]           issue_dep_data_o
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

    localparam [1:0] ISSUE_FREE     = 2'd0;
    localparam [1:0] ISSUE_WAIT_DEP = 2'd1;
    localparam [1:0] ISSUE_READY    = 2'd2;
    localparam [1:0] ISSUE_SELECTED = 2'd3;

    localparam integer CAND_ID_W    = 3;
    localparam integer ADMIT_BANKS  = READY_ENQUEUE_WIDTH;
    localparam integer ADMIT_BANK_W = 2;
    localparam integer ADMIT_ROWS   = ISSUE_DEPTH / ADMIT_BANKS;
    localparam integer ADMIT_ROW_W  = 3;

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
    reg [PACKET_W-1:0] candidate_packet_q [0:CAND_WINDOW_DEPTH-1];
    reg [PACKET_W-1:0] candidate_dep_data_q
        [0:CAND_WINDOW_DEPTH-1];
    reg [CAND_WINDOW_DEPTH-1:0] candidate_data_valid_q;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_prefetch_visible;
    reg [CAND_ID_W-1:0] prefetch_slot_q [0:ADMIT_BANKS-1];

    reg [ISSUE_DEPTH-1:0] candidate_present_q;
    reg [ISSUE_DEPTH-1:0] candidate_present_d;
    reg [ADMIT_ROW_W-1:0] ready_admit_row_rr_q [0:ADMIT_BANKS-1];
    reg [ADMIT_ROW_W-1:0] ready_admit_row_rr_d [0:ADMIT_BANKS-1];

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
    reg [ROB_ID_W-1:0] dep_status_consumer_id_q [0:N-1];
    reg [ISSUE_DEPTH-1:0] dep_status_pending_entry;
    reg [ISSUE_DEPTH-1:0] dep_status_available_entry;
    reg [SEQ_W-1:0] dep_status_target_entry [0:ISSUE_DEPTH-1];

    reg [ISSUE_DEPTH-1:0] selected_release_hit;
    reg [ISSUE_DEPTH-1:0] eligible_ready;
    reg [CAND_WINDOW_DEPTH-1:0] candidate_remove;
    reg [ISSUE_DEPTH-1:0] select_entry_hit;
    reg [SEQ_W-1:0] select_seq_tag [0:FE_NUM-1];
    reg [DELAY_W-1:0] select_delay [0:FE_NUM-1];
    reg [FE_NUM-1:0] select_dep_required;
    reg [ROB_ID_W-1:0] select_entry_id [0:FE_NUM-1];
    reg [PACKET_W-1:0] select_packet [0:FE_NUM-1];
    reg [PACKET_W-1:0] select_dep_data [0:FE_NUM-1];

    reg [ADMIT_ROWS-1:0] bank_ready [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] bank_winner_valid;
    reg [ADMIT_ROW_W-1:0] bank_winner_row [0:ADMIT_BANKS-1];
    reg [SEQ_W-1:0] bank_winner_seq_tag [0:ADMIT_BANKS-1];
    reg [SEQ_W-1:0] bank_winner_target_seq_tag [0:ADMIT_BANKS-1];
    reg [DELAY_W-1:0] bank_winner_delay [0:ADMIT_BANKS-1];
    reg [ADMIT_BANKS-1:0] bank_winner_dep_required;
    reg [ADMIT_BANKS-1:0] candidate_fill_valid;
    reg [CAND_ID_W-1:0] candidate_fill_slot [0:ADMIT_BANKS-1];

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
                    && (alloc_seq_tag_i[
                            lane*SEQ_W +: ADMIT_BANK_W]
                        == bank[ADMIT_BANK_W-1:0]);
                alloc_bank_write_en[bank] =
                    alloc_bank_write_en[bank] | lane_hit;
                alloc_bank_row[bank] =
                    alloc_bank_row[bank]
                    | (alloc_seq_tag_i[
                            lane*SEQ_W+ADMIT_BANK_W +: ADMIT_ROW_W]
                       & {ADMIT_ROW_W{lane_hit}});
                alloc_bank_seq_tag[bank] =
                    alloc_bank_seq_tag[bank]
                    | (alloc_seq_tag_i[lane*SEQ_W +: SEQ_W]
                       & {SEQ_W{lane_hit}});
                alloc_bank_delay[bank] =
                    alloc_bank_delay[bank]
                    | (alloc_delay_i[lane*DELAY_W +: DELAY_W]
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
        dep_status_target_seq_tag_o = {N*SEQ_W{1'b0}};
        for (lane = 0; lane < N; lane = lane + 1) begin
            dep_status_valid_o[lane] = dep_status_valid_q[lane];
            if (dep_status_valid_q[lane]) begin
                dep_status_target_seq_tag_o[
                    lane*SEQ_W +: SEQ_W] =
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
                        alloc_target_seq_tag_i[
                            lane*SEQ_W +: SEQ_W];
                    dep_status_consumer_id_q[lane] <=
                        alloc_seq_tag_i[lane*SEQ_W +: ROB_ID_W];
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
                        == completion_seq_tag_i[
                            fe*SEQ_W +: SEQ_W])) begin
                    wake_hit[entry] = 1'b1;
                end
            end
        end
    end

    always @* begin : candidate_removal_decode
        integer fe;
        integer slot;
        integer entry;

        candidate_remove = {CAND_WINDOW_DEPTH{1'b0}};
        select_entry_hit = {ISSUE_DEPTH{1'b0}};
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            select_seq_tag[fe]        = {SEQ_W{1'b0}};
            select_delay[fe]          = {DELAY_W{1'b0}};
            select_dep_required[fe]   = 1'b0;
            select_entry_id[fe]       = {ROB_ID_W{1'b0}};
            select_packet[fe]         = {PACKET_W{1'b0}};
            select_dep_data[fe]       = {PACKET_W{1'b0}};
            if (select_valid_i[fe]) begin
                candidate_remove =
                    candidate_remove
                    | select_candidate_onehot_i[
                        fe*CAND_WINDOW_DEPTH +: CAND_WINDOW_DEPTH];
                for (slot = 0;
                     slot < CAND_WINDOW_DEPTH;
                     slot = slot + 1) begin
                    if (select_candidate_onehot_i[
                            fe*CAND_WINDOW_DEPTH+slot]) begin
                        select_seq_tag[fe] = candidate_seq_tag_q[slot];
                        select_entry_id[fe] =
                            candidate_seq_tag_q[slot][ROB_ID_W-1:0];
                        select_delay[fe] = candidate_delay_q[slot];
                        select_dep_required[fe] =
                            candidate_dep_required_q[slot];
                        select_packet[fe] = candidate_packet_q[slot];
                        select_dep_data[fe] =
                            candidate_dep_data_q[slot];
                    end
                end
            end
        end

        for (entry = 0; entry < ISSUE_DEPTH; entry = entry + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (select_valid_i[fe]
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
                bank_ready[bank], ready_admit_row_rr_q[bank]);
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
        candidate_fill_valid = {ADMIT_BANKS{1'b0}};
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
            candidate_fill_slot[bank] = bank[CAND_ID_W-1:0];
            ready_admit_row_rr_d[bank] =
                ready_admit_row_rr_q[bank] + 3'd1;

            if (!candidate_valid_q[bank] || candidate_remove[bank]) begin
                fill_slot  = bank[CAND_ID_W-1:0];
                fill_valid = bank_winner_valid[bank];
            end else if (!candidate_valid_q[ADMIT_BANKS+bank]
                         || candidate_remove[ADMIT_BANKS+bank]) begin
                fill_slot = {1'b1, bank[ADMIT_BANK_W-1:0]};
                fill_valid = bank_winner_valid[bank];
            end

            if (fill_valid) begin
                candidate_fill_valid[bank] = 1'b1;
                candidate_fill_slot[bank] = fill_slot;
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
                    bank_winner_seq_tag[bank][ROB_ID_W-1:0]] = 1'b1;
            end
        end
    end

    always @* begin : interface_outputs
        integer slot;
        integer fe;

        candidate_valid_o          = {CAND_WINDOW_DEPTH{1'b0}};
        candidate_seq_tag_o        = {CAND_WINDOW_DEPTH*SEQ_W{1'b0}};
        candidate_delay_o          = {CAND_WINDOW_DEPTH*DELAY_W{1'b0}};
        issue_valid_o              = selected_valid_q;
        issue_packet_o             = {FE_NUM*PACKET_W{1'b0}};
        issue_delay_o              = {FE_NUM*DELAY_W{1'b0}};
        issue_dep_required_o       = {FE_NUM{1'b0}};
        issue_dep_data_o           = {FE_NUM*PACKET_W{1'b0}};
        candidate_prefetch_visible = {CAND_WINDOW_DEPTH{1'b0}};

        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            if (prefetch_valid_o[fe]) begin
                candidate_prefetch_visible[prefetch_slot_q[fe]] = 1'b1;
            end
        end
        candidate_valid_o =
            candidate_valid_q
            & (candidate_data_valid_q | candidate_prefetch_visible);
        for (slot = 0; slot < CAND_WINDOW_DEPTH; slot = slot + 1) begin
            if (candidate_valid_q[slot]) begin
                candidate_seq_tag_o[slot*SEQ_W +: SEQ_W] =
                    candidate_seq_tag_q[slot];
                candidate_delay_o[slot*DELAY_W +: DELAY_W] =
                    candidate_delay_q[slot];
            end
        end
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            if (selected_valid_q[fe]) begin
                issue_packet_o[fe*PACKET_W +: PACKET_W] =
                    selected_packet_q[fe];
                issue_delay_o[fe*DELAY_W +: DELAY_W] =
                    selected_delay_q[fe];
                issue_dep_required_o[fe] =
                    selected_dep_required_q[fe];
                issue_dep_data_o[fe*PACKET_W +: PACKET_W] =
                    selected_dep_data_q[fe];
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : prefetch_request
        integer bank;

        if (!rst_ni) begin
            prefetch_valid_o <= {FE_NUM{1'b0}};
        end else begin
            prefetch_valid_o <= candidate_fill_valid;
            for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
                if (candidate_fill_valid[bank]) begin
                    prefetch_slot_q[bank] <= candidate_fill_slot[bank];
                    prefetch_seq_tag_o[bank*SEQ_W +: SEQ_W] <=
                        bank_winner_seq_tag[bank];
                    prefetch_dep_required_o[bank] <=
                        bank_winner_dep_required[bank];
                    prefetch_target_seq_tag_o[
                        bank*SEQ_W +: SEQ_W] <=
                        bank_winner_dep_required[bank]
                        ? bank_winner_target_seq_tag[bank]
                        : {SEQ_W{1'b0}};
                end
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
            selected_valid_q <= select_valid_i;
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                if (select_valid_i[fe]) begin
                    selected_seq_tag_q[fe] <= select_seq_tag[fe];
                    selected_delay_q[fe] <= select_delay[fe];
                    selected_dep_required_q[fe] <=
                        select_dep_required[fe];
                    selected_packet_q[fe] <= select_packet[fe];
                    selected_dep_data_q[fe] <= select_dep_data[fe];
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : candidate_state
        integer bank;
        integer slot;

        if (!rst_ni) begin
            candidate_valid_q <= {CAND_WINDOW_DEPTH{1'b0}};
            candidate_present_q <= {ISSUE_DEPTH{1'b0}};
            candidate_dep_required_q <= {CAND_WINDOW_DEPTH{1'b0}};
            for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
                ready_admit_row_rr_q[bank] <= {ADMIT_ROW_W{1'b0}};
            end
        end else begin
            candidate_valid_q <= candidate_valid_d;
            candidate_present_q <= candidate_present_d;
            candidate_dep_required_q <= candidate_dep_required_d;
            for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
                ready_admit_row_rr_q[bank] <= ready_admit_row_rr_d[bank];
            end
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

    always @(posedge clk_i or negedge rst_ni) begin : candidate_data
        integer bank;

        if (!rst_ni) begin
            candidate_data_valid_q <= {CAND_WINDOW_DEPTH{1'b0}};
        end else begin
            for (bank = 0; bank < ADMIT_BANKS; bank = bank + 1) begin
                if (prefetch_valid_o[bank]) begin
                    candidate_packet_q[prefetch_slot_q[bank]] <=
                        prefetch_packet_i[bank*PACKET_W +: PACKET_W];
                    if (prefetch_dep_required_o[bank]) begin
                        candidate_dep_data_q[prefetch_slot_q[bank]] <=
                            prefetch_dep_data_i[
                                bank*PACKET_W +: PACKET_W];
                    end
                    candidate_data_valid_q[prefetch_slot_q[bank]] <=
                        1'b1;
                end
                if (candidate_fill_valid[bank]) begin
                    candidate_data_valid_q[
                        candidate_fill_slot[bank]] <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
