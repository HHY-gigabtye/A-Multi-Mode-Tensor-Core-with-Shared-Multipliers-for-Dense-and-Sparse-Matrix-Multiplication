# Sparse Tensor Core — Architecture and Project Handoff

> Prepared on 2026-10-24 from earlier design discussions and the supplied MLU/MSU,
> Bridge, and TC reference documents. This is a **handoff document**, not a complete
> audit of the current local source tree. Statements marked **[VERIFY]** must be
> checked against the latest local implementation and test results.

> Updated on 2026-11-21 for the shared outer-product TC on `main`. The dense systolic path and mode-aware admission described in the October handoff apply to the predecessor. [Integration and verification record](../reports/verification/outer_main_20261121/README.md)

> Updated on 2026-11-22: production now restores operand coordinates before multiplication and uses the shared DU/TIA whole-union assignment repair. The prior snapshots and reports are retained. [Promotion and verification record](../reports/verification/operand_route_main_20261122/README.md)

## 1. Goal and current scope

The project implements an 8×8 Tensor Core supporting dense and sparse workloads.
The current SystemVerilog core shares one outer-product pipeline across all
three input formats. The retained C TC model describes the predecessor: its
compatible sparse windows remain a cycle oracle, while dense and mixed-format
behavior use the current RTL contract and independent GEMM tests. The
[November 21 record](../reports/verification/outer_main_20261121/README.md)
documents the transition to shared multipliers. The
[November 22 promotion](../reports/verification/operand_route_main_20261122/README.md)
records the current operand-routing core, DU/TIA repair, fresh main-source
regression, and retained source-matched FPGA post-route evidence. ASIC
implementation remains outside the verified scope.

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
       | indexed operands and result-credit gating
       v
  Tensor Core: shared outer product
               (2 result slots)
       | 8x8 INT32 matrix + ordered metadata
       v
  MSU (2 whole-result buffers; 8 write beats)
       |
       v
