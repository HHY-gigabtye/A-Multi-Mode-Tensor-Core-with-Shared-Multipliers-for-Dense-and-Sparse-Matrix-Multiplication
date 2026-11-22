# Power comparison at 100 MHz

This extension initially compared the unchanged routed baseline checkpoint with
the 64-DSP operand-route candidate. Dense passed, but both original hybrid
netlists rejected legal input. Baseline dual diagnosis also reproduced a sparse
failure. These failed captures are excluded from power analysis. The user then
authorized a [shared DU/TIA repair](du_repair/README.md) in new isolated snapshots
and a fresh comparison. Production, original snapshots, references, tests,
assertions, and seeds remain unchanged. Results are in the parent `REPORT.md`.

The repaired comparison is complete: all six routed functional workload runs
pass, and estimated total power falls 19.7% dense, 12.7% hybrid, and 12.9% dual.
See [the results and limitations](../REPORT.md#100-mhz-power-comparison-with-the-shared-dutia-repair)
and [final validation](du_repair/validation.PASS.txt). Sparse DSP power rises
slightly, but total dynamic power falls in all three workloads. The original
commands below document the retained initial attempts; the final repaired-flow
commands are in [the repair record](du_repair/README.md#reproduction-commands).

## Workload and validation

`tb_power.sv` is an additional independent memory driver and signed GEMM
scoreboard. All inputs are driven using the same deterministic seed `51a7c0de`.
Each workload submits 288 independent 8x8x8 tiles, verifies every 32-bit result
and address/metadata, and requires an output tile interval of eight cycles.
External read and write channels have no injected backpressure or response
gaps. Memory protocol overhead and all real integrated modules remain present.

- Dense: all coordinates retained.
- Hybrid: independent approximately 50% A-coordinate retention; B uses uniformly
  selected legal 2:4 masks along K, with exactly two retained values per group.
- Dual: independent approximately 50% A and B coordinate retention.
- Retained values use uniformly distributed signed INT8 bytes, including stored
  zeros. Unused memory-image bytes are zero. These are synthetic sustained-load
  cases, not a trace from a particular application or an exhaustive density sweep.

The clock is 10.000 ns in the testbench and both checkpoints. Startup/reset
finishes before traffic. The activity window is 2,000 through 22,480 ns:
20.480 microseconds, 2,048 clock cycles, and exactly 256 completed tiles in each
case. Warmup, final drain, and reset are outside this window.

Both RTL variants first pass the workload. The same scoreboard then runs on
the actual exported routed netlists. The netlist-only port adapter explicitly
connects Vivado's flattened struct/array ports; it adds no clock or logic stage.
Separate transaction logs allow workload identity to be checked across variants.

## Activity and power methodology

The accepted activity flow uses `export_functional.tcl` to export a functional
simulation netlist from each retained routed checkpoint, and XSim 2022.2 to run
it. `simulate.tcl` captures nets/ports in the top and its five design-module
scopes during the steady window. Vendor primitive internals that do not correspond
to implemented design nets are excluded. The independent GEMM scoreboard must
finish successfully. `run_capture.ps1` reuses each compiled functional snapshot
and writes separate `functional_net_saif/{dense,hybrid,dual}` artifacts.

An SDF-annotated timing capture was attempted first: `export.tcl` saved each timing
netlist and slow-corner SDF, and XSim used maximum delays and transport settings.
Both native elaborators continued consuming a CPU without completing delay
annotation for more than 15 minutes. Those experiment processes were stopped,
and their logs/exports retained. They are NOT counted as passing timing simulations.
The accepted functional captures do not load SDF and therefore do not reproduce
actual routed delay glitches. They provide workload-driven functional switching
estimates, not a full timing/glitch-aware power result. The previous STA audit
still establishes the separate internal 100 MHz timing result.

`analyze.tcl` independently reopens the original 100 MHz checkpoints for every
workload, imports the corresponding SAIF with `-strip_path tb_power/dut`, and
reports annotation, operating conditions, power hierarchy, and input activity.
No power optimization or implementation rerun is performed.

Comparison assumptions are fixed at typical process, 50 C junction temperature,
VCCINT=1.0 V, VCCBRAM=1.0 V, and VCCAUX=1.8 V. Although the script supplies an
initial 25 C ambient setting, Vivado back-calculates ambient when junction
temperature is fixed; effective ambient is not held equal. Fixed junction
temperature avoids confounding the comparison with different estimated thermal
feedback. These are specified comparison conditions, not measured board values.
The same conditions and functional activity methodology are used for both versions.

The checkpoints are out-of-context: no board I/O load or actual top-level clock
buffer integration is represented. The estimates do not include external memory,
regulators, or a complete board. Absolute watts therefore describe this model.
SAIF annotation coverage and residual vectorless/default activity must be reviewed
before interpreting the differences. Values are estimates, not measured power.

AMD's [Vivado 2022.2 power methodology](https://docs.amd.com/r/2022.2-English/ug907-vivado-power-analysis-optimization/Specifying-Switching-Activity-for-Power-Analysis)
recommends realistic workloads and post-implementation timing activity to capture
glitches; unmatched nodes can still use vectorless propagation.

## Commands

Run from the parent experiment directory. Choose new export/run/report folders
when repeating to preserve accepted evidence. The simulator's native C compiler
requires approved execution outside this host's filesystem sandbox.

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log power/export_baseline.log -source power/export.tcl -tclargs baseline
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log power/export_candidate_v2.log -source power/export.tcl -tclargs candidate_v2
./power/run_sim.ps1 -Variant baseline -Kind rtl -RunName rtl_final
./power/run_sim.ps1 -Variant candidate_v2 -Kind rtl -RunName rtl_final
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log power/export_functional_baseline.log -source power/export_functional.tcl -tclargs baseline
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log power/export_functional_candidate_v2.log -source power/export_functional.tcl -tclargs candidate_v2
./power/run_sim.ps1 -Variant baseline -Kind functional -RunName functional
./power/run_sim.ps1 -Variant candidate_v2 -Kind functional -RunName functional
# Retained accepted captures used these launchers to reuse the compiled snapshots:
./power/run_capture.ps1 -Variant baseline
./power/run_capture.ps1 -Variant candidate_v2
foreach ($mode in 'dense','hybrid','dual') {
  foreach ($variant in 'baseline','candidate_v2') {
    & 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log "power/analyze_${variant}_${mode}.log" -source power/analyze.tcl -tclargs $variant functional_net_saif $mode
  }
}
./power/check_results.ps1
./check_integrity.ps1 -Variant candidate_v2
```

Earlier setup attempts are preserved. Sandbox native compilation failed; the
approved external execution succeeds. Windows batch parsing required avoiding
unquoted `=` in runtime plusargs and using forward slashes for the XSim Tcl
script path. The netlist adapter also needs plain 3-bit status wires, because
the exported module ports are bit vectors rather than SystemVerilog enums.
These launcher/adapter failures are not counted as successful simulations. The
initial recursive logging attempt also spent excessive time enumerating vendor
primitive internals. Only the validated design-scope captures are used for power.
`stopped_attempt_processes.csv` identifies the experiment processes stopped during
fallback selection; no unrelated simulator or user process was stopped.
