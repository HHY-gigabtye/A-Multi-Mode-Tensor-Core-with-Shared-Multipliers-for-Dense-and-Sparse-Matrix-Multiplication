# 10 ns timing experiment

Work is performed directly on `main`, as requested. Baseline commit:
`c3c9661bf69db3a2cc06f0e26ea91bcdc164235d`. No branch or worktree was created.
See [BASELINE.md](BASELINE.md) for baseline verification and source provenance.

## Final outcome

GUI follow-up on 2026-11-12: the native project flow now runs the full recipe
below. Fresh `impl_10p25_retry` completed and reopening the native run reproduced
WNS +0.043 ns / WHS +0.096 ns at 10.25 ns. This is now the active GUI run; no
archived checkpoint was imported into it. See the
historical GUI repair report (retired during cleanup); current native-project evidence is in [the 10 ns continuation](../target_10ns_20261112/README.md).
The earlier GUI limitations below describe the original experiment delivery;
the native flow repair supersedes them. Original run artifacts remain intact.

**10.000 ns remains unmet. Main retains a passing 10.250 ns (97.561 MHz)
operating point**, with setup WNS +0.043 ns, TNS 0, hold WHS +0.096 ns,
THS 0 and pulse-width slack +4.145 ns. The best 10 ns route fails setup by
0.207 ns. `validate_10p25.tcl` changes only that checkpoint's clock constraint
and applies the unchanged GUI setup/hold gate; it does not reroute or alter
RTL. Both the original failing 10 ns report and passing 10.25 ns report are
preserved. This is a slower operating-point validation, not 10 ns closure.

The strict gate passed at 22:42:23 on 2026-11-11. An independent checkpoint
reopen finished at 22:45:12 and reproduced the result, including 41,606 fully
routed nets, zero routing errors and only the existing DSP/OOC DRC warnings.
Area is 29,400 LUTs, 21,503 fabric registers and 128 DSPs (64 PREG=1, 64
PREG=0; all AREG/BREG/MREG=0). The selected checkpoint is
`main_dsp_route/operating_10p25/timing_closed.dcp`, SHA256
`804F524E55BFCDEC173267A2D202C053F7630AD111868F92E2BED6159BE19018`.
The audit is `main_dsp_route/audit_10p25/`.

The retained main RTL exactly matches `dsp_route` / `main_dsp_route/sources.csv`.
Its five original units and integration passed again at 21:53:49, with all
baseline coverage counters and protected hashes unchanged. Main's XDC now
uses 10.250 ns and waveform `{0.000 5.125}`. No pipeline cycle, interface,
packet layout, result ordering, golden vector or test was changed. The only
new commit is the requested pre-optimization snapshot `c3c9661`; optimization
changes remain uncommitted on main.

These are OOC internal post-route STA results for Vivado 2022.2 and
xc7z020clg484-1, speed file 1.12 (2019-11-22), with setup at the Slow corner.
The selected report has 424 inputs and 592 outputs without delay constraints,
and no HD.CLK_SRC assignment. It does not establish board timing, measured
hardware Fmax or power. The selected route was optimized at the stricter
10 ns implementation target; a fresh run at the operating period can produce
a different layout. Use the canonical recipe below, not the GUI's default
placement alone, to reproduce this result. Existing GUI run artifacts were
preserved and were not rerun in place.

## Reproduce current main

