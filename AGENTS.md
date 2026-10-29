# AGENTS.md — Sparse Tensor Core development instructions

> Handoff prepared 2026-10-24. This file supplies engineering guardrails for Codex; it is **not** proof that the checked-out RTL matches every statement in the design notes. Read `docs/architecture.md` before making substantive changes.

## Mission and source of truth

This project implements a tile-based **8×8×8 INT8/INT32 Sparse Tensor Core**: MLU → DU/TIA → credit-controlled Bridge/FIFO → Tensor Core → MSU → simplified memory interface. It supports dense × dense, unstructured × 2:4, and unstructured × unstructured workloads.

Precedence in case of disagreement:
1. Explicit instructions from the current user.
2. Actual repository source code, committed tests, measured simulator outputs, and documented interface contracts.
3. `docs/architecture.md` (prior design-decision handoff; may need reconciliation with local files).
4. Historical discussion, comments, or unverified assumptions.

**Report discrepancies. Do not silently modify the implementation or tests to fit a handoff note.** Before trusting an asserted timing, test count, or performance claim, verify it from logs/reports in this checkout.

## Protected material and change discipline

- Treat the working, verified C reference models, reference adapters, expected vectors, and existing regression tests as **read-only by default**. Do not change the golden result, expected outputs, random seeds, or assertions to make an RTL change pass.
- Preserve the current stable RTL version. Before editing, inspect `git status`, the current branch, and relevant files. Do not discard or overwrite existing uncommitted work.
- When optimization is requested, favor an isolated Git branch/worktree or other user-approved copy. Never use destructive Git commands (`reset --hard`, `clean -fd`, force-push) or delete historical versions without explicit authorization.
- Do not commit, merge, or push unless asked. Git operations may be local; a GitHub remote is not required.
- Confine edits to the requested unit and its tests. List newly created and modified files. If change scope must expand, explain why before doing so.
- Do not change stable module ports, packet layouts, handshake semantics, cycle latency, memory layout, or result ordering without explicit approval and an updated compatibility/test plan.

## Work procedure for each task

1. Inspect the actual file tree, applicable package/header files, C model, RTL, existing testbench, scripts, and `docs/architecture.md`. **Never invent file paths, interfaces, or a passing status.**
2. State the requested unit, expected behavior, which files would change, assumptions needing confirmation, and how to test it.
3. Make a small, focused change. Prefer synthesizable SystemVerilog (`always_ff`, `always_comb`, explicit widths and casts) and simple, inspectable logic. Avoid latches and accidental signed/unsigned conversions.
4. Validate at the **unit level first** using a standalone testbench with modeled upstream/downstream signals. Do not require unrelated real modules in a unit test. Perform full integration only after individual units pass.
5. Compare against immutable C/reference vectors and mathematical GEMM where applicable; check cycle timing **and** payload/order, not only numerical end results.
6. Run only tools actually available in this execution environment (e.g., GCC, Verilator, ModelSim/Questa, synthesis). If unavailable, report **not run** and give exact reproduction commands once paths are inspected.
7. Show the diff, regression result with actual commands, any known limitations, and whether PPA data are pre-placement estimates or post-route measurements.

## Invariants that must not silently break

