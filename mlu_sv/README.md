# MLU SystemVerilog: Standalone Unit Verification

> Scope note: tool availability and verification statements below describe the original standalone delivery. See the [repository README](../README.md) and [source audit](../docs/source-audit.md) for later ModelSim and full-system verification.

Generated from the supplied `mlu_model(2).c`, `mlu_model(3).h`, and `io_types(4).h`. The RTL preserves the original two tile buffers, single outstanding read burst, and ordered output of eight k packets per tile. `out_packet` directly uses the existing `du_tia_pkg::du_tia_input_t`.

## Verification Scope

`tb_mlu.sv` instantiates only `mlu dut`. C-model-generated vectors provide commands, memory response beats, read-request readiness, and downstream `out_ready`. Each cycle directly compares output packets, metadata, k, handshake events, status, and the complete buffer state. Vectors also control stalls; no DU/TIA, Bridge/FIFO, TC, or MSU instance is needed.

`du_tia_pkg.sv` must still be compiled because it defines the MLU output packet type. Referencing the package does not instantiate DU/TIA hardware. This standalone revision removed the DU/TIA instance, decoding reference, four-stage scoreboard, decoding counters, and related waveforms. Its simulation project no longer includes `du_tia.sv`. MLU RTL, the C model, and existing golden vectors were preserved.

Verify each unit independently before connecting MLU → DU/TIA → Bridge/FIFO → TC → MSU in a separate top-level testbench. This package does not run partial or full integration tests; the wiring examples below are for integration.

## Running ModelSim First

Extract the entire directory, then enter this command in the ModelSim Transcript:

```tcl
do C:/your_path/mlu_sv/run_mlu.do
```

Use braces when the path contains spaces:

```tcl
do {C:/your path/mlu_sv/run_mlu.do}
```

The script changes to the project directory, compiles the sources, adds waveforms, and runs the test. `mlu_vectors.txt` is supplied; SV replay does not require compiling C first. A passing run should show:

```text
ALL PASS MLU unit C/SV: 16708 records, 145 resets, 128 rejected edges
  commands=1397 packets=10236 retired=1279
  command+retire=1 read+output=4087 full_stalls=13908 both_ready=4396
```

The original standalone verification ran Verilator, not a local ModelSim/Questa installation. The testbench uses ordinary procedural checks, without SVA, DPI, UVM, or classes.

## Files and Compilation Order

| File | Purpose |
|---|---|
| `du_tia_pkg.sv` | Original package defining packet types; no DU/TIA module instance |
| `mlu_pkg.sv` | MLU commands, metadata, buffers, events, and packet-conversion functions |
| `mlu.sv` | MLU RTL; top module is `mlu` |
| `tb_mlu.sv` | Instantiates only MLU and compares it cycle by cycle against C vectors |
| `mlu_vectors.txt` | Complete pregenerated test vectors |
| `run_mlu.do`, `wave_mlu.do` | ModelSim execution and waveform scripts |
| `sim.f`, `synth.f` | Source order for simulation and MLU synthesis |
| `c_ref/` | Unmodified copies of the supplied C sources, plus the vector generator |
| `generate_vectors.sh`, `generate_vectors.bat` | Vector regeneration on Linux / Visual Studio Developer Command Prompt |
| `run_verilator.sh` | Linux Verilator compilation and simulation |
| `logs/` | Original C and RTL verification results |
| `SOURCE_SHA256.txt` | SHA-256 hashes of the supplied C files and original `du_tia_pkg.sv` |

Compile for simulation in this order: `du_tia_pkg.sv → mlu_pkg.sv → mlu.sv → tb_mlu.sv`. For MLU synthesis, use only the first three files and exclude the testbench, vectors, and C programs. If an existing project already compiles `du_tia_pkg.sv`, retain only one definition of the package.

## C-to-RTL Mapping

| C | SystemVerilog |
|---|---|
| `Mlu` | `mlu_state_t state_q` |
| `Mlu next` | Combinational `state_d` |
| `mlu_reset()` | `rst_n=0`, asynchronous active-low reset |
| `mlu_peek()` | Combinational `peek`; outputs depend on old registered state |
| `mlu_tick()` | `next_state` calculation, committed on the rising clock edge |
| `MluEvents` | `mlu_tick_info_t tick_info`, recording events at the preceding edge |
| `IoStatus` | Combinational `status`, indicating checks for the next rising edge |
| `IoFrame.packet` | `out_packet` |
| `IoFrame.meta` | `out_meta`: `tile_id[31:0]`, `dst_addr[63:0]` |
| `IoFrame.k` | `out_k[2:0]`, range 0–7 |

There is no extra output register. `out_packet` is generated combinationally from the registered head buffer and `next_k`. When `out_valid=1` and `out_ready=0`, neither head nor k advances, and the entire packet and sideband remain stable.

`tick_info` is an observation interface and may be left unconnected when unused. Do not use its registered `packet_issued` as DU/TIA input valid for the same edge; it would arrive one cycle late.

## Port Contract

