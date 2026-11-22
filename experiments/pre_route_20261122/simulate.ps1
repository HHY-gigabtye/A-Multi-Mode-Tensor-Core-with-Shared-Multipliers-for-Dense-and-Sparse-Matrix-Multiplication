param(
    [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate','candidate_v2')][string]$Variant,
    [string]$RunName = 'verification_repeat',
    [string]$Vsim = 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe'
)
$ErrorActionPreference = 'Stop'
$trial = $PSScriptRoot
$sourceRoot = Join-Path $trial "$Variant/src"
$output = Join-Path $trial "$Variant/$RunName"
if (Test-Path -LiteralPath $output) { throw "Choose a new RunName: $output" }
New-Item -ItemType Directory -Path $output | Out-Null
$entries = @(Import-Csv (Join-Path $trial 'baseline_manifest.csv')) + @(Import-Csv (Join-Path $trial 'extra_manifest.csv'))
function Assert-Inputs {
    foreach ($entry in $entries) {
        if ($Variant -ne 'baseline' -and $entry.Path -eq 'tensor_core_sv/outer_product_core.sv') { continue }
        if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $entry.Path)).Hash -ne $entry.SHA256) {
            throw "Protected snapshot file changed: $($entry.Path)"
        }
    }
}
Assert-Inputs
foreach ($case in @('units','top')) {
    $log = Join-Path $output "$case.log"
    $process = Start-Process -FilePath $Vsim -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $sourceRoot `
        -ArgumentList @('-c','-l', ('"{0}"' -f $log), '-do', "integration_sv/sim/run_$case.do") `
        -RedirectStandardOutput (Join-Path $output "$case.stdout.log") `
        -RedirectStandardError (Join-Path $output "$case.stderr.log")
    if ($process.ExitCode -ne 0) { throw "ModelSim $case exit $($process.ExitCode)" }
    $text = Get-Content -Raw -LiteralPath $log
    if ($text -match '\*\*\s+(Fatal|Error):') { throw "Simulator error: $log" }
    $markers = if ($case -eq 'units') {
        @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:', 'BRIDGE RTL PASS:', 'OUTER UNIT PASS', 'TC COMPARISON PASS', 'MSU SV PASS:')
    } else { @('UNSTALLED DENSE PASS', 'UNSTALLED MIXED PASS', 'TOP INTEGRATION PASS:') }
    foreach ($marker in $markers) { if (!$text.Contains($marker)) { throw "Missing marker: $marker" } }
    Write-Output "$Variant $case PASS"
}
$pattern = '^# (TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)|UNSTALLED (DENSE|MIXED) PASS)'
$expected = @(Get-Content -LiteralPath (Join-Path $trial 'expected_top_summary.txt'))
$actual = @(Get-Content -LiteralPath (Join-Path $output 'top.log') | Where-Object { $_ -match $pattern })
if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Integration summary differs from baseline' }
Assert-Inputs
$message = "PASS: $Variant original unit suites, comparison, integration; $($actual.Count) identical top summaries; protected snapshot hashes unchanged."
$message | Set-Content -LiteralPath (Join-Path $output 'PASS.txt')
Write-Output $message
