# FIFO head-to-DSP timing optimization, 2026-11-15

Current working RTL: restored native 100 MHz baseline on `main`.
This optimization round did not achieve a higher clock rate. All three RTL
candidates passed the original functional regression, but their completed
implementations failed setup. Two targeted replication trials also failed,
and the final 9.900 ns trial reports WNS -0.203 ns. No candidate is adopted.
All 11 live RTL/package hashes match the original audited 100 MHz sources;
all 76 protected files are intact. The final restored-baseline regression passed
at 23:04:29 (UTC+08:00), exit 0. No implementation or simulation job remains running.

## Objective and scope

Continue the requested clock optimization from the preserved baseline on
`main`, with no branch, worktree or commit. Success requires a fully routed,
independently reopened checkpoint at a period shorter than 10.000 ns, with
setup/hold checks passing and all original functional regressions intact.
A passing simulation or a completed implementation process is not that result.

Only `fifo_sv/du_tc_bridge.sv` changed in the first two candidates. The third
also changed `tensor_core_sv/tensor_core.sv`, as explained before editing.
The previous result-storage candidate remains rejected. Interfaces, packet layouts, FIFO depth, credit rules,
mode gating, invalid-edge freeze behavior and cycle latency are unchanged.

## Evidence and baseline

Commit `92c6e44bd003e27ef9b406d7e7d3a6393b13e3db`, branch `main`.
All 11 live RTL/package source hashes match the independently audited native
100 MHz build and all 76 protected reference/test/vector hashes are intact.
The tracked working tree was clean before this candidate. The preceding
restored-baseline regression completed at 18:40:43 (UTC+08:00), exit 0:
five isolated units followed by integration, with 316 completed tiles and
75 integration resets. See `../result_bank_20261115/final_live/`.

`baseline/src/` is a new immutable source copy. The selected baseline is
Vivado 2022.2, xc7z020clg484-1, FPGA OOC post-route, speed file -1 PRODUCTION
1.12, 10.000 ns: WNS +0.016 ns, WHS +0.096 ns. Its slow-corner critical path
is `u_bridge/head_select_q_reg[4]_rep/C` to
`u_tensor_core/g_arithmetic_row[3].g_arithmetic_column[7].product_q_reg/A[5]`.
Data delay is 6.178 ns, including 5.350 ns of routing through three LUT levels;
the launch net has fanout 96 and the DSP-input net fanout nine. DSP setup is
3.722 ns. These are archived measurements, not results for this candidate.

## Paired head-mux candidate

The original loop ORs eight one-hot-masked FIFO entries. The candidate exposes
four independent two-slot terms with preserved intermediate nets, followed by
a four-term OR. This targets a two-level LUT implementation of the head read.
No register is inserted. Both implementations compute exactly the same Boolean
expression from the same registered FIFO and head selector, including an all-
zero head when empty. Full FIFO state and error-priority logic remain unchanged.

The intended mapping must be checked in Vivado; the RTL shape alone is not
proof of fewer physical levels or improved Fmax. Check both the data path and
control paths after routing, and compare resources under the same constraints.

## Validation procedure

1. Preserve the baseline and exact candidate source/diff manifests.
2. Run the unchanged isolated unit suite, then integration, and verify all
   protected hashes and cycle/payload/order summaries.
3. Run a fresh 10 ns implementation and inspect actual head-mux mapping,
   resources, routing and timing. Use only new output directories.
4. Pursue a shorter period if the measurements support it. Independently
   reopen any claimed result without changing its saved clock constraints.
5. Retain only a proven production improvement; preserve failed evidence.

No timing improvement is claimed yet. Board I/O timing and power are not
measured. No golden C models, vectors, seeds or assertions are modified.

## Paired candidate regression and run

The original unit-then-integration regression completed at 20:37:30
(UTC+08:00), exit 0. All five units passed, including the Bridge replay's
19,147 rows, 7,156 rejected edges and 13 resets. Integration completed 316
tiles with 75 resets. All 10 selected unit and 46 integration summary/coverage
lines match the restored baseline in order. All 76 protected hashes passed,
and all 11 live source hashes matched `paired/sources.csv` at that validation.