Simplified memory write endpoint
```

Each command represents an **independent 8×8×8 tile**: eight k=0..7 packets and
one 8×8 INT32 result, with **no cross-K-block accumulation**. Real HBM/AXI
transaction responses, shared read/write arbitration, and full memory coherency
are outside the simplified model's scope.

## 2. Precision and modes

| Item | Design contract |
|---|---|
| Matrix dimensions | M=N=K=8; eight k slices per tile |
| Multiplication operands | Signed INT8 (-128 to 127) |
| Product | Signed 16 bits suffice for one INT8×INT8 product |
| Accumulator / result | Signed INT32; 8×8 result |
| `IO_DENSE=0` | Dense A × dense B; full-count indexed outer product |
| `IO_HYBRID=1` | Unstructured A × 2:4 structured B; sparse outer product |
| `IO_DUAL=2` | Unstructured A × unstructured B; sparse outer product |
| `mode=3` | Illegal |

The top normalizes DU/TIA output before the packet FIFO. Both operands use the same TC interface.

- Dense A[:,k] and B[k,:] keep all eight values, including zeros. Each operand gets `count=8` and indices `0..7` in lane order.
- Sparse payload: A and B each contain `count` (0..8), `value[8]`, and `index[8]`. Only the first `count` entries are valid. Indices identify original rows/columns 0..7 in increasing order. Stored zeros in the valid prefix are legal.
- The tag `is_sparse` identifies the source format for the Bridge sideband check. The TC receives only the indexed payload.
- Even fields stored as `logic [7:0]` require **correct sign extension / `$signed(...)`** during multiplication.
- C structures, SV packed unions, and HBM byte images **do not have memcpy-compatible binary layouts**; map fields explicitly.

## 3. MLU: Memory Load Unit

- Commands contain `mode`, `src_addr`, `meta.tile_id` (32 bits), and `meta.dst_addr` (64 bits). Source and destination addresses must be **32-byte aligned**.
- Two tile buffers load and output commands in order. A previous tile can output while the next preloads, but only one tile's k=0..7 stream is issued at a time.
- Reuse a buffer only after **successful acceptance** of k=7; do not wait for TC computation or MSU writeback.
- Read request: `read_request_valid && read_request_ready`; response: `read_data_valid && read_data_ready`. Each beat is 32 bytes and `read_last` identifies the final beat. There is **at most one outstanding read burst**; responses are ordered and the first beat arrives no earlier than the next edge after the request.
- Load the complete tile before issuing its eight DU/TIA packets. Hold MLU `out_valid` and payload stable under downstream blocking.
- `k_position = k % 4`; full k, tile ID, and destination address travel in sideband metadata without changing DU/TIA ports.

### 3.1 Fixed memory image layout (bytes)

| Mode | Valid data | Actual read | Layout relative to `src_addr` |
|---|---:|---:|---|
| Dense | 128 B | 4 × 32 B = 128 B | For each k, offset=`16*k`: 8B A[:,k], then 8B B[k,:] |
| Hybrid | 120 B | 4 × 32 B = 128 B | First 72B: A bitmap 1B + A packed[8] 8B for each k; final 48B: two B groups, each with 8 columns × (mask 1B + values 2B) |
| Dual sparse | 144 B | 5 × 32 B = 160 B | Per k: A bitmap 1B + A packed[8] 8B + B bitmap 1B + B packed[8] 8B |

Hybrid B group `g∈{0,1}` and column j use offset `72 + 24*g + 3*j`; the four k
positions correspond to `k=4*g+p`. B's 2:4 mask uses the low 4 bits and must have
exactly two set bits (six legal masks). Its two packed values follow the set-bit
k positions in ascending order and are reused within the group.

A bitmap bit i identifies row i; dual B bitmap bit j identifies column j.
Unstructured values are packed by increasing original index, with valid count
from popcount. Invalid padding bytes do not participate. This is a **fixed-size
memory image**, not a variable-length maximum-compression format.

## 4. DU/TIA: Decompression and index alignment

- Preserve the four registered S0/S1/S2/S3 stages and absence of downstream `out_ready`; insert bubbles with `in_valid=0`.
- Dense mode retains its existing path without sparse decoding. DU decoding and TIA alignment produce sparse TC payloads for hybrid/dual. **Actual RTL and C models define per-stage structures and control; do not rename or repartition stages without checking them.**
- A parallel four-stage sideband outside DU/TIA stores `valid/is_sparse/meta/k`; it need not duplicate the full matrix payload.
- DU/TIA cannot stall, so Bridge must reserve credit for future output rather than checking only current FIFO occupancy.
- S1 and S2 assemble dense/sparse fields in plain packed structs and assign the selected packed union once. This preserves the algorithm and four registers while avoiding the RTL/netlist mismatch reproduced with the prior partial-union-write form under Vivado 2022.2.

## 5. Bridge / FIFO / metadata: Critical cycle-level contract

### 5.1 Capacity and credits

- `IO_PACKET_FIFO = 8`; DU/TIA sideband has 4 stages; result metadata queue has 2 entries.
- `used = fifo_count + inflight_count <= 8`, where `inflight_count` includes packets already in S0..S3 but not yet in the FIFO.
- `can_issue = (used < 8)` uses **old registered state**. When old used=8, a same-edge TC pop cannot supply speculative credit.
- `issue` is an actual MLU→DU/TIA handshake and reserves one credit. Arrival of `du_valid` performs `inflight--` and `fifo_count++`, preserving total occupancy. `tc_accept` performs `fifo_count--` and releases one credit.
- Normal full/backpressure is a stall. Asserting `issue=1` while `can_issue=0` produces the C model's `IO_NO_CREDIT` contract error. Non-`IO_OK` edges do not update Bridge state; this is diagnostic behavior, not a normal pause mechanism.
- The FIFO head is combinational: **no extra head output register and no same-edge DU→TC bypass**.

### 5.2 Edge timing

For an MLU input accepted on edge `t`:

| Edge | Packet location |
|---|---|
| `t` | Enters DU/TIA S0 |
| `t+1` | S1 |
| `t+2` | S2 |
| `t+3` | S3 |
| `t+4` | Bridge accepts old S3 and writes the FIFO |
| `t+5` (earliest) | TC accepts the FIFO head |

**Compute every module's peek/handshake from old state, then tick every module
once.** Do not update DU first and use its new S3 as the same-edge FIFO input.

### 5.3 TC strict valid and result metadata

- The Bridge continuously presents the head. The top drives the strict input-valid pulse as `rst_n && head_valid && tc_in_ready`. At the first slice of a tile the TC requires an available result slot. It accepts subsequent slices under the same reservation.
- If the head has k=0 and the metadata FIFO already contains 2 entries, set `head_valid=0` to block a new tile.
- Enqueue `{tile_id,dst_addr}` only when **TC actually accepts k=0**. Dequeue only when **MSU accepts the TC result** (`result_accept`), not when MLU issues k=0 or when MSU finishes the final HBM write beat.
- Upstream guarantees k=0..7 ordering and consistent tile metadata; do not assume Bridge checks every sequence rule.

## 6. Tensor Core computation

The current shared pipeline is **Routing → MUL → ACC** for dense, hybrid, and dual-sparse tiles.

Each accepted slice first restores A and B independently from packed operand lanes to original row and column coordinates, zero-filling missing coordinates. The first stage registers two eight-element INT8 vectors and separate presence masks. The second stage registers fixed-coordinate products from one 8×8 bank of signed INT8 multipliers. The accumulator sign-extends each product into INT32 and initializes each output coordinate on the first slice of a tile. The fabric addition is explicitly marked `use_dsp="no"`, while multiplication uses `use_dsp="yes"`, preserving 64 DSPs. The historical `tick_info.mul` and `tick_info.route` fields still observe the first and second phases respectively; their names do not describe the new physical ordering.

All three formats use the same pipeline and two result slots. A tile reserves its slot when k=0 is accepted and releases it on the result handshake. With eight consecutive accepted slices, the result becomes available three advancing edges after acceptance of k=7. Unstalled dense, sparse and mixed streams can start a tile every eight cycles. Format changes have no drain requirement. End-to-end writeback also depends on MSU and memory readiness.

## 7. MSU: Memory Store Unit

- TC→MSU transfers `TcMatrix32` (8×8 INT32) with `IoMeta` (tile ID and destination address). An empty MSU result buffer accepts only on `result_valid && result_ready`.
- MSU has two **complete-result** buffers. It may accept another result while earlier writes stall if capacity remains, preserving order.
- Each tile is 256B, written as eight **32-byte / 256-bit** row-major beats. Row `r` uses address `dst_addr + 32*r`.
- INT32 element j occupies bytes `[4*j]..[4*j+3]` in **little-endian** order.
- Hold address, data, metadata, and `write_last` stable while `write_valid && !write_ready`.
- Assert `tile_done` **only after row 7 is actually accepted for writing**. Accepting a TC result into MSU does not mean HBM writeback is complete.
- This version has no cross-K-block sum or write-response channel; model `write_ready` means the endpoint accepts and commits the beat.

## 8. Test strategy and historical verification records

### 8.1 Unit tests first

Suggested organization (**illustrative paths; inspect the actual tree first**):

```text
project_root/
  AGENTS.md
  docs/architecture.md
  C_Model/        # Golden references and known test vectors
  RTL/            # Synthesizable module sources and packages
  Testbench/      # Standalone unit TBs and system-level TB
  reports/        # Timing/area reports and comparison notes
