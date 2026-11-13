# Verified 83.333 MHz implementation — 2026-11-08

> Historical experiment, superseded by the [verified 10 ns implementation](target_10ns_20261112/README.md). Older checkpoints, backups and retired 11/12 ns workflows referenced below are not distributed in this snapshot. Use the root README for current build commands. Historical local commit IDs are provenance, not necessarily public Git refs.

**Selected: original RTL, fresh 12.000 ns synthesis and implementation, followed
by post-route refinement.** The design passes 83.333 MHz with setup WNS
**+0.005 ns**, TNS zero, hold WHS **+0.098 ns**, and zero routing errors.
The verified target rises from 80.000 MHz to 83.333 MHz (**+4.17%**).
This is an implementation-flow improvement; the experimental RTL changes are
not adopted. There is only 5 ps setup margin, so this is not board-level sign-off.

The selected routed checkpoint is `baseline/fresh_12/refined/routed.dcp`.
`selected_checkpoint.csv` records its SHA256. `selected_inspection/` independently
reopens that checkpoint with its original constraints and reproduces the result.
All 43,981 routable nets are fully routed; all 128 DSP48E1s retain
AREG/BREG/MREG/PREG=0. `final_validation.txt` records source/reference integrity.

Active repository: `C:/Users/Jason/Desktop/TC`, branch `main`.
At the user's request, the selected 12 ns version is consolidated into the
primary checkout; the temporary linked worktree is removed. The RTL remains
byte-for-byte equal to the tested `4d277fb` baseline. The GUI project now uses
12 ns, fresh OOC synthesis, and the documented post-route refinement.
Use `tools/build_12ns.tcl` for the canonical fresh implementation, or
`tools/open_12ns_checkpoint.tcl` to inspect the preserved measured result.
See `reports/implementation/main_12ns/README.md` for the active entry points.

The experimental candidates remain historical evidence and are not adopted.
Historical logs retain their original worktree paths; `selected_checkpoint.csv`
records the current path and unchanged checkpoint SHA256. Original local edits
and unique worktree build products are backed up under
`.local-backups/consolidate-main-12ns-20261108/`. The original project hash record
is retained; `current_project.csv` records the promoted project settings.

## Selected result and controlled 12 ns comparison

The two fresh-12-ns revisions use the same 12 ns synthesis, part, constraints,
default implementation and identical refinement. Both versions passed the same
functional regression before implementation.

| Revision / flow | Clock ns | WNS ns | TNS ns | WHS ns | Routed LUTs | Registers | DSPs |
|---|---:|---:|---:|---:|---:|---:|---:|
| Original RTL / prior refined baseline | 12.5 | 0.004 | 0.000 | 0.096 | 29,988 | 22,486 | 128 |
| Original RTL / fresh default | 12.0 | -0.213 | -5.201 | 0.098 | 30,139 | 22,529 | 128 |
| **Original RTL / fresh refined, selected** | **12.0** | **0.005** | **0.000** | **0.098** | **30,149** | **22,529** | **128** |
| MSU local CE + TC CE32 / fresh default | 12.0 | -0.586 | -261.079 | 0.098 | 30,176 | 22,526 | 128 |
| MSU local CE + TC CE32 / fresh refined | 12.0 | -0.060 | -0.294 | 0.096 | 30,193 | 22,526 | 128 |

Fresh 12 ns synthesis followed by default implementation does not pass timing:
the selected original-RTL result requires the documented post-route refinement,
which improves WNS by 0.218 ns. Relative to the previous 80 MHz implementation,
the selected result uses 161 more routed LUTs (+0.54%), 43 more mapped registers
(+0.19%), and the same DSP count. There is no new RTL pipeline stage.

The MSU-only trial synthesized at 12.5 ns and reimplemented at 12 ns also fails:
WNS -0.600 ns by default and -0.108 ns after refinement. It is a different flow
and is not evidence against fresh 12 ns synthesis. All completed runs and their
phase-specific metrics are retained in `comparison.csv`.

## Remaining bottleneck in the selected route

`u_bridge/q_reg[count][2]/C` → sparse input validation / TC result control →
`u_tensor_core/ctrl_q_reg[result][3][1][14]/CE` is now the worst setup path.
It has 9 LUT levels, 11.706 ns data delay, 1.710 ns logic and 9.996 ns routing
(85.393%). The final enable net has 128 sinks and a 2.058 ns route segment to
the worst endpoint. The source FIFO-count decode also drives a 192-load net.

