# Isolated 19-bit TC experiment results — 2026-11-22

## Disposition

The isolated 19-bit TC preserves exact signed INT32 external results, the
original functional behavior, II=8 and k=7+3 publication. It reduces integrated
post-route LUTs by **20.89%** and FFs by **27.22%**, with **64 DSP48E1s and 18
RAMB36E1s unchanged**. Both fresh implementations pass an independently reopened
100 MHz internal FPGA OOC setup/hold, routing and DRC audit.

The timing qualification is material: the candidate's setup margin is only
**+0.004 ns (4 ps)**, down from the baseline's +0.296 ns. This establishes a pass
for this implementation, not robust timing margin across other placements or
board integration. One identical additional post-route optimization pass on
both variants does not improve the margin or resource counts. The original
`routed/` checkpoints remain the selected, fully validated comparison. The
`refined/` checkpoints and reports are retained as an unselected experiment;
they were not independently reopened or functionally simulated again.

Production RTL remains unchanged on `main`, HEAD
`2f12bd635963337e04ce8195b19bbb7b23bb2284`. No commit, merge, push or destructive
Git operation was performed. The pre-existing user edit in AGENTS.md remains
byte-for-byte unchanged. There are no other pre-existing working-tree edits.

## RTL scope and numeric argument

Only `candidate/src/tensor_core_sv/outer_product_core.sv` differs from the
93-file baseline snapshot. The public packages, ports, payload layout, all
other modules, C references, vectors, original tests, seeds and assertions are
unchanged. See [RTL diff](rtl.diff), [source manifest](source_manifest.csv) and
[integrity check](integrity.PASS.txt).

For signed INT8 operands, one product is in [-16256, 16384]. Every partial sum
of at most eight products is consequently in [-130048, 131072]. Signed 19 bits
cover this range; signed 18 bits do not cover the positive endpoint. This
argument depends on fixed K=8, independent tiles and no prior-C accumulation.

The candidate stores `acc_q`, `result_q` and `tail_q` as 19-bit elements and
uses an explicitly signed 19-bit fabric sum. Products are sign-extended from
16 to 19 bits before addition. The result port is sign-extended from 19 to 32
bits. Full-width combinational `acc` and `tail` observation views preserve the
existing unit tests without duplicate registers. Reset, idle-epoch clearing,
stale result contents, malformed-input/full-credit whole-edge rejection,
presence masks for stored zeros and all stage-event observations are retained.
Multiplication keeps `use_dsp="yes"`; accumulation keeps `use_dsp="no"`.

The routed netlist contains exactly 1,216 FFs for each of the three narrowed
matrices, versus 2,048 each in the baseline. See
[candidate register inventory](candidate_registers.csv). The remaining FF
differences include changed control replication and automatic integrated
merging of identical MSU sign bits. MSU RTL still accepts arbitrary INT32
values when independently instantiated; it was not specialized or truncated.

## Comparable implementation measurements

Both columns use the byte-identical prior accepted `implement.tcl` flow:
Vivado 2022.2, xc7z020clg484-1, production speed file 1.12, integrated
`sparse_tensor_core_top`, out-of-context synthesis, one 10.000 ns clock, one
synthesis thread and two implementation threads. Placement, pre-route physical
optimization and routing use their original default directives. The baseline
was freshly rebuilt and reproduces the retained accepted resource/slack values.

| Metric | Fresh 32-bit baseline | Isolated 19-bit TC | Change |
|---|---:|---:|---:|
| Post-synthesis LUTs | 12,803 | 10,146 | -2,657 |
| **Post-route LUTs** | **12,769** | **10,101** | **-2,668 (-20.89%)** |
| Post-route LUT device utilization | 24.00% | 18.99% | -5.01 percentage points |
| **Post-route FFs** | **15,519** | **11,295** | **-4,224 (-27.22%)** |
| Post-route FF device utilization | 14.59% | 10.62% | -3.97 percentage points |
| Occupied slices | 4,679 | 3,479 | -1,200 (-25.65%) |
| CARRY4 cells | 553 | 361 | -192 |
| DSP48E1 | 64 | 64 | Unchanged |
| RAMB36E1 / RAMB18E1 | 18 / 0 | 18 / 0 | Unchanged |
| Setup WNS at 10 ns | +0.296 ns | +0.004 ns | -0.292 ns |
| Hold WHS at 10 ns | +0.082 ns | +0.098 ns | Both pass |
| Fully routed nets | 21,827 | 17,067 | Both complete |
| DRC errors / BRAM control violations / route errors | 0 / 0 / 0 | 0 / 0 / 0 | Both pass |

