# =========================================================
# SystemVerilog Design RTL
# =========================================================
-f rtl/filelist.f

# =========================================================
# Shared UVM Verification Environment
# =========================================================
+incdir+tb/tb
+incdir+tb/env
+incdir+tb/agent
+incdir+tb/agent/master
+incdir+tb/agent/slave
+incdir+tb/seq_lib
+incdir+tb/seq_lib/base
+incdir+tb/tests
+incdir+tb/tests/base
+incdir+tb/probe

tb/tb/ppe_if.sv
tb/tb/ppe_tb_pkg.sv
tb/probe/ppe_pipeline_stall_probe.sv

# =========================================================
# SystemVerilog DUT UVM Top
# =========================================================
tb/tb/tb_top_sv.sv
