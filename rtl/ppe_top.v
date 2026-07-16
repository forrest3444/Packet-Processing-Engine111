`timescale 1ns/1ps

// PPE integration level.
//
// Data path:
//   input lanes -> dispatch -> one of four FEs -> reorder -> output lanes
//
// This module intentionally contains no packet state.  Dispatch owns packets
// that have not entered an FE, while reorder owns ordering after allocation.
// All repeated connections are named separately to keep the RTL compatible
// with Verilog-2001 (unpacked array ports would require SystemVerilog).
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

    // The external reset asserts asynchronously.  The two flip-flops below
    // make its release synchronous and identical for every child module.
    reg [1:0] reset_sync;
    wire internal_rst_n;
    wire                      alloc_valid0;
    wire [4:0]                alloc_seq_tag0;
    wire [2:0]                alloc_seq_residue0;
    wire [3:0]                alloc_rob_id0;
    wire                      alloc_valid1;
    wire [4:0]                alloc_seq_tag1;
    wire [2:0]                alloc_seq_residue1;
    wire [3:0]                alloc_rob_id1;
    wire                      alloc_valid2;
    wire [4:0]                alloc_seq_tag2;
    wire [2:0]                alloc_seq_residue2;
    wire [3:0]                alloc_rob_id2;
    wire                      alloc_valid3;
    wire [4:0]                alloc_seq_tag3;
    wire [2:0]                alloc_seq_residue3;
    wire [3:0]                alloc_rob_id3;
    wire                      fallback_valid;
    wire [3:0]                fallback_rob_id;
    wire [4:0]                fallback_seq_tag;
    wire [2:0]                fallback_residue;
    wire                      fallback_ready;
    wire [PACKET_W-1:0]       fallback_data;
    wire                      fe_in_valid0;
    wire [PACKET_W-1:0]       fe_in_data0;
    wire                      fe_dep_valid0;
    wire [PACKET_W-1:0]       fe_dep_data0;
    wire [1:0]                fe_desc_delay0;
    wire                      fe_out_valid0;
    wire [PACKET_W-1:0]       fe_out_data0;
    wire                      fe_in_valid1;
    wire [PACKET_W-1:0]       fe_in_data1;
    wire                      fe_dep_valid1;
    wire [PACKET_W-1:0]       fe_dep_data1;
    wire [1:0]                fe_desc_delay1;
    wire                      fe_out_valid1;
    wire [PACKET_W-1:0]       fe_out_data1;
    wire                      fe_in_valid2;
    wire [PACKET_W-1:0]       fe_in_data2;
    wire                      fe_dep_valid2;
    wire [PACKET_W-1:0]       fe_dep_data2;
    wire [1:0]                fe_desc_delay2;
    wire                      fe_out_valid2;
    wire [PACKET_W-1:0]       fe_out_data2;
    wire                      fe_in_valid3;
    wire [PACKET_W-1:0]       fe_in_data3;
    wire                      fe_dep_valid3;
    wire [PACKET_W-1:0]       fe_dep_data3;
    wire [1:0]                fe_desc_delay3;
    wire                      fe_out_valid3;
    wire [PACKET_W-1:0]       fe_out_data3;
    wire                      wb_valid0;
    wire [3:0]                wb_rob_id0;
    wire [4:0]                wb_seq_tag0;
    wire [PACKET_W-1:0]       wb_data0;
    wire                      wb_valid1;
    wire [3:0]                wb_rob_id1;
    wire [4:0]                wb_seq_tag1;
    wire [PACKET_W-1:0]       wb_data1;
    wire                      wb_valid2;
    wire [3:0]                wb_rob_id2;
    wire [4:0]                wb_seq_tag2;
    wire [PACKET_W-1:0]       wb_data2;
    wire                      wb_valid3;
    wire [3:0]                wb_rob_id3;
    wire [4:0]                wb_seq_tag3;
    wire [PACKET_W-1:0]       wb_data3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_sync <= 2'b00;
        end else begin
            reset_sync <= {reset_sync[0], 1'b1};
        end
    end

    assign internal_rst_n = reset_sync[1];
    // Dispatch allocates sequence numbers, waits for dependencies, and books
    // a future FE return slot before issuing each request.
    ppe_dispatch #(
        .PACKET_W (PACKET_W)
    ) u_dispatch (
        .clk                  (clk),
        .rst_n                (internal_rst_n),
        .bkps                 (bkps),
        .in_valid0            (in_valid0),
        .in_packet0           (in_packet0),
        .in_desc0             (in_desc0),
        .in_valid1            (in_valid1),
        .in_packet1           (in_packet1),
        .in_desc1             (in_desc1),
        .in_valid2            (in_valid2),
        .in_packet2           (in_packet2),
        .in_desc2             (in_desc2),
        .in_valid3            (in_valid3),
        .in_packet3           (in_packet3),
        .in_desc3             (in_desc3),
        .alloc_valid0         (alloc_valid0),
        .alloc_seq_tag0       (alloc_seq_tag0),
        .alloc_seq_residue0   (alloc_seq_residue0),
        .alloc_rob_id0        (alloc_rob_id0),
        .alloc_valid1         (alloc_valid1),
        .alloc_seq_tag1       (alloc_seq_tag1),
        .alloc_seq_residue1   (alloc_seq_residue1),
        .alloc_rob_id1        (alloc_rob_id1),
        .alloc_valid2         (alloc_valid2),
        .alloc_seq_tag2       (alloc_seq_tag2),
        .alloc_seq_residue2   (alloc_seq_residue2),
        .alloc_rob_id2        (alloc_rob_id2),
        .alloc_valid3         (alloc_valid3),
        .alloc_seq_tag3       (alloc_seq_tag3),
        .alloc_seq_residue3   (alloc_seq_residue3),
        .alloc_rob_id3        (alloc_rob_id3),
        .fallback_valid       (fallback_valid),
        .fallback_rob_id      (fallback_rob_id),
        .fallback_seq_tag     (fallback_seq_tag),
        .fallback_residue     (fallback_residue),
        .fallback_ready       (fallback_ready),
        .fallback_data        (fallback_data),
        .fe_in_valid0         (fe_in_valid0),
        .fe_in_data0          (fe_in_data0),
        .fe_dep_valid0        (fe_dep_valid0),
        .fe_dep_data0         (fe_dep_data0),
        .fe_desc_delay0       (fe_desc_delay0),
        .fe_out_valid0        (fe_out_valid0),
        .fe_out_data0         (fe_out_data0),
        .fe_in_valid1         (fe_in_valid1),
        .fe_in_data1          (fe_in_data1),
        .fe_dep_valid1        (fe_dep_valid1),
        .fe_dep_data1         (fe_dep_data1),
        .fe_desc_delay1       (fe_desc_delay1),
        .fe_out_valid1        (fe_out_valid1),
        .fe_out_data1         (fe_out_data1),
        .fe_in_valid2         (fe_in_valid2),
        .fe_in_data2          (fe_in_data2),
        .fe_dep_valid2        (fe_dep_valid2),
        .fe_dep_data2         (fe_dep_data2),
        .fe_desc_delay2       (fe_desc_delay2),
        .fe_out_valid2        (fe_out_valid2),
        .fe_out_data2         (fe_out_data2),
        .fe_in_valid3         (fe_in_valid3),
        .fe_in_data3          (fe_in_data3),
        .fe_dep_valid3        (fe_dep_valid3),
        .fe_dep_data3         (fe_dep_data3),
        .fe_desc_delay3       (fe_desc_delay3),
        .fe_out_valid3        (fe_out_valid3),
        .fe_out_data3         (fe_out_data3),
        .wb_valid0            (wb_valid0),
        .wb_rob_id0           (wb_rob_id0),
        .wb_seq_tag0          (wb_seq_tag0),
        .wb_data0             (wb_data0),
        .wb_valid1            (wb_valid1),
        .wb_rob_id1           (wb_rob_id1),
        .wb_seq_tag1          (wb_seq_tag1),
        .wb_data1             (wb_data1),
        .wb_valid2            (wb_valid2),
        .wb_rob_id2           (wb_rob_id2),
        .wb_seq_tag2          (wb_seq_tag2),
        .wb_data2             (wb_data2),
        .wb_valid3            (wb_valid3),
        .wb_rob_id3           (wb_rob_id3),
        .wb_seq_tag3          (wb_seq_tag3),
        .wb_data3             (wb_data3)
    );

    // Reorder stores completed FE results and retires them in sequence order.
    ppe_reorder #(
        .PACKET_W (PACKET_W)
    ) u_reorder (
        .clk                  (clk),
        .rst_n                (internal_rst_n),
        .in_valid0            (in_valid0),
        .in_valid1            (in_valid1),
        .in_valid2            (in_valid2),
        .in_valid3            (in_valid3),
        .bkps                 (bkps),
        .alloc_valid0         (alloc_valid0),
        .alloc_seq_tag0       (alloc_seq_tag0),
        .alloc_seq_residue0   (alloc_seq_residue0),
        .alloc_rob_id0        (alloc_rob_id0),
        .alloc_valid1         (alloc_valid1),
        .alloc_seq_tag1       (alloc_seq_tag1),
        .alloc_seq_residue1   (alloc_seq_residue1),
        .alloc_rob_id1        (alloc_rob_id1),
        .alloc_valid2         (alloc_valid2),
        .alloc_seq_tag2       (alloc_seq_tag2),
        .alloc_seq_residue2   (alloc_seq_residue2),
        .alloc_rob_id2        (alloc_rob_id2),
        .alloc_valid3         (alloc_valid3),
        .alloc_seq_tag3       (alloc_seq_tag3),
        .alloc_seq_residue3   (alloc_seq_residue3),
        .alloc_rob_id3        (alloc_rob_id3),
        .fallback_valid       (fallback_valid),
        .fallback_rob_id      (fallback_rob_id),
        .fallback_seq_tag     (fallback_seq_tag),
        .fallback_residue     (fallback_residue),
        .fallback_ready       (fallback_ready),
        .fallback_data        (fallback_data),
        .wb_valid0            (wb_valid0),
        .wb_rob_id0           (wb_rob_id0),
        .wb_seq_tag0          (wb_seq_tag0),
        .wb_data0             (wb_data0),
        .wb_valid1            (wb_valid1),
        .wb_rob_id1           (wb_rob_id1),
        .wb_seq_tag1          (wb_seq_tag1),
        .wb_data1             (wb_data1),
        .wb_valid2            (wb_valid2),
        .wb_rob_id2           (wb_rob_id2),
        .wb_seq_tag2          (wb_seq_tag2),
        .wb_data2             (wb_data2),
        .wb_valid3            (wb_valid3),
        .wb_rob_id3           (wb_rob_id3),
        .wb_seq_tag3          (wb_seq_tag3),
        .wb_data3             (wb_data3),
        .out_valid0           (out_valid0),
        .out_packet0          (out_packet0),
        .out_valid1           (out_valid1),
        .out_packet1          (out_packet1),
        .out_valid2           (out_valid2),
        .out_packet2          (out_packet2),
        .out_valid3           (out_valid3),
        .out_packet3          (out_packet3)
    );

    // The four FE instances have identical behavior but independent pipelines.
    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe0 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid0),
        .fe_in_data    (fe_in_data0),
        .fe_dep_valid  (fe_dep_valid0),
        .fe_dep_data   (fe_dep_data0),
        .fe_desc_delay (fe_desc_delay0),
        .fe_out_valid  (fe_out_valid0),
        .fe_out_data   (fe_out_data0)
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe1 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid1),
        .fe_in_data    (fe_in_data1),
        .fe_dep_valid  (fe_dep_valid1),
        .fe_dep_data   (fe_dep_data1),
        .fe_desc_delay (fe_desc_delay1),
        .fe_out_valid  (fe_out_valid1),
        .fe_out_data   (fe_out_data1)
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe2 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid2),
        .fe_in_data    (fe_in_data2),
        .fe_dep_valid  (fe_dep_valid2),
        .fe_dep_data   (fe_dep_data2),
        .fe_desc_delay (fe_desc_delay2),
        .fe_out_valid  (fe_out_valid2),
        .fe_out_data   (fe_out_data2)
    );

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe3 (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (fe_in_valid3),
        .fe_in_data    (fe_in_data3),
        .fe_dep_valid  (fe_dep_valid3),
        .fe_dep_data   (fe_dep_data3),
        .fe_desc_delay (fe_desc_delay3),
        .fe_out_valid  (fe_out_valid3),
        .fe_out_data   (fe_out_data3)
    );

endmodule
