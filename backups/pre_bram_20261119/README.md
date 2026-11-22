# Historical archive: pre-BRAM and pre-shared-core design, 2026-11-19

> **Historical architecture only.** This archive predates the shared outer-product
> core. The original README describes a dense systolic path and a separate sparse
> outer-product path, with 128 DSPs and predecessor timing. Those statements apply
> to the archived design. Current `main` uses one shared 64-multiplier
> `operand ROUTE -> MUL -> ACC` pipeline for all three formats. Read the
> [current project overview](../../README.md),
> [current TC contract](../../tensor_core_sv/README.md), and
> [current TC and DU/TIA promotion record](../../reports/verification/operand_route_main_20261122/README.md)
> for the active implementation.

## Preserved original material

On 2026-11-22, all 34 local files from this backup were relocated together into
`snapshot/`, without changing any file bytes. The 33 previously published files
remain published. The ignored routed checkpoint remains local-only.

- [Original repository README, unchanged](snapshot/README.md): historical prose;
  words such as "current" and "production" refer to the November 19 snapshot.
- [Original backup and restoration instructions](snapshot/BACKUP.md).
- [Original 22-file SHA-256 manifest](snapshot/manifest.csv),
  [base commit identifier](snapshot/base_commit.txt), and
  [protected-input hash record](snapshot/protected_initial.csv).
- [Original FF implementation notes](snapshot/implementation/README.md) and
  [six-file implementation manifest](snapshot/implementation/manifest.csv).
- [Relocation record](relocation_20261122.csv): original path, new path, SHA-256,
  and publication availability for every relocated file.

Interpret paths in the original backup instructions and 22-file manifest relative
to `snapshot/`; implementation-manifest paths remain relative to
`snapshot/implementation/`. `protected_initial.csv` records original
repository-relative reference/test paths, not additional files inside this backup.
Older reports retain their original path strings: insert `snapshot/` after
`backups/pre_bram_20261119/` when locating the relocated files. Restoration is a
deliberate historical operation; the archive is not part of the active source set.

The six-file implementation manifest includes `original_ff_routed.dcp`. That
checkpoint is preserved locally and excluded from GitHub by the existing `*.dcp`
rule. The other five files are published text reports. The original manifests and
dated measurement records have not been regenerated.

## Navigation for the original README's 19 broken references

The original README was copied from the repository root. Its relative links are
preserved as evidence; use this table when reading it. A current reference below
is explicitly **not** the archived interface contract. Historical logs and reports
describe predecessor runs and do not establish shared-core performance.

| Original target | Usable destination and scope |
|---|---|
| `mlu_sv/README.md` | [Current MLU documentation](../../mlu_sv/README.md) |
| `du_tia_sv/README.md` | [Current DU/TIA documentation](../../du_tia_sv/README.md) |
| `fifo_sv/README.md` | [Current Bridge contract](../../fifo_sv/README.md); updated since the snapshot |
| `tensor_core_sv/README.md` | [Current shared-core contract](../../tensor_core_sv/README.md); replaces the predecessor contract |
| `msu_sv/README.md` | [Current MSU documentation](../../msu_sv/README.md) |
| `integration_sv/README.md` | [Current integration contract](../../integration_sv/README.md); updated since the snapshot |
| `integration_sv/tb/tb_sparse_tensor_core_top.sv` | [Retained system testbench](../../integration_sv/tb/tb_sparse_tensor_core_top.sv); unchanged from the recorded base commit at this audit |
| `docs/Overall System Architecture.png` | [Overall system diagram](../../docs/Overall%20System%20Architecture.png); unchanged overview of module boundaries, not a TC-internal diagram |
| `docs/DU&TIA and Tensor Core architecture.png` | Removed from current documentation because it depicts the obsolete dual path. No replacement is embedded here; use the current TC contract for the shared core. |
| `experiments/msu_fmax/margin_10ns_20261113/final_live/units.log` | [Historical unit log](../../experiments/msu_fmax/margin_10ns_20261113/final_live/units.log) |
| `experiments/msu_fmax/margin_10ns_20261113/final_live/top.log` | [Historical integration log](../../experiments/msu_fmax/margin_10ns_20261113/final_live/top.log) |
| `experiments/msu_fmax/margin_10ns_20261113/final_live/functional_validation.txt` | [Historical functional validation](../../experiments/msu_fmax/margin_10ns_20261113/final_live/functional_validation.txt) |
| `docs/verification-and-reproduction.md` (two occurrences) | [Current reproduction guide](../../docs/verification-and-reproduction.md); updated since the snapshot |
| `experiments/msu_fmax/native_margin_10ns_20261113/README.md` | [Historical native-build guide](../../experiments/msu_fmax/native_margin_10ns_20261113/README.md), with later architecture annotations |
| `experiments/msu_fmax/native_margin_10ns_20261113/independent_audit/checkpoint/timing_summary.rpt` | [Historical independent timing report](../../experiments/msu_fmax/native_margin_10ns_20261113/independent_audit/checkpoint/timing_summary.rpt) |
| `experiments/msu_fmax/native_margin_10ns_20261113/result.json` | [Historical result summary](../../experiments/msu_fmax/native_margin_10ns_20261113/result.json) |
| `docs/source-audit.md` | [Current source audit](../../docs/source-audit.md); updated since the snapshot |
| `reports/verification/2026-11-13-native-publication/README.md` | [Historical publication validation](../../reports/verification/2026-11-13-native-publication/README.md) |

## Integrity and link validation

Run from the repository root:

```powershell
node tools/verify_archival_docs.cjs
```

The check verifies relocated file hashes, original manifests, preserved cleanup
records, and repository-local Markdown links. Only the exact 19 broken references
in the unchanged snapshot README and the four in the unchanged
[result-banking README](../../experiments/msu_fmax/result_bank_20261115/cleanup_20261115/README.before.md)
are allowed, as recorded in the
[hash-bound exception list](../../docs/archival_link_exceptions.json).
New navigation links must resolve to publishable files or directories. Original
snapshots are evidence copies, not the maintained reading entry points.
