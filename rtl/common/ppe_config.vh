`ifndef PPE_CONFIG_VH
`define PPE_CONFIG_VH

// PPE configuration shared by synthesizable design modules.
`define PPE_N                    4
`define PPE_FE_NUM               4
`define PPE_ROB_DEPTH            32
`define PPE_ISSUE_DEPTH          32
`define PPE_ISSUE_WIDTH          4
`define PPE_CAND_WINDOW_DEPTH    8
`define PPE_READY_ENQUEUE_WIDTH  4
`define PPE_ROB_ID_W             5

`define PPE_MAX_DEP              7
`define PPE_RESULT_BANKS         8
`define PPE_DELAY_W              2
`define PPE_RETURN_FUTURE_DEPTH  6
`define PPE_DEFAULT_PACKET_W     128
`define PPE_DEFAULT_DESC_W       5

// Widths derived from the maintained configuration.
`define PPE_SEQ_W                6
`define PPE_HISTORY_ID_W         3
`define PPE_ROB_BANK_ROW_W       (`PPE_ROB_ID_W - 2)
`define PPE_ROB_TAG_HI_W         (`PPE_SEQ_W - `PPE_ROB_ID_W)

`endif
