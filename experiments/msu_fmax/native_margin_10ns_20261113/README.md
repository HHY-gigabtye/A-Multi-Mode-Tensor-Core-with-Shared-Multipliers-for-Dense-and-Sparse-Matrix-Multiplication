# Fresh native 10 ns rebuild, 2026-11-13

> This timestamped record describes the completed native rebuild. Subsequent
> publication cleanup removed the superseded `synth_10ns` / `impl_10ns` run
> entries from the active XPR. The selected runs remain
> `synth_10ns_margin_20261113` / `impl_10ns_margin_20261113`. Statements below
> about preserved older runs describe the state at audit time; generated run
> directories and checkpoints are not distributed. Use a new output directory
> and unused suffix when reproducing the build.

## Scope and status

Requested: rebuild the updated physical flow from source in native Vivado runs,
verify the 10.000 ns result, and open that implementation in the Vivado GUI.
Work is directly on `main`, based on `f6ee5f1973487dad8026141550131cfe41c561da`.
No RTL, interface, latency, reference model, test, or expected vector was changed.
No new branch, worktree, commit, merge, or push was created.

Status: PASS. The fresh native build completed with exit code 0 at 20:27:54
(UTC+08:00), and the independent audit completed with exit code 0 at 20:29:27.
The GUI was then opened and visually verified: its implemented-design header
shows `impl_10ns_margin_20261113`, and its Timing Summary shows WNS +0.016 ns,
WHS +0.096 ns, zero failing endpoints, and all user-specified timing constraints
met. The GUI remains open on this result.

The previous `synth_10ns` and `impl_10ns` runs are preserved. New runs are
`synth_10ns_margin_20261113` and `impl_10ns_margin_20261113`.
`project_before.xpr` preserves the project file as found before this task,
including the user's existing edits. The project now selects the new runs.

## Reproduction

From the repository root, using a new output directory and unused run suffix:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/native_margin_10ns_20261113/native_project.log -source tools/run_10ns_project.tcl -tclargs experiments/msu_fmax/native_margin_10ns_20261113/native_project 10ns_margin_20261113
```

This command was launched at 18:55 on 2026-11-13 (UTC+08:00). It performs
fresh OOC synthesis, placement, default routing, refinement, six-driver
replication, closure refinement, the 9.750 ns physical search, restoration to
10.000 ns, and the existing final setup/hold gate. No historical checkpoint is
imported. All intermediate DCPs belong to the new native run.

Native recipe directory:
`project_integration/project_integration.runs/impl_10ns_margin_20261113/recipe_10ns_20261113_191421/`.

## Measured stages

Vivado 2022.2, `xc7z020clg484-1`, FPGA OOC post-route STA, 4 threads.
The following completed stages use the same 10.000 ns operating constraint.

| Stage | Setup WNS ns | TNS ns | Hold WHS ns | THS ns |
| --- | ---: | ---: | ---: | ---: |
| Fresh default route | -0.449 | -20.186 | +0.098 | 0.000 |
| First refinement | -0.231 | -3.720 | +0.098 | 0.000 |
| Driver replication and route | -0.207 | -13.765 | +0.096 | 0.000 |
| Closure refinement | +0.002 | 0.000 | +0.096 | 0.000 |
| Margin search, restored to 10.000 ns | +0.016 | 0.000 | +0.096 | 0.000 |
| Reopened native run and independent DCP audit | +0.016 | 0.000 | +0.096 | 0.000 |

All four stages reproduce the corresponding preserved native baseline reports.
The 9.750 ns period is only a physical search target; final acceptance requires
restoring the 10.000 ns clock and reopening the result without replacing its
constraints. Internal OOC STA does not establish board-level I/O timing; no I/O
delays or `HD.CLK_SRC` constraints were added.

The final native run has status `route_design Complete!` and
`NEEDS_REFRESH=0`. Its full-precision project statistics are WNS 0.015567 ns
and WHS 0.095518 ns; the displayed reports round these to 0.016 and 0.096 ns.
TNS and THS are both zero. Pulse-width slack is +4.020 ns. All 41,612 routable
nets are fully routed, with zero routing errors. DRC has no Error or Critical
Warning: the existing warning classes are DPIP-1 (320), DPOP-1 (64), DPOP-2
(128), and ZPS7-1 (1). Utilization is 29,406 LUTs, 21,503 registers and 128 DSPs.
The 9.750 ns search target itself is not closed (WNS -0.234 ns); only the
restored 10.000 ns result is accepted.

The critical slow-corner setup path is
`u_bridge/head_select_q_reg[4]_rep/C` to
`u_tensor_core/g_arithmetic_row[3].g_arithmetic_column[7].product_q_reg/A[5]`.
It has three LUT levels (LUT4/LUT5/LUT6), source-net fanout 96, and data-path
delay 6.178 ns (0.828 ns logic, 5.350 ns route). The destination DSP setup
requirement is also included in STA; the data-path delay alone is not Fmax.
See `independent_audit/checkpoint/critical_paths.rpt` for the complete path.

## Independent audit and GUI

Executed audit command:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log experiments/msu_fmax/native_margin_10ns_20261113/independent_audit.log -source experiments/msu_fmax/native_margin_10ns_20261113/audit_native.tcl -tclargs impl_10ns_margin_20261113 experiments/msu_fmax/native_margin_10ns_20261113/independent_audit
```

