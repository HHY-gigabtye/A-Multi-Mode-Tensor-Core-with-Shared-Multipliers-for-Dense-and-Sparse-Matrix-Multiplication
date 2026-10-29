# Public snapshot packaging verification

The public candidate is a file copy with the original module-relative layout.
No Git repository was initialized in that copy and no push was performed.
This verification checks packaging/paths; it does not introduce new test cases.

The 150,566,416-byte TC replay file is distributed as a 4,541,458-byte gzip.
Restoration with the existing PowerShell 7.6.5 runtime succeeded and matched
SHA-256 `95906db99b23a97fdf4580a768c481b861c2983f017742e513711dbee3d39935`.
Running restoration again verified the existing file without overwriting it.

From the candidate root, the successful commands were:

```powershell
pwsh -NoProfile -File tools/restore_vectors.ps1
vsim -c -l ../portfolio-audit/candidate_units_restored.log -do integration_sv/sim/run_units.do
vsim -c -l ../portfolio-audit/candidate_top.log -do integration_sv/sim/run_top.do
```

The unit and top simulations returned exit 0 and reproduced the October 29
PASS counts. All five unit markers and the top marker were checked, along with
absence of `** Error:` / `** Fatal:`. Six existing port-kind compile warnings
remain per suite. Restoring a vector does not regenerate or alter expected data.

An initial attempt to launch restoration using Windows PowerShell 5.1 was
blocked by that shell's execution policy. A subsequent unit invocation reached
TC without its vector and emitted `** Fatal: Cannot open ... c_vectors.txt`.
That attempt is retained as `initial_missing_vector.log` and is **not a pass**,
even though the legacy `.do` script ultimately returned exit 0. The existing
PowerShell regression wrapper checks fatal/error text and PASS markers, which
is why the root README recommends it rather than exit code alone.

The recovery used the already available PowerShell 7 (local-machine policy
RemoteSigned); no policy was changed and no tool was installed. The completed
unit rerun after restoration is `units_restored.log`; the top run is `top.log`.
Workspace prefixes in these public log copies are replaced with `<repo>`.
