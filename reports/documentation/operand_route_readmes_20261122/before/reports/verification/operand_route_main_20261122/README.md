# Operand-route TC and DU/TIA repair promotion — 2026-11-22

## Disposition

The user explicitly authorized updating the main TC and DU/TIA while preserving
the prior versions and reports. The two production RTL files are now exact copies
of the final validated isolated candidate. Fresh production unit and integration
regressions pass. The branch remains `main`; HEAD remains
`2458bf6962ea6946d820276a0faba0e00e6fe5e5`. These are working-tree changes: no
commit, merge, push, or destructive Git operation was performed.

Before this update, tracked production files were clean; the existing experiment
directory was untracked. No pre-existing user edits were overwritten.

## Promoted source and preserved versions

| Production file | Selected source under `experiments/pre_route_20261122/` | Change |
|---|---|---|
| `tensor_core_sv/outer_product_core.sv` | `power/du_repair/candidate_v2/src/tensor_core_sv/outer_product_core.sv` | Register routed INT8 operands before multiplication; preserve 64 DSPs and fabric INT32 accumulation |
| `du_tia_sv/rtl/du_tia.sv` | `power/du_repair/candidate_v2/src/du_tia_sv/rtl/du_tia.sv` | Build S1/S2 payloads in plain packed structs and assign each selected union once |

The TC retains the indexed interface, strict whole-edge rejection, presence masks
for stored zeros, two result slots, II=8, and k=7+3 publication. DU/TIA retains its
algorithm, ports, packet layout, and four-stage latency. All 93 production source,
reference, and test files match the selected validated snapshot. Only the two
listed RTL files differ from the pre-update source manifest. No existing test,
assertion, vector, seed, package, C reference model, or integration RTL was changed.

- [Complete applied RTL diff](rtl.diff).
- Direct pre-update backups: [old TC](before/tensor_core_sv/outer_product_core.sv)
  and [old DU/TIA](before/du_tia_sv/rtl/du_tia.sv).
- [Before manifest](before_manifest.csv) also covers pre-update copies of the
  five documentation files changed to reflect the new production datapath.
- [Production manifest](production_manifest.csv) records the 93 accepted hashes.
- [Preserved evidence manifest](preserved_evidence.csv) records 81 original
  reports, scripts, source/test artifacts, checkpoints, and activity captures.
  Their hashes were checked before and after the update/regression.

The original full source snapshots, first 128-DSP candidate, refined candidate,
repaired baseline/candidate, all previous logs, and all physical/power reports
remain under [the experiment directory](../../../experiments/pre_route_20261122/).
Older production verification reports also remain in place. Historical statements
that production was unchanged describe the earlier isolated experiment; this
record documents the later authorized promotion. The old experiment integrity
script intentionally asserts the pre-promotion production hashes; use this
record's production manifest for the updated main sources.

## Fresh production regression

Command run from `C:/Users/Jason/Desktop/TC`:

```powershell
./reports/verification/operand_route_main_20261122/run_regression.ps1
```

ModelSim Intel FPGA Edition 2020.1 runs the original unit suite first, then the
original full integration suite against the main source paths. The wrapper
copies the two existing Tcl launchers into the new result directory and changes
only their build-output directories. This preserves old build artifacts and logs.
All testbench contents, vectors, checks, and compilation source lists are unchanged.
The native simulator uses the host's approved execution outside its filesystem
sandbox. No existing run or report directory is overwritten.

| Check | Observed result |
|---|---|
| MLU C/SV unit | 16,708 records; 145 resets; 128 rejected edges; PASS |
| DU/TIA unit | 3,292 packets; PASS |
| Bridge C/SV unit | 19,147 rows; 7,156 rejected edges; 13 resets; PASS |
| TC compatible C windows | 21,032 records; 1,366 publications; 6 malformed offers; 1 full-credit reject; PASS |
| Existing TC comparison | PASS |
| MSU C/SV unit | 8,683 cycles; 676 accepts; 5,394 beats; 673 completions; 42 faults; 8 resets; PASS |
| Integration | 369 completed tiles; 3,542 issued packets; 2,987 write beats; 77 resets; PASS |
| Unstalled dense | 24 tiles; 23 intervals at II=8; k=7 to publication=3 |
| Unstalled mixed | 27 tiles; 26 intervals at II=8; k=7 to publication=3 |
| Integration summaries | All 50 accepted lines identical to the original baseline |
| Preservation | All 93 production hashes match the validated candidate; pre-update backups and 81 prior evidence files unchanged |

Evidence: [unit log](regression/units.log), [integration log](regression/top.log),
[integration summaries](regression/top_summary.txt), and [PASS](regression/PASS.txt).
For a repeat, select a fresh directory, for example
`./reports/verification/operand_route_main_20261122/run_regression.ps1 -RunName regression_repeat`.

## Retained implementation and netlist evidence

The promotion copies exactly the previously validated source. Synthesis,
placement, routing, full netlist workload simulation, and power estimation were
**not rerun** for this source-copy operation. The existing matching candidate
evidence remains unchanged:

- All six repaired routed functional workloads (two versions x three modes)
  passed 288 tiles each; see [validation](../../../experiments/pre_route_20261122/power/du_repair/validation.PASS.txt).
- Repaired standalone synthesized DU/TIA passed all 65,536 A/B bitmap pairs,
  6,144 directed hybrid cases, and mixed/reset traffic; see
  [unit PASS](../../../experiments/pre_route_20261122/power/du_repair/fixed_gate/PASS.txt).
- The selected candidate has 12,769 post-route LUTs, 15,519 FFs, 64 DSP48E1s,
  and 18 RAMB36E1s. At 10 ns, setup/hold slack is +0.296/+0.082 ns.
- The independently reopened candidate checkpoint passes its internal FPGA OOC
  100 MHz audit; see [audit](../../../experiments/pre_route_20261122/power/du_repair/audit/candidate_v2/PASS.txt).
- Against the baseline using the same DU/TIA repair, LUTs fall 43.3%. The retained
  functional-SAIF total power estimates fall 19.7% dense, 12.7% hybrid, and 12.9%
  dual. These estimates omit routed-delay glitches and are not board measurements.

Full methodology and limitations remain in the unmodified
[experiment report](../../../experiments/pre_route_20261122/REPORT.md).

The Vivado project already references the two production SV paths directly;
the project file was not changed. Existing GUI synthesis/implementation runs and
checkpoints remain historical, and a future rebuild will read the new main source.
No old run is relabeled as a fresh main implementation. The retained matching
candidate checkpoint is
`experiments/pre_route_20261122/power/du_repair/candidate_v2/routed/routed.dcp`.

## Changed and created files

Existing implementation files changed: only `tensor_core_sv/outer_product_core.sv`
and `du_tia_sv/rtl/du_tia.sv`, exactly as in the reviewed [RTL diff](rtl.diff).

Current documentation updated: `AGENTS.md`, `README.md`, `docs/architecture.md`,
`tensor_core_sv/README.md`, and `du_tia_sv/README.md`. These updates describe the
new stage ordering and DU/TIA repair, retain historical measurements as historical,
and link this record. No historical experiment report was edited.

New files are confined to this record directory: `README.md`, `rtl.diff`,
`before_manifest.csv`, `production_manifest.csv`, `preserved_evidence.csv`,
`run_regression.ps1`, `before/` backups, and fresh `regression/` launch adapters,
logs, summary, and PASS file. Generated simulator libraries/waveforms remain
local scratch rather than replacement historical evidence.
