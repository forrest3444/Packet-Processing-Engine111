`timescale 1ns/1ps

// Synthesizable stand-in for the external Forward Engine (FE).
//
// The real FE algorithm is a black box.  This model only preserves the PPE
// contract: one request may be accepted each cycle, delay d returns after
// d+1 cycles, and different delay values produce different result data.
module fe_mock #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input                       fe_in_valid,
    input      [PACKET_W-1:0]   fe_in_data,
    input                       fe_dep_valid,
    input      [PACKET_W-1:0]   fe_dep_data,
    input      [1:0]            fe_desc_delay,
    output                      fe_out_valid,
    output     [PACKET_W-1:0]  fe_out_data
);

    // slot 0 returns next; slot 3 is the farthest future return.  Dispatch
    // guarantees that a new request never overwrites an occupied target slot.
    reg [3:0]                 slot_valid;
    reg [PACKET_W-1:0]        slot_data [0:3];

    wire [PACKET_W-1:0]       input_data;
    wire [PACKET_W-1:0]       delay_mask;
    wire [PACKET_W-1:0]       result_data;

    // The verification VIP applies the same simple observable transformation.
    assign input_data = fe_in_data ^
                        (fe_dep_valid ? fe_dep_data : {PACKET_W{1'b0}});
    assign delay_mask = {{(PACKET_W-2){1'b0}}, fe_desc_delay};
    assign result_data = input_data ^ delay_mask;
    assign fe_out_valid = slot_valid[0];
    assign fe_out_data = slot_data[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_valid[0] <= 1'b0;
            slot_valid[1] <= 1'b0;
            slot_valid[2] <= 1'b0;
            slot_valid[3] <= 1'b0;
        end else begin
            // Time advances by shifting every pending result toward slot 0.
            slot_valid[0] <= slot_valid[1];
            slot_valid[1] <= slot_valid[2];
            slot_valid[2] <= slot_valid[3];
            slot_valid[3] <= 1'b0;

            if (slot_valid[1]) slot_data[0] <= slot_data[1];
            if (slot_valid[2]) slot_data[1] <= slot_data[2];
            if (slot_valid[3]) slot_data[2] <= slot_data[3];

            // A new result is written after the shift assignments.  With
            // nonblocking assignments this write wins if both address a slot;
            // such a collision is nevertheless forbidden by the PPE protocol.
            if (fe_in_valid) begin
                case (fe_desc_delay)
                    2'd0: begin
                        slot_valid[0] <= 1'b1;
                        slot_data[0] <= result_data;
                    end
                    2'd1: begin
                        slot_valid[1] <= 1'b1;
                        slot_data[1] <= result_data;
                    end
                    2'd2: begin
                        slot_valid[2] <= 1'b1;
                        slot_data[2] <= result_data;
                    end
                    default: begin
                        slot_valid[3] <= 1'b1;
                        slot_data[3] <= result_data;
                    end
                endcase
            end
        end
    end

endmodule
