# Tensor Core SystemVerilog — Sparse Overlap Version

> Before simulation, run `pwsh -NoProfile -File tools/restore_vectors.ps1` from the repository root to restore the SHA-256-verified `c_vectors.txt` from `c_vectors.txt.gz`. Current validation and FPGA mapping are documented in the [root README](../README.md).

This version was based on the supplied `tensor_core_model(1).c/.h` and
`tb_tensor_core(1).c`. The three original files in `c_reference/` only had `(1)`
removed from their names; their contents were unchanged. This package contains
only Tensor Core and accepts packets already decoded by DU/TIA.

## ModelSim

1. Extract the full directory, preserving the relative locations of `c_vectors.txt` and the `.sv` files.
2. In the ModelSim Transcript, substitute the actual path:

   ```tcl
   do C:/your/path/tensor_core_sv/run_modelsim.do
   ```

The script compiles, loads waveforms, and runs the complete test. Generated C
reference vectors are included; **GCC installation or C compilation is not
required first**. For a manual project, use simulation top `tb_tensor_core`:

```tcl
vlog -sv tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
vsim -onfinish stop -voptargs=+acc work.tb_tensor_core +VECTORS=c_vectors.txt
run -all
```

Run from this directory or change `+VECTORS=` to the vector path. RTL and the SV
testbench use no `assert` / SVA, UVM, classes, or DPI. Failures are reported with
procedural `if`, `$display`, and `$fatal`.

## Files

| File | Purpose |
|---|---|
| `tensor_core_pkg.sv` | Packet, PE, pipeline, control-register, and other types |
| `tensor_core.sv` | Core RTL; synthesis needs only this file and its package |
| `tb_tensor_core.sv` | Cycle-by-cycle C reference replay, comparing interfaces, results, and internal state |
| `run_modelsim.do` / `waves.do` | ModelSim compilation, simulation, and waveforms |
| `c_vectors.txt` | Complete pregenerated vectors, approximately 144 MiB |
| `c_reference/` | Original C model/testbench and vector generator |
| `generate_vectors.bat` / `.sh` | Regenerates vectors when changing seeds or test counts |
| `c_reference_results.txt` | Original C test results |
| `verification_results.txt` | Recorded Verilator C/SV comparison results |
| `SOURCE_SHA256.txt` | SHA-256 of the three original C files |

## Preserved behavior

- Fixed M=N=K=8, signed INT8 × INT8, and zero-initialized INT32 accumulation.
- Dense: 8×8 output-stationary systolic array; lane i is delayed i cycles, and data advances only one PE per edge.
- Sparse: MUL → ROUTE → ACC, each reading old registers; eight packets per tile.
- The next sparse tile may begin with the ninth input, without waiting for the previous result.
- Each tile's first accepted packet reserves a result credit; at most outstanding=2.
- Two physical result slots support same-edge consume/publish and consume/start.
- A full result FIFO blocks only a new sparse tile's first packet; started tiles may receive their remaining packets.
- `is_sparse` changes only after all work and results drain and busy=0.
- Sparse accumulation clears when `route.first` reaches ACC, not when the next tile first enters the input.
- Empty outer products still propagate valid/first/last; stored zeros in the valid prefix are legal.
- Invalid result slots retain their old contents after consumption, as in C. Use `result_valid` to interpret results.

In the original shared-multiplier RTL described by this package, dense and sparse
use operand muxes around 64 multiplication positions. Dense PE accumulators,
sparse accumulators, and the two result slots are separate; the C state union
was not translated into shared hardware storage. Actual multiplier/DSP count,
area, and Fmax require synthesis for the target device. Later experimental RTL
and its measured mapping are documented in the corresponding experiment reports.

The current main RTL uses separate dense and sparse multiplier inputs. Sparse
MUL product data has synchronous, non-reset storage at the original MUL edge;
the asynchronously reset valid/count metadata masks unused products to zero in
the logical `sparse_q` view. Rejected edges hold raw products. This enables DSP
PREG mapping without an extra pipeline cycle or a change to reset-visible state.
ROUTE uses direct one-hot matches because input validation rejects duplicate or
non-increasing indices before the entire edge commits. The original cycle,
state-hash and result-slot regressions remain unchanged. Mapping, timing and
candidate comparisons are recorded in the
[10 ns experiment](../experiments/msu_fmax/target_10ns_20261110/README.md).

## Timing

Let cycle 0 be the rising edge accepting the first packet, with k=0..7 accepted
on consecutive edges:

| Event | Dense | Sparse |
|---|---:|---:|
| Last input | 7 | 7 |
| Final accumulation | 21 | 9 |
| result_valid becomes high | 22 | 10 |
| Earliest consume with result_ready continuously high | 23 | 11 |
| Earliest next tile start | 24 | 8 |

With input gaps, publication occurs +15 cycles after the final accepted dense
packet or +3 cycles after the final accepted sparse packet. A newly published
result cannot be consumed on its publication edge; only an already-valid old
FIFO head can be consumed. `result_ready` is not part of combinational readiness;
a credit released on this edge becomes available next cycle.

## Interface