```

Model upstream/downstream behavior at each standalone unit boundary:

- MLU TB: memory responses and DU/FIFO `ready`; test packing, buffer switching, and stalls.
- Bridge TB: `issue`, fixed four-stage DU returns, TC acceptance, and MSU result acceptance; test credit, sideband, FIFO, metadata, and reset without instantiating other real units.
- TC TB: independently check dense/sparse GEMM, modes, result FIFO, and exact cycle behavior.
- MSU TB: TC result stream and memory `write_ready`; check bytes, beats, `tile_done`, and backpressure.
- Only after these pass, test full MLU→DU/TIA→Bridge→TC→MSU integration.

### 8.2 Records retained from earlier deliveries, not current local verification claims

- The C MLU/MSU/integration README recorded MLU 120 tiles/960 packets, MSU 120 results/960 beats, and C integration 474 completed tiles plus work abandoned by reset. Those runs used GCC; **they do not establish that all current SV units passed equivalent integration tests**.
- The standalone Bridge RTL README recorded Verilator C-equivalence over 19,147 input/state rows, including 7,156 expected rejected edges and 13 resets. **ModelSim/Questa scripts existed but had not been executed at that delivery**.
- Earlier TC RTL discussions mention Verilator regression, but current logs must establish counts, tool versions, and results.
- [VERIFY] MLU/MSU/FIFO SV and test versions were produced in earlier ChatGPT discussions. **That does not establish completed local unit regression or full-system RTL integration**.
- [VERIFY] An early ASIC synthesis discussion mentioned **approximately 80–83 MHz, unplaced**. That does not establish post-route Fmax. Record tools, library/corner, period, constraints, critical path, area, and implementation stage before diagnosing bottlenecks.

### 8.3 Local validation checklist

1. Compare mode encodings, signedness/widths, memory images, and timing interfaces across C models, RTL, and packages.
2. Run C references and every isolated unit TB; preserve commands, versions, PASS/FAIL, and seeds.
3. Cover dense/hybrid/dual, legal 2:4 masks `0011/0101/0110/1001/1010/1100`, INT8 extremes, count=0, and stored zeros.
4. Cover FIFO full plus inflight, metadata full, same-edge push/pop, wrap-around, reset during inflight work, and upstream/downstream stalls.
5. Check continuous mixed-mode tiles, sparse initiation interval, and result order; finish with end-to-end GEMM and memory-writeback comparisons.
6. After functional checks pass, inspect synthesis timing and optimize critical paths one concern at a time with regression after each change. Do not infer timing quality from whether Work/Codex generated the design.

## 9. Finding authoritative sources

Search for these **base names**. Historical `(1)`, `(2)`, or other copies may
exist; first determine which are current and verified.

| Area | Historical source / key names |
|---|---|
| MLU | `mlu_model.c/.h`, `tb_mlu.c`, `mlu.sv`, `tb_mlu.sv` |
| DU/TIA | `du_tia*.c/.h`, `du_tia_pkg.sv`, `du_tia.sv` |
| Bridge | `du_tc_bridge.c/.h`, `du_tc_bridge_pkg.sv`, `du_tc_bridge.sv`, `tb_bridge.sv` |
| TC | `outer_product_core.sv`, `tensor_core_pkg.sv`, `tb_outer_core.sv`, `tb_compare.sv`; predecessor `tensor_core.sv` and `tensor_core_model.c/.h` |
| MSU | `msu_model.c/.h`, `tb_msu.c`, `msu.sv`, `tb_msu.sv` |
| Integration | `io_types.h`, `tb_pipeline.c`, possible `du_tc_bridge_link.sv`, full-system SV TB |

Historical C packages include `make test` / `build_msvc.bat` examples, and Bridge
SV packages include `run_bridge.do` / `run_tests.py`. **Do not assume these
historical commands exist at the current repository root.** Inspect the tree
before selecting executable commands.

## 10. Suggested initial Codex handoff task

Audit without modifying files first:

> Read AGENTS.md and docs/architecture.md. Inspect the local repository and locate the authoritative C, RTL, testbenches, packages, vectors, and scripts. Distinguish working baseline from incomplete copies. Compare the local implementation against each stated interface/cycle contract, flag conflicts, and propose a minimal standalone regression order. Do not edit or delete files, alter expected outputs, or claim tests passed without executing them.

**The local Git worktree and reproducible tests are authoritative for subsequent
work.** This handoff provides context and preserves earlier design decisions.
