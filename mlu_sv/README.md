# MLU SystemVerilog — Standalone Unit Verification

Derived from the supplied `mlu_model(2).c`, `mlu_model(3).h`, and `io_types(4).h`.
The design preserves two tile buffers, one outstanding read burst, and eight
ordered k-packets per tile. `out_packet` uses the existing
`du_tia_pkg::du_tia_input_t` directly.

## Verification scope

`tb_mlu.sv` instantiates only `mlu dut`. C-generated vectors supply commands,
memory-response beats, read-request readiness, and downstream `out_ready`.
Every edge checks the output packet, metadata, k, handshake events, status, and
complete buffer state. Vectors also control stalls; no real DU/TIA, Bridge/FIFO,
TC, or MSU is required.

Compile `du_tia_pkg.sv` for the output packet type; importing a package does not
instantiate DU/TIA hardware. This standalone packaging revision removed the
DU/TIA instance, decoder reference, four-stage scoreboard, decoder counts, and
associated waveforms. Its simulation project no longer includes `du_tia.sv`.
MLU RTL, the C model, and existing golden vectors were unchanged by that revision.

Verify each unit independently before connecting MLU → DU/TIA → Bridge/FIFO →
TC → MSU in a separate top-level testbench. This package runs neither partial nor
full integration; the wiring example below is for subsequent integration.

## Running ModelSim

Extract the entire directory and enter this in the ModelSim Transcript:

```tcl
do C:/your_path/mlu_sv/run_mlu.do
```

Use braces for paths containing spaces:

```tcl
do {C:/your path/mlu_sv/run_mlu.do}
```

The script changes directory, compiles, adds waveforms, and runs the test.
`mlu_vectors.txt` is included, so SV simulation does not require compiling C
first. Expected output:

```text
ALL PASS MLU unit C/SV: 16708 records, 145 resets, 128 rejected edges
  commands=1397 packets=10236 retired=1279
  command+retire=1 read+output=4087 full_stalls=13908 both_ready=4396
```

The original delivery was tested with Verilator, not locally with
ModelSim/Questa. The testbench uses procedural checks, without SVA, DPI, UVM,
or classes.

## Files and compilation order

| File | Purpose |
|---|---|
| `du_tia_pkg.sv` | Original packet-type package; no DU/TIA module instance |
| `mlu_pkg.sv` | Commands, metadata, buffers, events, and packet conversion helpers |
| `mlu.sv` | MLU RTL, with top module `mlu` |
| `tb_mlu.sv` | Instantiates only MLU and compares C vectors cycle-by-cycle |
| `mlu_vectors.txt` | Complete generated test vectors |
| `run_mlu.do`, `wave_mlu.do` | ModelSim simulation and waveform scripts |
| `sim.f`, `synth.f` | Source order for simulation and MLU synthesis |
| `c_ref/` | Unmodified supplied C sources and the added vector generator |
| `generate_vectors.sh`, `generate_vectors.bat` | Vector regeneration on Linux or in a Visual Studio Developer Command Prompt |
| `run_verilator.sh` | Linux Verilator build and simulation |
| `logs/` | Recorded C and RTL validation results |
| `SOURCE_SHA256.txt` | SHA-256 of the supplied C files and original `du_tia_pkg.sv` |

Simulation order is `du_tia_pkg.sv → mlu_pkg.sv → mlu.sv → tb_mlu.sv`.
Synthesis uses only the first three files, excluding the testbench, vectors,
and C code. If a project already compiles `du_tia_pkg.sv`, retain only one
package definition.

## C-to-RTL mapping

| C | SystemVerilog |
|---|---|
| `Mlu` | `mlu_state_t state_q` |
| `Mlu next` | Combinational `state_d` |
| `mlu_reset()` | Asynchronous active-low reset, `rst_n=0` |
| `mlu_peek()` | Combinational `peek`, using old registered state |
| `mlu_tick()` | `next_state` computation, committed on the rising edge |
| `MluEvents` | `mlu_tick_info_t tick_info`, describing the edge just completed |
| `IoStatus` | Combinational `status`, checking inputs for the next rising edge |
| `IoFrame.packet` | `out_packet` |
| `IoFrame.meta` | `out_meta`: `tile_id[31:0]`, `dst_addr[63:0]` |
| `IoFrame.k` | `out_k[2:0]`, in the range 0–7 |

No extra output register is added. `out_packet` is generated combinationally
from the registered head buffer and `next_k`. While `out_valid=1` and
`out_ready=0`, the head and k do not advance, so the complete packet and sideband
remain stable.

`tick_info` is an optional observation interface. Do not use its registered
`packet_issued` as same-edge DU/TIA input valid; that would be one cycle late.

## Port contract