Use unused names on subsequent reruns. The new wrapper combines the same
component flows executed and checked separately during this experiment.
It was not rerun end-to-end after assembly. The final gate rejects negative
setup or hold slack and missing timing paths.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial target_10ns_20261110/recheck_main
& ./experiments/msu_fmax/regress.ps1 -Trial target_10ns_20261110/recheck_main
New-Item -ItemType Directory -Force build | Out-Null
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/recheck_main_10p25.log -source tools/build_10p25ns.tcl -tclargs build/recheck_main_10p25
```

The implementation recipe is: fresh 10 ns Default implementation, existing
AggressiveExplore/Explore refinement, measured six-driver replication with
Explore routing, then validation of the unchanged route at 10.25 ns.
`tools/build_11ns.tcl` additionally provides a fresh 11 ns comparison.

The GUI XPR was checked to reference the current main RTL and active XDC.
Its hook still applies the active-period setup/hold gate. The earlier root
README incorrectly said the GUI clock was 12 ns; inspection showed it was
already 11 ns before this task. The 12 ns-named init hook only sets four
threads. The 10.25 ns selected physical recipe is explicit in the new wrapper.

## Target and comparison

The target is 10.000 ns (100 MHz), Vivado 2022.2, xc7z020clg484-1, OOC.
Use the existing `experiments/msu_fmax/flow.tcl` for candidate snapshots:
fresh synthesis, default placement/physical optimization/routing, followed by
AggressiveExplore physical optimization and Explore routing. No false paths,
multicycle paths, I/O timing assumptions, or added pipeline stages are used.

The existing 11 ns routed checkpoint was independently reopened successfully:
setup +0.005 ns, hold +0.098 ns, all DSP pipeline registers disabled. See
`baseline/inspection_11/`. The tighter target needs measured implementation;
changing the clock declaration alone is not evidence of closure.

## Head decode candidate

Only `fifo_sv/du_tc_bridge.sv` changes. Eight redundant flip-flops encode the
nonempty FIFO head. On an accepted edge, each bit receives
`d.count != 0 && d.head == slot`; rejected edges hold both q and the decode,
and reset clears both. Therefore after every edge the vector is the one-hot
decode of the same registered count/head already represented in q. An OR of
the masked FIFO entries exactly preserves the old output, including zero when
empty. Payload is not registered, and a new arrival remains consumable only
after its FIFO write edge. Metadata blocking and old-state credit behavior
are preserved. No packet fields or package/state layouts change.

An older 11 ns trial tested this idea before the later MLU and arithmetic
changes, and failed timing. This trial evaluates it on the current 11 ns
baseline, which has separate dense/sparse multiplier inputs and factored
sparse accumulation. The old trial is not evidence that this candidate meets
10 ns. Source snapshots and exact patches are kept separately.

## Initial commands recorded

These historical invocations were run from the repository root. Their output
paths already contain evidence. For a rerun, use fresh trial/output names and
snapshot the intended live sources before simulation; do not overwrite these
logs or label current main simulation as a different candidate.

```powershell
& ./experiments/msu_fmax/regress.ps1 -Trial target_10ns_20261110/head_decode
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261110/baseline/flow_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/target_10ns_20261110/baseline/src experiments/msu_fmax/target_10ns_20261110/baseline/fresh_10 10.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261110/head_decode/flow_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/target_10ns_20261110/head_decode/src experiments/msu_fmax/target_10ns_20261110/head_decode/fresh_10 10.000
```

ModelSim and Vivado require approved execution outside this environment's
sandbox because their launchers fail inside it. Simulation compiles the live
main checkout; source hashes must match the corresponding snapshot before
attributing a regression to a candidate. Existing C, adapters, vectors, tests,
seeds and assertions are protected and are not edited.

## First completed 10 ns comparisons

| Candidate / phase | WNS ns | TNS ns | WHS ns | LUTs | Registers | DSPs |
|---|---:|---:|---:|---:|---:|---:|
| Baseline / default | -1.306 | -4191.386 | +0.098 | 30984 | 22546 | 128 |
| Baseline / refined | -1.000 | -1718.435 | +0.098 | 30990 | 22546 | 128 |
| Head decode / default | -1.562 | -3824.733 | +0.098 | 31018 | 22528 | 128 |
| Head decode / refined | -1.205 | -2331.411 | +0.098 | 31076 | 22528 | 128 |

These completed runs have zero routing errors; neither meets 10 ns. Head decode
alone is worse than baseline. Its critical path remains head selection through
a sparse multiplier into a fabric product register (11.152 ns data delay).
The refined baseline's worst path is MUL b_count through ROUTE selection into
delta[5][3][8], 10.947 ns data delay, including 9.499 ns routing. Both snapshots
passed all original unit/integration regressions and protected-file hashes.

## DSP product register candidate

`dsp_mul_reg` retains head decode and changes only TC product storage. The
existing MUL-stage products are captured by synchronous, non-reset data
registers. Asynchronously reset MUL valid/count metadata masks unused products
to zero in the logical `sparse_q` view. The rest of the sparse state retains its
original asynchronous reset. Capture requires reset released, TC_OK, in_valid,
and sparse mode. Thus rejects hold data, bubbles clear the logical products,
and new epochs/reset clear the view without a new pipeline cycle. Masking moves
after the data registers, allowing the synthesis tool to absorb them into DSPs.
The full C/SV state-hash, result-slot and cycle-event regression passed, followed
by integration with the exact original coverage counters. DSP mapping and PPA
must be checked from completed implementation, not inferred from RTL.

## ROUTE uniqueness candidate

`dsp_route` retains the preceding candidate and removes last-match priority
from ROUTE's coordinate selection. `valid_vector` still rejects non-increasing
or duplicate indices before any edge commits. Reset/epoch/bubbles clear MUL
state, and a committed input has unique indices in its valid prefix. Therefore
each coordinate has at most one matching stored rank in every reachable state.
The old priority mask and direct matches are equivalent under that invariant.
Error checking, whole-edge rollback and all references/tests remain unchanged.

During these initial trials, the project clock remained at the verified 11 ns
baseline while candidates were evaluated. The final 10.25 ns selection is
described above. `summarize.ps1` extracts completed routed reports;
`audit.tcl` independently reopens a checkpoint and records DSP configurations.

The ROUTE candidate passed all original regressions, source checks and exact
integration coverage comparison. Its independently reopened synthesis checkpoint
reports 64 DSPs with PREG=1 and 64 with PREG=0; AREG/BREG/MREG are all zero.
Unplaced WNS is +0.986 ns, with 29,326 LUTs, 21,460 fabric registers and 128 DSPs.
This verifies the intended register mapping, not routed timing closure.

`dsp_route_binary` restores the original Bridge byte-for-byte while retaining the
TC changes from `dsp_route`. All five units and integration passed with identical
coverage and protected-file hashes. This comparison checks whether the head
decode that failed on its own helps or hurts the combined TC changes. Its live
RTL diff contains only `tensor_core_sv/tensor_core.sv`. Its refined WNS is
-0.835 ns, so it was not selected over the combined `dsp_route` candidate.

## Completed RTL comparison and physical follow-up

All default/refined source implementations have finished. Refined results:

| Candidate | WNS ns | TNS ns | WHS ns | LUTs | Fabric registers | DSPs |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | -1.000 | -1718.435 | +0.098 | 30990 | 22546 | 128 |
| Head decode | -1.205 | -2331.411 | +0.098 | 31076 | 22528 | 128 |
| DSP product registers | -0.792 | -2034.920 | +0.098 | 29144 | 21515 | 128 |
| DSP registers + unique ROUTE | -0.231 | -3.720 | +0.098 | 29353 | 21503 | 128 |
| Same TC with original Bridge | -0.835 | -1003.311 | +0.098 | 28933 | 21520 | 128 |

All have zero routing errors. The best combined candidate still fails 10 ns.
Its worst path is head_select[6] through sparse input validation and control
logic into a DSP PREG CEP pin. The data path is 9.623 ns (1.448 ns logic,
8.175 ns routing), with 0.524 ns DSP CEP setup time. The last ten-sink enable
net contributes 2.487 ns routing. Result-control paths also fail by up to
0.071 ns. `critical_driver_paths.csv` records measured drivers from the report.

On 2026-11-11, the main sources were matched to `dsp_route/sources.csv` again.
Two physical-only trials start from the same preserved refined checkpoint:

- `replicated_controls`: three measured LUT drivers with 1633, 128 and 1032 sinks.
- `replicated_controls_cep`: the same three plus three measured ten-sink DSP
  CEP drivers with 2.4-2.7 ns routed delays on violating paths.

Both use the existing `target_11ns_20261109/replicate_drivers.tcl` with explicit
driver lists. The script validates exact LUT/output-net identities before
unrouting its in-memory copy, forcing replication, and routing with Explore.
It does not change RTL, clock constraints, pipeline stages or the source DCP.
The two driver-list files and log/output directories retain the exact trials.

The three-driver trial finished with WNS -0.428 ns, TNS -98.120 ns, and
WHS +0.096 ns; it is worse than the input checkpoint and is not selected.
The six-driver trial finished with WNS -0.207 ns, TNS -13.765 ns, WHS
+0.096 ns, 29,400 LUTs and 21,503 fabric registers. It has zero routing
errors but still fails 10 ns. Its worst path runs from Bridge metadata head
through MSU address checking (seven CARRY4 cells) into TC result-register CE.
An independent, read-only reopen completed at 21:37:30 on 2026-11-11
(`dsp_route/audit_best_10`). It confirms setup -0.207 ns and hold +0.096 ns,
41,606 fully routed nets and zero routing errors. DRC contains only the
DSP-pipeline and OOC PS7 warnings, with no Error/Critical Warning rule entries.
The 128 DSPs comprise 64 with PREG=1 and 64 with PREG=0; AREG/BREG/MREG are
zero throughout. Worst endpoint-group slacks are MSU +0.417, MLU +0.456,
Bridge +0.135, DU/TIA +0.809, TC dense -0.054, TC sparse +0.077 and TC
results/control -0.207 ns. This remains a failing 10 ns result.

## Raw-product capture enable

`capture_ok` starts from `dsp_route` and changes only the raw sparse-product
capture enable from `rst_n && TC_OK && in_valid && is_sparse` to
`rst_n && TC_OK`. A rejected edge must hold raw data because its OLD MUL
metadata may remain valid. On any non-rejected edge that commits a sparse
packet, the raw products must update, and both forms do so. Otherwise, in all
reachable states, the next MUL valid/count metadata masks those raw products
to zero: sparse bubbles clear MUL; new dense epochs clear sparse state; dense
and idle operation retain cleared MUL metadata. ROUTE still samples the OLD
masked products before the edge. Thus the extra raw captures are unobservable
in logical `sparse_q`, outputs, cycle events, or error rollback. No register
stage, port, memory layout or handshake changes.

All five original units and integration passed on 2026-11-11 at 15:48:57
(Asia/Taipei). Full TC state hashing, 136,136 records, 169 resets and 13 rejection
cases passed; original integration coverage and all protected hashes match.
This trial removes redundant valid/mode control from the measured DSP CEP
path. It may increase internal data-register switching during inactive/dense
cycles; power is not measured and no power saving is claimed.

The first `capture_ok/fresh_10` run was interrupted during routing on
2026-11-11, after saving `default/placed.dcp`. There is no final timing result
for that interrupted route. `resume_placed.tcl` reopens the preserved placed
checkpoint, checks that its clock remains 10 ns, and repeats the original
Default physical optimization and routing, followed by the same
AggressiveExplore/Explore refinement in a new `capture_ok/resumed_10` directory.
It does not modify the original checkpoint or rerun synthesis/placement.

The resumed implementation finished at 21:32:45 on 2026-11-11. Default routing
has WNS -0.819 ns, TNS -218.477 ns, WHS +0.097 ns, 28,650 LUTs and 21,525
fabric registers. Refinement has WNS -0.349 ns, TNS -12.933 ns, WHS +0.097 ns,
28,664 LUTs and 21,525 fabric registers. Both use 128 DSPs and have zero routing
errors. The relaxed raw enable reduces area but does not close 10 ns and is
not selected over `dsp_route` on timing.

## Address-comparison candidate

`capture_ok_addr` adds only the MSU address-overflow reduction to `capture_ok`.
The measured metadata-to-result-enable path contains seven CARRY4 cells.
For binary addresses, `addr > 64'hffff_ffff_ffff_ff00` is equivalent to
`(&addr[63:8]) && (|addr[7:0])`: the threshold's upper 56-bit field is maximal.
The separate alignment check, capacity condition, fault precedence and
whole-edge rejection remain unchanged. No four-state unknown-input equivalence
is claimed; the reference/interface contract supplies binary metadata. This
same algebraic transformation was explored with older RTL in the 11 ns work;
its effect with the new DSP product storage must be measured independently.

