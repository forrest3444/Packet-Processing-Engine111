`timescale 1ns/1ps
`default_nettype none

package ppe_types_pkg;

    // Baseline design configuration. These constants define one coherent PPE
    // build and are not independently overridden at submodule instances.
    localparam int N                    = 4;
    localparam int FE_NUM               = 4;
    localparam int ROB_DEPTH            = 32;
    localparam int ISSUE_DEPTH          = ROB_DEPTH;
    localparam int MAX_DEP              = 7;
    localparam int ISSUE_WIDTH          = FE_NUM;
    localparam int RESULT_BANKS         = MAX_DEP + 1;
    localparam int DELAY_W              = 2;
    localparam int CAND_WINDOW_DEPTH    = 8;
    localparam int RETURN_FUTURE_DEPTH  = 6;
    localparam int READY_ENQUEUE_WIDTH  = N;
    localparam int DEFAULT_PACKET_W     = 128;
    localparam int DEFAULT_DESC_W       = 5;

    // Widths derived from the baseline configuration.
    localparam int ROB_ID_W     = $clog2(ROB_DEPTH);
    localparam int SEQ_W        = $clog2(ROB_DEPTH + MAX_DEP);
    localparam int HISTORY_ID_W = $clog2(RESULT_BANKS);

    // Types shared by more than one architectural block. Module-private state
    // encodings, structures, pointers, and counters remain local to their owner.
    typedef logic [ROB_ID_W-1:0] rob_id_t;
    typedef logic [SEQ_W-1:0]    seq_tag_t;
    typedef logic [DELAY_W-1:0]  delay_t;

endpackage

`default_nettype wire
