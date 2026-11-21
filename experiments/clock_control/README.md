# Clock-control optimization — 2026-11-06

> Historical experiment, superseded by the [verified 10 ns implementation](../msu_fmax/target_10ns_20261112/README.md). Older checkpoints, backups and retired 11/12 ns workflows referenced below are not distributed in this snapshot. Use the root README for current build commands. Historical local commit IDs are provenance, not necessarily public Git refs.

**Result: 12.500 ns / 80 MHz passes post-route, preserving existing cycle behavior.**
Setup WNS is **+0.004 ns (4 ps)**, hold slack **+0.096 ns**, and all
43,911 routable nets are fully routed with zero errors. This meets the chosen
target with very little setup margin; it is not board-level timing sign-off.
The achieved target increases from the previously passed 76.923 MHz by 4%.
Developed on `codex/clock-control`, based on `adc4396`.
Promoted into `C:/Users/Jason/Desktop/TC` on `main` at the user's request on
2026-11-06. The temporary worktree/branch is removed after promotion. The prior
main commit remains in Git history; the existing uncommitted Vivado project/XDC
edits are preserved. Byte-identical backups of those files and the worktree's
ignored build products are in `.local-backups/promote-clock-control-20261106/`.
No push is performed. Historical logs retain their original worktree paths;
checkpoint manifests and reproduction commands use repository-relative paths.

## Physical results and selected version

| Trial at 12.5 ns | Post-route WNS | TNS | Hold slack | Routed LUTs | Registers | DSPs |
|---|---:|---:|---:|---:|---:|---:|
| Unchanged baseline, default flow | -0.757 ns | -320.044 ns | +0.098 ns | 31,713 | 22,494 | 128 |
| Result-control candidate, same flow | -0.123 ns | -0.737 ns | +0.096 ns | 29,985 | 22,486 | 128 |
| **Candidate + post-route refinement, selected** | **+0.004 ns** | **0.000 ns** | **+0.096 ns** | **29,988** | **22,486** | **128** |

The controlled default-flow pair isolates the RTL change: setup slack improves
by 0.634 ns, and placed/routed LUTs fall by 1,728 (5.45%). It does not yet meet
12.5 ns. The selected version then reopens that candidate's completed route,
runs `phys_opt_design -directive AggressiveExplore` followed by
`route_design -directive Explore`, and gains another 0.127 ns with three added
LUTs. The selected flow reduces LUTs by 1,725 (5.44%) versus the same-target
baseline. Do not attribute the physical-refinement improvement to RTL alone.

The original baseline's worst path at 12.5 ns is Bridge FIFO count to TC
result CE (12.968 ns data delay). After the RTL change it moves to Bridge head
pointer through sparse input validation to a dense PE accumulator CE
(12.370 ns). After refinement it moves again to
`u_bridge/q_reg[meta_count][0]/C` →
`u_msu/result_q_reg[0][6][2][18]/CE`: 12.207 ns data delay, 2.230 ns logic and
9.977 ns routing (81.7%). Its final MSU enable net has fanout 2,144 and a
5.963 ns routing segment to this endpoint. MSU control is now the measured
worst path; it was not changed in this task.

The selected checkpoint is
`result_local/refined_12p5/routed.dcp`; its hash is in
`selected_checkpoint.csv`. `selected_validation/` independently reopens that
checkpoint and checks STA, DSP pipeline settings, route status and the old
Bridge-to-result path. It reproduces +0.004 ns setup / +0.096 ns hold, and the
targeted Bridge-count/metadata-to-TC-result report now has +0.215 ns margin.
All 128 DSP48E1s still have AREG/BREG/MREG/PREG=0.
`final_validation.txt` records the completed integrity
audit. Live RTL in `TC/main` is the selected candidate; the original XPR/XDC
settings remain unchanged. `result_local.patch` contains the reviewed diff.
The existing GUI project's clock constraint is still 13 ns. Reproduce the
measured 12.5 ns result with the documented CLI flow, including post-route
refinement, or inspect the selected routed checkpoint; merely opening the GUI
project does not select that checkpoint or apply its implementation strategy.

12 ns and 10 ns are **not achieved or validated** in this task. With this fixed
route, the setup-margin arithmetic suggests a 12 ns deficit of about 0.496 ns
and a 10 ns deficit of about 2.496 ns; these are estimates, not failed physical
implementation runs or proof that those targets are impossible.

## Design change

The `result_local` candidate changes only `tensor_core_sv/tensor_core.sv`.
Result-storage selection is calculated from old registered state, independently
of the step-by-step `ctrl_d` control bookkeeping. It also provides a synthesis
`max_fanout=128` hint for the two wide result write enables.

The original result slots can change only on:

1. An accepted idle-to-busy epoch: clear both slots.
2. A result pop with two queued entries: move the second entry to the head.
3. Publication of the old accumulator: write the first free result slot after pop.