The first candidate's fresh 10 ns run completed. `flow.tcl` uses the existing synthesis,
default placement/physical optimization/routing, and first-refinement phases.
It adds a synthesis check of 40 head-selector-to-sparse-DSP input timing paths
and stops before placement if their reported logic depth exceeds two. This
mapping check is not a timing pass, and a successful process exit only means
the reports were produced.

Synthesis completed with no errors or critical warnings. The mapping guard
passed: all 40 reported head-to-DSP paths have two LUT levels (the reported
worst path is LUT4 + LUT4). Synthesis resources are 30,270 LUTs, 21,485 FFs
and 128 DSPs, versus archived baseline synthesis 29,326 LUTs, 21,460 FFs and
128 DSPs. These physical register-count differences come from synthesis mapping,
not new RTL pipeline stages. Overall unplaced WNS is +0.479 ns; the sampled
head-to-DSP unplaced WNS is +2.655 ns. Neither is a routed frequency result.

`inspect_mul_boundary.tcl` separately reads the original routed baseline to
measure the existing sparse MUL-to-ROUTE data-path margin. It changes no
source, constraints or checkpoint and records results under
`baseline/mul_boundary/`; this is analysis for subsequent decisions, not an
additional RTL candidate.

The baseline boundary inspection completed at 20:47:05 (UTC+08:00), exit 0.
Across 64 sparse product DSPs and 1,024 ROUTE delta registers, the worst
MUL-to-ROUTE slack is only +0.627 ns. That path has 9.318 ns data delay
(1.054 ns logic, 8.264 ns routing), through five LUT levels. Thus simply
moving the existing multiplier output register toward its inputs cannot be
assumed to improve the complete pipeline; it would also change the timing
burden on the ROUTE stage. No such TC register change has been implemented.

The first candidate's completed default route has WNS -0.832 ns, TNS
-1093.281 ns (4,293 failing setup endpoints), WHS +0.096 ns, THS zero and
WPWS +4.020 ns. All 41,970 routable nets are fully routed with no routing
errors. Routed resources are 29,728 LUTs, 21,496 FFs and 128 DSPs.
The slow-corner worst path now ends at a sparse DSP's CEP: head selector
through input validation and clock-enable control, nine LUT levels, 10.224 ns
data delay (1.708 ns logic and 8.516 ns routing). A control LUT on that path
drives 1,635 loads. Default routing therefore does not close 10 ns despite
the shorter synthesized operand-selection tree.

The first-refinement flow completed at 21:08:13 (UTC+08:00), exit 0. It still
fails 10 ns: WNS -0.336 ns, TNS -48.157 ns, 611 failing setup endpoints,
WHS +0.096 ns, THS zero, WPWS +4.020 ns. Resources are 29,750 LUTs, 21,496
FFs and 128 DSPs. The worst path remains head selection to a sparse DSP CEP,
now eight LUT levels, 9.728 ns data delay (1.448 ns logic, 8.280 ns routing).
The 1,635-load control net remains on that path. All 41,981 routable nets are
fully routed with zero routing errors; DRC reports only the existing 513
DSP-pipelining/PS7 warnings and no errors or critical warnings.

The read-only reopened audit completed at 21:12:12 (UTC+08:00), exit 0, and
reproduced the global timing. It separately reports head-to-DSP data slack
-0.090 ns and head-to-DSP enable slack -0.336 ns. The worst data path still
has two LUT4 levels, but data delay is 6.246 ns (0.732 ns logic, 5.514 ns
routing); its last two nets each have fanout ten and route delays 1.788 ns
and 2.551 ns. Reduced logic depth alone has not produced a routed improvement.
All DSP configurations remain AREG/BREG/MREG=0, with 64 PREG=1 and 64 PREG=0.

## Operand-only paired candidate

`operand_pairs/` narrows the preserved pair terms to the 64-bit A values and
64-bit B values consumed by sparse multipliers. The rest of the entry uses
the original expression, leaving count/index/metadata logic free to optimize
with its consumers. The two 64-bit union slices are replaced by an equivalent
OR expression regardless of mode; packet layout, dense values and reserved
bits remain unchanged. This tests whether the complete-entry KEEP boundaries
unnecessarily constrained control optimization; that causal explanation is
a hypothesis, not an established timing result.

