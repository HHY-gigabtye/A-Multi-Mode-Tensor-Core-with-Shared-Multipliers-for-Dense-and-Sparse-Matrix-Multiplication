# Tensor Core: C Model with Sparse Tile Overlap

> Legacy C reference scope: this directory preserves the predecessor's dense systolic path, sparse outer-product path and mode-switch drain rules. Current production RTL uses one shared outer-product core for all formats. Its dense timing differs from this model; use the [current TC contract](../../../tensor_core_sv/README.md) and [verification record](../../../reports/verification/outer_main_20261121/README.md). The C model, tests and expected results remain unchanged.

This package was based on the supplied `tensor_core_model(2).c`, `tensor_core_model(2).h`, and `tb_tensor_core(2).c`. Delivered files use the standard names required by the existing includes.

## Files and scope

| File | Purpose |
| --- | --- |
| tensor_core_model.h | Data structures, API, and handshake rules |
| tensor_core_model.c | Cycle-level C model, without main |
| tb_tensor_core.c | Existing single-tile tests, added continuous-tile scoreboard, performance measurement, and the only main |
| verification.txt | Actual build/run output and verification limitations |

- INT8 × INT8 → INT32 and M=N=K=8 are preserved. Every eight accepted packets form one tile.
- The sparse outer-product path supports overlapping tiles. Sparse formats after DU/TIA use the same path with `is_sparse=true`.
- The dense systolic path still handles one tile at a time; existing per-PE arrival-timing checks are retained.
- A mode switch must wait until all started tiles finish and all results are consumed, with `busy=false`.
- The original package change covered only the C model and testbench. It did not add DU/TIA, MLU, or MSU, or generate or verify new RTL.
- The testbench's `dense-unstructured` category constructs decoded packets directly. It does not introduce a DU/TIA compiler mode.

## Operation

### 1. Carry first/last markers through MUL and ROUTE to ACC

No new first/last input fields are required. The core generates boundary markers automatically for every eight accepted packets.

The complete accumulator matrix is cleared only when the first packet reaches ACC, before adding that packet's valid products. This also clears correctly when the first packet has count=0. Accepting the next tile's first packet does not clear the previous tile while it is still being computed.

### 2. Save the previous result and start the next accumulation on the same edge

`finish_pending` retains a one-cycle result-publication step. `tc_tick()` copies the old ACC value into the result FIFO before calling `sparse_tick()` to update ACC. The output therefore includes the previous tile's last products, and the next tile's first-packet clear cannot destroy that result.

RTL must preserve the semantics of reading old state before committing new state; these operations cannot be reordered arbitrarily.

### 3. Reserve one of two result slots before starting a tile

`result` is the FIFO head and `result_next` is the second slot. There is still only one sparse working accumulator, without a second arithmetic array.

| Field | Meaning in this version |
| --- | --- |
| received | Sparse: next input k, cycling through 0–7. Dense: original 0–8 count |
| outstanding | Started tiles whose results have not been consumed, including partial input, pipeline work, and completed results; maximum 2 |
| result_count | Completed results in the FIFO, 0–2 |
| result_valid | result_count > 0; the FIFO head can be consumed |
| busy | An outstanding tile exists; remains true even when the pipeline is empty if a result is still pending |

A result slot is reserved when the first packet of a tile is accepted. When all slots are reserved, only the next tile's first packet is blocked; a started tile can still receive its remaining packets and drain. In-flight work therefore has reserved storage even if result_ready stays false for a long time.

`TC_RESULT_SLOTS=2` describes the two explicitly implemented slots. Changing that constant alone does not expand the FIFO.

## Timing example

With no input bubbles and output always ready:

| Tile | Input acceptance | Last ACC | Result enters FIFO | Result consumed |
| --- | --- | --- | --- | --- |
| 0 | cycle 0–7 | 9 | 10 | 11 |
| 1 | cycle 8–15 | 17 | 18 | 19 |
| 2 | cycle 16–23 | 25 | 26 | 27 |

Cycle 10 saves tile 0's complete result while starting tile 1's first accumulation. Publishing a result does not pause MUL or ROUTE.

## Build and run

### GCC

Run in the extracted directory:

```bash
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror tensor_core_model.c tb_tensor_core.c -o tb_tensor_core
./tb_tensor_core
```

### Visual Studio

Use the supplied two `.c` files and one `.h` in the same C project. Remove older source versions from the build to avoid duplicate functions or main definitions. Place the `.h` where both `.c` files can include it; it is not compiled separately.

In a Visual Studio Developer Command Prompt with C11 support:

```bat
cl /std:c11 /W4 /TC tensor_core_model.c tb_tensor_core.c /Fe:tb_tensor_core.exe
tb_tensor_core.exe
```

