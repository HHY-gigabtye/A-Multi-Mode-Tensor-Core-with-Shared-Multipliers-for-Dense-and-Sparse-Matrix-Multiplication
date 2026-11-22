# Shared outer-product Tensor Core

The production module [`outer_product_core.sv`](outer_product_core.sv) accepts one indexed A/B operand pair per k slice. Dense, hybrid and dual-sparse tiles share operand routing, 64 signed INT8 multipliers, INT32 accumulation and two result slots. Routing restores the two eight-element INT8 vectors before multiplication, with zero-filled missing coordinates and separate presence masks. Products use fixed coordinates; the two 16-bit product-routing banks are removed. The fabric accumulator addition has `use_dsp="no"` to preserve the 64-DSP implementation. See the [November 22 promotion](../reports/verification/operand_route_main_20261122/README.md) and [measured comparison](../experiments/pre_route_20261122/REPORT.md). The dedicated dense systolic array and the earlier multiply-before-route shared core remain archived.

## Current packet and admission contract

`in_packet` is `tc_sparse_payload_t`: a 184-bit pair of indexed vectors, used
for **every** input format. Each operand has a 4-bit count (0..8), eight signed
INT8 values and eight 3-bit original-coordinate indices. Active indices must
be strictly increasing; stored zeros are legal and padding entries are ignored.
The type's historical `sparse` name does not restrict it to sparse input.

Before FIFO insertion, the integration top assigns dense operands `count=8`
and indices `0..7`, preserving all values. Decoded sparse counts/indices pass
through. The Bridge retains the `is_sparse` source-format tag for its sideband
check, but only the indexed payload reaches the TC. The core has no mode port,
`input_ready` port or format-switch drain requirement.

| Signal | Production behavior |
|---|---|
| `clk`, `rst_n` | Rising-edge update; active-low reset clears control, valid metadata, accumulators and result storage |
| `in_ready` | `(next_k != 0) || (outstanding < 2)`, using old state; reserve a result slot on k=0, then accept k=1..7 under that reservation |
| `in_valid`, `in_packet` | Actual legal offer; in integration, `in_valid = rst_n && head_valid && in_ready` |
| `result_valid`, `result_ready`, `result` | Transfer the old valid 8×8 INT32 result on an advancing edge; retain it under downstream stall |
| `busy` | At least one started tile has an unconsumed result, including partial input and pipeline work |
| `status` | `TC_OK`, `TC_BAD_SPARSE_VECTOR` or `TC_NOT_READY`; no mode-change status is emitted by this core |
| `tick_info` | Previous-edge observations; the retained `sparse_step` field now describes every outer-product format, while `dense_step` stays zero |

The strict valid contract requires `in_valid=0` while waiting for admission.
An offer without credit or with illegal active count/index metadata rejects
the entire edge, including a requested result pop, and clears `tick_info`.
Readiness alone does not validate metadata. A same-edge result pop cannot
fund a new tile when both result credits were already occupied.

## Current timing for every format

For legal input accepted consecutively with k=0 at edge 0:

| Event | Edge |
|---|---:|
| Accept k=7 | 7 |
| Earliest next tile start with available credit | 8 |
| Final accumulation | 9 |
| Publish result after the edge | 10 |
| Earliest result handshake | 11 |

Input gaps move publication with the last accepted slice: k=7 plus three
advancing edges. First/last markers align operand routing, MUL and ACC, allowing a new
tile to begin while the previous tile finishes. Dense, sparse and mixed streams
can all sustain a tile-start interval of eight cycles with available input and
result credit. Memory transfers and downstream stalls affect system throughput.

`tick_info.mul` retains its historical first-phase timing (now operand routing),
and `tick_info.route` retains second-phase timing (now multiplication). No external
latency or observation timing was changed by the promotion.

## Current files and verification

| File | Role |
|---|---|
| `tensor_core_pkg.sv`, `outer_product_core.sv` | Package and production core selected by the Vivado project and integration scripts |
| `tb_outer_core.sv` | Compatible legacy C-vector windows plus a directed full-credit rejection check |
| `tb_compare.sv` | Old/new core comparison using independent GEMM and each core's publication timing |
| `run_modelsim.do` | Runs `tb_outer_core`; it does not run the legacy full-trace test |
| `../integration_sv/tb/tb_outer_top.sv` | All three memory formats, dense normalization, mixed II=8, reset, backpressure and byte-level writeback |
| `tensor_core.sv`, `tb_tensor_core.sv`, `c_reference/` | Retained predecessor and original cycle reference; see the legacy section below |

