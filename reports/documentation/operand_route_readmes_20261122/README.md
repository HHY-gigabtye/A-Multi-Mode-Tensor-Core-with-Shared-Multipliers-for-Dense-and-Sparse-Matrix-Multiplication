# README reconciliation after operand-route promotion — 2026-11-22

The user requested updating all READMEs affected by the TC operand-routing
experiment, shared DU/TIA repair, and their promotion to the main working tree.
This documentation update follows the completed
[promotion and main regression](../../verification/operand_route_main_20261122/README.md).
It introduces no RTL, model, vector, test, seed, project, or implementation-flow
change. No commit, merge, or push was performed.

## Scope and changes

The review inventories 39 maintained Markdown READMEs. It updates 26 and leaves
13 unaffected READMEs unchanged. Original `src/`, `snapshot/`, `before/`, and
`README.before.md` copies are protected historical material; generated tool
README files are outside the maintained documentation scope. All new prose is
English, including the retained alternate-language filename aliases.

| Area | Updated files, relative to the repository root |
|---|---|
| Current overview and TC | `README.md`; `tensor_core_sv/README.md`; `tensor_core_sv/README_zh_TW.md` |
| DU/TIA and integration | `du_tia_sv/README.md`; `integration_sv/README.md`; `integration_sv/README_zh_TW.md` |
| Boundary and C-model navigation | `fifo_sv/README.md`; `c code/Tensor Core/Tensor Core/README.md` |
| Operand-route experiment | `experiments/pre_route_20261122/README.md`; its `power/README.md`, `power/du_repair/README.md`, and `sv_diff/README.md` |
| Current promotion | `reports/verification/operand_route_main_20261122/README.md` |
| Earlier shared-core records | `experiments/outer_product_20261121/README.md`; `reports/verification/outer_main_20261121/README.md` |
| Historical verification navigation | `reports/verification/tc_cycles_github_fe14c132/README.md`; `reports/verification/bram_main_20261119/README.md`; `reports/verification/2026-11-13-native-publication/README.md` |
| Historical experiment navigation | `experiments/mlu_bram_100mhz_20261118/README.md`; `experiments/msu_fmax/head_mux_20261115/README.md`; `experiments/msu_fmax/result_bank_20261115/README.md`; `experiments/msu_fmax/target_10ns_20261110/README.md`; `experiments/msu_fmax/target_10ns_20261112/README.md`; `experiments/msu_fmax/native_margin_10ns_20261113/README.md` |
| Archive navigation | `backups/pre_bram_20261119/README.md`; `experiments/msu_fmax/result_bank_20261115/cleanup_20261115/README.md` |

The updated READMEs describe operand ROUTE -> MUL -> signed INT32 ACC, the
unchanged II=8 and k=7+3 timing, the DU/TIA whole-union assignment repair, and
the distinction between RTL and synthesized-netlist validation. They point to
the fresh main-source regression, identify the source-matched retained PPA
evidence, and distinguish current source files from historical GUI checkpoints.
Historical algorithm descriptions, numerical measurements, and experiment
results remain dated evidence rather than being rewritten as current results.

The root and power READMEs summarize the final comparison using the same
repaired DU/TIA in both variants: 22,523 -> 12,769 post-route LUTs, 64 DSPs in
both, passing internal 100 MHz timing, and total power estimates of
0.714 -> 0.573 W dense, 0.574 -> 0.501 W hybrid, and 0.567 -> 0.494 W dual.
The fixed-route clock-boundary difference is only about 1%. Functional-SAIF
power omits SDF delay glitches and is not board-measured power. The unchanged
[measurement report](../../../experiments/pre_route_20261122/REPORT.md)
retains the detailed methodology and original failed/pre-repair evidence.

Historical reproduction commands now explicitly identify their original source
assumptions. The old experiment integrity script expects pre-promotion main
hashes; it is not a gate for the updated main tree. The diff package's main-tree
consistency command now uses `git apply --reverse --check` because its two-file
patch is already applied. Scripts and original package PASS records are unchanged.

The 13 unchanged maintained READMEs cover MLU/MSU standalone contracts, their C
models, the Bridge alias, and already dated unrelated records. They neither
describe the changed TC stage order nor identify superseded evidence as the
latest TC/DU/TIA validation. Their paths and original hashes appear in the
[review inventory](review_inventory.csv).

The [complete README diff](readme.diff) compares all 26 maintained files against
their preserved contents at the start of this documentation task. It excludes
the preceding RTL promotion changes and the new audit record itself.

## Preservation and evidence locations

Every edited README was copied byte-for-byte before editing. The
[before manifest](before_manifest.csv) records 26 README backups and the previous
promotion evidence-location manifest. It preserves the working-tree contents
as found, including the preceding promotion's documentation changes.

Three experiment READMEs were also protected by the promotion's 81-entry
`preserved_evidence.csv`. Their original bytes are now addressed through the
backups in this record. Only those three **Path** values changed in the active
manifest; all 81 original **SHA256** values and all other paths are unchanged.
The [relocation mapping](evidence_relocations.csv) identifies the three entries.
The [original manifest](before/reports/verification/operand_route_main_20261122/preserved_evidence.csv)
is retained verbatim. No hash was replaced to accept modified historical text.
This lets the unchanged promotion regression wrapper continue checking the
original evidence while maintained README entry points describe today's tree.

No numerical report, log, checkpoint, activity capture, source snapshot, or
existing promotion backup is rewritten. Earlier non-README documentation
changes from the promotion, including `AGENTS.md` and `docs/architecture.md`,
remain as found in this task.

## Validation and reproduction

Run the documentation and preservation audit from the repository root:

```powershell
./reports/documentation/operand_route_readmes_20261122/verify.ps1
```

The audit checks README backups and unchanged inventory entries, the 93-file
production manifest, the original promotion backups, all 81 preserved evidence
entries, repaired source/artifact manifests, and original baseline/candidate-v2
snapshot hashes. It also checks local Markdown link targets, the three read-only
patch consistency commands, and `git diff --check`. Results are written to
[validation.txt](validation.txt), [link checks](link_checks.csv), and the
[after manifest](after_manifest.csv). These checks do not run an RTL simulator,
synthesis, place-and-route, or power analysis; earlier passing results remain
attributed to their original runs.

New files for this update are confined to this documentation record: this
README, `verify.ps1`, `before/` backups, `before_manifest.csv`,
`review_inventory.csv`, `evidence_relocations.csv`, `after_manifest.csv`,
`readme.diff`, `link_checks.csv`, and `validation.txt`. The only edited non-README file is the
promotion's `preserved_evidence.csv`, for the three original-byte locations
described above.