Before editing, all live source hashes were checked against `paired/sources.csv`.
Only the Bridge source was changed again, and `operand_pairs/src/` preserves
the new source. Its original unit-then-integration regression completed at
21:08:29 (UTC+08:00), exit 0. All five units and integration passed, all 76
protected hashes were intact, and all 56 selected summary/coverage lines matched
the baseline. All 11 live sources matched its tested snapshot at validation.
Its fresh 10 ns implementation used the same mapping guard and flow.
The first-candidate process read only `paired/src/`, so the working-tree edit
did not enter that implementation. At that stage, live `tensor_core.sv` still
matched the original baseline.

The operand-only synthesis mapping guard passed: all 40 reported head-to-DSP
data paths have two LUT levels. Resources are 29,451 LUTs, 21,457 FFs and
128 DSPs, compared with baseline synthesis 29,326 LUTs, 21,460 FFs and 128
DSPs. This is 819 fewer LUTs than the complete-entry paired candidate.
Overall unplaced WNS is +0.988 ns, and the reported head-to-DSP unplaced
WNS is +2.655 ns. These unplaced values do not establish an achieved clock rate.

The completed default route reports WNS -0.878 ns, TNS -405.055 ns (2,224
failing setup endpoints), WHS +0.096 ns, THS zero and WPWS +4.020 ns.
All 41,710 routable nets are fully routed with zero routing errors. Resources
are 29,258 LUTs, 21,509 FFs and 128 DSPs. Its worst slow-corner path is FIFO
payload bit 100 in slot 5 to sparse product DSP [3][6]/CEP, eight LUT levels,
10.270 ns data delay (1.448 ns logic, 8.822 ns routing). The path includes
a 1,634-load control net and a ten-load DSP-enable net with 2.540 ns route
delay. Default routing did not close 10 ns and is not a selected improvement.

The first refinement completed at 21:37:15 (UTC+08:00), exit 0: WNS -0.443 ns,
TNS -87.673 ns (638 failing endpoints), WHS +0.096 ns, THS zero, WPWS +4.020 ns.
All 41,714 routable nets are fully routed without errors. Resources are 29,262
LUTs, 21,509 FFs, 128 DSPs. The worst path is now Bridge metadata count to TC
result-register CE: 14 levels (eight CARRY4), data 10.154 ns = 2.396 ns logic
+ 7.758 ns route. This result also fails 10 ns.

`extract_drivers.ps1` reads completed routed timing reports and records LUT
drivers on paths below a selected slack threshold, retaining each observation's
actual fanout and route delay. `paired/replication_candidates.csv` is diagnostic
evidence; `paired/replicate_measured.txt` selects six exact drivers from it.
Driver names must be resolved against the exact checkpoint used for any trial;
the original baseline's six-driver list cannot be assumed valid for changed RTL.

A physical-only trial ran from `paired/fresh_10/refined/routed.dcp`,
using the existing `../target_11ns_20261109/replicate_drivers.tcl` helper and
new output `paired/replicated/`. The six drivers cover the 1,635-load validation
net, two failing DSP-enable branches, two result-enable nets and the worst
head-to-DSP operand branch. The helper validates each cell and LUT output,
unroutes the copied design, forces replication and reroutes with Explore.
The saved input and live operand-only RTL were untouched. The trial completed
at 21:38:10 (UTC+08:00), exit 0, but worsened WNS to -0.967 ns and TNS to
-974.744 ns (3,668 failing endpoints). WHS is +0.096 ns, THS zero, WPWS +4.020 ns.
All 42,020 routable nets are fully routed without errors; resources are 29,786
LUTs, 21,496 FFs, 128 DSPs. The six drivers were replicated 10/7/2/7/9/1 times
respectively. This trial is rejected, not a frequency improvement.

## Product shadow candidate

`product_shadow/` preserves the operand-only Bridge change and changes only
the TC's physical storage of sparse MUL products. Before editing, all 11 live
source hashes matched the tested operand-only snapshot. The original five
units followed by integration completed at 21:49:28 (UTC+08:00), exit 0.
At validation, all 76 protected files were unchanged, all 11 live source hashes
matched the snapshot, and all 56 selected summary/coverage lines matched baseline.
The TC replay passed 136,136 records, 169 resets and 13 rejected-input cases;
integration passed 316 completed tiles and 75 resets.

