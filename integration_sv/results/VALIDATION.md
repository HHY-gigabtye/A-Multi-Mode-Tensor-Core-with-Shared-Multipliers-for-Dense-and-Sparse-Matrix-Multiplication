# ModelSim SV validation — 2026-10-27

Tool: Model Technology ModelSim - INTEL FPGA STARTER EDITION 2020.1,
Simulator 2020.02 (Feb 28 2020), Windows.

Working directory: `C:\Users\Jason\Desktop\TC`.

Actual executed commands:

```powershell
vsim -version
vsim -c -l integration_sv/results/units.log -do integration_sv/sim/run_units.do
vsim -c -l integration_sv/results/top.log -do integration_sv/sim/run_top.do
```

Both final simulations returned exit code 0. Simulator execution needed to run
outside the Codex sandbox because the 32-bit ModelSim executable encountered
a DLL relocation error inside the sandbox.

## Unmodified unit SV baseline

| Unit | Actual PASS observation |
|---|---|
| MLU | 16,708 records; 145 resets; 128 expected rejected edges |
| DU/TIA | 3,292 packets checked |
| Bridge/FIFO | 19,147 rows; 7,156 expected rejected edges; 13 resets |
| Tensor Core | 136,136 records; 169 resets; 13 expected rejection cases |
| MSU | 8,683 cycles; 676 accepted results; 5,394 beats; 673 completed tiles; 8 resets |

The rejection/fault counts above are expected coverage from existing unit tests,
not integration failures. The unit baseline consumes the unchanged stored vectors;
no C model was compiled or changed during this task.

## Final SV integration

```text
TOP COVERAGE full_credit=2175 fifo_full=1667 inflight4=2489 meta_full=1287 msu_full=1320 tc_full=535
TOP COVERAGE fifo_both=2167 meta_both=4 fifo_wrap=367 meta_wrap=150 sparse_II8=145
TOP COVERAGE write_stall=1138 last_stall=43 mlu_stall=1521 read_stall=37 command_stall=3754 mode_wait=81
TOP COVERAGE modes=104/159/117 zero_count=383 full_count=383 stored_zero=1269
TOP MODE TRANSITIONS 0->0/1/2=47/47/10 1->0/1/2=10/11/96 2->0/1/2=10/77/11
TOP RESET COVERAGE fifo=1ff inflight=1f meta=7 msu=7 tc=7 mlu=7 rows=ff read=1 last=1
TOP INTEGRATION PASS: completed_tiles=316 issued_packets=3124 write_beats=2563 resets=75 seed=91e10da5
```

316 completed tiles comprise 208 main-stream tiles and 108 post-reset recovery
tiles. Global packet/beat counters also include correctly checked partial work
discarded by reset, so they are intentionally not `completed_tiles * 8`.
Coverage counters count observations/events, not distinct completed tiles.
75 resets include initial setup, phase changes, occupancy-target setup and the
36 targeted resets followed by recovery. All occupancy bitmap bits are covered.

No Fatal/Error occurred. Compilation reports six existing `vlog-13314` warnings
about default input port kind in the unmodified MLU, Bridge and MSU; the new top
and TB compile without warnings. The final simulation reports Errors: 0, Warnings: 0.

## Scope and reconciliation

- Changed design: added one top that connects the existing five modules. No
  existing tracked source, reference, vectors or assertions were changed.
- At task start, `msu_sv/sim/run_msu.do` already had uncommitted edits and the
  workspace already contained untracked MSU/root logs; these were preserved.
- The MLU-local DU package and FIFO-local TC package are byte-identical to the
  selected integration packages, verified with SHA-256. Only one copy of each
  package is compiled for the integration.
- The existing Bridge already owns four tag stages; duplicating them in top
  would misalign payload and metadata. No duplicate sideband was added.
- The standalone MLU exposes `command_ready` even during reset; top explicitly
  gates external ready/valid transfer signals with `rst_n` without changing MLU.
- Older architecture notes label ModelSim baseline claims as unverified. The
  logs in this directory now provide direct execution evidence for this checkout.
- Legal traffic and reset recovery are covered end-to-end. Malformed external
  commands/images retain the component-level fault/reset contract; no new
  transaction recovery mechanism is implied.
- No synthesis, PPA, placed/routed timing, real HBM/AXI, or hardware execution
  was performed. The simulation clock period is not an Fmax measurement.

See `top.log` and `units.log` for full compilation and execution evidence.
