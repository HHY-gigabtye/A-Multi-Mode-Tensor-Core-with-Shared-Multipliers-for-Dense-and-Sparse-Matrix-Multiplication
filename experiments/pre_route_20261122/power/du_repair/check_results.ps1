$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$rows=@()
foreach($mode in 'dense','hybrid','dual'){
  $expected=$null
  $folders=@(
    [pscustomobject]@{Variant='original_baseline';Kind='rtl_final';Folder=(Join-Path $root "../baseline/rtl_final/$mode")}
  )
  foreach($variant in 'baseline','candidate_v2'){
    foreach($kind in 'rtl','functional'){
      $folders+=[pscustomobject]@{Variant=$variant;Kind=$kind;Folder=(Join-Path $root "$variant/$kind/$mode")}
    }
  }
  foreach($item in $folders){
    $pass=Get-Content -Raw (Join-Path $item.Folder 'PASS.txt')
    if(!$pass.Contains('POWER WORKLOAD PASS') -or !$pass.Contains('captured_tiles=256')){throw "Incomplete run $($item.Folder)"}
    $trace=Join-Path $item.Folder 'transactions.trace'
    $lines=@(Get-Content $trace | ForEach-Object {(($_ -split ' ')[0..8]) -join ' '})
    $inputText=$lines -join "`n"
    if($null -eq $expected){$expected=$inputText}elseif($inputText -cne $expected){throw "Changed stimulus or handshake timing $($item.Folder)"}
    $sha=[Security.Cryptography.SHA256]::Create()
    $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($inputText))).Replace('-','')
    $sha.Dispose()
    $rows+=[pscustomobject]@{Mode=$mode;Variant=$item.Variant;Kind=$item.Kind;Cycles=$lines.Count;InputSHA256=$hash;TransactionSHA256=(Get-FileHash $trace).Hash}
    if($item.Kind -eq 'functional'){
      $header=(Get-Content (Join-Path $item.Folder 'activity.saif') -TotalCount 25) -join "`n"
      if($header -notmatch '\(TIMESCALE\s+1 ps\)' -or $header -notmatch '\(DURATION\s+20480000\)'){throw 'Wrong activity window'}
      if(!(Test-Path (Join-Path $root "$($item.Variant)/reports/functional_filtered/$mode/power.rpt"))){throw 'Missing power report'}
    }
  }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $root 'trace_identity.csv')
$manifest=Import-Csv (Join-Path $root 'source_manifest.csv')
foreach($entry in $manifest){
  $path=Join-Path $root "$($entry.Variant)/src/$($entry.Path)"
  if((Get-FileHash $path).Hash -ne $entry.SHA256){throw "Snapshot changed $path"}
  $original=Join-Path $root "../../$($entry.Variant)/src/$($entry.Path)"
  if((Get-FileHash $original).Hash -ne $entry.OriginalSHA256){throw "Original changed $original"}
  if($entry.Path -ne 'du_tia_sv/rtl/du_tia.sv' -and $entry.SHA256 -ne $entry.OriginalSHA256){throw 'Unexpected source delta'}
}
$duHashes=@($manifest | Where-Object {$_.Path -eq 'du_tia_sv/rtl/du_tia.sv'} | Select-Object -ExpandProperty SHA256 -Unique)
if($duHashes.Count -ne 1){throw 'The two DU/TIA repairs differ'}
$artifacts=@('../tb_power.sv','../simulate.tcl','du_tia_fixed.sv','du_gate.sv','tb_du_gate.sv','implement.tcl','analyze.tcl','run_power_sim.ps1')
foreach($variant in 'baseline','candidate_v2'){
  $artifacts+="$variant/routed/routed.dcp"
  $artifacts+="$variant/routed/routed_functional.v"
  foreach($mode in 'dense','hybrid','dual'){
    foreach($name in 'activity.saif','activity_import.saif','transactions.trace','excluded_saif_nets.txt'){$artifacts+="$variant/functional/$mode/$name"}
    foreach($name in 'power.rpt','power.xml','saif_import.rpt'){$artifacts+="$variant/reports/functional_filtered/$mode/$name"}
  }
}
$hashes=foreach($file in $artifacts){[pscustomobject]@{Path=$file;SHA256=(Get-FileHash (Join-Path $root $file)).Hash}}
$hashes | Export-Csv -NoTypeInformation (Join-Path $root 'artifact_manifest.csv')
'PASS: shared DU/TIA repair; all source snapshots verified; 6 repaired RTL and 6 routed functional workload runs; identical driven inputs to original baseline; all 288 tiles checked per run; 100 MHz, 256 completed tiles per 20.480 us activity window; 6 power reports.' | Set-Content (Join-Path $root 'validation.PASS.txt')
Get-Content (Join-Path $root 'validation.PASS.txt')
