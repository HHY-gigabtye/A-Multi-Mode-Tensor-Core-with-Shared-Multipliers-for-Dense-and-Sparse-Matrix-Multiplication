$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'candidate/equivalence'
if(Test-Path -LiteralPath $out){throw 'Preserve previous equivalence evidence'}
New-Item -ItemType Directory -Path $out | Out-Null
$log=Join-Path $out 'simulation.log'
$p=Start-Process -FilePath 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe' -WindowStyle Hidden -PassThru -Wait -WorkingDirectory $PSScriptRoot -ArgumentList @('-c','-l',('"{0}"' -f $log),'-do','equivalence.do') -RedirectStandardOutput (Join-Path $out 'stdout.log') -RedirectStandardError (Join-Path $out 'stderr.log')
if($p.ExitCode -ne 0){throw "ModelSim exit $($p.ExitCode)"}
$text=Get-Content -Raw $log
if($text -match '\*\*\s+(Fatal|Error):' -or !$text.Contains('PRE_ROUTE EQUIVALENCE PASS') -or !$text.Contains('TC19 BOUNDS PASS')){throw 'Additional unit checks failed'}
Get-Content $log | Where-Object {$_ -match '^# (PRE_ROUTE EQUIVALENCE PASS|TC19 BOUNDS PASS)'} | Set-Content (Join-Path $out 'PASS.txt')
Get-Content (Join-Path $out 'PASS.txt')
