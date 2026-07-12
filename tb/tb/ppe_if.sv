// -----------------------------------------------------------------------------
// File       : ppe_if.sv
// Author     : Codex
// Description: PPE verification interface.
// -----------------------------------------------------------------------------

`ifndef PPE_IF_SV
`define PPE_IF_SV

interface ppe_if #(
    parameter int PACKET_W = 128
) (
    input logic clk,
    input logic rst_n
);

    logic                 in_valid0;
    logic [PACKET_W-1:0] in_packet0;
    logic [4:0]          in_desc0;
    logic                 in_valid1;
    logic [PACKET_W-1:0] in_packet1;
    logic [4:0]          in_desc1;
    logic                 in_valid2;
    logic [PACKET_W-1:0] in_packet2;
    logic [4:0]          in_desc2;
    logic                 in_valid3;
    logic [PACKET_W-1:0] in_packet3;
    logic [4:0]          in_desc3;
    logic                 bkps;

    logic                 out_valid0;
    logic [PACKET_W-1:0] out_packet0;
    logic                 out_valid1;
    logic [PACKET_W-1:0] out_packet1;
    logic                 out_valid2;
    logic [PACKET_W-1:0] out_packet2;
    logic                 out_valid3;
    logic [PACKET_W-1:0] out_packet3;

    task clear_inputs();
        in_valid0  <= 1'b0;
        in_packet0 <= '0;
        in_desc0   <= '0;
        in_valid1  <= 1'b0;
        in_packet1 <= '0;
        in_desc1   <= '0;
        in_valid2  <= 1'b0;
        in_packet2 <= '0;
        in_desc2   <= '0;
        in_valid3  <= 1'b0;
        in_packet3 <= '0;
        in_desc3   <= '0;
    endtask

endinterface

`endif
