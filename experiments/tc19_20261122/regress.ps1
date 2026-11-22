param(
  [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate')][string]$Variant,
  [string]$RunName='regression'
)
$ErrorActionPreference='Stop'
$trial=$PSScriptRoot
$repo=(Resolve-Path (Join-Path $trial '../..')).Path
$sourceRoot=Join-Path $trial "$Variant/src"
$out=Join-Path $trial "$Variant/$RunName"
if(Test-Path -LiteralPath $out){throw 'Choose a fresh regression directory'}
New-Item -ItemType Directory -Path $out | Out-Null
function Check-Sources {
  foreach($entry in Import-Csv (Join-Path $trial 'baseline_manifest.csv')){
    if((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256){throw "Production changed: $($entry.Path)"}
    if($Variant -eq 'candidate' -and $entry.Path -eq 'tensor_core_sv/outer_product_core.sv'){continue}
    if((Get-FileHash -LiteralPath (Join-Path $sourceRoot $entry.Path)).Hash -ne $entry.SHA256){throw "Protected snapshot changed: $($entry.Path)"}
  }
}
Check-Sources
$previousRoot=$env:STC_ROOT
$env:STC_ROOT=$sourceRoot
try {
  foreach($case in 'units','top'){
    $original=Get-Content -Raw (Join-Path $sourceRoot "integration_sv/sim/run_$case.do")
    $oldBuild='set build [file join $root integration_sv build '+$case+']'
    if(!$original.Contains($oldBuild)){throw 'Unexpected original launcher layout'}
    $build=(Join-Path $out "build/$case").Replace('\','/')
    $adapter=$original.Replace($oldBuild,('set build {'+$build+'}'))
    $adapterPath=Join-Path $out "run_$case.do"
    [IO.File]::WriteAllText($adapterPath,$adapter,[Text.UTF8Encoding]::new($false))
    $log=Join-Path $out "$case.log"
    $process=Start-Process -FilePath 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $sourceRoot -ArgumentList @('-c','-l',('"{0}"' -f $log),'-do',('"{0}"' -f $adapterPath.Replace('\','/'))) -RedirectStandardOutput (Join-Path $out "$case.stdout.log") -RedirectStandardError (Join-Path $out "$case.stderr.log")
    if($process.ExitCode -ne 0){throw "ModelSim $case failed with $($process.ExitCode)"}
    $text=Get-Content -Raw $log
    if($text -match '\*\*\s+(Fatal|Error):'){throw "Simulator error: $log"}
    $markers=if($case -eq 'units'){@('ALL PASS MLU unit C/SV:','[PASS] DU/TIA compact RTL:','BRIDGE RTL PASS:','OUTER UNIT PASS','TC COMPARISON PASS','MSU SV PASS:')}else{@('UNSTALLED DENSE PASS','UNSTALLED MIXED PASS','TOP INTEGRATION PASS:')}
    foreach($marker in $markers){if(!$text.Contains($marker)){throw "Missing PASS marker: $marker"}}
    Write-Output "$Variant $case PASS"
  }
} finally {$env:STC_ROOT=$previousRoot}
$pattern='^# (TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)|UNSTALLED (DENSE|MIXED) PASS)'
$expected=@(Get-Content (Join-Path $trial 'expected_top_summary.txt'))
$actual=@(Get-Content (Join-Path $out 'top.log') | Where-Object {$_ -match $pattern})
if(($expected -join "`n") -cne ($actual -join "`n")){throw 'Integration summaries differ from accepted baseline'}
$actual | Set-Content (Join-Path $out 'top_summary.txt')
Check-Sources
"PASS: $Variant original unit and integration regressions; $($actual.Count) identical top summaries; production and protected snapshot hashes unchanged." | Set-Content (Join-Path $out 'PASS.txt')
Get-Content (Join-Path $out 'PASS.txt')
