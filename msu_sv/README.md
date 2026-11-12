# MSU SystemVerilog — Translation of the C Model

This RTL was derived from the supplied `msu_model(1).c`, `msu_model(1).h`, and
`io_types(6).h`. For legal inputs, buffers, output data, addresses, and event
timing are compared cycle-by-cycle with the original C model. The fixed design
has two complete-result buffers, an 8×8 INT32 input, and a 256-bit write interface.
MSU stores and writes completed results; it performs no cross-K accumulation or
read-modify-write operation.

| File | Purpose |
|---|---|
| `rtl/msu_pkg.sv` | Matrix, metadata, status, and event types |
| `rtl/msu.sv` | Synthesizable MSU module |
| `tb/tb_msu.sv` | Cycle-by-cycle C golden comparison using procedural `$fatal`, without SVA/DPI/UVM |
| `vectors/msu_vectors.txt` | Complete generated vectors; ModelSim does not require compiling C first |
| `sim/run_msu.do` | ModelSim/Questa compilation, simulation, and waveform script |
| `reference/` | Unmodified C sources, with filenames restored to match includes |
| `tools/gen_msu_vectors.c` | Calls the original C model to generate vectors |
| `tools/run_verilator.sh` | Reruns C tests, generates vectors, lints, and runs Verilator |
| `tools/run_iverilog.sh` | Runs Icarus with the included vectors |
| `results/` | Recorded validation results |

After extraction, change to this directory in the ModelSim Transcript and run:

```tcl
do sim/run_msu.do
```

For a manual project, compile `rtl/msu_pkg.sv`, `rtl/msu.sv`, and `tb/tb_msu.sv`
in that order, with simulation top `tb_msu`. The default vector path is
`vectors/msu_vectors.txt` relative to the working directory; override it with
`+VECTORS=full_file_path`. Synthesis uses top `msu` and only the two `rtl/` files.
This standalone test does not compile MLU, DU/TIA, Bridge, or Tensor Core.

On Linux, use `bash tools/run_verilator.sh` or `bash tools/run_iverilog.sh`.
For VCD output, add `+VCD=results/msu.vcd`. The ModelSim script already adds the
main waveforms.

| Interface | Meaning |
|---|---|
| `clk`, `rst_n` | Rising-edge updates; asynchronous active-low reset, with system-level reset-release synchronization |
| `result_valid`, `result_ready` | Accept one complete result when both are high on the same edge |
| `result[7:0][7:0][31:0]` | 64 INT32 bit patterns, indexed as `result[row][col]` |
| `result_meta.tile_id` | 32-bit tile identifier |
| `result_meta.dst_addr` | 64-bit byte address, aligned to 32 bytes |
| `write_valid`, `write_ready` | The memory endpoint commits a 32-byte write when both are high |
| `write_addr` | `dst_addr + row*32` |
| `write_data[255:0]` | Current complete row, with little-endian byte lanes |
| `write_last` | Current row is row 7; may remain high throughout a stall |
| `write_meta` | Metadata for the tile currently being written |
| `status` | Combinational format-check result for the current edge; normally `IO_OK` |
| `events` | Registered observation of events on the most recent rising edge |
| `buffer_count`, `head_index`, `row_index` | Observable state, with ranges 0–2, 0–1, and 0–7 |

`events.result_accepted` records a newly accepted TC result;
`events.beat_written` records a committed write;
`events.tile_done` is asserted only when row 7 handshakes successfully.
`events.completed` then contains that tile's metadata and is zero on other edges.
These registered events describe the edge that just occurred. Do not substitute
them for pre-edge ready/valid decisions on the same edge.

Output layout matches C's `write_data[4*j+byte]`:

```systemverilog
write_data[32*j +: 32]       = result[row][j];
write_data[8*(4*j+b) +: 8]   = result[row][j][8*b +: 8];
```

For example, `32'h01234567` is stored as bytes `67 45 23 01` in increasing address
order. Negative two's-complement patterns are preserved; MSU performs no
addition, sign extension, or truncation. Each result occupies `8×8×4 = 256 bytes`.
C's `IO_TILE_BYTES=160` describes MLU input-image capacity, not MSU output size.

| Pre-edge state / input | Action on that edge |
|---|---|
| Empty buffer, valid input | Accept the result; no empty bypass, so row 0 can be written no earlier than the next edge |
| Buffered data, `write_ready=0` | In normal operation, hold valid, address, data, last, and metadata |
| count=1, writing row 0–6 while accepting a result | Write the current row, fill the other buffer, and set count=2 |
| count=1, writing row 7 while accepting a result | Complete the old tile, enqueue the new tile, and retain count=1 |
| count=2, writing row 7 | Keep `result_ready=0` on this edge; count becomes 1 and ready returns next cycle |

