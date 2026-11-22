# Operand-route experiment — 2026-11-22

## Disposition

Completed with the user-authorized shared DU/TIA repair: the operand-route
candidate reduces integrated post-route LUTs by **43.3%**, passes the same
**100 MHz** audit as the baseline, and lowers estimated total on-chip power by
**19.7% dense, 12.7% hybrid, and 12.9% dual**. Both repaired routed functional
netlists pass all three complete power workloads. These are workload-driven
Vivado estimates with functional SAIF, not timing/glitch-complete or board power
measurements. Sparse DSP power increases slightly, while the overall design
consumes less estimated power.

During power validation, both original post-route netlists rejected legal sparse
traffic because of a DU/TIA RTL-to-synthesis discrepancy. The original RTL tests
had passed; they did not establish netlist correctness. The shared repair is
applied only to two additional isolated snapshots. The original routes, failures,
and measurements remain preserved as historical evidence. See
[diagnosis and repair](power/du_repair/README.md).

Production remains on `main`, commit
`2458bf6962ea6946d820276a0faba0e00e6fe5e5`; no production RTL or project file
has been changed, and no commit, merge, or push has been performed.

## 100 MHz power comparison with the shared DU/TIA repair

Both columns below include the identical repaired DU/TIA. Only the TC operand
routing architecture differs between them. Vivado 2022.2 `report_power` opens
each new routed checkpoint and imports its validated functional-netlist SAIF.
The process is typical, junction temperature is fixed at 50 C, and VCCINT,
VCCBRAM, and VCCAUX are 1.0 V, 1.0 V, and 1.8 V respectively.

| Workload | Baseline total W | Candidate total W | Total change | Baseline dynamic W | Candidate dynamic W | Dynamic change |
|---|---:|---:|---:|---:|---:|---:|
| Dense | 0.714 | 0.573 | **-19.7%** | 0.562 | 0.422 | **-24.9%** |
| Hybrid | 0.574 | 0.501 | **-12.7%** | 0.422 | 0.350 | **-17.1%** |
| Dual | 0.567 | 0.494 | **-12.9%** | 0.416 | 0.343 | **-17.5%** |

Device static power is 0.151 W in all six reports. Vivado rounds total, static,
and dynamic figures independently to 1 mW, so their displayed sums can differ
by 1 mW. Percentages above use the displayed report values and are approximate.
At the validated eight-cycle tile interval, dynamic energy per tile changes
from 44.96 to 33.76 nJ dense, 33.76 to 28.00 nJ hybrid, and 33.28 to 27.44 nJ dual.

The estimated savings come primarily from logic and interconnect. The user's
concern about a possible multiplier-power tradeoff is visible in sparse modes:

| Workload | DSP mW, baseline -> candidate | Slice logic mW | Signals mW | TC hierarchy dynamic mW |
|---|---:|---:|---:|---:|
| Dense | 71 -> 71 | 146 -> 102 | 225 -> 134 | 338 -> 205 |
| Hybrid | **24 -> 31** | 106 -> 86 | 179 -> 124 | 215 -> 142 |
| Dual | **24 -> 30** | 103 -> 82 | 175 -> 121 | 210 -> 138 |

The sparse DSP increase is 7 mW hybrid and 6 mW dual. The logic/interconnect
savings exceed this increase; total dynamic power still falls by 72 mW and
73 mW respectively. Both versions contain 64 DSPs, but resource count alone
does not describe switching power. Hierarchy attribution and physical routing
also change outside TC under integrated implementation; whole-design power is
the primary comparison. BRAM power remains 64 mW in every case.

### Workload identity and validation

Each of the six repaired RTL and six routed functional simulations checks
288 independent tiles against a signed GEMM oracle, including every output
value, address/metadata, ordering, status, and tile II=8. All pass. The same
seed `51a7c0de` generates full-range signed INT8 values, including stored zeros.
Dense retains all coordinates; hybrid uses approximately 50% A retention and
legal 2:4 B masks; dual independently retains approximately 50% of A and B.
External memory responses and write acceptance have no injected stalls.
This is a sustained synthetic workload, not an application-specific trace.

