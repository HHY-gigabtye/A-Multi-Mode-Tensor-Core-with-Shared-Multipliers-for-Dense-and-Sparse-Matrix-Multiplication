# Publication validation — November 13, 2026

The public snapshot was assembled from local TC commit `f6ee5f1` and its existing
Vivado project edit, on top of GitHub `fe14c132af8e319af2e806e6758d2010341c1bf6`.
The local working tree and its pending files were preserved. No production RTL,
C reference, existing test, seed or expected vector was edited by this publication.
All 795 selected non-Markdown/non-ignore files matched the local input bytes.

## Validation

Run from the isolated publication root, using ModelSim Intel FPGA Edition 2020.1:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
New-Item -ItemType Directory -Force build
vsim -c -l build/github-sync-units.log -do integration_sv/sim/run_units.do
vsim -c -l build/github-sync-top.log -do integration_sv/sim/run_top.do
```

Vector restoration verified SHA-256. Units completed before integration. Both
simulator commands returned exit code 0, all six PASS markers were present,
and no Error/Fatal diagnostics occurred. Each suite retained six existing
port-kind warnings. Execution required leaving the sandbox because the 32-bit
simulator failed DLL relocation inside it. An initial attempt also lacked the
log directory; it was created before the successful commands above.

| Suite | Observed result |
| --- | --- |
| MLU | 16,708 records; 145 resets; 128 expected rejected edges |
| DU/TIA | 3,292 packets |
| Bridge | 19,147 records; 7,156 rejected edges; 13 resets |
| TC | 136,136 records; 169 resets; 13 RTL rejection cases |
| MSU | 8,683 cycles; 676 accepted results; 5,394 beats; 673 completed tiles |
| Integration | 316 completed tiles; 3,124 packets; 2,563 beats; 75 resets; seed 91e10da5 |

See [unit log](units.log) and [integration log](top.log). Standalone C compilation
and new synthesis/place/route were not run in this publication. The 10 ns PPA
values remain the November 12 FPGA OOC post-route measurements, with the
limitations stated in the [root README](../../../README.md).

## Publication cleanup

- Remove the obsolete standalone `project_1` XPR and constraint from main.
- Include the existing local removal of native 10.25 ns retry runs from the XPR.
- Publish six module/reference README files under language-neutral English names.
- Audit all 18 published README files as English; correct current entry points,
  mark superseded experiment documents and distinguish historical local commit IDs.
- Keep existing public diagrams and historical implementation evidence.
- Keep dated 10 ns experiment snapshots and reports for provenance.
- Exclude generated binaries, crash/scratch files, private literature/meeting
  materials and the raw TC vector file; retain its identical gzip distribution.

All Markdown relative links and all 18 XPR File references resolve in the
published source set. Historical commands inside archived experiment records
may refer to retired checkpoints or local-only commits; current build commands
are in the root README. GitHub history is preserved by a normal child commit.

[Changed-file manifest](changed-files.tsv) lists additions, modifications and
removals relative to the previous GitHub main, excluding this manifest itself.
