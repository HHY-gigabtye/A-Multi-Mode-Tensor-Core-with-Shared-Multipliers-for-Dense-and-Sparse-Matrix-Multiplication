# Result storage timing experiment, 2026-11-15

## Artifact cleanup, 2026-11-15

At the user's request, intermediate checkpoints and compiled tool caches were
removed. This experiment retains only
`distributed_flat/fresh_10/refined/routed.dcp`. Source snapshots, patches,
constraints, scripts, regression logs, and timing reports remain available.
The selected native 100 MHz baseline outside this experiment is unchanged.

Historical commands and checkpoint paths below describe the original runs;
removed intermediates must be regenerated before replaying dependent commands.
The current `artifact_inventory.csv` lists retained files. The original README
and inventory, pre-cleanup SHA256 inventory, and exact deletion logs are in
`cleanup_20261115/`. See
[the cleanup report](cleanup_20261115/cleanup_report.md) for verification and size totals.

## Experiment outcome

Production RTL has been restored byte-for-byte to the baseline; the three
candidate implementations are retained only in this experiment's source
snapshots and patches. No candidate has demonstrated a frequency improvement.
The restored-source regression passed. The completed distributed-memory
refinement still fails setup at 10.000 ns (WNS -0.092 ns, 11 endpoints), so
the existing verified 100 MHz OOC baseline remains selected. No shorter-period
candidate run or further manual driver-replication search was performed.

Review the reverted proposal in [the candidate diff](distributed_flat/rtl.patch),
the [timing comparison](timing_comparison.csv), and the
[final verification record](final_verification.txt). The complete file list is
in [the artifact inventory](artifact_inventory.csv).

## Scope and baseline

Baseline commit: `92c6e44` on `main`. The working tree was clean before this
experiment. All 11 production RTL/package hashes match the independently
audited 2026-11-13 native build, and all 76 protected reference/test/vector
hashes match `../protected.csv`.

The verified baseline is Vivado 2022.2, xc7z020clg484-1, FPGA OOC post-route
STA at 10.000 ns: WNS +0.016 ns and WHS +0.096 ns. These are archived
measurements, not a new implementation result from this experiment. The
9.750 ns search failed by 0.234 ns. Board I/O timing and power are not measured.

The original source snapshot is in `baseline/src/`, with hashes in
`baseline/sources.csv`. The unmodified unit-then-integration regression was
rerun before any candidate was applied. ModelSim could not start in the
sandbox (Windows DLL relocation error); the same runner was relaunched with
permission outside the sandbox. It completed at 17:16:55 (UTC+08:00) with exit
code 0: all five units passed, integration completed 316 tiles with 75 resets,
and all 76 protected hashes passed. TC checked 136,136 records, 169 resets,
and 13 rejected inputs, including logical result contents and state hashes.

Following the user's preference, work continues directly on `main` with the
committed baseline and source snapshot preserved. The proposed branch creation
was not approved and no branch/worktree/commit was created.

## Candidate design

The intended production scope is only `tensor_core_sv/tensor_core.sv`.
Do not alter references, adapters, vectors, seeds, test assertions, packages,
ports, cycle latency, input acceptance, or the two-result credit limit.

The experiment investigated replacing wide result shifts with logical head/tail selectors.
The C model retains the contents of an unused second logical result slot;
the existing unit test checks this as well as the full state hash. A simple
two-bank circular FIFO cannot silently discard that behavior.

A candidate with three physical data banks can allocate a bank not referenced
by either logical selector. A publication writes that bank without depending
on `result_ready`; consume/publication only update the small selectors.
Three physical banks do not increase the two-result queue capacity. Per-bank
valid bits can preserve reset/epoch-zero behavior without resetting every
raw data bit. The tradeoff is additional storage and output selection logic.
This is an experimental proposal, not a claim of timing improvement.

## Acceptance and procedure

1. Pass the existing five isolated unit tests, then the original integration
   test. Compare coverage counters and verify all protected hashes.
2. Snapshot the candidate sources and exact diff before physical implementation.
3. Run fresh synthesis, placement, routing, and the existing refinement at
   10.000 ns using `../flow.tcl`. Compare like-for-like stages with the archived
   native baseline; inspect actual path cells, fanout, delay, and resources.
