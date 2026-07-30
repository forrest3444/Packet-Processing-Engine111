`timescale 1ns/1ps
`default_nettype none

// Synthesizable stand-in for the external Forward Engine.
module FE_MOCK #(
    parameter integer PACKET_W = 128
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  fe_in_valid,
    input  wire [PACKET_W-1:0]   fe_in_data,
    input  wire                  fe_dep_valid,
    input  wire [PACKET_W-1:0]   fe_dep_data,
    input  wire [1:0]            fe_desc_delay,
    output wire                  fe_out_valid,
    output wire [PACKET_W-1:0]   fe_out_data
);

    reg  [3:0]          slot_valid;
    reg  [PACKET_W-1:0] slot_data [0:3];
    wire [PACKET_W-1:0] input_data;
    wire [PACKET_W-1:0] delay_mask;
    wire [PACKET_W-1:0] result_data;

    assign input_data   = fe_in_data
                          ^ (fe_dep_valid
                             ? fe_dep_data : {PACKET_W{1'b0}});
    assign delay_mask   = {{(PACKET_W-2){1'b0}}, fe_desc_delay};
    assign result_data  = input_data ^ delay_mask;
    assign fe_out_valid = slot_valid[0];
    assign fe_out_data  = slot_data[0];

    always @(posedge clk or negedge rst_n) begin : fe_pipeline_state
        if (!rst_n) begin
            slot_valid <= 4'b0000;
        end else begin
            slot_valid[0] <= slot_valid[1];
            slot_valid[1] <= slot_valid[2];
            slot_valid[2] <= slot_valid[3];
            slot_valid[3] <= 1'b0;

            if (slot_valid[1]) begin
                slot_data[0] <= slot_data[1];
            end
            if (slot_valid[2]) begin
                slot_data[1] <= slot_data[2];
            end
            if (slot_valid[3]) begin
                slot_data[2] <= slot_data[3];
            end

            if (fe_in_valid) begin
                case (fe_desc_delay)
                    2'd0: begin
                        slot_valid[0] <= 1'b1;
                        slot_data[0]  <= result_data;
                    end
                    2'd1: begin
                        slot_valid[1] <= 1'b1;
                        slot_data[1]  <= result_data;
                    end
                    2'd2: begin
                        slot_valid[2] <= 1'b1;
                        slot_data[2]  <= result_data;
                    end
                    default: begin
                        slot_valid[3] <= 1'b1;
                        slot_data[3]  <= result_data;
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
