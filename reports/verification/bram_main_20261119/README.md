# BRAM main promotion and complete validation

> Historical architecture scope: this record describes the November 19, 2026 predecessor or its experimental variants. References below to current, selected or production RTL refer to that dated snapshot. Current `main` uses a shared 64-multiplier outer-product core for every format; its dense timing and format-change rules differ. See the [current TC contract](../../../tensor_core_sv/README.md) and [promotion record](../../../reports/verification/outer_main_20261121/README.md). Original measurements and validation results below are retained.

## Source and backup

The accepted `experiments/mlu_bram_100mhz_20261118/rotating_fifo/src` version
was applied to the `main` working tree on 2026-11-19. No commit, merge, or push
was performed. All 11 main RTL/package source hashes match the accepted
snapshot recorded in [regression/sources.csv](regression/sources.csv).

Only `mlu_sv/mlu.sv` and `fifo_sv/du_tc_bridge.sv` changed. See the complete
[main RTL diff](main_rtl.patch): 216 inserted and 75 deleted lines across both
modules. TC, MSU, DU/TIA, top, and packages are unchanged.

The [historical archive guide](../../../backups/pre_bram_20261119/README.md) leads to
22 original source/configuration/documentation files, verified against its
SHA-256 manifest before and after promotion. On 2026-11-22 the complete backup
was relocated byte-for-byte into `snapshot/`, preserving the original manifests
and relative paths. Its `snapshot/README.md` is the original repository README;
original backup instructions are in `snapshot/BACKUP.md`. The outer guide states
the historical architecture scope and supplies maintained navigation.
Old experiment snapshots are retained. A verified original FF checkpoint and
five reports are additionally backed up under `snapshot/implementation/` with a
separate six-file manifest. The DCP is local-only; the manifest and text reports
are published. Original path strings in the dated JSON/log records are preserved;
the archive's relocation record maps them to the new locations. See the
GUI-handoff note below about the old native runs.

## Fresh functional results

The five original units were run before the integration test, directly against
the promoted main files. No golden vectors, C models, existing testbench
assertions, or random seeds were edited or regenerated.

| Check | Fresh result |
|---|---|
| MLU RTL/C replay | PASS; 16,708 records, 145 resets, 128 expected rejected edges |
| DU/TIA | PASS; 3,292 packets: 12 directed, 24 hybrid exhaustive, 256 bitmap exhaustive, 3,000 random |
| Bridge RTL/C replay | PASS; 19,147 records, 7,156 expected rejected edges, 13 resets |
| TC RTL/C replay | PASS; 136,136 records, 169 resets, 13 expected rejection cases |
| MSU RTL/C replay | PASS; 8,683 cycles, 676 accepted results, 5,394 writes, 673 completions, 8 resets |
| Connected RTL | PASS; 316 completed tiles, 3,124 issued packets, 2,563 writes, 75 resets, seed `91e10da5` |
| Integration comparison | All 46 phase/coverage/reset/mode/summary lines exactly match the original FF baseline |
| Newly synthesized MLU netlist | PASS; 16,708 vectors, 17,171 comparisons, 18 directed transitions, 234 simultaneous final-load/final-output cases, 5,347 stalls, 155 resets |
| Newly synthesized Bridge netlist | PASS; 19,147 records, 38,294 pre/post-edge comparisons, 7,156 rejected edges, 13 resets |
| Six original C suites | PASS; TC, MLU, MSU, Bridge, DU/TIA, and basic outer-product example |
| Integrity | 11 main source hashes match the accepted version; 76 protected reference/test files unchanged |

Evidence: [unit log](regression/units.log), [integration log](regression/top.log),
[46-line comparison](regression/integration_summary.txt),
[MLU netlist](netlists/mlu_equivalence/result.log),
[Bridge netlist](netlists/bridge_equivalence/result.log), and
[C suite](c_reference_retry.log). ModelSim Intel FPGA 2020.1 and Vivado/XSim
2022.2 were used. C tests were compiled with the installed MSVC C11 compiler.

The first C launcher invocation had an incorrect relative path and did not
start the suite. Only the new launcher path was corrected; the original C
runner/models/tests were unchanged. The failed `c_reference.log` is preserved;
the successful rerun is `c_reference_retry.log` (exit 0).

## Native implementation

The main project now contains `synth_bram_100mhz` and `impl_bram_100mhz` as
its active runs. The promotion script initially preserved the previous
`*_10ns_margin_20261113` runs; these were subsequently removed through the GUI
during handoff. Their original project configuration is preserved in the backup.
Sources are the main module files, and the constraint is the original 10 ns
clock on `xc7z020clg484-1`. Native synthesis/implementation starts from RTL;
no historical DCP is imported and automatic incremental reuse is disabled.

The native build completed successfully (exit 0) and passed both a native-run
reopen and an independent routed-checkpoint reopen. The following numbers are
**post-route**, not synthesis estimates:

| Metric | Original main GUI FF run | New main GUI BRAM run |
|---|---:|---:|
| Clock period | 10.000 ns | 10.000 ns |
| LUTs | 29,406 | 28,213 |
| Fabric registers | 21,503 | 19,852 |
| RAMB36E1 | 0 | 18 |
| DSP48E1 | 128 | 128 |
| Setup WNS | +0.016 ns | +0.011 ns |
| Hold WHS | +0.096 ns | +0.098 ns |
| Fully routed nets | 41,612 | 40,406 |
| Routing errors | 0 | 0 |