The candidate expresses these cases directly. With `pop` defined from old
`result_valid && result_ready`, the post-pop count is zero exactly when the
old two-bit count equals `{1'b0,pop}`. Publication is permitted only for old
busy plus finish-pending, except when dense is waiting for an existing result.
The epoch-clear case retains highest priority; every write remains gated by
`status == TC_OK`. Invalid input therefore still rejects the entire edge,
including a simultaneous output transfer. Invalid physical slots retain their
old contents outside an epoch clear. Publication reads the old accumulator.

There are no added pipeline stages, interface/packet changes, credit changes,
or changes to result ordering, latency, reset behavior, or error priority.
The new controls are combinational. Physical register replication by Vivado
does not introduce a cycle. C models, adapters, vectors, existing tests,
assertions and seeds remain unchanged.

## Functional validation

Both `baseline` and `result_local` were tested with the original five unit
testbenches before the original integrated test, using ModelSim 2020.1:

| Test | Result, both versions |
|---|---|
| MLU | 16,708 records; 145 resets; 128 rejected edges |
| DU/TIA | 3,292 packets |
| Bridge | 19,147 rows; 7,156 rejected edges; 13 resets |
| TC | 136,136 records; 169 resets; 13 rejection cases |
| MSU | 8,683 cycles; 676 accepted results; 5,394 beats; 673 completions |
| Integration | 316 completed tiles; 3,124 issued packets; 2,563 write beats; 75 resets |

The TC test checks readiness, status, tick information, both physical result
slots and the internal-state hash against immutable C vectors. Both runs have
145 sparse II=8 observations and matching integration coverage counters.
These are dynamic regressions, not formal equivalence or gate-level simulation.
C binaries were not rebuilt; unchanged C-generated vectors were replayed.

## Measurement method

Both initial trials use Vivado 2022.2, xc7z020clg484-1, OOC synthesis, production
speed file 1.12, maxThreads=4, fresh synthesis at 12.500 ns, and default
opt/place/phys_opt/route at 12.500 ns. No incremental checkpoints are used.
Source snapshots and hashes are saved under each trial. `comparison.csv`
contains measured post-route results, distinguishing placed and routed area.
For the refinement row, `Placed_*` is the input route's resource count before
refinement; use `Routed_*` to compare the final designs.

The historical passed 13 ns route used 14 ns synthesis followed by 13 ns
physical implementation; it is context, not the controlled RTL comparison.
Only internal OOC timing is measured: the existing design does not establish
input/output delays or the board clock tree. No power or hardware Fmax claim
is made. A slack-derived frequency is not a passed frequency sweep.
The routed DRC summary has no Error/Critical Warning entries and retains 577
warnings: 320 DSP input-pipelining, 128 PREG, 128 MREG, and one OOC PS7 warning.
These existing pipeline advisories were not suppressed or resolved by changing
latency. Timing reports still identify 424 inputs and 593 outputs without
I/O delay constraints.

## Reproduction

Run from the TC repository root. Use new output directories to preserve evidence.
The simulation commands use live RTL; the physical commands use
immutable snapshots. `result_local.patch` applies the candidate to the base
commit in a separate checkout; baseline is the unmodified base commit.

```powershell
& ./tools/restore_vectors.ps1
& 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -c -l experiments/clock_control/result_local/units.log -do integration_sv/sim/run_units.do
& ./experiments/clock_control/check_regression.ps1 -Trial result_local -UnitsOnly
& 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -c -l experiments/clock_control/result_local/top.log -do integration_sv/sim/run_top.do
& ./experiments/clock_control/check_regression.ps1 -Trial result_local

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/clock_control/baseline/impl_12p5.log -source experiments/clock_control/implement.tcl -tclargs experiments/clock_control/baseline/src experiments/clock_control/baseline/impl_12p5 12.500 Default
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/clock_control/result_local/impl_12p5.log -source experiments/clock_control/implement.tcl -tclargs experiments/clock_control/result_local/src experiments/clock_control/result_local/impl_12p5 12.500 Default
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/clock_control/result_local/refined_12p5.log -source experiments/clock_control/refine_route.tcl -tclargs experiments/clock_control/result_local/impl_12p5/routed.dcp experiments/clock_control/result_local/refined_12p5 12.500
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/clock_control/selected_validation.log -source experiments/clock_control/inspect.tcl -tclargs experiments/clock_control/result_local/refined_12p5/routed.dcp experiments/clock_control/selected_validation 12.500
& ./experiments/clock_control/summarize.ps1 -Trials baseline/impl_12p5,result_local/impl_12p5,result_local/refined_12p5
& ./experiments/clock_control/verify.ps1 -SelectedTrial result_local -SelectedRun result_local/refined_12p5 -Promoted
```

## Files

- Modified functional source: `tensor_core_sv/tensor_core.sv` in `TC/main`.
- Added evidence/tooling: `experiments/clock_control/`, including snapshots,
  manifests, patch, simulator logs, physical reports and reproduction scripts.
- `files.txt` lists the retained text/source evidence; ignored checkpoints and
  temporary simulator/Vivado databases are not included in that manifest.
- Generated ModelSim libraries and Vivado checkpoints are local build products.
- Selected RTL, immutable baseline snapshots and user XPR/XDC edits are checked
  against saved hashes. The promoted verification mode allows the authorized
  RTL replacement while continuing to verify the user project settings.
