# Main adoption of 19-bit TC internals — 2026-11-22

## Adopted change

At the user's explicit request, the validated 19-bit candidate is now installed
in the production `tensor_core_sv/outer_product_core.sv` on the `main` working
tree. External results remain exact signed INT32. The original unit regressions,
additional equivalence/bounds units, and connected-system regression pass using
the **main source paths**. II=8 and publication three advancing edges after
accepted k=7 are unchanged.

The retained source-matched FPGA implementation uses 10,101 LUTs and 11,295 FFs,
with 64 DSPs and 18 RAMB36s. It passes 100 MHz internal OOC setup/hold timing,
but setup margin is only **4 ps**. This adoption does not rerun synthesis,
placement, routing, netlist simulation, or power estimation. It preserves and
references the already validated experiment rather than relabeling GUI runs.

Branch remains `main`, with unchanged HEAD
`2f12bd635963337e04ce8195b19bbb7b23bb2284`. No commit, merge, push, or destructive
Git command was performed. The user's pre-existing AGENTS.md architectural notes
were preserved and reconciled with the newly authorized internal precision.

## Source selection and preservation

- Selected source: [validated candidate](../../../experiments/tc19_20261122/candidate/src/tensor_core_sv/outer_product_core.sv).
- Production source: [outer_product_core.sv](../../../tensor_core_sv/outer_product_core.sv).
- Both SHA-256 values: `E76A2EE5D7D65A85026D39180F111181868974A5CDD076B064BA7CFF4636E8B5`.
- [Applied RTL diff](rtl.diff): only the TC implementation changed. The candidate's
  comments are retained verbatim to preserve byte identity with measured sources.
- [Production manifest](production_manifest.csv): all 93 source/reference/test
  files match the validated candidate snapshot before and after regression.
- [Before-update manifest](before_manifest.csv) and [backup directory](before/):
  exact backups of all seven existing files touched by this adoption, including
  the previous stable 32-bit TC and the pre-existing user edit in AGENTS.md.
- [Preserved evidence manifest](preserved_evidence.csv): 326 experiment artifacts
  remain hash-identical. Historical sources, original tests, expected vectors,
  logs, selected checkpoints, scripts and reports are not rewritten.
- [Initial status](initial_status.txt) and [initial HEAD](initial_head.txt) retain
  the pre-adoption Git state.

The previous stable TC also remains in the isolated experiment's
[baseline snapshot](../../../experiments/tc19_20261122/baseline/src/tensor_core_sv/outer_product_core.sv).
The earlier routing promotion and all experimental reports remain dated evidence.
Statements there that production was unchanged describe the experimental run
before this adoption.

## RTL behavior

The accumulator and two result matrices (`acc_q`, `result_q`, `tail_q`) use
19-bit elements. Each signed 16-bit product is sign-extended to 19 bits before
the fabric addition. External results and the existing combinational `acc`/`tail`
observation views sign-extend to 32 bits. Multiplier `use_dsp="yes"` and adder
`use_dsp="no"` attributes remain in effect.

For signed INT8 operands, a product is in [-16256, 16384]. Every partial sum of
at most eight products is in [-130048, 131072]. Signed 19 bits cover the entire
range; signed 18 bits cannot hold +131072. This relies on K=8, zero initial
accumulation, and independent tiles with no prior-C/cross-tile accumulation.

Ports, packages, packet layout, control conditions, reset, malformed-input and
full-credit whole-edge rejection, presence masks, event timing, result ordering,
and MSU RTL remain unchanged. MSU still accepts arbitrary INT32 values when
independently instantiated. Integrated synthesis may merge replicated sign bits;
that does not change the public MSU interface.

## Fresh main-source regression

Executed from the repository root with PowerShell and ModelSim Intel FPGA
Starter Edition 2020.1, using native execution because the simulator's DLLs do
not load correctly inside the sandbox:

```powershell
pwsh -NoProfile -File reports/verification/tc19_main_20261122/run_regression.ps1
```

The launcher runs original isolated units, additional standalone TC units, then
integration. Original `.do` scripts are copied with only their build-output
directories redirected. Sources, tests, seeds, vectors and assertions are not
modified. The additional launcher compiles the current main package/core and
renames only the preserved 32-bit baseline module in a generated build adapter.

