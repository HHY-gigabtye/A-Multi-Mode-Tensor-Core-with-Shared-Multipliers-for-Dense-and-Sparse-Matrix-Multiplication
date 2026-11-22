# SystemVerilog change review

This package compares production `main` at
`2458bf6962ea6946d820276a0faba0e00e6fe5e5` with the final isolated candidate in
`../power/du_repair/candidate_v2/src/`. Production has not been changed. No patch
was applied, and no commit, merge, or push was performed.

## Files to review

| Artifact | Contents |
|---|---|
| [final_rtl.diff](final_rtl.diff) | Complete two-file RTL change, with repository-relative paths |
| [01_tc_operand_route.diff](01_tc_operand_route.diff) | TC operand-routing optimization only |
| [02_du_tia_union_repair.diff](02_du_tia_union_repair.diff) | Shared DU/TIA synthesis-compatibility repair only |
| [verification_additions.diff](verification_additions.diff) | Four new verification SV files, shown as additions |
| [source_manifest.csv](source_manifest.csv) | Exact source locations and SHA-256 hashes |
| [PASS.txt](PASS.txt) | Read-only patch consistency checks |

Historical 128-DSP candidate code, duplicated source snapshots, generated
simulation adapters/netlists, and unchanged package/test files are excluded.
The package contains the selected 64-DSP candidate and the shared DU/TIA repair.

## 1. TC: move operand routing before multiplication

Changed file: `tensor_core_sv/outer_product_core.sv`, **75 added / 76 removed lines**.
See [full diff](01_tc_operand_route.diff) and
[final source](../power/du_repair/candidate_v2/src/tensor_core_sv/outer_product_core.sv).

| Area | Before | After |
|---|---|---|
| First stage | Multiply packed A/B lanes; retain count/index metadata | Restore A/B independently to original coordinates; register values and presence masks |
| Second stage | Route 16-bit products by B column and then A row | Multiply registered INT8 operands at fixed coordinates |
| Routing network | 128 16-bit destinations | 16 8-bit operand destinations |
| State | `mul_q`, `route_q` | `operand_q`, `product_meta_q` |
| Multiply capture | `rst_n && in_valid && status == TC_OK` | `rst_n && operand_q.valid && status == TC_OK` |
| Accumulator input | `route_q.delta` with `route_q.enable` | `product_q` with aligned A/B presence masks |
| Arithmetic mapping | Fabric sum inferred from accumulator expression | Explicit `fabric_sum` with `use_dsp="no"`; multiply retains `use_dsp="yes"` |

The fabric-adder attribute avoids the 128-DSP inference seen in the retained
first attempt. The selected candidate has 64 DSPs. Presence masks are separate
from values, so a stored zero remains a valid coordinate while missing entries
receive zero operands. Legal input checks and the whole-edge error freeze remain.

Pipeline timing stays:

```text
Before: multiply      | product routing | accumulate | publish
After:  operand route | multiply        | accumulate | publish
```

No stage is added. The indexed input layout, module ports, signed arithmetic,
two result slots, readiness, result ordering, II=8, and k=7+3 publication remain.
`tick_info.mul` and `tick_info.route` preserve the old observation timing: they
identify the first and second phases, although the physical operations changed.

## 2. DU/TIA: repair an independently exposed synthesis mismatch

Changed file: `du_tia_sv/rtl/du_tia.sv`, **38 added / 24 removed lines**.
See [full diff](02_du_tia_union_repair.diff) and
[final source](../power/du_repair/candidate_v2/src/du_tia_sv/rtl/du_tia.sv).

This change was added during power validation. Both original routed netlists
failed legal sparse traffic even though their RTL simulations passed. A
standalone synthesized DU/TIA reproduced the failure without the TC:

```text
A bitmap:        f2
Expected indices [1, 4, 5, 6, 7]
Netlist indices  [0, 0, 0, 0, 7]
```

