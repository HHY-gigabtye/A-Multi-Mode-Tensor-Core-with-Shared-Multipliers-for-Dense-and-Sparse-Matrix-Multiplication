# Isolated 19-bit TC experiment — 2026-11-22

## Scope and acceptance gate

The user authorized an isolated trial narrowing the TC accumulator and its two
result-storage matrices to signed 19 bits, with exact signed INT32 external
results. The current production RTL and all existing references, vectors,
testbenches, seeds and assertions remain unchanged. The user-owned pre-existing
AGENTS.md modification is recorded and preserved.

The fixed K=8 contract bounds every partial and completed dot product between
-130048 and +131072. Signed 18 bits cannot represent +131072; signed 19 bits can.
There is no cross-tile accumulation. Only the candidate's
`src/tensor_core_sv/outer_product_core.sv` may differ from the 93-file baseline.
The public packet/package layout, two result credits, strict rejected-edge
freeze, stage observations, reset and stale-result behavior must remain exact.
The 64 DSP multipliers and fabric-only adder mapping remain explicit.

Acceptance requires original unit tests before integration, supplementary
standalone baseline equivalence and independent GEMM including numeric bounds,
II=8 and k=7+3 publication, then comparable integrated Vivado 2022.2 OOC
post-route implementation at 10.000 ns on xc7z020clg484-1. Reopen each checkpoint
for setup, hold, route completeness, DRC and DSP/BRAM configuration checks.
Routed functional-netlist workloads provide a further RTL-to-synthesis check.
These are internal FPGA results, not board or ASIC sign-off.

The immutable baseline source and initial Git/docs state are recorded beside
the candidate snapshot. Fresh regression and implementation directories are
required; scripts must not overwrite accepted evidence.

## Result

Completed: the isolated candidate passes all original regressions, supplemental
equivalence and numeric bounds, three-mode routed functional workloads, and the
independently reopened 100 MHz internal FPGA OOC gate. Production is unchanged.

Post-route resources decrease from 12,769 to 10,101 LUTs (-20.89%) and from
15,519 to 11,295 FFs (-27.22%). DSP48E1 and RAMB36E1 counts remain 64 and 18.
II=8 and k=7+3 publication are preserved. Setup/hold slack is +0.004/+0.098 ns,
versus +0.296/+0.082 ns for the baseline. The candidate passes 100 MHz but has
only 4 ps setup margin. A matched additional physical refinement does not
improve that margin; the original audited route remains the primary result.

See [REPORT.md](REPORT.md) for measurements, commands and limitations,
[rtl.diff](rtl.diff) for the only RTL change, and
[validation.PASS.txt](validation.PASS.txt) for the aggregate acceptance record.
