# PPE STA Microbenchmarks

For equal packet counts, the optimization score ratio is:

```text
performance_ratio = base_time / candidate_time
score_ratio = performance_ratio^2
            * sqrt(base_area / candidate_area)
            * sqrt(base_power / candidate_power)
```

`script/calc_score_ratio.sh` evaluates the formula from measured cycle counts,
frequencies, areas, and powers. Power values must come from equivalent activity
and analysis conditions.

`rtl/ppe_single_grant_ref.sv` is a standalone, fixed-dimension timing reference
for one scheduler grant decision. It is deliberately excluded from production
RTL and UVM filelists.

The reference has registered inputs and outputs. Its measured internal path is:

```text
input registers
  -> four-class schedulability and oldest selection
  -> rotating four-FE first-legal selection
  -> final sequence-tag mux
  -> output registers
```

Two Nangate45 ORFS configurations are provided:

- `config_single_grant_1ns.mk`: exact 1 ns comparison with scheduler STA.
- `config_single_grant_300mhz.mk`: direct 3.333 ns / 300 MHz feasibility check.

Run placement with the repository mounted as `/work`:

```sh
sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest make --file=/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=/work/sta/orfs/config_single_grant_1ns.mk WORK_HOME=/work/flow/orfs/work place'

sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest make --file=/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=/work/sta/orfs/config_single_grant_300mhz.mk WORK_HOME=/work/flow/orfs/work place'
```

Generate the placement-estimated reports with:

```sh
sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest REF_VARIANT=ppe_single_grant_ref_1ns REF_PERIOD_NS=1.000 openroad -exit /work/sta/orfs/report_single_grant.tcl'

sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest REF_VARIANT=ppe_single_grant_ref_300mhz REF_PERIOD_NS=3.333 openroad -exit /work/sta/orfs/report_single_grant.tcl'
```

Generated ORFS work products and reports remain below the repository's ignored
`flow/` directory.

## Nangate45 reference results

The initial placement-estimated results use the Nangate45 typical Liberty,
0.050 ns clock uncertainty, 0.200 ns I/O delays, and pre-CTS ideal clocks.

| Synthesis constraint | Data arrival | WNS | TNS | Placed area |
|---|---:|---:|---:|---:|
| 1.000 ns | 2.1003 ns | -1.1912 ns | -12.9778 ns | 1440 um^2 |
| 3.333 ns | 2.5237 ns | +0.7186 ns | 0.0000 ns | 1167 um^2 |

The different data-arrival values are expected because synthesis and timing
repair select different mappings for each constraint. Use the 1 ns result only
for an exact-condition ratio against the isolated scheduler report. Use the
3.333 ns result to judge direct 300 MHz feasibility.

For the present Nangate45 flow, a redesigned scheduler decision stage should
target no more logic depth than this reference and should achieve a data-arrival
time near or below 2.5 ns under the 3.333 ns constraint. These figures are
comparative engineering references, not foundry signoff limits.

## 16x16 Wallace multiplier reference

`rtl/ppe_wallace_mul_ref.sv` is a second standalone reference. It registers two
16-bit unsigned operands, forms sixteen shifted partial-product rows, reduces
them through six explicit 3:2 carry-save levels, and performs one final 32-bit
carry-propagate addition before the registered output. The multiplication
operator is not used in the synthesizable reference.

The verification-only testbench `tb/ppe_wallace_mul_ref_tb.sv` compares the
tree against the SystemVerilog multiplication operator. A 10,000-sample random
run passes with Verilator.

Run its two placement points with:

```sh
sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest make --file=/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=/work/sta/orfs/config_wallace_mul_1ns.mk WORK_HOME=/work/flow/orfs/work place'

sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest make --file=/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=/work/sta/orfs/config_wallace_mul_300mhz.mk WORK_HOME=/work/flow/orfs/work place'
```

Generate the placement-estimated reports with:

```sh
sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest REF_VARIANT=ppe_wallace_mul_ref_1ns REF_PERIOD_NS=1.000 openroad -exit /work/sta/orfs/report_wallace_mul.tcl'

sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest REF_VARIANT=ppe_wallace_mul_ref_300mhz REF_PERIOD_NS=3.333 openroad -exit /work/sta/orfs/report_wallace_mul.tcl'
```

The result uses the same Nangate45 typical corner, 0.050 ns clock uncertainty,
0.200 ns I/O delays, pre-CTS ideal clock, and placement-estimated parasitics as
the single-grant reference.

| Synthesis constraint | Data arrival | WNS | TNS | Placed area |
|---|---:|---:|---:|---:|
| 1.000 ns | 1.1652 ns | -0.2474 ns | -4.8794 ns | 2316 um^2 |
| 3.333 ns | 1.2710 ns | +1.9695 ns | 0.0000 ns | 2051 um^2 |

At 1 ns, the worst path crosses the partial-product AND, all six full-adder
compression levels, and the final carry-propagate network. The comparison shows
that this substantial arithmetic cone is still much faster than the isolated
single-grant scheduler logic under the same constraint. The 1 ns miss is real
for this flow, while 300 MHz has ample margin. As above, this is a comparative
open-library result rather than a foundry signoff result.
