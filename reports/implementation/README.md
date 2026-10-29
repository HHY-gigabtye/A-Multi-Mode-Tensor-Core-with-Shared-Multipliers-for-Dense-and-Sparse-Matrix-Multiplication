# Archived FPGA implementation evidence

These reports already existed before the portfolio audit. They were read and
selected for documentation; synthesis/place/route was **not rerun**. Local
originals remain in the Vivado project run directories. Copies here preserve
tool copyright notices and all metrics; only `Host` header values are replaced
with `<redacted>`. `provenance.csv` records source paths and original/copy hashes.
This does not imply redistribution rights for third-party paper PDFs.

## Integrated top, October 29, 2026

- Design: `sparse_tensor_core_top`.
- Vivado 2022.2, build 3671981; `xc7z020clg484-1`, production speed file 1.12.
- Archived synthesis command uses `-mode out_of_context`.
- Clock constraint: 17.000 ns; slow/fast corners analyzed; 58.824 MHz target.
- Post-route WNS +0.202 ns, TNS 0.000 ns, WHS +0.096 ns.
- Route-status report: 46,913 routable nets fully routed; zero routing errors.
- Post-place utilization: 36,222 LUTs, 22,467 registers, zero DSPs and BRAM.
- The tool says all *specified* constraints are met, but 424 input and 592
  output ports have no I/O delay constraint. BUFGCTRL usage is zero in this
  OOC design, and routed DRC warns that the PS7 block is required.

The worst reported setup path starts at
`u_bridge/q_reg[fifo][5][packet][is_sparse]/C` and ends at
`u_tensor_core/dense_q_reg[pe][7][0][acc][29]/D`. It has 20 logic levels
(`CARRY4=9 LUT2=1 LUT3=1 LUT4=4 LUT6=5`), a data-path delay of 16.776 ns,
of which 5.419 ns is logic and 11.357 ns routing. One control net on the path
has fanout 984. This is a control/mode-to-accumulator path through muxing and
arithmetic, not evidence that the isolated multiplier alone limits timing.

## TC alone, October 19, 2026

The archived `tensor_core` project uses the same device family/tool version and
OOC synthesis, with a 12.000 ns clock target (83.333 MHz). Its **post-route**
report gives WNS -0.238 ns and TNS -2.894 ns over 35 failing setup endpoints.
It also lacks 188 input and 2,078 output delay constraints. The target fails;
do not publish 83.333 MHz as an achieved operating frequency.

## Limits and reproduction status

These are FPGA reports, not ASIC area/power/library-corner measurements. The
two runs differ in design scope and constraint and are not a controlled
optimization comparison. A frequency calculated from slack is not a measured
Fmax. No frequency sweep, complete board timing closure, bitstream bring-up,
activity-calibrated power run, or physical HBM experiment is established.

Original `.xpr` and `.xdc` files are retained at their original relative paths
in the candidate snapshot. The project files include machine-specific cached
settings and reference generated incremental checkpoints that are intentionally
not published. Regeneration may require disabling/rebuilding those checkpoints
and adapting the local project settings. The complete PPA reproduction flow
and exact source-to-report commit association are **Not Yet Verified**.

Included evidence under `top/`: timing summary, placed utilization, route
status and routed DRC. Under `tc/`: timing summary and placed utilization.
Power reports exist locally but are not used for a headline power claim because
switching-activity provenance has not been established.
