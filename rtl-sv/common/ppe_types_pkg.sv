package ppe_types_pkg;
	parameter int N = 4;
	parameter int FE_NUM = 4;
	parameter int ROB_DEPTH = 16;
	parameter int ISSUE_DEPTH = 16;
	parameter int CAND_NUM = 8;
	parameter int MAX_DEP = 7;

	parameter int ROB_ID_W = $clog2(ROB_DEPTH);
	parameter int SEQ_W = $clog2(ROB_DEPTH + MAX_DEP);

endpackage
