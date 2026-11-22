# DSP multiply-accumulate trial from the production 19-bit core

**Rejected at 100 MHz.** The candidate kept II=8 in RTL simulation and implemented all 64 multiply-accumulate lanes in 64 DSP48E1s. The routed design missed setup by 65 ps. The experiment stopped after the first route and its independent checkpoint audit. The production 19-bit RTL remains the selected implementation.

## Post-route comparison

Both runs used the integrated out-of-context top, Vivado 2022.2, the xc7z020clg484-1, a 10.000 ns clock and the same implementation flow. Percentages use the production 19-bit design as the denominator.

| Whole-design metric | Production 19-bit | DSP MAC trial | Reduction |
|---|---:|---:|---:|
| Slice LUTs | 10,101 | 8,818 | 1,283 (12.70%) |
| Slice registers | 11,295 | 10,062 | 1,233 (10.92%) |
| Occupied slices | 3,479 | 3,171 | 308 (8.85%) |
| DSP48E1 | 64 | 64 | 0 |
| RAMB36E1 | 18 | 18 | 0 |
| Setup WNS | +0.004 ns | −0.065 ns | |
| Hold WHS | +0.098 ns | +0.082 ns | |

The reopened checkpoint had 25 failing setup endpoints and −0.694 ns total negative setup slack. All hold checks passed. The slow-corner worst setup path ran from Bridge metadata occupancy bit `u_bridge/state_q_reg[meta_count][1]` to the clock enable of MSU result bit `u_msu/result_q_reg[1][3][7][13]`. Of its 9.609 ns data delay, 6.965 ns came from routing. The final enable net drove 1,312 loads. All 15,660 routable nets were fully routed, and the audit passed the DSP, BRAM and DRC checks before rejecting timing. Integrated routed-netlist workload simulation was skipped at the timing stop condition. [19-bit baseline](../tc19_20261122/REPORT.md) · [Routed utilization](candidate/routed/utilization_routed.rpt) · [Audited timing](audit/timing_summary.rpt) · [Critical paths](audit/critical_paths.rpt) · [Checkpoint audit log](audit.log)

## Candidate

Each of the 64 lanes uses a signed INT8 multiplier, a registered product and a 19-bit signed running sum. At the first slice the lane loads the product, including zero for a missing coordinate. Later slices update the running sum only when the coordinate is present. A rejected edge holds both stages. The routed operand values already zero-fill absent coordinates. Presence masks still record stored zeros independently. A resettable validity bit gives the logical accumulator its immediate reset value until the first accepted accumulation overwrites every lane. A result can publish only after that overwrite. The two 19-bit result slots and their external INT32 sign extension retain their original behavior.

The working tree's 93 files matched the validated 19-bit production manifest before the trial. The [source manifest](source_manifest.csv) and [RTL diff](core.diff) identify the only implementation change, in the experiment's copy of `tensor_core_sv/outer_product_core.sv`. The baseline TC copy in this directory provides the direct reference for cycle comparisons. The original rotating Bridge is included in the candidate.

## Validation

The [standalone equivalence and bounds checks](candidate/equivalence/PASS.txt) compare state and ports to the 19-bit core and compare results to independent integer arithmetic. The 89,595-edge equivalence run includes all 65,536 pairs of A/B bitmaps, 178 resets, 3,823 malformed edges, 1,766 full-credit rejects and 9,892 simultaneous input/output transfers. The bounds test covers all 65,536 signed operand pairs across 1,024 tiles, checks both signed endpoints, and observes II=8 for all 1,023 intervals with publication three advancing edges after k=7.

The [original unit suite](regression/units.log) and [integration regression](regression/top_summary.txt) passed. All 50 top summary lines match the accepted baseline. Integration completed 369 tiles, issued 3,542 packets and accepted 2,987 write beats across 77 resets. The dense and mixed streams maintained II=8.

Standalone synthesis confirmed 64 DSP48E1 cells with MREG=1 and PREG=1. Integrated synthesis reports the multiply, product register, feedback addition and sum register in the same physical DSP in every lane. [Standalone synthesis](probe.log) and [integrated MAC inventory](inferred_macs.csv).

## Reproduction

Run these PowerShell commands in a fresh sibling copy of this experiment's inputs under `experiments/`. The equivalence runner uses native ModelSim and both preserved standalone tests. The implementation script is byte-identical to the original 19-bit flow. The experiment-local audit adapts the original DSP register checks to the requested MAC mapping.

```powershell
& ./run_equivalence.ps1
& ./candidate/src/integration_sv/sim/run_regression.ps1 -OutputDir "$PWD/regression"
$vivado = 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat'
& $vivado -mode batch -nojournal -log probe.log -source probe_core.tcl
& $vivado -mode batch -nojournal -log implementation.log -source implement.tcl -tclargs candidate candidate/routed
& $vivado -mode batch -nojournal -log audit.log -source check_mac_100mhz.tcl -tclargs candidate/routed/routed.dcp audit
```
