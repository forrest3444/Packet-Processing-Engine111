`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// File        : PPE_FE_SCHEDULER.v
// Block       : Scheduler / FE Matcher
//
// Description :
//   Matches ready candidates against FE return-slot constraints. Delay-3
//   candidates are legal on every FE. Registered grants are irrevocable and
//   are associated with FE results through a six-entry relative future table.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.2, 6, and 7
//   - doc/hld.txt, Sections 3.3, 5.1, and 6.2
//   - doc/lld.txt, Sections 3.3 through 3.5, 5.4, 5.6, and 8
//------------------------------------------------------------------------------

module PPE_FE_SCHEDULER (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,
    input  wire [`PPE_CAND_WINDOW_DEPTH-1:0]         candidate_valid_i,
    input  wire [`PPE_CAND_WINDOW_DEPTH*`PPE_SEQ_W-1:0]
                                                    candidate_seq_tag_i,
    input  wire [`PPE_CAND_WINDOW_DEPTH*`PPE_DELAY_W-1:0]
                                                    candidate_delay_i,
    output reg  [`PPE_FE_NUM-1:0]                    select_valid_o,
    output reg  [`PPE_FE_NUM*`PPE_CAND_WINDOW_DEPTH-1:0]
                                                    select_candidate_onehot_o,
    input  wire [`PPE_FE_NUM-1:0]                    fe_out_valid_i,
    output reg  [`PPE_FE_NUM-1:0]                    completion_valid_o,
    output reg  [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         completion_seq_tag_o
);

    // Baseline configuration. The fixed matcher is intentionally not exposed
    // as a generally parameterized implementation.
    localparam integer FE_NUM              = `PPE_FE_NUM;
    localparam integer CAND_WINDOW_DEPTH   = `PPE_CAND_WINDOW_DEPTH;
    localparam integer SEQ_W               = `PPE_SEQ_W;
    localparam integer DELAY_W             = `PPE_DELAY_W;
    localparam integer RETURN_FUTURE_DEPTH = `PPE_RETURN_FUTURE_DEPTH;
    localparam integer SHORTLIST_DEPTH     = FE_NUM;
    localparam integer FE_ID_W             = 2;

    reg [SHORTLIST_DEPTH-1:0]                        shortlist_valid;
    reg [SHORTLIST_DEPTH*CAND_WINDOW_DEPTH-1:0]      shortlist_candidate_onehot;
    reg [SHORTLIST_DEPTH*FE_NUM-1:0]                 shortlist_legal;
    reg [SHORTLIST_DEPTH*3-1:0]                      shortlist_pending_block;
    reg [CAND_WINDOW_DEPTH*FE_NUM-1:0]               candidate_legal;
    reg [CAND_WINDOW_DEPTH*3-1:0]                    candidate_pending_block;

    reg [FE_NUM-1:0]                                 grant_valid_q;
    reg [FE_NUM-1:0]                                 grant_valid_d;
    reg [FE_NUM*CAND_WINDOW_DEPTH-1:0]               grant_candidate_onehot_q;
    reg [FE_NUM*CAND_WINDOW_DEPTH-1:0]               grant_candidate_onehot_d;
    reg [FE_NUM*3-1:0]                               grant_pending_block_q;
    reg [FE_NUM*3-1:0]                               grant_pending_block_d;
    reg [FE_NUM*SEQ_W-1:0]                           grant_seq_tag_d2b;
    reg [FE_NUM*DELAY_W-1:0]                         grant_delay_d2b;

    reg [RETURN_FUTURE_DEPTH-1:0]                    future_valid_q [0:FE_NUM-1];
    reg [FE_NUM*RETURN_FUTURE_DEPTH*SEQ_W-1:0]       future_seq_tag_q;
    reg [3*FE_NUM-1:0]                               delay_target_free;

    reg [FE_ID_W-1:0]                                fe_rr_ptr_q;
    reg [FE_ID_W-1:0]                                fe_rr_ptr_d;
    reg [FE_NUM-1:0]                                 candidate_way_rr_q;
    reg [FE_NUM-1:0]                                 candidate_way_rr_d;

    function [FE_ID_W-1:0] add_fe_offset;
        input [FE_ID_W-1:0] base;
        input [FE_ID_W-1:0] offset;
        begin
            add_fe_offset = base + offset;
        end
    endfunction

    function [FE_NUM-1:0] first_fe_onehot;
        input [FE_NUM-1:0]  available;
        input [FE_ID_W-1:0] base;
        begin
            first_fe_onehot = {FE_NUM{1'b0}};
            case (base)
                2'd0: begin
                    if      (available[0]) first_fe_onehot[0] = 1'b1;
                    else if (available[1]) first_fe_onehot[1] = 1'b1;
                    else if (available[2]) first_fe_onehot[2] = 1'b1;
                    else if (available[3]) first_fe_onehot[3] = 1'b1;
                end
                2'd1: begin
                    if      (available[1]) first_fe_onehot[1] = 1'b1;
                    else if (available[2]) first_fe_onehot[2] = 1'b1;
                    else if (available[3]) first_fe_onehot[3] = 1'b1;
                    else if (available[0]) first_fe_onehot[0] = 1'b1;
                end
                2'd2: begin
                    if      (available[2]) first_fe_onehot[2] = 1'b1;
                    else if (available[3]) first_fe_onehot[3] = 1'b1;
                    else if (available[0]) first_fe_onehot[0] = 1'b1;
                    else if (available[1]) first_fe_onehot[1] = 1'b1;
                end
                default: begin
                    if      (available[3]) first_fe_onehot[3] = 1'b1;
                    else if (available[0]) first_fe_onehot[0] = 1'b1;
                    else if (available[1]) first_fe_onehot[1] = 1'b1;
                    else if (available[2]) first_fe_onehot[2] = 1'b1;
                end
            endcase
        end
    endfunction

    always @* begin : return_slot_availability
        integer fe;

        delay_target_free = {3*FE_NUM{1'b0}};
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            delay_target_free[0*FE_NUM+fe] =
                !future_valid_q[fe][3]
                && !grant_pending_block_q[fe*3+0];
            delay_target_free[1*FE_NUM+fe] =
                !future_valid_q[fe][4]
                && !grant_pending_block_q[fe*3+1];
            delay_target_free[2*FE_NUM+fe] =
                !future_valid_q[fe][5]
                && !grant_pending_block_q[fe*3+2];
        end
    end

    //--------------------------------------------------------------------------
    // D2A0: one registered candidate from each local issue bank
    //--------------------------------------------------------------------------

    always @* begin : candidate_delay_predecode
        integer candidate;

        candidate_legal         = {CAND_WINDOW_DEPTH*FE_NUM{1'b0}};
        candidate_pending_block = {CAND_WINDOW_DEPTH*3{1'b0}};

        for (candidate = 0;
             candidate < CAND_WINDOW_DEPTH;
             candidate = candidate + 1) begin
            case (candidate_delay_i[candidate*DELAY_W +: DELAY_W])
                2'd0: begin
                    candidate_legal[candidate*FE_NUM +: FE_NUM] =
                        delay_target_free[0*FE_NUM +: FE_NUM];
                end
                2'd1: begin
                    candidate_legal[candidate*FE_NUM +: FE_NUM] =
                        delay_target_free[1*FE_NUM +: FE_NUM];
                    candidate_pending_block[candidate*3+0] = 1'b1;
                end
                2'd2: begin
                    candidate_legal[candidate*FE_NUM +: FE_NUM] =
                        delay_target_free[2*FE_NUM +: FE_NUM];
                    candidate_pending_block[candidate*3+1] = 1'b1;
                end
                default: begin
                    candidate_legal[candidate*FE_NUM +: FE_NUM] =
                        {FE_NUM{1'b1}};
                    if (candidate_delay_i[
                            candidate*DELAY_W +: DELAY_W] == 2'd3) begin
                        candidate_pending_block[candidate*3+2] = 1'b1;
                    end
                end
            endcase
        end
    end

    always @* begin : d2a0_shortlist
        integer bank;
        integer fe;
        reg [CAND_WINDOW_DEPTH-1:0] pending_mask;
        reg [CAND_WINDOW_DEPTH-1:0] candidate_available;

        pending_mask                = {CAND_WINDOW_DEPTH{1'b0}};
        candidate_available         = {CAND_WINDOW_DEPTH{1'b0}};
        shortlist_valid             = {SHORTLIST_DEPTH{1'b0}};
        shortlist_candidate_onehot  =
            {SHORTLIST_DEPTH*CAND_WINDOW_DEPTH{1'b0}};
        shortlist_legal             = {SHORTLIST_DEPTH*FE_NUM{1'b0}};
        shortlist_pending_block     = {SHORTLIST_DEPTH*3{1'b0}};

        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            pending_mask = pending_mask
                | grant_candidate_onehot_q[
                    fe*CAND_WINDOW_DEPTH +: CAND_WINDOW_DEPTH];
        end
        candidate_available = candidate_valid_i & ~pending_mask;

        for (bank = 0; bank < FE_NUM; bank = bank + 1) begin
            if (!candidate_way_rr_q[bank]) begin
                if (candidate_available[bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[
                        bank*CAND_WINDOW_DEPTH+bank] = 1'b1;
                    shortlist_legal[bank*FE_NUM +: FE_NUM] =
                        candidate_legal[bank*FE_NUM +: FE_NUM];
                    shortlist_pending_block[bank*3 +: 3] =
                        candidate_pending_block[bank*3 +: 3];
                end else if (candidate_available[FE_NUM+bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[
                        bank*CAND_WINDOW_DEPTH+FE_NUM+bank] = 1'b1;
                    shortlist_legal[bank*FE_NUM +: FE_NUM] =
                        candidate_legal[(FE_NUM+bank)*FE_NUM +: FE_NUM];
                    shortlist_pending_block[bank*3 +: 3] =
                        candidate_pending_block[(FE_NUM+bank)*3 +: 3];
                end
            end else begin
                if (candidate_available[FE_NUM+bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[
                        bank*CAND_WINDOW_DEPTH+FE_NUM+bank] = 1'b1;
                    shortlist_legal[bank*FE_NUM +: FE_NUM] =
                        candidate_legal[(FE_NUM+bank)*FE_NUM +: FE_NUM];
                    shortlist_pending_block[bank*3 +: 3] =
                        candidate_pending_block[(FE_NUM+bank)*3 +: 3];
                end else if (candidate_available[bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[
                        bank*CAND_WINDOW_DEPTH+bank] = 1'b1;
                    shortlist_legal[bank*FE_NUM +: FE_NUM] =
                        candidate_legal[bank*FE_NUM +: FE_NUM];
                    shortlist_pending_block[bank*3 +: 3] =
                        candidate_pending_block[bank*3 +: 3];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // D2A1: fixed 4x4 single-round match
    //--------------------------------------------------------------------------

    always @* begin : d2a1_match
        integer candidate;
        integer fe;
        integer prior;
        reg [SHORTLIST_DEPTH*FE_NUM-1:0] legal;
        reg [SHORTLIST_DEPTH*FE_NUM-1:0] request_round0;
        reg [SHORTLIST_DEPTH*FE_NUM-1:0] accept_round0;
        reg [SHORTLIST_DEPTH*FE_NUM-1:0] accepted;
        reg [FE_ID_W-1:0]                preference_base;

        legal                       = {SHORTLIST_DEPTH*FE_NUM{1'b0}};
        request_round0              = {SHORTLIST_DEPTH*FE_NUM{1'b0}};
        accept_round0               = {SHORTLIST_DEPTH*FE_NUM{1'b0}};
        accepted                    = {SHORTLIST_DEPTH*FE_NUM{1'b0}};
        grant_valid_d               = {FE_NUM{1'b0}};
        grant_candidate_onehot_d    =
            {FE_NUM*CAND_WINDOW_DEPTH{1'b0}};
        grant_pending_block_d       = {FE_NUM*3{1'b0}};
        fe_rr_ptr_d                 = add_fe_offset(fe_rr_ptr_q, 2'd1);
        candidate_way_rr_d          = ~candidate_way_rr_q;
        preference_base             = {FE_ID_W{1'b0}};

        for (candidate = 0;
             candidate < SHORTLIST_DEPTH;
             candidate = candidate + 1) begin
            legal[candidate*FE_NUM +: FE_NUM] =
                shortlist_legal[candidate*FE_NUM +: FE_NUM]
                & {FE_NUM{shortlist_valid[candidate]}};
            preference_base = add_fe_offset(
                fe_rr_ptr_q, candidate[FE_ID_W-1:0]);
            request_round0[candidate*FE_NUM +: FE_NUM] =
                first_fe_onehot(
                    legal[candidate*FE_NUM +: FE_NUM],
                    preference_base);
        end

        for (candidate = 0;
             candidate < SHORTLIST_DEPTH;
             candidate = candidate + 1) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                accept_round0[candidate*FE_NUM+fe] =
                    request_round0[candidate*FE_NUM+fe];
                for (prior = 0;
                     prior < SHORTLIST_DEPTH;
                     prior = prior + 1) begin
                    if (prior < candidate) begin
                        accept_round0[candidate*FE_NUM+fe] =
                            accept_round0[candidate*FE_NUM+fe]
                            & !request_round0[prior*FE_NUM+fe];
                    end
                end
            end
        end

        accepted = accept_round0;
        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            for (candidate = 0;
                 candidate < SHORTLIST_DEPTH;
                 candidate = candidate + 1) begin
                grant_valid_d[fe] = grant_valid_d[fe]
                    | accepted[candidate*FE_NUM+fe];
                grant_candidate_onehot_d[
                    fe*CAND_WINDOW_DEPTH +: CAND_WINDOW_DEPTH] =
                    grant_candidate_onehot_d[
                        fe*CAND_WINDOW_DEPTH +: CAND_WINDOW_DEPTH]
                    | (shortlist_candidate_onehot[
                            candidate*CAND_WINDOW_DEPTH
                            +: CAND_WINDOW_DEPTH]
                       & {CAND_WINDOW_DEPTH{
                            accepted[candidate*FE_NUM+fe]}});
                if (accepted[candidate*FE_NUM+fe]) begin
                    grant_pending_block_d[fe*3 +: 3] =
                        shortlist_pending_block[candidate*3 +: 3];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // D2B candidate metadata read
    //--------------------------------------------------------------------------

    always @* begin : d2b_candidate_metadata
        integer candidate;
        integer fe;

        grant_seq_tag_d2b = {FE_NUM*SEQ_W{1'b0}};
        grant_delay_d2b   = {FE_NUM*DELAY_W{1'b0}};

        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            for (candidate = 0;
                 candidate < CAND_WINDOW_DEPTH;
                 candidate = candidate + 1) begin
                grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W] =
                    grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W]
                    | (candidate_seq_tag_i[
                            candidate*SEQ_W +: SEQ_W]
                       & {SEQ_W{grant_candidate_onehot_q[
                            fe*CAND_WINDOW_DEPTH+candidate]}});
                grant_delay_d2b[fe*DELAY_W +: DELAY_W] =
                    grant_delay_d2b[fe*DELAY_W +: DELAY_W]
                    | (candidate_delay_i[
                            candidate*DELAY_W +: DELAY_W]
                       & {DELAY_W{grant_candidate_onehot_q[
                            fe*CAND_WINDOW_DEPTH+candidate]}});
            end
        end
    end

    //--------------------------------------------------------------------------
    // Registered interfaces
    //--------------------------------------------------------------------------

    always @* begin : interface_outputs
        integer fe;

        select_valid_o            = grant_valid_q;
        select_candidate_onehot_o = grant_candidate_onehot_q;
        completion_valid_o        = {FE_NUM{1'b0}};
        completion_seq_tag_o      = {FE_NUM*SEQ_W{1'b0}};

        for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
            completion_valid_o[fe] =
                fe_out_valid_i[fe]
                && future_valid_q[fe][0];
            if (future_valid_q[fe][0]) begin
                completion_seq_tag_o[fe*SEQ_W +: SEQ_W] =
                    future_seq_tag_q[
                        fe*RETURN_FUTURE_DEPTH*SEQ_W +: SEQ_W];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Grant state
    //--------------------------------------------------------------------------

    always @(posedge clk_i or negedge rst_ni) begin : match_pipeline_state
        if (!rst_ni) begin
            grant_valid_q            <= {FE_NUM{1'b0}};
            grant_candidate_onehot_q <=
                {FE_NUM*CAND_WINDOW_DEPTH{1'b0}};
            grant_pending_block_q    <= {FE_NUM*3{1'b0}};
            fe_rr_ptr_q              <= {FE_ID_W{1'b0}};
            candidate_way_rr_q       <= {FE_NUM{1'b0}};
        end else begin
            grant_valid_q            <= grant_valid_d;
            grant_candidate_onehot_q <= grant_candidate_onehot_d;
            grant_pending_block_q    <= grant_pending_block_d;
            fe_rr_ptr_q              <= fe_rr_ptr_d;
            candidate_way_rr_q       <= candidate_way_rr_d;
        end
    end

    //--------------------------------------------------------------------------
    // D2B return reservation and completion association
    //--------------------------------------------------------------------------

    always @(posedge clk_i or negedge rst_ni) begin : future_table_state
        integer fe;
        integer slot;

        if (!rst_ni) begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                future_valid_q[fe] <=
                    {RETURN_FUTURE_DEPTH{1'b0}};
            end
        end else begin
            for (fe = 0; fe < FE_NUM; fe = fe + 1) begin
                for (slot = 0;
                     slot < (RETURN_FUTURE_DEPTH-1);
                     slot = slot + 1) begin
                    future_valid_q[fe][slot] <=
                        future_valid_q[fe][slot+1];
                    if (future_valid_q[fe][slot+1]) begin
                        future_seq_tag_q[
                            (fe*RETURN_FUTURE_DEPTH+slot)*SEQ_W
                            +: SEQ_W] <=
                            future_seq_tag_q[
                                (fe*RETURN_FUTURE_DEPTH+slot+1)*SEQ_W
                                +: SEQ_W];
                    end
                end
                future_valid_q[fe][RETURN_FUTURE_DEPTH-1] <= 1'b0;

                if (grant_valid_q[fe]) begin
                    case (grant_delay_d2b[
                            fe*DELAY_W +: DELAY_W])
                        2'd0: begin
                            future_valid_q[fe][1] <= 1'b1;
                            future_seq_tag_q[
                                (fe*RETURN_FUTURE_DEPTH+1)*SEQ_W
                                +: SEQ_W] <=
                                grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W];
                        end
                        2'd1: begin
                            future_valid_q[fe][2] <= 1'b1;
                            future_seq_tag_q[
                                (fe*RETURN_FUTURE_DEPTH+2)*SEQ_W
                                +: SEQ_W] <=
                                grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W];
                        end
                        2'd2: begin
                            future_valid_q[fe][3] <= 1'b1;
                            future_seq_tag_q[
                                (fe*RETURN_FUTURE_DEPTH+3)*SEQ_W
                                +: SEQ_W] <=
                                grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W];
                        end
                        default: begin
                            future_valid_q[fe][4] <= 1'b1;
                            future_seq_tag_q[
                                (fe*RETURN_FUTURE_DEPTH+4)*SEQ_W
                                +: SEQ_W] <=
                                grant_seq_tag_d2b[fe*SEQ_W +: SEQ_W];
                        end
                    endcase
                end
            end
        end
    end

endmodule

`default_nettype wire