The audit checks current-run selection, completion, freshness, project timing
statistics, and the saved clock. It then separately opens the native routed
DCP with the existing read-only audit script, preserving its constraints.
`independent_audit/` contains run properties, clocks, timing, route status,
DRC, utilization, critical paths, DSP configuration and endpoint-group reports.

Executed GUI command from the repository root:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode gui -nojournal -log C:/Users/Jason/Desktop/TC/experiments/msu_fmax/native_margin_10ns_20261113/gui.log -source C:/Users/Jason/Desktop/TC/experiments/msu_fmax/native_margin_10ns_20261113/open_gui.tcl
```

`gui_loaded.txt` records the GUI's actual loaded run, clock and timing.
The visible GUI was independently inspected using the computer-use skill.
The native routed DCP is
`project_integration/project_integration.runs/impl_10ns_margin_20261113/sparse_tensor_core_top_routed.dcp`.
Its SHA256 is
`D3BB68943300BCA0E34EA2640293D69E15D7C3865BF0F0ED045596436F09CC8E`.
This fresh native verification supersedes the pending-native-rebuild limitation
in the earlier, timestamped `../margin_10ns_20261113/` experiment record.

## Functional baseline and preservation

All 11 live source files match the immutable snapshot and the fully regressed
baseline in `../margin_10ns_20261113/final_live/`. Its original five unit tests
and integration passed before this rebuild. Simulation is not rerun for this
physical-only task because the RTL is unchanged. `sources.csv` records source
hashes, `flow_sources.csv` records the ten flow inputs, and
`protected_verified.csv` verifies all 76 protected reference/test files.

`preserved_verified.csv` verifies the old routed checkpoint, the user's root
README, crash archive, and scratch file. Only the project file is intentionally
updated to add/select the new native runs. Existing user edits are retained.
All source, flow, protected-file and preservation hashes were checked again
after the build. `project_update.patch` shows only this task's project changes
relative to `project_before.xpr`, separate from the user's pre-existing diff.
`final_manifest.csv` excludes the live `gui.log`, which remains locked by the
open GUI. Generated XPR line endings are retained; diff whitespace validation
uses Git's `cr-at-eol` setting without changing repository configuration.

## File scope

- Modified by native Vivado: `project_integration/project_integration.xpr`.
- New reviewable scripts: `audit_native.tcl` and `open_gui.tcl` in this directory.
- New evidence: this README, source snapshot, project backup, manifests, logs,
  and the native report directory; native synthesis/implementation artifacts
  reside under the two new run directories.
- The earlier uncommitted production flow changes are used without modification.
