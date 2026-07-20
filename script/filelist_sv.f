# =========================================================
# SystemVerilog Design RTL
# =========================================================
+define+PPE_SV_ARCH
-f rtl-sv/filelist.f

# =========================================================
# Shared UVM Verification Environment
# =========================================================
+incdir+tb/tb
+incdir+tb/env
+incdir+tb/agent
+incdir+tb/agent/master
+incdir+tb/agent/slave
+incdir+tb/seq_lib
+incdir+tb/tests

tb/tb/ppe_if.sv
tb/tb/ppe_tb_pkg.sv

# =========================================================
# SystemVerilog DUT UVM Top
# =========================================================
tb/tb/tb_top_sv.sv