Every capture uses the same 100 MHz clock and window from 2,000 to 22,480 ns:
20.480 us, 2,048 cycles, and exactly 256 completed tiles. Reset, warmup, and
final drain are excluded. The driven input/handshake traces match the original
baseline and both repaired RTL/netlist variants for each workload. Independent
scoreboards check all valid outputs even where unused netlist buses differ.
Source hashes confirm the shared repair and unchanged reference/test files.
See [final validation](power/du_repair/validation.PASS.txt),
[trace identity](power/du_repair/trace_identity.csv),
[source manifest](power/du_repair/source_manifest.csv), and
[artifact hashes](power/du_repair/artifact_manifest.csv).

### Annotation coverage and interpretation limits

- Baseline annotation: **49,063 / 49,063 nets (100%)** for every workload.
- Candidate annotation: **38,367 / 38,374 nets (99.9818%)** for every workload.
  Seven generated DU/TIA net names contain literal `(null)` and are rejected by
  Vivado's SAIF parser. Only those records are omitted from the import copy;
  they use vectorless propagation. Raw SAIF and the exact
  [excluded records](power/du_repair/candidate_v2/functional/dense/excluded_saif_nets.txt)
  are preserved. All remaining activity counts are unchanged.
- The accepted simulations use functional netlists exported from the routed
  checkpoints. They do **not** load SDF and do not reproduce routed-delay glitches.
  The initial full SDF attempts did not finish elaboration after more than
  15 minutes; their exports/logs are retained and are not counted as passing
  simulations. STA separately verifies internal 100 MHz timing.
- Junction temperature is fixed; Vivado back-calculates ambient despite the
  script's initial 25 C ambient setting. Effective ambient is 41.8/43.4 C dense,
  43.4/44.2 C hybrid, and 43.5/44.3 C dual (baseline/candidate). These are model
  assumptions, not board temperatures.
- The integrated design is OOC. Actual board I/O loads, clock-buffer integration,
  external memory, regulators, and board power are outside this estimate.
  Port-connectivity warnings and clock-SAIF-ignore warnings are retained;
  frequency comes from the identical explicit 10 ns clock constraints.

The data supports lower modeled total power for these three workloads. It does
not establish an exact silicon/board reduction or every possible sparsity/data
distribution. See the [full methodology](power/README.md),
[power component CSV](power/du_repair/power_summary.csv), and
[comparison CSV](power/du_repair/power_comparison.csv).

The six primary power reports are:

| Workload | Baseline | Candidate |
|---|---|---|
| Dense | [Report](power/du_repair/baseline/reports/functional_filtered/dense/power.rpt) | [Report](power/du_repair/candidate_v2/reports/functional_filtered/dense/power.rpt) |
| Hybrid | [Report](power/du_repair/baseline/reports/functional_filtered/hybrid/power.rpt) | [Report](power/du_repair/candidate_v2/reports/functional_filtered/hybrid/power.rpt) |
| Dual | [Report](power/du_repair/baseline/reports/functional_filtered/dual/power.rpt) | [Report](power/du_repair/candidate_v2/reports/functional_filtered/dual/power.rpt) |

For provenance, the original unrepaired dense-only estimates were 0.714/0.577 W
total and 0.563/0.426 W dynamic (baseline/candidate). Those older reports remain
under `power/{baseline,candidate_v2}/reports/functional_net_saif_filtered/dense/`.
Original hybrid/dual failed or incomplete captures are excluded; they are never
combined with the repaired comparison above.

## Repaired comparison: implementation and validation

Both new snapshots under `power/du_repair/` contain the same DU/TIA correction.
The baseline TC is unchanged; the candidate TC is byte-identical to the original
64-DSP `candidate_v2`. The correction builds the S1/S2 payloads in plain packed
structs and writes the selected union once. It preserves the decode algorithm,
packet layout, reset, four DU/TIA stages, TC II=8, and k=7+3 publication.
See [the focused DU/TIA diff](power/du_repair/du_tia.diff).