The original five unit tests and then integration passed on 2026-11-11 at
21:01:18 (Asia/Taipei), with identical baseline coverage and unchanged protected
hashes. The standalone MSU run covered 8,683 cycles, 42 faults, eight resets,
3,216 stalls and 632 full/last-row cases. The full TC run covered 136,136
records; integration completed 316 tiles with seed `91e10da5`. Live source
hashes match `capture_ok_addr/sources.csv` at validation time.

The complete 10 ns flow finished at 21:53:16 on 2026-11-11. Default routing
reports WNS -1.102 ns, TNS -3768.121 ns, WHS +0.098 ns, 28,836 LUTs and
21,528 registers. Refinement reports WNS -0.872 ns, TNS -2662.941 ns,
WHS +0.098 ns, 28,846 LUTs and 21,528 registers. Both use 128 DSPs and have
zero routing errors. The refined critical path is Bridge head select to sparse
accumulator CE, 10.619 ns data delay (9.036 ns routing). It is not selected.

## Grouped head selection

`head_groups` starts from the best completed RTL candidate, `dsp_route`,
without the later raw-capture-enable or MSU comparator changes. It changes
only the combinational Bridge head read into kept groups of at most three
data/select pairs, then ORs the three groups. Three pairs fit six LUT inputs;
the intent is two LUT levels for the eight-way one-hot read. The redundant
head register and all state updates are unchanged. The resumed `capture_ok`
default route had WNS -0.819 ns and a three-LUT head-select-to-DSP-B path,
7.199 ns data delay (6.371 ns routing). This trial isolates the head mux
structure on the stronger `dsp_route` base. Actual mapping must be checked
after implementation; kept intermediate nets do not guarantee timing closure.

