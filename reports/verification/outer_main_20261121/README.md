# Shared outer-product TC on main

> Historical November 21 promotion: "production" and "now" below describe the
> multiply-before-route shared core at that date. Main subsequently received
> operand routing before multiplication and the DU/TIA whole-union assignment
> repair; see the [November 22 promotion and current verification](../operand_route_main_20261122/README.md).
> Original numerical results and patches remain unchanged. The later experiment
> found that the original RTL passed while its sparse netlists failed DU/TIA
> decoding. Those older area/timing reports are not validated sparse-netlist or
> power evidence; the [repaired comparison](../../../experiments/pre_route_20261122/power/du_repair/README.md)
> supplies that validation. Except for the archived TC link below, source links
> resolve to main; the retained patches and manifests identify this dated version.

The baseline is local commit `7e40bf9`, which uses the BRAM MLU, the rotating Bridge FIFO and separate dense and sparse multiplier banks. The production Vivado source set now builds `outer_product_core` for all three input formats.

## SystemVerilog changes

| File | Change |
|---|---|
| [sparse_tensor_core_top.sv](../../../integration_sv/rtl/sparse_tensor_core_top.sv) | At FIFO ingress, copy all eight dense values per operand, set both counts to eight and assign lane indices 0 through 7. Feed the indexed payload at the FIFO head into the TC. |
| [outer_product_core.sv](../../../experiments/pre_route_20261122/baseline/src/tensor_core_sv/outer_product_core.sv) | Accept a 184-bit operand pair with no mode input. Compute 64 signed products, route by row and column index and accumulate in INT32. Reserve one of two result slots per tile. |
| [tb_outer_core.sv](../../../tensor_core_sv/tb_outer_core.sv) | Check C-vector windows that share the new timing contract, including malformed vectors. Exercise a rejected start while both results are reserved and a pop is requested. |
| [tb_compare.sv](../../../tensor_core_sv/tb_compare.sv) | Run the legacy and unified cores on the same matrices. Check GEMM results and publication cycles, then measure the start interval and total cycles at an always-ready sink. |
| [tb_outer_top.sv](../../../integration_sv/tb/tb_outer_top.sv) | Check the normalized payload at FIFO entry and TC acceptance, result timing, all nine mode transitions, reset recovery, and every writeback byte. |

The [RTL-only patch](rtl-only.patch) contains the first two rows. The [complete SV patch](main-sv.patch) contains all five. Both were checked against the predecessor. Applying the complete patch to a copy of the original SV files reproduced the five production files byte for byte. The [old/new TC diff](core-before-after.diff) compares the implementations directly for review. The old module remains available to the comparison test.

The top-level ports and memory images retain their existing contracts. Dense traverses the same four DU/TIA stages and bypasses sparse bitmap decoding. The adapter supplies fixed coordinates before the FIFO writes its registered entry. A stored zero occupies its original lane. The Bridge still checks the source-format tag against the delayed sideband. Its two result metadata slots are allocated on TC acceptance of k=0 and released on the TC-to-MSU handshake.

## Functional results

ModelSim 2020.1 ran the isolated units, the old/new comparison and then the integration test. The original C models, reference vectors, testbenches and seed are retained. The verifier checked 91 file hashes and all 50 expected top summary lines. [Verification result](PASS.txt) · [Units and benchmark](units.log) · [Integration log](top.log) · [Source manifest](main_manifest.csv)

- The TC unit checked 21,032 compatible C records, 1,366 result publications, six malformed vector rejections and one directed full-credit rejection. The C trace uses the predecessor's dense timing. The functional checks for dense use the GEMM oracle in the comparison and integration tests.
- The integration run completed 369 tiles with 77 resets. The counters include 3,542 issued packets and 2,987 accepted write beats across completed tiles and work interrupted by reset. All nine mode transitions occurred. The unstalled dense and mixed streams checked every tile-start interval (23 and 26 intervals, respectively).
- For continuous accepted input, all formats publish three edges after accepting k=7. With a ready result sink, k=0 on edge 0 gives publication after edge 10 and earliest result acceptance on edge 11. The next tile can start on edge 8 when a result slot is available.

| Standalone TC benchmark, 24 tiles | Prior cycles | Shared core cycles |
|---|---:|---:|
| Dense | 576 | 196 |
| Full-count indexed | 196 | 196 |
| Alternating dense and full-count indexed | 432 | 196 |

Cycles are counted from the first accepted slice through the last result handshake. The integrated system also observes memory and result backpressure.

## Resource use and timing

The two integrated designs use Vivado 2022.2, `xc7z020clg484-1`, the same 10.000 ns clock, default placement and routing, and out-of-context synthesis. These are internal post-route results. [Predecessor run](../bram_main_20261119/README.md) · [Native utilization](native/independent_checkpoint/utilization.rpt) · [Native timing](native/independent_checkpoint/timing_summary.rpt) · [Critical paths](native/independent_checkpoint/critical_paths.rpt)

| Post-route metric | Prior main | Shared core | Change |
|---|---:|---:|---:|
| Slice LUTs | 28,213 | 22,581 | −5,632 (−20.0%) |
| Slice registers | 19,852 | 16,281 | −3,571 (−18.0%) |
| DSP48E1 | 128 | 64 | −64 (−50%) |
| RAMB36E1 | 18 | 18 | 0 |
| Setup WNS | +0.011 ns | +0.162 ns | +0.151 ns |
| Hold WHS | +0.098 ns | +0.096 ns | −0.002 ns |

The worst setup path starts at Bridge metadata occupancy bit 1 and ends at the MSU result-buffer clock enable. Routing accounts for 7.258 ns of the 9.549 ns data path. Both versions meet 100 MHz internally. This promotion measures internal timing at a single constraint.

The initial native run paused while writing the post-placement optimization checkpoint. The retained placement checkpoint was opened in a separate process, passed through default physical optimization and routing, written to disk and independently reopened. The active project run then resumed from its placement checkpoint and completed routing. The native run, its independently reopened checkpoint and the separate replay agreed on resources and slack. Each reported 31,810 fully routed nets, zero routing errors and zero DRC errors. [Reopened native run](native/reopened_run/PASS.txt) · [Independent native checkpoint](native/independent_checkpoint/PASS.txt) · [Separate placement replay](placement_replay/PASS.txt)

## Reproduction

Run these commands from the checkout root. Use an unused output directory and Vivado run suffix.

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
pwsh -NoProfile -File tools/verify_bram_main.ps1 -OutputDir build/outer_verify_repeat
& 'C:/Xilinx/Vivado/2022.2/bin/vivado.bat' -mode batch -nojournal -log build/outer_repeat.log -source tools/run_bram_100mhz_project.tcl -tclargs build/outer_route_repeat outer_repeat
```

The project, simulation file lists, waveform setup, implementation checks and documentation select the production core. The physical build uses the 11 sources listed in [project settings](native/project_settings.txt). The standalone ModelSim entry also ran successfully. Verilator was unavailable on the validation host.
