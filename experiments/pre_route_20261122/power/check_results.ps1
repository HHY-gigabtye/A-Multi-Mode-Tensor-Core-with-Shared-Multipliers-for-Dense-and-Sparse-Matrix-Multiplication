param(
  [ValidateSet('functional_net_saif','timing_run3')][string]$Capture='functional_net_saif',
  [ValidateSet('dense','hybrid','dual')][string[]]$Modes=@('dense','hybrid','dual')
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$hashRows=@()
foreach ($mode in $Modes) {
  $expectedInputs=$null
  foreach ($variant in 'baseline','candidate_v2') {
    foreach ($kind in @('rtl_final',$Capture)) {
      $folder=Join-Path $root "$variant/$kind/$mode"
      $pass=Get-Content -Raw -LiteralPath (Join-Path $folder 'PASS.txt')
      if (!$pass.Contains('POWER WORKLOAD PASS') -or !$pass.Contains('captured_tiles=256')) {throw "Incomplete simulation: $folder"}
      $trace=Join-Path $folder 'transactions.trace'
      # Columns 0..8 are cycle plus all driven transaction inputs. Output buses
      # without valid may legitimately differ after netlist optimization.
      $inputLines=@(Get-Content -LiteralPath $trace | ForEach-Object { (($_ -split ' ')[0..8]) -join ' ' })
      $inputText=$inputLines -join "`n"
      if ($null -eq $expectedInputs) {$expectedInputs=$inputText}
      elseif ($inputText -cne $expectedInputs) {throw "Stimulus/handshake timing differs: $folder"}
      $inputPath=Join-Path $folder 'inputs.trace'
      [IO.File]::WriteAllText($inputPath,$inputText,[Text.UTF8Encoding]::new($false))
      $hashRows+=[pscustomobject]@{Mode=$mode;Variant=$variant;Kind=$kind;Cycles=$inputLines.Count;InputSHA256=(Get-FileHash -LiteralPath $inputPath).Hash;TransactionSHA256=(Get-FileHash -LiteralPath $trace).Hash}
      if ($kind -eq $Capture) {
        $saif=Join-Path $folder 'activity.saif'
        $header=(Get-Content -LiteralPath $saif -TotalCount 25) -join "`n"
        if ($header -notmatch '\(TIMESCALE\s+1 ps\)' -or $header -notmatch '\(DURATION\s+20480000\)') {throw "Unexpected SAIF timebase/window: $saif"}
      }
    }
  }
}
$hashRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $root 'trace_identity.csv')
$artifacts=@('tb_power.sv','run_sim.ps1','run_capture.ps1','simulate.tcl','export.tcl','export_functional.tcl','analyze.tcl')
foreach ($variant in 'baseline','candidate_v2') {
  $artifacts+="$variant/routed.v"
  $artifacts+="$variant/routed.sdf"
  $artifacts+="$variant/routed_functional.v"
  $artifacts+="../$variant/routed/routed.dcp"
  foreach ($mode in $Modes) {$artifacts+="$variant/$Capture/$mode/activity.saif"}
}
$artifactRows=foreach ($file in $artifacts) {[pscustomobject]@{Path=$file;SHA256=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash}}
$artifactRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $root 'artifact_manifest.csv')
"PASS: workloads=$($Modes -join ','); $($Modes.Count*2) RTL and $($Modes.Count*2) $Capture runs; identical driven inputs across all four runs per mode; 100 MHz; 256 completed tiles in each 20.480 us SAIF window." | Set-Content (Join-Path $root 'validation.PASS.txt')
Get-Content (Join-Path $root 'validation.PASS.txt')
