# Unified outer-product Tensor Core

> Historical November 21 experiment: the pipeline below multiplies before
> routing products. The [November 22 promotion](../../reports/verification/operand_route_main_20261122/README.md)
> subsequently moved operand routing before multiplication and repaired the
> shared DU/TIA. Current source paths and rebuilds therefore differ from this
> dated experiment. Its original RTL, measurements, and test results are retained.
> Later sparse-netlist validation exposed a DU/TIA mismatch in the original
> implementation; use the [repaired comparison](../pre_route_20261122/power/du_repair/README.md)
> for validated three-format netlist and power evidence.

This experiment targeted the previous BRAM/rotating FIFO production snapshot `7e40bf9`.
It replaces two compilation units in the integrated design. Compile
[`outer_product_core.sv`](outer_product_core.sv) and the local
[`sparse_tensor_core_top.sv`](sparse_tensor_core_top.sv) with the nine
original package and peripheral files listed in [implement.tcl](implement.tcl).
[rtl.diff](rtl.diff) compares the two design units to their production counterparts.

The shared core was subsequently promoted to `main`; see the
[promotion record](../../reports/verification/outer_main_20261121/README.md)
and [current TC contract](../../tensor_core_sv/README.md). References below to
the baseline or production comparator mean the pre-promotion implementation
with separate dense and sparse compute paths. The baseline reproduction
commands require that predecessor snapshot; current root regression scripts
select the shared core. Historical commit IDs are provenance and may not be
available in the rewritten public history.

## Packet and timing contract

The top adapter converts both operands before the FIFO writes its registered
word. For a dense k slice it forwards the original bytes, including zeros,
sets both counts to eight and assigns lane n the index n. For hybrid and dual
input it forwards the DU/TIA's decoded vectors. The Bridge's existing tag
still cross-checks the *source* format against its four-stage sideband on
arrival. The core port accepts only the two 92-bit indexed operands.

The core generates 64 registered signed INT8 products. The existing two
eight-way selection banks route columns and rows inside the ROUTE stage.
ACC uses the previous route register, clears absent coordinates on a tile's
first slice and accumulates in signed INT32. Publishing captures the previous
accumulator even when the next tile's first slice reaches ACC on the same edge.
A k=0 acceptance reserves one of two result slots. The producer consults
old-state credit before presenting valid. A malformed vector or an offer
without credit freezes computation and result consumption for that edge.

With k=0 accepted on edge 0 and k=7 on edge 7, the candidate publishes the
tile after edge 10. Its earliest output handshake is edge 11. With sufficient
credit, the next tile starts on edge 8, for any sequence of source formats.
Dense changes from k=7 + 15 to k=7 + 3 for publication. Source mode transitions
can overlap. DU latency, memory interfaces, Bridge credit/metadata ordering
and MSU writeback follow the production contract.

## Measured simulation results

| Standalone TC input, 24 tiles | Baseline cycles | Candidate cycles | Baseline start interval | Candidate start interval |
| --- | ---: | ---: | ---: | ---: |
| Dense | 576 | 196 | 24 | 8 |
| Full-count indexed | 196 | 196 | 8 | 8 |
| Alternating dense / full-count indexed | 432 | 196 | 12–24 | 8 |

[compare.log](compare.log) measures from the first accepted k=0 through the
final consumed result, inclusive. Both cores receive the same matrices, each
source presents the next packet whenever accepted, and both sinks stay ready.
The benchmark checks every signed result and every tile's publication cycle.

- The [baseline run](baseline_verified/PASS.txt) passed all five original units
  and the unchanged top regression. It verified the source and protected-file
  hashes against the accepted BRAM implementation.
- [tb_outer_core.sv](tb_outer_core.sv) replays the unchanged C trace from each
  reset through the first valid legacy dense offer (exclusive). These contiguous
  windows compare the original outer-product timing, readiness, status, both
  physical results, and tick events. [unit.log](unit.log) records 21,032
  comparable records, 1,366 publications and six malformed-vector rejections.
  A directed full-credit rejection additionally checks that a pending pop is
  frozen and the queued results subsequently drain.
