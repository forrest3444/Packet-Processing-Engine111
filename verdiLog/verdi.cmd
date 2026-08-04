debImport "-full64"
simSetSimulator "-vcssv" -exec \
           "/home/wwh/github/pfe/sim/build/fsdb/simv/tb_top_sv.simv" -args \
           "+ntb_random_seed=1 +UVM_TESTNAME=ppe_pipeline_stall_test +UVM_VERBOSITY=UVM_MEDIUM +FSDB +FSDB_FILE=sim/run/pipeline_stall_seed_1/waves.fsdb"
nsMsgSwitchTab -tab general
debImport "-dbdir" \
          "/home/wwh/github/pfe/sim/build/fsdb/simv/tb_top_sv.simv.daidir"
debLoadSimResult /home/wwh/github/pfe/sim/run/pipeline_stall_seed_1/waves.fsdb
wvCreateWindow
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "in_valid_i" -line 14 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "in_packet_i" -line 15 -pos 1 -win $_nTrace1
wvSetCursor -win $_nWave2 73830.879427 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 86136.025998 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 95023.076300 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 75881.737189 -snap {("G1" 1)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "bkps_o" -line 17 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcHBSelect "tb_top_sv.dut" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut" -delim "."
srcHBSelect "tb_top_sv.dut" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "out_valid" -line 18 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_outputs" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_state" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.bkps_state_update" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.occupancy_and_backpressure" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.occupancy_and_backpressure" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.occupancy_and_backpressure" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.bkps_state_update" -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.bkps_state_update" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_state" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_state" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_ingress.allocation_commit_outputs" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_ingress.allocation_commit_outputs" -win $_nTrace1
verdiWindowResize -win $_Verdi_1 "823" "19" "1574" "1010"
verdiWindowResize -win $_Verdi_1 "823" "19" "1708" "1135"
wvSetCursor -win $_nWave2 175843.991734 -snap {("G1" 3)}
wvSetCursor -win $_nWave2 186706.941031 -snap {("G1" 3)}
wvSetCursor -win $_nWave2 173807.188741 -snap {("G1" 3)}
wvSetCursor -win $_nWave2 73324.907750 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 173807.188741 -snap {("G1" 3)}
wvSetCursor -win $_nWave2 74682.776412 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 85545.725709 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 74003.842081 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 83508.922716 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 74003.842081 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 84866.791378 -snap {("G1" 1)}
wvZoomIn -win $_nWave2
wvZoomIn -win $_nWave2
wvZoomOut -win $_nWave2
srcHBSelect "tb_top_sv.pif" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.pif" -delim "."
srcHBSelect "tb_top_sv.pif" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler" -delim "."
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler.allocation_bank_route" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler.allocation_bank_route" \
           -delim "."
srcHBSelect "tb_top_sv.dut.u_scheduler.allocation_bank_route" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -delim \
           "."
srcHBSelect "tb_top_sv.dut.u_scheduler.g_future_table\[0\]" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "issue_state_q" -line 61 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 105234.821308 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 114060.967612 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 126621.252735 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 134768.464708 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 145970.881170 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 155815.428969 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 265123.856264 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 255618.775629 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 264444.921933 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 274289.469733 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 285491.886194 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 294318.032498 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 304502.047463 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 315364.996759 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 254939.841298 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 104895.354143 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 74003.842081 -snap {("G1" 1)}
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetCursor -win $_nWave2 104555.886977 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 115079.369108 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 82829.988385 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 105574.288474 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 115418.836274 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 125263.384073 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 116437.237770 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 124244.982577 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 115758.303439 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 105234.821308 -snap {("G1" 4)}
wvSetCursor -win $_nWave2 115079.369108 -snap {("G1" 4)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "issue_seq_tag_q" -line 62 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "issue_target_seq_tag_q" -line 63 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "issue_seq_tag_q" -line 62 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 103876.952646 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 115079.369108 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 125263.384073 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 137144.734866 -snap {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
wvSelectSignal -win $_nWave2 {( "G1" 5 )} 
wvSelectSignal -win $_nWave2 {( "G1" 5 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 4)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "candidate_valid_q" -line 67 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 105234.821308 -snap {("G1" 5)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "candidate_valid_d" -line 68 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 94711.339177 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 105234.821308 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 95729.740674 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 105913.755639 -snap {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "candidate_valid_q" -line 67 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
wvSetCursor -win $_nWave2 2414208.539842 -snap {("G1" 2)}
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler" -delim "."
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "issue_dep_required_q" -line 65 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 224800.454820 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 795316.508206 -snap {("G1" 5)}
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_rob" -delim "."
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "rob_valid_q" -line 51 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 6)}
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 5)}
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_scheduler" -delim "."
srcHBSelect "tb_top_sv.dut.u_scheduler" -win $_nTrace1
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_top_sv.dut.u_rob" -delim "."
srcHBSelect "tb_top_sv.dut.u_rob" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "rob_valid_q" -line 51 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "rob_result_valid_q" -line 52 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
srcDeselectAll -win $_nTrace1
srcSelect -signal "head_ptr_q" -line 173 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSetCursor -win $_nWave2 761369.791655 -snap {("G1" 8)}
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvSelectSignal -win $_nWave2 {( "G1" 6 )} 
wvSetCursor -win $_nWave2 733533.484083 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 734891.352745 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 745075.367711 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 734551.885580 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 745075.367711 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 755598.849841 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 764424.996145 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 775287.945441 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 784453.558910 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 776306.346937 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 785471.960406 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 795316.508206 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 874412.357770 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 773590.609613 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 734212.418414 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2765118.882508 -snap {("G1" 2)}
wvSetCursor -win $_nWave2 2794991.993073 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2823846.702141 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2764100.481011 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2794652.525907 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2804157.606542 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 2814681.088673 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 2825204.570803 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 2835388.585769 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2824186.169307 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2835049.118603 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2824186.169307 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 2834030.717107 -snap {("G1" 6)}
wvSetCursor -win $_nWave2 3295750.836727 -snap {("G1" 2)}
wvSetCursor -win $_nWave2 3304237.515865 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3315100.465161 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3324605.545796 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3335468.495092 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3344973.575726 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3355157.590692 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3364662.671326 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3374507.219126 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3386049.102753 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3394196.314725 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3404719.796856 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3415582.746153 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3424408.892456 -snap {("G1" 7)}
wvSetCursor -win $_nWave2 3433235.038759 -snap {("G1" 7)}
verdiWindowResize -win $_Verdi_1 "513" "19" "1708" "1135"
wvSetCursor -win $_nWave2 74343.309247 -snap {("G1" 1)}
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Bin
wvSetCursor -win $_nWave2 84527.324212 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 76040.645074 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 84866.791378 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 95390.273508 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 104555.886977 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 113382.033281 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 75022.243578 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 84187.857047 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 94711.339177 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 104895.354143 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 115758.303439 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 123905.515411 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 135786.866204 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 143594.611011 -snap {("G1" 1)}
wvSetCursor -win $_nWave2 103537.485481 -snap {("G1" 4)}
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Hex
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Bin
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Ascii
wvSelectSignal -win $_nWave2 {( "G1" 1 )} 
wvSetRadix -win $_nWave2 -format Bin
wvZoomIn -win $_nWave2
wvZoom -win $_nWave2 106762.423553 152081.290149
wvUndo -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 7)}
wvUndo -win $_nWave2
wvSetPosition -win $_nWave2 {("G1" 7)}
wvSetPosition -win $_nWave2 {("G1" 8)}
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("G2" 0)}
wvSetPosition -win $_nWave2 {("G1" 7)}
wvSelectSignal -win $_nWave2 {( "G1" 7 )} 
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