The original standalone synthesized DU/TIA reproduces the sparse-index failure.
The repaired standalone netlist passes all 65,536 A/B bitmap pairs, 6,144 hybrid
cases, mixed randomized offers, and in-flight resets. Both repaired integrated
RTL variants pass all unchanged original unit and integration suites, including
all 50 identical top summaries. Their three power-workload RTL transaction traces
are byte-identical to the original baseline. No golden test or assertion changed.
See [baseline regression](power/du_repair/baseline/regression/PASS.txt),
[candidate regression](power/du_repair/candidate_v2/regression/PASS.txt), and
[diagnosis and unit evidence](power/du_repair/README.md).

The two fresh implementations use exactly the original 100 MHz flow:

| Metric | Original TC + repaired DU/TIA | Operand-route TC + repaired DU/TIA |
|---|---:|---:|
| Synthesized LUTs | 22,797 | 12,803 |
| **Post-route LUTs** | **22,523** | **12,769 (-43.3%)** |
| Post-route LUT utilization | 42.34% | 24.00% |
| TC hierarchy LUTs | 15,652 | 5,254 (-66.4%) |
| Post-route FFs | 16,281 | 15,519 |
| DSP48E1 / RAMB36E1 | 64 / 18 | 64 / 18 |
| Setup WNS, 10 ns | +0.199 ns | +0.296 ns |
| Hold WHS, 10 ns | +0.096 ns | +0.082 ns |

Thus the area benefit survives the shared correction, and neither new route
fails 100 MHz internal setup/hold timing. The 97 ps setup-margin difference
does not establish a substantial clock speedup. The new worst paths remain
control paths: baseline Bridge `meta_count[1]` to MSU result CE (13 logic levels,
9.512 ns data delay, 73.6% routing), and candidate Bridge `head_present_q_reg_rep__2`
to TC `tail_reg[4][2][8]/CE` (6 levels, 9.415 ns data delay, 84.9% routing).
Both use slow-corner setup analysis and 35 ps uncertainty. The same OOC/external
clock and board-I/O limitations apply to both.

Evidence: [baseline resources](power/du_repair/baseline/routed/utilization_routed.rpt),
[candidate resources](power/du_repair/candidate_v2/routed/utilization_routed.rpt),
[baseline timing](power/du_repair/baseline/routed/timing_summary.rpt),
[candidate timing](power/du_repair/candidate_v2/routed/timing_summary.rpt),
[baseline paths](power/du_repair/baseline/routed/critical_paths.rpt), and
[candidate paths](power/du_repair/candidate_v2/routed/critical_paths.rpt).

The independent reopened-checkpoint audit passes both variants: routing complete,
no DRC errors, 64 DSPs with AREG/BREG/MREG=0 and PREG=1, and 18 unchanged SDP BRAMs.
Fixed-route clock-boundary checks pass at 9.810 ns / 101.9368 MHz for the baseline
and 9.710 ns / 102.9866 MHz for the candidate; the adjacent 10 ps faster points
fail setup. This is approximately a 1% boundary difference in one implementation
pair, not evidence of a large speedup or board sign-off. See the
[new audit](power/du_repair/audit/audit_summary.txt) and
[period sweep](power/du_repair/audit/periods.csv).

## Original TC experiment: scope and implementation

In the original experiment, only `tensor_core_sv/outer_product_core.sv` changes.
The baseline, first attempt, and refined candidate have separate source trees.
All 93 baseline source/reference/test files have SHA-256 provenance; the
candidate's only source delta is the TC. See [source integrity](source_integrity.csv),
[RTL diff](rtl.diff), and [candidate source](candidate_v2/src/tensor_core_sv/outer_product_core.sv).

The pipeline changes as follows; each vertical bar is a register boundary:

```text
Baseline:  packed operands -> multiply | product route | accumulate | publish
Candidate: packed operands -> operand route | multiply | accumulate | publish
```

The candidate restores A[:,k] and B[k,:] to original coordinates independently,
zero-fills missing entries, and uses fixed-coordinate products. It replaces
128 16-bit product-routing destinations with 16 8-bit operand-routing
destinations. This is a structural description, not a direct LUT-count formula:
decode sharing, register enables, arithmetic mapping, and physical optimization
also affect the measured resources.

Presence masks remain separate from values. Stored zeros retain their original
valid-coordinate semantics. Invalid metadata or a full-credit offer still
freezes the entire edge, including an otherwise possible result transfer.
The packet layout, ports, result ordering, two result slots, signed INT8/INT32
arithmetic, reset behavior, and old-state credit decisions are preserved.
There is no extra pipeline stage: tile II remains 8 and legal k=7 publication
remains three advancing edges later. Existing `tick_info.mul`/`route` observations
keep their exact stage timing; their historical names no longer identify the
physical operation in the experimental pipeline.

The first attempt (`candidate/`) passed all functional checks but Vivado inferred
128 DSPs: it duplicated multiply-add cones alongside the registered products.
The refined `candidate_v2/` explicitly marks each INT32 fabric sum with
`use_dsp = "no"`, while keeping `use_dsp = "yes"` on multiplication. Both attempts
and their reports are retained. The extra-DSP attempt is not the selected result.

## Original physical measurements before the DU/TIA repair

| Metric | Baseline | Refined candidate | Change |
|---|---:|---:|---:|
| Integrated LUTs, synthesized | 22,855 | 12,887 | -43.6% |
| **Integrated LUTs, post-route** | **22,581** | **12,857** | **-9,724 (-43.1%)** |
| Device LUT utilization, post-route | 42.45% | 24.17% | -18.28 percentage points |
| TC hierarchy LUTs, post-route | 15,652 | 5,256 | -10,396 (-66.4%) |
| Integrated FFs, post-route | 16,281 | 15,519 | -762 (-4.7%) |
| DSP48E1s | 64 | 64 | Unchanged |
| RAMB36E1s / RAMB18E1s | 18 / 0 | 18 / 0 | Unchanged |
| Setup WNS at 10.000 ns | +0.162 ns | +0.185 ns | +0.023 ns |
| Hold WHS at 10.000 ns | +0.096 ns | +0.084 ns | Both pass |
| Pulse-width slack at 10.000 ns | +4.020 ns | +4.020 ns | Both pass |
| Setup / hold / pulse-width failing endpoints | 0 / 0 / 0 | 0 / 0 / 0 | Both pass |
| Shortest tested passing fixed-route period | 9.840 ns | 9.820 ns | Effectively unchanged |
| Frequency at that passing period | 101.626 MHz | 101.833 MHz | +0.20%; not a meaningful speedup claim |
| Power | See power extension | See power extension | Original sparse captures fail validation |

The area benefit is substantial; the setup-margin difference is only 23 ps and
does not establish a meaningful frequency improvement. There is no observed
clock regression in this implementation pair. The hierarchy attribution changes
outside the TC despite unchanged source: for example, Bridge LUTs increase from
984 to 1,621 under integrated synthesis/physical optimization. Therefore the
whole-design reduction (9,724 LUTs) is the primary area result, not the larger
TC hierarchy difference alone.

The retained first attempt uses 13,125 LUTs, 15,707 FFs, **128 DSPs**, and 18 BRAMs
post-route, with +0.250 ns setup and +0.082 ns hold slack at 100 MHz. It is not
selected because it doubles DSP usage. Its reports remain under `candidate/routed/`.

Evidence: [baseline resources](baseline/routed/utilization_routed.rpt),
[candidate resources](candidate_v2/routed/utilization_routed.rpt),
[baseline hierarchy](baseline/routed/hierarchy.rpt),
[candidate hierarchy](candidate_v2/routed/hierarchy.rpt),
[baseline timing](baseline/routed/timing_summary.rpt),
[candidate timing](candidate_v2/routed/timing_summary.rpt).