| Interface | Signals | Meaning |
|---|---|---|
| Command | `command_valid`, `command_ready`, `command` | Accept a new tile command only when valid and ready are both 1 |
| Read request | `read_request_valid`, `read_request_ready` | Issue a burst request |
| Read request | `read_addr[63:0]` | Tile source byte address |
| Read request | `read_beats[2:0]` | Actual beat count, 4 or 5; not AXI length-minus-one |
| Read data | `read_data_valid`, `read_data_ready` | Accept a beat only when both are 1 |
| Read data | `read_data[31:0][7:0]` | 32 bytes, or 256 bits, per beat |
| Read data | `read_last` | Must be 1 on the final beat and 0 otherwise |
| DU input | `out_valid`, `out_ready` | MLU output handshake; `out_ready` represents Bridge credit |
| DU input | `out_packet` | 236-bit DU/TIA input packed struct |
| Sideband | `out_meta`, `out_k` | Sent to the wrapper/Bridge with the output handshake |
| Diagnostic | `status`, `tick_info` | Current checks and events from the previous rising edge |

This is the C model's simplified memory interface. A real HBM/AXI controller needs an adapter to translate requests and responses. MLU itself has no HBM controller, AXI IDs, response codes, or arbitration.

`read_data[0]` corresponds to the flattened `read_data[7:0]`, the lowest-address byte in the current beat. Byte i of beat b is stored in `image[32*b+i]`. Do not reverse the byte order of the entire 256-bit word.

During reset and before reset release, keep all connected modules in reset together and suppress valid at the sources. Do not count handshakes during reset. MLU combinational outputs preserve C `peek` semantics; for example, `command_ready` is 1 after clearing the buffers.

## Preserved Timing

1. An accepted command places its buffer in `MLU_PENDING`.
2. A read request can be issued starting on the next cycle; its handshake changes the buffer to `MLU_READING`.
3. Read data can be accepted starting on the following cycle. The first beat is not accepted on the request-acceptance edge.
4. After the final beat is received and the format is valid, the buffer becomes `MLU_READY`.
5. Starting on the next cycle, a ready head buffer outputs k=0.
6. Each `out_valid && out_ready` advances k. Acceptance of k=7 releases the buffer.

All ready/valid decisions use old state. If both buffers are occupied, `command_ready` remains 0 even when k=7 transfers on that edge; the released capacity becomes available on the next cycle. With old count=1, a new command and retirement of the old tile may occur on the same edge. This is the test's `command+retire` case.

One buffer may be reading while the other is outputting. Both may also be READY, but only the head outputs. At most one buffer is READING. When two consecutive tiles are already READY, the next tile's k=0 may follow the previous tile's k=7 on the next cycle.

## Memory Layout

All addresses below are byte offsets from `command.src_addr`. Upstream has already packed sparse data; MLU performs no zero detection or compression.

| Mode | Meaningful image bytes | Transfer bytes / beats | Per-k addressing |
|---|---:|---:|---|
| Dense | 128 | 128 / 4 | `A[:,k]`: `16*k + i`; `B[k,:]`: `16*k + 8 + i` |
| Hybrid | 120 | 128 / 4 | A bitmap: `9*k`; packed A: `9*k + 1 + i`; B as below |
| Dual sparse | 144 | 160 / 5 | A bitmap: `18*k`; packed A: `18*k+1+i`; B bitmap: `18*k+9`; packed B: `18*k+10+i` |

Hybrid B has two K groups. Each group has 8 columns, with 3 bytes per column:

```text
b = 72 + (k / 4) * 24 + column * 3
image[b]     = 2:4 mask
image[b + 1] = packed value[0]
image[b + 2] = packed value[1]
```

k=0–3 uses the first B group; k=4–7 uses the second. `out_packet.k_position = k[1:0]` lets DU/TIA select values from the group. A mask occupies 1 byte in the image; the only legal hexadecimal values are `03, 05, 06, 09, 0A, 0C`. MLU validates all 8 bits, checks that the upper 4 are zero, and then narrows the DU/TIA mask to 4 bits. Validation uses the updated image including the final beat, so illegal masks in that beat are also detected.

Values retain their original INT8 bit patterns: `80` represents −128 and `FF` represents −1. MLU only moves data, so it does not need hardware for the subtract-256 operation in C `io_signed_byte()`. As in the DU/TIA definition, packed lanes are bit vectors; actual multiplication must interpret them as signed.

## DU/TIA and Bridge Wiring for Full Integration

This wiring is not executed by the standalone testbench. Vectors provide `out_ready` in the unit test; the Bridge provides it during full integration. For legal traffic without format errors, the wrapper wiring is:

```systemverilog
assign mlu_out_ready = bridge_issue_ready;
assign issue_fire   = mlu_out_valid && mlu_out_ready;

// DU/TIA has no input_ready; issue once only when credit is available.
assign du_in_valid  = issue_fire;
assign du_in_packet = mlu_out_packet;

// The Bridge uses the same issue_fire for counting and sideband capture.
// bridge_issue = issue_fire;
// bridge_meta  = mlu_out_meta;
// bridge_k     = mlu_out_k;
```