- One command/tile corresponds to an independent 8×8×8 operation: signed `int8` operands, signed `int32` accumulation. **No cross-K-tile accumulation** in the current simplified scope.
- Three operating modes: `IO_DENSE=0`, `IO_HYBRID=1` (unstructured A × 2:4 B), and `IO_DUAL=2` (both unstructured); 3 is illegal. Each tile supplies k=0…7, in order, with consistent metadata.
- DU/TIA has 4 register stages S0–S3 and **no downstream `out_ready`** in the established interface. Idle cycles use `in_valid=0`. A stage-4-timed sideband carries `valid/is_sparse/meta/k`, while the DU/TIA itself carries the payload.
- Current packet bridge has 8 FIFO slots and reserves future DU/TIA output capacity: `used = fifo_count + inflight_count <= 8`. **Issue reserves**, DU arrival transfers the reservation into the FIFO, **TC acceptance releases**. Compute `can_issue` from OLD registered occupancy (no speculative same-cycle credit lookahead when full).
- The bridge is **not a bypass FIFO**: DU output is registered into FIFO; TC cannot consume that same newly-arrived packet until the following edge. Its head is combinational (no extra output register).
- `issue`, `tc_accept`, and `result_accept` describe **actual transfers**, not mere requests. A correctly backpressured full condition is a stall, not an error. Violating a contract (issuing without credit) is an error in the C model/diagnostics.
- A new tile's k=0 packet cannot enter TC while the 2-entry result-metadata FIFO is full. Push metadata on **TC acceptance of k=0**; pop on **TC-result→MSU handshake**, NOT on HBM writeback completion.
- Existing TC has a **strict valid contract**: never assert its `in_valid` when it cannot accept that specific packet mode. Present the FIFO head data to determine **mode-aware** `in_ready`, then assert `in_valid` only on eligibility and readiness. `input_ready` alone may not be mode-aware.
- Dense TC path: 8×8 systolic array with input skew. Sparse TC path: outer product with multiply → route → accumulate and a 2-entry result buffer. Signed multiply/casting and 32-bit accumulation are mandatory. Both sparse modes use `is_sparse=1` after DU/TIA.
- MLU: two tile buffers, ordered k-packets, valid/ready stability under stall, 32-byte memory beats; current simplified memory protocol permits only one outstanding read burst.
- MSU: two complete-result buffers, 8×8 INT32 = 256 bytes, eight 32-byte row beats in little endian; do not change `tile_done` timing (only after final accepted write beat). This version does **not** add old C or track AXI/HBM write responses.
- Sample all module outputs from pre-edge state, calculate handshakes, and then advance **all modules once per edge**. Reset related units and pending simulated memory traffic consistently.

## Mandatory regression areas

- Dense, hybrid, and dual sparse; 8 k-packets per tile; mixed-mode streams and mode switches.
- Positive/negative INT8 extremes; signed multiplication and INT32 sums; sparse bitmap popcount, sorted indices, stored zero, legal 2:4 masks (6 choices), zero-count and full-count vectors where legal.
- FIFO full, in-flight occupancy, result-metadata full, result-buffer full, same-edge FIFO push/pop, same-edge metadata push/pop, pointer wrap-around and ordered tile IDs/destination addresses.
- MLU read latency and gaps, upstream stalls, downstream backpressure, sustained sparse overlap (nominal sparse tile II=8 cycles without stalls), reset during every occupancy state, no dropped/duplicated packets or results.
- MSU stalled `write_valid` and stable payload, row-major/little-endian writeback, last-beat completion, two-buffer fill/drain.
- Preserve existing cycle-exact behavior unless user authorizes latency changes and regressions are updated with a separately justified specification.

## PPA optimization rules

- First identify the actual critical startpoint/endpoint, path cells, fanout, slack, library, corner, clock constraint, and implementation phase. A previously mentioned ~80–83 MHz *unplaced* estimate is NOT sign-off timing.
- Optimize only after a clean, reproducible functional baseline and a Git snapshot. Change one concern at a time (PE multiplier/adder path, muxing, routing, buffer/credit logic, stage boundaries).
- Re-run functional regression after every change. Compare area, delay/Fmax, and power only under comparable constraints and flow; mark `unplaced`, `post-place`, and `post-route` separately.
- Do not promise a clock rate or PE-utilization improvement merely from rewriting RTL. Any inserted pipeline stage must reconcile metadata, valid alignment, output latency, TC mode switching and tile overlap.

## Useful first instruction for a new Codex session

"Read `AGENTS.md` and `docs/architecture.md`, inspect this repository, and report (1) actual modules/files, (2) C/RTL/test status, (3) any mismatches with the handoff, and (4) a safe baseline regression plan. Do not modify any file yet."
