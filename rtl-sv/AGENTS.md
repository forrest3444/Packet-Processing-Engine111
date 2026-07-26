# RTL Design Guidelines

## File Organization

Use a fixed module skeleton for shared definitions, then organize the implementation by functional domain.

Recommended order:

1. Module parameters
2. Ports, grouped by interface
3. Local parameters and type definitions
4. Functional domains
5. Verification hooks, if any

Do not group all combinational logic in one section and all sequential logic in another for medium or large modules.

## Functional-Domain Grouping

Group internal signals and logic by architectural responsibility, such as:

- Input handling
- State tracking
- Datapath processing
- Arbitration
- Output handling

Within each functional domain, keep related declarations, combinational logic, next-state logic, and sequential updates close together.

## Parameters and Types

- Use `parameter` only for externally configurable values.
- Use `localparam` for internal derived constants.
- Place design-wide shared types and constants in a package.
- Keep module-specific implementation details local to the module.

## Signal Ownership

- Each signal must have exactly one driver.
- Each register must be updated in exactly one `always_ff` block.
- Group registers that belong to the same function and share the same reset and enable conditions.
- Avoid one large `always_ff` block containing unrelated state.

## Combinational Logic

- Use `always_comb`.
- Assign default values before conditional logic.
- Ensure every output is assigned on all paths.
- Avoid inferred latches and combinational loops.
- Keep priority behavior explicit.

## Sequential Logic

- Use `always_ff`.
- Use nonblocking assignments only.
- Reset control state and valid bits as required.
- Do not reset large datapath arrays unless functionally necessary.
- Make simultaneous update priority explicit.

## State Machines

- Define states with `typedef enum`.
- State encoding is a microarchitecture decision and must follow the design
  specification. Use one-hot encoding only when required or justified by
  implementation evidence; do not change encoding for style alone.
- Use three-process style: next-state logic, state register, and output logic.
- Default `state_d` to `state_q` at the top of `always_comb`.
- Always include a `default` branch that returns to a safe state.

## Naming

Use consistent suffixes:

- `_i`: input
- `_o`: output
- `_q`: registered/current value
- `_d`: next value
- `_en`: update enable
- `_valid`: valid indication
- `_ready`: ready indication
- `_fire`: successful valid-ready handshake
- `_idx`: index
- `_ptr`: pointer
- `_cnt`: counter
- `_n` or `_ni`: active-low signal

Internal point-to-point interconnects may omit direction suffixes when ownership
is clear. Module ports should retain direction suffixes unless fixed by an
external protocol.

## Source Conventions

- Begin synthesizable `.sv` files with ``timescale 1ns/1ps`` and
  ``default_nettype none``; restore ``default_nettype wire`` at end of file.
- Use a concise file header stating the file, block, responsibility, and
  governing design references when applicable.
- Express repeated channels as packed arrays instead of numbered ports.
- Keep shared dimensions and types in a package; derive private widths with
  `localparam`.
- Use `int` only for static loop indices. Synthesized counters, pointers,
  addresses, and arithmetic temporaries require explicitly sized types.
- Give every `always_comb` and `always_ff` block a functional label.

## Reset, Clock Enables, and Verification

- Do not manually instantiate or derive gated clocks. Express clock-enable
  intent with conditional register updates and let implementation tools infer
  clock gating.
- Reset valid bits, state, pointers, and other control state. Do not reset wide
  data arrays when their contents are ignored while valid is clear.
- Hold wide registers when their valid/write enable is false, and drive invalid
  combinational data outputs to zero when doing so suppresses meaningless
  switching.
- Keep protocol and consistency assertions in verification-only files unless
  the functional specification requires hardware handling.

## General Rule

Prefer functional cohesion and clear state ownership over purely visual separation of combinational and sequential logic.
