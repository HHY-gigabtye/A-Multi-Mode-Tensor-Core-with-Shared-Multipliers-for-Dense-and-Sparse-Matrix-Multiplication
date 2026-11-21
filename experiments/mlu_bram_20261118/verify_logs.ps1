$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check_integrity.ps1')
$markers = @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:', 'BRIDGE RTL PASS:', 'ALL PASS C/SV:', 'MSU SV PASS:')
foreach ($trial in @('baseline','banked')) {
    $units = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "$trial/units.log")
    $top = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "$trial/top.log")
    if ($units -match '\*\*\s+(Fatal|Error):' -or $top -match '\*\*\s+(Fatal|Error):') {
        throw "Simulator failure in $trial logs"
    }
    foreach ($marker in $markers) {
        if (!$units.Contains($marker)) { throw "Missing $trial marker: $marker" }
    }
    if (!$top.Contains('TOP INTEGRATION PASS:')) { throw "Missing $trial integration PASS" }
}
$pattern = '^# TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)'
$before = @(Select-String -LiteralPath (Join-Path $PSScriptRoot 'baseline/top.log') -Pattern $pattern | ForEach-Object Line)
$after = @(Select-String -LiteralPath (Join-Path $PSScriptRoot 'banked/top.log') -Pattern $pattern | ForEach-Object Line)
if (!$before.Count -or ($before -join "`n") -cne ($after -join "`n")) {
    throw 'Baseline/candidate integration summaries differ'
}
foreach ($test in @('equiv_rtl','equiv_netlist_5')) {
    $log = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "banked/$test/result.log")
    if ($log -notmatch 'MLU BRAM EQUIVALENCE PASS vectors=16708 steps=17171 directed_transitions=18 simultaneous_last=234 stalls=5347 resets=155') {
        throw "Missing supplemental equivalence PASS: $test"
    }
    if ($log -match '(?im)^\s*(Fatal|Error):') { throw "Supplemental simulation error: $test" }
}
Write-Output "PASS log audit: five units and integration for both snapshots; $($before.Count) identical integration summary/coverage lines; RTL and RAM primitive cycle comparisons passed."
