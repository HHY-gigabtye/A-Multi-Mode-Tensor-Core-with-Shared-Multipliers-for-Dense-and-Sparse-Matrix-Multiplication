param([Parameter(Mandatory=$true)][string]$Trial, [switch]$UnitsOnly)
$ErrorActionPreference = 'Stop'
$trialDir = Join-Path $PSScriptRoot $Trial
$markers = @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:',
    'BRIDGE RTL PASS:', 'ALL PASS C/SV:', 'MSU SV PASS:')
$unitText = Get-Content -Raw (Join-Path $trialDir 'units.log')
foreach ($marker in $markers) {
    if (!$unitText.Contains($marker)) { throw "Missing unit PASS: $marker" }
}
if ($unitText -match '\*\*\s+(Fatal|Error):') { throw 'Unit simulator error' }
if (!$UnitsOnly) {
    $topText = Get-Content -Raw (Join-Path $trialDir 'top.log')
    if (!$topText.Contains('TOP INTEGRATION PASS:') -or $topText -match '\*\*\s+(Fatal|Error):') {
        throw 'Integration did not pass'
    }
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
foreach ($row in (Import-Csv (Join-Path $PSScriptRoot 'protected.csv'))) {
    if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $row.Path)).Hash -ne $row.SHA256) {
        throw "Protected file changed: $($row.Path)"
    }
}
Write-Output "PASS: $Trial regression markers and protected file hashes."
