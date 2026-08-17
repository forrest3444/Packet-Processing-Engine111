`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Active reorder buffer, authoritative dependency storage, and retirement.
//------------------------------------------------------------------------------
module PPE_ROB #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W
) (
    // Clock and reset.
    input  wire                                      clk_i,
    input  wire                                      rst_ni,

    // A0: capacity reservation request from the registered ingress head.
    input  wire [`PPE_N-1:0]                         alloc_reserve_valid_i,
    // A0: combinational ready decision for the exact requested batch.
    output reg                                       alloc_reserve_ready_o,

    // A1: committed allocation metadata and original packet from ingress.
    input  wire [`PPE_N-1:0]                         alloc_commit_valid_i,
    input  wire [`PPE_SEQ_W-1:0]                     alloc_seq_tag_i [0:`PPE_N-1],
    input  wire [PACKET_W-1:0]                       alloc_packet_i [0:`PPE_N-1],

    // D0C/G0: dependency-status query and availability response.
    input  wire [`PPE_N-1:0]                         dep_status_valid_i,
    input  wire [`PPE_SEQ_W-1:0]                     dep_status_target_seq_tag_i [0:`PPE_N-1],
    output reg  [`PPE_N-1:0]                         dep_status_available_o,

    // D2B/G0: bank-local original-packet gather request and response.
    input  wire [`PPE_ROB_BANK_ROW_W-1:0]            source_bank_row_i [0:`PPE_N-1],
    input  wire [`PPE_ROB_TAG_HI_W-1:0]              source_bank_tag_hi_i [0:`PPE_N-1],
    output reg  [PACKET_W-1:0]                       source_bank_packet_o [0:`PPE_N-1],

    // D2A/D2B/G0: dependency-data prefetch query and pipelined response.
    input  wire [`PPE_ISSUE_WIDTH-1:0]               gather_dep_required_i,
    input  wire [`PPE_SEQ_W-1:0]                     gather_target_seq_tag_i [0:`PPE_ISSUE_WIDTH-1],
    output wire [PACKET_W-1:0]                       gather_dep_data_o [0:`PPE_ISSUE_WIDTH-1],

    // W0: FE completion/writeback inputs, including one-cycle predecode hints.
    input  wire [`PPE_FE_NUM-1:0]                    wb_valid_i,
    input  wire [`PPE_SEQ_W-1:0]                     wb_seq_tag_i [0:`PPE_FE_NUM-1],
    input  wire [`PPE_SEQ_W-1:0]                     wb_pre_seq_tag_i [0:`PPE_FE_NUM-1],
    input  wire [`PPE_ROB_DEPTH-1:0]                 wb_pre_entry_onehot_i [0:`PPE_FE_NUM-1],
    input  wire [PACKET_W-1:0]                       wb_data_i [0:`PPE_FE_NUM-1],

    // D1/R0: bank age hints to Scheduler and dense in-order retire bundle.
    output wire [`PPE_ROB_BANK_ROW_W-1:0]            ready_bank_head_row_o [0:`PPE_N-1],
    output reg  [`PPE_N-1:0]                         retire_valid_o,
    output reg  [PACKET_W-1:0]                       retire_data_o [0:`PPE_N-1]
);

    localparam integer N                = `PPE_N;
    localparam integer FE_NUM           = `PPE_FE_NUM;
    localparam integer ROB_DEPTH        = `PPE_ROB_DEPTH;
    localparam integer ISSUE_WIDTH      = `PPE_ISSUE_WIDTH;
    localparam integer RESULT_BANKS     = `PPE_RESULT_BANKS;
    localparam integer SEQ_W            = `PPE_SEQ_W;
    localparam integer ROB_ID_W         = `PPE_ROB_ID_W;
    localparam integer HISTORY_ID_W     = `PPE_HISTORY_ID_W;
    localparam integer LANE_COUNT_W     = `PPE_LANE_COUNT_W;
    localparam integer OCCUPANCY_W      = `PPE_ROB_OCCUPANCY_W;
    localparam integer CAPACITY_EXT_W  = OCCUPANCY_W + 1;
    localparam [CAPACITY_EXT_W-1:0] ROB_DEPTH_EXT =
        ROB_DEPTH[CAPACITY_EXT_W-1:0];
    localparam [CAPACITY_EXT_W-1:0] ROB_CAPACITY_1 =
        ROB_DEPTH_EXT - {{(CAPACITY_EXT_W-1){1'b0}}, 1'b1};
    localparam [CAPACITY_EXT_W-1:0] ROB_CAPACITY_2 =
        ROB_DEPTH_EXT - {{(CAPACITY_EXT_W-2){1'b0}}, 2'd2};
    localparam [CAPACITY_EXT_W-1:0] ROB_CAPACITY_3 =
        ROB_DEPTH_EXT - {{(CAPACITY_EXT_W-2){1'b0}}, 2'd3};
    localparam [CAPACITY_EXT_W-1:0] ROB_CAPACITY_4 =
        ROB_DEPTH_EXT - {{(CAPACITY_EXT_W-3){1'b0}}, 3'd4};
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
    reg [PACKET_W-1:0] rob_data_q [0:DATA_BANK_NUM-1][0:DATA_ROW_NUM-1];

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
    reg [DATA_BANK_W-1:0] retire_head_bank_next;
    reg [DATA_ROW_W-1:0] retire_bank_row_q [0:DATA_BANK_NUM-1];
    wire [ROB_ID_W-1:0] head_ptr_q;
    reg [OCCUPANCY_W-1:0] occupancy_q;
    reg [LANE_COUNT_W-1:0] alloc_pending_retire_count_q;
    reg [LANE_COUNT_W-1:0] retire_count;
    reg [OCCUPANCY_W-1:0] occupancy_next;
    reg [LANE_COUNT_W-1:0] accepted_reserve_count;
    reg [CAPACITY_EXT_W-1:0] occupancy_after_retire_ext;
    reg [CAPACITY_EXT_W-1:0] occupancy_next_ext;

    reg [FE_NUM-1:0] wb_commit;
    reg [ROB_ID_W-1:0] wb_rob_id [0:FE_NUM-1];
    reg [ROB_ID_W-1:0] alloc_rob_id [0:N-1];
    reg [ROB_ID_W-1:0] retire_rob_id [0:N-1];

    genvar head_bank_idx;
    generate
        for (head_bank_idx = 0; head_bank_idx < DATA_BANK_NUM;
             head_bank_idx = head_bank_idx + 1) begin : gen_ready_bank_head
            assign ready_bank_head_row_o[head_bank_idx] =
                retire_bank_row_q[head_bank_idx];
        end
    endgenerate
    reg [SEQ_W-1:0] retire_seq_tag [0:N-1];
    wire [N-1:0] alloc_commit;
    reg [N-1:0] retire_pending_valid_q;
    reg [ROB_ID_W-1:0] retire_pending_rob_id_q [0:N-1];
    reg [SEQ_W-1:0] retire_pending_seq_tag_q [0:N-1];
    reg [PACKET_W-1:0] retire_pending_data_q [0:N-1];

    reg [ROB_DEPTH-1:0] wb_lane_entry_commit [0:FE_NUM-1];
    reg [ROB_DEPTH-1:0] wb_lane_entry_predict [0:FE_NUM-1];
    reg [ROB_DEPTH-1:0] wb_entry_predict;
    reg [PACKET_W-1:0] wb_entry_predict_data [0:ROB_DEPTH-1];
    reg [ROB_DEPTH-1:0] data_entry_write_en;
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

    reg [PACKET_W-1:0] retire_bank_data [0:DATA_BANK_NUM-1];
    reg [PACKET_W-1:0] retire_rotate_one_data [0:DATA_BANK_NUM-1];
    reg [DATA_ROW_NUM-1:0] rob_done_bank [0:DATA_BANK_NUM-1];
    reg [DATA_BANK_NUM-1:0] retire_bank_done;
    reg [DATA_BANK_NUM-1:0] retire_rotate_one_done;
    reg [N-1:0] retire_raw_done;
    reg retire_done01;
    reg retire_done23;
    reg [ROB_ID_W-1:0] retire_bank_rob_id [0:DATA_BANK_NUM-1];
    reg [ROB_ID_W-1:0] retire_rotate_one_rob_id [0:DATA_BANK_NUM-1];
    reg [ROB_TAG_HI_W-1:0] retire_bank_tag_hi [0:DATA_BANK_NUM-1];
    reg [ROB_TAG_HI_W-1:0] retire_rotate_one_tag_hi [0:DATA_BANK_NUM-1];
    reg [ROB_TAG_HI_W-1:0] retire_raw_tag_hi [0:N-1];
    reg [DATA_BANK_NUM-1:0] retire_inverse_two_valid;
    reg [DATA_BANK_NUM-1:0] retire_bank_advance;

    reg [N-1:0] dep_status_active_match;
    reg [N-1:0] dep_status_active_available;
    reg [N-1:0] dep_status_history_match;
    reg [ISSUE_WIDTH-1:0] issue_dep_active_match;
    reg [ISSUE_WIDTH-1:0] issue_dep_active_available;
    reg [ISSUE_WIDTH-1:0] issue_dep_history_match;
    reg [PACKET_W-1:0] issue_dep_active_data [0:ISSUE_WIDTH-1];
    reg [PACKET_W-1:0] issue_dep_history_data [0:ISSUE_WIDTH-1];
    reg [FE_NUM-1:0] issue_dep_wb_match [0:ISSUE_WIDTH-1];
    reg [ISSUE_WIDTH-1:0] issue_dep_wb_any;
    reg [PACKET_W-1:0] issue_dep_wb_data [0:ISSUE_WIDTH-1];

    // D2B response candidates.  Each source path is captured independently
    // so the FE-facing cycle only contains the final shallow priority mux.
    reg [ISSUE_WIDTH-1:0] dep_wb_any_q;
    reg [PACKET_W-1:0] dep_wb_data_q [0:ISSUE_WIDTH-1];
    reg [ISSUE_WIDTH-1:0] dep_active_match_q;
    reg [ISSUE_WIDTH-1:0] dep_active_available_q;
    reg [PACKET_W-1:0] dep_active_data_q [0:ISSUE_WIDTH-1];
    reg [ISSUE_WIDTH-1:0] dep_history_match_q;
    reg [PACKET_W-1:0] dep_history_data_q [0:ISSUE_WIDTH-1];
    reg [PACKET_W-1:0] issue_dep_data_d [0:ISSUE_WIDTH-1];

    // The gather query is the narrow D2A intermediate register.  The
    // source-specific dependency candidates are captured at D2B; only their
    // final priority selection remains on the FE-facing cycle.
    reg [ISSUE_WIDTH-1:0] gather_dep_required_q;
    reg [SEQ_W-1:0] gather_target_seq_tag_q [0:ISSUE_WIDTH-1];

    //-------------------------------------------------------------------------
    // A0/A1 and W0: allocation, completion qualification, and done visibility.
    //-------------------------------------------------------------------------
    integer done_bank;
    integer done_row;

    // A0: calculate the historical exact-mask admission decision and the
    // next occupancy.  Retirement lookahead is still registered, but the
    // request-size decode is local to the ROB and does not cross back through
    // an ingress-side count/limit comparator.
    always @* begin : allocation_capacity
        occupancy_after_retire_ext =
            {1'b0, occupancy_q}
            - {{(CAPACITY_EXT_W-LANE_COUNT_W){1'b0}},
               alloc_pending_retire_count_q};
        accepted_reserve_count = {LANE_COUNT_W{1'b0}};
        alloc_reserve_ready_o = 1'b0;
        case (alloc_reserve_valid_i)
            4'b0001, 4'b0010, 4'b0100, 4'b1000: begin
                if (occupancy_after_retire_ext <= ROB_CAPACITY_1) begin
                    alloc_reserve_ready_o = 1'b1;
                    accepted_reserve_count = 3'd1;
                end
            end
            4'b0011, 4'b0101, 4'b0110,
            4'b1001, 4'b1010, 4'b1100: begin
                if (occupancy_after_retire_ext <= ROB_CAPACITY_2) begin
                    alloc_reserve_ready_o = 1'b1;
                    accepted_reserve_count = 3'd2;
                end
            end
            4'b0111, 4'b1011, 4'b1101, 4'b1110: begin
                if (occupancy_after_retire_ext <= ROB_CAPACITY_3) begin
                    alloc_reserve_ready_o = 1'b1;
                    accepted_reserve_count = 3'd3;
                end
            end
            4'b1111: begin
                if (occupancy_after_retire_ext <= ROB_CAPACITY_4) begin
                    alloc_reserve_ready_o = 1'b1;
                    accepted_reserve_count = 3'd4;
                end
            end
            default: begin
                alloc_reserve_ready_o = 1'b0;
            end
        endcase

        occupancy_next_ext =
            occupancy_after_retire_ext
            + {{(CAPACITY_EXT_W-LANE_COUNT_W){1'b0}},
               accepted_reserve_count};
        occupancy_next = occupancy_next_ext[OCCUPANCY_W-1:0];
    end

    // A0: derive local ROB indices from the committed sequence tags.
    always @* begin : allocation_request_decode
        integer lane_idx;
        for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
            alloc_rob_id[lane_idx] =
                alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0];
        end
    end

    // A0: capture one allocation packet per physical data bank.
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
                    alloc_packet_i[alloc_idx];
            end
            if (alloc_commit[alloc_idx]) begin
                alloc_data_capture_valid[alloc_bank] = 1'b1;
            end
        end
    end

    assign head_ptr_q =
        {retire_bank_row_q[retire_head_bank_q], retire_head_bank_q};
    assign alloc_commit = alloc_commit_valid_i;

    // A0/A1: register bank-local allocation row/control state.
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

    // A1: register bank-local allocation payloads.
    always @(posedge clk_i) begin : alloc_data_payload
        integer bank_idx;
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1)
            if (alloc_data_capture_en[bank_idx])
                alloc_data_q[bank_idx] <= alloc_data_capture[bank_idx];
    end

    // W0: qualify writeback lanes and form entry-local write enables/data.
    always @* begin : writeback_qualification
        integer wb_idx;
        integer entry_idx;
        reg [ROB_TAG_HI_W-1:0] wb_tag_hi;
        reg wb_actual_match;

        wb_commit = {FE_NUM{1'b0}};
        data_entry_write_en = {ROB_DEPTH{1'b0}};
        for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
            wb_rob_id[wb_idx] =
                wb_seq_tag_i[wb_idx][ROB_ID_W-1:0];
            wb_lane_entry_commit[wb_idx] = {ROB_DEPTH{1'b0}};
            wb_lane_entry_predict[wb_idx] = {ROB_DEPTH{1'b0}};
        end
        wb_entry_predict = {ROB_DEPTH{1'b0}};

        for (entry_idx = 0; entry_idx < ROB_DEPTH;
             entry_idx = entry_idx + 1) begin
            for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
                wb_tag_hi = wb_pre_seq_tag_i[wb_idx][
                    ROB_ID_W +: ROB_TAG_HI_W];
                wb_actual_match = wb_valid_i[wb_idx]
                    && (wb_seq_tag_i[wb_idx]
                        == wb_pre_seq_tag_i[wb_idx]);
                if (((entry_idx & 1) == 0 && wb_idx < 2)
                    || ((entry_idx & 1) != 0 && wb_idx >= 2)) begin
                    wb_lane_entry_predict[wb_idx][entry_idx] =
                        wb_pre_entry_onehot_i[wb_idx][entry_idx]
                        && rob_valid_q[entry_idx]
                        && !rob_result_valid_q[entry_idx];
                    wb_lane_entry_commit[wb_idx][entry_idx] =
                        wb_lane_entry_predict[wb_idx][entry_idx]
                        && wb_actual_match
                        && (rob_tag_hi_q[entry_idx] == wb_tag_hi);
                end
            end
            wb_entry_predict[entry_idx] =
                wb_lane_entry_predict[0][entry_idx]
                || wb_lane_entry_predict[1][entry_idx]
                || wb_lane_entry_predict[2][entry_idx]
                || wb_lane_entry_predict[3][entry_idx];
            data_entry_write_en[entry_idx] =
                wb_lane_entry_commit[0][entry_idx]
                || wb_lane_entry_commit[1][entry_idx]
                || wb_lane_entry_commit[2][entry_idx]
                || wb_lane_entry_commit[3][entry_idx];
            if ((entry_idx & 1) == 0) begin
                wb_entry_predict_data[entry_idx] =
                    (wb_data_i[0]
                     & {PACKET_W{
                         wb_lane_entry_predict[0][entry_idx]}})
                    | (wb_data_i[1]
                       & {PACKET_W{
                           wb_lane_entry_predict[1][entry_idx]}});
                data_entry_write_data[entry_idx] =
                    (wb_data_i[0]
                     & {PACKET_W{
                         wb_lane_entry_commit[0][entry_idx]}})
                    | (wb_data_i[1]
                       & {PACKET_W{
                           wb_lane_entry_commit[1][entry_idx]}});
            end else begin
                wb_entry_predict_data[entry_idx] =
                    (wb_data_i[2]
                     & {PACKET_W{
                         wb_lane_entry_predict[2][entry_idx]}})
                    | (wb_data_i[3]
                       & {PACKET_W{
                           wb_lane_entry_predict[3][entry_idx]}});
                data_entry_write_data[entry_idx] =
                    (wb_data_i[2]
                     & {PACKET_W{
                         wb_lane_entry_commit[2][entry_idx]}})
                    | (wb_data_i[3]
                       & {PACKET_W{
                           wb_lane_entry_commit[3][entry_idx]}});
            end
        end

        for (wb_idx = 0; wb_idx < FE_NUM; wb_idx = wb_idx + 1) begin
            wb_commit[wb_idx] = |wb_lane_entry_commit[wb_idx];
        end
    end

    // W0/R0: combine stored completion state with the next-return prediction.
    always @* begin : done_bank_decode
        for (done_bank = 0; done_bank < DATA_BANK_NUM;
             done_bank = done_bank + 1) begin
            rob_done_bank[done_bank] = {DATA_ROW_NUM{1'b0}};
            for (done_row = 0; done_row < DATA_ROW_NUM;
                 done_row = done_row + 1) begin
                rob_done_bank[done_bank][done_row] =
                    rob_valid_q[done_row*DATA_BANK_NUM+done_bank]
                    && (rob_result_valid_q[
                            done_row*DATA_BANK_NUM+done_bank]
                        || wb_entry_predict[
                            done_row*DATA_BANK_NUM+done_bank]);
            end
        end
    end

    //-------------------------------------------------------------------------
    // R0: in-order head scan, data rotation, and retirement bookkeeping.
    //-------------------------------------------------------------------------
    // R0: scan the dense DONE prefix from the current physical head.
    always @* begin : retirement_scan
        integer bank_idx;
        integer retire_idx;

        retire_bank_done = {DATA_BANK_NUM{1'b0}};
        retire_rotate_one_done = {DATA_BANK_NUM{1'b0}};
        retire_raw_done = {N{1'b0}};
        retire_done01 = 1'b0;
        retire_done23 = 1'b0;
        retire_head_bank_next = retire_head_bank_q;
        retire_valid_o = {N{1'b0}};
        retire_count = {LANE_COUNT_W{1'b0}};
        retire_inverse_two_valid = {DATA_BANK_NUM{1'b0}};
        retire_bank_advance = {DATA_BANK_NUM{1'b0}};

        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
            bank_idx = bank_idx + 1) begin
            retire_bank_done[bank_idx] =
                rob_done_bank[bank_idx][retire_bank_row_q[bank_idx]];
            retire_bank_rob_id[bank_idx] =
                {retire_bank_row_q[bank_idx],
                 bank_idx[DATA_BANK_W-1:0]};
            retire_bank_tag_hi[bank_idx] =
                rob_tag_hi_q[
                    {retire_bank_row_q[bank_idx],
                     bank_idx[DATA_BANK_W-1:0]}];
            retire_rotate_one_rob_id[bank_idx] =
                retire_bank_rob_id[bank_idx];
            retire_rotate_one_tag_hi[bank_idx] =
                retire_bank_tag_hi[bank_idx];
        end

        retire_rotate_one_done = retire_bank_done;
        if (retire_head_bank_q[0]) begin
            retire_rotate_one_done =
                {retire_bank_done[0], retire_bank_done[3:1]};
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1) begin
                retire_rotate_one_rob_id[retire_idx] =
                    retire_bank_rob_id[(retire_idx+1)%N];
                retire_rotate_one_tag_hi[retire_idx] =
                    retire_bank_tag_hi[(retire_idx+1)%N];
            end
        end

        retire_raw_done = retire_rotate_one_done;
        for (retire_idx = 0; retire_idx < N;
             retire_idx = retire_idx + 1) begin
            retire_rob_id[retire_idx] = retire_rotate_one_rob_id[retire_idx];
            retire_raw_tag_hi[retire_idx] =
                retire_rotate_one_tag_hi[retire_idx];
        end
        if (retire_head_bank_q[1]) begin
            retire_raw_done =
                {retire_rotate_one_done[1:0],
                 retire_rotate_one_done[3:2]};
            for (retire_idx = 0; retire_idx < N;
                 retire_idx = retire_idx + 1) begin
                retire_rob_id[retire_idx] =
                    retire_rotate_one_rob_id[(retire_idx+2)%N];
                retire_raw_tag_hi[retire_idx] =
                    retire_rotate_one_tag_hi[(retire_idx+2)%N];
            end
        end

        retire_done01 = retire_raw_done[0] && retire_raw_done[1];
        retire_done23 = retire_raw_done[2] && retire_raw_done[3];
        retire_valid_o[0] = retire_raw_done[0];
        retire_valid_o[1] = retire_done01;
        retire_valid_o[2] = retire_done01 && retire_raw_done[2];
        retire_valid_o[3] = retire_done01 && retire_done23;
        // Dense-prefix retire_valid has five legal encodings.  Decode the
        // modulo-four cursor update directly instead of building parity and
        // an adder on the retirement critical path.
        case (retire_valid_o)
            4'b0001: begin
                retire_head_bank_next[0] = ~retire_head_bank_q[0];
                retire_head_bank_next[1] =
                    retire_head_bank_q[1] ^ retire_head_bank_q[0];
            end
            4'b0011: begin
                retire_head_bank_next[0] = retire_head_bank_q[0];
                retire_head_bank_next[1] = ~retire_head_bank_q[1];
            end
            4'b0111: begin
                retire_head_bank_next[0] = ~retire_head_bank_q[0];
                retire_head_bank_next[1] =
                    ~(retire_head_bank_q[1] ^ retire_head_bank_q[0]);
            end
            default: begin
                // 0000 and 1111 both advance by zero modulo four.
                retire_head_bank_next = retire_head_bank_q;
            end
        endcase
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
                {retire_raw_tag_hi[retire_idx],
                 retire_rob_id[retire_idx]};
        end
    end

    // R0: read the retiring bank data and restore logical output order.
    always @* begin : retirement_data_read
        integer bank_idx;
        reg [ROB_ID_W-1:0] retire_data_rob_id;

        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            retire_data_rob_id =
                {retire_bank_row_q[bank_idx],
                 bank_idx[DATA_BANK_W-1:0]};
            if (wb_entry_predict[retire_data_rob_id]) begin
                retire_bank_data[bank_idx] =
                    wb_entry_predict_data[retire_data_rob_id];
            end else begin
                retire_bank_data[bank_idx] =
                    rob_data_q[bank_idx][retire_bank_row_q[bank_idx]];
            end
            retire_rotate_one_data[bank_idx] = retire_bank_data[bank_idx];
        end
        if (retire_head_bank_q[0]) begin
            for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
                 bank_idx = bank_idx + 1) begin
                retire_rotate_one_data[bank_idx] =
                    retire_bank_data[(bank_idx+1)%N];
            end
        end
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            if (retire_head_bank_q[1]) begin
                retire_data_o[bank_idx] =
                    retire_rotate_one_data[(bank_idx+2)%N];
            end else begin
                retire_data_o[bank_idx] = retire_rotate_one_data[bank_idx];
            end
        end
    end

    // R0: decode retired entries into history-bank writes.
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

    // R0: register the retirement prefix and private pending capacity credit.
    always @(posedge clk_i or negedge rst_ni) begin : retire_pending_control
        integer retire_idx;

        if (!rst_ni) begin
            retire_pending_valid_q <= {N{1'b0}};
            alloc_pending_retire_count_q <= {LANE_COUNT_W{1'b0}};
        end else begin
            retire_pending_valid_q <= retire_valid_o;
            alloc_pending_retire_count_q <= retire_count;
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

    // R0: register the retiring payload for the history write in the next edge.
    always @(posedge clk_i) begin : retire_pending_data
        integer retire_idx;
        for (retire_idx = 0; retire_idx < N;
             retire_idx = retire_idx + 1)
            if (retire_valid_o[retire_idx])
                retire_pending_data_q[retire_idx] <=
                    retire_data_o[retire_idx];
    end

    // R0: update retired-history metadata.
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

    // R0: update history payloads.
    always @(posedge clk_i) begin : history_data_update
        integer history_idx;
        for (history_idx = 0; history_idx < RESULT_BANKS;
             history_idx = history_idx + 1)
            if (history_write_en[history_idx])
                history_data_q[history_idx] <= history_write_data[history_idx];
    end

    //-------------------------------------------------------------------------
    // G0: source-packet read and dependency status/data resolution.
    //-------------------------------------------------------------------------
    // D2B/G0: read the original source packet addressed by the registered grant.
    always @* begin : issue_source_read
        integer bank_idx;
        reg [ROB_ID_W-1:0] source_rob_id;

        source_rob_id = {ROB_ID_W{1'b0}};
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1) begin
            source_bank_packet_o[bank_idx] = {PACKET_W{1'b0}};
            source_rob_id =
                {source_bank_row_i[bank_idx],
                 bank_idx[DATA_BANK_W-1:0]};
            if (rob_valid_q[source_rob_id]
                && (rob_tag_hi_q[source_rob_id]
                    == source_bank_tag_hi_i[bank_idx])
                && !rob_result_valid_q[source_rob_id]) begin
                if (alloc_data_valid_q[bank_idx]
                    && (alloc_data_row_q[bank_idx]
                        == source_bank_row_i[bank_idx])) begin
                    source_bank_packet_o[bank_idx] =
                        alloc_data_q[bank_idx];
                end else begin
                    source_bank_packet_o[bank_idx] =
                        rob_data_q[bank_idx][source_bank_row_i[bank_idx]];
                end
            end
        end
    end

    // G0: decode active-ROB and retired-history lookup metadata.
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
        for (query_idx = 0; query_idx < N; query_idx = query_idx + 1) begin
            target_rob_id = dep_status_target_seq_tag_i[query_idx][ROB_ID_W-1:0];
            history_id = dep_status_target_seq_tag_i[query_idx][HISTORY_ID_W-1:0];
            if (dep_status_valid_i[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == dep_status_target_seq_tag_i[query_idx][
                            ROB_ID_W +: ROB_TAG_HI_W])) begin
                    dep_status_active_match[query_idx] = 1'b1;
                    dep_status_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                end
                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == dep_status_target_seq_tag_i[query_idx][
                            HISTORY_ID_W +: HISTORY_TAG_HI_W])) begin
                    dep_status_history_match[query_idx] = 1'b1;
                end
            end
        end
        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            issue_dep_active_data[query_idx] = {PACKET_W{1'b0}};
            issue_dep_history_data[query_idx] = {PACKET_W{1'b0}};
            target_rob_id = gather_target_seq_tag_q[query_idx][ROB_ID_W-1:0];
            history_id = gather_target_seq_tag_q[query_idx][HISTORY_ID_W-1:0];
            if (gather_dep_required_q[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == gather_target_seq_tag_q[query_idx][
                            ROB_ID_W +: ROB_TAG_HI_W])) begin
                    issue_dep_active_match[query_idx] = 1'b1;
                    issue_dep_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                    if (rob_result_valid_q[target_rob_id]) begin
                        issue_dep_active_data[query_idx] =
                            rob_data_q[
                                target_rob_id[DATA_BANK_W-1:0]][
                                target_rob_id[
                                    ROB_ID_W-1:DATA_BANK_W]];
                    end
                end
                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == gather_target_seq_tag_q[query_idx][
                            HISTORY_ID_W +: HISTORY_TAG_HI_W])) begin
                    issue_dep_history_match[query_idx] = 1'b1;
                    issue_dep_history_data[query_idx] =
                        history_data_q[history_id];
                end
            end
        end
    end

    // D0C/G0: resolve dependency availability for the status probe.
    always @* begin : dependency_status_resolve
        integer query_idx;
        integer wb_idx;
        integer pair_lane;
        integer pair_base;
        reg [ROB_ID_W-1:0] target_rob_id;
        reg source_resolved;

        dep_status_available_o = {N{1'b0}};
        source_resolved = 1'b0;
        pair_base = 0;
        wb_idx = 0;
        for (query_idx = 0; query_idx < N; query_idx = query_idx + 1) begin
            source_resolved = 1'b0;
            target_rob_id = dep_status_target_seq_tag_i[query_idx][ROB_ID_W-1:0];
            if (dep_status_valid_i[query_idx]) begin
                pair_base = target_rob_id[0] ? 2 : 0;
                for (pair_lane = 0; pair_lane < 2;
                     pair_lane = pair_lane + 1) begin
                    wb_idx = pair_base + pair_lane;
                    if (!source_resolved
                        && wb_commit[wb_idx]
                        && (wb_rob_id[wb_idx] == target_rob_id)
                        && (wb_seq_tag_i[wb_idx]
                            == dep_status_target_seq_tag_i[query_idx])) begin
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

    // G0/W0: resolve same-cycle completion bypass for gather data.
    always @* begin : dependency_completion_bypass
        integer query_idx;
        integer wb_idx;

        issue_dep_wb_any = {ISSUE_WIDTH{1'b0}};
        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            issue_dep_wb_match[query_idx] = {FE_NUM{1'b0}};
            issue_dep_wb_data[query_idx] = {PACKET_W{1'b0}};
            if (!gather_target_seq_tag_q[query_idx][0]) begin
                for (wb_idx = 0; wb_idx < 2; wb_idx = wb_idx + 1) begin
                    issue_dep_wb_match[query_idx][wb_idx] =
                        gather_dep_required_q[query_idx]
                        && wb_commit[wb_idx]
                        && (wb_seq_tag_i[wb_idx]
                            == gather_target_seq_tag_q[query_idx]);
                end
                issue_dep_wb_any[query_idx] =
                    issue_dep_wb_match[query_idx][0]
                    || issue_dep_wb_match[query_idx][1];
                issue_dep_wb_data[query_idx] =
                    (wb_data_i[0]
                     & {PACKET_W{
                         issue_dep_wb_match[query_idx][0]}})
                    | (wb_data_i[1]
                       & {PACKET_W{
                           issue_dep_wb_match[query_idx][1]}});
            end else begin
                for (wb_idx = 2; wb_idx < 4; wb_idx = wb_idx + 1) begin
                    issue_dep_wb_match[query_idx][wb_idx] =
                        gather_dep_required_q[query_idx]
                        && wb_commit[wb_idx]
                        && (wb_seq_tag_i[wb_idx]
                            == gather_target_seq_tag_q[query_idx]);
                end
                issue_dep_wb_any[query_idx] =
                    issue_dep_wb_match[query_idx][2]
                    || issue_dep_wb_match[query_idx][3];
                issue_dep_wb_data[query_idx] =
                    (wb_data_i[2]
                     & {PACKET_W{
                         issue_dep_wb_match[query_idx][2]}})
                    | (wb_data_i[3]
                       & {PACKET_W{
                           issue_dep_wb_match[query_idx][3]}});
            end
        end
    end

    // D3/G0: apply the fixed priority to the D2B-registered candidates.
    always @* begin : dependency_data_resolve
        integer query_idx;

        for (query_idx = 0; query_idx < ISSUE_WIDTH;
             query_idx = query_idx + 1) begin
            issue_dep_data_d[query_idx] = {PACKET_W{1'b0}};
            if (dep_wb_any_q[query_idx]) begin
                issue_dep_data_d[query_idx] = dep_wb_data_q[query_idx];
            end else if (dep_active_match_q[query_idx]) begin
                if (dep_active_available_q[query_idx]) begin
                    issue_dep_data_d[query_idx] =
                        dep_active_data_q[query_idx];
                end
            end else if (dep_history_match_q[query_idx]) begin
                issue_dep_data_d[query_idx] =
                    dep_history_data_q[query_idx];
            end
        end
    end

    generate
        genvar gather_lane;
        for (gather_lane = 0; gather_lane < ISSUE_WIDTH;
             gather_lane = gather_lane + 1) begin : gather_outputs
            assign gather_dep_data_o[gather_lane] = issue_dep_data_d[gather_lane];
        end
    endgenerate

    // D2A/D2B/G0: capture the current query response before accepting the
    // next D2A query.  This keeps one response aligned with one grant while
    // allowing a new query every cycle.
    always @(posedge clk_i or negedge rst_ni) begin : gather_query_state
        integer query_idx;

        if (!rst_ni) begin
            gather_dep_required_q <= {ISSUE_WIDTH{1'b0}};
            dep_wb_any_q <= {ISSUE_WIDTH{1'b0}};
            dep_active_match_q <= {ISSUE_WIDTH{1'b0}};
            dep_active_available_q <= {ISSUE_WIDTH{1'b0}};
            dep_history_match_q <= {ISSUE_WIDTH{1'b0}};
            for (query_idx = 0; query_idx < ISSUE_WIDTH;
                 query_idx = query_idx + 1) begin
                gather_target_seq_tag_q[query_idx] <= {SEQ_W{1'b0}};
            end
        end else begin
            /*
             * These values describe gather_dep_*_q from the cycle before
             * this edge.  The next assignments below then replace the
             * narrow query with the new D2A request.
             */
            for (query_idx = 0; query_idx < ISSUE_WIDTH;
                 query_idx = query_idx + 1) begin
                dep_wb_any_q[query_idx] <= issue_dep_wb_any[query_idx];
                dep_active_match_q[query_idx] <=
                    issue_dep_active_match[query_idx];
                dep_active_available_q[query_idx] <=
                    issue_dep_active_available[query_idx];
                dep_history_match_q[query_idx] <=
                    issue_dep_history_match[query_idx];
                if (gather_dep_required_q[query_idx]) begin
                    dep_wb_data_q[query_idx] <=
                        issue_dep_wb_data[query_idx];
                    dep_active_data_q[query_idx] <=
                        issue_dep_active_data[query_idx];
                    dep_history_data_q[query_idx] <=
                        issue_dep_history_data[query_idx];
                end
            end

            gather_dep_required_q <= gather_dep_required_i;
            for (query_idx = 0; query_idx < ISSUE_WIDTH;
                 query_idx = query_idx + 1) begin
                if (gather_dep_required_i[query_idx]) begin
                    gather_target_seq_tag_q[query_idx] <=
                        gather_target_seq_tag_i[query_idx];
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Registered backend state updates.  The combinational groups above feed
    // these stage-owned registers without changing the architectural boundary.
    //-------------------------------------------------------------------------
    // A0/W0/R0: update ROB validity, generation, and result-valid metadata.
    always @(posedge clk_i or negedge rst_ni) begin : rob_metadata_update
        integer entry_idx;
        integer retire_idx;
        integer alloc_idx;

        if (!rst_ni) begin
            rob_valid_q <= {ROB_DEPTH{1'b0}};
            rob_result_valid_q <= {ROB_DEPTH{1'b0}};
        end else begin
            for (entry_idx = 0; entry_idx < ROB_DEPTH;
                 entry_idx = entry_idx + 1)
                if (data_entry_write_en[entry_idx])
                    rob_result_valid_q[entry_idx] <= 1'b1;
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
                        alloc_seq_tag_i[alloc_idx][ROB_ID_W +: ROB_TAG_HI_W];
                    rob_result_valid_q[alloc_rob_id[alloc_idx]] <= 1'b0;
                end
        end
    end

    // A1/W0: commit allocation payloads and FE results into the data banks.
    always @(posedge clk_i) begin : rob_data_update
        integer bank_idx;
        integer row_idx;
        for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
             bank_idx = bank_idx + 1)
            for (row_idx = 0; row_idx < DATA_ROW_NUM;
                 row_idx = row_idx + 1) begin
                if (data_entry_write_en[
                        row_idx*DATA_BANK_NUM+bank_idx])
                    rob_data_q[bank_idx][row_idx]
                        <= data_entry_write_data[
                            row_idx*DATA_BANK_NUM+bank_idx];
                if (alloc_data_valid_q[bank_idx]
                    && (alloc_data_row_q[bank_idx]
                        == row_idx[DATA_ROW_W-1:0]))
                    rob_data_q[bank_idx][row_idx]
                        <= alloc_data_q[bank_idx];
            end
    end

    // A0/R0: advance the ROB head, bank rows, occupancy, and capacity state.
    always @(posedge clk_i or negedge rst_ni) begin : rob_control_update
        integer bank_idx;
        if (!rst_ni) begin
            retire_head_bank_q <= {DATA_BANK_W{1'b0}};
            occupancy_q <= {OCCUPANCY_W{1'b0}};
            for (bank_idx = 0; bank_idx < DATA_BANK_NUM;
                 bank_idx = bank_idx + 1)
                retire_bank_row_q[bank_idx] <= {DATA_ROW_W{1'b0}};
        end else begin
            retire_head_bank_q <= retire_head_bank_next;
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