The original delivery was compiled and validated with Linux/GCC; Windows/MSVC was not executed.

### Display tile overlap

```bash
./tb_tensor_core --tests 0 --stream-tiles 8 --bench-tiles 100 --stream-trace
```

On Windows, use `tb_tensor_core.exe`. `--stream-trace` prints three full sparse tiles, showing tile 1 accepted from cycle 8 and tile 2 from cycle 16.

Other options:

| Option | Function |
| --- | --- |
| --tests N | Original single-tile random tests per mode; default 1000, permits 0 |
| --stream-tiles N | Tiles per random stream test; default 1000, minimum 1 |
| --bench-tiles N | Tiles in the full-load performance test; default 100, minimum 1 |
| --seed N | Random seed; 0 selects a fixed fallback seed |
| --demo / --trace / --bubbles | Retained single-tile demonstration, timing trace, and input-bubble options |
| --mode all/dense/hybrid/dual/dense-unstructured | Filters only the original single-tile tests; overlap and regression tests still run |

## API usage

1. Use `tc_input_ready_for(&core, next_packet.is_sparse)` to check admission for the next packet. `tc_input_ready()` remains available but describes readiness for the current mode; it does not check the next packet's mode compatibility.
2. If the next packet cannot enter, retain it and still call `tc_tick(..., false, NULL, result_ready, ...)` on that cycle so the pipeline and output advance. Do not stop calling tc_tick when input_ready=false.
3. The original strict API is preserved: valid input while not ready returns TC_NOT_READY and freezes the entire call. The model does not automatically hold valid until ready; the driver must use readiness to decide whether to submit the packet.
4. If a result will be consumed on this edge, read/save `core.result` **before** calling tc_tick. After the call, the FIFO head may be the next result. The testbench's run_stream() provides a complete example.
5. Sparse input and result output can transfer on the same edge. Consuming an old FIFO result and publishing a new result on the same edge are also supported.
6. Released result capacity becomes available on the next readiness query. There is no same-cycle combinational lookahead from result_ready to input_ready. An ideal unstalled stream can still accept one packet per cycle.
7. Results preserve input tile order. Each tile always contains eight packets; an empty sparse vector is still a valid packet and cannot simply be skipped without changing the protocol.

## Utilization measurement

Conditions: peak capacity fixed at 64 MAC/cycle; each sparse packet contains eight legal, nonzero values in both A and B, with indices 0–7; 100 tiles; no extra input bubbles; output always ready; every result checked against an independent matrix-multiplication golden model.

| Schedule | Total cycles | Useful MACs | Utilization |
| --- | --- | --- | --- |
| Start the next tile only after consuming the previous result | 1200 | 51200 | 66.6667% |
| Continuous sparse input with tile overlap | 804 | 51200 | 99.5025% |

Utilization = total MACs / (64 × total cycles). Measurement includes the cycle of the first input through the cycle of the last result consumption, **including batch startup and drain**. A continuous stream of N tiles takes 8N+4 cycles; one tile still takes 12 cycles. Sustained throughput improves, while first-result latency is unchanged.

The same testbench uses the same seed and data for serial and overlapping schedules. Existing tests use run_tile() for single-tile functionality; the added run_stream() actively supplies the next tile.

99.50% is the full-load result for the core C model. It is neither utilization for every sparse workload nor a TOPS result from synthesized RTL. Fewer valid elements, mode switches, output stalls, or limited external supply reduce overall utilization. A format named sparse does not require the test data to contain zeros; this test deliberately uses the interface's legal full vectors to measure the best case. DU/TIA and memory supply are outside this test.

## Verification coverage

- Existing directed/random tests for four decoded-data categories and per-PE dense arrival timing.
- An independent i/j/k GEMM golden model checks every output matrix and result ordering.
- Sparse first/last markers across tile boundaries, including all-zero tiles, empty first/last packets, stored zeros, and INT8 extremes.
- Random input bubbles, long output stalls, both result slots full, and credit reclamation.
- Consuming an old result while publishing a new one; consuming an old result while accepting a new tile's first packet.
- Continuous changes among sparse formats and dense/sparse switches after draining, without reset.
- The original 48 reset/restart points plus 30 reset points containing overlapping work and unconsumed results.
- Invalid inputs leave state unchanged, including invalid modes, count/index errors, and lack of result capacity.

The original default run passed 6389 tiles. AddressSanitizer and UndefinedBehaviorSanitizer passed; LeakSanitizer was disabled because of environment limitations. An additional NDEBUG build with a different seed confirmed that functionality does not depend on executing assertions. See verification.txt for exact commands and output.
