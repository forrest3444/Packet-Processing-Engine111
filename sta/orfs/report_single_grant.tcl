if {![info exists ::env(REF_VARIANT)]} {
  error "REF_VARIANT must name the ORFS design nickname"
}
if {![info exists ::env(REF_PERIOD_NS)]} {
  error "REF_PERIOD_NS must state the constrained clock period"
}

set variant $::env(REF_VARIANT)
set period_ns $::env(REF_PERIOD_NS)
set result_root "/work/flow/orfs/work/results/nangate45/${variant}/base"
set report_file "/work/flow/orfs/${variant}_critical_paths.rpt"

read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db "${result_root}/3_place.odb"
read_sdc "${result_root}/3_place.sdc"
source /OpenROAD-flow-scripts/flow/platforms/nangate45/setRC.tcl
estimate_parasitics -placement

set report_stream [open $report_file w]
puts $report_stream "PPE single-grant reference critical-path report"
puts $report_stream "Variant: ${variant}"
puts $report_stream "Target clock: ${period_ns} ns"
puts $report_stream "Clock uncertainty: 0.050 ns"
puts $report_stream "Input/output delay: 0.200 ns"
puts $report_stream "Corner: Nangate45 typical"
puts $report_stream "Parasitics: placement-estimated"
puts $report_stream ""
close $report_stream

check_setup -verbose >> $report_file
report_checks -path_delay max \
  -group_path_count 10 \
  -endpoint_path_count 2 \
  -fields {slew cap input net fanout} \
  -format full_clock_expanded \
  -digits 4 >> $report_file
report_worst_slack -max -digits 4 >> $report_file
report_tns -digits 4 >> $report_file
report_checks -unconstrained \
  -fields {slew cap input net fanout} \
  -format full_clock_expanded \
  -digits 4 >> $report_file

puts "Wrote $report_file"