This is illustrative wiring; map the Bridge port names to the actual Bridge RTL. Do not connect MLU `out_valid` directly to DU/TIA `in_valid`: MLU holds valid during a stall, while DU/TIA would accept the same input every cycle. Align `out_meta` / `out_k` with the DU/TIA pipeline in the wrapper/Bridge; they need not be added to DU/TIA or TC data packets. `src_addr` is used only for MLU memory requests; output metadata retains `tile_id` and the `dst_addr` needed by MSU.

## Status and Error-Handling Scope

`IO_OK=0`, `IO_BAD_FORMAT=2`, and `IO_PROTOCOL_ERROR=3` match C. Illegal modes, addresses not aligned to 32 bytes, read/write range overflow, and illegal hybrid masks are format errors. A `read_last` value inconsistent with the beat position is a protocol error. `IO_BAD_ARGUMENT` and `IO_NO_CREDIT` retain their enum values but are not produced by this MLU RTL. The RTL mode is 2 bits, so use `2'b11` for an illegal mode. Arbitrary C integer modes, such as 99, cannot be applied directly to that port.

Full MLU buffers or `valid=1 && ready=0` simply cause waiting; **they do not report an error**. Input format is checked only when the corresponding handshake conditions are met.

To match C, when `status != IO_OK`, all local MLU state holds at that rising edge and `tick_info` clears. `status` is not a sticky error register and must be sampled at the edge.

**Rolling back a C tick cannot automatically undo a physical bus handshake.** This RTL does not alter normal valid/ready timing based on status, so external modules may still observe handshakes on an error edge. Integration must treat nonzero status as a system fault and reset MLU, the memory responder, DU/TIA, Bridge, TC, and MSU together. Do not copy the negative unit test's change-one-input-and-retry procedure into a running system. These tests verify local MLU rejection behavior, not a full-system recovery protocol.

## Original Verification

The following work was completed on 2026-10-24:

- Original C testbench: PASS, 120 tiles, 960 packets, 1,312 cycles.
- The original C model and algorithm were preserved; `gen_mlu_vectors.c` calls it to generate golden vectors.
- Original 120-tile traffic, a consecutive 120-tile stream, and four stalled streams of 256 tiles each with different seeds.
- Every cycle compares all `mlu_peek` outputs, current status, updated events, and the entire 2,900-bit MLU state, including 320 bytes across the two buffers. No state hash substitutes for this comparison.
- Directed tests cover simultaneous command/tile retirement, two READY buffers, full-buffer stalls, head wrap, stable stalled outputs, signed-byte limits, highest legal and out-of-range addresses, incorrect last, multiple illegal values at all 16 hybrid-mask positions, and reset during processing.
- After the standalone revision, all vectors were recompiled and run with an MLU-only source list, retaining every MLU comparison and existing coverage threshold.

| Coverage item | Observed count |
|---|---:|
| Vector records, including resets | 16,708 |
| Reset records | 145 |
| Expected rejected error edges | 128 |
| Accepted commands | 1,397 |
| Packets issued by MLU | 10,236 |
| Fully retired tiles | 1,279 |
| Same-edge new command and old tile retirement | 1 |
| Same-edge read-data acceptance and packet output | 4,087 |
| Command stall cycles due to full buffers | 13,908 |
| Records with both buffers READY after update | 4,396 |

Some directed tests intentionally reset before a tile finishes reading or outputting, so not every command retires. These reset flushes are expected. `command+retire=1` is one explicitly arranged boundary case; `read+output=4087` covers other simultaneous transfers. The counters have different definitions.

The original standalone delivery did not run FPGA/ASIC synthesis or place-and-route and made no claim of Fmax, area, power, or actual HBM performance. The buffers are resettable register arrays, without deliberate BRAM/SRAM inference. This version serves as a cycle-equivalent functional baseline.

## Regeneration and Reruns

Linux:

```bash
bash generate_vectors.sh
bash run_verilator.sh
```

To select a different seed, use `bash generate_vectors.sh 12345`. Wait for vector generation to finish before starting simulation. If Verilator is not on PATH, set `VERILATOR` to the executable's full path. The original run used the PyPI `verilator` 5.48.0 package executable, whose simulation banner displayed Verilator 5.49. That environment required extra GCC PCH and C++20 settings:

```bash
MLU_VERILATOR_MAKEFLAGS='CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_STD=-std=c++20' bash run_verilator.sh
```

Windows: open a Visual Studio Developer Command Prompt with C11 support and run `generate_vectors.bat`. Supplied vectors make this step unnecessary for ModelSim replay. At the original standalone delivery, the Windows `.bat` and ModelSim `.do` files had not been tested in their native environments.

For VCD output, load the ModelSim testbench with `+VCD`. With Verilator, compile with `--trace` before using `+VCD`. The normal ModelSim flow already uses `log -r /*` and WLF waveforms, so extra VCD generation is unnecessary.