The independent inspection finds +0.203 ns worst MSU margin, +0.085 ns dense
state margin, +0.007 ns sparse state margin, and +0.005 ns TC-result margin.
MSU enable fanout is still 2,144 in this selected, unchanged RTL; placement and
routing under the new synthesis constraint relieve its earlier worst-path role.
The TC result control and sparse datapath remain very close to the new limit.

## Problem and change

The baseline post-route bottleneck is Bridge metadata count through MSU address
validation to the result-buffer clock enable: 12.207 ns data delay, including
9.977 ns routing. The final enable has 2,144 loads and a 5.963 ns segment to the
worst endpoint. The previously selected 12.5 ns route has only 0.004 ns slack.

Trial `local_ce` changes only `msu_sv/rtl/msu.sv`. Each of the two physical slots
has an explicit static write enable and a separate sequential storage block.
The enable has a `max_fanout=128` mapping hint so synthesis can replicate its
driver. This is a combinational control change, with no new pipeline stage.

The original storage assignment executes only for `status == IO_OK && push`.
Since `push = result_valid && result_ready` and ready already requires reset
released, capacity, and `status == IO_OK`, that extra outer status test is
redundant for an accepted transfer. Slot `b` writes exactly when `push` and
old `tail == b`. Both slots retain asynchronous reset and otherwise hold their
contents. The old head/count logic, address validation, output selection,
whole-edge fault rejection, event updates, and last-beat completion are unchanged.

This mapping hint must be judged by measured netlist/fanout and routed timing;
its presence in RTL alone is not proof of physical improvement.

The independent `local_ce/inspection_12p5` re-open confirms that the 4,288 MSU
result-plus-metadata enable loads are served by 34 nets: 32 with 127 sink pins
and two with 112. The worst MSU setup margin is now +0.364 ns, versus +0.004 ns
in the baseline route. The global worst path has moved to TC result CE through
sparse input validation, with +0.042 ns; sparse DSP data is close at +0.056 ns.

Trial `tc_ce32` additionally changes only the two existing TC result write-enable
mapping hints from 128 to 32. Boolean logic, storage, and interfaces are identical.
It is a separate trial. It also passed all five original unit
tests and the integrated test with the same coverage counters. It is **not
selected** because its fresh 12 ns refined route fails by 0.060 ns while the
original RTL passes. Its source snapshot, patch and reports remain available.

## Completed 12.5 ns comparison

| Version / flow | WNS ns | TNS ns | WHS ns | Routed LUTs | Registers | DSPs |
|---|---:|---:|---:|---:|---:|---:|
| Baseline / default | -0.123 | -0.737 | 0.096 | 29,985 | 22,486 | 128 |
| Baseline / refined | 0.004 | 0.000 | 0.096 | 29,988 | 22,486 | 128 |
| MSU local CE / default | -0.368 | -31.318 | 0.098 | 30,056 | 22,523 | 128 |
| MSU local CE / refined | 0.042 | 0.000 | 0.098 | 30,058 | 22,523 | 128 |

The baseline exactly reproduces the prior selected result. The candidate improves
final refined slack by 0.038 ns, adding 70 LUTs and 37 mapped registers. It makes
default-flow slack worse; improvement is established only with the documented
refinement. These results alone do not establish a materially higher tested target.

## Functional validation

Baseline, `local_ce`, and `tc_ce32` each ran the original five independent unit
testbenches before the original integrated test, using ModelSim 2020.1. All passed:

| Test | All three source revisions |
|---|---|
| MLU | 16,708 records; 145 resets; 128 rejected edges |
| DU/TIA | 3,292 packets |
| Bridge | 19,147 C-equivalent rows; 7,156 rejected edges; 13 resets |
| TC | 136,136 C/SV records; 169 resets; 13 rejection cases |
| MSU | 8,683 cycles; 676 results; 5,394 beats; 673 completions; 42 faults; 8 resets |
| Integration | 316 completed tiles; 3,124 issued packets; 2,563 write beats; 75 resets |

Integration coverage counters match exactly, including 145 sparse II=8
observations. MSU includes 34 simultaneous result-accept/tile-complete edges,
3,216 stalls, 632 full-buffer last-beat cases and 335 wraps.
`protected.csv` hashes immutable C models, adapters, testbenches, test scripts,
and vectors. The existing C-generated vectors were replayed; C binaries were
not rebuilt. These are dynamic regressions, not formal equivalence or GLS.

## Physical method

