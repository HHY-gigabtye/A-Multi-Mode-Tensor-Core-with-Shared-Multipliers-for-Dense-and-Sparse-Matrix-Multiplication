param([string[]]$Trials=@('fixed_tdp','predecode','local_acc','combined','head_cache','head_cache_fast','early_prefetch','eligibility_factored','dense_acc_local','dense_acc_shared','grouped_mux','direct_guard','rotating_fifo','msu_addr_reduce'))
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$previous = Join-Path $repo 'experiments/mlu_bram_20261118'
$original = Import-Csv (Join-Path $previous 'baseline/sources_initial.csv')
foreach ($entry in $original) {
    foreach ($root in @($repo,(Join-Path $previous 'baseline/src'))) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $entry.Path)).Hash -ne $entry.SHA256) {
            throw "Original source changed: $root / $($entry.Path)"
        }
    }
}
$protected = Import-Csv (Join-Path $PSScriptRoot 'protected_initial.csv')
foreach ($entry in $protected) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256) {
        throw "Protected file changed: $($entry.Path)"
    }
}
$summaryPattern = '^# TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)'
$baselineSummary = @(Get-Content -LiteralPath (Join-Path $previous 'baseline/top.log') | Where-Object { $_ -match $summaryPattern })
if ($baselineSummary.Count -ne 46) { throw 'Unexpected baseline summary count' }
foreach ($trial in $Trials) {
    $trialRoot = Join-Path $PSScriptRoot $trial
    $changed = @()
    $manifest = Import-Csv (Join-Path $trialRoot 'sources.csv')
    if ($manifest.Count -ne $original.Count) { throw "Unexpected source count: $trial" }
    foreach ($entry in $manifest) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $trialRoot "src/$($entry.Path)")).Hash
        if ($actual -ne $entry.SHA256) { throw "Frozen snapshot changed: $trial / $($entry.Path)" }
        $before = $original | Where-Object { $_.Path.Replace('\','/') -eq $entry.Path.Replace('\','/') }
        if (!$before) { throw "Unknown source: $($entry.Path)" }
        if ($actual -ne $before.SHA256) { $changed += $entry.Path }
    }
    $units = Get-Content -Raw -LiteralPath (Join-Path $trialRoot 'units.log')
    $top = Get-Content -Raw -LiteralPath (Join-Path $trialRoot 'top.log')
    if (($units + $top) -match '\*\*\s+(Fatal|Error):') { throw "Simulation error: $trial" }
    foreach ($marker in @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:', 'BRIDGE RTL PASS:', 'ALL PASS C/SV:', 'MSU SV PASS:')) {
        if (!$units.Contains($marker)) { throw "Missing $marker in $trial" }
    }
    if (!$top.Contains('TOP INTEGRATION PASS:')) { throw "Missing integration PASS: $trial" }
    $summary = @($top -split '\r?\n' | Where-Object { $_ -match $summaryPattern })
    if (Compare-Object $baselineSummary $summary) { throw "Integration summary differs: $trial" }
    $mluHash = (Get-FileHash -LiteralPath (Join-Path $trialRoot 'src/mlu_sv/mlu.sv')).Hash
    $primitiveLog = $null
    foreach ($referenceTrial in @('fixed_tdp','head_cache','head_cache_fast','early_prefetch')) {
        $referenceRoot = Join-Path $PSScriptRoot $referenceTrial
        $referenceMlu = Join-Path $referenceRoot 'src/mlu_sv/mlu.sv'
        if (!(Test-Path -LiteralPath $referenceMlu)) { continue }
        if ((Get-FileHash -LiteralPath $referenceMlu).Hash -ne $mluHash) { continue }
        foreach ($relativeLog in @('equiv_netlist/result.log','flow/equiv_netlist/result.log')) {
            $candidateLog = Join-Path $referenceRoot $relativeLog
            if (Test-Path -LiteralPath $candidateLog) { $primitiveLog = $candidateLog; break }
        }
        if ($primitiveLog) { break }
    }
    if (!$primitiveLog) { throw "No primitive comparison for this exact MLU source: $trial" }
    $netlistResult = Get-Content -Raw -LiteralPath $primitiveLog
    if (!$netlistResult.Contains('MLU BRAM EQUIVALENCE PASS vectors=16708 steps=17171') -or $netlistResult -match 'Fatal:|Error:|\$fatal') {
        throw "Missing clean primitive equivalence PASS: $trial"
    }
    Write-Output "PASS ${trial}: frozen source hashes; five units; integration; 46 baseline summary lines identical."
    Write-Output "Changed RTL: $($changed -join ', ')"
    Write-Output "Matching MLU primitive comparison: $primitiveLog"
}
Write-Output "PASS $($original.Count) original sources and $($protected.Count) protected files unchanged."
