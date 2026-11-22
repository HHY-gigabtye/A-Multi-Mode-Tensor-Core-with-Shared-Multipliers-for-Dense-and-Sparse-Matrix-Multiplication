# Extract retained report values; preserve all original Vivado evidence.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
function Field([string]$Report,[string]$Label){
  $pattern='(?m)^\|\s*'+[regex]::Escape($Label)+'\s*\|\s*([^|]+)\|'
  $match=[regex]::Match($Report,$pattern)
  if(!$match.Success){throw "Missing report field: $Label"}
  return $match.Groups[1].Value.Trim()
}
$rows=@()
foreach($mode in 'dense','hybrid','dual'){
  foreach($variant in 'baseline','candidate_v2'){
    $path="$variant/reports/functional_filtered/$mode/power.rpt"
    $report=Get-Content -Raw (Join-Path $root $path)
    $matched=[regex]::Match((Field $report 'Design Nets Matched'),'\((\d+)/(\d+)\)')
    if(!$matched.Success){throw 'Missing annotation counts'}
    $excluded=@(Get-Content (Join-Path $root "$variant/functional/$mode/excluded_saif_nets.txt"))
    $row=[pscustomobject][ordered]@{
      Mode=$mode;Variant=$variant
      TotalW=[double](Field $report 'Total On-Chip Power (W)')
      DynamicW=[double](Field $report 'Dynamic (W)')
      StaticW=[double](Field $report 'Device Static (W)')
      ClocksW=[double](Field $report 'Clocks')
      LogicW=[double](Field $report 'Slice Logic')
      SignalsW=[double](Field $report 'Signals')
      BramW=[double](Field $report 'Block RAM')
      DspW=[double](Field $report 'DSPs')
      TcDynamicW=[double](Field $report 'u_tensor_core')
      DuDynamicW=[double](Field $report 'u_du_tia')
      JunctionC=[double](Field $report 'Junction Temperature (C)')
      AmbientC=[double](Field $report 'Ambient Temp (C)')
      MatchedNets=[int]$matched.Groups[1].Value
      DesignNets=[int]$matched.Groups[2].Value
      CoveragePercent=100*[double]$matched.Groups[1].Value/[double]$matched.Groups[2].Value
      ExcludedRecords=$excluded.Count;Report=$path
    }
    if($row.JunctionC -ne 50){throw 'Unexpected fixed junction temperature'}
    $rows+=$row
  }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $root 'power_summary.csv')
$comparison=for($i=0;$i -lt $rows.Count;$i+=2){
  $base=$rows[$i]; $candidate=$rows[$i+1]
  [pscustomobject][ordered]@{
    Mode=$base.Mode;BaselineTotalW=$base.TotalW;CandidateTotalW=$candidate.TotalW
    TotalChangePercent=100*($candidate.TotalW/$base.TotalW-1)
    BaselineDynamicW=$base.DynamicW;CandidateDynamicW=$candidate.DynamicW
    DynamicChangePercent=100*($candidate.DynamicW/$base.DynamicW-1)
    BaselineDynamicNjPerTile=80*$base.DynamicW
    CandidateDynamicNjPerTile=80*$candidate.DynamicW
  }
}
$comparison | Export-Csv -NoTypeInformation (Join-Path $root 'power_comparison.csv')
@{Power=$rows;Comparison=$comparison} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root 'power_summary.json')
Get-Content (Join-Path $root 'power_comparison.csv')