All implementation numbers use Vivado 2022.2, `xc7z020clg484-1`, production speed
file 1.12, integrated `sparse_tensor_core_top`, out-of-context synthesis, and a
single 10.000 ns clock. Source order, one synthesis thread, two implementation
threads, default placement, default physical optimization, and default routing
are identical. This is a full integrated comparison, not a TC-only area estimate.
The complete flow is [implement.tcl](implement.tcl).

These are internal FPGA post-route static-timing results. No board input/output
delay constraints or `HD.CLK_SRC` value are added. The OOC clock and external-port
limitations also apply to the baseline. No board measurement, bitstream test,
ASIC timing, or power measurement is claimed. Clock-boundary checks change the
clock on a fixed routed checkpoint; they do not rerun implementation at the
tighter period. A single implementation per variant does not establish a
distribution across placement seeds or strategies.

## Original critical paths and clock interpretation

Both worst setup paths are reported at the slow process corner using the same
10.000 ns clock and 0.035 ns clock uncertainty. They are control paths with large
fanout, rather than the operand-routing or multiplier data path:

| Property | Baseline | Refined candidate |
|---|---|---|
| Startpoint | `u_bridge/state_q_reg[meta_count][1]/C` | `u_bridge/state_q_reg[meta_count][0]/C` |
| Endpoint | `u_msu/result_q_reg[0][4][6][28]/CE` | `u_tensor_core/result_reg[3][5][18]/CE` |
| Data delay | 9.549 ns | 9.526 ns |
| Logic / route delay | 2.291 / 7.258 ns | 2.468 / 7.058 ns |
| Route fraction | 76.0% | 74.1% |
| Logic levels | 13: 8 CARRY4, 5 LUTs | 13: 8 CARRY4, 5 LUTs |
| Final control-net fanout | 2,144 | 2,048 |
| Final control-net route delay | 2.757 ns | 2.211 ns |

See [baseline full paths](baseline/routed/critical_paths.rpt) and
[candidate full paths](candidate_v2/routed/critical_paths.rpt). The data supports
operand routing as an area improvement without an observed clock penalty here.
It does not show that the full design can run substantially faster: the shared
control path still dominates. No Bridge/MSU optimization is included in this trial.

There is a local tradeoff: restricting both startpoints and endpoints to TC
sequential cells gives +0.576 ns worst slack in the baseline and +0.453 ns in
the candidate. The candidate's local path starts at
`operand_q_reg[a_value][7][2]/C` and ends at DSP
`g_row[7].g_col[6].p_reg/A[2]`; operand distribution to the DSPs consumes margin.
That local margin is 123 ps smaller, but still larger than the whole-design
margin. Thus this experiment does not claim every TC path becomes faster.
See [baseline TC paths](audit/baseline/tc_internal_paths.rpt) and
[candidate TC paths](audit/candidate_v2/tc_internal_paths.rpt).

The independent audit reopens the saved routed checkpoints and applies the
unchanged production `check_bram_100mhz` procedure. Both pass: 64 DSP48E1s with
AREG/BREG/MREG=0 and PREG=1; 18 unchanged 72-bit SDP RAMB36E1s; no DRC errors;
no BRAM-control REQP-1839 violations; complete routing and no routing errors.
The baseline has 31,810 fully routed routable nets and the candidate has 21,883.
Both retain the same 193 DRC warnings (128 DPIP-1, 64 DPOP-2, 1 ZPS7-1), so
"no DRC errors" does not mean warning-free board sign-off.

Adjacent 10 ps fixed-route period checks give:

| Variant | Period | Frequency | Setup slack | Hold slack | Result |
|---|---:|---:|---:|---:|---|
| Baseline | 9.840 ns | 101.6260 MHz | +0.002 ns | +0.096 ns | PASS |
| Baseline | 9.830 ns | 101.7294 MHz | -0.008 ns | +0.096 ns | FAIL setup |
| Candidate v2 | 9.820 ns | 101.8330 MHz | +0.005 ns | +0.084 ns | PASS |
| Candidate v2 | 9.810 ns | 101.9368 MHz | -0.005 ns | +0.084 ns | FAIL setup |

