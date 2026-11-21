$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$manifest = Import-Csv (Join-Path $repo 'experiments/msu_fmax/native_margin_10ns_20261113/sources.csv')
foreach ($trial in @('baseline', 'banked')) {
    $destinationRoot = Join-Path $PSScriptRoot "$trial/src"
    if (Test-Path -LiteralPath $destinationRoot) { throw "Snapshot already exists: $destinationRoot" }
    $records = foreach ($entry in $manifest) {
        $source = Join-Path $repo $entry.Path
        $destination = Join-Path $destinationRoot $entry.Path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        [pscustomobject]@{Path=$entry.Path; SHA256=(Get-FileHash -LiteralPath $destination).Hash}
    }
    $records | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot "$trial/sources_initial.csv")
}
git -C $repo rev-parse HEAD | Set-Content (Join-Path $PSScriptRoot 'base_commit.txt')
git -C $repo status --short | Set-Content (Join-Path $PSScriptRoot 'initial_status.txt')
$protected = foreach ($entry in (Import-Csv (Join-Path $repo 'experiments/msu_fmax/protected.csv'))) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash
    if ($actual -ne $entry.SHA256) { throw "Protected file differs: $($entry.Path)" }
    [pscustomobject]@{Path=$entry.Path; SHA256=$actual}
}
$protected | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot 'protected_initial.csv')
Write-Output "Prepared baseline and candidate snapshots; $($manifest.Count) sources and $($protected.Count) protected files verified."
