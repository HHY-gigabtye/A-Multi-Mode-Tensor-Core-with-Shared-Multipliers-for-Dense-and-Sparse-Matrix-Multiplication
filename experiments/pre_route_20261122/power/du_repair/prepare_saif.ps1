param([ValidateSet('dense','hybrid','dual')][string]$Mode='dense',
  [ValidateSet('baseline','candidate_v2')][string[]]$Variants=@('baseline','candidate_v2'))
$ErrorActionPreference='Stop'
foreach ($variant in $Variants) {
  $folder=Join-Path $PSScriptRoot "$variant/functional/$Mode"
  if (!(Test-Path -LiteralPath (Join-Path $folder 'PASS.txt'))) {throw "Unvalidated workload: $folder"}
  $source=Join-Path $folder 'activity.saif'
  $target=Join-Path $folder 'activity_import.saif'
  if (Test-Path -LiteralPath $target) {throw "Preserve existing import: $target"}
  $kept=[Collections.Generic.List[string]]::new()
  $excluded=[Collections.Generic.List[string]]::new()
  foreach ($line in [IO.File]::ReadLines($source)) {
    # Vivado 2022.2's SAIF parser rejects its generated '(null)' net names.
    # Preserve the raw file and every activity count. Unsupported generated
    # net records are omitted from import and left to vectorless propagation.
    if ($line.Contains('\(null\)')) {
      if ($line -notmatch '^\s*\(.+ \(T0 \d+\).*\(TC \d+\)\)\s*$') {throw 'Unexpected unsupported-name record'}
      $excluded.Add($line)
    } else {$kept.Add($line)}
  }
  [IO.File]::WriteAllLines($target,$kept,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllLines((Join-Path $folder 'excluded_saif_nets.txt'),$excluded,[Text.UTF8Encoding]::new($false))
  Write-Output "$variant $Mode unsupported-name records=$($excluded.Count); all remaining activity data unchanged"
}
