param(
    [Parameter(Mandatory=$true)][string]$SelectedTrial,
    [Parameter(Mandatory=$true)][string]$SelectedRun,
    [string]$OriginalRoot = 'C:/Users/Jason/Desktop/TC',
    [switch]$Promoted
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repoRoot
try {
    foreach ($trial in @('baseline', 'result_local')) {
        & "$PSScriptRoot/check_regression.ps1" -Trial $trial
        foreach ($row in (Import-Csv "$PSScriptRoot/$trial/sources.csv")) {
            if ((Get-FileHash "$PSScriptRoot/$trial/src/$($row.Path)").Hash -ne $row.SHA256) {
                throw "Changed source snapshot: $trial $($row.Path)"
            }
            if ($trial -eq $SelectedTrial -and (Get-FileHash $row.Path).Hash -ne $row.SHA256) {
                throw "Live worktree differs from selected source: $($row.Path)"
            }
            if (!$Promoted -and $trial -eq 'baseline' -and
                (Get-FileHash (Join-Path $OriginalRoot $row.Path)).Hash -ne $row.SHA256) {
                throw "Original stable RTL changed: $($row.Path)"
            }
        }
    }
    foreach ($row in (Import-Csv "$PSScriptRoot/original_files.csv")) {
        # Promotion intentionally replaces this RTL; the selected-source check
        # above verifies it. The pre-promotion source remains in baseline/src.
        if ($Promoted -and $row.Path -eq 'tensor_core_sv/tensor_core.sv') { continue }
        if ((Get-FileHash (Join-Path $OriginalRoot $row.Path)).Hash -ne $row.SHA256) {
            throw "Original project/user file changed: $($row.Path)"
        }
    }
    foreach ($row in (Import-Csv "$PSScriptRoot/protected.csv")) {
        if ((Get-FileHash (Join-Path $OriginalRoot $row.Path)).Hash -ne $row.SHA256) {
            throw "Original protected input changed: $($row.Path)"
        }
    }
    foreach ($manifest in @('refine_input.csv', 'selected_checkpoint.csv')) {
        foreach ($row in (Import-Csv "$PSScriptRoot/$manifest")) {
            if ((Get-FileHash -LiteralPath $row.Path).Hash -ne $row.SHA256) {
                throw "Checkpoint changed: $($row.Path)"
            }
        }
    }
    $selected = @(Import-Csv "$PSScriptRoot/comparison.csv" | Where-Object Trial -eq $SelectedRun)
    if ($selected.Count -ne 1 -or [double]$selected[0].WNS_ns -lt 0 -or
        [double]$selected[0].WHS_ns -lt 0 -or [int]$selected[0].Routing_errors -ne 0) {
        throw 'Selected route does not pass timing/routing'
    }
    $check = Get-Content -Raw "$PSScriptRoot/selected_validation/clock_check.txt"
    $period = [double]$selected[0].Period_ns
    $checkPeriod = [double]([regex]::Match($check, 'Clock period: ([\d.]+)').Groups[1].Value)
    $checkSetup = [double]([regex]::Match($check, 'Setup slack: ([-\d.]+)').Groups[1].Value)
    $checkHold = [double]([regex]::Match($check, 'Hold slack: ([-\d.]+)').Groups[1].Value)
    if ($checkPeriod -ne $period -or $checkSetup -ne [double]$selected[0].WNS_ns -or
        $checkHold -ne [double]$selected[0].WHS_ns) { throw 'Independent STA differs' }
    $dsp = @(Import-Csv "$PSScriptRoot/selected_validation/dsp_registers.csv")
    if ($dsp.Count -ne 128 -or @($dsp | Where-Object {
        $_.AREG -ne '0' -or $_.BREG -ne '0' -or $_.MREG -ne '0' -or $_.PREG -ne '0'
    }).Count -ne 0) { throw 'Unexpected DSP registers' }
    git diff --check -- tensor_core_sv/tensor_core.sv
    if ($LASTEXITCODE -ne 0) { throw 'Whitespace check failed' }
    @(
        'PASS: baseline and candidate original five-unit and integration regressions.',
        'PASS: immutable source snapshots and protected models/vectors/tests retain hashes.',
        'PASS: refinement input and selected routed checkpoint hashes unchanged.',
        'PASS: live RTL matches selected source; original Vivado user project edits unchanged.',
        "PASS: selected $SelectedRun is post-route, period=$period ns, setup=$checkSetup ns, hold=$checkHold ns, zero routing errors.",
        'PASS: independent checkpoint STA reproduces results; all 128 DSPs have AREG/BREG/MREG/PREG=0.',
        'LIMIT: OOC internal timing only; no board timing, hardware frequency, power, or formal-equivalence claim.'
    ) | Set-Content -Encoding utf8 "$PSScriptRoot/final_validation.txt"
    Get-Content "$PSScriptRoot/final_validation.txt"
} finally { Pop-Location }
