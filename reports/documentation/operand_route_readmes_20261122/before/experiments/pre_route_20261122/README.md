# Operand routing before multiplication

This isolated experiment starts from production commit
`2458bf6962ea6946d820276a0faba0e00e6fe5e5` on `main`. It does not update the
production RTL, Vivado project, reference models, existing tests, or seeds.
The initial production worktree was clean. The source snapshots are recorded
in `baseline_manifest.csv`, `extra_manifest.csv`, and `source_integrity.csv`.

The completed [measurement report](REPORT.md) records a **43.3%** integrated
post-route LUT reduction, unchanged 64-DSP usage, passing 100 MHz timing for
both versions, and estimated total power reductions of **19.7% dense, 12.7%
hybrid, and 12.9% dual**. Both compared versions use the same isolated DU/TIA
repair, authorized after power validation exposed an RTL/netlist mismatch in
the original sparse implementation. All original evidence is retained; see
[the repair record](power/du_repair/README.md). Both repaired netlists pass all
three power workloads. Power uses functional SAIF without routed-delay glitches;
it is not a board measurement. Production is unchanged.

## Scope and compatibility

The sole functional RTL difference is `tensor_core_sv/outer_product_core.sv`.
`candidate/` retains the first attempt, which passed functionally but caused
Vivado to infer 128 DSPs by duplicating multiply-add cones. `candidate_v2/`
adds an explicit `use_dsp = "no"` attribute on the fabric accumulation sum;
the multiplier retains `use_dsp = "yes"`. This refinement is evaluated against
the same baseline. The first attempt and its reports are preserved.

The baseline registers packed-lane products, routes the 16-bit products by
column and row, then accumulates. The candidate registers two independently
routed 8-element INT8 vectors and their presence masks, registers 64 signed
products at fixed coordinates, then accumulates. Missing coordinates receive
zero operands. Presence masks remain separate from values so stored zeros
retain the baseline enable/event behavior.

The experiment retains 32-bit accumulators, the indexed 184-bit interface,
64 multipliers, two result slots, old-state result-credit readiness, whole-edge
error rejection, result ordering, and reset behavior. There is no added clock
stage: legal k=7 publication remains three advancing edges later and the
unstalled tile initiation interval remains eight cycles.

The existing `tick_info.mul` and `tick_info.route` fields are preserved as
first-stage and second-stage compatibility observations. In this candidate
their historical names no longer describe the physical operation: the first
stage routes operands and the second multiplies them. No existing test or
expected event vector was changed to accommodate the implementation.

## Validation

Both variants use byte-identical copies of the original unit testbenches,
reference vectors, comparison benchmark, and integration scoreboard. The
launcher requires all PASS markers and all 50 accepted integration summary
lines. `simulate.ps1` runs the original units before integration and checks
protected snapshot hashes before and after the tests.

`tb_pre_route_equiv.sv` adds a standalone common-stimulus comparison with an
independent GEMM and publication-timing oracle. It exhausts all 65,536 pairs
of A/B bitmaps, including empty/full vectors, stored zero, signed extremes,
and nonzero padding. A deterministic randomized phase injects bubbles,
backpressure, malformed offers, full-credit offers, and resets. A final
directed case rejects a third tile while a result pop is requested. The test
compares public outputs and tick observations before and after each edge,
as well as accumulators, result tails, and credit counters.

The baseline used in that additional comparison is unchanged. The ModelSim
launcher generates a compilation adapter that renames only its module
declaration to `outer_product_core_baseline`.

## Physical comparison

Both variants use `implement.tcl`: Vivado 2022.2, xc7z020clg484-1, integrated
out-of-context synthesis at 10.000 ns, one synthesis thread, two implementation
threads, default placement, default physical optimization, and default routing.
The same source ordering and clock assumptions are used for both variants.
No board input/output delay constraints or HD.CLK_SRC value are added.

`audit.tcl` independently reopens both routed checkpoints and applies the
existing production 100 MHz audit, including DSP/BRAM configurations, routing
completion, DRC, setup, and hold. It also tests adjacent 10 ps clock periods
around each fixed route's setup boundary. This is internal STA on the fixed
routes, not a new implementation at the tighter period or a board measurement.

The [power extension](power/README.md) records the 100 MHz workload-driven
Vivado estimates, netlist validation, and the shared DU/TIA repair. Original and
repaired implementation results are kept separate in the measurement report.

## Reproduction

From this experiment directory in PowerShell, use a fresh RunName/output path
for each repeated regression or implementation. On this host the 32-bit
ModelSim executable requires execution outside the sandbox; sandbox startup
failed with a Windows system-DLL relocation error. The new launcher explicitly
redirects stdout/stderr and starts ModelSim with a hidden window.

```powershell
./check_integrity.ps1
./simulate.ps1 -Variant baseline -RunName verification_repeat
./simulate.ps1 -Variant candidate_v2 -RunName verification_repeat
./run_equivalence.ps1 -Variant candidate_v2
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log baseline/implementation_repeat.log -source implement.tcl -tclargs baseline baseline/routed_repeat
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log candidate_v2/implementation_repeat.log -source implement.tcl -tclargs candidate_v2 candidate_v2/routed_repeat
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log audit_repeat.log -source audit.tcl -tclargs baseline/routed_repeat/routed.dcp candidate_v2/routed_repeat/routed.dcp audit_repeat
./check_integrity.ps1
```

The equivalence launcher refreshes its own logs and compilation scratch.
The copied original simulation scripts likewise reuse their variant-local
work libraries. The original production work libraries are not used.

Raw `c_vectors.txt` files and tool binaries/checkpoints are ignored by Git.
Each snapshot retains the unchanged gzip vector file for reconstruction.

## Files

- `baseline/src/`, `candidate/src/`, `candidate_v2/src/`: 93-file snapshots; only the TC RTL differs.
- `baseline_manifest.csv`, `extra_manifest.csv`, `provenance.txt`: source origin.
- `simulate.ps1`, `implement.tcl`, `audit.tcl`: repeatable comparison flow.
- `tb_pre_route_equiv.sv`, `equivalence.do`, `run_equivalence.ps1`: additional unit check.
- `check_integrity.ps1`, `source_integrity.csv`, `integrity.PASS.txt`: integrity audit.
- Each variant's `verification/`: original regression evidence.
- Each candidate's `equivalence/`: additional comparison and GEMM evidence.
- Each variant's `routed/`, plus `audit/`: physical measurements and audits.
- `rtl.diff`, `REPORT.md`: reviewable RTL delta and final conclusions.

Only files below this experiment directory are created or modified.
