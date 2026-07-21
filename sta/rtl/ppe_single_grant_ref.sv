`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_single_grant_ref.sv
// Project     : Packet Processing Engine (PPE)
// Block       : STA Reference / Single Grant Cell
//
// Description :
//   Technology-neutral timing microbenchmark for one complete scheduler grant
//   decision. Registered inputs feed forced-oldest class selection, rotating FE
//   selection, and a final sequence-tag mux. Results are captured by output
//   registers so the reported critical path is register-to-register.
//
//   This module is not production PPE RTL and is intentionally excluded from
//   all design and verification filelists. Its fixed dimensions mirror the
//   documented baseline scheduler and provide a portable reference for
//   comparing synthesis libraries and timing constraints.
//
// Clock/reset :
//   State is clocked by clk_i. rst_ni asynchronously clears only validity
//   state. Data fields are architecturally ignored while validity is clear.
//------------------------------------------------------------------------------

module ppe_single_grant_ref (
    // Clock and reset
    input  logic                 clk_i,
    input  logic                 rst_ni,

    // One registered head candidate and FE-legal mask per delay class
    input  logic [3:0]           candidate_valid_i,
    input  logic [3:0][5:0]      candidate_seq_tag_i,
    input  logic [3:0][3:0]      legal_fe_mask_i,

    // Rotating tie-break positions
    input  logic [1:0]           class_rr_ptr_i,
    input  logic [1:0]           fe_rr_ptr_i,

    // Registered single-grant result
    output logic                 grant_valid_o,
    output logic [5:0]           grant_seq_tag_o,
    output logic [1:0]           grant_class_o,
    output logic [1:0]           grant_fe_o
);

    //--------------------------------------------------------------------------
    // Local types and helper functions
    //--------------------------------------------------------------------------

    typedef logic [1:0] class_id_t;
    typedef logic [1:0] fe_id_t;
    typedef logic [5:0] seq_tag_t;

    // Within the documented active window, a non-zero forward modular distance
    // below half the sequence space means lhs precedes rhs.
    function automatic logic seq_tag_older(
        input seq_tag_t lhs,
        input seq_tag_t rhs
    );
        seq_tag_t forward_distance;
        begin
            forward_distance = rhs - lhs;
            seq_tag_older = (forward_distance != '0)
                            && !forward_distance[5];
        end
    endfunction

    //--------------------------------------------------------------------------
    // Input capture boundary
    //--------------------------------------------------------------------------

    logic [3:0]      candidate_valid_q;
    logic [3:0][5:0] candidate_seq_tag_q;
    logic [3:0][3:0] legal_fe_mask_q;
    class_id_t       class_rr_ptr_q;
    fe_id_t          fe_rr_ptr_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin : input_capture
        if (!rst_ni) begin
            candidate_valid_q <= '0;
        end else begin
            candidate_valid_q   <= candidate_valid_i;
            candidate_seq_tag_q <= candidate_seq_tag_i;
            legal_fe_mask_q     <= legal_fe_mask_i;
            class_rr_ptr_q      <= class_rr_ptr_i;
            fe_rr_ptr_q         <= fe_rr_ptr_i;
        end
    end

    //--------------------------------------------------------------------------
    // One forced-oldest class decision followed by rotating FE selection
    //--------------------------------------------------------------------------

    logic       grant_valid_d;
    seq_tag_t   grant_seq_tag_d;
    class_id_t  grant_class_d;
    fe_id_t     grant_fe_d;

    always_comb begin : single_grant_select
        logic      class_found;
        logic      fe_found;
        seq_tag_t  oldest_seq_tag;
        class_id_t scan_class;
        fe_id_t    scan_fe;

        grant_valid_d   = 1'b0;
        grant_seq_tag_d = '0;
        grant_class_d   = '0;
        grant_fe_d      = '0;
        class_found     = 1'b0;
        fe_found        = 1'b0;
        oldest_seq_tag  = '0;
        scan_class      = '0;
        scan_fe         = '0;

        // Scan order supplies the RR tie-break. Sequence age remains the
        // primary forced-first criterion.
        for (int class_offset = 0; class_offset < 4; class_offset++) begin
            scan_class = class_id_t'(class_rr_ptr_q
                                     + class_id_t'(class_offset));

            if (candidate_valid_q[scan_class]
                && (legal_fe_mask_q[scan_class] != '0)
                && (!class_found
                    || seq_tag_older(candidate_seq_tag_q[scan_class],
                                     oldest_seq_tag))) begin
                class_found     = 1'b1;
                grant_class_d   = scan_class;
                oldest_seq_tag  = candidate_seq_tag_q[scan_class];
            end
        end

        // A fixed four-way first-legal search models one FE selection cell.
        if (class_found) begin
            for (int fe_offset = 0; fe_offset < 4; fe_offset++) begin
                scan_fe = fe_id_t'(fe_rr_ptr_q + fe_id_t'(fe_offset));

                if (!fe_found && legal_fe_mask_q[grant_class_d][scan_fe]) begin
                    fe_found  = 1'b1;
                    grant_fe_d = scan_fe;
                end
            end
        end

        if (class_found && fe_found) begin
            grant_valid_d   = 1'b1;
            grant_seq_tag_d = candidate_seq_tag_q[grant_class_d];
        end
    end

    //--------------------------------------------------------------------------
    // Output capture boundary
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : output_capture
        if (!rst_ni) begin
            grant_valid_o <= 1'b0;
        end else begin
            grant_valid_o <= grant_valid_d;

            if (grant_valid_d) begin
                grant_seq_tag_o <= grant_seq_tag_d;
                grant_class_o   <= grant_class_d;
                grant_fe_o      <= grant_fe_d;
            end
        end
    end

endmodule : ppe_single_grant_ref

`default_nettype wire
