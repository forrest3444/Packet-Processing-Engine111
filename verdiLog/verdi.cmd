debImport "-full64"
verdiWindowResize -win $_Verdi_1 "819" "261" "1507" "911"
simSetSimulator "-vcssv" -exec \
           "/home/wwh/github/pfe/sim/build/fsdb/simv/tb_top_sv.simv" -args \
           "+ntb_random_seed=1 +UVM_TESTNAME=ppe_basic_test +UVM_VERBOSITY=UVM_MEDIUM +FSDB +FSDB_FILE=sim/run/ppe_basic_test_seed_1/waves.fsdb"
nsMsgSwitchTab -tab general
debImport "-dbdir" \
          "/home/wwh/github/pfe/sim/build/fsdb/simv/tb_top_sv.simv.daidir"
debLoadSimResult /home/wwh/github/pfe/sim/run/ppe_basic_test_seed_1/waves.fsdb
wvCreateWindow
srcHBSelect "tb_top_sv.dut" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut" -delim "."
srcHBSelect "tb_top_sv.dut" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "in_valid" -line 14 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 44353.658815 -snap {("G2" 0)}
wvZoomOut -win $_nWave2
wvSetCursor -win $_nWave2 74459.870821 -snap {("G1" 1)}
verdiWindowResize -win $_Verdi_1 "484" "114" "1777" "1063"
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "in_valid_i" -line 14 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 1)}
verdiWindowResize -win $_Verdi_1 "170" "42" "1924" "1063"
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "in_desc_i" -line 16 -pos 1 -win $_nTrace1
wvSelectGroup -win $_nWave2 {G1}
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Bin
wvZoomIn -win $_nWave2
wvSetCursor -win $_nWave2 84262.858852 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 94837.021531 -snap {("G1" 1)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 18 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_i" -line 19 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit_valid_o" -line 20 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_seq_tag_o" -line 21 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_target_seq_tag_o" -line 22 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_packet_o" -line 23 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_delay_o" -line 24 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_dep_required_o" -line 25 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectGroup -win $_nWave2 {G2}
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 8)}
wvSelectSignal -win $_nWave2 {( "G1" 8 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 7)}
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
wvSelectSignal -win $_nWave2 {( "G1" 5 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 4)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit_valid_o" -line 20 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_lane_valid_q" -line 38 -pos 1 -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvSetRadix -win $_nWave2 -format Bin
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvSetRadix -win $_nWave2 -format Hex
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Hex
wvSetCursor -win $_nWave2 147046.949761 -snap {("G2" 0)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_i" -line 19 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 18 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_i" -line 19 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.alloc_reserve_ready_i" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.alloc_reserve_ready_o" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_outputs" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_state" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[3\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[3\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[3\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[1\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.bkps_state_update" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "reserve_batch" -line 284 -pos 1 -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_q" -line 106 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_nonempty" -line 107 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_i" -line 108 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_release" -line 109 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_nonempty" -line 107 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.head_nonempty" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 105 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_nonempty" -line 107 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_packet_count" -line 80 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_lane_valid" -line 79 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_packet_count" -line 80 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_dep_required" -line 81 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_lane_valid" -line 79 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_packet_count" -line 80 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_dep_required" -line 81 -pos 1 -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvSetRadix -win $_nWave2 -format Bin
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 8)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_q" -line 88 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_count_q\[1:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_d" -line 263 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_count_d\[1:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "capture_batch" -line 118 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.capture_batch" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "bkps_q" -line 112 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "capture_batch" -line 112 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "bkps_q" -line 112 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 10 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 9)}
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 8)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_lane_valid_q" -line 38 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 84262.858852 -snap {("G1" 9)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_packet_q" -line 39 -pos 1 -win $_nTrace1
wvSetCursor -win $_nWave2 95167.464115 -snap {("G1" 9)}
wvSetCursor -win $_nWave2 106072.069378 -snap {("G1" 9)}
wvSetCursor -win $_nWave2 114663.576555 -snap {("G1" 9)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_desc_q" -line 40 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_lane_valid_q" -line 38 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_packet_q" -line 39 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_desc_q" -line 40 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_rd_ptr_q" -line 41 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_rd_ptr_q" -line 41 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_wr_ptr_q" -line 42 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 84923.744019 -snap {("G1" 11)}
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_wr_ptr_q" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "capture_batch" -line 257 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 12 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 11)}
wvSelectSignal -win $_nWave2 {( "G1" 11 )} 
srcDeselectAll -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 11 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 10)}
wvSelectSignal -win $_nWave2 {( "G1" 10 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 9)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_q" -line 88 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 10 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 9)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_lane_valid" -line 89 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_packet_count" -line 90 -pos 1 -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvShowOneTraceSignals -win $_nWave2 -signal \
           "/tb_top_sv/dut/u_ingress/alloc_commit_valid_o\[3:0\]" -driver
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 0
wvSelectGroup -win $_nWave2 \
           {G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver}
wvSelectSignal -win $_nWave2 \
           {( "G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver" \
           1 )} 
wvSetCursor -win $_nWave2 151342.703349 -snap \
           {("/tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver" 2)}
wvSelectGroup -win $_nWave2 \
           {G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver}
wvScrollDown -win $_nWave2 2
wvSelectGroup -win $_nWave2 \
           {G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver}
wvSelectSignal -win $_nWave2 \
           {( "G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver" \
           1 )} 
wvSelectSignal -win $_nWave2 {( "G1" 8 )} 
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvSelectSignal -win $_nWave2 {( "G1" 11 )} 
wvSelectSignal -win $_nWave2 {( "G1" 12 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 11 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 10 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 8 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 \
           {( "G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver" \
           2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 \
           {( "G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver" \
           1 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectGroup -win $_nWave2 \
           {G1//tb_top_sv/dut/u_ingress/alloc_commit_valid_o@0(1ps)#ActiveDriver}
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit_valid_q" -line 217 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.alloc_commit_valid_q\[3:0\]" -win \
           $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "reserve_batch" -line 284 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 284 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "reserve_batch" -line 284 -pos 1 -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_rob" -delim "."
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_i" -line 13 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_o" -line 14 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
srcActiveTrace "tb_top_sv.dut.u_rob.alloc_reserve_ready_o" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "occupancy_next" -line 476 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.occupancy_next\[5:0\]" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.occupancy_next\[5:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.occupancy_next\[5:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "occupancy_next" -line 476 -pos 1 -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.occupancy_next\[5:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.occupancy_next\[5:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "occupancy_q" -line 474 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_count_q" -line 475 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 174143.241627 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 195291.566986 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 174473.684211 -snap {("G1" 7)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "occupancy_after_retire" -line 473 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 8 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 7)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_count_q" -line 475 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcTraceLoad "tb_top_sv.dut.u_rob.retire_count_q\[2:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.retire_count_q\[2:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -word -line 750 -pos 3 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_pending_valid_q" -line 754 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_count_q" -line 755 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_pending_valid_q" -line 757 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_valid_o" -line 757 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 9 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 8)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_pending_valid_q" -line 757 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "retire_valid_o" -line 757 -pos 1 -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.retire_valid_o\[3:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.retire_valid_o\[3:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.retire_valid_o\[3:0\]" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 7)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvExpandBus -win $_nWave2 {("G1" 2)}
wvSetPosition -win $_nWave2 {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 1)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_q" -line 88 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_count_q\[1:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_d" -line 263 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_count_d\[1:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_count_d" -line 125 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "capture_batch" -line 118 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_release" -line 118 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcActiveTrace "tb_top_sv.dut.u_ingress.head_release" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.head_release" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit_valid_o" -line 20 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 83271.531100 -snap {("G1" 2)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 18 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 75671.351675 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 85915.071770 -snap {("G1" 7)}
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
srcSetScope -win $_nTrace1 \
           "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_metadata_outputs\[0\]" -win \
           $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
srcDeselectAll -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
srcDeselectAll -win $_nTrace1
srcSelect -signal "reserve_batch" -line 106 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_release" -line 109 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_nonempty" -line 105 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "reserve_batch" -line 106 -pos 1 -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.reserve_batch" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 18 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.alloc_reserve_valid_o\[3:0\]" -win \
           $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "slot_lane_valid_q\[slot_rd_ptr_q\]" -line 89 -pos 1 -win \
          $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.slot_lane_valid_q\[0:1\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.slot_lane_valid_q\[0:1\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_ready_i" -line 19 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.alloc_reserve_ready_i" -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 5 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
wvSelectSignal -win $_nWave2 {( "G1" 2 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSetPosition -win $_nWave2 {("G1" 2)}
wvMoveSelected -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 2)}
wvSetPosition -win $_nWave2 {("G1" 3)}
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
srcTraceLoad "tb_top_sv.dut.u_rob.alloc_reserve_ready_o" -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "G1" 3 )} 
wvSelectSignal -win $_nWave2 {( "G1" 4 )} 
srcTraceLoad "tb_top_sv.dut.u_ingress.alloc_reserve_ready_i" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 102 -pos 1 -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.alloc_reserve_valid_o\[3:0\]" -win \
           $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_reserve_valid_o" -line 102 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit_valid_o" -line 20 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_ingress.alloc_commit_valid_o\[3:0\]" -win \
           $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_ingress.alloc_commit_valid_o\[3:0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "alloc_commit" -line 179 -pos 1 -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.alloc_commit\[3:0\]" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.alloc_commit\[3:0\]" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.alloc_commit\[3:0\]" -win $_nTrace1
srcActiveTrace "tb_top_sv.dut.u_rob.alloc_commit\[3:0\]" -win $_nTrace1
srcTraceLoad "tb_top_sv.dut.u_rob.alloc_commit\[3:0\]" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_rob" -delim "."
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
