# Bridge packet FIFO in LUTRAM on the 19-bit core

Rejected at the user's 100 MHz internal OOC timing gate. One integrated route completed at 10.000 ns. Setup WNS was -0.049 ns, TNS was -0.719 ns across 32 failing endpoints, and hold WHS was +0.076 ns with zero hold failures. The production Bridge retains its rotating FIFO.

| Integrated post-route metric | 19-bit rotating FIFO | 19-bit LUTRAM FIFO |
|---|---:|---:|
| Slice LUTs, including memory | 10,101 | 8,462 |
| Slice FFs | 11,295 | 9,020 |
| Occupied slices | 3,479 | 2,947 |
| LUTs used as distributed RAM | 0 | 192 |
| DSP48E1 / RAMB36E1 | 64 / 18 | 64 / 18 |
| Setup WNS (ns) | +0.004 | -0.049 |
| Hold WHS (ns) | +0.098 | +0.076 |

The candidate saved 1,639 LUTs and 2,275 FFs. Its worst setup path runs from Bridge `state_q_reg[meta_count][0]` to the clock enable of TC `result_q_reg[0][1][12]`, through result readiness. It has 15 logic levels (8 CARRY4, 7 LUTs) and 9.760 ns data delay, including 7.069 ns routing. The final enable drives 1,216 loads. Both designs' worst setup paths start at the Bridge metadata count and end at a TC result enable. The candidate completed all 15,137 routable nets with zero routing errors.

Vivado 2022.2 used xc7z020clg484-1, speed file 1.12, slow-corner setup and one 10.000 ns internal clock. The candidate used a byte-identical copy of the [19-bit implementation flow](../tc19_20261122/implement.tcl). The baseline values come from the [source-matched baseline route](../tc19_20261122/candidate/routed/utilization_routed.rpt). The [candidate hierarchy](candidate/routed/hierarchy.rpt), [critical paths](candidate/routed/critical_paths.rpt), [timing summary](candidate/routed/timing_summary.rpt) and [independent audit log](audit.log) record this trial.

## Source and validation

The [candidate diff](bridge.diff) replaces rotating packet words with an eight-entry distributed RAM, a write pointer advanced on each committed arrival, and an asynchronous read at the registered head. Queue count masks empty reads. For full-state simulation, per-slot written flags expose reset values until each physical word has been written. The unit test observes the actual memory contents after that write, including stale slots after pop.

The [manifest](source_manifest.csv) covers the working tree's 93 source, reference and regression files and their isolated copies. Only `candidate/src/fifo_sv/du_tc_bridge.sv` differs. Production inputs matched the validated 19-bit snapshot. All files created for the trial are under this experiment directory, including the input snapshot, [regression logs](regression), physical reports, checkpoints, scripts and simulator build files.

- Original units passed, including the Bridge full-state C replay over 19,147 rows, 7,156 rejected edges and 13 resets. [Unit log](regression/units.log)
- Integration completed 369 tiles with 77 resets. Dense and mixed streams retained II=8 and publication three advancing edges after k=7. All 50 integration summary lines matched the baseline. [Integration summary](regression/top_summary.txt)
- The standalone synthesized LUTRAM Bridge passed 38,294 pre/post-edge interface comparisons over the original vectors. Native ModelSim and the original native Vivado/XSim launcher produced the accepted functional results. Initial sandbox and auxiliary simulator launches failed during startup, elaboration or vector argument handling. [Netlist replay](netlist_native/result.log)
- The negative integrated setup slack ended the trial. No additional route strategy or integrated routed-netlist workload was run.

## Commands

From this experiment directory, the following commands reproduce the runs. Use a fresh output location for each run. For a full replay, copy this directory's source and scripts under a new sibling experiment directory first.

```powershell
& ./candidate/src/integration_sv/sim/run_regression.ps1 -OutputDir "$PWD/regression"
$vivado = 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat'
& $vivado -mode batch -nojournal -log netlist_native.log -source ../mlu_bram_100mhz_20261118/bridge_netlist_check.tcl -tclargs candidate/src netlist_native
& $vivado -mode batch -nojournal -log implementation.log -source implement.tcl -tclargs candidate candidate/routed
& $vivado -mode batch -nojournal -log audit.log -source check_route.tcl -tclargs candidate/routed/routed.dcp audit
```
