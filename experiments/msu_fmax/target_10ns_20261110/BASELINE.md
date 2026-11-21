# Baseline before the 10 ns experiment

The user requested a baseline commit followed by optimization directly on `main`,
without a new branch or worktree. The previous HEAD was
`1b52052d20fa242117fc9e0e2a0377cac44c88ac` (12 ns), while the working directory
already contained the promoted 11 ns implementation and documentation changes.
This snapshot preserves those existing changes before any 10 ns RTL edit.

All 11 active RTL/package files match the selected 11 ns `mlu_split_acc` manifest.
`baseline/src/` and `baseline/sources.csv` preserve the exact starting sources.
The pre-existing Vivado crash archive and empty scratch text file are retained
locally and excluded from this source/evidence commit. Generated DCPs remain
local under the existing ignore rules.

Fresh verification on 2026-11-10 (Asia/Taipei):

- Existing MSVC C reference suite: PASS (`baseline/c_tests.log`).
- MLU: 16,708 records, 145 resets, 128 rejected edges.
- DU/TIA: 3,292 packets.
- Bridge: 19,147 records, 7,156 rejected edges, 13 resets.
- TC: 136,136 records, 169 resets, 13 rejected edges; complete internal state,
  both result slots, payload and cycle events compared with immutable C vectors.
- MSU: 8,683 cycles, 676 accepted results, 5,394 write beats.
- Integration: 316 completed tiles, 3,124 issued packets, 2,563 write beats,
  75 resets; original seed `91e10da5`. All existing coverage counters match the
  previously promoted baseline.
- Existing protected-file hash manifest: PASS.

Commands executed from the repository root:

```powershell
& ./tools/restore_vectors.ps1
& ./experiments/msu_fmax/regress.ps1 -Trial target_10ns_20261110/baseline
cmd /c '"C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" && tools\run_c_tests.bat'
```

The preserved 11 ns recovery checkpoint is
`reports/implementation/recover_11ns_20261110/replicated/timing_closed.dcp`,
SHA-256 `93A4FDCA245A011C6BB308E2213C87E8DCF1716FED4F031F4C197A9E1C10ECEF`.
Its existing report gives setup WNS +0.005 ns, TNS 0, hold WHS +0.098 ns,
30,545 LUTs, 22,473 registers and 128 DSP48E1s. The critical path is Bridge
count[2] through FIFO payload gating and a sparse DSP into the MUL product
register: 10.986 ns data delay, including 6.339 ns routing.

Timing scope is Vivado 2022.2 OOC post-route on xc7z020clg484-1, speed file
1.12, setup at Slow Process Corner, both corners analyzed. This is not ASIC,
board-level timing sign-off, or measured power. The actual recovery report
lists 424 inputs and **593 outputs** without I/O delays; an older experiment
summary says 592 outputs and should not override this report.

The 10 ns target means a 100 MHz clock. Candidate changes must preserve ports,
packet layouts, cycle latency, strict valid behavior, error rollback, and all
existing references/tests. Results will be accepted only from completed routed
reports, with a separate source snapshot and regression for each RTL candidate.
