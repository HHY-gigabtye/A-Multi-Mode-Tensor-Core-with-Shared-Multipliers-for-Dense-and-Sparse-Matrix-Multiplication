# 10 ns continuation, 2026-11-12

> Historical architecture scope: this record describes the November 12, 2026 predecessor or its experimental variants. References below to current, selected or production RTL refer to that dated snapshot. Current `main` uses operand ROUTE -> MUL -> ACC in one shared 64-multiplier core for every format, together with the DU/TIA whole-union assignment repair; its dense timing and format-change rules differ from this predecessor. See the [current TC contract](../../../tensor_core_sv/README.md) and [promotion record](../../../reports/verification/operand_route_main_20261122/README.md). Original measurements and validation results below are retained.

The user requested a 10.000 ns target, a commit of the current version if it
was not already committed, and no new worktree. Work remains on `main`.

## Verified 10 ns result

The additional physical pass completed at 18:05:59 (Asia/Taipei), with setup
WNS +0.002 ns, TNS 0, hold WHS +0.096 ns, THS 0 and pulse-width slack
+4.020 ns. All 41,611 routable nets are fully routed, with zero routing errors.
Utilization is 29,405 LUTs, 21,503 fabric registers and 128 DSP48E1s. This is
five more LUTs than the prior 10.25 ns route, with unchanged registers and DSPs.

`validated_10ns/` independently reopens `postroute_1/routed.dcp` and applies
the existing final gate without modifying its clock or routing. It completed
at 18:08:15 and reproduced setup +0.002 ns and hold +0.096 ns.

The final critical path starts at Bridge `head_select_q_reg[3]_rep__0` and
ends at TC `g_arithmetic_row[3].g_arithmetic_column[2].product_q_reg/B[15]`.
Its data delay is 6.378 ns (0.828 ns logic, 5.550 ns routing), through LUT4,
LUT5 and LUT6 at the Slow corner. This replaces the earlier worst
metadata-to-result-enable path after physical optimization.

These results are internal FPGA OOC STA, not board measurements. The design
still has 424 inputs and 592 outputs without delay constraints, and no
HD.CLK_SRC assignment. The approximately 2 ps setup margin is small. Power is not measured.
The DRC report retains only the DSP-pipeline and OOC PS7 warning categories.

## Starting point

Initial HEAD was `c3c9661bf69db3a2cc06f0e26ea91bcdc164235d` (11 ns snapshot).
The working tree already contained the selected 10.25 ns RTL and native GUI
flow, which were not committed. The 11 active source hashes match
`../target_10ns_20261110/main_dsp_route/sources.csv` exactly.

The existing native `impl_10p25_retry` result has setup WNS +0.043 ns and
hold WHS +0.096 ns at 10.250 ns. At 10.000 ns its unchanged physical route
has setup WNS -0.207 ns. These are Vivado 2022.2 FPGA OOC post-route results
for xc7z020clg484-1, speed file 1.12, Slow setup corner.

The worst 10 ns path starts at `u_bridge/q_reg[meta_head][0]` and ends at
`u_tensor_core/ctrl_q_reg[result][3][3][10]/CE`. Data delay is 9.918 ns:
2.416 ns logic and 7.502 ns routing, with seven CARRY4 cells and six LUTs.
The source net has fanout 131; the final enable net has fanout 128. See
`../target_10ns_20261110/dsp_route/audit_best_10/critical_paths.rpt`.

## Baseline reproduction

The following commands were invoked from the repository root:

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial target_10ns_20261112/baseline
& ./experiments/msu_fmax/regress.ps1 -Trial target_10ns_20261112/baseline
git -c core.whitespace=cr-at-eol diff --check
```

The existing runner executes all five isolated units before integration, then
checks the protected-file hashes. The snapshot records all active RTL and
package files. Existing C models, vectors, assertions and seeds are unchanged.

The fresh run completed at 16:55:58 (Asia/Taipei): all five units and integration
passed. TC checked 136,136 records, 169 resets and 13 rejected inputs. Integration
completed 316 tiles with 75 resets and seed `91e10da5`. All protected hashes
match. See `baseline/units.log` and `baseline/top.log` for exact coverage.

## Optimization scope

Start with physical optimization of the measured paths, keeping RTL and cycle
behavior unchanged. Use fresh output directories and preserve every input
checkpoint. Only promote a result after setup, hold, routing, source provenance
and independent checkpoint reopening have been checked at exactly 10.000 ns.
No clock relaxation or timing exceptions count as reaching the target.

The baseline commit includes the preceding RTL, flow scripts and text evidence.
The existing Vivado crash ZIP and empty scratch text file are left untouched
and untracked. Generated binary checkpoints remain local under the existing
ignore policy; scripts and manifests preserve reproducibility and provenance.

Baseline commit: `9b99f65` (`Snapshot verified 10.25 ns main before 100 MHz closure`).

## Trials

`postroute_1` applies one additional existing AggressiveExplore / Explore pass
to the previously best 10 ns route. Its input checkpoint is immutable and its
RTL corresponds to the baseline snapshot, not the separate address trial.

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261112/postroute_1.log -source experiments/clock_control/refine_route.tcl -tclargs experiments/msu_fmax/target_10ns_20261110/dsp_route/replicated_controls_cep/routed.dcp experiments/msu_fmax/target_10ns_20261112/postroute_1 10.000
```

`addr_reduce` changes only the MSU overflow comparator relative to the baseline.
For binary inputs, `addr > 64'hffff_ffff_ffff_ff00` is equivalent to
`(&addr[63:8]) && (|addr[7:0])`. The alignment check, capacity gating, fault
precedence and whole-edge rejection remain unchanged. No four-state unknown
input equivalence is claimed. The immutable MSU vectors already cover every
misaligned low-five-bit value, the seven aligned overflowing bases, the last
legal base and rejection during a simultaneous write/final beat.

