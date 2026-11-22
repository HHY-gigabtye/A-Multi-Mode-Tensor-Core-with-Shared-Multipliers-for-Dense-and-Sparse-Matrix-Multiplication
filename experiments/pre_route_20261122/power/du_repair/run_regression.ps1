param([Parameter(Mandatory=$true)][ValidateSet('baseline','candidate_v2')][string]$Variant)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$src=Join-Path $root "$Variant/src"
$out=Join-Path $root "$Variant/regression"
if(Test-Path -LiteralPath $out){throw 'Preserve existing regression'}
New-Item -ItemType Directory -Path $out | Out-Null
$entries=Import-Csv (Join-Path $root 'source_manifest.csv') | Where-Object {$_.Variant -eq $Variant}
function Check-Inputs {
  foreach($entry in $entries){if((Get-FileHash -LiteralPath (Join-Path $src $entry.Path)).Hash -ne $entry.SHA256){throw "Changed protected snapshot: $($entry.Path)"}}
}
Check-Inputs
foreach($case in 'units','top'){
  $log=Join-Path $out "$case.log"
  $process=Start-Process -FilePath 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $src -ArgumentList @('-c','-l',('"{0}"' -f $log),'-do',"integration_sv/sim/run_$case.do") -RedirectStandardOutput (Join-Path $out "$case.stdout.log") -RedirectStandardError (Join-Path $out "$case.stderr.log")
  if($process.ExitCode -ne 0){throw "ModelSim $case failed"}
  $text=Get-Content -Raw $log
  if($text -match '\*\*\s+(Fatal|Error):'){throw "Simulator error $log"}
  $markers=if($case -eq 'units'){@('ALL PASS MLU unit C/SV:','[PASS] DU/TIA compact RTL:','BRIDGE RTL PASS:','OUTER UNIT PASS','TC COMPARISON PASS','MSU SV PASS:')}else{@('UNSTALLED DENSE PASS','UNSTALLED MIXED PASS','TOP INTEGRATION PASS:')}
  foreach($marker in $markers){if(!$text.Contains($marker)){throw "Missing $marker"}}
  Write-Output "$Variant repaired $case PASS"
}
$pattern='^# (TOP (PHASE PASS|COVERAGE|MODE TRANSITIONS|RESET COVERAGE|INTEGRATION PASS)|UNSTALLED (DENSE|MIXED) PASS)'
$expected=@(Get-Content (Join-Path $root '../../expected_top_summary.txt'))
$actual=@(Get-Content (Join-Path $out 'top.log') | Where-Object {$_ -match $pattern})
if(($expected -join "`n") -cne ($actual -join "`n")){throw 'Changed integration summary'}
Check-Inputs
"PASS: $Variant repaired DU/TIA, immutable original unit and integration suites; $($actual.Count) identical top summaries; protected source hashes verified." | Set-Content (Join-Path $out 'PASS.txt')
Get-Content (Join-Path $out 'PASS.txt')
