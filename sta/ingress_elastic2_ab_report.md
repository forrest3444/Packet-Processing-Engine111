# Ingress two-slot elastic buffer A/B report

## Scope

This report records the A/B comparison that preceded adoption of the two-slot
elastic ingress. The two-slot design is now the production implementation and
the specification, HLD, and LLD have been synchronized. Experiment-only RTL and
alternate file lists were removed after adoption.

## Input-register compliance

The experimental ingress obeys the PPE external input-register rule:

- `in_valid_i`, `in_packet_i`, and `in_desc_i` are used only as write data for
  slot 0 or slot 1 registers.
- Slot write enable is derived from registered `bkps_q` and the registered write
  pointer. Raw input values do not control write enable, pointers, occupancy,
  allocation, backpressure, or output logic.
- Allocation and dependency parsing consume only the registered head slot, so
  an external input cannot affect internal behavior until after a clock edge.
- Backpressure remains registered. No manual gated clock or ICG cell is present;
  bank-local conditional updates provide clock-enable coding for implementation
  tools that support automatic clock-gating inference.

Verilator full-design lint completes without errors or warnings that block the
build.

## Functional and performance verification

Both designs passed the same existing UVM environment without modifying the
driver, monitor, scoreboard, interface, or environment components.

| Check | Three-batch baseline | Two-slot elastic |
| --- | ---: | ---: |
| Full functional/performance regression | 25/25 pass | 25/25 pass |
| Additional functional seeds 7, 41, 99 | 12/12 pass | 12/12 pass |
| Saturated ingress stress, seed 17 | pass | pass |
| Stress packets completed | 256 | 256 |
| Stress peak ROB occupancy | 32 | 32 |
| Stress backpressure cycles | 1107 | 1123 |
| Stress completion time | 14220 ns | 14210 ns |

The stress sequence includes empty input beats whose invalid-lane payload and
descriptor values continue changing, mixed valid masks, dependency chains,
mixed delays, ROB-full operation, and repeated registered backpressure.

Selected performance results:

| Workload | Metric | Three-batch | Two-slot | Observation |
| --- | --- | ---: | ---: | --- |
| P0 | issue/retire packets per cycle | 3.8788 | 3.8935 | No sustained loss; cycle-window effect favors two-slot by 0.38% |
| P0 | average latency | 8.00 | 7.00 | One input stage removed |
| Mixed load | issue/retire packets per cycle | 1.9027 | 1.9059 | No sustained loss; +0.17% |
| Mixed load | average/max latency | 18.93/31 | 17.40/29 | Lower occupancy time |
| P6 dependency 50% | source accept rate | 2.2456 | 2.2165 | Two-slot burst absorption is 1.30% lower |
| P6 dependency 75% | source accept rate | 1.7840 | 1.7595 | Two-slot burst absorption is 1.37% lower |

The one-slot capacity reduction does not reduce measured issue or retire
throughput. It does make registered backpressure visible slightly earlier under
dependency-heavy saturation, which is the expected burst-capacity tradeoff.

## Comparative STA and area

Both placed comparisons use the same Nangate45 typical corner, 2.857 ns clock
period (350 MHz), 0.050 ns clock uncertainty, 0.200 ns input/output delay, and
the same die/core dimensions. Results are pre-CTS placement-estimated and are
comparative data, not foundry signoff.

| Metric | Three-batch | Two-slot | Change |
| --- | ---: | ---: | ---: |
| Synthesized cell area | 13195.728 um^2 | 9058.098 um^2 | -31.36% |
| Synthesized cells | 4850 | 3699 | -23.73% |
| Sequential area | 7344.792 um^2 | 4912.488 um^2 | -33.12% |
| DFF count | 1620 | 1083 | -537 |
| MUX2 count | 2153 | 1616 | -537 |
| Detailed-place cell area | 13314 um^2 | 9857 um^2 | -25.97% |
| WNS at 2.857 ns | +1.5926 ns | +1.6198 ns | +0.0272 ns |
| TNS | 0 | 0 | unchanged |
| Worst register-to-register arrival | 0.9610 ns | 0.8749 ns | -0.0861 ns |
| Reported core fmax | 950.71 MHz | 1035.49 MHz | +8.92% |

The dominant area reduction is exactly one 4-lane registered input batch: 537
data/state flip-flops and the corresponding 537 hold/write muxes. This also
removes one level of storage selection from important paths.

## Adoption decision

The two-slot implementation is a favorable candidate: it preserves measured
retire throughput and input-register compliance while materially reducing area
and modestly improving timing. Its explicit cost is one fewer batch of burst
absorption, observed as approximately 1.3% lower source acceptance in the most
dependency-heavy performance cases and 1.45% more backpressure-high cycles in
the dedicated saturation test.

The two-slot implementation was adopted after this comparison. The governing
documents now define the two-slot input boundary and its one-cycle-lower input
latency. Production regression and STA must use `rtl/filelist.f`.
