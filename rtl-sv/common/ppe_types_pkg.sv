`timescale 1ns/1ps
`default_nettype none

package ppe_types_pkg;
	parameter int N = 4;
	parameter int FE_NUM = 4;
	parameter int ROB_DEPTH = 32;
	parameter int ISSUE_DEPTH = 32;
	parameter int MAX_DEP = 7;

	parameter int ROB_ID_W = $clog2(ROB_DEPTH);
	parameter int SEQ_W = $clog2(ROB_DEPTH + MAX_DEP);

endpackage

`default_nettype wire
