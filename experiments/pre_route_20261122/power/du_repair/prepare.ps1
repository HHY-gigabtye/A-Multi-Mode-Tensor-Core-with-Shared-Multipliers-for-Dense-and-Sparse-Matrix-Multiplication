$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$trial=(Resolve-Path (Join-Path $root '../..')).Path
$entries=@(Import-Csv (Join-Path $trial 'baseline_manifest.csv'))+@(Import-Csv (Join-Path $trial 'extra_manifest.csv'))
$rows=@()
foreach($variant in 'baseline','candidate_v2'){
  $src=Join-Path $trial "$variant/src"
  $dst=Join-Path $root "$variant/src"
  if(Test-Path -LiteralPath $dst){throw "Preserve source snapshot $dst"}
  foreach($entry in $entries){
    $from=Join-Path $src $entry.Path
    $hash=(Get-FileHash -LiteralPath $from).Hash
    if($entry.Path -ne 'tensor_core_sv/outer_product_core.sv' -and $hash -ne $entry.SHA256){throw "Unexpected source modification: $from"}
    $to=Join-Path $dst $entry.Path
    New-Item -ItemType Directory -Path (Split-Path $to) -Force | Out-Null
    if($entry.Path -eq 'du_tia_sv/rtl/du_tia.sv'){
      Copy-Item -LiteralPath (Join-Path $root 'du_tia_fixed.sv') -Destination $to
    } else {Copy-Item -LiteralPath $from -Destination $to}
    $rows+=[pscustomobject]@{Variant=$variant;Path=$entry.Path;OriginalSHA256=$hash;SHA256=(Get-FileHash -LiteralPath $to).Hash}
  }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $root 'source_manifest.csv')
Write-Output "Prepared two isolated 93-file snapshots; shared DU/TIA repair only."