4. Only claim a higher frequency after a fully routed setup/hold/route/DRC
   check at that period. Preserve failed trials and the known-good baseline.

The baseline and the register-bank candidate passed the original
regression. The candidate completed at 17:21:13 (UTC+08:00), exit code 0, with all 76 protected
hashes intact. Ten unit summary lines and 46 integration phase/coverage lines
match the baseline exactly (`regression_comparison.txt`). The register-bank
implementation was later stopped for severe routing congestion (see below).
No performance improvement is claimed.

Vivado's launcher was denied access to its setup scripts inside the sandbox.
The exact same command was relaunched with permission outside the sandbox.
It reads only `three_bank/src/` and writes a new `three_bank/fresh_10/` tree;
the native production project and its selected checkpoint are not overwritten.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial result_bank_20261115/baseline
& ./experiments/msu_fmax/regress.ps1 -Trial result_bank_20261115/baseline
& ./experiments/msu_fmax/snapshot.ps1 -Trial result_bank_20261115/three_bank
& ./experiments/msu_fmax/regress.ps1 -Trial result_bank_20261115/three_bank
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/result_bank_20261115/three_bank/flow_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/result_bank_20261115/three_bank/src experiments/msu_fmax/result_bank_20261115/three_bank/fresh_10 10.000
```

## Logical state preservation

The head and tail selectors each reference one physical bank. They may alias
after a two-entry pop, matching the C model's retained second-slot value.
With three banks, at least one bank is unreferenced before every publication.
The lowest unreferenced bank is written using only old selectors, old
accumulator/control state, and the unchanged whole-edge acceptance guard.
The write enable has no combinational dependency on `result_ready`.

The original pop-before-publish decisions select the new logical head/tail
after the edge. A pop with two entries copies the tail selector to the head;
publication changes exactly the logical selector that C would overwrite.
Reset and a new epoch clear all bank-valid bits and reset the selectors,
masking raw data to zero. Rejected edges hold bank data, selectors and validity.
No valid result is exposed before the original publication edge, and all
original control/credit bookkeeping is unchanged. The existing C replay
checks both logical matrices even while invalid, as well as state hashes.

## Distributed-memory mapping trial

`three_bank` synthesizes to 28,199 LUTs, 23,529 registers and 128 DSPs.
The matching archived baseline synthesis has 29,326 LUTs, 21,460 registers
and 128 DSPs. The candidate's unplaced +0.682 ns setup slack is not a routed
result. Placement completed successfully, but initial routing reported
congestion and 47,322 routable nets. After 28:15 elapsed in routing, global
iteration 1 still had 1,842 overlapping nodes and reported intermediate WNS
-2.350 ns / TNS -14071.649 ns. The run was deliberately interrupted during
global iteration 2 (exit code 1) to reject the expensive routing direction.
No fully routed checkpoint or final timing result exists for this candidate;
the intermediate slack must not be reported as measured Fmax. Synthesis and
placement checkpoints and the complete partial log are preserved.

A second independent snapshot, `distributed_bank`, retains the same logical
three-bank allocation but uses an unpacked memory, a single synchronous write
port and asynchronous indexed reads, with `ram_style = "distributed"`.
This tests whether LUTRAM mapping can reduce the extra register and routing
cost. It changes only the same TC source file; all logical capacity, cycle,
reset masking and stale-slot behavior remain as above. Actual memory mapping
and routed timing must be measured. Its original regression completed at
17:41:23 (UTC+08:00), exit code 0, with all five units/integration passing and
all 76 protected hashes intact. All 56 selected unit/integration summary lines
match the baseline. Its synthesis emitted `Synth 8-7186`: the distributed-RAM
attribute was ignored on the multidimensional packed matrix elements. The
run was deliberately interrupted during synthesis, before any routed result
was produced (process exit code 1). It is a failed mapping trial, not a
timing result.

`distributed_flat` changes the memory word declaration to a single packed
`logic [$bits(tc_matrix_t)-1:0]` vector while retaining three unpacked addresses.
It passed the original regression at 17:56:43 (UTC+08:00), exit code 0, with
all 76 protected-file hashes intact. `flow_lutram.tcl` duplicates the
existing synthesis/default implementation/refinement operations and adds a
TC LUTRAM-cell check immediately after synthesis. An absent mapping causes an
error before placement/routing. This helper does not alter production flows.
The guarded fresh 10 ns run completed default routing and refinement at
19:00:11 (UTC+08:00), process exit code 0. This exit code means the flow
completed, not that timing passed. The other two trials were deliberately
stopped as described above.
The synthesis guard passed with 343 TC memory cells: 341 RAM32M and two
RAM32X1D. Final synthesis resources are 31,226 total LUTs (1,368 LUTRAM LUTs),
17,369 fabric registers and 128 DSPs. Unplaced WNS is +0.302 ns. All 56
selected regression summary/coverage lines match the baseline exactly.

## Measured implementation results

All rows below use Vivado 2022.2, xc7z020clg484-1, a 10.000 ns clock and
OOC implementation. Archived baseline default and first-refinement rows
compare corresponding flow stages; the selected baseline includes additional
targeted physical optimization and margin refinement. A synthesis or
post-place slack is not a completed routing result.

| Source / implementation stage | WNS (ns) | TNS (ns) | Failing setup endpoints | WHS (ns) |
| --- | ---: | ---: | ---: | ---: |
| Baseline, archived default route | -0.449 | -20.186 | 261 | +0.098 |
| Baseline, archived first refinement | -0.231 | -3.720 | 70 | +0.098 |
| Baseline, selected and independently audited | +0.016 | 0.000 | 0 | +0.096 |
| Distributed flat, default route | -0.800 | -317.331 | 2162 | +0.146 |
| Distributed flat, first refinement | -0.092 | -0.263 | 11 | +0.146 |

The default candidate checkpoint is fully routed: 45,048 fully routed nets,
zero routing-error nets. Its final timing report has THS 0.000 ns and WPWS
+3.750 ns. Default DRC reports 514 warnings (DSP pipeline recommendations,
one no-routable-load warning and one missing-PS7 warning); no DRC errors are
reported. There are 424 inputs and 593 outputs without I/O delay constraints,
and the OOC clock source is unset. These results do not establish board timing.

Default routed resources are 30,098 LUTs, 17,416 FFs and 128 DSPs. The selected
baseline uses 29,406 LUTs, 21,503 FFs and 128 DSPs. Reducing FF usage therefore
did not establish an area or timing win overall.

The default worst path runs from `u_bridge/head_select_q_reg[5]/C` to
`u_tensor_core/sparse_storage_q_reg[route][delta][0][2][3]/CE` at the slow
corner. Its data delay is 10.511 ns: 1.448 ns logic and 9.063 ns routing
(86.224%), through eight LUT levels. The last enable driver has fanout 1,077.
The path includes FIFO-head selection, input validation and sparse state
control. Moving result data into LUTRAM did not remove that control path.

Refinement improves the candidate substantially and is better than the
archived baseline at the first-refinement stage, but still does not close
10 ns or demonstrate a clock increase over the selected baseline.
The refined checkpoint has 45,053 fully routed nets and zero routing-error
nets, THS 0.000 ns, WPWS +3.750 ns, and the same 514 DRC warnings with no DRC
errors. It uses 30,106 LUTs, 17,416 FFs and 128 DSPs: 700 more LUTs and 4,087
fewer FFs than the selected baseline. Power was not measured.

The refined worst path moves back to FIFO head selection to a sparse DSP:
`u_bridge/head_select_q_reg[6]_rep/C` to
`u_tensor_core/g_arithmetic_row[5].g_arithmetic_column[0].product_q_reg/B[2]`.
At the slow corner, data delay is 6.472 ns (0.828 ns logic and 5.644 ns
routing, 87.206%), through three LUT levels. The launch net has fanout 108;
the final DSP-input net has fanout eight and 2.802 ns routing delay.
The DSP input setup requirement is 3.536 ns. There is no new pipeline stage.

This experiment does not prove that 100 MHz is an architectural ceiling or
that all Vivado/RTL optimizations are exhausted. It evaluates one result
storage change under the existing latency and interface contracts. The
selected baseline's own critical path is FIFO-head selection to a sparse DSP
input; the candidate's new worst path must not be confused with that baseline
measurement. Any future attempt should start from the restored baseline and
its measured paths, and retain the existing invalid-input freeze behavior.

Exact candidate reports are in `distributed_flat/fresh_10/default/` and
`distributed_flat/fresh_10/refined/`.
Baseline default/first-refinement evidence is in
`../target_10ns_20261112/native_evidence/`; selected-baseline evidence is in
`../native_margin_10ns_20261113/independent_audit/checkpoint/`.

The refined checkpoint was reopened without changing any constraint or
rerouting, and the audit completed at 19:01:48 (UTC+08:00), exit code 0.
`distributed_flat/refined_audit/` independently reproduces WNS -0.092 ns,
TNS -0.263 ns, 11 setup failures, WHS +0.146 ns and the resource counts.
All 128 DSPs retain AREG/BREG/MREG=0; 64 have PREG=1 and 64 have PREG=0.
The `groups.tsv` rows use explicit cell-name patterns: `tc_sparse` excludes
the `g_arithmetic_*` DSP instances. Use `tc_all` and `critical_paths.rpt`
for the complete TC timing result, including the failing sparse DSP inputs.

## Restored working tree

Before restoring `tensor_core_sv/tensor_core.sv`, all 11 live source hashes
were checked against the last candidate snapshot and the original snapshot
was checked against its manifest. Only that one production source was copied
back. All 11 production sources then matched `baseline/sources.csv`; the
tracked Git diff was empty. This avoids overwriting unrelated user changes.

`final_live/` records the restored production sources and the final regression.
The final unit-then-integration command completed at 18:40:43 (UTC+08:00),
exit code 0, with all 76 protected hashes unchanged. All 56 selected
summary/coverage lines match the baseline in order. These same comparisons
also pass for all three rejected candidates; see `regression_comparison.txt`
and the exact reference lines in `regression_summaries.txt`.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial result_bank_20261115/final_live
& ./experiments/msu_fmax/regress.ps1 -Trial result_bank_20261115/final_live
```

