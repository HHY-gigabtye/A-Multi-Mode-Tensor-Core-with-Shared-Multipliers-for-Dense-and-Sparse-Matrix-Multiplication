# Source audit and architecture reconciliation

Audit date: 2026-10-29. Baseline Git HEAD: `7dba760`, preceded by `e41a44e`.
Statements below distinguish inspected implementation from measured behavior.
The audit adds documentation, packaging helpers and evidence; it does not alter
existing C/SV source, test assertions, seeds, interfaces or timing.

## Source map

| Unit | RTL / package | C reference | SV test |
|---|---|---|---|
| MLU | `mlu_sv/mlu.sv`, `mlu_pkg.sv` | `mlu_sv/c_ref/mlu_model.c` | `mlu_sv/tb_mlu.sv` |
| DU/TIA | `du_tia_sv/rtl/du_tia.sv`, `du_tia_pkg.sv` | `c code/DU & TIA/DU & TIA/DU & TIA.c` | `du_tia_sv/tb/tb_du_tia.sv` |
| Bridge | `fifo_sv/du_tc_bridge.sv`, `du_tc_bridge_pkg.sv` | `fifo_sv/c_reference/du_tc_bridge.c` | `fifo_sv/tb_bridge.sv` |
| TC | `tensor_core_sv/tensor_core.sv`, `tensor_core_pkg.sv` | `tensor_core_sv/c_reference/tensor_core_model.c` | `tensor_core_sv/tb_tensor_core.sv` |
| MSU | `msu_sv/rtl/msu.sv`, `msu_pkg.sv` | `msu_sv/reference/msu_model.c` | `msu_sv/tb/tb_msu.sv` |
| System | `integration_sv/rtl/sparse_tensor_core_top.sv` | Independent SV GEMM oracle at this boundary | `integration_sv/tb/tb_sparse_tensor_core_top.sv` |

The four packaged C model `.c` files for MLU/MSU/Bridge/TC are byte-identical
to their corresponding originals under `c code/`. SHA-256 comparison also
confirms that `mlu_sv/du_tia_pkg.sv` equals the DU/TIA package and
`fifo_sv/tensor_core_pkg.sv` equals the TC package. Retain these copies for
standalone unit builds, but compile only one of each package in integration.

The original `c code/` directory also contains Visual Studio solutions/projects,
a basic mathematical outer-product example, an empty DU/TIA `.cpp` file, and a
TC `.cpp` Hello World template. The active TC reference is `tensor_core_model.c`
with `tb_tensor_core.c`; the `.cpp` template is not the arithmetic reference.

## Confirmed architecture

- Fixed M=N=K=8, signed INT8 multiplication, signed INT32 accumulation.
- Three MLU input modes (0/1/2); both sparse formats become `is_sparse=1`.
- Dense output-stationary systolic dataflow and separate sparse MUL/ROUTE/ACC
  state, with one common 8x8 multiplication loop selecting operands by mode.
- Four DU/TIA registers S0-S3, no `out_ready`; the Bridge owns four sideband
  registers. Top does not duplicate this delay.
- Eight packet FIFO slots, with old-state `count + inflight < 8` readiness,
  no arrival bypass, and a separate two-slot result-metadata queue.
- Top presents the stored FIFO packet to TC before consulting its mode-aware
  `in_ready`; `in_valid` is pulsed only on an eligible transfer.
- Metadata is pushed on accepted k=0 and popped at TC-to-MSU transfer.
- TC reserves one of two result slots on a tile start. Sparse starts may overlap
  the previous tile's pipeline tail; dense work drains before restart.
- MLU has two tile buffers, fixed 32-byte beats and one outstanding read burst.
  It packetizes already packed sparse images; it is not a sparse compressor.
- MSU has two full matrix buffers and emits eight little-endian row writes;
  completion follows the last accepted write. No old-C or cross-K accumulation.

## Reconciliations with older material

1. `docs/architecture.md` is an explicitly provisional handoff. Its descriptions
   of pending ModelSim/integration work are superseded by the existing October
   27 logs and the October 29 rerun. Its 474-tile historical C integration claim
   is not a current full-system C result: no `tb_pipeline.c` was found here.
2. The old approximately 80-83 MHz unplaced ASIC remark is unsupported by an
   ASIC report in this checkout. Actual available reports are Vivado FPGA
   out-of-context reports. TC-alone 12 ns fails setup; top-level 17 ns meets
   its specified internal constraints with incomplete I/O constraints.
3. Legacy `c code/MLU_MSU_FIFO_README.md` describes packaging files such as
   `MLU_MSU_BRIDGE.sln`, `make test`, and `build_msvc.bat` that do not exist at
   those locations in this checkout. Use the root README's inspected commands.
4. DU/TIA C has diagnostic tags/bitmap/valid-mask fields removed from the
   compact RTL representation. Its C and SV test populations also differ.
   Do not claim that DU/TIA performs whole-state C/SV replay equivalence.
5. The TC SV test uses a 32-bit internal-state hash plus direct matrix checks;
   MLU and Bridge compare complete state vectors. These are different strengths
   of checking, and neither is a formal equivalence proof.
6. MSU suppresses physical ready/valid during reset or an invalid destination;
   its TB derives effective handshakes from C outputs, reset and status. MLU's
   local rejected-edge model does not provide transaction rollback at a live
   bus. End-to-end verification covers legal traffic and coordinated resets.
7. At the October 29 audit start, `msu_sv/sim/run_msu.do` contained an
   uncommitted machine-specific root, and the top TB contained an uncommitted
   blank-line change. Both were preserved exactly as found. These observations
   describe that local working tree, not the current GitHub tracking status.
   Use the root unit runner to avoid the machine-specific MSU entry point.
8. The new top implementation reports and XPR were untracked at audit start.
   Matching their source paths to this checkout is not proof of exact synthesis
   input provenance; no source-hash manifest accompanied the archived run.

## Verification boundaries and open work

The rerun checks available directed/random regressions and coverage thresholds.
It does not establish exhaustive coverage, formal proof, post-route simulation,
physical clock/reset integration, actual HBM/AXI support, malformed-transaction
recovery across all modules, or network/application-level performance.
The 10 ns testbench clock is simulation scheduling, not a 100 MHz timing result.

Sparse II=8 refers to accepted TC tile starts under suitable traffic and credit
availability. Memory loading, mode switches, result stalls, and writeback may
increase end-to-end latency. "64 shared multipliers" is a source-level resource
organization, not a claim of 64 FPGA DSP primitives or quantified area savings.

## Documentation update, November 1, 2026

At the October 29 audit, the original diagrams were local material whose
authorship and correspondence to the RTL had not been established; the README
used a text/Mermaid connectivity summary derived from the inspected top module.

The public repository now includes the author's updated
[overall system architecture](Overall%20System%20Architecture.png) and
[DU/TIA and Tensor Core architecture](DU%26TIA%20and%20Tensor%20Core%20architecture.png)
images. The [root README](../README.md) presents them in Sections 3 and 5 and
retains the Mermaid connectivity summary in an expandable section. The captions
identify the simplified memory boundary, shared multipliers, and conceptual
scope of the compute diagram. This documentation update does not establish
new RTL verification results or change the implementation limitations above.
