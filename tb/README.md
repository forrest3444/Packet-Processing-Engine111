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

`ppe_load_mix_perf_test` adds a combined exact-ratio load test: 378 packets at
50% input-port utilization followed by 756 packets at 90% utilization. Delay is
randomized per packet, and dependency offsets use an exact `14:1:1:1:1:1:1:1`
distribution for offsets `0..7`.

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

## SystemVerilog DUT with the shared UVM environment

The new `rtl-sv` implementation uses a separate UVM top and filelist while
reusing the existing interface, agents, sequences, scoreboard, and tests. The
legacy `tb_top` is unchanged.

```sh
make elab FILELIST=./script/filelist_sv.f TB_TOP=tb_top_sv BUILD_NAME=sv
make run  FILELIST=./script/filelist_sv.f TB_TOP=tb_top_sv BUILD_NAME=sv \
  TESTNAME=ppe_basic_test SEED=1 RUN_TAG=sv_basic_seed_1
```

The ROB32 saturation and wraparound test is:

```sh
make run FILELIST=./script/filelist_sv.f TB_TOP=tb_top_sv BUILD_NAME=sv \
  TESTNAME=ppe_rob32_wrap_test SEED=1 RUN_TAG=sv_rob32_wrap_seed_1
```

## Registered top-level boundary verification

The `rtl-sv` implementation must add checks for the registered external-interface
contract before it replaces the current bring-up RTL:

- raw input changes must not affect allocation, scheduling, or any top-level
  output until after an input-capture clock edge;
- except for asynchronous reset assertion, `bkps`, `out_valid`, and `out_packet`
  may change only after a clock edge and must remain stable between edges;
- maximum-width traffic must not overflow, drop, duplicate, or partially accept
  a batch while registered `bkps` is taking effect;
- FIFO-full/empty, simultaneous enqueue/dequeue, ROB-full with retirement, and
  reset assertion/release cases must be covered;
- sustained four-wide retirement and allocation must demonstrate that the skid
  FIFO does not introduce avoidable steady-state bubbles.
