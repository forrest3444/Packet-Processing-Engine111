// -----------------------------------------------------------------------------
// File       : ppe_top.v
// Author     : Codex
// Description: PPE top level for 4-lane configuration with mock FE array.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module ppe_top #(
    parameter integer PACKET_W  = 128,
    parameter integer RESULT_W  = 128,
    parameter integer ROB_DEPTH = 16,
    parameter integer ROB_AW    = 4
) (
    input                     clk,
    input                     rst_n,

    input                     in_valid0,
    input      [PACKET_W-1:0] in_packet0,
    input      [4:0]          in_desc0,
    input                     in_valid1,
    input      [PACKET_W-1:0] in_packet1,
    input      [4:0]          in_desc1,
    input                     in_valid2,
    input      [PACKET_W-1:0] in_packet2,
    input      [4:0]          in_desc2,
    input                     in_valid3,
    input      [PACKET_W-1:0] in_packet3,
    input      [4:0]          in_desc3,
    output                    bkps,

    output                    out_valid0,
    output     [PACKET_W-1:0] out_packet0,
    output                    out_valid1,
    output     [PACKET_W-1:0] out_packet1,
    output                    out_valid2,
    output     [PACKET_W-1:0] out_packet2,
    output                    out_valid3,
    output     [PACKET_W-1:0] out_packet3
);

    wire                    fe_in_valid0;
    wire                    fe_in_ready0;
    wire [PACKET_W-1:0]     fe_in_packet0;
    wire                    fe_in_valid1;
    wire                    fe_in_ready1;
    wire [PACKET_W-1:0]     fe_in_packet1;
    wire                    fe_in_valid2;
    wire                    fe_in_ready2;
    wire [PACKET_W-1:0]     fe_in_packet2;
    wire                    fe_in_valid3;
    wire                    fe_in_ready3;
    wire [PACKET_W-1:0]     fe_in_packet3;

    wire                    fe_out_valid0;
    wire                    fe_out_ready0;
    wire [PACKET_W-1:0]     fe_out_packet0;
    wire [RESULT_W-1:0]     fe_out_result0;
    wire                    fe_out_valid1;
    wire                    fe_out_ready1;
    wire [PACKET_W-1:0]     fe_out_packet1;
    wire [RESULT_W-1:0]     fe_out_result1;
    wire                    fe_out_valid2;
    wire                    fe_out_ready2;
    wire [PACKET_W-1:0]     fe_out_packet2;
    wire [RESULT_W-1:0]     fe_out_result2;
    wire                    fe_out_valid3;
    wire                    fe_out_ready3;
    wire [PACKET_W-1:0]     fe_out_packet3;
    wire [RESULT_W-1:0]     fe_out_result3;

    ppe_core #(
        .PACKET_W  (PACKET_W),
        .RESULT_W  (RESULT_W),
        .ROB_DEPTH (ROB_DEPTH),
        .ROB_AW    (ROB_AW)
    ) u_ppe_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_valid0      (in_valid0),
        .in_packet0     (in_packet0),
        .in_desc0       (in_desc0),
        .in_valid1      (in_valid1),
        .in_packet1     (in_packet1),
        .in_desc1       (in_desc1),
        .in_valid2      (in_valid2),
        .in_packet2     (in_packet2),
        .in_desc2       (in_desc2),
        .in_valid3      (in_valid3),
        .in_packet3     (in_packet3),
        .in_desc3       (in_desc3),
        .bkps           (bkps),
        .out_valid0     (out_valid0),
        .out_packet0    (out_packet0),
        .out_valid1     (out_valid1),
        .out_packet1    (out_packet1),
        .out_valid2     (out_valid2),
        .out_packet2    (out_packet2),
        .out_valid3     (out_valid3),
        .out_packet3    (out_packet3),
        .fe_in_valid0   (fe_in_valid0),
        .fe_in_ready0   (fe_in_ready0),
        .fe_in_packet0  (fe_in_packet0),
        .fe_in_valid1   (fe_in_valid1),
        .fe_in_ready1   (fe_in_ready1),
        .fe_in_packet1  (fe_in_packet1),
        .fe_in_valid2   (fe_in_valid2),
        .fe_in_ready2   (fe_in_ready2),
        .fe_in_packet2  (fe_in_packet2),
        .fe_in_valid3   (fe_in_valid3),
        .fe_in_ready3   (fe_in_ready3),
        .fe_in_packet3  (fe_in_packet3),
        .fe_out_valid0  (fe_out_valid0),
        .fe_out_ready0  (fe_out_ready0),
        .fe_out_packet0 (fe_out_packet0),
        .fe_out_result0 (fe_out_result0),
        .fe_out_valid1  (fe_out_valid1),
        .fe_out_ready1  (fe_out_ready1),
        .fe_out_packet1 (fe_out_packet1),
        .fe_out_result1 (fe_out_result1),
        .fe_out_valid2  (fe_out_valid2),
        .fe_out_ready2  (fe_out_ready2),
        .fe_out_packet2 (fe_out_packet2),
        .fe_out_result2 (fe_out_result2),
        .fe_out_valid3  (fe_out_valid3),
        .fe_out_ready3  (fe_out_ready3),
        .fe_out_packet3 (fe_out_packet3),
        .fe_out_result3 (fe_out_result3)
    );

    fe_mock #(
        .PACKET_W (PACKET_W),
        .RESULT_W (RESULT_W),
        .FE_ID    (0)
    ) u_fe0 (
        .clk           (clk),
        .rst_n         (rst_n),
        .fe_in_valid   (fe_in_valid0),
        .fe_in_ready   (fe_in_ready0),
        .fe_in_packet  (fe_in_packet0),
        .fe_out_valid  (fe_out_valid0),
        .fe_out_ready  (fe_out_ready0),
        .fe_out_packet (fe_out_packet0),
        .fe_out_result (fe_out_result0)
    );

    fe_mock #(
        .PACKET_W (PACKET_W),
        .RESULT_W (RESULT_W),
        .FE_ID    (1)
    ) u_fe1 (
        .clk           (clk),
        .rst_n         (rst_n),
        .fe_in_valid   (fe_in_valid1),
        .fe_in_ready   (fe_in_ready1),
        .fe_in_packet  (fe_in_packet1),
        .fe_out_valid  (fe_out_valid1),
        .fe_out_ready  (fe_out_ready1),
        .fe_out_packet (fe_out_packet1),
        .fe_out_result (fe_out_result1)
    );

    fe_mock #(
        .PACKET_W (PACKET_W),
        .RESULT_W (RESULT_W),
        .FE_ID    (2)
    ) u_fe2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .fe_in_valid   (fe_in_valid2),
        .fe_in_ready   (fe_in_ready2),
        .fe_in_packet  (fe_in_packet2),
        .fe_out_valid  (fe_out_valid2),
        .fe_out_ready  (fe_out_ready2),
        .fe_out_packet (fe_out_packet2),
        .fe_out_result (fe_out_result2)
    );

    fe_mock #(
        .PACKET_W (PACKET_W),
        .RESULT_W (RESULT_W),
        .FE_ID    (3)
    ) u_fe3 (
        .clk           (clk),
        .rst_n         (rst_n),
        .fe_in_valid   (fe_in_valid3),
        .fe_in_ready   (fe_in_ready3),
        .fe_in_packet  (fe_in_packet3),
        .fe_out_valid  (fe_out_valid3),
        .fe_out_ready  (fe_out_ready3),
        .fe_out_packet (fe_out_packet3),
        .fe_out_result (fe_out_result3)
    );

endmodule
