# Fresh GitHub clone verification of the 19-bit TC — 2026-11-22

## Result and tested revision

**PASS.** A new HTTPS clone of the public GitHub repository successfully ran
the README Section 10 general regression and standalone 19-bit equivalence /
signed-bound commands. Project inputs came from that checkout, including the
TC vectors restored from its published gzip file. No input was copied from the
original development working tree, and simulator libraries were built afresh.

| Item | Recorded value |
|---|---|
| Tested commit | `24b84dfa3754128bbf37ae8847c4b718ebc2b6fa` |
| Tested README Git blob | `ffd58c6be498891b200ca9d866433996a21800df` |
| Acquisition | HTTPS clone of `main`, `--depth 1 --single-branch` |
| Initial worktree | Clean; no Git object alternates |
| Environment | Windows, PowerShell 7.6.9, ModelSim Intel FPGA Edition 2020.1 |
| General / supplemental command exit codes | 0 / 0 |

The [tested README](https://github.com/HHY-gigabtye/A-Multi-Mode-Tensor-Core-with-Shared-Multipliers-for-Dense-and-Sparse-Matrix-Multiplication/blob/24b84dfa3754128bbf37ae8847c4b718ebc2b6fa/README.md#10-how-to-run-the-tests)
defines the commands under test. [Preflight](preflight.json) records the remote,
commit, README blob, tool path, and fresh temporary checkout at
`C:/Users/Jason/AppData/Local/Temp/tc19_github_check_20261122_171104156`.
The checkout was outside the original `C:/Users/Jason/Desktop/TC` workspace.
This record publishes the already completed run; assembling it did not rerun
simulation or change RTL, reference models, vectors, tests, seeds or assertions.

## Execution procedure

The acquisition command used a newly generated temporary destination:

```powershell
$cloneCheckRoot = Join-Path ([IO.Path]::GetTempPath()) ('tc19_github_check_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
git clone --depth 1 --single-branch --branch main https://github.com/HHY-gigabtye/A-Multi-Mode-Tensor-Core-with-Shared-Multipliers-for-Dense-and-Sparse-Matrix-Multiplication.git $cloneCheckRoot
```

The two tested code blocks were extracted from the cloned README and executed
with PowerShell 7, with the working directory set to the clone root. Before each
block, the process-local `STC_ROOT`, `TC19_MAIN_OUTPUT`, and `MODELSIM` environment
variables were cleared so inherited settings could not select the old workspace.
ModelSim ran natively outside the execution sandbox, using the installed tool
on `PATH`.

The [general command excerpt](general-command.ps1) first restored the vectors,
then ran the original isolated units, the TC comparison, and integration:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
pwsh -NoProfile -File integration_sv/sim/run_regression.ps1
```

The [supplemental command excerpt](supplemental-command.ps1) then ran the exact
standalone block from the tested README. It set both environment paths to the
new checkout, created a fresh `build/tc19_extra_<timestamp>/` directory, invoked
`reports/verification/tc19_main_20261122/extra.do`, checked the simulator exit
code and both PASS markers, and restored the environment variables. These
`.ps1` files are archived command excerpts, not new test implementations.

For a later reproduction after `main` advances, pin the checkout to the tested
revision before executing the code blocks in that revision's README:

```powershell
git fetch --depth 1 origin 24b84dfa3754128bbf37ae8847c4b718ebc2b6fa
git checkout --detach 24b84dfa3754128bbf37ae8847c4b718ebc2b6fa
```

The repository already shipped historical `integration_sv/results/units.log`
and `top.log`. They were copied aside before the general command wrote fresh
logs at those default paths. The preserved [published units](published_units.log)
and [published top](published_top.log) are historical comparisons and are not
counted as results of this run.

## Observed results

| Check | Result from the fresh run |
|---|---|
| TC vector restoration | PASS; SHA-256 `95906DB99B23A97FDF4580A768C481B861C2983F017742E513711DBEE3D39935` |
| MLU | PASS; 16,708 C/SV records, 145 resets, 128 rejected edges |
| DU/TIA | PASS; 3,292 packets |
| Bridge | PASS; 19,147 C-equivalent rows, 7,156 rejected edges, 13 resets |
| TC compatible C replay | PASS; 21,032 records, 1,366 publications, 6 malformed offers, 1 full-credit rejection |
| TC comparison, 24 tiles | PASS; predecessor/shared cycles: dense 576/196, full-count indexed 196/196, alternating 432/196 |
| MSU | PASS; 8,683 cycles, 676 accepts, 5,394 write beats, 673 completions, 42 faults, 8 resets |
| Connected integration | PASS; 369 completed tiles, 3,542 issued packets, 2,987 write beats, 77 resets |
| Unstalled dense / mixed | PASS; 24 / 27 tiles, 23 / 26 II=8 intervals, k=7+3 publication |
| Integration summaries | All 50 lines match the accepted public baseline |
| 19-bit / 32-bit equivalence | PASS; 89,595 edges, all 65,536 A/B bitmap pairs, 10,080 completed results, 178 resets |
| Signed bounds | PASS; all 65,536 signed INT8 operand pairs over 1,024 tiles, endpoints -130048 and +131072 |
| Bounds timing | PASS; 1,023 II=8 intervals and k=7+3 publication |

The fresh [unit log](units.log), [integration log](top.log), and
[supplemental log](extra.log) contain the simulator results. Both supplemental
summary lines also match the accepted public summaries. No simulator Error or
Fatal entries were found; the existing `vlog-13314` port-kind warnings remain.
The [general console](general-console.log) records vector restoration and the
overall regression PASS; the [supplemental console](supplemental-console.log)
records execution of the standalone command and its PASS checks.

## Input provenance and isolation checks

- The initial checkout had no expanded root TC vectors or compiled integration
  libraries. Root vectors were generated only by the checked-in restoration
  script from `tensor_core_sv/c_vectors.txt.gz`, with the SHA-256 above.
- [Source inputs](source-inputs.json) enumerate 28 unique RTL, package, testbench,
  reference and vector paths: 27 tracked files and the restored TC vector file.
- [General runtime paths](general-runtime-inputs.json) record 33 absolute source
  compilation paths and four vector reads, all inside the fresh checkout.
- [Supplemental runtime paths](supplemental-runtime-inputs.json) record four
  absolute source compilation paths inside the checkout. The additional generated
  baseline adapter matched the public 32-bit snapshot after only the module-name
  substitution performed by `extra.do`; line endings were normalized for that
  content comparison.
- Neither fresh simulator log set contained an input path under the original
  development workspace. Only the two default generated unit/integration logs
  changed among the clone's tracked files; source and test files remained intact.
- Two unrelated historical DCP files were already tracked in the public repository;
  their paths are recorded in preflight. Their presence does not establish a
  dependency: these RTL test commands did not open or use them.

The evidence consists of the fresh checkout state, inspected launcher/test
inputs, and simulator command paths. It is not an operating-system file-access
trace or a test on a clean virtual machine. Installed PowerShell and ModelSim
remain external prerequisites; no unpublished project artifact was needed by
the tested commands.

## Scope and limitations

This run validates the general SV regression and the standalone supplemental
block in README Section 10 on the recorded Windows tool installation. It does
not rerun C executables, optional vector regeneration, other simulators,
synthesis, placement/routing, netlist simulation or power estimation. No new
PPA result is claimed.

The separate archived full-promotion launcher
`reports/verification/tc19_main_20261122/run_regression.ps1` was not used.
As documented in the README, that launcher checks preservation manifests that
include local Vivado checkpoints/netlists and expanded snapshot vectors. A fresh
GitHub clone should use the general and standalone supplemental commands tested
here. The [19-bit promotion record](../tc19_main_20261122/README.md) retains the
broader historical functional and implementation evidence.

## Evidence preservation and published changes

[PASS.txt](PASS.txt) and [validation.json](validation.json) summarize the run.
[top_summary.txt](top_summary.txt) and [extra_summary.txt](extra_summary.txt)
retain the 50 integration lines and two supplemental lines used for comparison.
[evidence_hashes.csv](evidence_hashes.csv) contains the original SHA-256 values
for all 17 evidence files; it excludes itself and the subsequently authored
README and `.gitattributes`. All 18 archived files, including that manifest,
were copied byte-for-byte from the completed local validation archive and
rechecked during publication. Directory-local attributes preserve the evidence
bytes across Git checkouts.

This publication changes the root README only to add the Section 10 link and
adds this directory: the report, evidence attributes, and the 18 archived files.
The report is bound to tested commit `24b84df`, rather than implying that the
later documentation commit was the revision cloned for the recorded run.
