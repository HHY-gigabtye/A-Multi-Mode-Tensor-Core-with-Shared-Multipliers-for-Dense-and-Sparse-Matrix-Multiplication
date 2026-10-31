# Sparse Tensor Core — Architecture and Project Handoff

> Prepared/updated: 2026-10-24. This **handoff document** consolidates earlier design discussions and the supplied MLU/MSU, Bridge, and TC reference documents. It is not a complete source-code audit of the local checkout. Statements marked **[VERIFY]** require comparison against the latest local implementation and test results.
>
> Historical context: later source reconciliation and verification evidence are documented in the [source audit](source-audit.md) and [repository README](../README.md). The historical claims and open checks below are preserved as handoff context, not restated as current verification results.

## 1. Objective and Current Scope

The project implements an 8×8 Tensor Core supporting dense and sparse execution. Cycle-level C models define behavior, followed by SystemVerilog RTL generation and regression testing, with ASIC synthesis and PPA optimization planned afterward in the original handoff.

```text
Simplified memory/HBM model
       |
       v
  MLU (2 tile buffers; load + encode/packetize)
       | k=0..7, valid/ready
       v
  DU/TIA (S0-S3, 4-stage fixed pipeline; no out_ready)
       | decoded payload + aligned sideband
       v
  DU-TC Bridge: packet FIFO (8) + inflight credits
                + result metadata FIFO (2)
       | mode-aware gating
       v
  Tensor Core: dense systolic / sparse outer-product
               (2 result slots)
       | 8x8 INT32 matrix + ordered metadata
       v
  MSU (2 whole-result buffers; 8 write beats)
       |
       v
Simplified memory write endpoint
```

Each command represents an **independent 8×8×8 tile**: eight packets with k=0..7 and one 8×8 INT32 result. **There is no accumulation across K blocks.** Real HBM/AXI transaction responses, shared read/write arbitration, and complete memory consistency are outside this simplified model's scope.

## 2. Precision and Modes

| Item | Design contract |
|---|---|
| Matrix dimensions | M=N=K=8; eight k slices per tile |
| Operands | Signed INT8 (-128 to 127) |
| Product | Signed 16-bit storage is sufficient for one INT8×INT8 product |
| Accumulator / result | Signed INT32; 8×8 result |
| `IO_DENSE=0` | Dense A × dense B; 8×8 systolic |
| `IO_HYBRID=1` | Unstructured A × 2:4 structured B; sparse outer product |
| `IO_DUAL=2` | Unstructured A × unstructured B; sparse outer product |
| `mode=3` | Illegal |

TC receives **packets already decoded by DU/TIA**:

- Dense payload: `dense_a[8] = A[:,k]` and `dense_b[8] = B[k,:]`. The TC datapath handles the required input skew.
- Sparse payload: each A/B vector contains `count` (0..8), `value[8]`, and `index[8]`. Only the first `count` entries are interpreted. Indices identify original rows/columns 0..7 in increasing order. Valid stored-zero entries are legal.
- Both sparse modes use `is_sparse=1` at TC after decoding. Do not send the original 2:4 bitmap into TC for a second decoding pass.
- Even when SV fields are stored as `logic [7:0]`, multiplication requires **correct sign extension / `$signed(...)`**.
- C structs, SV packed unions, and HBM byte images **do not have binary layouts compatible with direct memcpy**. Map their fields explicitly.

## 3. MLU: Memory Load Unit

- Source command: `mode`, `src_addr`, `meta.tile_id` (32 bits), and `meta.dst_addr` (64 bits). Source and destination addresses must be aligned to **32 bytes**.
- Two tile buffers load and output commands in order. Output of the previous tile may overlap preloading of the next, but only one tile's k=0..7 sequence is streamed at a time.
- A buffer may be reused only after **successful handshake** of k=7. It need not wait for TC computation or MSU writeback of that tile.
- Memory request: `read_request_valid && read_request_ready`; response: `read_data_valid && read_data_ready`. Each beat contains 32 bytes, and `read_last` marks the final burst beat. The model allows **at most one outstanding read burst**. Responses are ordered, with the first beat no earlier than the cycle after the request.
- The complete tile is read before generating its eight DU/TIA packets. When downstream blocks, MLU `out_valid` and payload must remain stable.
- `k_position = k % 4`. Full k, tile ID, and destination address travel in sideband metadata without changes to the original DU/TIA ports.