| Interface | Signals | Meaning |
|---|---|---|
| Command | `command_valid`, `command_ready`, `command` | Accept a tile command only when valid and ready are both high |
| Read request | `read_request_valid`, `read_request_ready` | Issue one burst request |
| Read request | `read_addr[63:0]` | Source byte address for the tile |
| Read request | `read_beats[2:0]` | Actual beat count, 4 or 5; not AXI length-minus-one |
| Read data | `read_data_valid`, `read_data_ready` | Accept a beat only when both are high |
| Read data | `read_data[31:0][7:0]` | 32 bytes / 256 bits per beat |
| Read data | `read_last` | High on the final beat only |
| DU input | `out_valid`, `out_ready` | MLU output handshake; `out_ready` represents Bridge credit |
| DU input | `out_packet` | 236-bit DU/TIA input packed structure |
| Sideband | `out_meta`, `out_k` | Transferred to the wrapper/Bridge with the output handshake |
| Diagnostic | `status`, `tick_info` | Current-edge checks and events from the previous rising edge |

This is the C model's simplified memory interface. An adapter must translate
requests and responses for a real HBM/AXI controller; MLU contains no HBM
controller, AXI IDs, response codes, or arbitration.

`read_data[0]` corresponds to `read_data[7:0]`, the lowest-address byte in the
current beat. Byte i of beat b is stored in `image[32*b+i]`. Do not reverse the
byte order of the complete 256-bit word.

During reset and before reset release, keep connected modules in reset together
and stop source valid signals. Do not count handshakes during reset. MLU's
combinational outputs retain C `peek` semantics; for example, `command_ready`
is high after the buffers are cleared.

## Preserved timing

1. An accepted command puts its buffer in `MLU_PENDING`.
2. A read request can first appear in the following cycle; acceptance changes the buffer to `MLU_READING`.
3. Read data can first be accepted on the next edge, never on the request-acceptance edge.
4. The final accepted beat changes the buffer to `MLU_READY` if its format is valid.
5. Starting next cycle, a ready head buffer presents k=0.
6. Each `out_valid && out_ready` advances k once; accepting k=7 releases the buffer.

All ready/valid decisions use old state. With both buffers occupied,
`command_ready` remains low even if k=7 transfers on that edge; released space
is usable next cycle. With old count=1, a new command and retirement of the old
tile may occur together; this is the `command+retire` coverage case.

One buffer can be reading while the other outputs. Both may be READY, but only
the head outputs. At most one buffer is READING. If consecutive tiles are both
READY, the next tile's k=0 can follow the previous k=7 on the next edge.

## Memory layout

Addresses below are byte offsets from `command.src_addr`. Sparse packing is
performed upstream; MLU does not detect zeros or compress data.

| Mode | Valid image bytes | Transferred bytes / beats | Per-k layout |
|---|---:|---:|---|
| Dense | 128 | 128 / 4 | `A[:,k]`: `16*k + i`; `B[k,:]`: `16*k + 8 + i` |
| Hybrid | 120 | 128 / 4 | A bitmap: `9*k`; A packed: `9*k + 1 + i`; B as below |
| Dual sparse | 144 | 160 / 5 | A bitmap: `18*k`; A packed: `18*k+1+i`; B bitmap: `18*k+9`; B packed: `18*k+10+i` |

Hybrid B contains two K groups, each with 8 columns and 3 bytes per column:

```text
b = 72 + (k / 4) * 24 + column * 3
image[b]     = 2:4 mask
image[b + 1] = packed value[0]
image[b + 2] = packed value[1]
```

k=0–3 uses the first B group; k=4–7 uses the second.
`out_packet.k_position = k[1:0]` selects the position within that group in DU/TIA.
The image stores each mask in one byte, with legal values `03, 05, 06, 09, 0A, 0C`.
MLU validates all 8 bits, including zero upper bits, before narrowing the mask to
4 bits for DU/TIA. Validation includes the newly arrived final beat, so illegal
masks in that beat are detected.

Values retain their raw INT8 patterns: `80` means −128 and `FF` means −1. MLU
only moves data, so it needs no subtract-256 circuit corresponding to C's
`io_signed_byte()`. Packed lanes remain bit vectors under the existing DU/TIA
types; actual multiplication must interpret them as signed.

## DU/TIA and Bridge wiring for later full integration

This section is not exercised by the standalone testbench. Vectors currently
drive `out_ready`; Bridge supplies it in full integration. For valid traffic:

```systemverilog
assign mlu_out_ready = bridge_issue_ready;
assign issue_fire   = mlu_out_valid && mlu_out_ready;

// DU/TIA has no input_ready: issue once only after credit is available.
assign du_in_valid  = issue_fire;
assign du_in_packet = mlu_out_packet;

// Bridge uses the same issue_fire for accounting and sideband capture.
// bridge_issue = issue_fire;
// bridge_meta  = mlu_out_meta;
// bridge_k     = mlu_out_k;
```

