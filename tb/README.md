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
- `tb/agent/slave`: passive slave agent and output monitor
- `tb/env`: environment assembly and scoreboard
- `tb/seq_lib`: smoke sequences
- `tb/tests`: UVM tests
