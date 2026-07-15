`timescale 1ns/1ps

module ppe_top #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input                       in_valid0,
    input      [PACKET_W-1:0]   in_packet0,
    input      [4:0]            in_desc0,
    input                       in_valid1,
    input      [PACKET_W-1:0]   in_packet1,
    input      [4:0]            in_desc1,
    input                       in_valid2,
    input      [PACKET_W-1:0]   in_packet2,
    input      [4:0]            in_desc2,
    input                       in_valid3,
    input      [PACKET_W-1:0]   in_packet3,
    input      [4:0]            in_desc3,
    output                      bkps,
    output                      out_valid0,
    output     [PACKET_W-1:0]   out_packet0,
    output                      out_valid1,
    output     [PACKET_W-1:0]   out_packet1,
    output                      out_valid2,
    output     [PACKET_W-1:0]   out_packet2,
    output                      out_valid3,
    output     [PACKET_W-1:0]   out_packet3
);

    reg [1:0] reset_sync;
    wire internal_rst_n;
    wire [3:0]                in_valid_bus;
    wire [4*PACKET_W-1:0]     in_packet_bus;
    wire [19:0]               in_desc_bus;
    wire [3:0]                alloc_valid;
    wire [19:0]               alloc_seq_tag;
    wire [11:0]               alloc_seq_residue;
    wire [15:0]               alloc_rob_id;
    wire                      fallback_valid;
    wire [3:0]                fallback_rob_id;
    wire [4:0]                fallback_seq_tag;
    wire [2:0]                fallback_residue;
    wire                      fallback_ready;
    wire [PACKET_W-1:0]       fallback_data;
    wire [3:0]                fe_in_valid;
    wire [4*PACKET_W-1:0]     fe_in_data;
    wire [3:0]                fe_dep_valid;
    wire [4*PACKET_W-1:0]     fe_dep_data;
    wire [7:0]                fe_desc_delay;
    wire [3:0]                fe_out_valid;
    wire [4*PACKET_W-1:0]     fe_out_data;
    wire [3:0]                wb_valid;
    wire [15:0]               wb_rob_id;
    wire [19:0]               wb_seq_tag;
    wire [4*PACKET_W-1:0]     wb_data;
    wire [3:0]                out_valid_bus;
    wire [4*PACKET_W-1:0]     out_packet_bus;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_sync <= 2'b00;
        end else begin
            reset_sync <= {reset_sync[0], 1'b1};
        end
    end

    assign internal_rst_n = reset_sync[1];
    assign in_valid_bus = {in_valid3, in_valid2, in_valid1, in_valid0};
    assign in_packet_bus = {in_packet3, in_packet2, in_packet1, in_packet0};
    assign in_desc_bus = {in_desc3, in_desc2, in_desc1, in_desc0};
    assign out_valid0 = out_valid_bus[0];
    assign out_valid1 = out_valid_bus[1];
    assign out_valid2 = out_valid_bus[2];
    assign out_valid3 = out_valid_bus[3];
    assign out_packet0 = out_packet_bus[0*PACKET_W +: PACKET_W];
    assign out_packet1 = out_packet_bus[1*PACKET_W +: PACKET_W];
    assign out_packet2 = out_packet_bus[2*PACKET_W +: PACKET_W];
    assign out_packet3 = out_packet_bus[3*PACKET_W +: PACKET_W];

    ppe_dispatch #(
        .PACKET_W (PACKET_W)
    ) u_dispatch (
        .clk                  (clk),
        .rst_n                (internal_rst_n),
        .bkps                 (bkps),
        .in_valid             (in_valid_bus),
        .in_packet            (in_packet_bus),
        .in_desc              (in_desc_bus),
        .alloc_valid          (alloc_valid),
        .alloc_seq_tag        (alloc_seq_tag),
        .alloc_seq_residue    (alloc_seq_residue),
        .alloc_rob_id         (alloc_rob_id),
        .fallback_valid       (fallback_valid),
        .fallback_rob_id      (fallback_rob_id),
        .fallback_seq_tag     (fallback_seq_tag),
        .fallback_residue     (fallback_residue),
        .fallback_ready       (fallback_ready),
        .fallback_data        (fallback_data),
        .fe_in_valid          (fe_in_valid),
        .fe_in_data           (fe_in_data),
        .fe_dep_valid         (fe_dep_valid),
        .fe_dep_data          (fe_dep_data),
        .fe_desc_delay        (fe_desc_delay),
        .fe_out_valid         (fe_out_valid),
        .fe_out_data          (fe_out_data),
        .wb_valid             (wb_valid),
        .wb_rob_id            (wb_rob_id),
        .wb_seq_tag           (wb_seq_tag),
        .wb_data              (wb_data)
    );

    ppe_reorder #(
        .PACKET_W (PACKET_W)
    ) u_reorder (
        .clk                  (clk),
        .rst_n                (internal_rst_n),
        .in_valid             (in_valid_bus),
        .bkps                 (bkps),
        .alloc_valid          (alloc_valid),
        .alloc_seq_tag        (alloc_seq_tag),
        .alloc_seq_residue    (alloc_seq_residue),
        .alloc_rob_id         (alloc_rob_id),
        .fallback_valid       (fallback_valid),
        .fallback_rob_id      (fallback_rob_id),
        .fallback_seq_tag     (fallback_seq_tag),
        .fallback_residue     (fallback_residue),
        .fallback_ready       (fallback_ready),
        .fallback_data        (fallback_data),
        .wb_valid             (wb_valid),
        .wb_rob_id            (wb_rob_id),
        .wb_seq_tag           (wb_seq_tag),
        .wb_data              (wb_data),
        .out_valid            (out_valid_bus),
        .out_packet           (out_packet_bus)
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe0 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid[0]),
        .fe_in_data    (fe_in_data[0*PACKET_W +: PACKET_W]),
        .fe_dep_valid  (fe_dep_valid[0]),
        .fe_dep_data   (fe_dep_data[0*PACKET_W +: PACKET_W]),
        .fe_desc_delay (fe_desc_delay[0*2 +: 2]),
        .fe_out_valid  (fe_out_valid[0]),
        .fe_out_data   (fe_out_data[0*PACKET_W +: PACKET_W])
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe1 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid[1]),
        .fe_in_data    (fe_in_data[1*PACKET_W +: PACKET_W]),
        .fe_dep_valid  (fe_dep_valid[1]),
        .fe_dep_data   (fe_dep_data[1*PACKET_W +: PACKET_W]),
        .fe_desc_delay (fe_desc_delay[1*2 +: 2]),
        .fe_out_valid  (fe_out_valid[1]),
        .fe_out_data   (fe_out_data[1*PACKET_W +: PACKET_W])
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe2 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid[2]),
        .fe_in_data    (fe_in_data[2*PACKET_W +: PACKET_W]),
        .fe_dep_valid  (fe_dep_valid[2]),
        .fe_dep_data   (fe_dep_data[2*PACKET_W +: PACKET_W]),
        .fe_desc_delay (fe_desc_delay[2*2 +: 2]),
        .fe_out_valid  (fe_out_valid[2]),
        .fe_out_data   (fe_out_data[2*PACKET_W +: PACKET_W])
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe3 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid[3]),
        .fe_in_data    (fe_in_data[3*PACKET_W +: PACKET_W]),
        .fe_dep_valid  (fe_dep_valid[3]),
        .fe_dep_data   (fe_dep_data[3*PACKET_W +: PACKET_W]),
        .fe_desc_delay (fe_desc_delay[3*2 +: 2]),
        .fe_out_valid  (fe_out_valid[3]),
        .fe_out_data   (fe_out_data[3*PACKET_W +: PACKET_W])
    );

endmodule
