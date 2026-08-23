# PPE Top-Level Test-Point Decomposition

Language: [中文](ppe_test_plan.md) | English

## Short Description

This document only decomposes PPE top-level test points. It does not define the
verification environment, reference model, complete coverage plan, or regression
strategy. Tests use only top-level inputs and outputs, and the DUT is a black
box. The lane count is a variable parameter from 3 through 7; descriptions do
not depend on a fixed lane count.

### Default Checks

The verification environment continuously checks the following properties in
every test, so they are not separate test points:

- `out_monitor` samples packets from the current output start lane and checks that same-cycle `out_valid` lanes are dense, contain no hole, and wrap after the highest lane.
- `scb` builds its expected queue in top-level acceptance order, compares data, dependency results, and output order packet by packet, and checks the final output count and pending queue. Therefore, packet loss, duplicate/unexpected output, and reordering are default checks in every test.

The check-mechanism column below only highlights collection or comparison that
is specific to each test point; the default checks always remain enabled.

In the tables below, “random” means constrained-random within the legal protocol
range. Each C field identifies random variables and variables requiring fixed
or directed values.

## 1. Performance Dimension

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| PERF-001 | Peak throughput | C: Fix `valid` at full width, randomize `packet`, set delay=0 and dep_offset=0, and apply no reset. I: Send a sustained long stream. PO: Measure accept/output throughput, backpressure ratio, and latency. | `in_monitor` counts acceptance; `out_monitor` measures output and latency. | Full width, delay 0, and dep 0 hit. | `tc_performance` (not implemented) |
| PERF-002 | Mixed-delay throughput | C: Randomize nonempty `valid` and `packet`, randomize delay from 0 through 3, set dep_offset=0, and apply no reset. I: Send a sustained long stream. PO: Measure steady-state throughput and latency. | `in_monitor` collects input/delay distribution; `out_monitor` measures output and latency. | Delays 0 through 3 hit. | `tc_performance` (not implemented) |
| PERF-003 | Mixed-dependency throughput | C: Randomize `valid`, `packet`, and delay; randomize dep_offset to the selected dependency ratio with legal targets; apply no reset. I: Send independent, low-, medium-, and high-dependency long streams. PO: Measure steady-state throughput and backpressure. | `in_monitor` measures dependency ratio and acceptance; `out_monitor` measures output. | Independent, low, medium, and high dependency ratios hit. | `tc_performance` (not implemented) |
| PERF-004 | Offered load | C: Randomize `packet`, set delay=0 and dep_offset=0, apply no reset, and direct the `valid` count for each target load. I: Send sparse, medium, and full-width input. PO: Compare accept rate, output rate, and latency. | `in_monitor` measures input width and acceptance; `out_monitor` measures output and latency. | Sparse, medium, and full-width loads hit. | `tc_performance` (not implemented) |
| PERF-005 | Steady-state comparison | C: Reuse the selected workload constraints for every input variable, with identical configuration, seed, and random sequence across RTL versions; apply no reset. I: Send a sufficiently long identical stream. PO: Compare RTL versions after excluding startup/drain effects. | `in_monitor` and `out_monitor` use identical windows. | Startup, steady, and drain windows have samples. | `tc_performance` (not implemented) |

## 2. Interface Dimension

