# TC cycle comparison against the linked GitHub version

Verified on 2026-11-12 with ModelSim Intel FPGA Edition 2020.1.

Both the linked GitHub RTL and the current local RTL passed the unchanged
136,136-record unit regression. The checks include per-cycle handshakes, stage
events, result-valid timing, result payloads, and the logical internal-state hash.
This establishes matching behavior for the tested traces, not exhaustive formal
equivalence. No production RTL, reference model, testbench, or vectors were
modified for this comparison.

## Compared inputs

The user-provided `main` link was resolved to commit
`fe14c132af8e319af2e806e6758d2010341c1bf6` before fetching the source:
[pinned GitHub TC](https://github.com/HHY-gigabtye/A-Multi-Mode-Tensor-Core-with-Shared-Multipliers-for-Dense-and-Sparse-Matrix-Multiplication/blob/fe14c132af8e319af2e806e6758d2010341c1bf6/tensor_core_sv/tensor_core.sv).
This identifies the linked version; it does not assert that this is the first
historical commit of the project.

| File | Verified identifier |
| --- | --- |
| `github_tensor_core.sv` | Git blob `595fe7ec487319e6abeec0577a9031a7e74bd955` |
| `current_tensor_core.sv` | SHA256 `954F43FE5941A3346AF2D419BF04AC68F5006D182F5FC3B1F5E463D6265210D4` |
| Shared `tensor_core_pkg.sv` | Git blob `c3bffb24060888ed3ec05a5425e572258073683b` |
| Shared `tb_tensor_core.sv` | Git blob `819e961b5cc35a9a2c0ca5dbbce908b9b3eecee5` |
| Shared `c_vectors.txt.gz` | Git blob `66491e9dfb71d5ca72e376a6ebcd4fb702aaaffd` |
| Uncompressed `c_vectors.txt` | SHA256 `95906DB99B23A97FDF4580A768C481B861C2983F017742E513711DBEE3D39935` |

The package, testbench, and compressed-vector Git blobs match the pinned GitHub
directory. The decompressed gzip bytes match the text vectors used by ModelSim.
The current snapshot SHA256 also matches the live local TC after both runs.

## Results and clock-edge convention

Assume an initially idle TC with empty result storage, eight consecutive accepted
packets (k=0 through k=7), and `result_ready=1`. Let edge N accept k=0.

| Event | GitHub version | Current version |
| --- | --- | --- |
| Dense result becomes valid after edge | N+22 | N+22 |
| Dense earliest result handshake | N+23 | N+23 |
| Sparse result becomes valid after edge | N+10 | N+10 |
| Sparse earliest result handshake | N+11 | N+11 |

These offsets come from the shared golden events in `nominal_cycles.json`, whose
per-cycle values both RTL runs pass. Dense example: records 2/9/24/25 for first
input, last input, production, and consumption. Sparse example: records
94334/94341/94344/94345 respectively. Backpressure or input gaps can increase
elapsed latency. These are TC-only counts, not end-to-end memory latency.

For a sparse packet accepted at edge N, both versions perform MUL capture at N,
ROUTE capture at N+1, and ACC at N+2. The original source computes the product at
lines 327-329 and registers it through `sparse_q <= sparse_d` at line 356. The
current separate `product_q` replaces that existing MUL data register. It does
not add another sequential stage before ROUTE.

Both runs reported:

```text
ALL PASS C/SV: 136136 records, 169 resets, 13 RTL rejection cases
  published=6440 consumed=6392 overlap_starts=1609
  pop_and_push=1 consume_and_start=151 full_fifo_cycles=3480
```

`comparison_retry.log` contains the two runs, with separate `cycle_github` and
`cycle_current` libraries and zero compiler/simulator errors. The initial
`comparison.log` records a runner path-resolution error before compilation;
`run_compare.do` was corrected to locate the repository from the working
directory. No test or RTL change was needed.

## Commands and generated files

Executed from the repository root in PowerShell:

```powershell
& 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -c -l reports/verification/tc_cycles_github_fe14c132/comparison_retry.log -do reports/verification/tc_cycles_github_fe14c132/run_compare.do
& ./reports/verification/tc_cycles_github_fe14c132/inspect_vectors.ps1
```

The runner intentionally rejects existing comparison libraries. To repeat,
preserve/rename its existing `build` directory first; this keeps the original
run artifacts. The vector inspector requires PowerShell 7/.NET with
`Convert.ToHexString` support.

All files created for this task are under this report directory: two RTL
snapshots, the comparison runner, the vector inspector, nominal-cycle JSON,
this README, logs, and simulator build artifacts. No branch/worktree or commit
was created. This run checks RTL cycle behavior and supplies no new synthesis,
placement, routing, or clock-period measurement.