| Check | Observed result |
|---|---|
| MLU | 16,708 C/SV records; 145 resets; 128 rejected edges |
| DU/TIA | 3,292 packets |
| Bridge | 19,147 C-equivalent rows; 7,156 rejected edges; 13 resets |
| TC compatible C replay | 21,032 records; 1,366 publications; 6 malformed offers; 1 full-credit rejection |
| Existing old/new TC comparison | PASS |
| MSU | 8,683 cycles; 676 accepts; 5,394 write beats; 673 done; 42 faults; 8 resets |
| 32-bit/main equivalence | 89,595 edges; all 65,536 bitmap pairs; 10,080 completed tiles; 178 resets; error, credit, stall, stored-zero and simultaneous-transfer checks |
| Signed bounds | All 65,536 operand pairs over 1,024 tiles; extrema -130048 and +131072; 1,023 II=8 intervals; k=7+3 publication |
| Connected system | 369 completed tiles; 3,542 issued packets; 2,987 write beats; 77 resets; all 50 accepted summaries identical |
| Unstalled dense | 24 tiles; 23 II=8 intervals; k=7+3 publication |
| Unstalled mixed | 27 tiles; 26 II=8 intervals; k=7+3 publication |

All three simulator processes returned exit code 0, with no simulator Error or
Fatal entries. Existing `vlog-13314` default port-kind warnings remain. Additional
unit summaries exactly match the validated candidate. No C executable was rebuilt
or rerun during adoption; the original immutable vectors were replayed.

Evidence: [PASS](regression/PASS.txt), [units](regression/units.log),
[additional units](regression/extra.log), [extra summaries](regression/extra_summary.txt),
[integration](regression/top.log), and [all integration summaries](regression/top_summary.txt).
Repeat without replacing accepted logs using a fresh directory name:

```powershell
pwsh -NoProfile -File reports/verification/tc19_main_20261122/run_regression.ps1 -RunName regression_repeat
```

Older promotion/experiment integrity launchers intentionally assert their dated
pre-adoption production manifests. They now reject the current TC, and are left
unchanged. Use the launcher in this directory for the adopted sources.

## Retained post-route measurements and limits

The selected candidate checkpoint is
[`candidate/routed/routed.dcp`](../../../experiments/tc19_20261122/candidate/routed/routed.dcp),
not the unselected `refined/` experiment. The comparison uses Vivado 2022.2,
`xc7z020clg484-1`, the integrated top, the same 10.000 ns OOC clock and default
implementation flow, one synthesis thread and two implementation threads.

| Integrated post-route metric | Fresh 32-bit baseline | Adopted 19-bit candidate | Change |
|---|---:|---:|---:|
| Slice LUTs | 12,769 | 10,101 | -2,668 (-20.89%) |
| Slice registers | 15,519 | 11,295 | -4,224 (-27.22%) |
| Occupied slices | 4,679 | 3,479 | -1,200 (-25.65%) |
| CARRY4 | 553 | 361 | -192 |
| DSP48E1 | 64 | 64 | Unchanged |
| RAMB36E1 | 18 | 18 | Unchanged |
| Setup WNS | +0.296 ns | +0.004 ns | Both pass |
| Hold WHS | +0.082 ns | +0.098 ns | Both pass |

Both selected checkpoints were independently reopened during the experiment and
passed setup/hold, routing and DRC checks. Baseline/candidate routed functional
netlists pass dense, hybrid and dual workloads; the candidate also passes the
three modes with bounds stimulus. Those simulations do not use SDF. These retained
checks were not repeated for the byte-identical source copy.

The worst candidate path is Bridge result-metadata count to TC result-register
enables, with 9.707 ns data delay and 13 logic levels. The narrow 4 ps setup margin
does not establish robustness across other placements. OOC reports do not provide
board I/O timing sign-off; no new 19-bit power, board, or ASIC measurement is claimed.

See the [complete experiment report](../../../experiments/tc19_20261122/REPORT.md),
[resource CSV](../../../experiments/tc19_20261122/resource_comparison.csv),
[candidate audit](../../../experiments/tc19_20261122/audit/candidate/PASS.txt), and
[validation record](../../../experiments/tc19_20261122/validation.PASS.txt).
Existing Vivado GUI runs remain historical. The project already references
`../tensor_core_sv/outer_product_core.sv`, so its next build uses the adopted RTL;
no project edit or overwrite of old runs was needed.

## Changed and added files

Modified existing files:

- `tensor_core_sv/outer_product_core.sv`: exact validated candidate.
- `AGENTS.md`: reconcile physical precision with the user-authorized adoption,
  preserving the earlier operand-route and systolic-removal notes.
- `README.md`, `docs/architecture.md`, `tensor_core_sv/README.md`: current precision,
  numeric bounds, validation, measured resources and timing limits.
- `integration_sv/README.md`, `docs/verification-and-reproduction.md`: current
  verification links and a launcher that checks the new production manifest.

Added files are confined to this record: this README, `run_regression.ps1`,
`extra.do`, `rtl.diff`, manifests, initial Git records, exact `before/` backups,
and `regression/` logs plus generated simulator build artifacts. No original test,
reference, vector, implementation script, or historical report was changed.