The additional standalone `tb_product_rejections.sv` passed at 21:57:15
(UTC+08:00), exit 0: 10,872 edges, 7,200 rejected inputs, longest rejected
streak 24 edges, and 72 consumed results. It instantiates the candidate and
the immutable baseline (only the baseline module name is changed in a generated
copy), compares every public output and the complete logical control/dense/
sparse/info state before and after each edge, and exercises malformed counts,
unsorted indices, forbidden mode changes, changing idle data, output stalls,
signed extremes, zero-count vectors and reset with a live MUL product.
`run_product_rejections.do` runs only these two TC instances; original tests,
C adapters, vectors, seeds and assertions remain unchanged. This supplements
the C-backed suite; it does not replace it.

Each raw 16-bit DSP product register now advances on every edge. A one-bit
registered flag records whether that edge met the original capture condition.
When the OLD flag is true, a shadow register saves the OLD raw product. The
logical MUL product selects raw data when the NEW flag is true, otherwise the
shadow. Thus a newly accepted product appears on the original edge, the first
non-capture edge saves the previous accepted product, and consecutive rejected
edges preserve it. The original asynchronously reset metadata still masks all
invalid/unused products to zero. No acceptance rule or error precedence changes.
The shadow is storage redundancy, not an additional externally visible stage.

The purpose is to remove input validation from DSP CEP paths. The tradeoff is
up to 1,024 extra shadow bits plus selection logic and potentially more switching;
power is not measured. MUL-to-ROUTE timing must be checked because the selection
mux can consume its existing margin. No clock improvement is assumed.
`check_product_shadow.tcl` requires all 64 sparse DSPs to retain PREG=1 and
constant-high CEP, in addition to the existing two-level input-mux mapping
guard. `flow.tcl` now accepts an optional synthesis guard; its three-argument
behavior used by the first two candidates is unchanged.
`audit.tcl` accepts an optional `product_shadow` variant that also checks
constant-high CEP and expects no timed head-to-DSP-enable paths. Its default
behavior for the other candidates remains unchanged.

Synthesis passed both mapping guards: 40 sampled head-to-DSP paths have at
most two LUT levels, and all 64 sparse DSP product registers have constant-high
CEP, AREG/BREG/MREG=0 and PREG=1. Total resources are 30,414 LUTs, 22,547 FFs
and 128 DSPs. Relative to operand-only synthesis this adds 963 LUTs and 1,090
FFs after mapping. Overall unplaced WNS is +0.719 ns, and the sampled
head-to-DSP slack is +2.656 ns. These are synthesis estimates, not achieved
post-route timing; completed implementation results follow below.

The product-shadow default route completed despite initial congestion: all
43,981 routable nets are fully routed without errors. Final reported WNS is
-0.242 ns, TNS -66.980 ns (888 failing endpoints), WHS +0.096 ns, THS zero,
WPWS +4.020 ns; resources are 30,388 LUTs, 22,560 FFs and 128 DSPs. This is
better than the other two candidates' default routes but still fails 10 ns.
The worst slow-corner path is head_select[4] to dense PE [6][2] accumulator CE,
seven LUT levels, 9.988 ns data delay (1.324 ns logic, 8.664 ns routing).
The head-launch net has fanout 93 and route 1.305 ns; a validation net has
fanout 504 and route 2.300 ns. Completed timing
measurements are collected in `timing_comparison.csv`; phase labels distinguish
default routing, refinement and the fully tuned native reference.

The first refinement completed at 22:25:09 (UTC+08:00), exit 0: WNS -0.103 ns,
TNS -3.100 ns (93 failing endpoints), WHS +0.096 ns, THS zero, WPWS +4.020 ns.
Resources are 30,396 LUTs, 22,560 FFs and 128 DSPs; all 43,988 routable nets
are fully routed without errors. The worst path is head_select[0]_rep to dense
PE [0][0] accumulator D, four levels including one combinational DSP48E1,
10.096 ns data delay (4.669 ns logic, 5.427 ns routing). The head launch net
has fanout 92 and route delay 1.685 ns; the DSP input net has fanout ten and
route delay 1.769 ns.

