# 10 ns margin experiment, 2026-11-13

> The subsequent [fresh native rebuild](../native_margin_10ns_20261113/README.md)
> reproduced this physical result from RTL and supersedes the pending native
> rebuild limitation below. This dated experiment remains as provenance.

## Selected result

The original RTL is retained. A physical-only guardband search improves routed
setup WNS from +0.002 ns to +0.016 ns at the same 10.000 ns operating period.
Hold WHS remains +0.096 ns, TNS/THS are zero, and all 41,612 routable nets are
fully routed with zero routing errors. Resources are 29,406 LUTs (one more),
21,503 fabric registers and 128 DSPs. The improvement is approximately 14 ps
using the rounded report values; the remaining 16 ps margin is still small.
This is not a board-level timing result or closure at 9.750 ns.

The selected checkpoint is `guardband_9p75/timing_closed.dcp`. The search target
itself has WNS -0.234 ns and TNS -70.485 ns, so it does not meet 9.750 ns.
The final operating constraint is exactly 10.000 ns. An independent read-only
reopen completed at 18:37:58 with the same +0.016/+0.096 ns timing. See
`guardband_audit/` for the independent reports. DSP configuration remains
64 PREG=1 and 64 PREG=0, with all AREG/BREG/MREG=0.

The final critical path is Bridge `head_select_q_reg[4]_rep` to
`g_arithmetic_row[3].g_arithmetic_column[7].product_q_reg/A[5]`, Slow setup
corner, speed file -1 PRODUCTION 1.12. Data delay is 6.178 ns (0.828 ns logic,
5.350 ns routing), through LUT4/LUT5/LUT6. The DSP setup requirement is also
part of the timing check; the 6.178 ns data delay alone is not a clock period.

Main's MSU was restored byte-for-byte to the committed baseline. All 11 live
RTL/package hashes match the baseline manifest. A final original unit-then-
integration regression completed at 18:36:13 with exit code 0, identical
coverage and all 76 protected hashes intact; see `final_live/`.

Only the standalone `tools/build_10ns.tcl` and native
`project_integration/scripts/post_route_10ns.tcl` production entry points are
updated. They append the measured guardband step after the existing closure
stage, then reopen its 10 ns checkpoint through the existing final validator.
No RTL, tests, vectors, operating XDC or XPR settings are changed in the final
selection. The old native run/DCP is deliberately preserved; it still contains
the original +0.002 ns result. The new selected checkpoint is separate.

Validation scope: the original fresh native recipe was already reproduced and
audited; the new physical tail was executed from that exact preserved native
checkpoint and independently reopened. A complete new source-to-native run of
the updated wrappers has not been rerun. The commands below reproduce the new
full standalone recipe or only the measured tail.

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/margin_10ns_rebuild.log -source tools/build_10ns.tcl -tclargs build/margin_10ns_rebuild
```

## Baseline and authorization

The user requested work directly on `main`, without a worktree, and a baseline
commit only if the current 10 ns version was not already committed. Commit
`f6ee5f1` already contains the verified RTL and 10 ns flow, so no new baseline
commit is needed. The pre-existing README/XPR edits and untracked crash/scratch
files are preserved; `preserved_files.csv` records their original hashes and
the existing native routed checkpoint hash.

## Scope and acceptance

The production RTL candidate changes only `msu_sv/rtl/msu.sv`. For binary
addresses, comparison against `64'hffff_ffff_ffff_ff00` can be expressed as
`(&addr[63:8]) && (|addr[7:0])`. Alignment, fault priority, whole-edge rejection,
buffer capacity, interface ports, result order, and cycle timing stay intact.
No equivalence for unknown four-state addresses is claimed. Existing reference
models, vectors, tests, assertions, and seeds remain unchanged.

Run the original isolated units before integration, both before and after the
change, and check all protected hashes and original coverage counters. Use the
existing fresh-source FPGA OOC flow at 10.000 ns on xc7z020clg484-1, then inspect
the resulting paths before further physical optimization. A candidate is kept
in the live RTL only if functional checks pass and fully routed setup margin
improves over the selected baseline while hold, routing, and DRC remain valid.
Preserve every trial even if the baseline is ultimately retained.