```powershell
& ./experiments/msu_fmax/snapshot.ps1 -Trial target_10ns_20261112/addr_reduce
& ./experiments/msu_fmax/regress.ps1 -Trial target_10ns_20261112/addr_reduce
```

The address trial passed all five units and integration at 18:06:17, with the
same coverage and protected hashes. It was not synthesized or selected because
the unchanged baseline RTL already reached 10 ns through physical optimization.
The trial source and logs are preserved; the live MSU was restored byte-for-byte
to the baseline and all 11 live source hashes were rechecked.

## Production flow

The selected recipe is fresh 10 ns synthesis/placement/default route, the
previous AggressiveExplore/Explore refinement, six-driver replication and
Explore route, then one additional AggressiveExplore/Explore pass. The final
clock remains 10.000 ns throughout. No timing exceptions, retiming request,
pipeline changes or relaxed final gate are introduced.

- `tools/build_10ns.tcl`: standalone fresh-source recipe.
- `project_integration/scripts/post_route_10ns.tcl`: same recipe as a native
  post-route hook, using only checkpoints from that new run.
- `tools/run_10ns_project.tcl`: creates fresh native runs, checks persisted
  settings, executes synthesis/implementation and reopens the completed run.
- `validate_10ns.tcl`: checks the original checkpoint clock and applies the
  unchanged production setup/hold gate.
- `audit_project.tcl`: independently checks native run properties and reopens
  its routed checkpoint for timing, routing, utilization and DSP reports.

Actual invocations:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261112/validate_10ns.log -source experiments/msu_fmax/target_10ns_20261112/validate_10ns.tcl -tclargs experiments/msu_fmax/target_10ns_20261112/postroute_1/routed.dcp experiments/msu_fmax/target_10ns_20261112/validated_10ns
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261112/native_project.log -source tools/run_10ns_project.tcl -tclargs experiments/msu_fmax/target_10ns_20261112/native_project 10ns
```

Use a new output directory and unused run suffix for later repetitions. Earlier
native runs and historical scripts are retained. The standalone wrapper uses
the same component flows; its full fresh-source execution is not separately
rerun when the native recipe supplies the end-to-end reproduction.

## Fresh native reproduction

`synth_10ns` completed with synthesis checksum `a8dd2d53`, matching the prior
verified source implementation. The new native `impl_10ns` completed normally
at 19:24:19, and the parent reopened it and returned exit code 0 at 19:24:53.
`native_project/result.txt` records `route_design Complete!`, 10.000 ns,
setup +0.002 ns and hold +0.096 ns. No archived implementation checkpoint
was imported into this run. It is the active project implementation.

| Fresh native stage | Period ns | WNS ns | TNS ns | WHS ns |
| --- | ---: | ---: | ---: | ---: |
| Default route | 10.000 | -0.449 | -20.186 | +0.098 |
| First refinement | 10.000 | -0.231 | -3.720 | +0.098 |
| Six-driver replication and route | 10.000 | -0.207 | -13.765 | +0.096 |
| Additional refinement and route | 10.000 | +0.002 | 0.000 | +0.096 |

All six named control drivers resolved successfully in the fresh run. The
native recipe directory is
`project_integration/project_integration.runs/impl_10ns/recipe_10ns_20261112_183025/`.
Selected text evidence is copied into `native_evidence/` because generated
Vivado run directories and binary checkpoints are ignored by Git.

Independent native audit invocation:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/target_10ns_20261112/native_audit.log -source experiments/msu_fmax/target_10ns_20261112/audit_project.tcl -tclargs experiments/msu_fmax/target_10ns_20261112/native_audit
```

The independent audit completed at 19:32:45 with exit code 0. It confirms
`NEEDS_REFRESH=0`, `STATUS=route_design Complete!`, GUI `STATS.WNS=0.001660`,
`STATS.WHS=0.095518`, TNS/THS zero, and zero failed nets. The rounded timing
reports reproduce setup +0.002 ns, hold +0.096 ns and pulse width +4.020 ns.
The exact GUI setup margin is 1.660 ps. All 41,611 routable nets are routed.
DRC has no Error or Critical Warning rules, only DPIP-1/DPOP-1/DPOP-2/ZPS7-1.
DSP configuration remains 64 with PREG=1 and 64 with PREG=0; all have
AREG/BREG/MREG=0. The original clocks and constraints were preserved.

Worst endpoint-group slacks in ns are MSU +0.417, MLU +0.456, Bridge +0.123,
DU/TIA +0.809, TC dense +0.062, TC sparse +0.077 and TC results +0.011.
See [native audit](native_audit/checkpoint/audit.txt),
[run properties](native_audit/run_properties.txt),
[selected result](selected_result.json) and [file hashes](final_manifest.csv).

## File scope

Production changes are limited to the 10 ns clock constraint, native XPR run
configuration, new `post_route_10ns.tcl`, `tools/build_10ns.tcl`,
`tools/run_10ns_project.tcl`, and the root README. This experiment directory
contains validation/audit scripts, the unselected MSU trial snapshot, source
manifests, exact simulator logs and physical evidence. All live RTL, packages,
C references, existing tests, vectors and seeds match the committed baseline.

[production_flow.patch](production_flow.patch) contains the reviewable production
flow/documentation diff, and [changed_files.txt](changed_files.txt) lists every
file included in the final optimization commit. Existing crash/scratch files
remain untouched and untracked, as noted above.
