# Native implementation publication — November 13, 2026

> Historical publication scope: references below to current implementation or
> main describe November 13. The active main working tree now contains operand
> routing before multiplication and the DU/TIA whole-union assignment repair;
> see the [November 22 promotion and verification](../operand_route_main_20261122/README.md).
> This publication's measurements, source history, and validation remain unchanged.

This publication integrates local TC `dad7b14` and the user's pending root
README changes into GitHub main, based on `e8986e71154eff23cfea7e00004cdcfceb69c529`.
The source was copied into an isolated publication directory. The original
working tree, pending README edit, local history, and scratch files were preserved.
No production RTL, C reference, existing test, seed, assertion, or golden vector
was changed. The active RTL already matched the previous public version.

## Published update and cleanup

- Publish the November 13 physical margin experiment and fresh native rebuild,
  their source snapshots, measured text reports, and reproducible flow inputs.
- Update the active Vivado project and physical flow to the verified native
  margin implementation; retain the latest local README results and caveats.
- Preserve the remote English module READMEs, architecture images, and historical
  corrections that were missing from the local checkout.
- Remove superseded `reports/implementation/` reports and the earlier
  `reports/verification/2026-11-13-publication/` packaging record from main.
  They remain recoverable in the parent Git commit. Current implementation
  evidence lives under `experiments/msu_fmax/native_margin_10ns_20261113/`.
- Retain dated experiment snapshots that establish provenance. Exclude old
  alternate README filenames, generated run trees, checkpoints, crash/scratch
  files, private literature/meeting material, and the raw 150 MB TC vector file.
  The byte-identical gzip distribution remains available.

See [the changed-file manifest](changed-files.tsv) for every published addition,
modification, and deletion relative to the parent, excluding the manifest itself.

## Executed validation

Commands, run from the isolated publication root with PowerShell 7 and ModelSim
Intel FPGA Edition 2020.1 / Simulator 2020.02:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1
```

Vector restoration verified the expected SHA-256. The existing launcher ran
all five units before integration and returned exit code 0. All six required
PASS markers were present, with no Error/Fatal diagnostics. Each suite retained
six existing port-kind warnings. The sandboxed simulator launch failed with
a Windows DLL relocation error; the successful run used approved execution
outside the sandbox. No test or reference was changed to accommodate execution.

| Suite | Observed result |
| --- | --- |
| MLU | 16,708 records; 145 resets; 128 expected rejected edges |
| DU/TIA | 3,292 checked packets |
| Bridge | 19,147 records; 7,156 expected rejected edges; 13 resets |
| TC | 136,136 records; 169 resets; 13 expected RTL rejection cases |
| MSU | 8,683 cycles; 676 accepted results; 5,394 beats; 673 completed tiles; 8 resets |
| Integration | 316 completed tiles; 3,124 packets; 2,563 write beats; 75 resets; seed `91e10da5` |

See [unit log](units.log) and [integration log](top.log). SHA-256 checks matched
all 11 live RTL/package files, 76 protected reference/test/vector files, and 10
physical-flow inputs against the native rebuild's recorded manifests.

All Markdown relative links resolve in the publication tree, including the two
preserved remote images. All 18 active XPR File references resolve. A targeted
scan found no credential filenames or high-confidence private-key/token patterns
in the selected files. Excluded local material was not copied into this tree.

This publication did not recompile standalone C or rerun synthesis/place/route.
The published 100 MHz result is the separately recorded November 13 fresh
native FPGA OOC post-route build: WNS +0.016 ns, WHS +0.096 ns, TNS/THS zero.
It is internal timing analysis with incomplete external I/O constraints, not
board-level timing sign-off or measured hardware maximum frequency.
