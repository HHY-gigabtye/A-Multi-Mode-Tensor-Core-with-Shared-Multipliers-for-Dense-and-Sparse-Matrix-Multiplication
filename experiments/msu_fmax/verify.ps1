param(
    [Parameter(Mandatory=$true)][string]$Trial,
    [Parameter(Mandatory=$true)][string]$Run
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Join-Path $PSScriptRoot 'check_regression.ps1') -Trial baseline
if ($Trial -ne 'baseline') { & (Join-Path $PSScriptRoot 'check_regression.ps1') -Trial $Trial }
foreach ($entry in (Import-Csv (Join-Path $PSScriptRoot "$Trial/sources.csv"))) {
    $live = Join-Path $repo $entry.Path
    $snapshot = Join-Path $PSScriptRoot "$Trial/src/$($entry.Path)"
    if ((Get-FileHash -LiteralPath $live).Hash -ne $entry.SHA256 -or
        (Get-FileHash -LiteralPath $snapshot).Hash -ne $entry.SHA256) {
        throw "Selected source mismatch: $($entry.Path)"
    }
}
foreach ($entry in (Import-Csv (Join-Path $PSScriptRoot 'current_project.csv'))) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256) {
        throw "Promoted project file changed: $($entry.Path)"
    }
}
$backupRoot = Join-Path $repo '.local-backups/consolidate-main-12ns-20261108/original-local'
$backupStatus = 'Pre-promotion local backup is absent; historical original_project.csv retained.'
if (Test-Path -LiteralPath $backupRoot) {
    foreach ($entry in (Import-Csv (Join-Path $PSScriptRoot 'original_project.csv'))) {
        $relative = $entry.Path.Replace('\','/') -replace '^.*/TC/',''
        if (!$relative.StartsWith('project_integration/')) {throw 'Unexpected original project path'}
        if ((Get-FileHash -LiteralPath (Join-Path $backupRoot $relative)).Hash -ne $entry.Hash) {
            throw "Pre-promotion project backup changed: $relative"
        }
    }
    $backupStatus = 'PASS: pre-promotion XPR/XDC backup hashes match original_project.csv.'
}
$baseline = Get-Content (Join-Path $PSScriptRoot 'baseline/top.log') | Where-Object {$_ -match '^# TOP (COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)'}
$candidate = Get-Content (Join-Path $PSScriptRoot "$Trial/top.log") | Where-Object {$_ -match '^# TOP (COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)'}
if (Compare-Object $baseline $candidate) { throw 'Integration coverage counters changed' }
& (Join-Path $PSScriptRoot 'summarize.ps1')
$selected = Import-Csv (Join-Path $PSScriptRoot 'comparison.csv') | Where-Object Run -eq $Run
if (!$selected -or [double]$selected.WNS_ns -lt 0 -or [double]$selected.WHS_ns -lt 0 -or [int]$selected.RoutingErrors -ne 0) {
    throw "Selected implementation does not pass: $Run"
}
$checkpoint = Join-Path $PSScriptRoot "$Run/routed.dcp"
$inspectionDir = Join-Path $repo 'reports/implementation/main_12ns/checkpoint_inspection'
$audit = Get-Content -Raw (Join-Path $inspectionDir 'audit.txt')
$inspectedCheckpoint = [regex]::Match($audit, '(?m)^Checkpoint: (.+)\r?$').Groups[1].Value.Trim()
$checkpointRecord = @(Import-Csv (Join-Path $PSScriptRoot 'selected_checkpoint.csv'))
$checkpointHash = Get-FileHash -LiteralPath $checkpoint
$expectedSuffix = "/experiments/msu_fmax/$Run/routed.dcp"
# Historical inspection logs retain their original absolute path after a move.
# Require the same relative run and the previously recorded checkpoint content.
if ($checkpointRecord.Count -ne 1 -or
    $checkpointRecord[0].Algorithm -ne 'SHA256' -or
    $checkpointRecord[0].Hash -ne $checkpointHash.Hash) {
    throw 'Selected checkpoint content differs from its recorded SHA256'
}
if (!$inspectedCheckpoint -or
    !$inspectedCheckpoint.Replace('\','/').EndsWith($expectedSuffix, [StringComparison]::OrdinalIgnoreCase) -or
    !$checkpointRecord[0].Path.Replace('\','/').EndsWith($expectedSuffix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Independent inspection used a different checkpoint'
}
$clockReport = Get-Content -Raw (Join-Path $inspectionDir 'clocks.rpt')
if ($clockReport -notmatch '(?m)^clk\s+12\.000\s+') {throw 'Independent clock period is not 12 ns'}
$inspectedSetup = [regex]::Match($audit, 'Setup slack ns: ([\d.-]+)')
$inspectedHold = [regex]::Match($audit, 'Hold slack ns: ([\d.-]+)')
if (!$inspectedSetup.Success -or !$inspectedHold.Success -or
    [double]$inspectedSetup.Groups[1].Value -ne [double]$selected.WNS_ns -or
    [double]$inspectedHold.Groups[1].Value -ne [double]$selected.WHS_ns) {
    throw 'Independent STA does not match selected result'
}
foreach ($property in @('AREG','BREG','MREG','PREG')) {
    if ($audit -notmatch ('(?m)^{0} values: 0\r?$' -f $property)) {throw "DSP register configuration changed: $property"}
}
if ($audit -notmatch '(?m)^DSP48E1 count: 128\r?$') {throw 'Unexpected DSP count'}
$drc = Get-Content -Raw (Join-Path $PSScriptRoot "$Run/drc_routed.rpt")
if ($drc -match '\|\s*(Error|Critical Warning)\s*\|') {throw 'DRC error or critical warning'}
$checkpointHash | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot 'selected_checkpoint.csv')
@(
    "Selected trial: $Trial",
    "Selected run: $Run",
    'PASS: baseline and selected functional regressions; protected reference/test hashes.',
    'PASS: selected live RTL equals immutable implementation source snapshot.',
    'PASS: promoted 12 ns project/configuration hashes match current_project.csv.',
    $backupStatus,
    'PASS: integration coverage counters equal baseline.',
    "PASS: post-route setup $($selected.WNS_ns) ns; hold $($selected.WHS_ns) ns; zero routing errors.",
    'PASS: independent checkpoint re-open confirms 12 ns and reproduces setup/hold; 128 DSPs with AREG/BREG/MREG/PREG=0.',
    'PASS: routed DRC has no Error or Critical Warning entries; existing warnings retained.',
    'The active RTL is unchanged; project settings and implementation evidence are promoted to main.'
) | Set-Content (Join-Path $PSScriptRoot 'final_validation.txt')
Get-Content (Join-Path $PSScriptRoot 'final_validation.txt')
