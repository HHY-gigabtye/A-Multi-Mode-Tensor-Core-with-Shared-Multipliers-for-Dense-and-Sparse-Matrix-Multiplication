# A Multi-Mode Tensor Core with Shared Multipliers for Dense and Sparse Matrix Multiplication

## 1. Project Overview

This hardware design project implements an **8 x 8 x 8 matrix multiplication tile engine** with signed **INT8 operands and INT32 accumulation**. It combines dense systolic execution and sparse outer-product execution around a shared 8 x 8 multiplier bank, with loading, decoding, flow control, and ordered result writeback implemented in SystemVerilog.

The project demonstrates cycle-level architecture modeling, RTL implementation, pipeline control, resource sharing, and hardware verification. Its engineering focus is preserving numerical correctness, packet order, and precise transfer timing across independently tested modules under backpressure and reset.

**Verified scope:** the five RTL units and their connected system pass the supplied simulation regressions. The memory boundary is a simplified 256-bit interface; a physical HBM controller, complete AXI protocol, board execution, and ASIC implementation are outside the verified scope. Each command computes an independent `C = A x B` tile with zero initial accumulation; there is no accumulation across K tiles or addition of a previous C matrix.

## 2. Key Features

- Three input modes: dense x dense, unstructured x 2:4, and unstructured x unstructured.
- Dense output-stationary systolic dataflow with lane-dependent input skew.
- Sparse multiply -> route -> accumulate pipeline with consecutive tile overlap.
- One shared bank of 64 signed INT8 multiplication operations in the RTL; separate dense and sparse state and accumulation paths.
- Four-stage DU/TIA decoding and index alignment, followed by an eight-entry packet FIFO with in-flight credit reservation.
- Two Tensor Core result slots, a separate two-entry result-metadata FIFO, and two whole-result buffers in the MSU.
- C reference models, immutable replay vectors, procedural SV scoreboards, and an independent system-level GEMM/writeback check.

## 3. Overall System Architecture

The diagram below summarizes the inspected RTL connections. "HBM" describes the intended system context; simulation supplies a behavioral memory endpoint.

```mermaid
flowchart LR
    MEM["Simplified memory / intended HBM boundary"] --> MLU["MLU: two tile buffers"]
    MLU --> DU["DU/TIA: S0-S3"]
    DU --> FIFO["Bridge: 8 packet slots + in-flight credits"]
    FIFO --> TC["Tensor Core: dense / sparse dataflow; shared multipliers"]
    TC --> MSU["MSU: two result buffers"]
    MSU --> OUT["Memory: eight row writes per tile"]
    MLU -. "tile ID, destination, k" .-> TAG["Bridge: four tag stages"]
    TAG -.-> FIFO
    FIFO -. "metadata on accepted k=0" .-> META["Two-entry result-metadata FIFO"]
    META -. "pop on TC-to-MSU transfer" .-> MSU
```

The top-level module is [`sparse_tensor_core_top`](integration_sv/rtl/sparse_tensor_core_top.sv). It maps fields explicitly between packages and uses mode-aware readiness to turn the FIFO head into an actual Tensor Core acceptance pulse.

## 4. Supported Computation Modes

| Mode | Input representation | Compute dataflow |
|---|---|---|
| `IO_DENSE = 0` | Eight A values and eight B values per k slice | Dense systolic array |
| `IO_HYBRID = 1` | Bitmap/packed A; B uses two retained positions per four K positions, for each output column | Decoded sparse outer product |
| `IO_DUAL = 2` | Bitmap/packed A and B | Decoded sparse outer product |

Mode 3 is illegal. Every tile supplies eight ordered packets, `k=0..7`. Both sparse modes become the same count/value/index representation after DU/TIA. Counts range from 0 to 8, indices are strictly increasing original coordinates, and stored zero values remain legal.

The MLU reads fixed-size images rather than variable-length compressed streams:

| Mode | Meaningful image bytes | Read transfer |
|---|---:|---:|
| Dense | 128 | 4 x 32 bytes |
| Hybrid | 120 | 4 x 32 bytes |
| Dual sparse | 144 | 5 x 32 bytes |