The original unit-then-integration regression completed at 21:11:55 on
2026-11-11. All source/protected hashes and original coverage counters match.
ModelSim additionally emits four SVCHK notices that conflicts for generated
`always_comb` slices are checked at optimization time; simulation reports no
conflict or functional error. The six existing port-kind warnings remain.

The full flow finished at 22:27:56 on 2026-11-11. Default routing has WNS
-1.043 ns, TNS -969.010 ns, WHS +0.124 ns, 29,884 LUTs and 21,510 registers.
Refinement has WNS -0.708 ns, TNS -492.934 ns, WHS +0.124 ns, 29,889 LUTs and
21,510 registers. Both have 128 DSPs and zero routing errors. It is not selected.

## Main source selection and existing-clock validation

At 21:51 on 2026-11-11, main was matched back to the best completed RTL
candidate, `dsp_route`. The `main_dsp_route` snapshot has identical hashes for
all 11 source files. This preserves the DSP-register and ROUTE improvements
while excluding the slower raw-enable, address-comparison and kept-group
variants, all of which remain in their experiment snapshots. The active
project clock was still 11 ns at that point. The original stable source remains
in commit `c3c9661`; the final operating-point selection is described above.

The selected main source passed all five units followed by integration again
at 21:53:49 on 2026-11-11. All original coverage counters, protected hashes and
all 11 source hashes match. The fresh 11 ns flow finished at 22:22:20: default
WNS -0.660 ns, TNS -164.553 ns, WHS +0.098 ns, 29,156 LUTs and 21,471 registers;
refined WNS +0.042 ns, TNS 0, WHS +0.098 ns, 29,161 LUTs and 21,471 registers.
Both use 128 DSPs and have zero routing errors. This provides an independently
placed/routed passing 11 ns comparison; the faster selected 10.25 ns result
uses the better physical route produced by the 10 ns recipe.