From the repository root:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
# Isolated current TC unit:
vsim -c -do tensor_core_sv/run_modelsim.do
# All isolated units and the old/new comparison, followed by integration:
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1
```

The unchanged C trace encodes the predecessor's dense timing. The current unit
replays each window from reset up to the first valid legacy dense offer; it does
not claim full-trace cycle equivalence. Dense and mixed-format correctness and
timing use the comparison and integration scoreboards. The November 22 main-source
regression passes 21,032 compatible C records, 1,366 publications, six malformed
offers, one full-credit rejection, and the existing TC comparison. Integration
completes 369 tiles with 77 resets and preserves all 50 baseline summary lines,
including II=8 and k=7+3 timing. See the
[current verification evidence and applied diff](../reports/verification/operand_route_main_20261122/README.md).
These runs preceded this documentation update; no simulation is rerun for README edits.

The isolated experiment additionally exhausts all 65,536 A/B bitmap pairs in a
standalone TC comparison with independent GEMM, timing, error, backpressure, and
reset checks. Its snapshots, added tests, and results remain under the
[operand-routing experiment](../experiments/pre_route_20261122/README.md).
The promoted source matches the validated 64-DSP candidate exactly; the first
128-DSP attempt remains historical. Integrated post-route area, timing, and
functional-SAIF power estimates are in the [measurement report](../experiments/pre_route_20261122/REPORT.md),
not a fresh implementation of the main working tree.

## Legacy core and cycle reference

Everything below describes the retained `tensor_core.sv` and its original C model/testbench. Its 185-bit tagged input, mode-aware readiness, dense systolic latency and drain rules are **legacy-only**. The comparison suite still instantiates this module; production synthesis selects `outer_product_core.sv`.

This version was based on the supplied `tensor_core_model(1).c/.h` and
`tb_tensor_core(1).c`. The three original files in `c_reference/` only had `(1)`
removed from their names; their contents were unchanged. This package contains
only Tensor Core and accepts packets already decoded by DU/TIA.

### Running the legacy core manually

From this directory, run these ModelSim commands with the restored vector file.

```tcl
vlog -sv tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
vsim -onfinish stop -voptargs=+acc work.tb_tensor_core +VECTORS=c_vectors.txt
run -all
```

Run from this directory or change `+VECTORS=` to the vector path. RTL and the SV
testbench use no `assert` / SVA, UVM, classes, or DPI. Failures are reported with
procedural `if`, `$display`, and `$fatal`.

### Legacy files

| File | Purpose |
|---|---|
| `tensor_core_pkg.sv` | Packet, PE, pipeline, control-register, and other types |
| `tensor_core.sv` | Predecessor RTL for comparison; not the production synthesis core |
| `tb_tensor_core.sv` | Cycle-by-cycle C reference replay, comparing interfaces, results, and internal state |
| `waves.do` | Legacy TC waveforms |
| `c_vectors.txt` | Complete pregenerated vectors, approximately 144 MiB |
| `c_reference/` | Original C model/testbench and vector generator |
| `generate_vectors.bat` / `.sh` | Regenerates vectors when changing seeds or test counts |
| `c_reference_results.txt` | Original C test results |
| `verification_results.txt` | Recorded Verilator C/SV comparison results |
| `SOURCE_SHA256.txt` | SHA-256 of the three original C files |

### Legacy behavior

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

The retained legacy `tensor_core.sv` uses separate dense and sparse multiplier inputs. Sparse
MUL product data has synchronous, non-reset storage at the original MUL edge;
the asynchronously reset valid/count metadata masks unused products to zero in
the logical `sparse_q` view. Rejected edges hold raw products. This enables DSP
PREG mapping without an extra pipeline cycle or a change to reset-visible state.
ROUTE uses direct one-hot matches because input validation rejects duplicate or
non-increasing indices before the entire edge commits. The original cycle,
state-hash and result-slot regressions remain unchanged. Mapping, timing and
candidate comparisons are recorded in the
[10 ns experiment](../experiments/msu_fmax/target_10ns_20261110/README.md).

### Legacy timing

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

### Legacy interface

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

### Legacy packet format and DU/TIA

`tc_input_packet_t` is 185 bits and matches the field order and widths of the
supplied `du_tia_pkg::du_tia_output_t`, permitting the cast above. Standalone TC
compilation does not depend on du_tia_pkg.

- Dense: `payload.dense.dense_a[i] = A[i][k]`, `dense_b[j] = B[k][j]`.
- Sparse: `a/b.count` is 0..8; valid value/index entries are 0..count-1.
- Indices are 3-bit original coordinates 0..7 and strictly increasing in the valid prefix. Padding values and indices are ignored.
- Lane 0 occupies the least-significant byte/field of its packed array; assign through field indices.
- No extra k, tile_start, first, last, or original compiler-mode input is required.
- Hybrid, dual sparse, and dense×unstructured decoded inputs share the is_sparse=1 path.

### Original legacy validation

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

### Optional legacy vector regeneration

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

Generation overwrites local `c_vectors.txt` and the C test log. Use an isolated
copy and compare against the immutable reference; run the manual legacy replay
above when checking the full legacy trace. `run_modelsim.do` selects the current
shared-core unit. `generate_c_vectors.c` includes the original
testbench and renames its main; **do not also compile tb_tensor_core.c as a
separate compilation unit** when building the generator. Included
`run_verilator.sh` runs the same SV testbench on Linux with Verilator installed.