Savings are 1,193 LUTs (4.06%) and 1,651 registers (7.68%). The historical
main GUI run is documented in
[the original native result](../../../experiments/msu_fmax/native_margin_10ns_20261113/result.json).
The earlier BRAM experiment used a separately implemented FF baseline with
29,405 LUTs and +0.002 ns WNS; the one-LUT difference is a physical-flow
difference, not another RTL change. Device/tool/operating constraints match,
but the physical recipes are different.

The new native run exactly reproduces the accepted experiment's reported
post-route resource counts and setup/hold slacks. It has no DRC errors, zero
REQP-1839 violations, 18 SDP/READ_FIRST BRAMs, and the original 128 DSP pipeline
configurations. Setup/hold TNS are zero. See the independent
[PASS record](native/independent_checkpoint/PASS.txt),
[timing](native/independent_checkpoint/timing_summary.rpt),
[utilization](native/independent_checkpoint/utilization.rpt), and
[routing](native/independent_checkpoint/route_status.rpt).

Fresh synthesis reported 28,431 LUTs, 19,852 registers, 18 RAMB36E1s, and
128 DSP48E1s. Those **pre-placement** numbers are distinct from the table above.
Timing remains internal FPGA OOC STA with only 11 ps setup margin. No board
timing, HBM controller, bitstream programming, Fmax sweep, or measured power
was verified. External I/O delays and clock-source location remain unspecified,
as in the original design.

See [project settings](native/project_settings.txt),
[native build transcript](native_build.log), and the
[GUI guide](../../../docs/bram-100mhz-gui.md).

## GUI handoff

The native GUI launcher successfully opened `impl_bram_100mhz`, confirmed it
was complete and not out of date, checked 10 ns / 18 BRAMs / nonnegative setup
and hold slack, and created the named `bram_100mhz_utilization` and
`bram_100mhz_timing` reports. Its [GUI transcript](gui_bram.log) records
`GUI_BRAM_OPENED run=impl_bram_100mhz period_ns=10.000 setup=0.011 hold=0.098 bram36=18`.
The project is available in the interactive Vivado session.

After the successful open, `gui_bram.log` recorded
`delete_runs "synth_10ns_margin_20261113"`, which also removed its dependent
old implementation. This was not issued by the promotion/launch scripts.
The old native DCP is consequently absent. Its historical text reports remain;
the separately verified original FF checkpoint (29,405 LUTs / +0.002 ns WNS)
was copied into the backup instead of recreating the removed GUI runs.

Computer Use was interrupted by an accidental physical Escape key. The user
authorized retries, including a fresh control-kernel initialization, but that
control tool continued to return its stopped state. No successful visual
inspection of the implemented-design report panels is claimed. The GUI was
instead opened through Vivado's own supported Tcl startup interface, and its
run/report commands completed successfully. No GUI automation is needed for
the user's normal project opening or Run Synthesis / Run Implementation flow.

## Commands used

From `C:/Users/Jason/Desktop/TC`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_bram_main.ps1 -OutputDir C:/Users/Jason/Desktop/TC/reports/verification/bram_main_20261119/regression

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log reports/verification/bram_main_20261119/netlists.log -source tools/check_bram_main_netlists.tcl -tclargs C:/Users/Jason/Desktop/TC/reports/verification/bram_main_20261119/netlists

& $env:ComSpec /d /c reports\verification\bram_main_20261119\run_c_reference.cmd

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log reports/verification/bram_main_20261119/native_build.log -source tools/run_bram_100mhz_project.tcl -tclargs C:/Users/Jason/Desktop/TC/reports/verification/bram_main_20261119/native
```

Use new output paths and an unused native run suffix for a fresh reproduction.
The existing output paths are intentionally protected from accidental overwrite.

## Changed and added source/configuration files

- Modified: `mlu_sv/mlu.sv`, `fifo_sv/du_tc_bridge.sv`,
  `project_integration/project_integration.xpr`, and root `README.md`.
- Added tools: `tools/verify_bram_main.ps1`,
  `tools/check_bram_main_netlists.tcl`, `tools/run_bram_100mhz_project.tcl`,
  and `tools/open_bram_100mhz_gui.tcl`.
- Added GUI hooks: `project_integration/scripts/bram_100mhz_synth_pre.tcl`,
  `bram_100mhz_impl_pre.tcl`, `bram_100mhz_route_post.tcl`,
  and `check_bram_100mhz.tcl` in the same directory.
- Added guide: `docs/bram-100mhz-gui.md`.
- Added archival material: `backups/pre_bram_20261119/` and this dated
  verification directory, including logs, manifests, netlists, and reports.

The original test files and historical experiment scripts remain unchanged.
The old experiment integrity checker expects the pre-promotion main RTL;
use `tools/verify_bram_main.ps1` to check the promoted version.

Final machine-readable results are in [result.json](result.json); the complete
source/backup/reference/archive hash check is recorded in
[integrity_final.txt](integrity_final.txt). The original 22-file backup manifest
and additional six-file implementation manifest both passed. The 36 archived
accepted-experiment artifacts remain unchanged.