Evidence: [baseline utilization](baseline/routed/utilization_routed.rpt),
[candidate utilization](candidate/routed/utilization_routed.rpt),
[resource CSV](resource_comparison.csv), and independent reopened
[baseline audit](audit/baseline/PASS.txt) / [candidate audit](audit/candidate/PASS.txt).

Hierarchical post-route attribution is:

| Module | Baseline LUTs | Candidate LUTs | Baseline FFs | Candidate FFs |
|---|---:|---:|---:|---:|
| TC | 5,254 | 3,146 | 6,605 | 4,045 |
| MSU | 1,588 | 1,064 | 4,406 | 2,738 |
| Bridge | 1,621 | 1,574 | 2,676 | 2,674 |
| DU/TIA | 2,138 | 2,149 | 794 | 800 |
| MLU | 2,169 | 2,170 | 1,038 | 1,038 |

Source changes are confined to TC despite some changed integrated attribution.
Cross-hierarchy LUT packing means child LUT totals need not equal the top total.
Whole-design resource counts are the primary comparison.

## Timing interpretation

The worst paths remain shared control paths, not the narrowed accumulator
carry chain. Both reports use slow-corner setup and 0.035 ns clock uncertainty.

| Property | Baseline | Candidate |
|---|---|---|
| Startpoint | Bridge `head_present_q_reg_rep__2/C` | Bridge `state_q_reg[meta_count][0]/C` |
| Endpoint | TC `tail_reg[4][2][8]/CE` | TC `result_q_reg[0][0][8]/CE` |
| Data path delay | 9.415 ns | 9.707 ns |
| Logic / route delay | 1.417 / 7.998 ns | 2.892 / 6.815 ns |
| Logic levels | 6 LUT levels | 13: 8 CARRY4 and 5 LUTs |
| Final enable fanout | 2,048 | 1,216 |

The candidate path crosses metadata/result readiness and enable logic. Its
eight CARRY4 cells are in that control path, not a remaining 32-bit TC data
accumulator. See [baseline paths](baseline/routed/critical_paths.rpt) and
[candidate paths](candidate/routed/critical_paths.rpt).

The identical extra `AggressiveExplore` physical optimization followed by
`Explore` routing leaves both resource counts and setup/hold slack unchanged.
See [refinement script](refine.tcl), [baseline metrics](baseline/refined/metrics.csv)
and [candidate metrics](candidate/refined/metrics.csv). It is not evidence of
additional timing margin. No tighter clock or placement-seed search was run.

These are internal FPGA OOC post-route results. The original flow has no board
input/output delays or HD.CLK_SRC specification. No board-level timing,
bitstream execution, ASIC PPA, power estimate or power measurement is claimed.

## Functional and cycle validation

The original unit suite was run before integration on the isolated baseline,
then on the candidate. Each run passes the unmodified tests:

| Check | Observed result on each version |
|---|---|
| MLU unit | 16,708 C/SV records; 145 resets; 128 rejected edges |
| DU/TIA unit | 3,292 packets |
| Bridge unit | 19,147 C/SV rows; 7,156 rejected edges; 13 resets |
| TC compatible C windows | 21,032 records; 1,366 publications; 6 malformed offers; 1 full-credit rejection |
| Original TC comparison | PASS |
| MSU unit | 8,683 cycles; 676 accepts; 5,394 beats; 673 completions; 42 faults; 8 resets |
| Original integration | 369 completed tiles; 3,542 issued packets; 2,987 write beats; 77 resets |
| Unstalled dense | 24 tiles; all 23 intervals II=8; k=7+3 publication |
| Unstalled mixed | 27 tiles; all 26 intervals II=8; k=7+3 publication |
| Original integration summaries | All 50 lines identical to the accepted baseline |

Logs: [baseline units](baseline/regression_native/units.log),
[baseline integration](baseline/regression_native/top.log),
[candidate units](candidate/regression_native/units.log), and
[candidate integration](candidate/regression_native/top.log).

Additional standalone verification uses modeled upstream/downstream signals:

- The unchanged prior equivalence test compares pre/post-edge outputs, events,
  wide logical accumulator/tail state and controls against the preserved 32-bit
  baseline, with an independent GEMM/publication scoreboard. It passes 89,595
  edges, all 65,536 A/B bitmap pairs, 82,299 accepted slices, 10,080 consumed
  results, 10,145 publications, 3,823 malformed edges, 1,766 full-credit rejects,
  178 resets, 9,892 simultaneous input/output transfers and 54,909 stored zeros.
  The original additional-test seed remains `7a913b65`.
- The new bound test passes 1,024 dense indexed tiles covering all 65,536 signed
  INT8 operand pairs, each accumulated eight times. The positive +131072 and
  negative -130048 endpoints are checked as full INT32 results. All 1,023 tile
  intervals are eight edges; every publication is k=7+3. No original test was
  weakened to accommodate the narrower representation.