The failing adjacent points deliberately locate the timing boundary. They do
not invalidate the successful 100 MHz runs. Both passing-point full timing
summaries also pass pulse-width checks. Evidence: [audit summary](audit/audit_summary.txt),
[baseline audit](audit/baseline/PASS.txt), [candidate audit](audit/candidate_v2/PASS.txt),
[clock-period measurements](audit/periods.csv), and [audit log](audit.log).

## Original RTL functional verification

The unchanged original unit suites run before integration for each variant.
All three source snapshots passed the original suites. The refined candidate
also passed the additional standalone common-stimulus comparison against the
unchanged production core, with an independent GEMM and publication-timing oracle.
This is simulation coverage, not formal equivalence proof.

| Check | Observed result |
|---|---|
| MLU C/SV unit | 16,708 records; 145 resets; 128 rejected edges; PASS |
| DU/TIA | 3,292 packets; PASS |
| Bridge C/SV unit | 19,147 records; 7,156 rejected edges; 13 resets; PASS |
| TC compatible C windows | 21,032 records; 1,366 publications; 6 malformed offers; 1 full-credit reject; PASS |
| Existing TC comparison/GEMM | All existing patterns; PASS |
| MSU C/SV unit | 8,683 cycles; 676 accepted results; 5,394 beats; 673 completions; 42 faults; 8 resets; PASS |
| Full integration | 369 completed tiles; 3,542 issued packets; 2,987 write beats; 77 resets; PASS |
| Integration trace comparison | All 50 accepted summary lines identical to baseline |
| Unstalled dense stream | 24 tiles; 23 intervals at II=8; k=7 to publication=3 |
| Unstalled mixed stream | 27 tiles; 26 intervals at II=8; k=7 to publication=3 |
| Additional A/B bitmap coverage | All 65,536 legal subset pairs, including empty/full vectors |
| Additional edge comparison | 89,595 edges; 82,299 accepted slices; 10,080 consumed GEMM results; PASS |
| Additional exceptional traffic | 3,823 malformed offers; 1,766 full-credit rejects; 178 reset edges |
| Additional overlap/data cases | 9,892 simultaneous input/result transfers; 54,909 stored-zero A entries |

The additional test uses fixed seed `7a913b65`, arbitrary nonzero padding, positive
and negative INT8 extremes, bubbles, backpressure, in-flight resets, and a directed
full-credit rejection with a requested simultaneous result pop. It compares
public outputs and tick observations before and after every edge, plus accumulator,
result-tail, and credit state. There were 10,145 publications; resets intentionally
discard some queued results, so this differs from the consumed-result count.
The integration seed remains the original `91e10da5`.

Evidence:

- [Baseline units](baseline/verification/units.log), [baseline integration](baseline/verification/top.log).
- [Candidate units](candidate_v2/verification/units.log), [candidate integration](candidate_v2/verification/top.log), [regression PASS](candidate_v2/verification/PASS.txt).
- [Additional comparison log](candidate_v2/equivalence/equivalence.log), [additional testbench](tb_pre_route_equiv.sv).
- [First-attempt regression](candidate/verification/PASS.txt) and [first-attempt source](candidate/src/tensor_core_sv/outer_product_core.sv).

No golden model, existing vector, expected result, assertion, random seed, or
existing testbench was altered. The extra comparison generates a baseline
compilation adapter that renames only the module declaration, allowing both
implementations to run under the same stimulus.

## Reproduction and execution notes

