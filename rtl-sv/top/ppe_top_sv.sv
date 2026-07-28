`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_top_sv.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Top-level integration
//
// Description :
//   Integrates the registered ingress boundary, issue table, FE scheduler,
//   four Forward Engines, ROB, and registered retirement-output mapping. Raw
//   external inputs connect only to ppe_ingress capture state. External bkps
//   and output data/valid are direct aliases of owning submodule registers.
//
//   The top owns only the two-flop reset synchronizer and port adaptation. It
//   owns no packet, dependency, scheduling, completion, or retirement state.
//------------------------------------------------------------------------------

module ppe_top_sv #(
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W,
    parameter int DESC_W   = ppe_types_pkg::DEFAULT_DESC_W
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [ppe_types_pkg::N-1:0]                 in_valid,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]   in_packet,
    input  logic [ppe_types_pkg::N-1:0][DESC_W-1:0]     in_desc,

    output logic                    bkps,

    output logic [ppe_types_pkg::N-1:0]                 out_valid,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]   out_packet
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Shared reset synchronization
    //--------------------------------------------------------------------------

    logic [1:0] reset_sync_q;
    logic       internal_rst_n;

    always_ff @(posedge clk or negedge rst_n) begin : reset_synchronizer
        if (!rst_n) begin
            reset_sync_q <= 2'b00;
        end else begin
            reset_sync_q <= {reset_sync_q[0], 1'b1};
        end
    end

    assign internal_rst_n = reset_sync_q[1];

    //--------------------------------------------------------------------------
    // External-lane adaptation and ingress allocation bundle
    //--------------------------------------------------------------------------

    // Internal point-to-point interconnects intentionally omit _i/_o suffixes;
    // direction is expressed only at each owning module boundary.

    logic [N-1:0]                 alloc_reserve_valid;
    logic                         alloc_reserve_ready;
    logic [N-1:0]                 alloc_commit_valid;
    logic [N-1:0][SEQ_W-1:0]      alloc_seq_tag;
    logic [N-1:0][SEQ_W-1:0]      alloc_target_seq_tag;
    logic [N-1:0][PACKET_W-1:0]   alloc_packet;
    logic [N-1:0][DELAY_W-1:0]    alloc_delay;
    logic [N-1:0]                 alloc_dep_required;

    ppe_ingress #(
        .PACKET_W (PACKET_W),
        .DESC_W   (DESC_W)
    ) u_ingress (
        .clk_i                    (clk),
        .rst_ni                   (internal_rst_n),
        .in_valid_i               (in_valid),
        .in_packet_i              (in_packet),
        .in_desc_i                (in_desc),
        .bkps_o                   (bkps),
        .alloc_reserve_valid_o    (alloc_reserve_valid),
        .alloc_reserve_ready_i    (alloc_reserve_ready),
        .alloc_commit_valid_o     (alloc_commit_valid),
        .alloc_seq_tag_o          (alloc_seq_tag),
        .alloc_target_seq_tag_o   (alloc_target_seq_tag),
        .alloc_packet_o           (alloc_packet),
        .alloc_delay_o            (alloc_delay),
        .alloc_dep_required_o     (alloc_dep_required)
    );

    //--------------------------------------------------------------------------
    // Issue table, candidate scheduler, and dependency connections
    //--------------------------------------------------------------------------

    logic [N-1:0]                    dep_status_valid;
    logic [N-1:0][SEQ_W-1:0]         dep_status_target_seq_tag;
    logic [N-1:0]                    dep_status_available;

    logic [CAND_WINDOW_DEPTH-1:0]                 candidate_valid;
    logic [CAND_WINDOW_DEPTH-1:0][SEQ_W-1:0]      candidate_seq_tag;
    logic [CAND_WINDOW_DEPTH-1:0][DELAY_W-1:0]    candidate_delay;

    logic [FE_NUM-1:0]               select_valid;
    logic [FE_NUM-1:0][CAND_WINDOW_DEPTH-1:0]
                                       select_candidate_onehot;
    logic [FE_NUM-1:0]               completion_valid;
    logic [FE_NUM-1:0][SEQ_W-1:0]    completion_seq_tag;

    logic [FE_NUM-1:0]               issue_valid;
    logic [FE_NUM-1:0][SEQ_W-1:0]    issue_seq_tag;
    logic [FE_NUM-1:0][PACKET_W-1:0] issue_packet;
    logic [FE_NUM-1:0][DELAY_W-1:0]  issue_delay;
    logic [FE_NUM-1:0]               issue_dep_required;
    logic [FE_NUM-1:0][SEQ_W-1:0]    issue_target_seq_tag;
    logic [FE_NUM-1:0][PACKET_W-1:0] issue_dep_data;
    logic [FE_NUM-1:0]               fe_out_valid;
    logic [FE_NUM-1:0][PACKET_W-1:0] fe_out_data;

    ppe_issue_table u_issue_table (
        .clk_i                       (clk),
        .rst_ni                      (internal_rst_n),
        .issue_alloc_valid_i         (alloc_commit_valid),
        .alloc_seq_tag_i             (alloc_seq_tag),
        .alloc_target_seq_tag_i      (alloc_target_seq_tag),
        .alloc_delay_i               (alloc_delay),
        .alloc_dep_required_i        (alloc_dep_required),
        .dep_status_valid_o          (dep_status_valid),
        .dep_status_target_seq_tag_o (dep_status_target_seq_tag),
        .dep_status_available_i      (dep_status_available),
        .completion_valid_i          (completion_valid),
        .completion_seq_tag_i        (completion_seq_tag),
        .candidate_valid_o           (candidate_valid),
        .candidate_seq_tag_o         (candidate_seq_tag),
        .candidate_delay_o           (candidate_delay),
        .select_valid_i              (select_valid),
        .select_candidate_onehot_i   (select_candidate_onehot),
        .issue_valid_o               (issue_valid),
        .issue_seq_tag_o             (issue_seq_tag),
        .issue_delay_o               (issue_delay),
        .issue_dep_required_o        (issue_dep_required),
        .issue_target_seq_tag_o      (issue_target_seq_tag)
    );

    ppe_fe_scheduler u_fe_scheduler (
        .clk_i                (clk),
        .rst_ni               (internal_rst_n),
        .candidate_valid_i    (candidate_valid),
        .candidate_seq_tag_i  (candidate_seq_tag),
        .candidate_delay_i    (candidate_delay),
        .select_valid_o       (select_valid),
        .select_candidate_onehot_o(select_candidate_onehot),
        .fe_out_valid_i       (fe_out_valid),
        .completion_valid_o   (completion_valid),
        .completion_seq_tag_o (completion_seq_tag)
    );

    //--------------------------------------------------------------------------
    // Forward Engine array
    //--------------------------------------------------------------------------

    for (genvar fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin : gen_fe
        fe_mock #(
            .PACKET_W (PACKET_W)
        ) u_fe (
            .clk           (clk),
            .rst_n         (internal_rst_n),
            .fe_in_valid   (issue_valid[fe_idx]),
            .fe_in_data    (issue_packet[fe_idx]),
            .fe_dep_valid  (issue_valid[fe_idx]
                            && issue_dep_required[fe_idx]),
            .fe_dep_data   (issue_dep_data[fe_idx]),
            .fe_desc_delay (issue_delay[fe_idx]),
            .fe_out_valid  (fe_out_valid[fe_idx]),
            .fe_out_data   (fe_out_data[fe_idx])
        );
    end

    //--------------------------------------------------------------------------
    // ROB, dependency resolution, writeback, and logical retirement
    //--------------------------------------------------------------------------

    logic [N-1:0]               retire_valid;
    logic [N-1:0][PACKET_W-1:0] retire_data;

    ppe_rob #(
        .PACKET_W (PACKET_W)
    ) u_rob (
        .clk_i                       (clk),
        .rst_ni                      (internal_rst_n),
        .alloc_reserve_valid_i       (alloc_reserve_valid),
        .alloc_reserve_ready_o       (alloc_reserve_ready),
        .alloc_commit_valid_i        (alloc_commit_valid),
        .alloc_seq_tag_i             (alloc_seq_tag),
        .alloc_packet_i              (alloc_packet),
        .dep_status_valid_i          (dep_status_valid),
        .dep_status_target_seq_tag_i (dep_status_target_seq_tag),
        .dep_status_available_o      (dep_status_available),
        .issue_valid_i               (issue_valid),
        .issue_seq_tag_i             (issue_seq_tag),
        .issue_dep_required_i        (issue_dep_required),
        .issue_target_seq_tag_i      (issue_target_seq_tag),
        .issue_packet_o              (issue_packet),
        .issue_dep_data_o            (issue_dep_data),
        .wb_valid_i                  (completion_valid),
        .wb_seq_tag_i                (completion_seq_tag),
        .wb_data_i                   (fe_out_data),
        .retire_valid_o              (retire_valid),
        .retire_data_o               (retire_data)
    );

    //--------------------------------------------------------------------------
    // Registered physical output mapping and external-lane adaptation
    //--------------------------------------------------------------------------

    ppe_retire_output #(
        .PACKET_W (PACKET_W)
    ) u_retire_output (
        .clk_i          (clk),
        .rst_ni         (internal_rst_n),
        .retire_valid_i (retire_valid),
        .retire_data_i  (retire_data),
        .out_valid_o    (out_valid),
        .out_packet_o   (out_packet)
    );

endmodule : ppe_top_sv

`default_nettype wire