- [tb_outer_top.sv](tb_outer_top.sv) is a separate version of the integration
  scoreboard for the new interface and timing. It retains the original matrix
  generator, seed, FIFO and metadata accounting, reset coverage, GAP/stall
  checks and byte-level writeback oracle. It independently packs every valid
  coordinate from the full input matrices and checks the adapted packet both
  at FIFO ingress and at TC acceptance. It checks k=7 + 3 publication for all
  modes, the credit-only ready equation, all nine mode pairs and mixed II=8.
  Extra no-stall dense (24 tiles) and mixed (27 tiles) phases check every
  successive tile start. [top.log](top.log) records 369 completed tiles and
  77 reset events. The runs also include partial transfers discarded by reset.

## Integrated FPGA implementation

Both runs use Vivado 2022.2, xc7z020clg484-1, OOC synthesis at 10.000 ns,
Default placement, Default physical optimization and Default routing. The
reference is the [rotating FIFO routed report](../mlu_bram_100mhz_20261118/rotating_fifo/flow/initial/utilization_routed.rpt).

| Post-route metric | BRAM production | Unified outer product |
| --- | ---: | ---: |
| Slice LUTs | 28,213 | 22,581 |
| Flip-flops | 19,852 | 16,281 |
| DSP48E1 | 128 | 64 |
| RAMB36E1 | 18 | 18 |
| Worst setup slack at 10 ns | +0.011 ns | +0.162 ns |
| Worst hold slack at 10 ns | +0.098 ns | +0.096 ns |
| Setup / hold failing endpoints | 0 / 0 | 0 / 0 |

The candidate saves 5,632 LUTs (19.96%), 3,571 FFs (17.99%) and 64 DSPs
(50%) at the integrated top. All 31,810 routable nets were fully routed with
zero routing errors. See the [utilization](routed/utilization_routed.rpt),
[hierarchy](routed/hierarchy.rpt), [timing](routed/timing_summary.rpt),
[route status](routed/route_status.rpt) and [DRC](routed/drc.rpt) reports.
DRC reports 192 DSP pipeline warnings and one missing-PS7 warning.

At the slow setup corner the production path runs from FIFO k[1] to a sparse
DSP clock enable (+0.011 ns). The candidate's [worst path](routed/critical_paths.rpt)
runs from Bridge metadata count to an MSU result-buffer clock enable
(+0.162 ns). It traverses eight CARRY4 cells and five LUTs. Of 9.549 ns data
delay, 7.258 ns is routing, including a 2,144-load enable. These are internal
FPGA timing results. Board-level I/O delays, board operation, power and ASIC
implementation are outside these measurements.

Reopening the same routed checkpoints and changing only the clock constraint
gives the following internal STA bounds at 10 ps resolution. The passing
points meet setup, hold and pulse-width checks. Both use the production OOC
clock assumptions, including the unset HD.CLK_SRC.

| Fixed route | Faster tested point that passed | Adjacent point that failed setup |
| --- | ---: | ---: |
| Production | 9.990 ns / 100.100 MHz | 9.980 ns / 100.200 MHz |
| Candidate | 9.840 ns / 101.626 MHz | 9.830 ns / 101.729 MHz |

[Measured points](clocks_verified/periods.csv) and the [passing candidate
timing summary](clocks_verified/candidate_longer.rpt) accompany the
[10 ns implementation log](implementation.log).

## Reproduction

From the production repository root in PowerShell, restore the existing TC
vector file with `./tools/restore_vectors.ps1` if the checkout contains only
the gzip copy. Use ModelSim on PATH and Vivado 2022.2.

```powershell
$trial = 'experiments/outer_product_20261121'
& ./tools/verify_bram_main.ps1 -OutputDir "$trial/baseline_repeat"
& "$trial/simulate.ps1" -Case unit
& "$trial/simulate.ps1" -Case top
& "$trial/simulate.ps1" -Case compare
Push-Location $trial
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log implementation_repeat.log -source implement.tcl -tclargs routed_repeat
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log clocks_repeat.log -source clock_check.tcl -tclargs ../mlu_bram_100mhz_20261118/rotating_fifo/flow/initial/routed.dcp routed_repeat/routed.dcp clocks_repeat
Pop-Location
```

The simulation entry points refresh the corresponding case logs. Give each
physical run a new output directory. The existing production project and
reference models are independently usable.