`in_monitor` collects accepted input transactions, `out_monitor` collects output
transactions, and `scb` performs end-to-end checking.

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| IF-001 | Valid patterns | C: Direct `valid` through every pattern, randomize `packet` and delay, randomize dep_offset with legal targets, and obey `bkps`. I: Send each valid pattern. PO: Only valid lanes form accepted transactions. | `in_monitor` records actual accepted masks; default checks verify corresponding outputs. | Every valid-mask value. | `tc_if_basic` (not implemented) |
| IF-002 | Data boundaries | C: Randomize `valid` and delay, randomize dep_offset with legal targets, direct `packet` to all-zero/all-one, and randomize other packet values. I: Send boundary and random data. PO: Output matches the packet/descriptor result with no data mismatch. | `in_monitor` collects input packets; `out_monitor` collects output packets; `scb` checks expected data. | Minimum and maximum data values. | `tc_if_basic` (not implemented) |
| IF-003 | Delay | C: Randomize `valid` and `packet`, randomize delay from 0 through 3, and randomize dep_offset with legal targets. I: Send sustained random-delay traffic. PO: Each packet uses its own delay and produces the correct result. | `in_monitor` collects delay; `scb` compares the corresponding processed result. | Delay 0, 1, 2, and 3. | `tc_if_basic` (not implemented) |
| IF-004 | Dependency | C: Randomize `valid`, `packet`, and delay; randomize dep_offset from 0 through 7 with every nonzero target legal. I: Send sustained random-dependency traffic. PO: Independent packets use zero dependency data and dependent packets use the exact K-th preceding result. | `in_monitor` builds accepted order and collects dep_offset; `scb` checks the target and result. | dep_offset 0 through 7; cross `delay × dep_offset`. | `tc_if_dependency` (not implemented) |
| IF-005 | Dependency topology | C: Randomize `packet` and delay; direct `valid` and dep_offset for each target topology; keep every target legal. I: Traverse all 127 nonempty repeated-dependency combinations over the next seven positions, cover same/cross-batch consumer placement, and create chains plus fanout continuing into a chain. PO: Every consumer gets the correct target and every chain level uses its direct predecessor. | `in_monitor` records producer/consumer relationships; `scb` checks fanout and chain results. | Consumer count 1 through 7; chain depth; dep_offset 1 through 7. | `tc_if_dependency` (not implemented) |
| IF-006 | Dependency boundaries | C: Randomize `packet`; direct `valid`, delay, and dep_offset for each target boundary; keep every target legal. I: Direct same-batch sparse dependency, cross-batch offsets 1/7, a delay-3 producer with immediate consumer, dependency after target output, consumers of one producer on both sides of target output, and dependency across sequence wrap. PO: Every consumer receives the exact target result under each boundary. | `in_monitor` records abstract accepted order; `scb` checks boundary targets and results. | Same batch, cross batch, target pending, target output, across-output-boundary, and wrap are hit. | `tc_if_dependency` (not implemented) |

The 127 repeated-dependency combinations are distributed by consumer count:

| Consumers | Combinations |
| ---: | ---: |
| 1 | 7 |
| 2 | 21 |
| 3 | 35 |
| 4 | 35 |
| 5 | 21 |
| 6 | 7 |
| 7 | 1 |

## 3. Functional Dimension

The functional and interface dimensions share test-case planning. No separate
functional test case is created; the following points map into the interface
dependency test case.

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| FUNC-001 | Dependency result | C: Randomize `valid`, `packet`, and delay; direct dep_offset to a pending or already-output target; keep dependencies legal. I: Create both target states. PO: Consumers receive the same exact processed target result. | `in_monitor` records target relationships; `scb` checks dependency results. | Target pending and target output hit. | `tc_if_dependency` (not implemented) |
| FUNC-002 | Multiple consumers and chains | C: Randomize `packet` and delay; direct `valid` and dep_offset for shared targets and dependency chains; keep all dependencies legal. I: Create shared targets and multilevel chains. PO: Shared reads and every chain level are correct. | `in_monitor` records topology; `scb` checks results level by level. | Single consumer, multiple consumers, and chain hit. | `tc_if_dependency` (not implemented) |
| FUNC-003 | Long-stream wrap | C: Randomize `valid`, `packet`, and delay; randomize legal dep_offset and direct dependencies across wrap boundaries; apply no reset. I: Send enough legal traffic to pass finite encoding wraps. PO: Dependency targets and processed results remain continuous across each wrap. | `in_monitor` maintains abstract acceptance order; `scb` checks dependency results across wrap boundaries. | Order wrap and dependency across wrap hit. | `tc_if_dependency` (not implemented) |

## 4. Backpressure Dimension

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| BP-001 | Global backpressure | C: Fix `valid` at full width, randomize `packet` and delay, randomize dep_offset with legal targets, and target cycles with `bkps=1`. I: Offer and hold a complete batch during backpressure. PO: No lane is accepted and partial acceptance is forbidden. | `in_monitor` confirms no accepted transaction; `scb` confirms expected count unchanged. | Input request while `bkps` is active. | `tc_backpressure` (not implemented) |
| BP-002 | Input hold | C: Randomize `valid`, `packet`, and delay, randomize dep_offset with legal targets, and hold every input field fixed after `bkps=1`. I: Hold for one and multiple cycles until release. PO: The batch is accepted exactly once on the first legal edge after release. | `in_monitor` checks stability and single acceptance. | One-cycle and multicycle backpressure hit. | `tc_backpressure` (not implemented) |
| BP-003 | Backpressure boundary | C: Randomize `packet` and delay, randomize dep_offset with legal targets, and direct `valid` to sparse/full patterns. I: Send sustained input around `bkps` assertion and release. PO: The accepted set on each edge matches `bkps`, with no partial batch acceptance. | `in_monitor` checks actual accepted masks at backpressure boundaries; default checks verify subsequent outputs. | Assertion, release, sparse, and full batches hit. | `tc_backpressure` (not implemented) |

