# PPE UVM Smoke Environment

Minimal UVM environment for first bring-up.

Current scope:
- 4-lane shuffled input beats
- no-dependency packets
- strict output `seq` check
- output lane round-robin check

Run from repository root:

```sh
make sim
make run TESTNAME=ppe_basic_test SEED=2
```

Directory layout:
- `tb/tb`: interface, package, and top-level testbench
- `tb/agent`: shared agent transactions
- `tb/agent/master`: active master agent, sequencer, and input driver
- `tb/agent/master`: active driver plus accepted-input monitor
- `tb/agent/slave`: passive slave agent and output monitor
- `tb/env`: environment, FE reference VIP, and full-width end-to-end scoreboard
- `tb/seq_lib`: smoke sequences
- `tb/tests`: UVM tests

P0 peak-throughput baseline:

```sh
make run BUILD_NAME=<build> TESTNAME=ppe_p0_perf_test SEED=1
```

P1-P6 characterization uses `ppe_perf_test` with `USER_SIM_OPTS=+PERF_CASE=<case>`.
Supported cases are `P1_DELAY1`, `P1_DELAY2`, `P1_DELAY3`, `P2_MIXED_DELAY`,
`P3_LANES1`, `P3_LANES2`, `P3_LANES3`, `P4_DEP1_D0`, `P4_DEP1_D3`,
`P5_DEP2`, `P5_DEP4`, `P5_DEP7`, `P6_DEP25`, `P6_DEP50`, and `P6_DEP75`.

Regression targets keep functional pass/fail testing separate from performance
characterization:

```sh
make regress-functional
make regress-performance
make regress
```

Functional regression uses seeds `1 23` by default. Override them with
`REGRESS_FUNC_SEEDS="1 7 23"`; performance seeds use `REGRESS_PERF_SEEDS`.
Each test/case gets a unique directory under `sim/run`. Regression summaries
are written below `sim/regression/<target>/`, with performance metrics collected
in `performance_metrics.log`.
