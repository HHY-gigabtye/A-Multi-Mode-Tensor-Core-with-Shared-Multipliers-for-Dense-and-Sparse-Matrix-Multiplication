param([string]$RunName='regression')
$ErrorActionPreference='Stop'
$record=$PSScriptRoot
$repo=(Resolve-Path (Join-Path $record '../../..')).Path
$out=Join-Path $record $RunName
if(Test-Path -LiteralPath $out){throw 'Choose a fresh regression directory'}
New-Item -ItemType Directory -Path $out | Out-Null
function Check-Sources {
  foreach($entry in Import-Csv (Join-Path $record 'production_manifest.csv')){
    if((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256){throw "Changed production input: $($entry.Path)"}
  }
}
Check-Sources
$previousRoot=$env:STC_ROOT
$env:STC_ROOT=$repo
try {
  foreach($case in 'units','top'){
    # Only redirect build artifacts. Tests, sources, seeds, assertions, and
    # the unit-before-integration execution order are unchanged.
    $original=Get-Content -Raw (Join-Path $repo "integration_sv/sim/run_$case.do")
    $oldBuild='set build [file join $root integration_sv build '+$case+']'
    if(!$original.Contains($oldBuild)){throw 'Unexpected original launcher layout'}
    $build=(Join-Path $out "build/$case").Replace('\','/')
    $adapter=$original.Replace($oldBuild,('set build {'+$build+'}'))
    $adapterPath=Join-Path $out "run_$case.do"
    [IO.File]::WriteAllText($adapterPath,$adapter,[Text.UTF8Encoding]::new($false))
    $log=Join-Path $out "$case.log"
    $process=Start-Process -FilePath 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $repo -ArgumentList @('-c','-l',('"{0}"' -f $log),'-do',('"{0}"' -f $adapterPath.Replace('\','/'))) -RedirectStandardOutput (Join-Path $out "$case.stdout.log") -RedirectStandardError (Join-Path $out "$case.stderr.log")
    if($process.ExitCode -ne 0){throw "ModelSim $case failed with $($process.ExitCode)"}
    $text=Get-Content -Raw $log
    if($text -match '\*\*\s+(Fatal|Error):'){throw "Simulator error: $log"}
    $markers=if($case -eq 'units'){@('ALL PASS MLU unit C/SV:','[PASS] DU/TIA compact RTL:','BRIDGE RTL PASS:','OUTER UNIT PASS','TC COMPARISON PASS','MSU SV PASS:')}else{@('UNSTALLED DENSE PASS','UNSTALLED MIXED PASS','TOP INTEGRATION PASS:')}
    foreach($marker in $markers){if(!$text.Contains($marker)){throw "Missing PASS marker: $marker"}}
    Write-Output "Production $case PASS"
  }
} finally {$env:STC_ROOT=$previousRoot}
$pattern='^# (TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)|UNSTALLED (DENSE|MIXED) PASS)'
$expected=@(Get-Content (Join-Path $repo 'experiments/pre_route_20261122/expected_top_summary.txt'))
$actual=@(Get-Content (Join-Path $out 'top.log') | Where-Object {$_ -match $pattern})
if(($expected -join "`n") -cne ($actual -join "`n")){throw 'Integration summaries differ from accepted baseline'}
$actual | Set-Content (Join-Path $out 'top_summary.txt')
Check-Sources
foreach($entry in Import-Csv (Join-Path $record 'before_manifest.csv')){
  if((Get-FileHash -LiteralPath (Join-Path "$record/before" $entry.Path)).Hash -ne $entry.SHA256){throw 'Pre-update backup changed'}
}
foreach($entry in Import-Csv (Join-Path $record 'preserved_evidence.csv')){
  if((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256){throw "Historical evidence changed: $($entry.Path)"}
}
'PASS: production unit and integration regressions; all 50 accepted top summaries identical; 93 production source/reference/test hashes match the validated candidate; pre-update backups and 81 historical evidence artifacts unchanged.' | Set-Content (Join-Path $out 'PASS.txt')
Get-Content (Join-Path $out 'PASS.txt')
