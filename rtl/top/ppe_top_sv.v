`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Registered top-level integration for the four-FE packet-processing engine.
//------------------------------------------------------------------------------
module PPE_TOP_SV #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W,
    parameter integer DESC_W   = `PPE_DEFAULT_DESC_W
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire [`PPE_N-1:0]                 in_valid,
    input  wire [`PPE_N*PACKET_W-1:0]        in_packet,
    input  wire [`PPE_N*DESC_W-1:0]          in_desc,
    output wire                              bkps,
    output wire [`PPE_N-1:0]                 out_valid,
    output wire [`PPE_N*PACKET_W-1:0]        out_packet
);

    reg  [1:0] reset_sync_q;
    wire       internal_rst_n;

    // Point-to-point interconnects omit direction suffixes intentionally.
    wire [`PPE_N-1:0]                         alloc_reserve_valid;
    wire                                      alloc_reserve_ready;
    wire [`PPE_N-1:0]                         alloc_commit_valid;
    wire [`PPE_N*`PPE_SEQ_W-1:0]              alloc_seq_tag;
    wire [`PPE_N*`PPE_SEQ_W-1:0]              alloc_target_seq_tag;
    wire [`PPE_N*PACKET_W-1:0]                alloc_packet;
    wire [`PPE_N*`PPE_DELAY_W-1:0]            alloc_delay;
    wire [`PPE_N-1:0]                         alloc_dep_required;

    wire [`PPE_N-1:0]                         dep_status_valid;
    wire [`PPE_N*`PPE_SEQ_W-1:0]              dep_status_target_seq_tag;
    wire [`PPE_N-1:0]                         dep_status_available;

    wire [`PPE_FE_NUM-1:0]                    completion_valid;
    wire [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         completion_seq_tag;

    wire [`PPE_FE_NUM-1:0]                    issue_valid;
    wire [`PPE_FE_NUM*PACKET_W-1:0]           issue_packet;
    wire [`PPE_FE_NUM*`PPE_DELAY_W-1:0]       issue_delay;
    wire [`PPE_FE_NUM-1:0]                    issue_dep_required;
    wire [`PPE_FE_NUM*PACKET_W-1:0]           issue_dep_data;
    wire [`PPE_FE_NUM-1:0]                    gather_valid;
    wire [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         gather_seq_tag;
    wire [`PPE_FE_NUM-1:0]                    gather_dep_required;
    wire [`PPE_FE_NUM*`PPE_SEQ_W-1:0]         gather_target_seq_tag;
    wire [`PPE_FE_NUM*PACKET_W-1:0]           gather_packet;
    wire [`PPE_FE_NUM*PACKET_W-1:0]           gather_dep_data;
    wire [`PPE_FE_NUM-1:0]                    fe_out_valid;
    wire [`PPE_FE_NUM*PACKET_W-1:0]           fe_out_data;

    wire [`PPE_N-1:0]                         retire_valid;
    wire [`PPE_N*PACKET_W-1:0]                retire_data;

    always @(posedge clk or negedge rst_n) begin : reset_synchronizer
        if (!rst_n)
            reset_sync_q <= 2'b00;
        else
            reset_sync_q <= {reset_sync_q[0], 1'b1};
    end

    assign internal_rst_n = reset_sync_q[1];

    PPE_INGRESS #(
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

    PPE_SCHEDULER #(
        .PACKET_W (PACKET_W)
    ) u_scheduler (
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
        .gather_valid_o              (gather_valid),
        .gather_seq_tag_o            (gather_seq_tag),
        .gather_dep_required_o       (gather_dep_required),
        .gather_target_seq_tag_o     (gather_target_seq_tag),
        .gather_packet_i             (gather_packet),
        .gather_dep_data_i           (gather_dep_data),
        .issue_valid_o               (issue_valid),
        .issue_packet_o              (issue_packet),
        .issue_delay_o               (issue_delay),
        .issue_dep_required_o        (issue_dep_required),
        .issue_dep_data_o            (issue_dep_data),
        .fe_out_valid_i              (fe_out_valid),
        .completion_valid_o          (completion_valid),
        .completion_seq_tag_o        (completion_seq_tag)
    );

    genvar fe_idx;
    generate
        for (fe_idx = 0; fe_idx < `PPE_FE_NUM; fe_idx = fe_idx + 1) begin : gen_fe
            FE_MOCK #(
                .PACKET_W (PACKET_W)
            ) u_fe (
                .clk           (clk),
                .rst_n         (internal_rst_n),
                .fe_in_valid   (issue_valid[fe_idx]),
                .fe_in_data    (issue_packet[fe_idx*PACKET_W +: PACKET_W]),
                .fe_dep_valid  (issue_valid[fe_idx]
                                && issue_dep_required[fe_idx]),
                .fe_dep_data   (issue_dep_data[fe_idx*PACKET_W +: PACKET_W]),
                .fe_desc_delay (issue_delay[fe_idx*`PPE_DELAY_W
                                             +: `PPE_DELAY_W]),
                .fe_out_valid  (fe_out_valid[fe_idx]),
                .fe_out_data   (fe_out_data[fe_idx*PACKET_W +: PACKET_W])
            );
        end
    endgenerate

    PPE_ROB #(
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
        .gather_valid_i              (gather_valid),
        .gather_seq_tag_i            (gather_seq_tag),
        .gather_dep_required_i       (gather_dep_required),
        .gather_target_seq_tag_i     (gather_target_seq_tag),
        .gather_packet_o             (gather_packet),
        .gather_dep_data_o           (gather_dep_data),
        .wb_valid_i                  (completion_valid),
        .wb_seq_tag_i                (completion_seq_tag),
        .wb_data_i                   (fe_out_data),
        .retire_valid_o              (retire_valid),
        .retire_data_o               (retire_data)
    );

    PPE_RETIRE_OUTPUT #(
        .PACKET_W (PACKET_W)
    ) u_retire_output (
        .clk_i          (clk),
        .rst_ni         (internal_rst_n),
        .retire_valid_i (retire_valid),
        .retire_data_i  (retire_data),
        .out_valid_o    (out_valid),
        .out_packet_o   (out_packet)
    );

endmodule

`default_nettype wire