The final row deliberately preserves C's old-state decision, without speculative
ready based on an imminent release. Output selects the current row from the
stored head buffer, with no extra output register or pipeline latency.
While `result_valid && !result_ready`, the producer must hold valid, matrix, and
metadata until acceptance. MSU does not need the original dense/hybrid/dual mode.

Format checks retain both C conditions: 32-byte address alignment and
`dst_addr <= 64'hffff_ffff_ffff_ff00`, ensuring the entire 256-byte result fits.
Checks run only when `result_valid=1` and capacity is available. Full occupancy
is ordinary backpressure, not an error.

**Explicit error/reset distinction:** C's `msu_peek()` reports capacity and output
before the tick, but an illegal address makes `msu_tick()` return `IO_BAD_FORMAT`
and reject the entire edge without updating state. RTL likewise suppresses
state updates and events, and additionally deasserts `result_ready` and
`write_valid` on an error edge so external endpoints do not mistake it for a
committed transfer. These two handshake signals therefore differ from raw C
peek on illegal inputs; the testbench handles that difference explicitly.
Handshakes are also disabled during reset. An illegal address is an interface
fault, not a normal stall: correct the producer or reset the system. Normal
valid/payload stability applies to legal transactions; this interface is not AXI.

`msu_matrix_t` and `tensor_core_pkg::tc_matrix_t` are both
`logic [7:0][7:0][31:0]`, so matrices connect directly without transposition or
lane reordering. Bridge's result-metadata queue supplies `result_meta`; TC does
not carry it. Connect metadata across packages by `tile_id` and `dst_addr` fields.

Example wrapper connections for normal operation without TC errors:

```systemverilog
assign msu_result_valid    = tc_result_valid && meta_valid;
assign tc_result_ready    = msu_result_ready && meta_valid;
assign bridge_result_accept = msu_result_valid && msu_result_ready;
// msu.result      <- tc.result
// msu.result_meta <- bridge result metadata head
```

Pop Bridge metadata on **the same rising edge as TC→MSU acceptance**. Do not wait
for `tile_done` or drive that pop with the delayed `events.result_accepted`.
MSU copies metadata into its own result buffer on acceptance. If a top permits
TC strict-contract errors, it must also suppress downstream transfers on that
edge so MSU cannot consume a result from a canceled TC tick. Normal integration
must obey TC's input contract. Reset all connected modules and the memory
responder together to prevent pairing old results with new metadata.

`write_ready` means the write commits on that edge; there is no separate write
response/error channel. An AXI/HBM controller still requires an adapter; these
ports are not AXI AW/W/B. If MLU/MSU share a memory port that cannot read and
write simultaneously, external arbitration must control requests and
`write_ready`. MSU does not arbitrate MLU reads. Reset discards unfinished MSU
buffers but does not undo rows already committed to memory.

Original validation used GCC for the C tests, Verilator 5.020 for RTL
lint/simulation, and Icarus Verilog 12.0 for simulation. ModelSim scripts were
provided but not run in that environment. FPGA/ASIC synthesis, timing analysis,
and full Tensor Core integration were not part of that delivery.

| Check | Result |
|---|---|
| Original `tb_msu.c` | PASS: 120 results, 960 beats, 1,339 cycles, simultaneous=1 |
| Cycle-by-cycle C/SV comparison | PASS: 8,683 cycles, identical across both SV simulators |
| Accepted / written / completed | 676 results, 5,394 beats, 673 completed tiles |
| Simultaneous acceptance and final-row write | 34 events, including 32 explicitly directed events |
| Illegal addresses / resets | 42 / 8 |
| Output stalls | 3,216 cycles, checking stability of every output payload |
| Final-row write while count=2 | 632 events, checking that no new result is accepted on that edge |
| Head wraps / maximum count | 335 / 2 |

The 676 accepted results versus 673 completions reflect three unfinished results
intentionally flushed by reset. Of 5,394 writes, 10 were committed rows belonging
to tiles interrupted by reset. Tests include INT32_MIN/MAX, negatives and zero,
full 64-bit addresses, the highest legal address, full buffers, long stalls,
last-row stalls, whole-edge rejection of illegal inputs, and reset/restart.