All runs use immutable source snapshots in each trial's `src/`, with `sources.csv`
SHA256 manifests. The initial 12.5 ns comparison uses Vivado 2022.2,
`xc7z020clg484-1`, OOC synthesis at 12.500 ns, maxThreads=4, default
opt/place/phys_opt/route, followed by the same post-route
`phys_opt_design -directive AggressiveExplore` and `route_design -directive Explore`.
The `default/` and `refined/` reports keep RTL and physical-refinement effects
distinguishable. No incremental synthesis or implementation checkpoint is used.

Any tighter-target `retarget.tcl` runs reuse the trial's 12.5 ns **synthesized,
unplaced** checkpoint and perform new opt/place/phys_opt/route plus refinement.
Such runs are explicitly separate from fresh synthesis at the tighter target.

The `baseline/fresh_12` and `tc_ce32/fresh_12` pair instead uses **12 ns
for both fresh synthesis and all implementation steps**, with the same flow,
part, tool version and thread limit. These are the main higher-frequency
comparison. `tc_ce32/flow_12.log` was interrupted before completion when switching
to this direct-12-ns flow; its partial outputs are not a measured physical result.

Measured results are recorded in `comparison.csv`. Slack-derived MHz is an estimate,
not a frequency sweep or hardware measurement. Power is not measured.
STA uses production speed file 1.12, with slow and fast corners enabled; the worst
setup paths are at the Slow corner. These are FPGA reports, not ASIC library PPA.
There are 424 inputs and 592 outputs without I/O delays, and HD.CLK_SRC is unset;
the OOC flow does not establish the board clock tree. The final routed DRC has
no Error/Critical Warning entries, but retains 577 existing warnings: 320 DSP
input-pipeline, 128 PREG, 128 MREG and one OOC PS7 warning. No hardware frequency
sweep, board timing sign-off, or power measurement was performed. The 83.368 MHz
slack-derived estimate is not an additional validated operating target.

## Reproduction

Run from the repository root. Use new trial/output/log names when rerunning to
preserve evidence. `snapshot.ps1` captures live RTL; simulation uses live RTL;
implementation reads only the named immutable snapshot.

```powershell
& ./tools/restore_vectors.ps1
& ./experiments/msu_fmax/snapshot.ps1 -Trial baseline
& ./experiments/msu_fmax/regress.ps1 -Trial baseline
# After applying the candidate patch:
& ./experiments/msu_fmax/snapshot.ps1 -Trial local_ce
& ./experiments/msu_fmax/regress.ps1 -Trial local_ce

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/baseline/flow_12p5.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/baseline/src experiments/msu_fmax/baseline/impl_12p5 12.500
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/local_ce/flow_12p5.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/local_ce/src experiments/msu_fmax/local_ce/impl_12p5 12.500
# Controlled pair with 12 ns used in synthesis AND implementation:
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/baseline/fresh_12.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/baseline/src experiments/msu_fmax/baseline/fresh_12 12.000
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/tc_ce32/fresh_12.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/tc_ce32/src experiments/msu_fmax/tc_ce32/fresh_12 12.000
& ./experiments/msu_fmax/summarize.ps1
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/selected_inspection.log -source experiments/msu_fmax/inspect.tcl -tclargs experiments/msu_fmax/baseline/fresh_12/refined/routed.dcp experiments/msu_fmax/selected_inspection
& ./experiments/msu_fmax/verify.ps1 -Trial baseline -Run baseline/fresh_12/refined
```

For a fresh reproduction of the selected physical result without overwriting the
evidence, use a new output directory, for example:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/reproduce_12.log -source experiments/msu_fmax/flow.tcl -tclargs experiments/msu_fmax/baseline/src experiments/msu_fmax/reproduce_12 12.000
```

To inspect the selected result in a separate Vivado session, open this checkpoint
from its Tcl console:

```tcl
open_checkpoint {C:/Users/Jason/Desktop/TC/experiments/msu_fmax/baseline/fresh_12/refined/routed.dcp}
```

`local_ce/rtl.patch` records the functional diff. New scripts, source snapshots,
simulation logs and implementation evidence are confined to `experiments/msu_fmax/`.
Ignored checkpoints and simulator work libraries are build products.
`original_project.csv` records the original main checkout's XPR/XDC hashes.
`files.txt` lists the new source/text evidence. The final functional RTL diff is
empty; experimental diffs remain in `local_ce/rtl.patch` and `tc_ce32/rtl.patch`.
`physical_help*.log` and `replicate_route.tcl` record a possible targeted-replication
follow-up; that extra flow was not run or required for the selected passing result.