The independent reopened audit completed at 22:29:27 (UTC+08:00), exit 0.
It reproduced setup -0.103 ns and hold +0.096 ns with the saved 10.000 ns
clock unchanged. All 64 sparse DSPs still have constant-high CEP and PREG=1;
no head-to-DSP-enable paths exist, as intended. Head-to-sparse-DSP data slack
is -0.072 ns. Thus removal of the CEP bottleneck is verified, but the entire
design still does not meet 10 ns.

`replicate_head.tcl` is a separate physical-only test on that saved checkpoint.
It resolves the seven exact FDCE startpoints from the completed critical-path
report in `product_shadow/replicate_head.txt`, verifies their scope/type/Q nets,
and uses Vivado's forced replication followed by Explore routing. It preserves
the original checkpoint and clock; it makes no RTL or pipeline change.
Outputs are isolated in `product_shadow/replicated_head/`.
Vivado accepted FDCE replication and created 6/9/9/9/8/8/7 replicas for the
seven listed nets respectively. The complete route finished at 22:48:16
(UTC+08:00), exit 0, with WNS -0.361 ns, TNS -100.810 ns (942 failing endpoints),
WHS +0.096 ns, THS zero and WPWS +4.020 ns. All 44,051 routable nets are fully
routed without errors. Resources are 30,396 LUTs, 22,616 FFs and 128 DSPs.
The worst path is now Bridge metadata count to MSU result-register CE, 12 levels
(eight CARRY4), data delay 10.072 ns (2.229 ns logic, 7.843 ns route).
Head replication worsened overall setup and this result is not selected.

`product_shadow/closure_9p9/` separately started from the unreplicated refined
checkpoint and ran the existing AggressiveExplore/Explore refinement with
an actual 9.900 ns clock (about 101.010 MHz). This trial retains 9.900 ns in
its checkpoint and reports; it does not restore 10 ns. The source checkpoint
failed 10 ns by 0.103 ns, so the tighter target is an experiment, not a claimed
operating point. It completed at 22:59:15 (UTC+08:00), exit 0: WNS -0.203 ns,
TNS -29.679 ns (473 failing endpoints), WHS +0.096 ns, THS zero, WPWS +3.970 ns.
All 43,988 routable nets are fully routed without errors; resources are 30,396
LUTs, 22,560 FFs and 128 DSPs. The worst path remains head_select[0]_rep to
dense PE [0][0] accumulator D, with the same 10.096 ns data delay. This trial
did not demonstrate 101.010 MHz. Both physical trials used the same tested RTL.

## Final source disposition

Before restoration, every live source hash was checked against
`product_shadow/sources.csv`, every protected file was checked against the
original manifest, and the preserved baseline was checked against the native
100 MHz source manifest. Only the two files edited by this round were copied
back: `fifo_sv/du_tc_bridge.sv` and `tensor_core_sv/tensor_core.sv`. All 11
production source hashes then matched the audited native baseline, and the
tracked Git diff was empty. `final_live/src/` captures that restored state.
No branch, worktree, commit, merge or push was created.

The restored baseline passed all five original isolated units followed by
integration at 23:04:29 (UTC+08:00), exit 0. All 10 unit and 46 integration
summary/coverage lines match the pre-experiment baseline in order, including
316 completed integration tiles and 75 resets. `final_verification.txt` records
the final source/protected hashes, branch/HEAD, empty tracked diff and checks
of all ten comparison rows against their actual timing/resource reports.
`artifact_inventory.csv` lists the preserved experiment files and SHA256 hashes.

The candidate patches and snapshots describe attempted changes, not changes
remaining in production. In particular, `product_shadow/rtl.patch` contains
the rejected TC shadow-register change; the current main TC file does not.
The original native project, clock constraints and build hooks remain valid
for the restored baseline and were not edited by this experiment.

The measured outcome is an unsuccessful frequency-improvement attempt, not
proof of an absolute 10 ns RTL limit. Fewer mux levels and removal of a DSP
enable path were verified, but routed data/control paths elsewhere prevented
closure. No interface, latency, error-freeze contract or original test was
relaxed to obtain a passing result. Board I/O timing and power remain unmeasured.