Sparse packing occurs upstream. The MLU loads and packetizes an already encoded image; it does not discover or compress nonzeros.

## 5. Hardware Microarchitecture

**Dense path.** Regular dense matrices benefit from local operand reuse and predictable nearest-neighbor movement. Lane i is skewed by i cycles, operands propagate across the 8 x 8 PE array, and each PE holds its INT32 accumulator. This implementation drains and consumes a dense result before starting another dense tile.

**Sparse path.** Packed operand ranks do not directly identify output coordinates. Up to `A.count x B.count` products are formed, then routed using the stored row/column indices into the 8 x 8 accumulator matrix. The ROUTE stage uses two combinational selector banks inside the existing pipeline stage. No extra pipeline register is implied by this factorization.

**Shared arithmetic.** The common multiplication loop selects either aligned dense PE operands or sparse packed operands. Products are signed 16-bit values and are sign-extended for INT32 accumulation. Sharing is visible in the RTL structure; it is not a measured area-saving claim against a separately synthesized dual-engine baseline. The archived FPGA reports use LUT logic and report zero DSP blocks.

**Memory units.** MLU has two tile buffers and permits one outstanding read burst. MSU has two complete 256-byte result buffers. It writes eight 32-byte rows in little-endian order and asserts `tile_done` only after the final row transfer. There is no AXI write-response channel in this interface.

## 6. Pipeline and Dataflow

**DU/TIA:** S0 captures the selected input, S1 forwards packed values/decodes 2:4 B and predecodes bitmap halves, S2 merges indices, and S3 registers the output. DU/TIA has no downstream ready input, so capacity must be reserved before issue. Its aligned metadata stages reside in the Bridge.

**Packet credits:** `used = fifo_count + inflight_count <= 8`. Issuing into DU/TIA reserves one slot; arrival moves the reservation into the packet FIFO; TC acceptance frees it. Readiness uses the old registered occupancy. A full FIFO cannot borrow a credit from a same-edge dequeue, and newly arriving DU data cannot bypass the FIFO. For an issue at edge t, the earliest TC acceptance is t+5.

**Result metadata:** accepting a k=0 packet into TC enqueues its tile ID and destination address. A full metadata FIFO blocks another k=0. Metadata is removed when TC transfers its result into MSU, independently of later memory write completion.

**Sparse overlap:** first/last markers travel through MUL and ROUTE to ACC. The accumulator clears when the next tile's first packet reaches ACC. Before that clear, the previous completed accumulator is published into a reserved result slot. Thus the next tile can begin MUL while the previous tile is still finishing ROUTE/ACC. New tile starts wait when both result credits are occupied; an already accepted tile can finish safely.

With first TC acceptance numbered edge 0 and eight consecutive packets, the reference/test contract publishes sparse results after edge 10 and dense results after edge 22. Sparse tile starts can be eight cycles apart when inputs and result capacity are available. These are **TC-boundary timings**, not command-to-memory completion latencies. Dense/sparse mode changes wait for the prior mode's outstanding work and results to drain.

## 7. Verification Methodology

Verification proceeds from isolated units to the connected system. Reference models and existing test assertions are preserved.

| Boundary | Checking method |
|---|---|
| MLU | C vectors; pre-edge outputs, events, and all 2,900 state bits |
| DU/TIA | Independent SV packet oracle; directed, all six 2:4 masks at four positions, bitmap enumeration, and deterministic random traffic |
| Bridge | C vectors; all 2,941 state bits, credits, metadata, and rejected-edge behavior |
| Tensor Core | C vectors; readiness/status/events, both complete result slots, and a logical internal-state hash |
| MSU | C vectors; result acceptance, control state, byte order, stalled writes, and final-beat completion |
| Connected RTL | Independent SV matrix generation, memory-image encoding, GEMM, and byte-level writeback scoreboard |

The TC hash is an additional diagnostic, not a formal proof or a full bit-for-bit internal-state comparison. Full result matrices are compared directly. The DU/TIA C model is a separate test program; the DU/TIA SV regression does not call C through DPI. MSU reset/fault handshake suppression is explicitly accounted for by its vector adapter.

