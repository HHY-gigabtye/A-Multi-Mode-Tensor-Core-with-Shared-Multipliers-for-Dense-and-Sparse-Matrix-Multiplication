# Accepted BRAM version: 100 MHz internal FPGA timing

> Historical architecture scope: this record describes the November 19, 2026 predecessor or its experimental variants. References below to current, selected or production RTL refer to that dated snapshot. Current `main` uses a shared 64-multiplier outer-product core for every format; its dense timing and format-change rules differ. See the [current TC contract](../../tensor_core_sv/README.md) and [promotion record](../../reports/verification/outer_main_20261121/README.md). Original measurements and validation results below are retained.

Accepted on 2026-11-19 with Vivado 2022.2 for `xc7z020clg484-1`.
The selected source snapshot is `rotating_fifo/src`. Its independently
reopened routed checkpoint passes the original 10.000 ns internal clock:
WNS +0.011 ns, TNS 0, WHS +0.098 ns, THS 0, with zero failing setup/hold
endpoints. All 40,406 routable nets are fully routed with zero routing errors.

## Comparable results

All columns are FPGA OOC post-route results at 10.000 ns using the same
device, Vivado version and speed file `-1 PRODUCTION 1.12 2019-11-22`.
The physical optimization histories differ; the reports are preserved.

| Metric | Original FF baseline | Previous BRAM attempt | Accepted BRAM version |
| --- | ---: | ---: | ---: |
| LUT | 29,405 | 26,573 | 28,213 |
| FF | 21,503 | 19,223 | 19,852 |
| RAMB36E1 | 0 | 18 | 18 |
| DSP48E1 | 128 | 128 | 128 |
| Setup WNS (ns) | +0.002 | -1.116 | +0.011 |
| Hold WHS (ns) | +0.096 | +0.098 | +0.098 |
| Meets 100 MHz internal setup/hold | Yes | No | Yes |

The accepted design saves 1,192 LUTs (4.05%) and 1,651 FFs (7.68%) versus
the passing FF baseline. It uses 18 of 140 BRAM tiles. The timing repair
uses more LUTs/FFs than the earlier BRAM attempt that failed timing.

## Selected RTL changes

Only two source files differ from the original eleven-file snapshot:

- `rotating_fifo/src/mlu_sv/mlu.sv`: store image data in 18 synchronous
  BRAMs. Capture accepted input writes in pending registers; on accepted
  k=6, save the final packet and start reading the next slot. A small
  forwarding cache handles the hybrid final-load/read collision. Public
  packets, output cycles, stalls, resets and command ordering are preserved.
- `rotating_fifo/src/fifo_sv/du_tc_bridge.sv`: rotate the existing eight
  physical FIFO words on pop, keeping the head in physical word zero.
  The head remains combinational and there is no extra output stage or
  bypass. OLD occupancy credits and metadata transfer timing are unchanged.
  The logical ring state is reconstructed from actual storage, including
  stale words, for the unchanged full-state C comparison.

Review diffs: `rotating_fifo/mlu.patch` and `rotating_fifo/bridge.patch`.
TC, MSU, DU/TIA, packages and top-level source remain byte-identical to the
original. The MSU address-predicate experiment is not part of this result.
Production RTL was not overwritten; no commit, merge or push was performed.

## Validation evidence

- Five unchanged standalone unit suites pass: MLU 16,708 C records;
  DU/TIA 3,292 packets; Bridge 19,147 records; TC 136,136 records;
  MSU 8,683 cycles.
- Original integration passes: 316 completed tiles, 3,124 issued packets,
  2,563 write beats, 75 resets, seed `91e10da5`. All 46 summary lines
  exactly match the original baseline.
- Actual synthesized MLU primitive comparison passes 16,708 vectors and
  17,171 cycle comparisons, including 18 directed transitions, 234
  simultaneous final-load/final-output cases, 5,347 stalls and 155 resets.
  The selected MLU source is byte-identical to that tested snapshot.