The existing 10 ns checkpoint was independently reopened in this session with
`target_10ns_20261110/audit.tcl`; text evidence is retained in
`baseline/audit/`. Setup WNS is +0.002 ns, hold WHS
is +0.096 ns, TNS/THS are zero, and all 41,611 routable nets are fully routed.
The native DCP hash differs from the older `selected_result.json`; it matches
the later cleanup manifest and reproduces the archived timing and resources.

These are internal FPGA OOC STA comparisons. Actual top-level clock-source and
I/O timing requirements have not been provided, so this experiment does not
invent board constraints or claim board timing closure or measured power.

## Commands and status

Run commands from the repository root. Outputs use fresh directories.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial margin_10ns_20261113/baseline
& ./experiments/msu_fmax/regress.ps1 -Trial margin_10ns_20261113/baseline
& ./experiments/msu_fmax/snapshot.ps1 -Trial margin_10ns_20261113/addr_reduce
& ./experiments/msu_fmax/regress.ps1 -Trial margin_10ns_20261113/addr_reduce
& ./experiments/msu_fmax/snapshot.ps1 -Trial margin_10ns_20261113/final_live
& ./experiments/msu_fmax/regress.ps1 -Trial margin_10ns_20261113/final_live
```

The sandbox could not launch ModelSim because of a Windows DLL relocation
error. The same unmodified regression runner was relaunched outside the
sandbox. Baseline regression completed at 17:34:57 (Asia/Taipei), exit code 0:
all five units and integration passed, with all 76 protected-file hashes intact.
MSU checked 8,683 cycles, 42 faults, eight resets and 3,216 write stalls. TC
checked 136,136 records, 169 resets and 13 rejected inputs. Integration completed
316 tiles with 75 resets and the original seed `91e10da5`.

The new candidate source snapshot matches the previously functionally verified
`target_10ns_20261112/addr_reduce` snapshot byte-for-byte across all 11 sources.
Its fresh regression completed at 17:38:08, exit code 0. All five units and
integration passed. The eight unit coverage lines and 46 integration coverage/
phase lines are identical to the fresh baseline. All 76 protected-file hashes
and all 11 live source hashes match the intended files.

Fresh synthesis, placement, routing and the existing refinement were launched
with Vivado 2022.2 after those checks:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/margin_10ns_20261113/addr_reduce/flow_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/margin_10ns_20261113/addr_reduce/src experiments/msu_fmax/margin_10ns_20261113/addr_reduce/fresh_10 10.000
```

The synthesis report has 28,016 LUTs, 21,457 fabric registers and 128 DSPs.
Unplaced WNS is -0.029 ns; this is not a routed result. The initial route reports
congestion (Route 35-447). Its completed default route has WNS -1.533 ns, TNS
-5178.146 ns, WHS +0.096 ns, and 12,874 failing setup endpoints. The worst
path is Bridge `head_select_q_reg[7]_rep` to sparse DSP `product_q_reg/CEP`,
with 10.925 ns data delay (1.696 ns logic, 9.229 ns routing).

The complete candidate flow finished at 18:43:03 with exit code 0 (flow
completion, not timing closure). Refinement has WNS -1.068 ns, TNS -3067.337 ns,
9,782 failing setup endpoints, WHS +0.096 ns, THS 0, 28,217 LUTs, 21,501 fabric
registers and 128 DSPs. All 40,815 routable nets are routed with zero errors.
DRC has only the existing DPIP-1/DPOP-1/DPOP-2/ZPS7-1 warning categories.
Its worst path is Bridge `head_select_q_reg[6]_rep` to
`g_arithmetic_row[5].g_arithmetic_column[5].product_q_reg/CEP`, with 10.460 ns
data delay (1.557 ns logic, 8.903 ns routing), seven LUT levels. It fails
10 ns and is worse than the original source at both equivalent default and
first-refinement stages. It is rejected; no further replication trials are
claimed for this candidate. Its source snapshot, RTL diff and complete logs
are retained. No production implementation run is overwritten.

The original selected source's completed physical stages provide these
comparison points, extracted from the actual native reports:

| Baseline stage | WNS ns | TNS ns | WHS ns |
| --- | ---: | ---: | ---: |
| Default route | -0.449 | -20.186 | +0.098 |
| First refinement | -0.231 | -3.720 | +0.098 |
| Six-driver replication and route | -0.207 | -13.765 | +0.096 |
| Additional refinement and route | +0.002 | 0.000 | +0.096 |

Those stage reports remain in `../target_10ns_20261112/native_evidence/`.

## Physical-only comparison

Because the RTL candidate's default result is substantially worse, one additional
physical-only refinement of the already passing baseline is also evaluated.
It uses the same original 10.000 ns clock target and the existing recipe,
does not edit RTL, and never overwrites the input checkpoint. This checks margin
improvement without changing logical behavior. This completed with WNS +0.002 ns,
TNS 0, WHS +0.096 ns and THS 0, providing no material margin improvement.
Vivado reported: `No setup violation found. The netlist was not modified.`

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/margin_10ns_20261113/baseline_extra_refine.log -source experiments/clock_control/refine_route.tcl -tclargs project_integration/project_integration.runs/impl_10ns/sparse_tensor_core_top_routed.dcp experiments/msu_fmax/margin_10ns_20261113/baseline_extra_refine 10.000
```

One bounded guardband search therefore starts from the same original baseline
DCP, temporarily optimizes at 9.750 ns, and restores the original 10.000 ns
operating constraint before applying the unchanged final setup/hold gate.
`guardband_refine.tcl` checks the input clock, records before/after reports at
both periods, and does not change RTL or add timing exceptions. Passing at the
operating period is not a claim of closure at the tighter search period.

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/margin_10ns_20261113/guardband_9p75.log -source experiments/msu_fmax/margin_10ns_20261113/guardband_refine.tcl -tclargs project_integration/project_integration.runs/impl_10ns/sparse_tensor_core_top_routed.dcp experiments/msu_fmax/margin_10ns_20261113/guardband_9p75 9.750
```

The guardband search completed at 18:34:06 with exit code 0 and the unchanged
10 ns setup/hold gate passed. Independent audit command:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/margin_10ns_20261113/guardband_audit.log -source experiments/msu_fmax/target_10ns_20261110/audit.tcl -tclargs experiments/msu_fmax/margin_10ns_20261113/guardband_9p75/timing_closed.dcp experiments/msu_fmax/margin_10ns_20261113/guardband_audit
```

## Final comparison and file scope

All entries below use the same 10.000 ns operating constraint, Vivado 2022.2,
xc7z020clg484-1 and post-route timing analysis. The guardband search's separate
9.750 ns reports remain available and are explicitly failing.

| Result | WNS ns | TNS ns | WHS ns | LUTs | Fabric registers | DSPs | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Original selected baseline | +0.002 | 0.000 | +0.096 | 29405 | 21503 | 128 | Preserved |
| MSU reduction, default | -1.533 | -5178.146 | +0.096 | 28212 | 21501 | 128 | Reject |
| MSU reduction, refined | -1.068 | -3067.337 | +0.096 | 28217 | 21501 | 128 | Reject |
| Baseline, extra 10 ns refinement | +0.002 | 0.000 | +0.096 | 29405 | 21503 | 128 | No material gain |
| Baseline, guardband search, evaluated at 10 ns | +0.016 | 0.000 | +0.096 | 29406 | 21503 | 128 | Selected |

Modified production files:

- `tools/build_10ns.tcl`
- `project_integration/scripts/post_route_10ns.tcl`

New helper and evidence are confined to this experiment directory:
`guardband_refine.tcl`, this README, source snapshots/manifests, immutable
regression logs, physical logs/checkpoints/reports, independent audit,
`selected_result.json`, `final_manifest.csv`, `production_flow.patch` and
`changed_files.txt`. The rejected RTL edit is in `addr_reduce/rtl.patch`.
The live MSU file has no final diff.

Final checks confirm all 11 live baseline sources, all 76 protected files, all
four pre-existing user files and the original native DCP are unchanged.
Git remains on `main` at `f6ee5f1973487dad8026141550131cfe41c561da`.
No new branch, worktree, commit, merge or push was created. The new flow edits
and experiment evidence remain uncommitted for review. Existing README/XPR
edits and the crash/scratch files remain exactly as found.
