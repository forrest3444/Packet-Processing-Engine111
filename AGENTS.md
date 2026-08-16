# PPE Repository Instructions

## Scope and sources of truth

These instructions apply to the entire repository.

- Read `doc/ppe_feature_description.txt` before changing functional behavior. It is the source of truth for externally observable semantics.
- Read `doc/hld.txt` before changing RTL structure. It is the source of truth for module ownership, data flow, and microarchitecture decisions.
- Read `doc/lld.txt` before changing RTL internals. It is the source of truth for internal interfaces, entry fields, state transitions, indexing, and cycle-level behavior.
- If implementation work requires a functional-semantic change, update the spec first and then synchronize the HLD and verification plan.
- If implementation work changes module ownership, pipeline boundaries, arbitration, buffers, or PPA strategy, update the HLD in the same change.
- If implementation work changes internal ports, stored fields, state encodings, lookup rules, or concurrent update behavior, update the LLD in the same change.
- Do not silently resolve a conflict between the spec, HLD, LLD, RTL, and testbench. Report it and preserve the higher-level documented contract unless the user explicitly changes it.

## Optimization objective

Functional correctness is a hard gate. After correctness, use this qualitative optimization priority:

1. Performance.
2. Power.
3. Area.

- The local environment does not provide a complete performance, power, and area feedback loop. Do not perform numerical score-based optimization or invent quantitative PPA estimates.
- Treat performance as the primary design direction. Power and area are supporting targets addressed mainly through coding discipline, reduced switching, and avoiding unnecessary storage or logic.
- MUST NOT sacrifice clear throughput capability for speculative power or area savings.
- Without implementation-tool evidence, describe PPA effects qualitatively and identify uncertainty.
- MUST preserve correctness even when a potentially faster implementation is available.

## Design-authority boundary

- Do not use this file as an independent source for parameters, module partitioning, interfaces, state fields, arbitration algorithms, buffer organization, or cycle-level behavior. Those decisions belong only in the spec, HLD, and LLD.
- Implement the documented baseline exactly. If a needed design detail is absent or ambiguous, close it in the appropriate design document before encoding it in RTL.
- Keep verification-only checks in verification files. Do not add synthesizable error reporting, recovery, or lock states unless the functional specification explicitly requires them.

## Performance rules

- Treat documented throughput, resource utilization, fairness, and critical-path constraints as first-class design requirements.
- Avoid avoidable bubbles and do not serialize operations that the HLD/LLD require to proceed concurrently merely to simplify RTL.
- Pipeline long combinational paths when needed for frequency, but account for added latency, occupancy pressure, and throughput effects.
- Do not change documented pipeline boundaries or flow-control policy without synchronizing the HLD and LLD.

## Power rules

- Prefer clock-enable behavior and conditional register updates over unconditional toggling of wide data paths.
- Do not create manually gated clocks unless the project explicitly adopts a supported clock-gating methodology.
- Clear valid/state bits on reset; avoid resetting wide data arrays when their contents are architecturally ignored while valid is clear.
- Hold or avoid rewriting wide data registers when no valid transaction updates them.
- Avoid unnecessary broadcast activity and meaningless downstream switching.
- Use valid bits to suppress meaningless downstream switching.

## Area rules

- Do not duplicate wide storage without a documented timing or port-pressure reason.
- Share decode or comparison logic only when sharing does not create a performance-critical fanout or mux path.
- Parameterization must not impose significant cost on the documented baseline configuration.

## RTL coding requirements

- Use nonblocking assignments for sequential state and complete assignments/defaults in combinational logic.
- Give each state element one clear owning sequential process.
- Avoid inferred latches, combinational loops, `casex`, simulation delays, and unsynthesizable constructs in RTL.
- Size counters, pointers, additions, subtractions, and comparisons explicitly. Handle non-power-of-two wrap intentionally.
- Follow the spec, HLD, and LLD for ordering, lookup, register-boundary, and interface behavior; do not restate or reinterpret those rules in RTL comments as a competing contract.
- Put protocol and internal-consistency assertions in verification-only SystemVerilog files, not synthesizable RTL.

## Change workflow

Before editing RTL:

1. Identify the governing spec, HLD, and LLD sections.
2. State the expected correctness impact and qualitative performance, power, and area effects.
3. Preserve unrelated user changes.

After editing RTL:

1. Run `make elab` for compilation/elaboration.
2. Run the relevant test with `make run TESTNAME=<test> SEED=<seed>`; use multiple seeds for arbitration, dependency, and concurrency changes.
3. Check logs for assertions, timeouts, dropped packets, duplicates, ordering failures, and dependency mismatches.
4. Report verification performed and clearly label any unmeasured PPA expectations as qualitative.

## STA environment and handoff

- Docker is installed and user `wwh` belongs to the `docker` group. If an existing agent process has stale group membership, run Docker commands as `sg docker -c '<command>'`.
- OpenROAD-flow-scripts is installed at `/home/wwh/github/OpenROAD-flow-scripts`. Its Docker image provides Yosys/ABC, OpenROAD/OpenSTA, KLayout, and the bundled Nangate45 platform. Host-side Verilator and GTKWave are also available.
- The repository's canonical top-level synthesis setup is 1.25 GHz under `flow/orfs/`: `config/config.mk`, `config/config_top_sv_1p25ghz.mk`, `constraints/constraint_top_sv_1p25ghz.sdc`, and `scripts/report_top_sv_1p25ghz_functional.tcl`. Before reuse, synchronize its top, RTL file list, and result paths with the current design; do not assume the checked-in configuration follows later RTL restructuring automatically.
- Run front-end synthesis from the repository root with:

  ```sh
  sg docker -c '/home/wwh/github/OpenROAD-flow-scripts/flow/util/docker_shell --image openroad/orfs:latest make --file=/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=/work/flow/orfs/config/config.mk WORK_HOME=/work/flow/orfs/work synth'
  ```

  Use the `place` target only when placement-estimated parasitics are needed. Do not run the default full RTL-to-GDS target for ordinary front-end timing work.
- Nangate45 currently uses its typical Liberty corner and is suitable for comparative optimization, not foundry signoff. Every timing result must state clock period, uncertainty, I/O delays, corner, and whether delays are synthesis-only or placement-estimated; report WNS, TNS, and the actual startpoint/endpoint path. Never claim that 1.25 GHz is met from synthesis completion alone.
- Treat inferred latches, unconstrained endpoints, combinational loops, incomplete synthesis, or missing clocks as hard blockers to a credible critical-path report. Preserve the failing log and fix or report the modeling/RTL issue first.
- Known environment limits: the available prebuilt ORFS images have triggered a repeatable `illegal instruction` in the post-CTS flow on this VMware host, while synthesis and pre-CTS stages run. VCS may also fail when the license server is unavailable. Do not misreport either condition as an RTL timing failure.

## Review checklist

- Externally observable behavior matches the functional specification.
- Module ownership, data flow, buffering, arbitration, and pipeline boundaries match the HLD.
- Internal interfaces, state transitions, lookup rules, and concurrent updates match the LLD.
- Reset, flow control, ordering, dependency, and output-register requirements are covered by verification.
- Concurrency and wraparound corner cases do not cause loss, duplication, mismatch, deadlock, or reordering.
- Any intentional PPA tradeoff is documented qualitatively, including known uncertainty.
