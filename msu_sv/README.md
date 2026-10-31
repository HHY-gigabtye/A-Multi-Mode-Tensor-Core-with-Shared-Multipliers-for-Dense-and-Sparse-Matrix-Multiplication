# MSU SystemVerilog — C Model Translation

> Scope note: tool availability and verification statements below describe the original standalone delivery. See the [repository README](../README.md) and [source audit](../docs/source-audit.md) for later ModelSim, integration, and implementation results. The root regression launcher provides the portable MSU replay entry point; the legacy local ModelSim script retains a machine-specific path.

This RTL is based on the supplied `msu_model(1).c`, `msu_model(1).h`, and `io_types(6).h`. For legal inputs, buffers, output data, addresses, and event timing are compared cycle by cycle with the original C model. The fixed specification is two complete-result buffers, an 8×8 INT32 input, and a 256-bit write interface. MSU stores and writes completed results only; it performs no cross-K accumulation or read-modify-write.

| File | Purpose |
|---|---|
| `rtl/msu_pkg.sv` | Matrix, metadata, status, and event types |
| `rtl/msu.sv` | Synthesizable MSU module |
| `tb/tb_msu.sv` | Cycle-by-cycle C golden comparison using procedural `$fatal`, without SVA/DPI/UVM |
| `vectors/msu_vectors.txt` | Complete pregenerated vectors; ModelSim replay needs no C compilation |
| `sim/run_msu.do` | ModelSim/Questa compilation, simulation, and waveform script |
| `reference/` | Original C files with include-compatible filenames restored; contents unchanged |
| `tools/gen_msu_vectors.c` | Calls the original C model to generate vectors |
| `tools/run_verilator.sh` | Reruns original C tests, generates vectors, lints, and runs Verilator |
| `tools/run_iverilog.sh` | Runs Icarus using supplied vectors |
| `results/` | Recorded verification results |

After extraction, change the ModelSim Transcript working directory to this folder and run:

```tcl
do sim/run_msu.do
```

For a manual project, compile `rtl/msu_pkg.sv`, `rtl/msu.sv`, and `tb/tb_msu.sv` in that order, selecting `tb_msu` as the simulation top. By default, the test reads `vectors/msu_vectors.txt` relative to the working directory; use `+VECTORS=full_file_path` to override it. For synthesis, select `msu` and include only the two `rtl/` files. This standalone test does not compile MLU, DU/TIA, Bridge, or Tensor Core.

On Linux, use `bash tools/run_verilator.sh` or `bash tools/run_iverilog.sh`. For VCD, add `+VCD=results/msu.vcd`; the ModelSim script already adds the main waveforms.

## Interface

| Interface | Meaning |
|---|---|
| `clk`, `rst_n` | Rising-edge updates; asynchronous active-low reset, with reset release synchronized appropriately by the system |
| `result_valid`, `result_ready` | Accept one complete result when both are 1 on the same edge |
| `result[7:0][7:0][31:0]` | 64 INT32 bit patterns; `result[row][col]` |
| `result_meta.tile_id` | 32-bit tile identifier |
| `result_meta.dst_addr` | 64-bit byte address, aligned to 32 bytes |
| `write_valid`, `write_ready` | Commit one 32-byte write at the memory endpoint when both are 1 |
| `write_addr` | `dst_addr + row*32` |
| `write_data[255:0]` | The entire current row, with little-endian byte lanes |
| `write_last` | Current row is row 7; may remain 1 over multiple stalled cycles |
| `write_meta` | Metadata of the current output tile |
| `status` | Combinational format-check result for the current cycle; normally `IO_OK` |
| `events` | Registered observations of actual events on the most recent rising edge |
| `buffer_count`, `head_index`, `row_index` | Observable state: 0–2, 0–1, and 0–7 |

`events.result_accepted` indicates that a TC result was just accepted. `events.beat_written` indicates that a write was committed. `events.tile_done` is 1 only when row 7 successfully handshakes. `events.completed` holds that completed tile's metadata on this event and is zero otherwise. These events report the edge after it occurs; do not substitute them for pre-edge ready/valid decisions.

## Output Layout and Timing

Output layout matches C `write_data[4*j+byte]`:

```systemverilog
write_data[32*j +: 32]       = result[row][j];
write_data[8*(4*j+b) +: 8]   = result[row][j][8*b +: 8];
```

For example, `32'h01234567` is stored as bytes `67 45 23 01` in increasing address order. Negative two's-complement bits are preserved exactly; MSU performs no addition, sign extension, or truncation. One result is `8×8×4 = 256 bytes`. C `IO_TILE_BYTES=160` describes MLU input-image capacity, not MSU result size.

