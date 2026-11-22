# Historical archive: result-banking cleanup, 2026-11-15

> **Historical architecture only.** These records concern the predecessor with
> separate dense systolic and sparse outer-product execution. Statements such as
> "production RTL" and "selected baseline" in the original files refer to that
> experiment date. Current `main` uses one shared 64-multiplier outer-product
> `MUL -> ROUTE -> ACC` pipeline. See the
> [current TC contract](../../../../tensor_core_sv/README.md) and
> [shared-core promotion record](../../../../reports/verification/outer_main_20261121/README.md).

## Original records

The [original pre-cleanup README](README.before.md) and
[original artifact inventory](artifact_inventory.before.csv) remain at their
existing paths with unchanged bytes. Their original hashes are recorded in
[inventory_before.csv](inventory_before.csv); no original inventory or verification
record was rewritten for this navigation update.

The [cleanup report](cleanup_report.md), [verification record](verification.json),
[planned deletions](deletion_manifest.csv), [completed deletions](deleted_files.csv),
and [removed empty directories](removed_empty_directories.csv) retain the original
cleanup evidence. Historical inventories include files deliberately deleted in
2026-11-15 cleanup; entries in those CSVs are provenance, not promises that every
artifact remains downloadable. The explicitly retained experimental DCP linked
from the cleanup report is published; deleted intermediates were not restored.

## Navigation for the original README's four broken references

The README originally lived one directory above this snapshot. Use these links
without editing the preserved copy:

| Original target | Preserved historical destination |
|---|---|
| `distributed_flat/rtl.patch` | [Candidate RTL patch](../distributed_flat/rtl.patch) |
| `timing_comparison.csv` | [Timing comparison](../timing_comparison.csv) |
| `final_verification.txt` | [Final verification record](../final_verification.txt) |
| `artifact_inventory.csv` | [Original pre-cleanup inventory](artifact_inventory.before.csv) |

The patch, timing comparison, and verification record match the hashes in
`inventory_before.csv`. The original inventory above preserves the file list that
the original README referred to. For the later retained-file inventory and
architecture annotations, use the [experiment guide](../README.md); it describes
a historical experiment, not the current core's PPA or timing contract.

## Validation

Run `node tools/verify_archival_docs.cjs` from the repository root. It verifies the
original hashes and maintained navigation. The exact four broken references in
`README.before.md` are narrowly recorded in the
[hash-bound archive exceptions](../../../../docs/archival_link_exceptions.json),
alongside the 19 in the [pre-BRAM archive](../../../../backups/pre_bram_20261119/README.md).
The preserved originals remain evidence copies; this guide is the reading entry.
