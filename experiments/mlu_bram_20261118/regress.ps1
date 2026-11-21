param([Parameter(Mandatory=$true)][string]$Trial, [ValidateSet('mlu','units','top','all')][string]$Test='all')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$trialRoot = (Resolve-Path (Join-Path $PSScriptRoot $Trial)).Path
$env:MLU_BRAM_SOURCE = Join-Path $trialRoot 'src'
$env:MLU_BRAM_REPO = $repo
$env:MLU_BRAM_OUTPUT = $trialRoot
$sim = 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe'
$testCases = if ($Test -eq 'all') { @('units','top') } else { @($Test) }
foreach ($testCase in $testCases) {
    $env:MLU_BRAM_CASE = $testCase
    $log = Join-Path $trialRoot "$testCase.log"
    if (Test-Path -LiteralPath $log) { throw "Preserve existing log: $log" }
    & $sim -c -l $log -do (Join-Path $PSScriptRoot 'run_tests.do')
    if ($LASTEXITCODE -ne 0) { throw "Simulation exited $LASTEXITCODE; inspect $log" }
    $body = Get-Content -Raw -LiteralPath $log
    if ($body -match '\*\*\s+(Fatal|Error):') { throw "Simulator failure: $log" }
    $markers = switch ($testCase) {
        'mlu' { @('ALL PASS MLU unit C/SV:') }
        'units' { @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:', 'BRIDGE RTL PASS:', 'ALL PASS C/SV:', 'MSU SV PASS:') }
        'top' { @('TOP INTEGRATION PASS:') }
    }
    foreach ($marker in $markers) { if (!$body.Contains($marker)) { throw "Missing PASS $marker in $log" } }
    Select-String -LiteralPath $log -Pattern 'PASS|records|resets|commands=|command\+retire|completed|seed=' | ForEach-Object { $_.Line }
}
foreach ($entry in (Import-Csv (Join-Path $PSScriptRoot 'protected_initial.csv'))) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256) { throw "Protected file changed: $($entry.Path)" }
}
Write-Output "PASS $Trial $Test; protected files unchanged."
