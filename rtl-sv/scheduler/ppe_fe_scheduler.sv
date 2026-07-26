`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_fe_scheduler.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Scheduler / FE Matcher
//
// Description :
//   Pipelines candidate preselection, a fixed 4x4 single-round FE match, and
//   return-slot commit. The registered grant is irrevocable and is associated
//   with the FE result through a six-entry relative future table.
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
    localparam int CAND_ID_W       = $clog2(CAND_WINDOW_DEPTH);

    typedef logic [FE_ID_W-1:0] fe_id_t;
    typedef logic [CAND_ID_W-1:0] cand_id_t;

    logic [SHORTLIST_DEPTH-1:0]                         shortlist_valid;
    cand_id_t [SHORTLIST_DEPTH-1:0]                    shortlist_candidate_id;
    logic [SHORTLIST_DEPTH-1:0][SEQ_W-1:0]             shortlist_seq_tag;
    logic [SHORTLIST_DEPTH-1:0][DELAY_W-1:0]           shortlist_delay;

    logic [FE_NUM-1:0]                                  grant_valid_q;
    logic [FE_NUM-1:0]                                  grant_valid_d;
    logic [FE_NUM-1:0][SEQ_W-1:0]                      grant_seq_tag_q;
    logic [FE_NUM-1:0][SEQ_W-1:0]                      grant_seq_tag_d;
    cand_id_t [FE_NUM-1:0]                             grant_candidate_id_q;
    cand_id_t [FE_NUM-1:0]                             grant_candidate_id_d;
    logic [FE_NUM-1:0][DELAY_W-1:0]                    grant_delay_q;
    logic [FE_NUM-1:0][DELAY_W-1:0]                    grant_delay_d;

    logic [FE_NUM-1:0][RETURN_FUTURE_DEPTH-1:0]        future_valid_q;
    logic [FE_NUM-1:0][RETURN_FUTURE_DEPTH-1:0]
         [SEQ_W-1:0]                                   future_seq_tag_q;

    fe_id_t fe_rr_ptr_q;
    fe_id_t fe_rr_ptr_d;
    logic   candidate_bank_rr_ptr_q;
    logic   candidate_bank_rr_ptr_d;

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

    function automatic logic [15:0] compact_onehot4(
        input logic [3:0] valid
    );
        begin
            unique case (valid)
                4'h0: compact_onehot4 = {4'h0, 4'h0, 4'h0, 4'h0};
                4'h1: compact_onehot4 = {4'h0, 4'h0, 4'h0, 4'h1};
                4'h2: compact_onehot4 = {4'h0, 4'h0, 4'h0, 4'h2};
                4'h3: compact_onehot4 = {4'h0, 4'h0, 4'h2, 4'h1};
                4'h4: compact_onehot4 = {4'h0, 4'h0, 4'h0, 4'h4};
                4'h5: compact_onehot4 = {4'h0, 4'h0, 4'h4, 4'h1};
                4'h6: compact_onehot4 = {4'h0, 4'h0, 4'h4, 4'h2};
                4'h7: compact_onehot4 = {4'h0, 4'h4, 4'h2, 4'h1};
                4'h8: compact_onehot4 = {4'h0, 4'h0, 4'h0, 4'h8};
                4'h9: compact_onehot4 = {4'h0, 4'h0, 4'h8, 4'h1};
                4'ha: compact_onehot4 = {4'h0, 4'h0, 4'h8, 4'h2};
                4'hb: compact_onehot4 = {4'h0, 4'h8, 4'h2, 4'h1};
                4'hc: compact_onehot4 = {4'h0, 4'h0, 4'h8, 4'h4};
                4'hd: compact_onehot4 = {4'h0, 4'h8, 4'h4, 4'h1};
                4'he: compact_onehot4 = {4'h0, 4'h8, 4'h4, 4'h2};
                default:
                    compact_onehot4 = {4'h8, 4'h4, 4'h2, 4'h1};
            endcase
        end
    endfunction

    function automatic logic target_is_free(
        input fe_id_t fe,
        input delay_t delay
    );
        logic pending_conflict;
        begin
            pending_conflict = 1'b0;
            unique case (delay)
                delay_t'(0): begin
                    pending_conflict = grant_valid_q[fe]
                        && (grant_delay_q[fe] == delay_t'(1));
                    target_is_free = !future_valid_q[fe][3]
                        && !pending_conflict;
                end
                delay_t'(1): begin
                    pending_conflict = grant_valid_q[fe]
                        && (grant_delay_q[fe] == delay_t'(2));
                    target_is_free = !future_valid_q[fe][4]
                        && !pending_conflict;
                end
                delay_t'(2): begin
                    pending_conflict = grant_valid_q[fe]
                        && (grant_delay_q[fe] == delay_t'(3));
                    target_is_free = !future_valid_q[fe][5]
                        && !pending_conflict;
                end
                default: target_is_free = 1'b1;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // D2A0: two-bank compacting 8-to-4 shortlist
    //--------------------------------------------------------------------------

    always_comb begin : d2a0_shortlist
        logic [CAND_WINDOW_DEPTH-1:0] pending_mask;
        logic [CAND_WINDOW_DEPTH-1:0] candidate_available;
        logic [1:0][3:0][3:0]        bank_local_onehot;
        logic [1:0][3:0]             bank_valid;
        cand_id_t [1:0][3:0]           bank_candidate_id;
        logic [1:0][3:0][SEQ_W-1:0]  bank_seq_tag;
        logic [1:0][3:0][DELAY_W-1:0]
                                            bank_delay;
        logic [3:0]                   primary_valid;
        cand_id_t [3:0]                primary_candidate_id;
        logic [3:0][SEQ_W-1:0]        primary_seq_tag;
        logic [3:0][DELAY_W-1:0]      primary_delay;
        logic [3:0]                   secondary_valid;
        cand_id_t [3:0]                secondary_candidate_id;
        logic [3:0][SEQ_W-1:0]        secondary_seq_tag;
        logic [3:0][DELAY_W-1:0]      secondary_delay;

        pending_mask                  = '0;
        candidate_available           = '0;
        bank_local_onehot              = '0;
        bank_valid                     = '0;
        bank_candidate_id              = '0;
        bank_seq_tag                   = '0;
        bank_delay                     = '0;
        primary_valid                  = '0;
        primary_candidate_id           = '0;
        primary_seq_tag                = '0;
        primary_delay                  = '0;
        secondary_valid                = '0;
        secondary_candidate_id         = '0;
        secondary_seq_tag              = '0;
        secondary_delay                = '0;
        shortlist_valid               = '0;
        shortlist_candidate_id        = '0;
        shortlist_seq_tag             = '0;
        shortlist_delay               = '0;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            if (grant_valid_q[fe]) begin
                pending_mask[grant_candidate_id_q[fe]] = 1'b1;
            end
        end

        candidate_available = candidate_valid_i & ~pending_mask;
        bank_local_onehot[0] = compact_onehot4(candidate_available[3:0]);
        bank_local_onehot[1] = compact_onehot4(candidate_available[7:4]);

        for (int bank = 0; bank < 2; bank++) begin
            for (int lane = 0; lane < 4; lane++) begin
                bank_valid[bank][lane] =
                    |bank_local_onehot[bank][lane];
                for (int slot = 0; slot < 4; slot++) begin
                    if (bank_local_onehot[bank][lane][slot]) begin
                        bank_candidate_id[bank][lane] =
                            cand_id_t'(bank*4 + slot);
                    end
                    bank_seq_tag[bank][lane] |=
                        candidate_seq_tag_i[bank*4 + slot]
                        & {SEQ_W{bank_local_onehot[bank][lane][slot]}};
                    bank_delay[bank][lane] |=
                        candidate_delay_i[bank*4 + slot]
                        & {DELAY_W{bank_local_onehot[bank][lane][slot]}};
                end
            end
        end

        if (!candidate_bank_rr_ptr_q) begin
            primary_valid            = bank_valid[0];
            primary_candidate_id     = bank_candidate_id[0];
            primary_seq_tag          = bank_seq_tag[0];
            primary_delay            = bank_delay[0];
            secondary_valid            = bank_valid[1];
            secondary_candidate_id     = bank_candidate_id[1];
            secondary_seq_tag          = bank_seq_tag[1];
            secondary_delay            = bank_delay[1];
        end else begin
            primary_valid            = bank_valid[1];
            primary_candidate_id     = bank_candidate_id[1];
            primary_seq_tag          = bank_seq_tag[1];
            primary_delay            = bank_delay[1];
            secondary_valid            = bank_valid[0];
            secondary_candidate_id     = bank_candidate_id[0];
            secondary_seq_tag          = bank_seq_tag[0];
            secondary_delay            = bank_delay[0];
        end

        // Each compacted bank is a dense valid prefix. Decode that prefix
        // directly instead of rebuilding its length with an adder tree.
        unique case (primary_valid)
            4'b0000: begin
                shortlist_valid            = secondary_valid;
                shortlist_candidate_id     = secondary_candidate_id;
                shortlist_seq_tag          = secondary_seq_tag;
                shortlist_delay            = secondary_delay;
            end
            4'b0001: begin
                shortlist_valid[0]            = primary_valid[0];
                shortlist_candidate_id[0] = primary_candidate_id[0];
                shortlist_seq_tag[0]          = primary_seq_tag[0];
                shortlist_delay[0]            = primary_delay[0];
                for (int lane = 1; lane < 4; lane++) begin
                    shortlist_valid[lane] = secondary_valid[lane-1];
                    shortlist_candidate_id[lane] =
                        secondary_candidate_id[lane-1];
                    shortlist_seq_tag[lane] = secondary_seq_tag[lane-1];
                    shortlist_delay[lane] = secondary_delay[lane-1];
                end
            end
            4'b0011: begin
                for (int lane = 0; lane < 2; lane++) begin
                    shortlist_valid[lane] = primary_valid[lane];
                    shortlist_candidate_id[lane] =
                        primary_candidate_id[lane];
                    shortlist_seq_tag[lane] = primary_seq_tag[lane];
                    shortlist_delay[lane] = primary_delay[lane];
                    shortlist_valid[lane+2] = secondary_valid[lane];
                    shortlist_candidate_id[lane+2] =
                        secondary_candidate_id[lane];
                    shortlist_seq_tag[lane+2] = secondary_seq_tag[lane];
                    shortlist_delay[lane+2] = secondary_delay[lane];
                end
            end
            4'b0111: begin
                for (int lane = 0; lane < 3; lane++) begin
                    shortlist_valid[lane] = primary_valid[lane];
                    shortlist_candidate_id[lane] =
                        primary_candidate_id[lane];
                    shortlist_seq_tag[lane] = primary_seq_tag[lane];
                    shortlist_delay[lane] = primary_delay[lane];
                end
                shortlist_valid[3] = secondary_valid[0];
                shortlist_candidate_id[3] = secondary_candidate_id[0];
                shortlist_seq_tag[3] = secondary_seq_tag[0];
                shortlist_delay[3] = secondary_delay[0];
            end
            4'b1111: begin
                shortlist_valid            = primary_valid;
                shortlist_candidate_id     = primary_candidate_id;
                shortlist_seq_tag          = primary_seq_tag;
                shortlist_delay            = primary_delay;
            end
            default: begin
                shortlist_valid            = '0;
                shortlist_candidate_id     = '0;
                shortlist_seq_tag          = '0;
                shortlist_delay            = '0;
            end
        endcase
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
        grant_seq_tag_d  = '0;
        grant_candidate_id_d = '0;
        grant_delay_d    = '0;
        fe_rr_ptr_d      = fe_rr_ptr_q;
        candidate_bank_rr_ptr_d = ~candidate_bank_rr_ptr_q;
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
                grant_seq_tag_d[fe] |=
                    shortlist_seq_tag[candidate]
                    & {SEQ_W{accepted[candidate][fe]}};
                grant_candidate_id_d[fe] |=
                    shortlist_candidate_id[candidate]
                    & {CAND_ID_W{accepted[candidate][fe]}};
                grant_delay_d[fe] |=
                    shortlist_delay[candidate]
                    & {DELAY_W{accepted[candidate][fe]}};
            end
        end

        // Any non-empty legal matrix necessarily produces at least one
        // round-0 acceptance. Advance fairness from this early reduction
        // instead of waiting for request, conflict, and metadata networks.
        if (|legal) begin
            fe_rr_ptr_d = add_fe_offset(fe_rr_ptr_q, fe_id_t'(1));
        end

    end

    //--------------------------------------------------------------------------
    // Registered interfaces
    //--------------------------------------------------------------------------

    always_comb begin : interface_outputs
        select_valid_o            = grant_valid_q;
        select_candidate_onehot_o = '0;
        completion_valid_o        = '0;
        completion_seq_tag_o      = '0;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            if (grant_valid_q[fe]) begin
                select_candidate_onehot_o[fe][grant_candidate_id_q[fe]] =
                    1'b1;
            end
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
            grant_valid_q     <= '0;
            fe_rr_ptr_q       <= '0;
            candidate_bank_rr_ptr_q <= 1'b0;
        end else begin
            grant_valid_q     <= grant_valid_d;
            fe_rr_ptr_q       <= fe_rr_ptr_d;
            candidate_bank_rr_ptr_q <= candidate_bank_rr_ptr_d;

            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (grant_valid_d[fe]) begin
                    grant_seq_tag_q[fe] <= grant_seq_tag_d[fe];
                    grant_candidate_id_q[fe] <= grant_candidate_id_d[fe];
                    grant_delay_q[fe] <= grant_delay_d[fe];
                end
            end
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
                    unique case (grant_delay_q[fe])
                        delay_t'(0): begin
                            future_valid_q[fe][1] <= 1'b1;
                            future_seq_tag_q[fe][1] <= grant_seq_tag_q[fe];
                        end
                        delay_t'(1): begin
                            future_valid_q[fe][2] <= 1'b1;
                            future_seq_tag_q[fe][2] <= grant_seq_tag_q[fe];
                        end
                        delay_t'(2): begin
                            future_valid_q[fe][3] <= 1'b1;
                            future_seq_tag_q[fe][3] <= grant_seq_tag_q[fe];
                        end
                        default: begin
                            future_valid_q[fe][4] <= 1'b1;
                            future_seq_tag_q[fe][4] <= grant_seq_tag_q[fe];
                        end
                    endcase
                end
            end
        end
    end

endmodule : ppe_fe_scheduler

`default_nettype wire