### 3.1 Fixed Memory Image Layout (Bytes)

| Mode | Meaningful data | Actual read | Layout relative to `src_addr` |
|---|---:|---:|---|
| Dense | 128 B | 4 × 32 B = 128 B | Per-k offset=`16*k`: first A[:,k] 8B, then B[k,:] 8B |
| Hybrid | 120 B | 4 × 32 B = 128 B | First 72B: per k, A bitmap 1B + A packed[8] 8B; last 48B: two B groups, each with 8 columns × (mask 1B + values 2B) |
| Dual sparse | 144 B | 5 × 32 B = 160 B | Per k: A bitmap 1B + A packed[8] 8B + B bitmap 1B + B packed[8] 8B |

For hybrid B group `g∈{0,1}` and column j, the offset is `72 + 24*g + 3*j`; the four k positions correspond to `k=4*g+p`. The B 2:4 mask uses the low 4 bits and must have exactly two set bits, giving six legal masks. The two packed B values follow the increasing k positions of those set bits and are reused within the group.

A bitmap bit i represents row i; dual B bitmap bit j represents column j. Unstructured values are packed in increasing original-index order, with popcount determining the valid count. Invalid padding bytes do not participate in computation. This is a **fixed-space memory image**, not a maximally compressed variable-length format.

## 4. DU/TIA: Decompression and Index Alignment

- Preserve the original four registered input-to-output stages S0/S1/S2/S3, with no `out_ready` feedback. Insert bubbles using `in_valid=0`.
- Dense mode preserves the original forwarding path without sparse decoding. In hybrid/dual modes, DU decoding and TIA alignment produce the sparse payload needed by TC. **Use the current RTL and C model for per-stage structures and control logic; do not independently rename or repartition stages.**
- A parallel four-stage sideband outside DU/TIA stores `valid/is_sparse/meta/k`. The full matrix payload does not need to be duplicated through this sideband.
- DU/TIA cannot stall, so downstream Bridge capacity must be reserved with credits. Current FIFO occupancy alone is insufficient.

## 5. Bridge / FIFO / Metadata — Critical Cycle-Level Contract

### 5.1 Capacity and Credits

- `IO_PACKET_FIFO = 8`; DU/TIA sideband stages = 4; result metadata queue = 2.
- `used = fifo_count + inflight_count <= 8`, where `inflight_count` includes packets in S0..S3 that have not yet entered the FIFO.
- `can_issue = (used < 8)` uses **old registered state**. When old used=8, a same-edge TC pop cannot provide a speculative credit for another issue.
- `issue` denotes the actual MLU→DU/TIA handshake. issue=1 reserves 1 credit. On `du_valid` arrival, `inflight--` and `fifo_count++`, preserving total occupied credit. On `tc_accept`, `fifo_count--` and 1 credit is released.
- Normal full/backpressure conditions cause stalls. Asserting `issue=1` despite `can_issue=0` makes the C model report the `IO_NO_CREDIT` contract error. A non-`IO_OK` edge does not update Bridge state; this is diagnostic behavior, not a general pause mechanism.
- The FIFO head is read combinationally: **no additional head output register and no same-edge DU→TC bypass**.

### 5.2 Edge Timing

Assume an MLU input is accepted at edge `t`:

| Time | Packet location |
|---|---|
| Edge `t` | Enters DU/TIA S0 |
| `t+1` | S1 |
| `t+2` | S2 |
| `t+3` | S3 |
| `t+4` | Bridge accepts old S3 and writes the FIFO |
| `t+5` (earliest) | TC accepts the FIFO head |

**Calculate all same-cycle peek/handshake decisions from old state, then tick every module exactly once.** Do not update DU first and use its new S3 value as FIFO input on that same edge.

### 5.3 TC Strict Valid and Result Metadata