See [extra-unit PASS](candidate/equivalence/PASS.txt) and
[test source](tb_tc19_bounds.sv).

System workload validation comprises **18 runs, each checking all 288 tiles**:
nine RTL runs and nine functional simulations of netlists exported from the
selected routed checkpoints. The unchanged random full-range workload runs in
dense/hybrid/dual on both versions; an additional directed bound workload runs
in all three modes on candidate RTL and netlist. The extra test includes
all-negative products yielding the positive bound, mixed-sign products yielding
the negative bound, cancellation and alternating signed extremes. All check
signed GEMM, writeback data/address/order, completion timing and sustained II=8.

Driven inputs, handshake cycles and accepted read/write transfers match between
the compared runs. Scoreboards independently check metadata as well. Full
baseline/candidate RTL transaction files also match byte-for-byte for all three
unchanged workloads. Raw traces and [trace identity CSV](trace_identity.csv)
are retained. The netlist simulations are functional, without SDF; post-route
STA separately verifies the clock requirement.

The aggregate [validation PASS](validation.PASS.txt) verifies all results and
source integrity. The [artifact manifest](artifact_manifest.csv) records the
selected checkpoints, exports, reports, scripts and evidence hashes.

## Actual commands and reproducibility

Run from `C:/Users/Jason/Desktop/TC` unless otherwise indicated:

```powershell
./experiments/tc19_20261122/regress.ps1 -Variant baseline -RunName regression_native
./experiments/tc19_20261122/regress.ps1 -Variant candidate -RunName regression_native
./experiments/tc19_20261122/run_equivalence.ps1
./experiments/tc19_20261122/run_workload.ps1 -Variant baseline -Kind rtl
./experiments/tc19_20261122/run_workload.ps1 -Variant candidate -Kind rtl
./experiments/tc19_20261122/run_workload.ps1 -Variant candidate -Kind rtl -Bounds
./experiments/tc19_20261122/run_workload.ps1 -Variant baseline -Kind functional
./experiments/tc19_20261122/run_workload.ps1 -Variant candidate -Kind functional
./experiments/tc19_20261122/run_workload.ps1 -Variant candidate -Kind functional -Bounds
./experiments/tc19_20261122/check_results.ps1
```

The implementation commands ran from `experiments/tc19_20261122`:

```powershell
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log baseline_implementation.log -source implement.tcl -tclargs baseline baseline/routed
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log candidate_implementation.log -source implement.tcl -tclargs candidate candidate/routed
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log audit.log -source audit.tcl -tclargs baseline/routed/routed.dcp candidate/routed/routed.dcp audit
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log refine.log -source refine.tcl
```

The initial sandbox ModelSim launch failed before simulation with the known
32-bit Windows system-DLL relocation error. All accepted native runs used
approved execution outside that sandbox. This startup failure is not counted
as a regression pass. ModelSim Intel FPGA Edition 2020.1 runs original/extra
unit tests; Vivado 2022.2 xsim runs the system/netlist workloads.

Existing result directories are intentionally protected. Use fresh `RunName`
values for regression/workload repeats and fresh implementation/audit output
directories. For a complete replay including the fixed-path equivalence and
refinement launchers, use a fresh copy of this experiment's source/scripts.
Do not overwrite the accepted snapshots, checkpoints or evidence.

## Files created and modified

All task-created files are inside `experiments/tc19_20261122/`:

- `baseline/src/` and `candidate/src/`: 93-file source/reference/test snapshots
  plus byte-identical expanded C vectors. Only candidate TC differs; the
  complete paths and hashes are in `source_manifest.csv`.
- `README.md`, `REPORT.md`, `.gitignore`, `rtl.diff`, `baseline_manifest.csv`,
  `source_manifest.csv`, `initial_status.txt`, `initial_head.txt`,
  `existing_docs.csv`, `AGENTS.initial.txt`, `expected_top_summary.txt`.
- `regress.ps1`, `implement.tcl`, `audit.tcl`, `refine.tcl`,
  `check_integrity.ps1`, `check_results.ps1`, `run_equivalence.ps1`,
  `equivalence.do`, `tb_pre_route_equiv.sv`, `tb_tc19_bounds.sv`,
  `tb_power.sv`, `tb_tc19_system.sv`, `run_workload.ps1`.
- Per-version regression, implementation, refinement, RTL/netlist workload
  reports, logs and traces; independent `audit/` reports; equivalence logs;
  resource/trace/register CSVs and validation/integrity/artifact manifests.
  Generated simulator libraries, waveforms, netlists and checkpoints remain
  local build artifacts and do not replace historical evidence.

No existing production file was modified. The user's initial AGENTS.md edit is
preserved, not part of this task's change set.