New authored files in this experiment are `README.md`, `timing_comparison.csv`,
`flow.tcl`, `audit.tcl`, `inspect_mul_boundary.tcl`, `extract_drivers.ps1`,
`check_product_shadow.tcl`, `replicate_head.tcl`, `tb_product_rejections.sv`,
`run_product_rejections.do`, and the two measured-driver lists under `paired/`
and `product_shadow/`. Source snapshots, patches, hash manifests, regression
logs, implementation reports/checkpoints and validation summaries are generated
evidence. Existing reference models, adapters, vectors, seeds and tests were
not modified; the previous `result_bank_20261115/` experiment was left intact.

## Recorded commands

Commands recorded as executed (use new trial/output names when repeating;
the snapshot and regression helpers read live production sources):

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial head_mux_20261115/baseline
& ./experiments/msu_fmax/snapshot.ps1 -Trial head_mux_20261115/paired
& ./experiments/msu_fmax/regress.ps1 -Trial head_mux_20261115/paired
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/paired/flow_10.log -source experiments/msu_fmax/head_mux_20261115/flow.tcl -tclargs experiments/msu_fmax/head_mux_20261115/paired/src experiments/msu_fmax/head_mux_20261115/paired/fresh_10 10.000
& ./experiments/msu_fmax/snapshot.ps1 -Trial head_mux_20261115/operand_pairs
& ./experiments/msu_fmax/regress.ps1 -Trial head_mux_20261115/operand_pairs
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/operand_pairs/flow_10.log -source experiments/msu_fmax/head_mux_20261115/flow.tcl -tclargs experiments/msu_fmax/head_mux_20261115/operand_pairs/src experiments/msu_fmax/head_mux_20261115/operand_pairs/fresh_10 10.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/paired/refined_audit.log -source experiments/msu_fmax/head_mux_20261115/audit.tcl -tclargs experiments/msu_fmax/head_mux_20261115/paired/fresh_10/refined/routed.dcp experiments/msu_fmax/head_mux_20261115/paired/refined_audit 10.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/paired/replicated.log -source experiments/msu_fmax/target_11ns_20261109/replicate_drivers.tcl -tclargs experiments/msu_fmax/head_mux_20261115/paired/fresh_10/refined/routed.dcp experiments/msu_fmax/head_mux_20261115/paired/replicated experiments/msu_fmax/head_mux_20261115/paired/replicate_measured.txt
& ./experiments/msu_fmax/snapshot.ps1 -Trial head_mux_20261115/product_shadow
& ./experiments/msu_fmax/regress.ps1 -Trial head_mux_20261115/product_shadow
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/product_shadow/flow_10.log -source experiments/msu_fmax/head_mux_20261115/flow.tcl -tclargs experiments/msu_fmax/head_mux_20261115/product_shadow/src experiments/msu_fmax/head_mux_20261115/product_shadow/fresh_10 10.000 experiments/msu_fmax/head_mux_20261115/check_product_shadow.tcl
& 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -c -l experiments/msu_fmax/head_mux_20261115/product_shadow/rejection_equiv.log -do experiments/msu_fmax/head_mux_20261115/run_product_rejections.do
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/product_shadow/refined_audit.log -source experiments/msu_fmax/head_mux_20261115/audit.tcl -tclargs experiments/msu_fmax/head_mux_20261115/product_shadow/fresh_10/refined/routed.dcp experiments/msu_fmax/head_mux_20261115/product_shadow/refined_audit 10.000 product_shadow
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/product_shadow/replicated_head.log -source experiments/msu_fmax/head_mux_20261115/replicate_head.tcl -tclargs experiments/msu_fmax/head_mux_20261115/product_shadow/fresh_10/refined/routed.dcp experiments/msu_fmax/head_mux_20261115/product_shadow/replicated_head experiments/msu_fmax/head_mux_20261115/product_shadow/replicate_head.txt
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/head_mux_20261115/product_shadow/closure_9p9.log -source experiments/clock_control/refine_route.tcl -tclargs experiments/msu_fmax/head_mux_20261115/product_shadow/fresh_10/refined/routed.dcp experiments/msu_fmax/head_mux_20261115/product_shadow/closure_9p9 9.900
& ./experiments/msu_fmax/snapshot.ps1 -Trial head_mux_20261115/final_live
& ./experiments/msu_fmax/regress.ps1 -Trial head_mux_20261115/final_live
```
