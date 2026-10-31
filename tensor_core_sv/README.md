# Tensor Core SystemVerilog — Sparse Tile Overlap

> Scope note: tool availability and verification statements below describe the original standalone delivery. See the [repository README](../README.md) and [source audit](../docs/source-audit.md) for later ModelSim and implementation results. In this repository, restore `c_vectors.txt` from its gzip distribution with `tools/restore_vectors.ps1` at the repository root before replay.

This version is based on the supplied `tensor_core_model(1).c/.h` and `tb_tensor_core(1).c`. The three original C files in `c_reference/` only had `(1)` removed from their filenames; their contents were unchanged. This package contains only Tensor Core. Inputs are packets already decoded by DU/TIA.

## Running ModelSim

1. Extract the entire directory, preserving the relative locations of `c_vectors.txt` and the `.sv` files.
2. Enter the following in the ModelSim Transcript, substituting the actual path:

   ```tcl
   do C:/your/path/tensor_core_sv/run_modelsim.do
   ```

The script compiles the sources, loads waveforms, and runs the full test. Pregenerated C reference vectors are supplied; **GCC installation or C compilation is not required first**. When creating a ModelSim project manually, use this compilation order and select `tb_tensor_core` as the simulation top:

```tcl
vlog -sv tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
vsim -onfinish stop -voptargs=+acc work.tb_tensor_core +VECTORS=c_vectors.txt
run -all
```

For manual execution, use this directory as the working directory or set `+VECTORS=` to the vector file path. Neither RTL nor the SV testbench uses `assert` / SVA, UVM, classes, or DPI. Failures are reported with ordinary `if`, `$display`, and `$fatal`.

## Files

| File | Purpose |
|---|---|
| `tensor_core_pkg.sv` | Packet, PE, pipeline, control-register, and other types |
| `tensor_core.sv` | Core RTL; synthesis needs only this file and the package |
| `tb_tensor_core.sv` | Reads C reference records cycle by cycle and compares interfaces, results, and internal state |
| `run_modelsim.do` / `waves.do` | ModelSim compilation, simulation, and waveform setup |
| `c_vectors.txt` | Complete pregenerated test vectors, approximately 144 MiB |
| `c_reference/` | Original C model/testbench plus the vector generator |
| `generate_vectors.bat` / `.sh` | Vector regeneration with different seeds or test counts |
| `c_reference_results.txt` | Original C test results |
| `verification_results.txt` | Original measured Verilator C/SV comparison results |
| `SOURCE_SHA256.txt` | SHA-256 hashes of the three original C sources |

## Preserved Behavior

- Fixed M=N=K=8, signed INT8 × INT8, INT32 accumulation initialized to zero.
- Dense: 8×8 output-stationary systolic array; lane i is delayed by i cycles, and data moves across only one PE per cycle.
- Sparse: MUL → ROUTE → ACC, each reading previous-cycle registers; eight accepted packets per tile.
- The next sparse tile can start at the ninth input without waiting for the previous result to be output.
- The first input of each tile reserves a result credit; at most outstanding=2.
- Two physical result slots support same-edge consume/publish and consume/start.
- A full result FIFO blocks only the first packet of a new sparse tile; a started tile can still accept its remaining packets.
- `is_sparse` can change only after all old work and results drain and busy=0.
- Sparse accumulation clears only when `route.first` reaches ACC, not prematurely when the next tile enters.
- Empty outer products still propagate valid/first/last. Stored zero values within the valid prefix are legal.
- Invalid result slots retain old data after consumption, as in C. Use `result_valid` to determine validity.

Dense and sparse paths share 64 multiplication operation positions through operand muxes in RTL. Dense PE accumulators, the sparse accumulator, and the two result slots have separate storage; the C state union was not directly converted into shared hardware storage. Actual multiplier/DSP mapping, area, and Fmax require synthesis in the target flow.

## Timing

Number the rising edge accepting the first input as cycle 0 and accept k=0..7 consecutively:

| Event | Dense | Sparse |
|---|---:|---:|
| Final input | 7 | 7 |
| Final accumulation | 21 | 9 |
| result_valid becomes 1 | 22 | 10 |
| Earliest consumption with result_ready continuously 1 | 23 | 11 |
| Earliest start of the next tile | 24 | 8 |

With input gaps, measure from the last actually accepted input: dense publishes at +15 cycles and sparse at +3 cycles. A newly published result cannot be consumed on its publication edge; only a previously valid FIFO head can be consumed. `result_ready` does not feed combinational input readiness. A credit released on an edge becomes available in the next cycle.

## Interface