The production project, constraints, scripts, references and tests have not
been changed. No branch, worktree, commit, merge or push was created.

New files are confined to `experiments/msu_fmax/result_bank_20261115/`:
this report, `audit.tcl`, `flow_lutram.tcl`, regression comparisons, and the
`baseline`, `three_bank`, `distributed_bank`, `distributed_flat`, and
`final_live` source manifests, patches, logs and implementation reports.
Generated checkpoints and simulator databases remain local ignored artifacts.
`artifact_inventory.csv` lists eligible text/source files and ignored generated
files separately, excluding the inventory itself. Final verification found
all 55 snapshot source files intact, all 11 production sources identical to
the selected native build, all 76 protected hashes unchanged, and no tracked
working-tree diff. The production XPR still references the normal live
`tensor_core_sv/tensor_core.sv` path.

## Additional recorded commands

These blocks record the commands as executed. Snapshot helpers read the live
working tree and refuse to overwrite an existing snapshot; the regression
runner also reads live sources, which now contain the baseline. To repeat
candidate implementation, reuse its preserved `src/` directory and choose a
new output directory and log name instead of recreating the snapshot.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial result_bank_20261115/distributed_bank
& ./experiments/msu_fmax/regress.ps1 -Trial result_bank_20261115/distributed_bank
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/result_bank_20261115/distributed_bank/flow_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/result_bank_20261115/distributed_bank/src experiments/msu_fmax/result_bank_20261115/distributed_bank/fresh_10 10.000
& ./experiments/msu_fmax/snapshot.ps1 -Trial result_bank_20261115/distributed_flat
& ./experiments/msu_fmax/regress.ps1 -Trial result_bank_20261115/distributed_flat
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/result_bank_20261115/distributed_flat/flow_10.log -source experiments/msu_fmax/result_bank_20261115/flow_lutram.tcl -tclargs experiments/msu_fmax/result_bank_20261115/distributed_flat/src experiments/msu_fmax/result_bank_20261115/distributed_flat/fresh_10 10.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/result_bank_20261115/distributed_flat/refined_audit.log -source experiments/msu_fmax/result_bank_20261115/audit.tcl -tclargs experiments/msu_fmax/result_bank_20261115/distributed_flat/fresh_10/refined/routed.dcp experiments/msu_fmax/result_bank_20261115/distributed_flat/refined_audit 10.000
```