## Reproduce the latest physical trials

Use a new output path for each invocation. These commands read the immutable
candidate sources, not whatever RTL is currently edited in the main checkout.
The example below reproduces the best fully audited 10 ns physical trial;
it is expected to report a 10 ns timing violation, not a passing design.

```powershell
New-Item -ItemType Directory -Force build | Out-Null
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/reproduce_dsp_route_10.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/target_10ns_20261110/dsp_route/src build/reproduce_dsp_route_10 10.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/reproduce_dsp_route_cep.log -source experiments/msu_fmax/target_11ns_20261109/replicate_drivers.tcl -tclargs build/reproduce_dsp_route_10/refined/routed.dcp build/reproduce_dsp_route_cep experiments/msu_fmax/target_10ns_20261110/dsp_route/replicate_controls_cep.txt
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/reproduce_dsp_route_audit.log -source experiments/msu_fmax/target_10ns_20261110/audit.tcl -tclargs build/reproduce_dsp_route_cep/routed.dcp build/reproduce_dsp_route_audit
```

The preserved audited DCP SHA256 is
`632B1BD3D1FF782C02C1F1279868F580AF399924781A4A1CDE78E149A1D78A66`.
To reproduce `capture_ok_addr` or `head_groups`, pass that candidate's `src`
directory to `flow.tcl`, a different fresh output directory, and `10.000`.
The functional commands were run with the live main files matching each
candidate's `sources.csv`. `functional_validation.txt`, `units.log` and
`top.log` retain the outcome; none of the reference/test files were edited.
