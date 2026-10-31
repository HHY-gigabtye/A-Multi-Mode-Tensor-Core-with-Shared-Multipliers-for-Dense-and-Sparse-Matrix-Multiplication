# Three Standalone C Projects: MLU, MSU, and Bridge

> Historical package note: this README describes the original standalone delivery layout. Names such as `MLU_MSU_BRIDGE.sln`, `make test`, and `build_msvc.bat` below are historical package instructions, not current repository entry points. See the [repository README](../README.md), [source audit](../docs/source-audit.md), and `tools/run_c_tests.bat` for the current layout and runner.

This package follows the workflow "C verification of each module → SV verification of each module → full SV integration." The three models are identical to the original package. A standalone Bridge testbench and three Visual Studio Console projects were added. Each project builds its own executable and does not link DU/TIA or Tensor Core `.c` files.

## Opening the Original Package

1. Extract the full package, preserving the locations of `reference` and `vs`.
2. Open `MLU_MSU_BRIDGE.sln` at the package root.
3. Select `Debug`, `x64`, and build the solution.
4. In Solution Explorer, right-click the project to run, choose "Set as Startup Project," and press `Ctrl+F5`.
5. Run `MLU_Test`, `MSU_Test`, and `Bridge_Test` in order. Building the solution does not execute all three tests.

The projects select C11, Compile as C, and disabled precompiled headers. Do not add a default `.cpp` containing another `main()`. The solution uses the VS 2022 v143 toolset and selects v142 in VS 2019; VS 2019 requires version 16.8 or later. Install Desktop development with C++ and a C11-capable Windows SDK (10.0.20348.0 or later). If a toolset or SDK is missing, select an installed C11-capable version in project properties or install the required tools. See [Microsoft's C11/C17 support installation instructions](https://learn.microsoft.com/en-us/cpp/overview/install-c17-support?view=msvc-170).

## Sources Required by Each Project

| Project | Source Files: only these two C files are compiled | Header Files |
|---|---|---|
| MLU_Test | `tb_mlu.c`, `mlu_model.c` | `mlu_model.h`, `io_types.h`, `tb_support.h`, `reference/tensor_core_model.h` |
| MSU_Test | `tb_msu.c`, `msu_model.c` | `msu_model.h`, `io_types.h`, `tb_support.h`, `mlu_model.h`, `reference/tensor_core_model.h` |
| Bridge_Test | `tb_bridge.c`, `du_tc_bridge.c` | `du_tc_bridge.h`, `io_types.h`, `reference/tensor_core_model.h` |

MSU_Test needs `mlu_model.h` because the original shared test helpers in `tb_support.h` include it; `mlu_model.c` is not linked. `io_types.h` references packet and matrix types from `reference/tensor_core_model.h`, so all three projects need that header. TC functions that are declared but never called do not require their C implementations.

Header Files is an IDE grouping, not a separate compilation step. The supplied projects reference the same files at the original package root; three copies are unnecessary.

## Files Retained from the Original Package

| Treatment | Files |
|---|---|
| Retained | `mlu_model.c/.h`, `msu_model.c/.h`, `du_tc_bridge.c/.h`, `io_types.h` |
| Retained | `tb_mlu.c`, `tb_msu.c`, `tb_support.h` |
| Directory and this header retained | `reference/tensor_core_model.h` |
| Added | `tb_bridge.c`, `MLU_MSU_BRIDGE.sln`, and three projects/filters under `vs/` |
| Unused by these standalone tests; may remain in the original package backup | `tb_pipeline.c`, `du_reference.inc`, `reference/du_tia_reference.c`, `reference/tensor_core_model.c` |
| Replaced by this package's versions | `Makefile`, `build_msvc.bat`, the package README, `verification.txt` |

The old Makefile and build_msvc.bat also compiled the C integration test. If integration-related files are removed, the standalone package's scripts must be used instead. Previously completed DU/TIA and TC projects and SV files remain available for later integration.

## Bridge_Test Coverage

This testbench links only `du_tc_bridge.c` and models surrounding inputs:

- After an upstream MLU issue, DU returns the corresponding payload four cycles later. The testbench maintains this schedule independently and does not derive returns from the Bridge side pipeline.
- TC may stop and resume acceptance. Metadata consumption is permitted only after all eight packets of that tile have been accepted at the TC boundary.
- Monotonically increasing tokens independently check payload, k, tile ID, 64-bit writeback address, ordering, and counters.

Coverage includes empty-read protection, illegal k/mode, incorrect DU return timing/mode, unchanged state on rejected calls, long downstream stalls, all eight FIFO slots full, up to four in-flight packets, same-edge enqueue/dequeue, pointer wrap, both result metadata slots full and blocking, simultaneous metadata push/pop, and reset in three occupied-state scenarios followed by different tile IDs.

Bridge packet capacity is `used = FIFO.count + inflight <= 8`. Capacity is reserved before DU issue; DU output entering the FIFO only transfers occupancy; actual TC acceptance releases it. This version uses old state to decide whether issue is allowed. When full, even if TC consumes a packet on that edge, the credit becomes available only on the following cycle. There is no FIFO payload bypass: newly arrived DU output cannot enter TC until the next cycle.

This is a Bridge unit test. It does not verify DU decoding, TC computation, or the complete mode-switch protocol. Actual DU/TC modules are not linked, so it cannot replace full SV integration.

## MLU and MSU Behavior Summary

- Each task is an independent 8×8×8 INT8 matrix multiplication with INT32 results; MSU performs no cross-K-block accumulation.
- MLU has two tile buffers. It loads a complete tile before outputting DU packets in k=0..7 order.
- MLU permits only one outstanding read burst, with 32 bytes/beat; reads and packet outputs may both stall.
- Dense images contain 128 bytes; hybrid images contain 120 meaningful bytes with 128 bytes read; dual images contain 144 meaningful bytes with 160 bytes read.
- MLU does not compress data; memory input is already packed. C struct layout is not equivalent to SV packed-union layout.
- MSU has two complete-result buffers. Each result occupies 256 bytes and is written in row-major order as eight 32-byte beats.
- In this simplified interface, MSU `write_ready` means the write commits on that edge. AXI write responses and a real HBM controller are not modeled.
- System reset must coordinate all connected modules and pending memory transactions. Data already committed to memory are not automatically restored.

Complete layout and interface comments remain in the original package README and model headers. This package focuses on standalone operation of the three modules.

## Other Build Methods in the Original Package

GCC: run `make test` in the package directory.

Visual Studio Developer Command Prompt: run `build_msvc.bat` in that directory to build and execute all three tests in sequence. The batch file and solution are alternative entry points; either may be used.

Manual source combinations:

```text
MLU_Test    = tb_mlu.c    + mlu_model.c
MSU_Test    = tb_msu.c    + msu_model.c
Bridge_Test = tb_bridge.c + du_tc_bridge.c
```

Each executable contains exactly one `main()`. Do not compile all three testbenches into one project.

## Original Verification Status

Recorded execution results are in `verification.txt` in the original package. That environment used GCC. Visual Studio project XML, source references, and single-main configuration were checked, but Windows/MSVC execution had not been performed. That delivery did not generate MLU/MSU/Bridge SV or run ModelSim or ASIC synthesis.
