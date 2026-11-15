# Result-banking artifact cleanup, 2026-11-15

The user authorized removal of unsuccessful experiment intermediates. This
directory had 453 files totaling 520,669,863 bytes. Cleanup deleted 250 files
totaling 472,383,321 bytes and preserved the contents of 203 original files.
New cleanup records add a small amount of storage.

The retained experimental checkpoint is
[`distributed_flat/fresh_10/refined/routed.dcp`](../distributed_flat/fresh_10/refined/routed.dcp),
SHA256 `ECD3965BAE29B6A5297AFA1FA386D4C003768EA4E2106E88C4147652B017DA1D`.
All source snapshots, patches, constraints, scripts, regression logs, and
timing reports remain available, including text evidence inside `.Xil`.
Other experimental checkpoints and generated binary/cache intermediates were
removed. Historical commands may require regenerating removed intermediates.

`inventory_before.csv` records original paths, sizes, hashes, and decisions.
`deletion_manifest.csv` and `deleted_files.csv` record the planned and completed
deletions. `removed_empty_directories.csv` records removed empty directories.
`verification.json` records the successful SHA256 and deletion checks.

The root README and artifact inventory were updated. Their original bytes are
preserved in `README.before.md` and `artifact_inventory.before.csv`; all other
retained original files are byte-identical at their original paths. The current
inventory keeps its original `Path,Kind,Bytes` schema with repository-relative
paths and excludes itself.

See the [combined cleanup report](../../head_mux_20261115/cleanup_20261115/cleanup_report.md)
for both experiments and baseline verification. Production RTL, the native
100 MHz checkpoint, and protected reference/test files are unchanged. No
simulation/PPA rerun, branch/worktree creation, or commit was performed.
