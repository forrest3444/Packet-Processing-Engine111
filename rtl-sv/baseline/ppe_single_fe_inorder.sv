`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// Complete single-FE in-order architecture baseline.
//
// The design captures four-lane input batches, stores packets in sequence
// order, and permits only one FE request in flight. FE completion is therefore
// also retirement. The last eight retired results form the dependency history.
// fe_mock is the only instantiated submodule.
//------------------------------------------------------------------------------

module ppe_single_fe_inorder #(
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W,
    parameter int DESC_W   = ppe_types_pkg::DEFAULT_DESC_W
) (
    input  logic                                          clk,
    input  logic                                          rst_n,
    input  logic [ppe_types_pkg::N-1:0]                  in_valid,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]    in_packet,
    input  logic [ppe_types_pkg::N-1:0][DESC_W-1:0]      in_desc,
    output logic                                          bkps,
    output logic [ppe_types_pkg::N-1:0]                  out_valid,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]    out_packet
);

    import ppe_types_pkg::*;

    localparam int INPUT_SLOTS  = 2;
    localparam int FIFO_DEPTH   = 32;
    localparam int FIFO_PTR_W   = $clog2(FIFO_DEPTH);
    localparam int FIFO_COUNT_W = $clog2(FIFO_DEPTH + 1);
    localparam int LANE_COUNT_W = $clog2(N + 1);
    localparam int DEP_MSB      = DESC_W - 1;
    localparam int DEP_LSB      = DELAY_W;

    typedef logic [FIFO_PTR_W-1:0] fifo_ptr_t;
    typedef logic [FIFO_COUNT_W-1:0] fifo_count_t;
    typedef logic [LANE_COUNT_W-1:0] lane_count_t;

    //--------------------------------------------------------------------------
    // Reset and registered input boundary
    //--------------------------------------------------------------------------

    logic [1:0] reset_sync_q;
    logic       internal_rst_n;

    logic [INPUT_SLOTS-1:0][N-1:0]               input_valid_q;
    logic [INPUT_SLOTS-1:0][N-1:0][PACKET_W-1:0] input_packet_q;
    logic [INPUT_SLOTS-1:0][N-1:0][DESC_W-1:0]   input_desc_q;
    logic                                         input_rd_ptr_q;
    logic                                         input_wr_ptr_q;
    logic [1:0]                                   input_count_q;
    logic [1:0]                                   input_count_d;
    logic                                         bkps_q;
    logic                                         bkps_d;
    logic                                         capture_batch;
    logic                                         release_batch;

    always_ff @(posedge clk or negedge rst_n) begin : reset_synchronizer
        if (!rst_n) begin
            reset_sync_q <= 2'b00;
        end else begin
            reset_sync_q <= {reset_sync_q[0], 1'b1};
        end
    end

    assign internal_rst_n = reset_sync_q[1];
    assign capture_batch  = !bkps_q;
    assign bkps           = bkps_q;

    //--------------------------------------------------------------------------
    // Sequential packet FIFO and descriptor decode
    //--------------------------------------------------------------------------

    logic [PACKET_W-1:0] fifo_packet_q       [FIFO_DEPTH];
    seq_tag_t            fifo_seq_tag_q      [FIFO_DEPTH];
    seq_tag_t            fifo_target_tag_q   [FIFO_DEPTH];
    delay_t              fifo_delay_q        [FIFO_DEPTH];
    logic                fifo_dep_required_q [FIFO_DEPTH];

    fifo_ptr_t           fifo_head_ptr_q;
    fifo_ptr_t           fifo_tail_ptr_q;
    fifo_count_t         fifo_count_q;
    fifo_count_t         fifo_count_d;
    seq_tag_t            next_seq_tag_q;

    logic [N-1:0]        head_lane_valid;
    lane_count_t         lane_rank [N];
    lane_count_t         head_packet_count;
    lane_count_t         lower_pair_count;
    lane_count_t         upper_pair_count;
    fifo_count_t         fifo_free_count;
    logic                enqueue_batch;
    logic                head_nonempty;

    always_comb begin : input_head_decode
        head_lane_valid  = '0;
        lane_rank        = '{default:'0};
        lower_pair_count = '0;
        upper_pair_count = '0;
        head_packet_count = '0;

        if (input_count_q != 2'd0) begin
            head_lane_valid = input_valid_q[input_rd_ptr_q];
        end

        lower_pair_count = lane_count_t'(head_lane_valid[0])
            + lane_count_t'(head_lane_valid[1]);
        upper_pair_count = lane_count_t'(head_lane_valid[2])
            + lane_count_t'(head_lane_valid[3]);
        lane_rank[0] = '0;
        lane_rank[1] = lane_count_t'(head_lane_valid[0]);
        lane_rank[2] = lower_pair_count;
        lane_rank[3] = lower_pair_count
            + lane_count_t'(head_lane_valid[2]);
        head_packet_count = lower_pair_count + upper_pair_count;
    end

    assign head_nonempty = |head_lane_valid;
    assign fifo_free_count = fifo_count_t'(FIFO_DEPTH) - fifo_count_q;
    assign enqueue_batch = (input_count_q != 2'd0)
        && head_nonempty
        && (fifo_free_count >= fifo_count_t'(head_packet_count));
    assign release_batch = (input_count_q != 2'd0)
        && (!head_nonempty || enqueue_batch);

    always_comb begin : input_occupancy
        input_count_d = input_count_q;
        unique case ({capture_batch, release_batch})
            2'b10: input_count_d = input_count_q + 2'd1;
            2'b01: input_count_d = input_count_q - 2'd1;
            default: begin end
        endcase
        bkps_d = (input_count_d == 2'd2);
    end

    //--------------------------------------------------------------------------
    // Retired dependency history and single-FE dispatch
    //--------------------------------------------------------------------------

    logic [RESULT_BANKS-1:0]               history_valid_q;
    logic [RESULT_BANKS-1:0][SEQ_W-1:0]    history_seq_tag_q;
    logic [RESULT_BANKS-1:0][PACKET_W-1:0] history_data_q;

    logic                inflight_valid_q;
    seq_tag_t            inflight_seq_tag_q;
    logic                dispatch_packet;
    logic                head_dep_available;
    logic [PACKET_W-1:0] head_dep_data;
    logic [HISTORY_ID_W-1:0] head_history_id;

    logic                fe_out_valid;
    logic [PACKET_W-1:0] fe_out_data;

    always_comb begin : dependency_lookup
        head_history_id   = '0;
        head_dep_available = 1'b0;
        head_dep_data      = '0;

        if (fifo_count_q != '0) begin
            head_history_id =
                fifo_target_tag_q[fifo_head_ptr_q][HISTORY_ID_W-1:0];
            if (!fifo_dep_required_q[fifo_head_ptr_q]) begin
                head_dep_available = 1'b1;
            end else if (history_valid_q[head_history_id]
                         && (history_seq_tag_q[head_history_id]
                             == fifo_target_tag_q[fifo_head_ptr_q])) begin
                head_dep_available = 1'b1;
                head_dep_data = history_data_q[head_history_id];
            end
        end
    end

    assign dispatch_packet = (fifo_count_q != '0)
        && !inflight_valid_q
        && head_dep_available;

    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe (
        .clk           (clk),
        .rst_n         (internal_rst_n),
        .fe_in_valid   (dispatch_packet),
        .fe_in_data    (fifo_packet_q[fifo_head_ptr_q]),
        .fe_dep_valid  (dispatch_packet
                        && fifo_dep_required_q[fifo_head_ptr_q]),
        .fe_dep_data   (head_dep_data),
        .fe_desc_delay (fifo_delay_q[fifo_head_ptr_q]),
        .fe_out_valid  (fe_out_valid),
        .fe_out_data   (fe_out_data)
    );

    //--------------------------------------------------------------------------
    // FIFO, input buffer, completion, and output state
    //--------------------------------------------------------------------------

    always_comb begin : fifo_occupancy
        fifo_count_d = fifo_count_q;
        if (enqueue_batch) begin
            fifo_count_d = fifo_count_d
                + fifo_count_t'(head_packet_count);
        end
        if (dispatch_packet) begin
            fifo_count_d = fifo_count_d - fifo_count_t'(1);
        end
    end

    always_ff @(posedge clk or negedge internal_rst_n) begin : input_state
        if (!internal_rst_n) begin
            input_rd_ptr_q <= 1'b0;
            input_wr_ptr_q <= 1'b0;
            input_count_q  <= 2'd0;
            bkps_q         <= 1'b1;
        end else begin
            if (capture_batch && !input_wr_ptr_q) begin
                input_valid_q[0]  <= in_valid;
                input_packet_q[0] <= in_packet;
                input_desc_q[0]   <= in_desc;
            end
            if (capture_batch && input_wr_ptr_q) begin
                input_valid_q[1]  <= in_valid;
                input_packet_q[1] <= in_packet;
                input_desc_q[1]   <= in_desc;
            end
            if (capture_batch) begin
                input_wr_ptr_q <= ~input_wr_ptr_q;
            end
            if (release_batch) begin
                input_rd_ptr_q <= ~input_rd_ptr_q;
            end
            input_count_q <= input_count_d;
            bkps_q        <= bkps_d;
        end
    end

    always_ff @(posedge clk or negedge internal_rst_n) begin : fifo_state
        if (!internal_rst_n) begin
            fifo_head_ptr_q <= '0;
            fifo_tail_ptr_q <= '0;
            fifo_count_q    <= '0;
            next_seq_tag_q  <= '0;
        end else begin
            if (enqueue_batch) begin
                for (int lane = 0; lane < N; lane++) begin
                    if (head_lane_valid[lane]) begin
                        fifo_ptr_t write_id;
                        seq_tag_t  allocation_tag;
                        logic [DESC_W-DEP_LSB-1:0] dep_offset;

                        write_id = fifo_tail_ptr_q
                            + fifo_ptr_t'(lane_rank[lane]);
                        allocation_tag = next_seq_tag_q
                            + seq_tag_t'(lane_rank[lane]);
                        dep_offset =
                            input_desc_q[input_rd_ptr_q][lane]
                                        [DEP_MSB:DEP_LSB];

                        fifo_packet_q[write_id] <=
                            input_packet_q[input_rd_ptr_q][lane];
                        fifo_seq_tag_q[write_id] <= allocation_tag;
                        fifo_delay_q[write_id] <=
                            input_desc_q[input_rd_ptr_q][lane][DELAY_W-1:0];
                        fifo_dep_required_q[write_id] <= (dep_offset != '0);
                        fifo_target_tag_q[write_id] <=
                            allocation_tag - seq_tag_t'(dep_offset);
                    end
                end
                fifo_tail_ptr_q <= fifo_tail_ptr_q
                    + fifo_ptr_t'(head_packet_count);
                next_seq_tag_q <= next_seq_tag_q
                    + seq_tag_t'(head_packet_count);
            end

            if (dispatch_packet) begin
                fifo_head_ptr_q <= fifo_head_ptr_q + fifo_ptr_t'(1);
            end
            fifo_count_q <= fifo_count_d;
        end
    end

    logic [$clog2(N)-1:0] output_lane_ptr_q;

    always_ff @(posedge clk or negedge internal_rst_n) begin : completion_state
        if (!internal_rst_n) begin
            inflight_valid_q <= 1'b0;
            history_valid_q  <= '0;
            output_lane_ptr_q <= '0;
            out_valid         <= '0;
        end else begin
            out_valid <= '0;

            if (dispatch_packet) begin
                inflight_valid_q   <= 1'b1;
                inflight_seq_tag_q <= fifo_seq_tag_q[fifo_head_ptr_q];
            end else if (fe_out_valid) begin
                inflight_valid_q <= 1'b0;
            end

            if (fe_out_valid && inflight_valid_q) begin
                history_valid_q[inflight_seq_tag_q[HISTORY_ID_W-1:0]]
                    <= 1'b1;
                history_seq_tag_q[inflight_seq_tag_q[HISTORY_ID_W-1:0]]
                    <= inflight_seq_tag_q;
                history_data_q[inflight_seq_tag_q[HISTORY_ID_W-1:0]]
                    <= fe_out_data;

                out_valid[output_lane_ptr_q] <= 1'b1;
                out_packet[output_lane_ptr_q] <= fe_out_data;
                output_lane_ptr_q <= output_lane_ptr_q + 2'd1;
            end
        end
    end

endmodule : ppe_single_fe_inorder

`default_nettype wire
