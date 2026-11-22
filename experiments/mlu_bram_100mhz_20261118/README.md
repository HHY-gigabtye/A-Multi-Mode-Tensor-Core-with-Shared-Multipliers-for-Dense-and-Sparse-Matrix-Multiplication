# BRAM 100 MHz timing continuation — 2026-11-18

> Historical architecture scope: this record describes the November 19, 2026 predecessor or its experimental variants. References below to current, selected or production RTL refer to that dated snapshot. Current `main` uses operand ROUTE -> MUL -> ACC in one shared 64-multiplier core for every format, together with the DU/TIA whole-union assignment repair; its dense timing and format-change rules differ from this predecessor. See the [current TC contract](../../tensor_core_sv/README.md) and [promotion record](../../reports/verification/operand_route_main_20261122/README.md). Original measurements and validation results below are retained.

## Current acceptance status

**Accepted on 2026-11-19:** `rotating_fifo/src` passes the independently
reopened 100 MHz internal FPGA OOC gate. WNS is +0.011 ns, WHS +0.098 ns,
with 28,213 LUTs, 19,852 FFs, 18 BRAMs and 128 DSPs. All 40,406 routable
nets are routed with zero errors. Setup/hold failing endpoints and BRAM
control DRC violations are zero. See [RESULTS.md](RESULTS.md) for the selected
RTL, comparison, verification evidence, exact checkpoint hash and reproduction.
The 11 ps margin is small; this is not board-level sign-off.
The production source tree and protected reference/test files are unchanged.
The sections below retain the experiment history, including rejected and
unfinished alternatives. `ppa_progress.csv` includes completed routes only.

## Contract and provenance

Continue from the preserved `mlu_bram_20261118/banked/src` candidate. The
production sources, original BRAM experiment, all C/reference models,
vectors, seeds, assertions, and existing tests remain unchanged. No commit,
merge, or push is requested. Keep the original 10.000 ns internal FPGA OOC
constraint and all external ports, handshakes, packet order, and cycles.

The measured starting candidate has setup WNS -1.116 ns and hold WHS
+0.098 ns. Its global worst path is Bridge head selection to a TC sparse
accumulator enable; the MLU-local BRAM write-enable path also fails at
-0.411 ns. Both reports use Vivado 2022.2, xc7z020clg484-1, slow corner,
speed file -1 PRODUCTION 1.12. The original BRAM-control fan-in has
REQP-1839 asynchronous-control warnings. These are measured starting facts,
not evidence that the new revision meets timing.

## First revision: registered writes and fixed-address dual-port reads

Only `registered/src/mlu_sv/mlu.sv` changes initially. One shared 256-bit
pending-write register captures an accepted beat, slot, and bank. BRAM
writes commit one edge later. Every BRAM input control is then synchronous
or constant. The two RAM ports read the two tile slots at fixed addresses;
the committed head selects their outputs combinationally. No speculative
credit or additional externally visible packet stage is introduced.

The first output packet only uses beats accepted before the final beat.
WRITE_FIRST on each port makes the penultimate beat available on the final
load edge, including hybrid group-0 masks/data. The pending final beat is
committed before later k packets need it. Reset invalidates all logical
images immediately; stale pending writes drain before a reloaded image can
become READY. The simulation-only state view includes the actual pending
write, not an independent golden copy.

Validation order: original standalone MLU tests; supplemental cycle
comparison and inferred-primitive simulation; all original units then
integration; fresh implementation and independent reopen at 10 ns. RAM
mapping, resource usage, reset-control DRC, and timing are unverified until
their reports complete. A true-dual-port mapping may use more BRAM tiles
than the prior simple-dual-port version.

## Measured intermediate revisions

- `registered`: original MLU and supplemental RTL cycle comparison pass.
  Vivado did not infer RAM for the fixed-address words (zero BRAM). Rejected
  as a hardware mapping, regardless of behavioral equivalence.
- `fixed_tdp`: use explicit RAMB36E1 true dual ports, with separate fixed
  addresses for the two slots and WRITE_FIRST behavior. The portable RTL
  simulation branch models the same memory. Standalone synthesis confirms
  36 RAMB36E1, 2,481 LUTs and 671 FFs (MLU only, before placement).
  All five original unit tests and top integration pass. The actual
  synthesized primitive netlist also passes 16,708 immutable C records and
  17,171 cycle comparisons, including 18 directed transitions, 234
  simultaneous final-load/final-output edges, 5,347 stalls and 155 resets.
  The full design was also synthesized and placed at 10.000 ns; its route
  was later stopped for congestion, as recorded below.
