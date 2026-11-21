param(
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$Vsim = 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$record = Join-Path $repo 'reports/verification/outer_main_20261121'
$manifest = Import-Csv -LiteralPath (Join-Path $record 'main_manifest.csv')
function Assert-SourceIntegrity {
    foreach ($entry in $manifest) {
        if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256) {
            throw "Source/reference differs from the verified version: $($entry.Path)"
        }
    }
}

Assert-SourceIntegrity
$output = [IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $output) { throw "Choose a new verification directory: $output" }
& (Join-Path $repo 'integration_sv/sim/run_regression.ps1') -Vsim $Vsim -OutputDir $output
Assert-SourceIntegrity

$pattern = '^# (TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)|UNSTALLED (DENSE|MIXED) PASS)'
$expected = @(Get-Content -LiteralPath (Join-Path $record 'expected_top_summary.txt'))
$actual = @(Get-Content -LiteralPath (Join-Path $output 'top.log') | Where-Object { $_ -match $pattern })
if (!$expected.Count -or ($expected -join "`n") -cne ($actual -join "`n")) {
    throw 'Integration summary differs from the accepted outer-product run'
}
$actual | Set-Content -LiteralPath (Join-Path $output 'integration_summary.txt')
$message = "PASS: unit suites, old/new comparison, integration, $($actual.Count) matching summary lines, $($manifest.Count) verified files."
$message | Set-Content -LiteralPath (Join-Path $output 'PASS.txt')
Write-Output $message