- Actual synthesized Bridge netlist passes 19,147 C-vector edges and
  38,294 pre/post-edge interface comparisons, including 7,156 rejected
  edges and 13 resets. The original RTL full-state check also passes.
- Final independent timing gate passes. BRAM control DRC REQP-1839 has
  zero violations; full DRC has zero errors. The 513 warnings are the
  existing DSP pipeline advisories and OOC PS7 warning, not waived errors.
- There are no valid timing exceptions and no unconstrained internal
  endpoints. DSP pipeline configuration remains 64 PREG=0 and 64 PREG=1,
  with AREG/BREG/MREG=0 for all 128 DSPs. No externally visible pipeline
  latency was added.
- Hash verification confirms the eleven original source files and all
  76 protected reference/model/vector/test files remain unchanged.

Evidence locations:

- `rotating_fifo/flow/final_audit/PASS.txt`
- `rotating_fifo/flow/final_audit/timing_summary.rpt`
- `rotating_fifo/flow/final_audit/utilization.rpt`
- `rotating_fifo/units.log`, `rotating_fifo/top.log`
- `rotating_fifo/bridge_netlist/result.log`
- `early_prefetch/equiv_netlist/result.log`
- `rotating_fifo/sources.csv`, `verification_final.log`, `accepted_result.json`

Accepted checkpoint: `rotating_fifo/flow/initial/routed.dcp`.
SHA256: `6D2D087D2B5114E74F0CBE099A17B132FCDD910DADAD68FF147E4472A551E3A5`.
Original Git baseline: `e3c1ccdf6742165fec1e1ad74561d91e1ed157a8`.

## Commands and reproduction

The actual accepted run used these commands from the repository root
(Vivado was invoked from the trial folder for its log output):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File experiments/mlu_bram_100mhz_20261118/regress.ps1 -Trial rotating_fifo -Test all
powershell -NoProfile -ExecutionPolicy Bypass -File experiments/mlu_bram_100mhz_20261118/verify.ps1 -Trials rotating_fifo
```

Vivado then ran `bridge_netlist_check.tcl` with `rotating_fifo/src` and
`rotating_fifo/bridge_netlist`, followed by `prefetch_candidate_flow.tcl`
with `rotating_fifo/src` and `rotating_fifo/flow`. The latter automatically
reopened the passing route through `final_gate.tcl`. Full commands and
tool output are in `rotating_fifo/bridge_netlist.log` and `rotating_fifo/flow.log`.

For a fresh reproducible run, preserve existing evidence and use a new folder:

```powershell
$bramRepo = 'C:/Users/Jason/Desktop/TC'
$bramExp = Join-Path $bramRepo 'experiments/mlu_bram_100mhz_20261118'
$bramRepro = Join-Path $bramExp 'rotating_fifo_repro'
if (Test-Path -LiteralPath $bramRepro) { throw 'Use a new output folder' }
New-Item -ItemType Directory -Path $bramRepro | Out-Null
Copy-Item -LiteralPath (Join-Path $bramExp 'rotating_fifo/src') -Destination (Join-Path $bramRepro 'src') -Recurse
Copy-Item -LiteralPath (Join-Path $bramExp 'rotating_fifo/sources.csv') -Destination (Join-Path $bramRepro 'sources.csv')
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bramExp 'regress.ps1') -Trial rotating_fifo_repro -Test all
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log (Join-Path $bramRepro 'flow.log') -source (Join-Path $bramExp 'rotating_candidate_flow.tcl') -tclargs (Join-Path $bramRepro 'src') (Join-Path $bramRepro 'flow')
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bramExp 'verify.ps1') -Trials rotating_fifo_repro
```

## Scope and remaining margin

The measured setup margin is only 11 ps. This establishes internal FPGA
OOC STA at 100 MHz for the saved implementation; it is not a higher-frequency
sweep or an on-board test. External I/O delays and HD.CLK_SRC remain unspecified
exactly as in the baseline, so board I/O/clock integration needs its own timing
constraints. No power measurement was performed. Other unfinished experiments
were stopped once this accepted result was independently verified.