| Signal | Meaning |
|---|---|
| `clk` / `rst_n` | Rising-edge updates; asynchronous active-low reset clears all state and debug information |
| `in_packet` | `tc_input_packet_t`, the next packet to issue |
| `input_ready` | Corresponds to `tc_input_ready()`; checks resources for the current mode only |
| `in_ready` | Corresponds to `tc_input_ready_for(..., in_packet.is_sparse)`; includes mode compatibility |
| `in_valid` | Valid input for this edge; a legal driver asserts it only when in_ready=1 |
| `result_valid` / `result_ready` | Valid FIFO head / downstream readiness; the old head is consumed at the rising edge |
| `result` | `result[i][j]` is a 32-bit two's-complement result; use `$signed(...)` for decimal display |
| `busy` | An unconsumed tile exists, including partially received input, pipeline work, or completed results |
| `status` | Combinational check of current inputs for the next rising edge, not a registered pulse |
| `tick_info` | Observation of the most recent rising edge, corresponding to `TcTickInfo` |

`status` matches the C enum: OK=0, BAD_SPARSE_VECTOR=2, MODE_CHANGE=3, NOT_READY=4. C BAD_ARGUMENT=1 applies only to NULL pointers and is not produced in hardware. `tick_info` supports verification and waveform inspection; it may be left unconnected in a larger top so synthesis can remove unused debug logic.

**This version preserves the strict C API rather than adopting a general streaming protocol that permits valid to remain asserted while waiting.** If `in_valid=1` while resources are unavailable, the mode is incompatible, or sparse metadata is illegal, **the entire core holds state for that edge**. Even an old result is not consumed, and `tick_info` is zero. Drive `in_valid=0` while waiting so the pipeline and output can advance. `in_ready` does not validate sparse count/index values; upstream must supply legal metadata.

With an upstream FIFO that can hold its head, normal wiring is:

```systemverilog
assign tc_in_packet = tensor_core_pkg::tc_input_packet_t'(fifo_head);
assign tc_in_valid  = fifo_valid && tc_in_ready;
assign fifo_pop     = fifo_valid && tc_in_ready;
```

This assumes legal FIFO packets. Do not simply AND a one-cycle DU/TIA `out_valid` with ready; blocked packets would be lost. DU/TIA has no ready port, so full integration needs external buffering and upstream issue control to accommodate packets already in its pipeline. The original TC delivery did not modify DU/TIA or add MLU/MSU.

## Packets and DU/TIA

This package's `tc_input_packet_t` is 185 bits and matches the field order and widths of the supplied `du_tia_pkg::du_tia_output_t`, allowing the cast shown above. Standalone TC compilation does not depend on du_tia_pkg.

- Dense: `payload.dense.dense_a[i] = A[i][k]`, `dense_b[j] = B[k][j]`.
- Sparse: `a/b.count` is 0..8; valid value/index entries are 0..count-1.
- Indices are 3-bit original coordinates 0..7 and must be strictly increasing within the prefix. Padding values and indices are ignored.
- Lane 0 is the least-significant byte/field of each packed array. Populate values through field indices.
- No additional k, tile_start, first, last, or original compiler-mode input is required.
- Hybrid, dual sparse, and decoded dense×unstructured packets use the same is_sparse=1 path.

## Original Verification

1. Original C tests passed: 6,389 tiles and 1,593,020 MACs.
2. Intercepting public reset/tick calls from the same original C testbench generated 136,136 cycle records.
3. All records passed in Verilator: 169 resets and 13 representable RTL input-rejection cases; 3,480 full-FIFO cycles, 1 same-edge pop/push, and 151 consume/start cases.
4. Each record checks pre-edge readiness/status, all post-edge TickInfo, busy/result_valid, **all 64 INT32 elements in each of both result slots**, and a field-based 32-bit internal-state hash. The hash covers control registers and all pipeline/accumulator state in the current mode, excluding C struct padding.
5. The original C tests independently use i/j/k GEMM to check numerical results, dense wavefront timing, sparse pipeline behavior, FIFO ordering, and latency.

Coverage includes zeros, extremes, stored zeros, gaps, long output holds, cross-tile overlap, mode changes, and reset/restart. Four C-only rejection calls involving NULL pointers and active index≥8 are checked by the original C tests; an SV 3-bit index cannot represent ≥8. Padding index=255 is truncated to 7 during vector conversion but remains unused padding. Records include work discarded by mid-test resets and contract tests excluded from the tile total, so publish/consume counts do not exactly match 6,389 tiles.

Verilator `--Wall` RTL lint passed. SV syntax and scripts targeted ModelSim, but ModelSim was not installed in the original standalone environment; **that verification used Verilator**. That delivery did not run FPGA/ASIC synthesis, STA, or formal equivalence. State-hash comparison is not a formal proof.

## Regenerating Test Data (Optional)

Windows: use a Visual Studio "x64 Native Tools Command Prompt" with C11 support:

```bat
generate_vectors.bat
generate_vectors.bat --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

Linux/GCC:

```bash
bash generate_vectors.sh
bash generate_vectors.sh --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

These commands overwrite local `c_vectors.txt` and C test logs. Then rerun `run_modelsim.do`. `generate_c_vectors.c` includes the original testbench and renames its main; **do not add tb_tensor_core.c as another compilation unit when building the generator**. The supplied `run_verilator.sh` runs the same SV testbench on Linux with Verilator installed.
