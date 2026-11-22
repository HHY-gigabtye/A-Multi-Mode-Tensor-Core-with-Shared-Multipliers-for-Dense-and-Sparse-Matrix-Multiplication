$ErrorActionPreference='Stop'
$trial=$PSScriptRoot
& (Join-Path $trial 'check_integrity.ps1')
foreach($variant in 'baseline','candidate'){
  if(!(Get-Content -Raw (Join-Path $trial "$variant/regression_native/PASS.txt")).Contains('50 identical top summaries')){throw 'Original regression missing'}
  if(!(Get-Content -Raw (Join-Path $trial "audit/$variant/PASS.txt")).Contains('PASS internal FPGA OOC post-route STA')){throw '100 MHz audit missing'}
}
$extra=Get-Content -Raw (Join-Path $trial 'candidate/equivalence/PASS.txt')
if(!$extra.Contains('PRE_ROUTE EQUIVALENCE PASS') -or !$extra.Contains('TC19 BOUNDS PASS')){throw 'Additional unit tests missing'}
$traceRows=@()
foreach($bounds in $false,$true){
  $suffix=if($bounds){'bounds'}else{'workload'}
  $variants=if($bounds){@('candidate')}else{@('baseline','candidate')}
  foreach($mode in 'dense','hybrid','dual'){
    $expectedInputs=$null
    $expectedTransfers=$null
    foreach($variant in $variants){
      foreach($kind in 'rtl','functional'){
        $folder=Join-Path $trial "$variant/${kind}_$suffix/$mode"
        $pass=Get-Content -Raw (Join-Path $folder 'PASS.txt')
        if(!$pass.Contains('tiles=288') -or !$pass.Contains('II=8') -or !$pass.Contains('TC19_WORKLOAD_PASS')){throw "Incomplete workload: $folder"}
        $trace=Join-Path $folder 'transactions.trace'
        $lines=@(Get-Content $trace)
        $inputs=@()
        $transfers=@()
        foreach($line in $lines){
          $fields=$line -split ' '
          # First nine fields include all driven inputs and cf/rf/df/wf.
          $inputs+=($fields[0..8] -join ' ')
          $handshakes=$fields[8]
          if($handshakes[1] -eq '1'){$transfers+="R $($fields[0]) $($fields[9])"}
          if($handshakes[3] -eq '1'){$transfers+="W $($fields[0]) $($fields[10..12] -join ' ')"}
        }
        $inputText=$inputs -join "`n"
        $transferText=$transfers -join "`n"
        if($null -eq $expectedInputs){$expectedInputs=$inputText;$expectedTransfers=$transferText}
        elseif($expectedInputs -cne $inputText -or $expectedTransfers -cne $transferText){throw "Stimulus, handshake or accepted transfer mismatch: $folder"}
        $traceRows+=[pscustomobject]@{Bounds=$bounds;Mode=$mode;Variant=$variant;Kind=$kind;Cycles=$lines.Count;SHA256=(Get-FileHash -LiteralPath $trace).Hash}
      }
    }
  }
}
$traceRows | Export-Csv -NoTypeInformation (Join-Path $trial 'trace_identity.csv')
$resources=@()
foreach($variant in 'baseline','candidate'){
  foreach($stage in 'synth','routed'){
    $report=Get-Content -Raw (Join-Path $trial "$variant/routed/utilization_$stage.rpt")
    $lut=[regex]::Match($report,'\| Slice LUTs\*?\s+\|\s+(\d+)').Groups[1].Value
    $ff=[regex]::Match($report,'\| Slice Registers\s+\|\s+(\d+)').Groups[1].Value
    $bram=[regex]::Match($report,'\|\s+RAMB36E1 only\s+\|\s+(\d+)').Groups[1].Value
    $dsp=[regex]::Match($report,'\| DSPs\s+\|\s+(\d+)').Groups[1].Value
    if(!$lut -or !$ff -or $bram -ne '18' -or $dsp -ne '64'){throw 'Unexpected or missing resources'}
    $resources+=[pscustomobject]@{Variant=$variant;Stage=$stage;LUT=[int]$lut;FF=[int]$ff;DSP=[int]$dsp;BRAM36=[int]$bram}
  }
}
$resources | Export-Csv -NoTypeInformation (Join-Path $trial 'resource_comparison.csv')
$artifacts=@('README.md','REPORT.md','rtl.diff','source_manifest.csv','baseline_manifest.csv','regress.ps1','implement.tcl','audit.tcl','refine.tcl','run_equivalence.ps1','equivalence.do','tb_tc19_bounds.sv','tb_pre_route_equiv.sv','tb_power.sv','tb_tc19_system.sv','run_workload.ps1','check_results.ps1','check_integrity.ps1')
foreach($variant in 'baseline','candidate'){
  $artifacts+="$variant/routed/routed.dcp","$variant/routed/routed_functional.v","$variant/routed/utilization_routed.rpt","$variant/routed/timing_summary.rpt","$variant/regression_native/PASS.txt","audit/$variant/PASS.txt"
}
$hashes=foreach($file in $artifacts){[pscustomobject]@{Path=$file;SHA256=(Get-FileHash -LiteralPath (Join-Path $trial $file)).Hash}}
$hashes | Export-Csv -NoTypeInformation (Join-Path $trial 'artifact_manifest.csv')
'PASS: both original regressions; standalone equivalence and all 65536 signed operand pairs; 18 system workload runs (9 RTL, 9 routed functional), 288 tiles each, identical relevant traces; both reopened 100 MHz audits; production and protected inputs unchanged.' | Set-Content (Join-Path $trial 'validation.PASS.txt')
Get-Content (Join-Path $trial 'validation.PASS.txt')
$resources | Format-Table -AutoSize
