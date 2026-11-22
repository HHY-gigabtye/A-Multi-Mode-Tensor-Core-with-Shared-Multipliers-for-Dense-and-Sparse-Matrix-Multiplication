# Shared outer-product implementation in Vivado

## Active sources and backup

The production project builds the shared **Routing → MUL → ACC** TC with the repaired DU/TIA, BRAM MLU, and rotating Bridge FIFO. The active source set has 11 SystemVerilog files. The legacy TC is available in the unit comparison suite.

The November 22 promotion updated the root TC and DU/TIA sources without
rebuilding existing Vivado GUI runs. A new synthesis reads the promoted sources;
an already completed run or checkpoint retains its original implementation.
See the [current promotion record](../reports/verification/operand_route_main_20261122/README.md)
for source hashes, fresh main-source regression, and matching candidate reports.

The original RTL, project configuration, scripts, and root README are backed
up in the [pre-BRAM historical archive](../backups/pre_bram_20261119/README.md), with a SHA-256
manifest. A verified original FF routed checkpoint and its reports are also
copied into the backup's `snapshot/implementation/` directory. The checkpoint
is local-only; its hash and text reports are published. The archive guide
distinguishes this predecessor from the current shared outer-product design.

The MLU uses synchronous BRAM storage with a pending write, early next-tile
read, saved final packet, and hybrid data forwarding. The Bridge remains a
register FIFO: physical words rotate on pop so its combinational head is
always physical slot zero. Neither change inserts a public pipeline stage.

## Open and inspect in Vivado 2022.2

The [November 22 promotion record](../reports/verification/operand_route_main_20261122/README.md) links the current source-matched implementation evidence at 10.000 ns. The [November 21 record](../reports/verification/outer_main_20261121/README.md) describes the retained multiply-before-route GUI implementation, and the [previous BRAM result](../reports/verification/bram_main_20261119/README.md) records the 128-DSP predecessor.

1. Open [project_integration.xpr](../project_integration/project_integration.xpr).
2. In **Design Runs**, the retained `synth_outer_100mhz` and
   `impl_outer_100mhz` runs identify the November 21 implementation unless
   explicitly rebuilt. The previous BRAM runs have separate names.
3. Select **Open Implemented Design** for `impl_outer_100mhz`.
4. Select **Report Timing Summary** to inspect setup/hold slack and the
   `clk` period of **10.000 ns**. Select **Report Utilization** on the implemented
   design to inspect LUTs, registers, Block RAM Tile, and DSP counts.
5. The clock constraint, OOC synthesis setting, thread limits, physical
   optimization step, and final validation hook are saved in the project;
   no manual Tcl entry is required for these GUI operations.

An optional native GUI launcher, `tools/open_bram_100mhz_gui.tcl`, opens the
selected completed implementation and displays named utilization and
timing reports. It rejects an incomplete/out-of-date run or a failed clock/
BRAM/timing check. Launch it with Vivado's `-mode gui -source` options; normal
project opening and the GUI steps above do not require this helper.

## Rebuild using only GUI controls

For a deliberate rebuild of an existing run, right-click `synth_outer_100mhz`
in **Design Runs**, choose **Reset Runs**, and include its dependent
`impl_outer_100mhz` run. This replaces those runs' generated results with a
build of the current root sources. Then select **Run Synthesis**, followed by
**Run Implementation**. To retain the existing runs, use the fresh-run Tcl
command below instead.
After completion, select **Open Implemented Design** and generate the two
reports above. A reset replaces generated results for the selected runs;
the dated verification reports and original backup remain separate.

The runs use `xc7z020clg484-1`, Default synthesis/placement/routing directives,
OOC synthesis, one synthesis thread, two implementation threads, and enabled
Default post-place `phys_opt_design`. Automatic incremental checkpoints are
disabled. Sources are read directly from the main module directories.

The route post-hook checks the current run's result without importing any
historical checkpoint. It requires nonnegative setup and hold slack at
10.000 ns, complete routing, zero DRC errors, zero REQP-1839 violations,
18 RAMB36E1s with the expected SDP/READ_FIRST configuration, and 64 DSP48E1s
with the product register enabled. A failed check fails the run rather
than claiming that the design passes 100 MHz.

Native project-mode operations and Tcl hooks follow the
[Vivado 2022.2 project-mode flow](https://docs.amd.com/r/2022.2-English/ug892-vivado-design-flows-overview/Using-Project-Mode)
and [UG894 Tcl scripting guide](https://www.xilinx.com/support/documents/sw_manuals/xilinx2022_2/ug894-vivado-tcl-scripting.pdf).

## Reproduce verification from the repository root

Choose new output directories to preserve existing evidence:

```powershell
./reports/verification/operand_route_main_20261122/run_regression.ps1 -RunName regression_repeat

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/bram_netlists_new.log -source tools/check_bram_main_netlists.tcl -tclargs C:/Users/Jason/Desktop/TC/build/bram_netlists_new

& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/bram_native_new.log -source tools/run_bram_100mhz_project.tcl -tclargs C:/Users/Jason/Desktop/TC/build/bram_native_new outer_100mhz_new
```

The first command checks the November 22 production source/reference manifest, runs the standalone units, compares both TCs and checks all 50 accepted top summaries. The second
command synthesizes MLU and Bridge separately and compares their functional
netlists against original RTL and immutable C vectors before/after each edge.
The third command creates fresh native runs, makes them active, builds from
main RTL, reopens the native implementation, and independently audits its
saved routed checkpoint. An explicit suffix must name unused runs. Without a suffix the script finds the next available outer-product run name.

The older `tools/verify_bram_main.ps1` still checks the November 21 manifest and
will reject today's promoted TC/DU/TIA sources. Its earlier results are retained;
the first command above is the current production regression entry point.

For the unchanged C models, run `tools\run_c_tests.bat` from a Visual Studio
Developer Command Prompt. This compiles the existing six C suites without
regenerating vectors or changing seeds/assertions.

The earlier `tools/build_10ns.tcl` and `tools/run_10ns_project.tcl` describe the
historical FF physical recipe. Use the BRAM entry points above for this version.

## Scope

Timing evidence is **FPGA OOC post-route internal STA**. External I/O delays,
board pins, a physical clock source, and an HBM/AXI controller are outside this
project's existing constraints. This workflow provides synthesis and
implementation in the GUI; it is not a board-ready bitstream flow or a measured
Fmax sweep. Re-run functional verification after later RTL changes and recheck
post-route timing after changing device, tool version, constraints, or strategy.