- For the current TC, `in_valid=1` while not ready is a contract error, not standard "hold valid until ready" behavior. The Bridge/link must continuously present `head_entry.packet` to TC, then use mode-aware `in_ready` to decide whether `tc_valid` may be asserted.
- `tc_valid = head_valid && tc_mode_aware_in_ready`, with reset gating as needed. `tc_accept` denotes actual acceptance. Do not derive TC valid directly from FIFO nonemptiness or rely only on non-mode-aware `input_ready`.
- If the head has k=0 and the metadata FIFO already contains 2 entries, `head_valid=0` blocks a new tile.
- Enqueue `{tile_id,dst_addr}` only when **TC actually accepts k=0**. Dequeue when **MSU accepts** the TC result (`result_accept`), not when MLU issues k=0 or MSU completes the final HBM write beat.
- External logic must guarantee increasing k=0..7 and consistent metadata within each tile. Do not assume the Bridge validates every sequence rule.

## 6. Tensor Core Compute Engine

### 6.1 Dense

- An 8×8 **output-stationary systolic array** processes eight k slices per tile, with input skew and propagation through adjacent PE registers.
- Dense computation and mode-switch scheduling do not necessarily have sparse-style tile overlap. Follow the current TC C model/SV cycle behavior.

### 6.2 Sparse

- Sparse outer-product datapath: **multiply register → route register → accumulate**.
- A packet's A count/index/value × B count/index/value determines active multiplications and the final accumulator row/column locations. Each completed tile outputs 8×8 INT32.
- The TC result FIFO has two physical slots. Results remain until downstream accepts them; they must not be overwritten or corrupted by the next tile.
- Original design target/prior model behavior: an unstalled sparse stream can **start a new tile every 8 cycles**, with 8 packets/tile and overlapping tiles. This assumes specific steady-state conditions and does not guarantee end-to-end writeback completion every 8 cycles.
- Dense↔sparse changes must obey TC draining requirements, including outstanding results. Hybrid↔dual are both sparse at TC; input-mode decoding remains in DU/TIA.
- [VERIFY] Earlier discussions placed dense results around cycle 22 and sparse results around cycle 10 with consecutive tile input. These were relative cycle descriptions from earlier C/RTL examples. **Do not turn these values into fixed top-level latency tests without checking the latest version.**

## 7. MSU: Memory Store Unit

- TC→MSU transfers `TcMatrix32` (8×8 INT32) and `IoMeta` (tile ID and destination address). An empty result buffer accepts them only on `result_valid && result_ready`.
- MSU has two **complete-result** buffers. If an earlier write stalls, another result may still be accepted while capacity remains. Result order is preserved.
- Each tile occupies 256B, written as eight **32-byte / 256-bit** row-major beats. Row `r` uses address `dst_addr + 32*r`.
- INT32 element j occupies bytes `[4*j]..[4*j+3]` of the beat, in **little-endian** order.
- During `write_valid && !write_ready`, address, data, metadata, and `write_last` must remain stable.
- `tile_done` occurs **only after the row 7 write is actually accepted**. Acceptance of a TC result into MSU is not HBM writeback completion.
- This version has no cross-K-block summation or write-response channel. Model `write_ready` means the endpoint accepts and commits that beat.

## 8. Test Strategy and Known Verification Records

### 8.1 Unit Verification First

Suggested organization (**illustrative paths; inspect the actual directory tree first**):

```text
project_root/
  AGENTS.md
  docs/architecture.md
  C_Model/        # Golden references and known test vectors
  RTL/            # Synthesizable module sources and packages
  Testbench/      # Standalone unit TBs and system-level TB
  reports/        # Timing/area reports and comparison notes
```

Standalone unit testbenches model upstream/downstream signals at their boundaries:

- MLU TB: model memory responses and DU/FIFO `ready`; test tile packing, buffer switching, and stalls.
- Bridge TB: model `issue`, fixed four-stage DU returns, TC acceptance, and MSU result acceptance without instantiating the other real units. Test credits, sideband, FIFO, metadata, and reset.
- TC TB: independently verify dense/sparse GEMM, modes, the result FIFO, and exact cycle behavior.
- MSU TB: model the TC result stream and memory `write_ready`; verify bytes, beats, `tile_done`, and backpressure.
- After these pass, integrate the complete MLU→DU/TIA→Bridge→TC→MSU top.

