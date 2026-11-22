param(
    [ValidateSet('candidate','candidate_v2')][string]$Variant = 'candidate_v2',
    [string]$Vsim = 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe'
)
$ErrorActionPreference = 'Stop'
$trial = $PSScriptRoot
$output = Join-Path $trial "$Variant/equivalence"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$env:PRE_ROUTE_VARIANT = $Variant
$logPath = Join-Path $output 'equivalence.log'
$process = Start-Process -FilePath $Vsim -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $trial `
    -ArgumentList @('-c','-l', ('"{0}"' -f $logPath),'-do','equivalence.do') `
    -RedirectStandardOutput (Join-Path $output 'equivalence.stdout.log') `
    -RedirectStandardError (Join-Path $output 'equivalence.stderr.log')
if ($process.ExitCode -ne 0) { throw "Equivalence simulator exit $($process.ExitCode)" }
$log = Get-Content -Raw -LiteralPath $logPath
if ($log -match '\*\*\s+(Error|Fatal):' -or !$log.Contains('PRE_ROUTE EQUIVALENCE PASS')) {
    throw 'Equivalence test did not pass'
}
$line = @(Get-Content -LiteralPath $logPath | Where-Object { $_ -match '^# PRE_ROUTE EQUIVALENCE PASS' })
$line | Set-Content -LiteralPath (Join-Path $output 'equivalence.PASS.txt')
Write-Output $line