The user authorized expanding the isolated experiment to repair this problem.
Both compared versions now use the same corrected DU/TIA, keeping the TC power
comparison fair. Production and the original failed netlists remain unchanged.

S1 and S2 originally built payloads by repeatedly writing fields through packed
union members. They now use local ordinary packed structs and one whole-union
assignment per selected mode. For example, these actual S2 statements change:

```diff
-            s2_d.packet.payload.sparse.a.index[merge_position_a] =
+            sparse_payload.a.index[merge_position_a] =
                 s1_q.payload.sparse.a_low.index[lane_index];
```

The completed S2 payload is selected once:

```systemverilog
if (s2_d.packet.is_sparse) s2_d.packet.payload = sparse_payload;
else s2_d.packet.payload = dense_payload;
```

S1 uses the corresponding `sparse_predecode_t` and `s1_dense_payload_t` locals;
S2 uses `sparse_output_payload_t` and `dense_output_payload_t`. All locals are
initialized to zero. Decode helpers, compaction loops, counts, ordering, S0/S3,
pipeline registers, reset, ports, and four-stage latency remain unchanged.
This is a tested workaround for the observed Vivado 2022.2 RTL/netlist mismatch;
it is not a claim of a vendor-confirmed general compiler defect.

## 3. Added verification SV files

These are new files, not edits to the original regression tests or golden models.
Their complete contents are in [verification_additions.diff](verification_additions.diff).

| File, relative to the experiment | Added lines | Purpose |
|---|---:|---|
| `tb_pre_route_equiv.sv` | 202 | Standalone common-stimulus TC comparison with independent GEMM, timing, error, backpressure, and reset checks |
| `power/tb_power.sv` | 239 | Identical dense/hybrid/dual memory workloads, signed GEMM scoreboard, tile interval checks, and netlist port adapter |
| `power/du_repair/du_gate.sv` | 13 | Flat standalone DU/TIA synthesis boundary to isolate the mismatch |
| `power/du_repair/tb_du_gate.sv` | 144 | Exhaustive bitmap pairs, directed hybrid cases, mixed traffic, idle cycles, and resets |

`power/du_repair/du_tia_fixed.sv` is the canonical repaired DUT copy; it is
byte-identical to the DU/TIA file in both repaired snapshots and is represented
once in the RTL diff, not counted as another functional modification.

## Validation and provenance

No RTL was edited or re-simulated while preparing this review package. The
existing measured evidence is retained:

- Both repaired variants pass all unchanged original unit/integration suites,
  including 50 identical top summaries:
  [baseline](../power/du_repair/baseline/regression/PASS.txt),
  [candidate](../power/du_repair/candidate_v2/regression/PASS.txt).
- Repaired standalone synthesized DU/TIA passes 65,536 A/B bitmap pairs,
  6,144 directed hybrid cases, and mixed/reset traffic:
  [unit PASS](../power/du_repair/fixed_gate/PASS.txt).
- Six repaired RTL and six routed functional power workloads pass:
  [validation](../power/du_repair/validation.PASS.txt).
- Both independently reopened routed checkpoints pass internal 100 MHz STA:
  [audit](../power/du_repair/audit/audit_summary.txt).

Patch checks run from the repository root, without applying any change:

```powershell
git apply --check experiments/pre_route_20261122/sv_diff/final_rtl.diff
git apply --reverse --check --directory=experiments/pre_route_20261122/power/du_repair/candidate_v2/src experiments/pre_route_20261122/sv_diff/final_rtl.diff
git apply --reverse --check experiments/pre_route_20261122/sv_diff/verification_additions.diff
```

All three checks pass. The first validates the old side against production; the
second validates the new side against the selected isolated snapshot; the third
checks that verification additions match their existing source files. These
commands are consistency checks, not authorization to promote the experiment.
Full regression commands, results, and PPA methodology are in the
[experiment report](../REPORT.md) and [repair record](../power/du_repair/README.md).

This packaging task creates only the files in this `sv_diff/` directory.
