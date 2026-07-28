`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_fe_scheduler.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Scheduler / FE Matcher
//
// Description :
//   Selects one registered candidate from each local issue bank, performs a
//   fixed 4x4 single-round FE match, and commits return-slot reservations.
//   The registered grant is irrevocable and is associated with the FE result
//   through a six-entry relative future table.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.2, 6, and 7
//   - doc/hld.txt, Sections 3.3, 5.1, and 6.2
//   - doc/lld.txt, Sections 3.3 through 3.5, 5.4, 5.6, and 8
//------------------------------------------------------------------------------

module ppe_fe_scheduler (
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    input  logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]    candidate_valid_i,
    input  logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                candidate_seq_tag_i,
    input  logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              candidate_delay_i,

    output logic [ppe_types_pkg::FE_NUM-1:0]               select_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                                                             select_candidate_onehot_o,

    input  logic [ppe_types_pkg::FE_NUM-1:0]               fe_out_valid_i,

    output logic [ppe_types_pkg::FE_NUM-1:0]               completion_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                completion_seq_tag_o
);

    import ppe_types_pkg::*;

    localparam int SHORTLIST_DEPTH = FE_NUM;
    localparam int FE_ID_W         = $clog2(FE_NUM);

    typedef logic [FE_ID_W-1:0] fe_id_t;

    logic [SHORTLIST_DEPTH-1:0]                         shortlist_valid;
    logic [SHORTLIST_DEPTH-1:0][CAND_WINDOW_DEPTH-1:0]
                                                         shortlist_candidate_onehot;
    logic [SHORTLIST_DEPTH-1:0][DELAY_W-1:0]           shortlist_delay;

    logic [FE_NUM-1:0]                                  grant_valid_q;
    logic [FE_NUM-1:0]                                  grant_valid_d;
    logic [FE_NUM-1:0][CAND_WINDOW_DEPTH-1:0]
                                                         grant_candidate_onehot_q;
    logic [FE_NUM-1:0][CAND_WINDOW_DEPTH-1:0]
                                                         grant_candidate_onehot_d;
    logic [FE_NUM-1:0][2:0]                            grant_pending_block_q;
    logic [FE_NUM-1:0][2:0]                            grant_pending_block_d;
    logic [FE_NUM-1:0][SEQ_W-1:0]                      grant_seq_tag_d2b;
    logic [FE_NUM-1:0][DELAY_W-1:0]                    grant_delay_d2b;

    logic [FE_NUM-1:0][RETURN_FUTURE_DEPTH-1:0]        future_valid_q;
    logic [FE_NUM-1:0][RETURN_FUTURE_DEPTH-1:0]
         [SEQ_W-1:0]                                   future_seq_tag_q;

    fe_id_t fe_rr_ptr_q;
    fe_id_t fe_rr_ptr_d;
    logic [FE_NUM-1:0] candidate_way_rr_q;
    logic [FE_NUM-1:0] candidate_way_rr_d;

    function automatic fe_id_t add_fe_offset(
        input fe_id_t base,
        input fe_id_t offset
    );
        add_fe_offset = base + offset;
    endfunction

    function automatic logic [FE_NUM-1:0] first_fe_onehot(
        input logic [FE_NUM-1:0] available,
        input fe_id_t           base
    );
        begin
            first_fe_onehot = '0;
            unique case (base)
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

    function automatic logic target_is_free(
        input fe_id_t fe,
        input delay_t delay
    );
        begin
            unique case (delay)
                delay_t'(0): target_is_free = !future_valid_q[fe][3]
                    && !grant_pending_block_q[fe][0];
                delay_t'(1): target_is_free = !future_valid_q[fe][4]
                    && !grant_pending_block_q[fe][1];
                delay_t'(2): target_is_free = !future_valid_q[fe][5]
                    && !grant_pending_block_q[fe][2];
                default: target_is_free = 1'b1;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // D2A0: one registered candidate from each local issue bank
    //--------------------------------------------------------------------------

    always_comb begin : d2a0_shortlist
        logic [CAND_WINDOW_DEPTH-1:0] pending_mask;
        logic [CAND_WINDOW_DEPTH-1:0] candidate_available;

        pending_mask           = '0;
        candidate_available    = '0;
        shortlist_valid        = '0;
        shortlist_candidate_onehot = '0;
        shortlist_delay        = '0;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            pending_mask |= grant_candidate_onehot_q[fe];
        end
        candidate_available = candidate_valid_i & ~pending_mask;

        for (int bank = 0; bank < FE_NUM; bank++) begin
            if (!candidate_way_rr_q[bank]) begin
                if (candidate_available[bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[bank][bank] = 1'b1;
                    shortlist_delay[bank] =
                        candidate_delay_i[bank];
                end else if (candidate_available[FE_NUM + bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[bank][FE_NUM + bank] = 1'b1;
                    shortlist_delay[bank] =
                        candidate_delay_i[FE_NUM + bank];
                end
            end else begin
                if (candidate_available[FE_NUM + bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[bank][FE_NUM + bank] = 1'b1;
                    shortlist_delay[bank] =
                        candidate_delay_i[FE_NUM + bank];
                end else if (candidate_available[bank]) begin
                    shortlist_valid[bank] = 1'b1;
                    shortlist_candidate_onehot[bank][bank] = 1'b1;
                    shortlist_delay[bank] =
                        candidate_delay_i[bank];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // D2A1: fixed 4x4 single-round match
    //--------------------------------------------------------------------------

    always_comb begin : d2a1_match
        logic [SHORTLIST_DEPTH-1:0][FE_NUM-1:0] legal;
        logic [SHORTLIST_DEPTH-1:0][FE_NUM-1:0] request_round0;
        logic [SHORTLIST_DEPTH-1:0][FE_NUM-1:0] accept_round0;
        logic [SHORTLIST_DEPTH-1:0][FE_NUM-1:0] accepted;
        fe_id_t                                 preference_base;

        legal            = '0;
        request_round0   = '0;
        accept_round0    = '0;
        accepted         = '0;
        grant_valid_d    = '0;
        grant_candidate_onehot_d = '0;
        grant_pending_block_d = '0;
        fe_rr_ptr_d      = add_fe_offset(fe_rr_ptr_q, fe_id_t'(1));
        candidate_way_rr_d = ~candidate_way_rr_q;
        preference_base  = '0;

        for (int candidate = 0;
             candidate < SHORTLIST_DEPTH;
             candidate++) begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                legal[candidate][fe] = shortlist_valid[candidate]
                    && target_is_free(fe_id_t'(fe),
                                      shortlist_delay[candidate]);
            end
            preference_base = add_fe_offset(
                fe_rr_ptr_q, fe_id_t'(candidate));
            request_round0[candidate] =
                first_fe_onehot(legal[candidate], preference_base);
        end

        for (int candidate = 0;
             candidate < SHORTLIST_DEPTH;
             candidate++) begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                accept_round0[candidate][fe] =
                    request_round0[candidate][fe];
                for (int prior = 0;
                     prior < SHORTLIST_DEPTH;
                     prior++) begin
                    if (prior < candidate) begin
                        accept_round0[candidate][fe] &=
                            !request_round0[prior][fe];
                    end
                end
            end
        end

        accepted = accept_round0;
        for (int fe = 0; fe < FE_NUM; fe++) begin
            for (int candidate = 0;
                 candidate < SHORTLIST_DEPTH;
                 candidate++) begin
                grant_valid_d[fe] |= accepted[candidate][fe];
                grant_candidate_onehot_d[fe] |=
                    shortlist_candidate_onehot[candidate]
                    & {CAND_WINDOW_DEPTH{accepted[candidate][fe]}};
                if (accepted[candidate][fe]) begin
                    unique case (shortlist_delay[candidate])
                        delay_t'(1):
                            grant_pending_block_d[fe][0] = 1'b1;
                        delay_t'(2):
                            grant_pending_block_d[fe][1] = 1'b1;
                        delay_t'(3):
                            grant_pending_block_d[fe][2] = 1'b1;
                        default: begin
                            grant_pending_block_d[fe] = '0;
                        end
                    endcase
                end
            end
        end

    end

    //--------------------------------------------------------------------------
    // D2B candidate metadata read
    //--------------------------------------------------------------------------

    always_comb begin : d2b_candidate_metadata
        grant_seq_tag_d2b = '0;
        grant_delay_d2b   = '0;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            for (int candidate = 0;
                 candidate < CAND_WINDOW_DEPTH;
                 candidate++) begin
                grant_seq_tag_d2b[fe] |=
                    candidate_seq_tag_i[candidate]
                    & {SEQ_W{grant_candidate_onehot_q[fe][candidate]}};
                grant_delay_d2b[fe] |=
                    candidate_delay_i[candidate]
                    & {DELAY_W{grant_candidate_onehot_q[fe][candidate]}};
            end
        end
    end

    //--------------------------------------------------------------------------
    // Registered interfaces
    //--------------------------------------------------------------------------

    always_comb begin : interface_outputs
        select_valid_o            = grant_valid_q;
        select_candidate_onehot_o = grant_candidate_onehot_q;
        completion_valid_o        = '0;
        completion_seq_tag_o      = '0;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            completion_valid_o[fe] =
                fe_out_valid_i[fe] && future_valid_q[fe][0];
            if (future_valid_q[fe][0]) begin
                completion_seq_tag_o[fe] = future_seq_tag_q[fe][0];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Grant state
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : match_pipeline_state
        if (!rst_ni) begin
            grant_valid_q            <= '0;
            grant_candidate_onehot_q <= '0;
            grant_pending_block_q    <= '0;
            fe_rr_ptr_q              <= '0;
            candidate_way_rr_q       <= '0;
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

    always_ff @(posedge clk_i or negedge rst_ni) begin : future_table_state
        if (!rst_ni) begin
            future_valid_q <= '0;
        end else begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                for (int slot = 0;
                     slot < (RETURN_FUTURE_DEPTH - 1);
                     slot++) begin
                    future_valid_q[fe][slot] <=
                        future_valid_q[fe][slot + 1];
                    if (future_valid_q[fe][slot + 1]) begin
                        future_seq_tag_q[fe][slot] <=
                            future_seq_tag_q[fe][slot + 1];
                    end
                end
                future_valid_q[fe][RETURN_FUTURE_DEPTH-1] <= 1'b0;

                if (grant_valid_q[fe]) begin
                    unique case (grant_delay_d2b[fe])
                        delay_t'(0): begin
                            future_valid_q[fe][1] <= 1'b1;
                            future_seq_tag_q[fe][1] <= grant_seq_tag_d2b[fe];
                        end
                        delay_t'(1): begin
                            future_valid_q[fe][2] <= 1'b1;
                            future_seq_tag_q[fe][2] <= grant_seq_tag_d2b[fe];
                        end
                        delay_t'(2): begin
                            future_valid_q[fe][3] <= 1'b1;
                            future_seq_tag_q[fe][3] <= grant_seq_tag_d2b[fe];
                        end
                        default: begin
                            future_valid_q[fe][4] <= 1'b1;
                            future_seq_tag_q[fe][4] <= grant_seq_tag_d2b[fe];
                        end
                    endcase
                end
            end
        end
    end

endmodule : ppe_fe_scheduler

`default_nettype wire
