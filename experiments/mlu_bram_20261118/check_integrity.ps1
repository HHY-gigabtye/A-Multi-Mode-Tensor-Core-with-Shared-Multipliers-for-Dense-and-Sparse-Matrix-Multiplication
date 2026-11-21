$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$initial = Import-Csv (Join-Path $PSScriptRoot 'baseline/sources_initial.csv')
foreach ($entry in $initial) {
    foreach ($root in @($repo,(Join-Path $PSScriptRoot 'baseline/src'))) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $entry.Path)).Hash -ne $entry.SHA256) {
            throw "Original source changed: $root / $($entry.Path)"
        }
    }
}
$changed = @()
foreach ($entry in (Import-Csv (Join-Path $PSScriptRoot 'banked/sources.csv'))) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "banked/src/$($entry.Path)")).Hash
    if ($actual -ne $entry.SHA256) { throw "Candidate differs from tested snapshot: $($entry.Path)" }
    $before = $initial | Where-Object Path -eq $entry.Path
    if ($actual -ne $before.SHA256) { $changed += $entry.Path }
}
if ($changed.Count -ne 1 -or $changed[0].Replace('\','/') -ne 'mlu_sv/mlu.sv') {
    throw "Unexpected source change scope: $changed"
}
$protected = Import-Csv (Join-Path $PSScriptRoot 'protected_initial.csv')
foreach ($entry in $protected) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256) {
        throw "Protected file changed: $($entry.Path)"
    }
}
Write-Output "PASS integrity: $($initial.Count) main/baseline sources unchanged; only candidate MLU differs; $($protected.Count) protected files unchanged."