The later power extension uses additional scripts and new source snapshots;
its reproduction commands are in [the DU/TIA repair record](power/du_repair/README.md#reproduction-commands).

The baseline used its copied original regression launcher. The candidates used
the experiment launcher, which invokes the same unchanged `run_units.do` and
`run_top.do`, then checks PASS markers, protected file hashes, and exact summary
equality. From the experiment directory, the successful commands were:

```powershell
# Original baseline launcher, automatically changes to baseline/src.
./baseline/src/integration_sv/sim/run_regression.ps1 -Vsim 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -OutputDir "$PWD/baseline/verification"
./simulate.ps1 -Variant candidate -RunName verification
./simulate.ps1 -Variant candidate_v2 -RunName verification
./run_equivalence.ps1 -Variant candidate_v2
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log baseline/implementation.log -source implement.tcl -tclargs baseline baseline/routed
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log candidate/implementation.log -source implement.tcl -tclargs candidate candidate/routed
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log candidate_v2/implementation.log -source implement.tcl -tclargs candidate_v2 candidate_v2/routed
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log audit.log -source audit.tcl -tclargs baseline/routed/routed.dcp candidate_v2/routed/routed.dcp audit
./check_integrity.ps1 -Variant candidate_v2
```

Choose fresh RunName/output paths when repeating; do not overwrite the accepted
evidence. [README](README.md) provides a repeat-run command sequence including the
independent audit. The equivalence launcher explicitly refreshes only its own
logs and compilation scratch.

The 32-bit ModelSim executable failed sandbox startup with a Windows system-DLL
relocation error. Successful simulator runs used approved execution outside the
sandbox. Initial setup also exposed two missing unit-local package copies in
the 91-file accepted manifest; their byte-identical production copies were added
to all snapshots and recorded in `extra_manifest.csv`. A first additional-test
launcher attempt resolved ModelSim's `info script` to its internal Tcl file;
using the explicitly selected experiment working directory fixed that launcher.
These were setup failures, not waived RTL test failures. The related logs remain
available. Vivado's TclStore write warning does not prevent the implementation;
OOC external-port and clock assumptions are recorded with the timing limitations.

## Created and modified files

All additions and edits are confined to `experiments/pre_route_20261122/`.
No pre-existing production file is modified. The created artifacts are:

- Three 93-file source snapshots under `baseline/src/`, `candidate/src/`, and
  `candidate_v2/src/`; only the two experimental TC files differ from production.
- `README.md`, `REPORT.md`, `provenance.txt`, `.gitignore`, `rtl.diff`, and
  `candidate/rtl.diff` for review and provenance.
- `baseline_manifest.csv`, `extra_manifest.csv`, `expected_top_summary.txt`,
  `source_integrity.csv`, and `integrity.PASS.txt` for immutable inputs and checks.
- `simulate.ps1`, `implement.tcl`, `audit.tcl`, and `check_integrity.ps1` for the flow.
- `tb_pre_route_equiv.sv`, `equivalence.do`, and `run_equivalence.ps1` for the extra unit check.
- Per-variant regression logs, equivalence logs, implementation logs, text reports,
  and local checkpoints; independent reopened-checkpoint audit reports under `audit/`.
- `power/tb_power.sv`, workload/simulation/export/SAIF/report scripts and original
  captures; original dense power reports and rejected sparse simulation logs.
- `power/du_repair/du_tia_fixed.sv`, `du_tia.diff`, `du_gate.sv`, `tb_du_gate.sv`,
  unit synthesis/simulation scripts and original-failure/repaired-pass evidence.
- Two further 93-file source snapshots under `power/du_repair/{baseline,candidate_v2}/src/`,
  both with the identical DU/TIA repair; `source_manifest.csv` records all hashes.
- Repaired regression/implementation/power launchers, `summarize.ps1`, trace and
  artifact manifests, per-variant reports and local checkpoints under `power/du_repair/`.
- Updated experiment `README.md`, `REPORT.md`, and `power/README.md`; new
  `power/du_repair/README.md` documents the authorized scope expansion.

Tool work libraries, expanded raw vectors, and binary checkpoints are retained
locally and ignored by Git. Unchanged gzip vectors are retained for reconstruction.
