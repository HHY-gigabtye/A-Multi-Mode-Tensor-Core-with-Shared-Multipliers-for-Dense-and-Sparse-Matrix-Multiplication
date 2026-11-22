# Shared DU/TIA repair and repeated comparison

The user authorized expanding the isolated experiment after both original
post-route netlists rejected legal sparse traffic. Main remained unchanged during
that experiment. After validation, the final TC and DU/TIA sources were promoted
to the main working tree on November 22; see the
[promotion and fresh main regression](../../../../reports/verification/operand_route_main_20261122/README.md).
The original experimental snapshots and raw reports remain unchanged. Both
repaired snapshots use the same DU/TIA, so the TC comparison does not mix
repaired and unrepaired datapaths. Promotion did not rerun physical or power
analysis; its source hashes match this validated candidate exactly.

## Reproduction and correction

The standalone `du_gate.sv` wrapper has flat input/output vectors and contains
only DU/TIA. This removes the integrated TC and exported struct-port adapter
from the reproduction. Original RTL passes; its synthesized functional netlist
fails on the first directed packet at 257 ns:

```text
A bitmap = f2, packed values = 01 02 03 04 05
Expected A indices = [1, 4, 5, 6, 7]
Actual A indices   = [0, 0, 0, 0, 7]
actual   = 150000000504030201007000300000000001312110001eb
expected = 150000000504030201007d61300000000001312110001eb
```

The original integrated hybrid failure also loses earlier compacted B values.
See [standalone failure](original_gate/simulation.log) and the retained original
integrated failures under `../baseline/functional_net_saif/hybrid/` and
`../candidate_v2/functional_net_saif/hybrid/`.

`du_tia_fixed.sv` builds S1 and S2 payload fields in ordinary packed structs,
then assigns the selected packed union once. It replaces repeated partial
writes through the union. The decode tables, compaction loops, arithmetic,
registers, reset, four-stage latency, and public packet types are unchanged.
This is a verified workaround for the RTL/netlist discrepancy under Vivado
2022.2; no vendor-confirmed general compiler defect is claimed.

The additional independent unit test compares every output bit and its exact
four-stage valid timing, including idle/reset outputs. Original RTL, repaired
RTL, and repaired synthesized netlist pass the same seed `9412c731`:

- All 65,536 A/B bitmap pairs, empty/full cases, stored zeros, signed extrema,
  and nonzero unused input padding.
- 6,144 hybrid cases covering every A bitmap, all four positions, and all six
  legal 2:4 masks, distributed differently across columns.
- 4,096 mixed randomized offers with idle cycles and 16 in-flight resets.
- 74,734 accepted packets, 74,701 checked outputs; resets intentionally discard
  33 in-flight packets. The initial reproduction packet is also included.

Evidence: [original RTL](original_rtl/PASS.txt), [repaired RTL](fixed_rtl/PASS.txt),
[repaired synthesized netlist](fixed_gate/PASS.txt), [new unit test](tb_du_gate.sv),
[original synthesis](synth_original.log), [repaired synthesis](synth_fixed.log).

## Isolation and comparison method

`prepare.ps1` copies the 93-file original manifests into two new snapshots and
replaces only `du_tia_sv/rtl/du_tia.sv` with the shared repair. The selected TC
candidate is byte-identical to the earlier `candidate_v2` implementation.
`source_manifest.csv` records every old/new hash. The original tests, golden
models, vectors, assertions, and seeds are immutable.

`run_regression.ps1` runs all existing units before integration and requires
the same 50 accepted top-level summaries. `implement.tcl` preserves the original
10 ns integrated OOC implementation flow and also exports its routed functional
netlist. No synthesis/placement/routing optimization is introduced by this repair.
The new physical results must be assessed independently of the original routes.

The power workload, seed, input trace, 20.480 us capture window, 256 completed
tiles, 100 MHz clock, voltages, fixed 50 C junction temperature, and functional
SAIF method are the same as described in [the power methodology](../README.md).
Both TC versions use the shared repaired DU/TIA. The original dense-only estimates
are retained separately and must not be mixed into this repaired comparison.