| Signal | Meaning |
|---|---|
| `clk` / `rst_n` | Rising-edge update; asynchronous active-low reset clears state and debug information |
| `in_packet` | `tc_input_packet_t`, containing the next offered packet |
| `input_ready` | Corresponds to `tc_input_ready()`, checking current-mode resources |
| `in_ready` | Corresponds to `tc_input_ready_for(..., in_packet.is_sparse)`, including mode compatibility |
| `in_valid` | Offers a packet on this edge; a legal driver asserts it only when in_ready=1 |
| `result_valid` / `result_ready` | FIFO-head validity / consumer readiness; consume the old head on the rising edge |
| `result` | `result[i][j]` is a 32-bit two's-complement result; use `$signed(...)` for decimal display |
| `busy` | At least one unconsumed tile, including partial input, pipeline work, or completed results |
| `status` | Combinational validation of current inputs for the next edge; not a registered pulse |
| `tick_info` | Observations from the latest rising edge, corresponding to `TcTickInfo` |

Status values match C: OK=0, BAD_SPARSE_VECTOR=2, MODE_CHANGE=3, NOT_READY=4.
C's BAD_ARGUMENT=1 applies only to NULL pointers and is not produced by hardware.
`tick_info` supports verification/waveforms and may be left unconnected in a
larger top so synthesis can remove unused debug logic.

**This version preserves C's strict API rather than a conventional stream that
may hold valid high while waiting.** If `in_valid=1` while resources are not ready,
the mode is incompatible, or sparse metadata is illegal, **the entire core
holds state on that edge**. Even an old result is not consumed, and `tick_info`
is zero. Drive `in_valid=0` while waiting so the pipeline/output can advance.
`in_ready` does not validate sparse count/index fields; upstream must supply
legal metadata.

For a FIFO with a stable head containing legal packets:

```systemverilog
assign tc_in_packet = tensor_core_pkg::tc_input_packet_t'(fifo_head);
assign tc_in_valid  = fifo_valid && tc_in_ready;
assign fifo_pop     = fifo_valid && tc_in_ready;
```

Do not simply AND a one-cycle DU/TIA `out_valid` pulse with ready; blocked packets
would be lost. Existing DU/TIA has no ready port, so integration needs external
buffering and upstream issue control that accounts for packets already in its
pipeline. This package did not change DU/TIA or add MLU/MSU.

## Packet format and DU/TIA

`tc_input_packet_t` is 185 bits and matches the field order and widths of the
supplied `du_tia_pkg::du_tia_output_t`, permitting the cast above. Standalone TC
compilation does not depend on du_tia_pkg.

- Dense: `payload.dense.dense_a[i] = A[i][k]`, `dense_b[j] = B[k][j]`.
- Sparse: `a/b.count` is 0..8; valid value/index entries are 0..count-1.
- Indices are 3-bit original coordinates 0..7 and strictly increasing in the valid prefix. Padding values and indices are ignored.
- Lane 0 occupies the least-significant byte/field of its packed array; assign through field indices.
- No extra k, tile_start, first, last, or original compiler-mode input is required.
- Hybrid, dual sparse, and dense×unstructured decoded inputs share the is_sparse=1 path.

## Original validation

1. Original C tests passed: 6,389 tiles and 1,593,020 MACs.
2. Public reset/tick calls from that unchanged C testbench generated 136,136 cycle records.
3. Verilator replay passed all records: 169 resets, 13 representable RTL rejection cases, 3,480 full-FIFO cycles, 1 same-edge pop/push, and 151 consume/start events.
4. Every record checked pre-edge readiness/status, all post-edge TickInfo, busy/result_valid, **all 64 INT32 elements in each of the two result slots**, and a field-derived 32-bit internal-state hash. The hash includes control and active-mode pipeline/accumulator state, without C structure padding.
5. The original C tests separately used independent i/j/k GEMM to check mathematical results, dense wavefront timing, sparse pipeline behavior, FIFO ordering, and latency.

Coverage includes zero, extremes, stored zero, gaps, long output holds, cross-tile
overlap, mode changes, and reset/restart. Four C-only rejected calls involving
NULL pointers or active indices ≥8 remain covered by C; a 3-bit SV index cannot
represent ≥8. Padding index=255 is truncated to 7 during conversion but remains
unused padding. Records include reset-discarded work and contract tests excluded
from tile totals, so publish/consume counts differ from the final 6,389 tiles.

Verilator `--Wall` lint passed. SV syntax and scripts target ModelSim, but the
original environment lacked ModelSim; **the simulator used for that delivery
was Verilator**. FPGA/ASIC synthesis, STA, and formal equivalence were not run.
State-hash comparison is not a formal proof.

## Optional vector regeneration

Windows, in a C11-capable Visual Studio x64 Native Tools Command Prompt:

```bat
generate_vectors.bat
generate_vectors.bat --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

Linux/GCC:

```bash
bash generate_vectors.sh
bash generate_vectors.sh --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

Generation overwrites local `c_vectors.txt` and the C test log; rerun
`run_modelsim.do` afterward. `generate_c_vectors.c` includes the original
testbench and renames its main; **do not also compile tb_tensor_core.c as a
separate compilation unit** when building the generator. Included
`run_verilator.sh` runs the same SV testbench on Linux with Verilator installed.
