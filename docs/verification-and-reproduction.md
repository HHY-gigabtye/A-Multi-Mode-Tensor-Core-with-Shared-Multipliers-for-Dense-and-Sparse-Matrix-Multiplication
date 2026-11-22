# Verification and reproduction

## Current shared-core verification

Current `main` builds `outer_product_core.sv` for dense, hybrid and dual-sparse
tiles using **Routing → MUL → ACC**, together with the DU/TIA whole-union
assignment repair. TC now uses signed 19-bit internal accumulation/result storage
and exact INT32 external results. The [19-bit verification record](../reports/verification/tc19_main_20261122/README.md)
contains fresh main-source units, additional equivalence/bounds units, integration
results, and retained candidate post-route evidence whose source hashes match main.
Promotion did not rerun implementation; no 19-bit power estimate was measured.
The [earlier November 22 record](../reports/verification/operand_route_main_20261122/README.md)
describes the 32-bit operand-routing core and its power evidence. The [November 21 record](../reports/verification/outer_main_20261121/README.md)
describes the preceding multiply-before-route shared core; the older observations
below apply to their dated snapshots.

From the repository root, restore the immutable vectors, then run the isolated
units and old/new TC comparison before the connected test:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1
```

The TC unit is `tb_outer_core.sv`; the system test is `tb_outer_top.sv`. The
unchanged C model still contains a dense systolic path and mode-switch drain
rules. Only compatible outer-product windows are replayed against the new TC.
Dense and mixed-format checks use mathematical GEMM and the shared-core timing
contract: publication three advancing edges after k=7 and unstalled tile II=8.
The original C tests and full legacy replay remain predecessor evidence.

For a repeat that preserves the accepted logs, choose a fresh run name:

```powershell
./reports/verification/tc19_main_20261122/run_regression.ps1 -RunName regression_repeat
```

The older `tools/verify_bram_main.ps1`, operand-route promotion launcher, and
19-bit experiment integrity/regression scripts check their dated pre-promotion
production manifests and will reject the current TC source. They are preserved
historical entry points. Use the `tc19_main_20261122` launcher above to check the
current source manifest without rewriting historical evidence.

## October 29, 2026 rerun

The commands and counts in this section document the October 29 run. The
scripts at these paths now select the current core and testbenches; rerunning
them produces current-contract results rather than the old dense timing/counts.

Run from the repository root, after restoring `tensor_core_sv/c_vectors.txt`:

```powershell
New-Item -ItemType Directory -Force build/portfolio-audit
vsim -version
vsim -c -l build/portfolio-audit/units.log -do integration_sv/sim/run_units.do
vsim -c -l build/portfolio-audit/top.log -do integration_sv/sim/run_top.do
```

The unit run completed successfully before starting integration. Both processes
returned exit code 0. All five unit PASS markers and the top PASS marker were
present, and no `** Error:` or `** Fatal:` appeared. There were six existing
`vlog-13314` port-kind warnings per suite (MLU, Bridge and MSU). The simulator
was ModelSim Intel FPGA Starter Edition 2020.1 / Simulator 2020.02, Windows.
In the audit environment it required execution outside the sandbox because
the 32-bit executable encountered DLL relocation failure inside the sandbox.

The convenience command `pwsh -NoProfile -File integration_sv/sim/run_regression.ps1`
invokes these same two `.do` scripts,
stores logs in `integration_sv/results/`, and checks exit status and markers.
The audit used separate log paths to preserve historical evidence.

See [full run evidence](../reports/verification/2026-10-29/README.md).

## Existing C models compiled during the October 29 audit

The additional `tools/run_c_tests.bat` launcher compiles the existing tests
separately with MSVC, retaining assertions and default random seeds. It writes
only build output under `build/c_reference/`. Compiler options:

```text
/nologo /W4 /O2 /std:c11 /TC /utf-8 /D_CRT_SECURE_NO_WARNINGS
```

Use a Visual Studio Developer Command Prompt, then run:

```bat
tools\run_c_tests.bat
```

`/D_CRT_SECURE_NO_WARNINGS` permits the existing portable C library calls;
`/utf-8` decodes the original source correctly. An initial launcher attempt
without `/utf-8` failed at DU/TIA compilation/linking under code page 950.
Adding the source-encoding option to the new launcher resolved it without
changing the reference. The failed attempt is preserved alongside the final
log to make this distinction explicit.

| C test | Fresh observation |
|---|---|
| TC, seed 20260915 | 6,389 checked tiles (1,290 dense / 5,099 sparse), 1,593,020 checked MACs |
| MLU | 120 tiles, 960 packets, 1,312 cycles |
| MSU | 120 results, 960 beats, 1,339 cycles |
| Bridge | Guard, 96-tile continuous, 96-tile stalled, and three reset/recovery cases pass |
| DU/TIA | 1,004 dense, 1,052 hybrid, 1,260 dual packets checked; malformed-input checks pass |
| Basic outer-product example | Directed matrix comparison and 1,000 random cases pass |

These totals are not to be added to the SV replay totals as independent design
coverage. The C test runs and the stored-vector replay are related evidence.
No vector regeneration or seed modification was performed.

## Legacy C and October integration benchmark interpretation

`tensor_core_sv/c_reference/tb_tensor_core.c::test_streaming` compares serial
and overlapped schedules using `STREAM_FULL`, 100 tiles, no gaps, ready output,
and identical seed. `run_stream` checks every matrix, every tile boundary,
publication latency, reservation count, and stage events. All 8 A and 8 B lanes
are populated at each of 8 k positions. The 51,200 MAC total equals
`100 * 8 * 8 * 8`.

Serial scheduling waits for a tile to be consumed before starting the next:
1,200 elapsed cycles. Overlap accepts starts 8 cycles apart and takes
`100*8 + 4 = 804` cycles including fill/final handshake. The printed utilization
is `MACs / (64 * cycles)`, giving 66.6667% and 99.5025%; the ratio is 1.4925x.
This is the sparse datapath processing full-count packets. It is not a sparse
network benchmark, a dense-vs-sparse algorithm speedup, or a power measurement.

The October connected-system TB independently observed 145 start intervals of 8 cycles
in its complete run; its unstalled 64-tile sparse phase takes 547 TB cycles,
including command/memory overhead and the test's final 12-cycle drain check.
Do not label that phase counter as pure compute latency or omit its setup/drain.

## Golden-vector distribution

The original TC vector file is 150,566,416 bytes. It remains untouched locally.
The proposed public snapshot stores `tensor_core_sv/c_vectors.txt.gz`, a gzip
copy of those exact bytes; use `tools/restore_vectors.ps1` to restore it.

Expected SHA-256 of restored bytes:

```text
95906db99b23a97fdf4580a768c481b861c2983f017742e513711dbee3d39935
```

The helper verifies the hash before installing the file and refuses to replace
an existing different file. Linux users can equivalently run:

```bash
gzip -dk tensor_core_sv/c_vectors.txt.gz
sha256sum tensor_core_sv/c_vectors.txt
```

The other three unit replay-vector files are preserved uncompressed. The
existing `generate_vectors.sh/.bat`, Bridge `run_tests.py --regenerate`, and
MSU tools generate replacement vectors; use a disposable copy when exploring
those flows. Historical Linux/Verilator/Icarus results remain historical.
No such simulator was installed or rerun for this audit.
