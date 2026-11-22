$ErrorActionPreference='Stop'
$trial=$PSScriptRoot
$repo=(Resolve-Path (Join-Path $trial '../..')).Path
$baseline=@(Import-Csv (Join-Path $trial 'baseline_manifest.csv'))
$snapshots=@(Import-Csv (Join-Path $trial 'source_manifest.csv'))
foreach($entry in $baseline){
  if((Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash -ne $entry.SHA256){throw "Production changed: $($entry.Path)"}
}
foreach($entry in $snapshots){
  if((Get-FileHash -LiteralPath (Join-Path $trial "$($entry.Variant)/src/$($entry.Path)")).Hash -ne $entry.SHA256){throw "Snapshot changed: $($entry.Variant)/$($entry.Path)"}
  $original=@($baseline | Where-Object Path -eq $entry.Path)[0]
  if($entry.SHA256 -ne $original.SHA256 -and !($entry.Variant -eq 'candidate' -and $entry.Path -eq 'tensor_core_sv/outer_product_core.sv')){throw 'Unexpected scope expansion'}
}
foreach($entry in Import-Csv (Join-Path $trial 'existing_docs.csv')){
  if((Get-FileHash -LiteralPath $entry.Path).Hash -ne $entry.Hash){throw "Pre-existing document changed: $($entry.Path)"}
}
foreach($pair in @(
  @('tb_pre_route_equiv.sv','experiments/pre_route_20261122/tb_pre_route_equiv.sv'),
  @('tb_power.sv','experiments/pre_route_20261122/power/tb_power.sv'),
  @('implement.tcl','experiments/pre_route_20261122/power/du_repair/implement.tcl')
)){
  if((Get-FileHash -LiteralPath (Join-Path $trial $pair[0])).Hash -ne (Get-FileHash -LiteralPath (Join-Path $repo $pair[1])).Hash){throw "Reused file changed: $($pair[0])"}
}
$raw=(Get-FileHash -LiteralPath (Join-Path $repo 'tensor_core_sv/c_vectors.txt')).Hash
foreach($variant in 'baseline','candidate'){
  if((Get-FileHash -LiteralPath (Join-Path $trial "$variant/src/tensor_core_sv/c_vectors.txt")).Hash -ne $raw){throw 'Raw C vectors differ'}
}
$message='PASS: 93 production inputs unchanged; 186 snapshot hashes unchanged; only candidate TC differs; original tests, vectors, reused flow and pre-existing AGENTS.md edit preserved.'
$message | Set-Content (Join-Path $trial 'integrity.PASS.txt')
Write-Output $message
