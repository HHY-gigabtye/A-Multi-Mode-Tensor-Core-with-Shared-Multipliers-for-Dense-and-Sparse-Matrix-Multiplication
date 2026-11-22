param([ValidateSet('candidate','candidate_v2')][string]$Variant = 'candidate_v2')
$ErrorActionPreference = 'Stop'
$trial = $PSScriptRoot
$production = (Resolve-Path (Join-Path $trial '../..')).Path
$entries = @(Import-Csv (Join-Path $trial 'baseline_manifest.csv')) + @(Import-Csv (Join-Path $trial 'extra_manifest.csv'))
$rows = foreach ($entry in $entries) {
    $productionHash = (Get-FileHash -LiteralPath (Join-Path $production $entry.Path)).Hash
    $baselineHash = (Get-FileHash -LiteralPath (Join-Path $trial "baseline/src/$($entry.Path)")).Hash
    $candidateHash = (Get-FileHash -LiteralPath (Join-Path $trial "$Variant/src/$($entry.Path)")).Hash
    if ($productionHash -ne $entry.SHA256 -or $baselineHash -ne $entry.SHA256) {
        throw "Production/baseline changed: $($entry.Path)"
    }
    $changed = $candidateHash -ne $entry.SHA256
    if ($changed -and $entry.Path -ne 'tensor_core_sv/outer_product_core.sv') {
        throw "Unexpected candidate change: $($entry.Path)"
    }
    [pscustomobject]@{
        Path = $entry.Path
        CandidateVariant = $Variant
        ProductionSHA256 = $productionHash
        BaselineSHA256 = $baselineHash
        CandidateSHA256 = $candidateHash
        CandidateChanged = $changed
    }
}
if (@($rows | Where-Object CandidateChanged).Count -ne 1) { throw 'Expected exactly one RTL change' }
$rows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $trial 'source_integrity.csv')
$message = "PASS: $($rows.Count) production and baseline files unchanged; candidate changes only outer_product_core.sv."
$message | Set-Content -LiteralPath (Join-Path $trial 'integrity.PASS.txt')
Write-Output $message
