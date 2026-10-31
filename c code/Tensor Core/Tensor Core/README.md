# Tensor Core: C Model with Sparse Tile Overlap

> Scope note: this document records the original C-model delivery. Its tool and verification statements refer to that delivery, not the later RTL/integration work. See the [repository README](../../../README.md) and [source audit](../../../docs/source-audit.md) for current repository entry points and later evidence.

This revision was based on the supplied `tensor_core_model(2).c`, `tensor_core_model(2).h`, and `tb_tensor_core(2).c`. Delivered files use the standard filenames required by their includes.

## Files and Scope

| File | Purpose |
| --- | --- |
| tensor_core_model.h | Data structures, API, and handshake rules |
| tensor_core_model.c | Cycle-level C model, without main |
| tb_tensor_core.c | Existing single-tile tests, added consecutive-tile scoreboard, performance measurement, and the only main |
| verification.txt | Recorded compilation/execution output and verification limitations |

- Preserves INT8 × INT8 → INT32 and M=N=K=8; every eight successfully accepted packets form a tile.
- The sparse/outer-product path supports input overlap across tiles. Sparse formats after DU/TIA all use the same `is_sparse=true` path.
- The dense systolic path remains one tile at a time, retaining the original per-PE arrival-timing checks.
- Mode changes require all started tiles to finish, all results to be consumed, and `busy=false`.
- The original revision changed only the C model and testbench. It did not add DU/TIA, MLU, or MSU, or generate/verify revised RTL.
- The testbench's `dense-unstructured` category constructs decoded packets directly; it does not add a DU/TIA compiler mode.

## Operation

### 1. Propagate first/last Through MUL and ROUTE to ACC

No new first/last input fields are required. The core automatically derives tile boundaries from every eight successfully accepted packets.

The entire accumulator matrix is cleared when the first packet reaches ACC, before adding that packet's valid products. This also works when the first packet has count=0. Accepting the next tile's first input does not clear the previous tile's still-active computation.

### 2. Save the Previous Result and Start the Next Accumulation on the Same Edge

`finish_pending` retains a one-cycle result-publication stage. `tc_tick()` first copies the old ACC value into the result FIFO, then calls `sparse_tick()` to update ACC. This includes the previous tile's final products in its output and prevents the next tile's first-packet clear from destroying that result.

RTL must preserve the semantics of reading previous-cycle state before committing next-cycle state. These operations cannot be arbitrarily reordered.

### 3. Reserve One of Two Fixed Result Slots Before Starting a Tile

`result` is the FIFO head and `result_next` is the second slot. There is still only one working sparse accumulator; no second arithmetic array is duplicated.

| Field | Meaning in this revision |
| --- | --- |
| received | Sparse: next input k, cycling through 0–7; dense: original 0–8 counter |
| outstanding | Started tiles whose results have not been consumed, including partial input, pipeline work, and completed results; maximum 2 |
| result_count | Completed results in the FIFO, 0–2 |
| result_valid | result_count > 0, indicating an available FIFO head |
| busy | Outstanding tiles remain; stays true even with an empty pipeline if a result is unconsumed |

The first accepted packet of each tile reserves a result slot. Full capacity blocks only the first packet of the next tile; an already-started tile can finish receiving and drain. In-flight work therefore has storage even when result_ready remains false for a long time.

`TC_RESULT_SLOTS=2` describes the two explicitly implemented slots. Changing this constant alone does not expand the FIFO.

## Timing Example

Assume no input bubbles and continuously ready output:

| Tile | Input acceptance | Final ACC | Result enters FIFO | Result consumed |
| --- | --- | --- | --- | --- |
| 0 | cycle 0–7 | 9 | 10 | 11 |
| 1 | cycle 8–15 | 17 | 18 | 19 |
| 2 | cycle 16–23 | 25 | 26 | 27 |

Cycle 10 both saves tile 0's complete result and begins tile 1's first accumulation. Publishing a result does not stop MUL/ROUTE.

## Compilation and Execution

### GCC

Run in the extracted source directory:

```bash
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror tensor_core_model.c tb_tensor_core.c -o tb_tensor_core
./tb_tensor_core
```

### Visual Studio

Use the two `.c` files and one `.h` file in one C project. Exclude older same-named sources from the build to avoid duplicate functions or main definitions. Put the header where both C files can include it; it is not compiled separately.

From a Visual Studio Developer Command Prompt with C11 support:

```bat
cl /std:c11 /W4 /TC tensor_core_model.c tb_tensor_core.c /Fe:tb_tensor_core.exe
tb_tensor_core.exe
```

The original delivery was compiled and verified with Linux/GCC, not Windows/MSVC.