These are illustrative signal names; adapt them to the Bridge RTL ports.
Do not connect MLU `out_valid` directly to DU/TIA `in_valid`: MLU holds valid
while stalled, whereas DU/TIA would accept it every cycle and duplicate packets.
Align `out_meta` / `out_k` with DU/TIA through the wrapper; do not add them to the
DU/TIA or TC data packets. `src_addr` is only for MLU reads. Output metadata
retains `tile_id` and the `dst_addr` needed later by MSU.

## Status and error handling

`IO_OK=0`, `IO_BAD_FORMAT=2`, and `IO_PROTOCOL_ERROR=3` match C. Invalid mode,
non-32-byte-aligned addresses, read/write span overflow, and illegal hybrid masks
are format errors. A `read_last` mismatch is a protocol error.
`IO_BAD_ARGUMENT` and `IO_NO_CREDIT` retain their enum values but are not produced
by MLU RTL. The RTL mode port is 2 bits; use `2'b11` for an illegal mode. Arbitrary
C integer modes such as 99 cannot be passed directly through that port.

Full buffers and `valid=1 && ready=0` are normal waits, **not errors**. Format
checks apply only when the corresponding input meets handshake conditions.

To match C, `status != IO_OK` freezes all local MLU state on that edge and clears
`tick_info`. `status` is combinational, not sticky, and must be sampled on the edge.

**C's whole-tick rollback cannot undo a real bus handshake.** RTL does not use
status to rewrite normal valid/ready timing, so external modules may still see
a handshake on an erroneous edge. Treat nonzero status in integration as a
system fault: reset MLU, the memory responder, DU/TIA, Bridge, TC, and MSU
together. Do not retry by changing one input while the rest of the system keeps
running. Negative unit tests verify local MLU rejection, not system recovery.

## Original validation

Completed on 2026-10-24:

- Original C testbench: 120 tiles, 960 packets, 1,312 cycles, PASS.
- The C model and algorithm were unchanged; `gen_mlu_vectors.c` called it to produce golden vectors.
- Original 120-tile traffic, a continuous 120-tile stream, and four stalled 256-tile streams with distinct seeds.
- Every edge compared all `mlu_peek` outputs, current status, updated events, and the complete 2,900-bit state, including 320 bytes across both buffers; no state hash substituted for this comparison.
- Directed cases: simultaneous command/retirement, both slots READY, full stalls, head wrap, stalled output stability, signed-byte extremes, maximum legal and overflowing addresses, bad last, illegal values at all 16 hybrid mask positions, and reset during work.
- After standalone repackaging, the MLU-only source list was rebuilt and every vector rerun, preserving all comparisons and coverage thresholds.

| Coverage | Measured count |
|---|---:|
| Vector records, including reset | 16,708 |
| Reset records | 145 |
| Expected rejected error edges | 128 |
| Accepted commands | 1,397 |
| Issued MLU packets | 10,236 |
| Fully issued tiles | 1,279 |
| Simultaneous new command and old tile retirement | 1 |
| Simultaneous read-data acceptance and packet issue | 4,087 |
| Command stalls due to full buffers | 13,908 |
| Records with both buffers READY after update | 4,396 |

Some directed cases reset before a tile finishes loading or issuing, so not every
command retires. These flushes are expected. `command+retire=1` is one explicit
boundary case; `read+output=4087` measures a different simultaneous-transfer case.

The original validation did not run FPGA/ASIC synthesis or place-and-route and
claimed no Fmax, area, power, or real HBM performance. Buffers use resettable
register arrays without deliberate BRAM/SRAM inference. This version serves as
a cycle-equivalent functional baseline.

## Regeneration and reproduction

Linux:

```bash
bash generate_vectors.sh
bash run_verilator.sh
```

An alternate seed can be supplied as `bash generate_vectors.sh 12345`. Wait for
vector generation before starting simulation. If Verilator is not on PATH, set
`VERILATOR` to its full executable path. The original environment used the PyPI
`verilator` 5.48.0 executable, whose banner reported Verilator 5.49. It required
these additional GCC PCH and C++20 settings:

```bash
MLU_VERILATOR_MAKEFLAGS='CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_STD=-std=c++20' bash run_verilator.sh
```

On Windows, run `generate_vectors.bat` in a C11-capable Visual Studio Developer
Command Prompt. Included vectors allow ModelSim-only users to skip generation.
At the original delivery, the Windows `.bat` and ModelSim `.do` scripts had not
been tested in their native environments.

For VCD, manually load the ModelSim testbench with `+VCD`; Verilator requires
compilation with `--trace` before using `+VCD`. The normal ModelSim flow already
uses `log -r /*` and WLF waveforms, so extra VCD output is unnecessary.