The new integrated implementation, netlist validation, and power results are
recorded in the parent [experiment report](../../REPORT.md).

Completed: both original regression suites and all six repaired routed functional
workloads pass. Identical-input and source/artifact checks pass. Independent
reopened-checkpoint 100 MHz audits pass both variants. The candidate uses
12,769 versus 22,523 post-route LUTs (-43.3%). Total on-chip power estimates are
0.714 -> 0.573 W dense, 0.574 -> 0.501 W hybrid, and 0.567 -> 0.494 W dual.
Sparse DSP power rises 6-7 mW while total power falls. See
[validation](validation.PASS.txt), [power comparison](power_comparison.csv),
[component summary](power_summary.csv), and [audit](audit/audit_summary.txt).

## Reproduction commands

These commands document the isolated experiment. Its final
`check_integrity.ps1` command requires the pre-promotion main sources and will
reject today's promoted tree; run that check only in an isolated reproduction
copy with the original baseline at the root. Use the
[main regression launcher](../../../../reports/verification/operand_route_main_20261122/README.md#fresh-production-regression)
for the updated main source set. Keep accepted snapshots, captures, and report
directories intact when selecting fresh output paths.

Run from `experiments/pre_route_20261122`. The commands below identify retained
runs; preserve them and choose fresh output paths when repeating. Simulation
uses the host's approved native compiler execution, as in the original experiment.

```powershell
$vivado = 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat'
& $vivado -mode batch -nojournal -log power/du_repair/synth_original.log -source power/du_repair/synth_unit.tcl -tclargs baseline/src/du_tia_sv/rtl/du_tia.sv power/du_repair/original_synth
./power/du_repair/run_unit.ps1 -Source baseline/src/du_tia_sv/rtl/du_tia.sv -RunName original_rtl
# Expected failure: retained reproduction, not waived validation.
./power/du_repair/run_unit.ps1 -Source power/du_repair/original_synth/unit_netlist.v -RunName original_gate -Gate
& $vivado -mode batch -nojournal -log power/du_repair/synth_fixed.log -source power/du_repair/synth_unit.tcl -tclargs power/du_repair/du_tia_fixed.sv power/du_repair/fixed_synth
./power/du_repair/run_unit.ps1 -Source power/du_repair/du_tia_fixed.sv -RunName fixed_rtl
./power/du_repair/run_unit.ps1 -Source power/du_repair/fixed_synth/unit_netlist.v -RunName fixed_gate -Gate
./power/du_repair/prepare.ps1
foreach ($variant in 'baseline','candidate_v2') {
  ./power/du_repair/run_regression.ps1 -Variant $variant
  ./power/du_repair/run_power_sim.ps1 -Variant $variant -Kind rtl
  & $vivado -mode batch -nojournal -log "power/du_repair/implement_$variant.log" -source power/du_repair/implement.tcl -tclargs $variant "power/du_repair/$variant/routed"
  ./power/du_repair/run_power_sim.ps1 -Variant $variant -Kind functional
}
foreach ($mode in 'dense','hybrid','dual') {
  ./power/du_repair/prepare_saif.ps1 -Mode $mode
}
& $vivado -mode batch -nojournal -log power/du_repair/analyze_candidate_v2.log -source power/du_repair/analyze.tcl -tclargs candidate_v2
foreach ($mode in 'dense','hybrid','dual') {
  & $vivado -mode batch -nojournal -log "power/du_repair/analyze_baseline_$mode.log" -source power/du_repair/analyze.tcl -tclargs baseline functional $mode
}
& $vivado -mode batch -nojournal -log power/du_repair/audit.log -source audit.tcl -tclargs power/du_repair/baseline/routed/routed.dcp power/du_repair/candidate_v2/routed/routed.dcp power/du_repair/audit
./power/du_repair/check_results.ps1
./power/du_repair/summarize.ps1
./check_integrity.ps1 -Variant candidate_v2
```