### Displaying Cross-Tile Operation

```bash
./tb_tensor_core --tests 0 --stream-tiles 8 --bench-tiles 100 --stream-trace
```

Use `tb_tensor_core.exe` on Windows. `--stream-trace` prints three full-count sparse tiles, showing tile 1 accepted at cycle 8 and tile 2 at cycle 16.

Other options:

| Option | Purpose |
| --- | --- |
| --tests N | Original single-tile random tests per mode; default 1000, allows 0 |
| --stream-tiles N | Tiles per random stream test; default 1000, minimum 1 |
| --bench-tiles N | Tiles in the full-count performance test; default 100, minimum 1 |
| --seed N | Random seed; 0 selects a fixed fallback seed |
| --demo / --trace / --bubbles | Original single-tile demo, timing trace, and input-bubble options |
| --mode all/dense/hybrid/dual/dense-unstructured | Filters only the original single-tile tests; cross-tile and regression tests still run |

## API Usage

1. Prefer `tc_input_ready_for(&core, next_packet.is_sparse)` to decide whether the next packet can be issued. `tc_input_ready()` remains available, but reports only the current mode's capacity and does not check compatibility with the next packet.
2. If the next packet cannot be issued, hold it and still call `tc_tick(..., false, NULL, result_ready, ...)` that cycle so the pipeline/output can advance. Do not stop calling tc_tick merely because input_ready=false.
3. The strict API is retained: valid input while not ready returns TC_NOT_READY and prevents the entire call from advancing. This is not automatic hardware-style handling of valid held high while waiting; the driver must use readiness to decide whether to submit a packet.
4. If a result will be consumed on the current edge, read/save `core.result` **before** calling tc_tick. The FIFO head may have changed afterward. The testbench's run_stream() provides a complete example.
5. Sparse input acceptance and result output can occur on the same edge. Consumption of an old FIFO result and publication of a new result may also coincide.
6. Reclaimed result capacity is available on the next readiness query; there is no direct combinational path from current result_ready to input_ready. An ideal unstalled stream can still accept a packet every cycle.
7. Results preserve input tile order. Exactly eight packets form a tile; an empty sparse vector still counts as a valid packet and cannot simply be skipped without changing the protocol.

## Utilization Measurement

Conditions: fixed peak capacity of 64 MAC/cycle; each sparse packet has eight legal nonzero values in both A and B, with indices 0–7; 100 tiles; no additional input bubbles; continuously ready output; every result compared against independent matrix multiplication.

| Scheduling | Total cycles | Active MACs | Utilization |
| --- | --- | --- | --- |
| Wait for each tile's result consumption before issuing the next tile | 1200 | 51200 | 66.6667% |
| Consecutive sparse input with tile overlap | 804 | 51200 | 99.5025% |

Utilization = total MACs / (64 × total cycles). Measurement begins on the first input edge and ends on the final result-consumption edge, **including initial fill and final drain**. The overlapping stream takes 8N+4 cycles for N tiles; a single tile still takes 12 cycles. The improvement is sustained throughput, not first-result latency.

The same testbench runs serial and overlap scheduling with the same seed and data. Existing tests still use run_tile() for single-tile correctness; the new run_stream() actively issues the next tile.

99.50% is a full-count core C-model benchmark, not utilization for all sparse data or a synthesized RTL TOPS result. Fewer valid entries, mode changes, output backpressure, and insufficient external supply reduce total utilization. A sparse-format interface does not imply zeros in every test; this benchmark deliberately uses legal full-count vectors to measure the best case. DU/TIA and memory supply are excluded.

## Verification Coverage

- Directed/random tests for the four existing decoded-data categories and per-PE dense arrival timing.
- Independent i/j/k GEMM checks of every output matrix and result order.
- Sparse first/last propagation across tile boundaries, including all-zero tiles, empty first/last packets, stored zeros, and INT8 extremes.
- Random input bubbles, long output stalls, both result slots full, and credit reclamation.
- Same-edge old-result consumption/new-result publication and old-result consumption/new-tile start.
- Consecutive sparse data-format changes and dense/sparse changes after draining, without reset.
- The original 48 reset/restart points plus 30 reset points with overlapping work and unconsumed results.
- State preservation on rejected inputs, including incompatible modes, invalid count/index values, and unavailable result capacity.

The default tests passed 6389 tiles. AddressSanitizer and UndefinedBehaviorSanitizer checks passed; LeakSanitizer was disabled because of environment limitations. A separate NDEBUG build with a different seed confirmed that correctness did not depend on assert execution. Detailed commands and recorded output are in verification.txt.