| Pre-edge state / input | Behavior at that edge |
|---|---|
| Empty buffers, valid input | Accept the result; no empty bypass; earliest row 0 write is the next rising edge |
| Buffered data, `write_ready=0` | In normal error-free operation, hold valid, address, data, last, and metadata |
| count=1, writing row 0–6 while accepting a result | Write the current row, fill the other buffer, and change count to 2 |
| count=1, writing row 7 while accepting a result | Complete the old tile, insert the new tile, and keep count at 1 |
| count=2, writing row 7 | `result_ready=0` on this edge; count becomes 1 afterward and ready returns on the next cycle |

The final row deliberately preserves C old-state decisions, without early readiness based on a slot about to be released. Output selects the current row from the stored head buffer, without another output register or pipeline delay. When `result_valid && !result_ready`, the source must hold valid, the matrix, and metadata until acceptance. Normal result traffic need not identify the original dense, hybrid, or dual mode.

## Format Checks and Reset

The two C format conditions are preserved: the address must be 32-byte aligned, and `dst_addr <= 64'hffff_ffff_ffff_ff00`, so the complete 256-byte result fits the address space. Checks occur only when `result_valid=1` and capacity is available. Full buffers cause normal backpressure, not an error.

**Explicit error/reset distinction:** C `msu_peek()` reports capacity and outputs before the tick, but an illegal address makes `msu_tick()` return `IO_BAD_FORMAT` and cancel the entire edge without changing state. RTL likewise cancels state updates and events, and additionally deasserts `result_ready` and `write_valid` on that error cycle to prevent the external endpoint from observing a committed write. Therefore these two handshake signals differ from raw C peek on illegal-input cycles; the testbench explicitly accounts for this difference. Handshakes are also suppressed during reset.

An illegal address is an interface fault, not an ordinary stall. The producer must correct it or the system must reset. The valid/payload hold guarantee assumes legal transactions; this interface is not AXI.

## Tensor Core and Bridge Integration

`msu_matrix_t` and `tensor_core_pkg::tc_matrix_t` are both `logic [7:0][7:0][31:0]`, so matrices connect directly without transposition or lane reordering. `result_meta` comes from the Bridge result-metadata queue head; TC itself does not carry this metadata. Connect metadata across packages explicitly by `tile_id` and `dst_addr`.

For normal operation without a TC error, illustrative top-wrapper wiring is:

```systemverilog
assign msu_result_valid    = tc_result_valid && meta_valid;
assign tc_result_ready    = msu_result_ready && meta_valid;
assign bridge_result_accept = msu_result_valid && msu_result_ready;
// msu.result      <- tc.result
// msu.result_meta <- bridge result metadata head
```

Pop Bridge metadata on **the same rising edge as TC→MSU acceptance**. Do not wait for `tile_done` or use the one-cycle-delayed `events.result_accepted` to drive that pop. MSU copies metadata into its own result buffer at acceptance.

If a top permits TC strict-contract errors, it must also suppress downstream transfers on the error edge so MSU does not accept a result from a canceled TC tick. Normal integration must obey TC's existing input contract. Reset all connected modules and the memory responder together to prevent old results from being paired with new metadata.

Here, `write_ready` means the write commits on that edge; there is no separate write-response/error channel. An AXI/HBM controller still needs an adapter; this interface is not directly AXI AW/W/B. If MLU and MSU share a memory port that cannot read and write simultaneously, external arbitration must control requests and `write_ready`. Standalone MSU does not handle MLU read requests. Reset clears unfinished MSU buffers but does not undo rows already committed to memory.

## Original Verification

The original standalone verification ran the C tests with GCC, RTL lint/simulation with Verilator 5.020, and simulation with Icarus Verilog 12.0. ModelSim scripts were supplied but ModelSim was unavailable in that environment. That delivery did not run FPGA/ASIC synthesis, timing analysis, or full Tensor Core system integration.

| Check | Result |
|---|---|
| Original `tb_msu.c` | PASS: 120 results, 960 beats, 1,339 cycles, simultaneous=1 |
| Cycle-by-cycle C/SV comparison | PASS: 8,683 cycles, identical results in both SV simulators |
| Acceptance / writes / completion | 676 results, 5,394 beats, 673 completed tiles |
| Same-edge acceptance and final-row write | 34 occurrences, including 32 explicitly directed cases |
| Illegal addresses / resets | 42 / 8 |
| Output stalls | 3,216 cycles, checking stability of all output payload fields |
| Final-row writes with count=2 | 632 occurrences, checking that no new result is accepted on that edge |
| Head wraps / maximum count | 335 / 2 |

The difference between 676 accepted and 673 completed results comes from reset tests intentionally clearing 3 unfinished results. Of the 5,394 writes, 10 are rows committed before reset from tiles that did not complete. Tests include INT32_MIN/MAX, negative and zero values, full 64-bit addresses, the highest legal address, full buffers, long stalls, final-row stalls, whole-edge cancellation on illegal input, and restart after reset.
