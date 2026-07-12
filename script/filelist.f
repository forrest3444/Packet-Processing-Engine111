# =========================================================
# Design RTL
# =========================================================
rtl/fe_mock.v
rtl/ppe_core.v
rtl/ppe_top.v

# =========================================================
# Verification Environment
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
# TB Top
# =========================================================
tb/tb/tb_top.sv