Coverage includes signed INT8 extremes, empty/full sparse prefixes, stored zeros, all three modes and all nine mode transitions, FIFO and result saturation, simultaneous push/pop, pointer wrap, memory gaps, held payload stability, and reset/recovery at each targeted occupancy. The tests use procedural checks; they are not a UVM environment, formal equivalence proof, or a claim of exhaustive verification.

## 8. Performance and Implementation Results

The audit reran the existing SV suites on **2026-10-29**, using **ModelSim Intel FPGA Starter Edition 2020.1 / Simulator 2020.02**. Both commands exited successfully; six existing port-kind compilation warnings remain in each suite. See [verification evidence](reports/verification/2026-10-29/README.md). The separate public candidate reproduced these results after vector restoration on [2026-10-30](reports/verification/2026-10-30-packaging/README.md).

| Simulation | Observed result |
|---|---|
| MLU unit | PASS: 16,708 records; 145 resets; 128 expected rejected edges |
| DU/TIA unit | PASS: 3,292 checked packets |
| Bridge unit | PASS: 19,147 records; 7,156 expected rejected edges; 13 resets |
| TC unit | PASS: 136,136 records; 169 resets; 13 expected rejection cases |
| MSU unit | PASS: 8,683 cycles; 676 accepted results; 5,394 beats; 673 completed tiles; 8 resets |
| Connected system | PASS: 316 completed tiles; 3,124 issued packets; 2,563 write beats; 75 resets; seed `91e10da5` |

System totals include partial work deliberately discarded by reset, so packet/beat counts are not simply eight times the completed tile count. The 145 `sparse_II8` observations count TC tile-start intervals, not 145 end-to-end throughput benchmarks.

The standalone C TC benchmark uses **100 tiles of full 8 x 8 outer-product packets**, no input gaps or output stalls, and includes initial fill and final result handshaking. It reports 51,200 MACs: serial scheduling takes 1,200 cycles (66.6667% utilization); overlap takes 804 cycles (99.5025%), a 1.4925x cycle-throughput ratio. Utilization is `MACs / (64 x elapsed cycles)`. This is a controlled full-count sparse-path scheduling experiment, not measured utilization for a pruned network, an HBM workload, or the entire integrated system. Stored zeros count as active work when included in the valid prefix. See [benchmark provenance](docs/verification-and-reproduction.md).

Existing Vivado reports were inspected, **not regenerated**:

| Archived implementation | Phase and constraints | Reported result |
|---|---|---|
| TC alone, 2026-10-19 | FPGA post-route; 12 ns target | WNS -0.238 ns; TNS -2.894 ns; target not met |
| Integrated top, 2026-10-29 | FPGA post-route; 17 ns target | WNS +0.202 ns; TNS 0; specified constraints met |
| Integrated top utilization | Post-place, same archived project | 36,222 LUTs; 22,467 registers; 0 DSPs; 0 block RAM tiles |

Both projects target `xc7z020clg484-1` with Vivado 2022.2 and out-of-context synthesis. The integrated clock target is 58.824 MHz. Its report also records **424 inputs and 592 outputs without delay constraints**, zero BUFGCTRL usage, and a PS7-related DRC warning. Therefore it is not complete board-level timing sign-off or a measured Fmax. Report-to-source commit provenance is not established. See [implementation evidence and limitations](reports/implementation/README.md).

**Not Yet Verified:** maximum operating frequency of the current source, FPGA board/HBM operation, ASIC library/corner PPA, measured power, application-level speedup, and a controlled area comparison quantifying multiplier-sharing savings. The earlier architecture note's approximately 80-83 MHz unplaced ASIC estimate has no supporting ASIC report in the inspected files.

## 9. Repository Structure

Module-local paths are retained so includes, package order, and existing test scripts remain usable.

