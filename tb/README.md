# PPE Four-FE UVM Environment

The environment verifies the maintained four-FE RTL with shared agents, FE
reference model, and end-to-end scoreboard.

Functional tests have distinct primary responsibilities:

- `ppe_basic_test`: short end-to-end smoke test.
- `ppe_dep_loss_test`: dependency wakeup and retirement-history lifetime.
- `ppe_rob32_wrap_test`: full ROB occupancy and sequence-tag wraparound.
- `ppe_ingress_elastic_stress_test`: sparse/empty batches and registered backpressure.

Performance tests cover three representative workloads:

- `ppe_p0_perf_test`: zero-delay peak throughput.
- `ppe_uniform_random_delay_test`: dependency-free scheduler/calendar efficiency.
- `ppe_load_mix_perf_test`: mixed offered load, random delay, and dependencies.
- `ppe_pipeline_stall_test`: the mixed workload plus causal pipeline pressure
  counters for scheduler supply, calendar legality, matching, and ROB head wait.

Run a single test from the repository root after elaboration:

```sh
make elab
make run TESTNAME=ppe_basic_test SEED=1
```

Run the targeted blockage probe with:

```sh
make sim TESTNAME=ppe_pipeline_stall_test SEED=1 BUILD_NAME=stall_probe
```

The `PIPE_STALL` lines separate independent pressure indicators. They are not
exclusive cycle classifications: for example, dependency waiting and ROB-head
waiting can overlap in the same cycle.

The mixed workload keeps seven dependent packets per 21 packets by default.
Override the exact ratio with `MIXED_DEP_PER_21=0..21`; zero selects a fully
dependency-free mixed workload:

```sh
make run BUILD_NAME=<build> TESTNAME=ppe_load_mix_perf_test SEED=1 \
  USER_SIM_OPTS=+MIXED_DEP_PER_21=0
```

Compile and run the same test with an FSDB waveform using:

```sh
make sim-fsdb TESTNAME=ppe_pipeline_stall_test SEED=1 \
  RUN_TAG=pipeline_stall_seed_1
```

The waveform is written to `sim/run/<RUN_TAG>/waves.fsdb` by default. Override
the location with `FSDB_FILE=<path>`.

Run the compact functional and performance regressions with:

```sh
./script/run_regression.sh functional
./script/run_regression.sh performance
./script/run_regression.sh all
```

Functional regression defaults to seeds `1 23`; performance defaults to seed
`1`. Override them with `FUNC_SEEDS` and `PERF_SEEDS`. Each invocation performs
one lint and one elaboration, then reuses that image for all selected tests.
Summaries are written under `sim/regression/four_fe/`.

Directory layout:

- `tb/tb`: interface, package, and four-FE testbench top.
- `tb/agent`: active input and passive output agents.
- `tb/env`: FE reference model, environment, and scoreboard.
- `tb/seq_lib`: stimulus sequences.
- `tb/tests`: UVM tests and workload metrics.
