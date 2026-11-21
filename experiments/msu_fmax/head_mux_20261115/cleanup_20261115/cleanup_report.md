# Experiment artifact cleanup, 2026-11-15

The user authorized removal of unsuccessful experiment intermediates while
preserving the native 100 MHz baseline, experiment evidence, and two selected
experimental routed checkpoints. Only the `head_mux_20261115` and
`result_bank_20261115` experiment directories were cleaned.

| Experiment | Deleted files | Deleted bytes | Retained original files |
| --- | ---: | ---: | ---: |
| FIFO head / product shadow | 20 | 530,591,763 | 221 |
| Result banking | 250 | 472,383,321 | 203 |
| Total | 270 | 1,002,975,084 | 424 |

The deleted files total 956.51 MiB: 19 unselected checkpoints, 133 Vivado
`.rtd` databases, six `.tim` databases, and 112 other generated cache/library
files. Empty directories were also removed. File-byte totals exclude filesystem
allocation overhead. New cleanup records add a small amount of storage.

## Preserved checkpoints and evidence

- [Product-shadow routed checkpoint](../product_shadow/fresh_10/refined/routed.dcp):
  SHA256 `8D5A80B13BEACEBD621D96F26DD5559473C0E4C452431B36F20ED231DA4FC79C`.
- [Distributed-flat routed checkpoint](../../result_bank_20261115/distributed_flat/fresh_10/refined/routed.dcp):
  SHA256 `ECD3965BAE29B6A5297AFA1FA386D4C003768EA4E2106E88C4147652B017DA1D`.

All source snapshots, patches, constraints, scripts, regression logs, and
timing reports were retained. Text logs/reports/scripts found within `.Xil`
were also retained, so some `.Xil` directories still exist as text evidence.
The selected native 100 MHz checkpoint is outside both cleanup roots and
remains unchanged.

## Verification and audit trail

All 424 retained original file contents were verified by SHA256. The two root
READMEs and two artifact inventories were updated; their exact original
contents are preserved as `README.before.md` and
`artifact_inventory.before.csv` in their respective cleanup directories.
All other retained original files remain at their original paths and are
byte-identical. Each experiment contains:

- `inventory_before.csv`: original paths, sizes, SHA256 hashes, and keep/delete decisions.
- `deletion_manifest.csv` and `deleted_files.csv`: planned deletions and completed deletions.
- `removed_empty_directories.csv`: removed empty directories.
- `verification.json`: retained-content and deletion verification.

The current root artifact inventories list remaining files and cleanup records,
excluding the inventory file itself. Their original column/path conventions
are preserved. Historical commands referencing removed intermediates require
regenerating those intermediates before execution.

The [baseline verification](baseline_verification.json) confirms 11 production
RTL/package hashes, 76 protected reference/test hashes, and the native 100 MHz
checkpoint hash are unchanged. Branch `main` and HEAD
`92c6e44bd003e27ef9b406d7e7d3a6393b13e3db` are unchanged; there is no tracked or
staged diff. No commit was created. Functional simulation and PPA were not
rerun for this artifact-only cleanup; the existing regression/timing records
remain the evidence for the baseline.