```text
.
|-- README.md / .gitignore / AGENTS.md
|-- c code/                    # Original C projects, unit tests, VS settings
|-- du_tia_sv/                 # rtl/, tb/, filelist.f, simulation scripts
|-- fifo_sv/                   # Bridge RTL/packages/TB, c_reference/, vectors/
|-- mlu_sv/                    # MLU RTL/packages/TB, c_ref/, vectors, scripts
|-- tensor_core_sv/            # TC RTL/packages/TB, c_reference/, vectors.gz
|-- msu_sv/                    # rtl/, tb/, reference/, vectors/, tools/, sim/
|-- integration_sv/            # Connected top, SV system TB, regression scripts
|-- docs/                      # Architecture notes and source/reproduction audit
|-- reports/
|   |-- verification/          # Reviewed run logs, source hashes and results
|   `-- implementation/        # Selected archived FPGA reports and provenance
|-- tools/                     # Vector restoration and C regression launcher
|-- project_1/                 # Original TC Vivado .xpr / source constraints
`-- project_integration/       # Original top Vivado .xpr / source constraints
```

Legacy documents are retained for context, but may describe earlier package layouts or pre-integration status. Use this README and [source audit](docs/source-audit.md) for current entry points. Generated EDA run trees and private literature/meeting materials are excluded from the proposed public snapshot. Project files retain historical machine-specific settings; they are not a self-contained PPA reproduction flow.

## 10. How to Run the Tests

### ModelSim: units followed by integration

Prerequisites: PowerShell 7 (7.6.5 tested) with permission to run local scripts and the tested ModelSim version (or a compatible simulator, independently verified). Run from the repository root. No C compiler is needed for SV vector replay.

```powershell
# Restore the exact TC vectors from the small gzip distribution.
pwsh -NoProfile -File tools/restore_vectors.ps1

# Runs all five isolated units, checks PASS markers/errors, then runs the top.
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1
```

The first command verifies SHA-256 and refuses to overwrite differing existing vectors. Other unit vectors remain plain text. Windows PowerShell 5.1 may block local scripts under its execution policy; the audit used the already available PowerShell 7 without changing policy. Logs go to `integration_sv/results/`; simulator libraries go to `integration_sv/build/`. To inspect the top alone after establishing a unit baseline:

```powershell
vsim -c -l integration_sv/results/top.log -do integration_sv/sim/run_top.do
```

`run_units.do` compiles each unit separately. `run_top.do` lists the integration packages before modules and selects exactly one DU/TIA package and one TC package. Do not compile all duplicate package files together. The legacy `msu_sv/sim/run_msu.do` has a local absolute path; use the root regression entry point above for portable MSU replay.

### C references

From a Visual Studio Developer Command Prompt with C11 support:

```bat
tools\run_c_tests.bat
```

The launcher builds into `build/c_reference/` and executes the existing TC, MLU, MSU, Bridge, DU/TIA, and basic outer-product C tests. It leaves the original sources, seeds, and replay vectors unchanged. UTF-8 source decoding is required for the DU/TIA source comments. See [commands, results, and limitations](docs/verification-and-reproduction.md).

Optional vector-regeneration scripts already exist in the individual modules. They overwrite vectors/logs, so run them in a separate copy and compare against the published baseline. Verilator and Icarus flows are also included in the original packages; historical results do not imply those tools were rerun in the current Windows audit.

## 11. References

This project is informed by published work on systolic arrays and sparse tensor execution. The implementation and verification artifacts here are the portfolio contribution; the cited architectures, algorithms, and published results remain the work of their respective authors. No paper's benchmark is presented as a result of this project.

1. Chen Zhang et al., **DSTC: Dual-Side Sparse Tensor Core for DNNs Acceleration on Modern GPU Architectures**, IEEE Transactions on Computers, 74(2), 341-355, 2025. [DOI](https://doi.org/10.1109/TC.2024.3475814).
2. Zhi-Gang Liu, Paul N. Whatmough, and Matthew Mattina, **Systolic Tensor Array: An Efficient Structured-Sparse GEMM Accelerator for Mobile CNN Inference**, 2020. [Author preprint](https://arxiv.org/abs/2005.08098).
3. Jun Liu et al., **TSTC: Two-Level Sparsity Tensor Core Enabling both Algorithm Flexibility and Hardware Efficiency**, ICCAD 2023. [DOI](https://doi.org/10.1109/ICCAD57390.2023.10323775).

Only references are intended for the public snapshot; locally stored publisher PDFs and meeting slides are withheld pending redistribution approval. A project-wide redistribution license has not yet been selected by the author.
