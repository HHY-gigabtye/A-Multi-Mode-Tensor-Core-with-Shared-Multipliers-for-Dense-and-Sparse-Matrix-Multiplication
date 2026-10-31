# Sparse Tensor Core Integration (SystemVerilog / ModelSim)

This directory adds the synthesizable `sparse_tensor_core_top` and a pure-SV integration testbench using the five existing units directly. The integration delivery did not modify existing RTL, packages, testbenches, vectors, or C references, and did not add or compile C programs.

## Files and Connections

| Added file | Purpose |
|---|---|
| `rtl/sparse_tensor_core_top.sv` | Integration top; production design source |
| `tb/tb_sparse_tensor_core_top.sv` | SV memory model, matrix generator, GEMM scoreboard, cycle checks, and reset checks |
| `sim/run_top.do` | Compiles and simulates the top; also adds waveforms in the GUI |
| `sim/wave_top.do` | Waveform grouping |
| `sim/run_units.do` | Runs the five existing SV unit tests in isolated libraries |
| `sim/run_regression.ps1` | Optional batch launcher checking exit codes, errors, and all PASS markers |
| `results/units.log`, `results/top.log` | Recorded local ModelSim runs |
| `results/VALIDATION.md` | Verification summary, commands, and limitations |

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

The top does not create another sideband pipeline; `du_tc_bridge` already contains four tag stages. Payload and metadata are connected field by field across packages, avoiding assumptions about implicit struct layout. Both sparse DU/TIA modes output `is_sparse=1`.

The Bridge permits MLU issue using old-state `fifo_count + inflight_count < 8`. The FIFO head is always presented to TC, and **mode-aware `in_ready`** determines TC `in_valid`. Metadata is enqueued when TC accepts k=0 and dequeued on the actual TC→MSU handshake. No new data register stage, bypass, cross-tile accumulation, or global control state machine is added.

## Top-Level External Interface

| Interface | Contract |
|---|---|
| `clk`, `rst_n` | Shared clock and asynchronous active-low reset; cancel pending external memory responses during reset |
| `command_valid/ready`, `command` | `mlu_pkg::io_command_t`: mode, 64-bit source, 32-bit tile ID, and 64-bit destination; hold the command stable while valid waits |
| `read_request_valid/ready`, `read_addr`, `read_beats` | At most one outstanding burst; `read_beats` is the actual 4 or 5 beats, not AXI ARLEN |
| `read_data_valid/ready`, `read_data`, `read_last` | 256 bits per beat, byte 0 in `[7:0]`; first beat no earlier than the cycle after request acceptance |
| `write_valid/ready`, `write_addr/data/last/meta` | Eight 256-bit row beats per tile; row-major, little-endian INT32; stable while stalled |
| `tile_done`, `completed` | Registered pulse and metadata after actual acceptance of the row 7 write; not a TC computation-complete notification |
| `mlu_status`, `bridge_status`, `tc_status`, `msu_status` | Original unit diagnostic codes; all 0 for legal traffic |

Each command performs an independent 8×8×8 signed INT8→INT32 GEMM. Modes 0/1/2 are dense/hybrid/dual; mode 3 is illegal. Source and destination must be 32-byte aligned and satisfy the existing modules' complete-burst/result address-range checks.

Source images use the formats in `docs/architecture.md`: 128B dense, 128B padded hybrid, and 160B padded dual. This is the original simplified read/write interface, without AXI/HBM responses, cross-K-tile accumulation, or read/write arbitration. Nonzero status indicates an interface fault. The top adds no transaction rollback; correct the source and reset the system together.

## Running ModelSim

From the repository root, verify the top directly without a C compiler or external golden files:

```powershell
Set-Location C:\Users\Jason\Desktop\TC
vsim -c -l integration_sv/results/top.log -do integration_sv/sim/run_top.do
```

In the GUI Transcript:

```tcl
cd C:/Users/Jason/Desktop/TC
do integration_sv/sim/run_top.do
```

The script adds waveforms and stops at test completion. `integration_sv/build/top/vsim.wlf` is the generated waveform file. When invoking an absolute `.do` path from elsewhere, first set:

```tcl
set env(STC_ROOT) C:/Users/Jason/Desktop/TC
do C:/Users/Jason/Desktop/TC/integration_sv/sim/run_top.do
```

In ModelSim 2020.1 `do` macros, `[info script]` is unreliable. The script searches upward from the current directory for the repository or uses `STC_ROOT`. All builds/libraries go into `integration_sv/build/`, preserving the original unit libraries.

To rerun the existing SV unit tests:

```powershell
vsim -c -l integration_sv/results/units.log -do integration_sv/sim/run_units.do
```

Optional full regression entry point:

```powershell
& .\integration_sv\sim\run_regression.ps1
# Integration only:
& .\integration_sv\sim\run_regression.ps1 -TopOnly
```

For the published repository, first restore TC vectors using the command in the [root README](../README.md#10-how-to-run-the-tests).

All stimulus, memory simulation, and matrix comparisons are implemented in SV. Existing MLU/Bridge/TC/MSU unit testbenches still read their original C-generated vectors; these are neither modified nor regenerated. `run_units.do` continues to the next test after `$finish`. For automation, use the PowerShell launcher to check all five PASS markers and the absence of Fatal/Error. `run_top.do` checks the testbench's `passed` flag and returns a nonzero batch exit code if PASS is not reached.

Compilation order is in `sim/run_top.do`: packages precede modules, and the top follows the five modules. Integration compiles exactly one `du_tia_sv/rtl/du_tia_pkg.sv` and one `tensor_core_sv/tensor_core_pkg.sv`; it does not also compile the same-named package copies in the MLU and FIFO directories.

## Verification Coverage

The testbench computes GEMM from the original mathematical A/B matrices and independently encodes the memory images. It does not use DUT packetization/decoding helpers to generate expected values. In addition to every INT32 result, it checks every output byte, address, tile ID, k sequence, and completion notification.

- A 64-tile sparse stream without stalls, checking II=8 for every adjacent tile pair; a 96-tile mixed-mode stream and a 48-tile sparse stress stream.
- All nine mode→mode transitions, all six legal 2:4 masks, -128/127/0/±1, zero/full counts, and legal stored zeros.
- Command/request gaps, response latency and gaps, long write backpressure, and final-beat stalls.
- Exactly four edges from issue to DU arrival; at least five from issue to TC acceptance; no empty-FIFO bypass or full-credit lookahead.
- Per-cycle FIFO, in-flight, and metadata counter updates; same-edge push/pop, wrap, full metadata, full MSU, and full TC result storage.
- Result publication 3 edges after sparse k=7 acceptance and 15 edges after dense k=7 acceptance, matching the measured SV contract; stable results/metadata under stall.
- Reset after reaching each FIFO occupancy 0…8, in-flight occupancy 0…4, metadata/MSU/TC-result/MLU-buffer occupancy 0…2, and writeback row 0…7; also outstanding reads and stalled final beats.
- Each tested reset clears pending simulated memory responses, then runs three recovery tiles with new IDs to detect stale packets/results.

These are fixed-seed dynamic simulations and directed coverage, not a formal proof. The 10 ns testbench clock schedules simulation and does not establish 100 MHz timing closure. The original integration verification did not run synthesis, placement, routing, or PPA measurements; later archived implementation results are documented in the [repository README](../README.md).