## 5. Reset Dimension

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| RST-001 | Reset values | C: Set `rst_n=0`; direct `valid` to all-zero and nonzero values; randomize other inputs without requiring a legal transaction during reset. I: Apply both valid classes during reset. PO: `bkps` active, all `out_valid` inactive, and no acceptance/output. | `reset_monitor` checks reset ports; `in_monitor`/`out_monitor` confirm no transaction. | Invalid and valid input while reset hit. | `tc_reset` (not implemented) |
| RST-002 | Asynchronous assert, synchronous release | C: Set valid=0, randomize other inputs, and direct reset assertion/release phases away from clock edges. I: Assert and release `rst_n` while the clock runs. PO: Assertion is immediate and release takes effect only after synchronization. | `reset_monitor` checks assertion/release timing; `out_monitor` checks valid state. | Asynchronous assertion and synchronous release hit. | `tc_reset` (not implemented) |
| RST-003 | In-flight reset | C: Randomize `valid`, `packet`, and delay, randomize dep_offset with legal targets, and direct reset timing to input wait, pending traffic, and output activity. I: Assert reset in each target phase. PO: All old transactions are cancelled and never appear after reset. | `reset_monitor` records phase; `scb` clears old expected; `out_monitor` checks no old output. | Input wait, pending traffic, and output activity hit. | `tc_reset` (not implemented) |
| RST-004 | Post-reset restart | C: After reset release, randomize `valid`, `packet`, and delay; randomize dep_offset within post-reset history and direct the first legal dependency. I: Send new legal traffic. PO: Packet order, dependency history, and output start lane restart from initial state. | `in_monitor` builds new stream; `out_monitor` collects output; `scb` checks post-reset results. | First packet, first dependency, and first lane wrap hit. | `tc_reset` (not implemented) |

## 6. Scenario Dimension

| ID | Test point | Test-point description | Check mechanism | FCOV | Test-case mapping |
| --- | --- | --- | --- | --- | --- |
| SCN-001 | Backpressure and reset | C: Randomize `valid`, `packet`, and delay, randomize dep_offset with legal targets, and direct reset to occur while `bkps=1`. I: Send sustained traffic and insert reset during backpressure. PO: Acceptance boundaries, old cancellation, and post-reset recovery are correct. | `reset_monitor` records reset; `in_monitor` checks acceptance; `scb` checks cancellation/recovery. | Reset under backpressure and first post-reset batch hit. | `tc_reset` (not implemented) |
| SCN-002 | Consecutive idle cycles | C: Randomize `packet` and delay, randomize dep_offset with legal targets, randomize nonempty `valid` outside the gap, set valid=0 in the gap, and place the gap at `bkps=0`. I: Send nonempty input for several cycles, insert several idle cycles, and resume nonempty input. PO: Idle cycles create no input transaction, previously accepted packets may continue to output, and processing resumes correctly. | `in_monitor` records nonempty batches and the idle interval; default checks verify packets around the interval. | Consecutive-idle length and nonempty batches on both sides hit. | `tc_if_basic` (not implemented) |
| SCN-003 | Single idle cycle | C: Randomize `packet` and delay, randomize dep_offset with legal targets, randomize nonempty `valid` around the gap, set valid=0 for one cycle, and place the gap at `bkps=0`. I: Send nonempty input for several cycles, insert one idle cycle, and resume nonempty input on the next cycle. PO: The idle cycle creates no input transaction and the accepted sequence remains correct across it. | `in_monitor` confirms exactly one idle cycle between two nonempty intervals; default checks verify packets around it. | A single idle cycle and nonempty valid patterns on both sides hit. | `tc_if_basic` (not implemented) |
