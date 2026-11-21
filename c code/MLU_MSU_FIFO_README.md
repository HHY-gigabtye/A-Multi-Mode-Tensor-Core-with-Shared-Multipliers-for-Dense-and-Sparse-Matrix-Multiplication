# Three Standalone C Projects: MLU, MSU, and Bridge

This package supports the workflow: each module in C → each module in SV → full SV integration.
The three models are unchanged from the original package. A standalone Bridge testbench and three Visual Studio Console projects were added.
Each project produces its own executable without linking the DU/TIA or Tensor Core `.c` implementations.

## Opening the solution

1. Extract the complete package, preserving the locations of the `reference` and `vs` directories.
2. Open `MLU_MSU_BRIDGE.sln` in the package root.
3. Select `Debug` and `x64`, then build the solution.
4. In Solution Explorer, right-click the project to run, select **Set as Startup Project**, and press `Ctrl+F5`.
5. Run `MLU_Test`, `MSU_Test`, and `Bridge_Test` in turn. Building the solution does not run all three tests.

The projects use C11, Compile as C, and disabled precompiled headers. Do not add a default `.cpp` containing another `main()`.
The solution uses the VS 2022 v143 toolset; VS 2019 selects v142 and requires version 16.8 or later.
Install Desktop development with C++ and a Windows SDK supporting C11 (10.0.20348.0 or later).
If the toolset or SDK is missing, select an installed C11-capable version in project properties or install the required component.
See the [Microsoft C11/C17 installation instructions](https://learn.microsoft.com/en-us/cpp/overview/install-c17-support?view=msvc-170).

## Files in each project

| Project | Source Files: only these two `.c` files are compiled | Header Files |
|---|---|---|
| MLU_Test | `tb_mlu.c`, `mlu_model.c` | `mlu_model.h`, `io_types.h`, `tb_support.h`, `reference/tensor_core_model.h` |
| MSU_Test | `tb_msu.c`, `msu_model.c` | `msu_model.h`, `io_types.h`, `tb_support.h`, `mlu_model.h`, `reference/tensor_core_model.h` |
| Bridge_Test | `tb_bridge.c`, `du_tc_bridge.c` | `du_tc_bridge.h`, `io_types.h`, `reference/tensor_core_model.h` |

MSU_Test needs `mlu_model.h` because the shared test utilities in `tb_support.h` include it; it does not need to link `mlu_model.c`.
`io_types.h` uses packet and matrix types from `reference/tensor_core_model.h`, so all three projects need that header.
TC functions that are declared but never called do not require their `.c` implementation.
Header Files is an IDE grouping, not a separate compilation step. All supplied projects reference the same files in the package root; three copies are unnecessary.

## Files retained from the original package

| Treatment | Files |
|---|---|
| Keep | `mlu_model.c/.h`, `msu_model.c/.h`, `du_tc_bridge.c/.h`, `io_types.h` |
| Keep | `tb_mlu.c`, `tb_msu.c`, `tb_support.h` |
| Keep the directory and this header | `reference/tensor_core_model.h` |
| Added | `tb_bridge.c`, `MLU_MSU_BRIDGE.sln`, and three projects with filters under `vs/` |
| Unused by these standalone tests; may remain in the original package backup | `tb_pipeline.c`, `du_reference.inc`, `reference/du_tia_reference.c`, `reference/tensor_core_model.c` |
| Use the versions from this package | `Makefile`, `build_msvc.bat`, `README_zh_TW.md`, `verification.txt` |

The old Makefile and build_msvc.bat also compile the C integration test. If integration files are removed, use the standalone scripts supplied here.
Retain the separately completed DU/TIA and TC projects and SV files for later integration.

## Bridge_Test coverage

This testbench links only `du_tc_bridge.c` and models the surrounding inputs:

- After an MLU issue is accepted, DU returns the corresponding payload four cycles later. The testbench schedules this independently; it does not read the Bridge sideband pipeline to generate returns.
- TC reception can stall and resume. Result metadata may be consumed only after all eight packets of that tile have been accepted at the TC side.
- Monotonically increasing token IDs independently check payload, k, tile ID, 64-bit writeback address, ordering, and counts.

Coverage includes empty-read protection, invalid k/mode, incorrect DU return timing or mode, unchanged state after rejected calls,
long receive stalls, all eight FIFO entries full, up to four in-flight packets, simultaneous enqueue/dequeue, pointer wrap-around,
both result-metadata entries full with admission blocked, simultaneous metadata push/pop, and reset/restart with new tile IDs in three occupied states.

Bridge packet capacity is `used = FIFO.count + inflight <= 8`.
Issuing to DU reserves capacity; DU arrival transfers that occupancy into the FIFO; actual TC acceptance releases it.
Admission uses old state only. If full at the start of a cycle, a credit released by TC in that cycle becomes usable in the next cycle.
There is no FIFO payload bypass: newly arrived DU output can reach TC only in the following cycle.

This Bridge unit test does not verify DU decoding, TC arithmetic, or the complete mode-switch protocol.
It does not link the real DU/TC and cannot replace full SV integration testing.

## MLU and MSU behavior

- Each command is an independent 8×8×8 INT8 matrix multiplication with INT32 results. MSU performs no accumulation across K tiles.
- MLU has two tile buffers. It loads a complete tile before emitting DU packets in k=0..7 order.
- MLU permits one outstanding read burst, with 32 bytes/beat. Both memory reads and packet output can stall.
- Dense images occupy 128 bytes; hybrid images occupy 120 bytes (128 bytes read); dual images occupy 144 bytes (160 bytes read).
- MLU does not compress data; memory images are already packed. C struct layout is not the bit layout of an SV packed union.
- MSU has two complete-result buffers. Each 256-byte result is written in row-major order as eight 32-byte beats.
- In this simplified interface, MSU `write_ready` means the write commits on that edge. AXI write responses and a real HBM controller are not modeled.
- System reset must coordinate connected modules and pending memory traffic. Data already committed to memory is not automatically rolled back.

Full data layouts and interface comments remain in the original package README and model headers. This package focuses on standalone operation of the three modules.

## Other build methods

GCC: run `make test` in this directory.

Visual Studio Developer Command Prompt: run `build_msvc.bat` here to build and run all three tests in sequence.
The `.bat` and `.sln` are alternative workflows; either can be used.

For a manual build, use these source pairs:

```text
MLU_Test    = tb_mlu.c    + mlu_model.c
MSU_Test    = tb_msu.c    + msu_model.c
Bridge_Test = tb_bridge.c + du_tc_bridge.c
```

Each executable must contain exactly one `main()`. Do not compile all three testbenches into one project.

## Verification status

Actual results from the original package validation are recorded in `verification.txt`.
That validation used GCC. The Visual Studio project XML, source references, and unique main functions were checked, but the projects were not executed on Windows/MSVC.
The original package delivery did not generate MLU/MSU/Bridge SV or run ModelSim or ASIC synthesis.