- `predecode`: copy `fixed_tdp`, changing only the Bridge's combinational
  head-valid expression. Compute each slot's k/metadata eligibility before
  applying the registered one-hot head selector. The FIFO payload read and
  all sequential state updates are unchanged. This addresses four logic
  levels before head_valid on the previous measured worst path. Its
  functional and timing results must be checked independently.
- `local_acc`: copy `fixed_tdp` (without the Bridge edit), changing only TC
  sparse-accumulator data selection. An accepted idle-epoch start clears
  every accumulator; an existing sparse epoch updates only from OLD ROUTE.
  Invalid input freezes the edge through the unchanged status check.
  Direct conditions replace the dependency on next-mode/run-pipeline
  bookkeeping, without adding registers or changing the result pipeline.
  Other sparse state, control, and MAC-count diagnostics remain in the
  original state machine. Original full-state C regression is mandatory.
- `combined`: copy `local_acc` and apply the already tested Bridge
  predecode change. This combines the two independent control reductions;
  its own unit and integration regression runs before any implementation.

The explicit true-dual-port implementation uses 36 of 140 BRAM tiles,
versus 18 tiles in the previous failed implementation. Both slots can be
read at fixed addresses without asynchronous address-control fan-in. This
is an intentional resource tradeoff; timing closure is not yet established.

### Physical results available so far

- `fixed_tdp/implementation`: synthesis and placement completed. The full
  route was stopped after congestion caused a -2.009 ns intermediate WNS
  during global routing (not a completed-route result). There is no final
  routed checkpoint for this trial. The source, passed tests, synthesized
  and placed checkpoints, and router transcript are preserved.
- `predecode/implementation`: completed route at 10.000 ns. WNS -1.346 ns,
  TNS -5,113.128 ns, 12,067 failing setup endpoints; WHS +0.015 ns, THS 0.
  27,148 LUTs, 19,522 FFs, 36 RAMB36E1, 128 DSP48E1. All 41,170 routable
  nets are fully routed with zero routing errors. DRC reports 513 existing
  design warnings and no REQP-1839 warning. The worst path is FIFO payload
  bit 98 in slot 2 to sparse accumulator [5][5][28] CE: 11.057 ns data
  delay, 1.586 ns logic and 9.471 ns routing, eight LUT levels. This remains
  a failed timing candidate. An independent physical refinement is running.
- `local_acc/implementation`: synthesis yields 26,303 LUTs, 19,433 FFs,
  36 RAMB36E1 and 128 DSP48E1. Default post-physical-optimization estimated
  WNS is approximately -0.20 ns, but placement reports a 32x32 eastward
  congestion region and the router explicitly prioritizes routability.
  The default route was stopped during global routing; no final timing
  result is claimed. `local_acc/spread` reuses the exact same synthesized
  checkpoint with AltSpreadLogic_high placement, AggressiveExplore physical
  optimization and Explore routing, still at 10.000 ns.

All `fixed_tdp`, `predecode`, `local_acc`, and `combined` original unit and
integration regressions pass. `verify.ps1 -Trials fixed_tdp,predecode,local_acc,combined`
checks their frozen source hashes, all PASS markers, the 46 integration
summary lines against the immutable baseline, the primitive comparison,
the 11 original production sources and all 76 protected files.