### 8.2 Records Preserved from Earlier Deliveries (Not Current Local Verification Claims)

- The C MLU/MSU/integration README recorded MLU 120 tiles/960 packets, MSU 120 results/960 beats, and C integration 474 completed tiles plus work discarded by reset. That delivery ran with GCC; **it does not establish that all current SV units passed the same integrated verification**.
- The standalone Bridge RTL README recorded Verilator C-equivalence over 19,147 input/state rows, including 7,156 expected rejected edges and 13 resets. **ModelSim/Questa entry scripts existed but had not been run at that delivery stage**.
- Earlier TC RTL discussions mentioned Verilator regressions. Exact counts, tool versions, and outcomes must be checked in current repository logs rather than treated as current results.
- [VERIFY] MLU, MSU, FIFO, and other SV/test versions had recently been produced in ChatGPT discussions. **This does not establish that all unit regressions or full-system RTL integration were completed on the user's machine**.
- [VERIFY] Preliminary ASIC synthesis discussions mentioned **approximately 80–83 MHz, unplaced**. This is insufficient to establish post-route Fmax. Preserve the tool, cell library/corner, clock period, constraints, critical path, area, and routing phase before identifying the bottleneck.

### 8.3 Local Verification Checklist

1. Compare mode encodings, field signedness/widths, memory images, and timing interfaces across the C models, RTL, and packages.
2. Run the C references and all standalone unit testbenches. Save commands, versions, PASS/FAIL results, and seeds.
3. Cover dense/hybrid/dual, legal 2:4 masks `0011/0101/0110/1001/1010/1100`, INT8 extremes, 0 count, and stored zeros.
4. Cover FIFO full plus in-flight occupancy, full metadata, same-edge push/pop, pointer wrap, reset during in-flight traffic, and upstream/downstream stalls.
5. Verify consecutive tiles across modes, sparse initiation interval, and result order. Then perform end-to-end GEMM and memory-writeback comparisons.
6. Only after functional tests pass, inspect synthesis timing reports, make minimal changes targeting the critical path, and rerun regression. Do not infer timing from whether Work or Codex generated the design.

## 9. Original Sources and Implementation Cross-Checks

Search the local project for these **base names**. Historical copies may contain `(1)`, `(2)`, or similar suffixes; first determine which version is latest and which is verified.

| Area | Historical source files / key names |
|---|---|
| MLU | `mlu_model.c/.h`, `tb_mlu.c`, `mlu.sv`, `tb_mlu.sv` |
| DU/TIA | `du_tia*.c/.h`, `du_tia_pkg.sv`, `du_tia.sv` |
| Bridge | `du_tc_bridge.c/.h`, `du_tc_bridge_pkg.sv`, `du_tc_bridge.sv`, `tb_bridge.sv` |
| TC | `tensor_core_model.c/.h`, `tb_tensor_core.c`, `tensor_core.sv`, `tensor_core_pkg.sv`, `tb_tensor_core.sv` |
| MSU | `msu_model.c/.h`, `tb_msu.c`, `msu.sv`, `tb_msu.sv` |
| Integration | `io_types.h`, `tb_pipeline.c`, possible `du_tc_bridge_link.sv`, full-system SV TB |

Earlier C packages included `make test` / `build_msvc.bat` examples; Bridge SV packages included `run_bridge.do` and `run_tests.py` examples. **These are historical package commands. Do not assume the scripts exist at the current local repository root.** List actual directories before selecting runnable commands.

## 10. Suggested First Codex Handoff Task

Start with an audit without modifying files:

> Read AGENTS.md and docs/architecture.md. Inspect the local repository and locate the authoritative C, RTL, testbenches, packages, vectors, and scripts. Distinguish working baseline from incomplete copies. Compare the local implementation against each stated interface/cycle contract, flag conflicts, and propose a minimal standalone regression order. Do not edit or delete files, alter expected outputs, or claim tests passed without executing them.

**Use the local Git working tree and reproducible tests as the basis for subsequent discussions.** This handoff supplies background and preserves existing design decisions so Codex can understand the project without overlooking them.
