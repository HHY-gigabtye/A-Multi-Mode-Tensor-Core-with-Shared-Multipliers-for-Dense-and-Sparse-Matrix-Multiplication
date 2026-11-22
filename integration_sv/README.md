# Sparse Tensor Core Integration (SystemVerilog / ModelSim)

The production top connects MLU, DU/TIA, the credit-controlled Bridge, the shared outer-product TC and MSU. The system testbench checks all three external memory formats against mathematical GEMM.

Since the November 22 promotions, TC restores INT8 operand coordinates before
its 64 signed multipliers, then accumulates in signed 19-bit storage and
sign-extends to exact INT32 external results. DU/TIA S1/S2 build plain
packed structs and assign the selected union once to avoid the reproduced
Vivado RTL/netlist mismatch. The top, packet layouts, four-stage DU/TIA timing,
credit rules, II=8, and k=7+3 publication are unchanged.

## Files and connections

| Added file | Purpose |
|---|---|
| `rtl/sparse_tensor_core_top.sv` | Synthesizable integration top |
| `tb/tb_outer_top.sv` | SV memory model, matrix generator, GEMM scoreboard, cycle and reset checks |
| `sim/run_top.do` | Compiles and simulates the top; adds waveforms in the GUI |
| `sim/wave_top.do` | Waveform groups |
| `sim/run_units.do` | Runs isolated component suites and the old/new TC comparison |
| `sim/run_regression.ps1` | Optional batch launcher checking exit codes, errors, and every PASS marker |
| `../reports/verification/tc19_main_20261122/` | Current 19-bit main-source regression, applied TC diff, backups, source hashes, and retained candidate implementation evidence |
| `../reports/verification/operand_route_main_20261122/` | Historical 32-bit operand-routing promotion and DU/TIA repair |
| `../reports/verification/outer_main_20261121/` | Historical shared-core promotion and implementation reports |
| `results/VALIDATION.md` | Historical integration validation |

```text
command / read memory
          |
         MLU -- issue = out_valid && can_issue --> DU/TIA
          |                                        |
          +-- mode / k / metadata --> Bridge <-----+
                                     |
                       packet FIFO (8), inflight credit,
                       4-stage sideband, result metadata (2)
                                     |
                       head_valid && TC.in_ready
                                     |
                                Tensor Core
                                     |
                         result + ordered metadata
                                     |
                                    MSU
                                     |
                         write memory / tile_done
```

The top does not duplicate the sideband; `du_tc_bridge` already contains four
stages of tags. Payload and metadata are connected field-by-field across
packages, avoiding implicit structure-layout assumptions. Both sparse modes
use `is_sparse=1` at the DU/TIA output. The top supplies dense operands with `count=8` and identity indices at FIFO ingress. The TC reads the same indexed operand fields for all three formats.

Bridge gates MLU with old-state `fifo_count + inflight_count < 8`. The FIFO head
is always presented to TC. `tc_accept = rst_n && head_valid && tc_in_ready`
also drives TC `in_valid`. The first slice reserves a result slot; the remaining
slices use that reservation. The core has no mode input or separate dense
datapath, so format changes need no drain. Every format publishes three
advancing edges after k=7, with an unstalled tile-start interval of eight cycles.
Metadata is pushed when TC accepts k=0 and popped on the actual TC→MSU handshake.
There is no added data-register stage, bypass, cross-tile accumulation, or global
control state machine.

## External top interface

| Interface | Contract |
|---|---|
| `clk`, `rst_n` | Shared clock and asynchronous active-low reset; cancel external pending memory responses on reset |
| `command_valid/ready`, `command` | `mlu_pkg::io_command_t`: mode, 64-bit source, 32-bit tile ID, 64-bit destination; hold the command stable while valid waits |
| `read_request_valid/ready`, `read_addr`, `read_beats` | At most one outstanding burst; `read_beats` is the actual count of 4 or 5, not AXI ARLEN |
| `read_data_valid/ready`, `read_data`, `read_last` | 256 bits per beat, byte 0 at `[7:0]`; first response no earlier than the edge after request acceptance |
| `write_valid/ready`, `write_addr/data/last/meta` | Eight 256-bit row beats per tile; row-major, little-endian INT32; stable under stall |
| `tile_done`, `completed` | Registered pulse and metadata after row 7 is accepted for writing; not TC computation completion |
| `mlu_status`, `bridge_status`, `tc_status`, `msu_status` | Original component diagnostic codes; all zero for legal traffic |

Each command is an independent 8×8×8 signed INT8→INT32 GEMM. Modes 0/1/2 are
dense/hybrid/dual; mode 3 is illegal. Source and destination addresses must be
32-byte aligned and satisfy each module's complete burst/result-span checks.
Source images retain the 128B dense, 128B padded hybrid, and 160B padded dual
formats in `docs/architecture.md`. This is the original simplified read/write
interface, without AXI/HBM responses, cross-K-tile accumulation, or read/write
arbitration. Nonzero status is an interface fault; the top adds no transaction
recovery mechanism. Correct the source and reset connected modules together.