The placement experiment follows the manufacturer's distinction between
net-delay and congestion strategies; see [Vivado 2022.2 Implementation
Guide, UG904](https://docs.amd.com/r/2022.2-English/ug904-vivado-implementation).
Directive selection is not evidence of timing closure. Only a completed
route and independent 10 ns reopen can establish the requested result.

## Why fixed_tdp preserves packet cycles

Let E be the final memory-beat acceptance edge. The module presents k=0
immediately after E, exactly as before. Data accepted at E is committed at
E+1; the previous accepted beat is committed at E with WRITE_FIRST.

| Mode | Bytes used by k=0 | First packet needing the final accepted beat |
| --- | --- | --- |
| Dense | 0..15 | k=6 (bytes 96..111) |
| Hybrid | A: 0..8; B group 0: 72..95 | k=4 (B group 1: 96..119) |
| Dual | 0..17 | k=7 (bytes 126..143, spanning the last two beats) |

Hybrid's penultimate beat is the tight case: it is committed on E, and
WRITE_FIRST exposes its new bytes on that same edge. A memory gap only
makes the earlier bytes available sooner. Downstream backpressure delays
consumption and cannot create an earlier requirement for pending bytes.
The two fixed-address ports also preserve old-head output during a
simultaneous other-slot final load. Reset invalidates both logical images;
the old pending write drains before any reloaded slot can become READY.

The netlist comparison covers original error/reject behavior as well as
legal traffic; pending writes change physical storage only for data already
accepted on the preceding edge. The logical state view includes those
accepted pending bytes without replacing any reference assertion.

## 18-BRAM active-image cache revision

`head_cache` starts from `local_acc`. Five simple-dual-port RAM banks retain
both images and continuously prefetch the non-active slot. Their read
address is driven only by a synchronous head mirror. A local FF cache
contains the active image, so only one image is read from BRAM each cycle.
The cache changes heads on the original k=7 retirement edge. Per bank, its
replacement data combines the prefetched RAM value, the most recently
committed RAM write (READ_FIRST collision bypass), the pending write, and
the current accepted beat, in chronological order. Loads into an already
active head update the cache directly. No external packet stage is added.
The logical state observation still reads actual RAM plus pending writes.

Standalone `head_cache` synthesis confirms 18 RAMB36E1, 4,129 LUTs and
2,066 FFs. Its unplaced MLU WNS is +0.700 ns, with a nine-level path from
the head register through integer last-beat/error decoding to cache CE.
All original unit/integration tests and the actual primitive-netlist
comparison pass.

`head_cache_fast` changes only those cache control terms. Retirement
requests and data source choices are evaluated independently of errors;
the unchanged status guard is applied once to the final cache enable.
Pending/committed bypass selection uses the opposite OLD head, because it
is needed only on head replacement; a direct accepted write has priority.
The last-beat test uses the exact fixed-width truth table (including false
for illegal mode 3), eliminating the integer increment/comparison chain.
Standalone synthesis gives 3,394 LUTs, 2,088 FFs, 18 RAMB36E1 and unplaced
MLU WNS +2.942 ns. All original units and integration pass, and its own
synthesized RAM netlist passes the 17,171-step comparison. These numbers
describe the MLU only, not full-system timing closure.

`head_cache_fast/flow` first requires original regression PASS markers,
then primitive equivalence. It synthesizes the full system, checks BRAM
control DRC, uses WLDrivenBlockPlacement/AggressiveExplore/Explore, and
attempts measured control-net replication and a final physical refinement
only if needed. Every physical trial gets a separate directory. A passing
candidate is independently reopened by `final_gate.tcl`; otherwise the
flow writes `INCOMPLETE.txt`, never a false PASS.

## Latest completed 36-BRAM route

`predecode/refined/routed.dcp` completes at WNS -0.875 ns, TNS -2,382.379 ns,
9,314 failing setup endpoints, WHS +0.052 ns and THS 0. Resources are
27,162 LUTs, 19,522 FFs, 36 RAMB36E1 and 128 DSP48E1. The worst path is
head_select[2] to sparse accumulator [3][7][17] CE: 10.622 ns data delay,
1.448 ns logic and 9.174 ns routing (86.368%), eight LUT levels.
`predecode/targeted` continues from this complete checkpoint, selecting
replication drivers from its own measured fanout and path reports.

The `local_acc/spread` and `combined/netdelay` routes were stopped while
still congested and incomplete. Their intermediate timing estimates are
not completed-route results. All source snapshots, passed tests, completed
synthesis/placement/physopt checkpoints and transcripts are retained.

No version in this continuation has yet been accepted as a 100 MHz result.

## Incremental implementation from the passing baseline

`incremental_flow.tcl` implements a frozen synthesized candidate using the
independently audited original `baseline/implementation/closure/routed.dcp`
as the physical reference. It runs `opt_design`, imports the reference with
`read_checkpoint -incremental`, and places/routes the candidate at the
unchanged 10.000 ns constraint. Matching cells/nets may reuse physical data;
the reference does not replace candidate logic. Reuse percentages, final
timing, utilization and DRC are recorded separately. This follows the
[Vivado 2022.2 incremental implementation flow](https://docs.amd.com/r/2022.2-English/ug908-vivado-programming-debugging/Using-Incremental-Compile).

The first trial is `fixed_tdp/incremental`. Only MLU differs from the
baseline in this candidate, so the rest of the netlist can potentially
retain the baseline's successful placement/routing. No new RTL or timing
exceptions are introduced. The flow writes a passing result only after
independent setup/hold, route, RAM configuration and DRC checks; until then
this is an experiment, not evidence of 100 MHz closure.

The default incremental attempt matched 77.52% of cells, below Vivado's
80% threshold, and silently selected the ordinary implementation flow.
That redundant run was stopped before routing. The separate
`incremental_forced_flow.tcl` / `fixed_tdp/incremental_forced` trial uses
the tool's documented `-force_incr` option to exercise actual reuse despite
that match rate. It retains the same candidate netlist, reference and
10 ns requirement.

The 64-driver replication trial completed in
`predecode/targeted/measured/replicated`: WNS -2.485 ns, WHS +0.052 ns,
41,641 fully routed nets, zero route errors. This is worse than -0.875 ns
and is rejected. The wrapper correctly chooses the earlier -0.875 ns
checkpoint as its subsequent refinement input.

Actual forced-reuse import retained 66.95% of cells and 32.59% of nets
(77.57% cell matching after two replayed physical changes). Placement and
physical optimization completed; `incremental_forced/physopt.dcp` is
preserved. Its unfinished route was stopped when three simultaneous Vivado
jobs left less than 1 GB of free physical memory. It has no final routed
result and is not included in the PPA comparison.

Run `./experiments/mlu_bram_100mhz_20261118/summarize.ps1` from the repository
root to regenerate `ppa_progress.csv`. The script reads completed-route
reports only and checks that all routable nets are routed without errors.
Its setup/hold column is a timing observation, not a substitute for the
independent BRAM configuration, control DRC and functional acceptance gates.

## Early prefetch with a final-packet cache

`early_prefetch` changes only MLU against the immutable original source
manifest. It starts from `fixed_tdp`'s untouched surrounding RTL and uses
18 inferred SDP RAMs instead of 36 fixed-address TDP RAMs. On an accepted
k=6 edge, it captures the k=7 packet and switches a synchronously reset RAM
read-address FF to the other slot. k=7 uses the saved packet, including
under backpressure. At the earliest next retirement edge, the RAM output
already contains the next head's image. Thus the output sequence retains
the original k=6, k=7, next-k=0 edges without a full-image FF cache.

The shared pending-write stage remains. READ_FIRST forwarding retains only
bytes 72..95 of the last committed beat 2: hybrid k=0 can need those bytes
on the same edge that commits them. All other packet bytes are first used
after their write/read delay has elapsed. Accepted k=6 occurs late enough
that every byte needed for the cached k=7 is already in RAM. Faults freeze
the prefetch/cache change through the original IO_OK guard. Reset prevents
any stale packet from becoming visible before a fresh k=6 capture.

Original MLU regression passes 16,708 records, 145 resets and 128 rejected
edges. All five original units and integration now pass; all 46 integration
summary lines match the immutable baseline. The actual synthesized RAM
netlist also passes all 17,171 comparisons, including 18 directed mode/slot
transitions, 234 simultaneous final-load/final-output edges, 5,347 stalls
and 155 resets. `verify.ps1 -Trials early_prefetch` confirms that only MLU
differs from the original 11 sources and that all 76 protected files remain
unchanged. `early_prefetch/mlu.patch` is the reviewable RTL diff.

Standalone synthesis reports 2,223 LUTs, 1,081 FFs, 18 RAMB36E1 and unplaced
MLU WNS +2.605 ns (not a full-system timing result). The full-system
`early_prefetch/flow` uses `default_candidate_flow.tcl`, with the same
Default placement/physical optimization/routing sequence as the original
baseline's initial implementation. It first checks the completed regression
and primitive-equivalence markers, then the synthesized BRAM control DRC.
Only a completed route followed by `final_gate.tcl` can accept 100 MHz.

The larger `head_cache_fast/flow/initial` route was stopped with a preserved
`physopt.dcp` after persistent congestion and an intermediate -1.520 ns
WNS. It has no final routed result. This releases memory for the smaller,
fully regression-tested early-prefetch candidate without discarding any
source, test, synthesis, placement or physical-optimization checkpoint.

## Metadata eligibility factoring

The second completed `predecode` refinement has WNS -0.790 ns, TNS
-2,229.769 ns, 9,144 failing setup endpoints, WHS +0.052 ns and THS 0.
It uses 27,164 LUTs, 19,522 FFs, 36 RAMB36E1 and 128 DSP48E1. Its worst
path now starts at Bridge meta_count[1] and ends at dense PE[5][4] ACC CE:
11 LUT levels and 10.501 ns data delay (8.619 ns routing).

`eligibility_factored` starts from the frozen 36-BRAM `predecode` snapshot,
changing only Bridge combinational eligibility. Boolean distribution gives
`OR(select & (k_nonzero | meta_not_full)) = OR(select & k_nonzero) |
(OR(select) & meta_not_full)`. Keep the selected nonzero-k reduction
independent of metadata, so metadata crosses only the last gate. No
register, error guard, FIFO payload read, credit calculation, handshake or
cycle boundary changes. This remains a separate candidate from the running
18-BRAM early-prefetch implementation.

`fixed_tdp_candidate_flow.tcl` uses the same Default implementation steps
and verifies exact MLU source-text equality before reusing the already
passed fixed-TDP primitive comparison. Its final independent gate requires
36 RAMB36E1 with the original TDP primitive configuration.

All five original units and top integration pass for `eligibility_factored`;
the 46 integration summary lines match the original baseline. Its MLU hash
matches the primitive-tested `fixed_tdp` source exactly. Physical timing
has not yet been measured for this Boolean factoring revision.

## Reproducing the early-prefetch candidate

Run the following from `C:/Users/Jason/Desktop/TC` in PowerShell. Use a new
trial name each time: scripts intentionally refuse to overwrite evidence.
The C models, vector files, tests and original production RTL are read-only.

```powershell
$trialName = 'early_prefetch_repro'
$taskDir = 'C:/Users/Jason/Desktop/TC/experiments/mlu_bram_100mhz_20261118'
$previousDir = 'C:/Users/Jason/Desktop/TC/experiments/mlu_bram_20261118'
$reproDir = Join-Path $taskDir $trialName
if (Test-Path -LiteralPath $reproDir) { throw 'Choose a fresh trial name' }
New-Item -ItemType Directory -Path $reproDir | Out-Null
Copy-Item -LiteralPath "$taskDir/early_prefetch/src" -Destination "$reproDir/src" -Recurse
Copy-Item -LiteralPath "$taskDir/early_prefetch/sources.csv" -Destination "$reproDir/sources.csv"
& "$taskDir/regress.ps1" -Trial $trialName -Test all
if ($LASTEXITCODE) { throw 'Regression failed' }

$vivado = 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat'
& $vivado -mode batch -nojournal -log "$reproDir/probe.log" -source "$previousDir/probe_mlu.tcl" -tclargs "$reproDir/src" "$reproDir/probe"
if ($LASTEXITCODE) { throw 'MLU synthesis failed' }
& $vivado -mode batch -nojournal -log "$reproDir/equiv_netlist.log" -source "$previousDir/equiv.tcl" -tclargs "$reproDir/src" "$reproDir/probe/mlu_netlist.v" "$reproDir/equiv_netlist"
if ($LASTEXITCODE) { throw 'Primitive comparison failed' }
& "$taskDir/verify.ps1" -Trials $trialName
& $vivado -mode batch -nojournal -log "$reproDir/flow.log" -source "$taskDir/default_candidate_flow.tcl" -tclargs "$reproDir/src" "$reproDir/flow"
```

An ordinary Vivado exit code of zero does not establish 100 MHz. A failed
timing trial writes `flow/INCOMPLETE.txt`. Acceptance requires an independent
`flow/final_audit/PASS.txt` plus the unchanged-source regression checks.
The flow measures internal FPGA OOC paths; it does not establish external
board I/O timing or perform an on-board hardware test.

## Completed early-prefetch route and physical-only follow-up

The initial early-prefetch route completed at WNS -0.568 ns and WHS
+0.082 ns: 27,470 LUTs, 19,933 FFs, 18 RAMB36E1 and 128 DSP48E1. All
40,888 routable nets are routed with zero routing errors. This improves
the best earlier BRAM timing but still fails the original 10 ns target.
The worst path is Bridge head_select[4] to dense PE[3][6] ACC CE, ten LUT
levels and 10.315 ns data delay (8.619 ns routing). This result must not
be presented as a 100 MHz pass.

The placement congestion report identifies a north window at 101% demand,
with TC accounting for 66% and MSU 29% of its cells. The read-only
`layout_probe.tcl` inventory shows most MSU primitives in X0Y1/X1Y1;
X1Y2 has only 2,484 TC and 459 MSU primitives before the trial. Its slice
extent is X50..113, Y100..149, containing 2,600 physical slice sites.
The inventory's RAM count filters the configured RAMB36E1 site subtype;
use device utilization reports, not that field, for total BRAM capacity.

`msu_floorplan_flow.tcl` reuses the exact early-prefetch synthesized DCP
and restricts the MSU hierarchy to that upper-right slice region. It changes
placement constraints only: the RTL, original 10 ns timing requirement,
ports, packets and cycles remain the already-tested early-prefetch design.
This addresses measured central congestion without modifying MSU RTL.
The separate `early_prefetch/msu_top` output retains every checkpoint and
must pass the same independent final gate before acceptance.

## Dense accumulator enable factoring

The completed early-prefetch worst path still ends at dense ACC CE after
input validation and mode/pipeline bookkeeping. `dense_acc_local` changes
only TC relative to the early-prefetch snapshot. It expresses dense ACC
storage directly from OLD state: an accepted idle epoch clears every dense
ACC; only PE[0][0] may take the initial dense product on that edge. An
existing dense epoch advances ACC only while neither result_valid nor
finish_pending was set, and only when both old aligned tokens are valid.
The original TC_OK guard freezes errors. The original state machine still
computes token movement, metadata, MAC diagnostics, result publication and
mode switching. Its final ACC fields are replaced by the equivalent local
calculation, without adding or moving registers.

All five original unit tests and top integration pass, including complete
TC state comparison. The 46 integration summary lines match the baseline;
the MLU source is byte-identical to the primitive-tested early-prefetch
version. `dense_acc_local/tensor_core.patch` records the TC diff.
`prefetch_candidate_flow.tcl` checks exact MLU source equality before reusing
that primitive comparison. It uses one synthesis thread to limit memory
demand, then the same two-thread Default implementation sequence. The
part, speed file, source order and 10 ns clock remain unchanged.
This version is not accepted until its physical reports and final gate pass.

Synthesis of `dense_acc_local` reports 26,860 LUTs, 19,894 FFs and 18 BRAMs,
but 129 DSPs: the initial PE[0][0] multiply was mapped separately from its
MAC. This is a resource-mapping discrepancy, not a regression failure.
The implementation was stopped after preserving the synthesized checkpoint;
the original 128-DSP acceptance check was not weakened.

`dense_acc_shared` keeps the direct ACC control calculation and explicitly
zeros only PE[0][0]'s DSP C operand on an idle epoch. The first product and
subsequent MAC then use the same dense_sum expression. Other PEs still
clear to zero on a new epoch and retain their direct existing-state MAC.
This is mathematically identical to selecting the initial product after the
adder, and adds no register. It requires its own original regressions and
mapping check. Future `prefetch_candidate_flow.tcl` runs stop immediately
after synthesis if DSP count is not 128, before spending time on placement.

The MSU floorplan trial completed at WNS -1.723 ns, WHS +0.095 ns,
27,455 LUTs and 19,915 FFs. It is rejected in favor of the original
early-prefetch placement at -0.568 ns. `early_prefetch/refined` applies
post-route AggressiveExplore to that better checkpoint, without a pblock.
`refine_gate.tcl` preserves its post-physopt DCP and avoids a further route
if it is already fully routed and passes setup/hold. Otherwise it routes
and performs the same independent final gate only after a passing result.

The refinement completed at WNS -0.378 ns and WHS +0.082 ns. It still
fails 100 MHz. Its worst path starts at the same Bridge head-select register
and ends at a TC result-tail CE: ten LUT levels, 10.089 ns data delay,
8.393 ns routing. The final CE driver has 128 loads and 2.091 ns net delay.
The original route and all refinement checkpoints remain available.

`dense_acc_shared` passed all five units and integration; all 46 integration
summary lines match the original baseline. Synthesis confirms 18 BRAMs and
128 DSPs, correcting the isolated initial-product mapping discrepancy.

## Grouped Bridge head mux

`grouped_mux` starts from the early-prefetch source snapshot and changes only
the Bridge's combinational payload selection. It preserves three intermediate
masked-OR groups (3 + 3 + 2 slots), followed by their OR. Each three-slot
bit fits one LUT6; the intended mapping removes one level from the measured
three-level head selector. The Boolean expression remains identical for
every select pattern. FIFO contents, pointers, credits, metadata guards,
ports and cycle boundaries are unchanged. `grouped_mux/bridge.patch` records
the complete Bridge diff. No TC source is changed in this trial.

The five original unit regressions and top integration pass; all 46 summary
lines match the baseline. Its MLU source exactly matches the primitive-tested
early-prefetch source. Physical implementation uses
`prefetch_candidate_flow.tcl` with the original device and 10 ns constraint.
This is a candidate, not a 100 MHz acceptance result.

## Direct TC update permit and routed-only refinement

`direct_guard` changes only TC relative to `early_prefetch`. Storage uses
`!in_valid || (in_ready && (!is_sparse || (valid_A && valid_B)))` directly.
For binary contract inputs this is exactly equivalent to `status == TC_OK`:
an idle input has no error; a valid input must satisfy readiness, mode match
and both sparse-vector checks. `in_ready` already includes readiness and
mode matching. The original status/error-priority calculation is unchanged.
The separate permit avoids requiring storage enables to decode the encoded
diagnostic status. No stage, state field, packet or external port changes.

The first attempt had a declaration-order compilation error; its source,
manifest and log are preserved in `direct_guard/failed_compile`. After
moving the wire declaration before its first use, all original units and
integration pass. The 46 integration summaries match baseline, and the
MLU source exactly matches its previously simulated primitive netlist.

The `dense_acc_shared` route was stopped after severe congestion (51,047
overlapping routing nodes in global iteration 1). Its synthesized and
post-physical-optimization checkpoints remain available. It has no completed
route and is not included as a measured post-route PPA result. Synthesis
reports 26,349 LUTs, 19,888 FFs, 18 BRAMs and 128 DSPs.

`refine_routed_only.tcl` continues from the best complete early-prefetch
route. Post-route AggressiveExplore preserves and reports each complete
stage without rerunning route_design. It stops after no setup improvement
or at most three stages. Any positive result still requires independent
`final_gate.tcl` acceptance; incomplete routing cannot pass.

The first routed-only refinement improved WNS to -0.317 ns. The second
stage has the same WNS and stopped the loop for no further improvement.
Worst paths now include Bridge head selection through the first dense DSP,
and sparse B-count decoding through the two routing selector banks.

`early_prefetch/four_drivers.txt` identifies four LUT drivers from the first
two measured paths, with net delays 2.357, 1.413, 2.151 and 2.299 ns.
`replicate_selected.tcl` resolves exactly those four drivers before changing
the netlist, then uses the same forced-replication operation as the original
passing FF flow. Vivado 2022.2 requires unroute first, so this is a new route
trial, not a claim that the original routes are preserved. The unchanged
best checkpoint remains available. No RTL or clock exception changes.

The grouped-mux trial was stopped with 54,064 overlapping nodes during
routing. It has no final routed result. Its post-placement WNS was -0.835 ns
and its congestion report had a 109% east window. The synthesized and
post-physical-optimization checkpoints are preserved; the latter has SHA256
`C911DAEF44DF5D7D382B5A3DC64957AACB40A15D08EE447348B2FCB22ADE7A82`.

## Rotating physical FIFO candidate

`rotating_fifo` keeps the exact early-prefetch MLU and original TC, changing
only Bridge storage representation. Its eight physical FIFO words rotate
on an accepted pop; physical word zero is therefore always the logical
head. The combinational head read only applies the empty mask. This removes
the eight-way payload mux without introducing an output register or cycle.
The incoming DU word writes physical index `old_count - tc_accept` after
rotation. Control counts, OLD occupancy credits, pointer increments, error
precedence, metadata timing and no-bypass behavior are unchanged.

All eight words rotate, including unused/stale data. The existing logical
`q.fifo` view is reconstructed from this actual storage and the logical head
pointer; it is not a separately maintained reference copy. `state_q.fifo`
is constant zero, so it adds no duplicate hardware storage. This preserves
the complete C-visible ring state, including stale slots, through reset,
rejected edges, wraparound and simultaneous push/pop.

All five original units and integration pass. Bridge compares all 2,941
state bits over 19,147 records, including 7,156 rejected edges and 13 resets.
All 46 integration summary lines match baseline. The unchanged MLU retains
its independently tested BRAM primitive comparison.

`bridge_netlist_check.tcl`, `bridge_flat.sv` and `tb_bridge_netlist.sv` add
a standalone synthesized-interface comparison against the immutable original
Bridge and C vectors. It compares every external output both before and
after each edge and checks the reference's complete state against the C
record. The original unit tests are neither modified nor replaced.
`rotating_candidate_flow.tcl` requires that additional proof to finish
before starting full implementation. Prepared scripts alone are not proof
that the netlist comparison or timing has passed.

The standalone Bridge synthesized-netlist comparison completed successfully:
19,147 records, 7,156 rejected edges, 13 resets and 38,294 pre/post-edge
interface comparisons. Evidence is `rotating_fifo/bridge_netlist/result.log`.
Standalone synthesis reports 1,657 LUTs, 2,732 FFs and no latches. The full
rotating-FIFO implementation starts only after this proof and all original
regressions have passed. Its physical result is still pending.

The direct-guard route completed at WNS -0.893 ns and WHS +0.098 ns,
26,572 LUTs, 19,917 FFs, 18 BRAMs and 128 DSPs. The four-driver route
completed at WNS -0.439 ns and WHS +0.085 ns, 27,512 LUTs, 19,933 FFs,
18 BRAMs and 128 DSPs. Neither improves the best -0.317 ns result.
`early_prefetch/four_refined` applies the routed-only refinement after
replication, following the original FF flow's physical optimization sequence.

The four-driver refinement completed at WNS -0.201 ns and WHS +0.085 ns,
27,514 LUTs and 19,933 FFs. A second complete stage has the same WNS and
stopped the refinement loop. It remains a failed 100 MHz result. The worst
path is now Bridge metadata occupancy through MSU address validation to
TC result-head CE: thirteen logic levels, including eight CARRY4 cells.
Other remaining paths include head selection to result-tail CE (-0.190 ns)
and sparse routing (-0.131 ns), as measured in the first stage's report.

## Equivalent MSU address-range predicate

`msu_addr_reduce` starts from `early_prefetch`, changing only MSU relative
to that snapshot. The C model rejects an input with capacity when its
address is unaligned or exceeds `UINT64_MAX - 255`. For any 64-bit unsigned
address, exceeding that threshold is exactly equivalent to all upper 56
bits being one and the low byte being nonzero. The RTL expresses that
reduction directly, avoiding a wide greater-than comparator. The alignment
check, capacity guard, fault behavior, storage, write ordering and tile_done
timing are unchanged. `msu_addr_reduce/msu.patch` contains the complete diff.

All original units and integration pass, including MSU's existing misaligned
addresses, aligned overflow bases, maximum address, last legal aligned base,
and ignored invalid input while full. The 46 integration summaries match
baseline; original sources and all 76 protected files remain unchanged.

`msu_incremental_flow.tcl` checks that the other ten source files exactly
match early-prefetch, synthesizes the new candidate, and requests physical
reuse of `early_prefetch/four_refined/stage1/routed.dcp`. Actual reuse must
be reported by `report_incremental_reuse`; it is not assumed. Final clock,
BRAM, DSP, route, DRC and independent acceptance checks are unchanged.

The MSU candidate's original regressions passed, but its synthesis was stopped
after `rotating_fifo` independently passed the requested 100 MHz gate.
No incremental-reuse or post-route result is claimed for the MSU alternative.
The accepted design uses the original MSU and TC sources.