## ModelSim

From the repository root, verify the top without a C compiler or external golden
file:

```powershell
Set-Location C:\Users\Jason\Desktop\TC
vsim -c -l integration_sv/results/top.log -do integration_sv/sim/run_top.do
```

In the GUI Transcript:

```tcl
cd C:/Users/Jason/Desktop/TC
do integration_sv/sim/run_top.do
```

The script adds waveforms and stops at test completion. The generated waveform
file is `integration_sv/build/top/vsim.wlf`. To invoke the absolute `.do` path
from another directory, first set:

```tcl
set env(STC_ROOT) C:/Users/Jason/Desktop/TC
do C:/Users/Jason/Desktop/TC/integration_sv/sim/run_top.do
```

`[info script]` is unreliable inside ModelSim 2020.1 `do` macros, so these scripts
search upward from the current directory or use `STC_ROOT`. All builds/libraries
are under `integration_sv/build/`, preserving the units' original libraries.

Rerun existing SV unit tests:

```powershell
vsim -c -l integration_sv/results/units.log -do integration_sv/sim/run_units.do
```

Optional complete regression launcher:

```powershell
& .\integration_sv\sim\run_regression.ps1
# Integration only:
& .\integration_sv\sim\run_regression.ps1 -TopOnly
```

All stimulus, memory modeling, and matrix comparison are in SV. MLU, Bridge
and MSU replay their original C-generated vectors. The shared TC unit replays
compatible outer-product windows from the unchanged legacy C trace; its dense
timing is checked by `tb_compare.sv` and `tb_outer_top.sv` against the new contract
and mathematical GEMM. The legacy dense trace is not a cycle-exact oracle for
the shared core. `run_units.do` proceeds to the next
test after `$finish`; automated runs should use the PowerShell launcher to check
all unit and comparison PASS markers and absence of Fatal/Error messages. `run_top.do` checks
the testbench's `passed` flag and returns nonzero in batch mode if PASS is not
reached.

Compilation order is in `sim/run_top.do`: packages precede modules, and the top
follows the five modules. Integration compiles exactly one copy each of
`du_tia_sv/rtl/du_tia_pkg.sv` and `tensor_core_sv/tensor_core_pkg.sv`, excluding
the duplicate package definitions in the MLU and FIFO directories.

## Verification coverage

The [November 22 19-bit main-source regression](../reports/verification/tc19_main_20261122/README.md)
passes all original units before integration, then completes 369 tiles with
3,542 issued packets, 2,987 accepted write beats, and 77 resets. All 50 integration
summary lines match the original baseline. Dense and mixed streams retain II=8
and k=7+3 publication. To repeat without overwriting accepted evidence, run from
the repository root with a fresh output name:

```powershell
./reports/verification/tc19_main_20261122/run_regression.ps1 -RunName regression_repeat
```

The launcher additionally reruns TC equivalence and signed bounds units before
integration. The [19-bit isolated comparison](../experiments/tc19_20261122/REPORT.md)
also validates baseline/candidate routed functional netlists in all three modes,
including candidate bounds workloads. Its post-route area/timing evidence matches
the promoted source hashes: 100 MHz passes with only 4 ps setup margin. Promotion
did not rerun implementation or measure power; existing GUI runs remain historical.

The testbench computes GEMM from original mathematical A/B matrices, then
independently encodes the memory image. It does not use DUT packetize/decode
helpers to generate expected values. In addition to every INT32 result, it
checks every written byte, address, tile ID, k ordering, and completion event.

- A 64-tile unstalled sparse stream checks II=8 for every adjacent tile; 24-tile dense and 27-tile mixed streams check every unstalled interval. A 96-tile mixed stream and a 48-tile sparse stress stream exercise backpressure.
- All nine mode→mode transitions, six legal 2:4 masks, -128/127/0/±1, zero/full counts, and legal stored zeros.
- Command/request gaps, response latency/gaps, prolonged write backpressure, and last-beat stalls.
- Exactly four edges from issue to DU arrival; at least five from issue to TC acceptance; no empty-FIFO bypass or full-credit lookahead.
- Per-edge FIFO, inflight, and metadata accounting; simultaneous push/pop, wrap-around, metadata full, MSU full, and TC result full.
- All formats publish a result three advancing edges after k=7 acceptance. The testbench checks stability of results and metadata under stall.
- Reset after reaching every FIFO occupancy 0…8, inflight occupancy 0…4, metadata/MSU/TC-result/MLU occupancy 0…2, and write row 0…7; also outstanding reads and stalled last beats.
- Each tested reset cancels pending modeled memory responses, then runs three recovery tiles with new tile IDs to check that no stale packets/results escape.

These are fixed-seed dynamic simulation and directed coverage, not formal proof.
The testbench's 10 ns clock schedules simulation and does not establish 100 MHz
timing closure. The original integration validation did not include synthesis,
placement, routing, or PPA measurements.
