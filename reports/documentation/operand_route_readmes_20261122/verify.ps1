$ErrorActionPreference = 'Stop'
$record = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $record '../../..')).Path
$promotion = Join-Path $repo 'reports/verification/operand_route_main_20261122'
$trial = Join-Path $repo 'experiments/pre_route_20261122'
$repair = Join-Path $trial 'power/du_repair'
$results = [Collections.Generic.List[string]]::new()
'IN PROGRESS: documentation audit has not completed.' | Set-Content -Encoding utf8 (Join-Path $record 'validation.txt')

function Assert-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Hash mismatch: $Path"
    }
}
function Check-Manifest([string]$Manifest, [string]$Base) {
    $entries = @(Import-Csv -LiteralPath $Manifest)
    foreach ($entry in $entries) { Assert-Hash (Join-Path $Base $entry.Path) $entry.SHA256 }
    return $entries.Count
}

$before = @(Import-Csv (Join-Path $record 'before_manifest.csv'))
foreach ($entry in $before) { Assert-Hash (Join-Path $repo $entry.Backup) $entry.SHA256 }
$results.Add("PASS: $($before.Count) documentation/metadata backups preserve original bytes.")

$inventory = @(Import-Csv (Join-Path $record 'review_inventory.csv'))
$after = foreach ($entry in $inventory) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $repo $entry.Path)).Hash
    $changed = $hash -ne $entry.SHA256Before
    if ($changed -ne ($entry.PlannedUpdate -eq 'True')) {
        throw "Unexpected README change status: $($entry.Path)"
    }
    [pscustomobject]@{ Path=$entry.Path; Changed=$changed; SHA256Before=$entry.SHA256Before; SHA256After=$hash }
}
$after | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $record 'after_manifest.csv')
$changedCount = @($after | Where-Object Changed).Count
$results.Add("PASS: $changedCount updated READMEs; $($inventory.Count - $changedCount) reviewed READMEs unchanged.")

$oldEvidence = @(Import-Csv (Join-Path $record 'before/reports/verification/operand_route_main_20261122/preserved_evidence.csv'))
$newEvidence = @(Import-Csv (Join-Path $promotion 'preserved_evidence.csv'))
$relocations = @(Import-Csv (Join-Path $record 'evidence_relocations.csv'))
if ($oldEvidence.Count -ne $newEvidence.Count -or $relocations.Count -ne 3) { throw 'Evidence manifest count changed' }
for ($i=0; $i -lt $oldEvidence.Count; $i++) {
    $old = $oldEvidence[$i]
    $mapped = @($relocations | Where-Object OriginalPath -eq $old.Path)
    $expectedPath = $old.Path
    if ($mapped.Count -eq 1) {
        if ($mapped[0].SHA256 -ne $old.SHA256) { throw 'Relocation changed an original hash' }
        $expectedPath = $mapped[0].ArchivedPath
    }
    if ($newEvidence[$i].Path -ne $expectedPath -or $newEvidence[$i].SHA256 -ne $old.SHA256) {
        throw "Unexpected evidence manifest change: $($old.Path)"
    }
}
$results.Add('PASS: exactly three evidence locations relocated; all original hashes retained.')
$count = Check-Manifest (Join-Path $promotion 'production_manifest.csv') $repo
$results.Add("PASS: $count production source/reference/test hashes unchanged.")
$count = Check-Manifest (Join-Path $promotion 'before_manifest.csv') (Join-Path $promotion 'before')
$results.Add("PASS: $count original promotion backups unchanged.")
$count = Check-Manifest (Join-Path $promotion 'preserved_evidence.csv') $repo
$results.Add("PASS: $count original evidence artifacts preserved.")
$repairedSources = @(Import-Csv (Join-Path $repair 'source_manifest.csv'))
foreach ($entry in $repairedSources) {
    Assert-Hash (Join-Path $repair "$($entry.Variant)/src/$($entry.Path)") $entry.SHA256
}
$results.Add("PASS: $($repairedSources.Count) repaired snapshot source hashes unchanged.")
$count = Check-Manifest (Join-Path $repair 'artifact_manifest.csv') $repair
$results.Add("PASS: $count repaired experiment artifact hashes unchanged.")
$originalSources = @(Import-Csv (Join-Path $trial 'source_integrity.csv'))
foreach ($entry in $originalSources) {
    Assert-Hash (Join-Path $trial "baseline/src/$($entry.Path)") $entry.BaselineSHA256
    Assert-Hash (Join-Path $trial "$($entry.CandidateVariant)/src/$($entry.Path)") $entry.CandidateSHA256
}
$results.Add("PASS: $($originalSources.Count * 2) original baseline/candidate snapshot hashes unchanged.")

# Check inline local link destinations without rewriting dated historical links.
'"Document","Target","Exists"' | Set-Content -Encoding utf8 (Join-Path $record 'link_checks.csv')
$documents = @($after | Where-Object Changed | ForEach-Object { Join-Path $repo $_.Path }) + @(Join-Path $record 'README.md')
$links = foreach ($document in $documents) {
    $body = [IO.File]::ReadAllText($document)
    foreach ($match in [regex]::Matches($body, '\[[^\]\r\n]+\]\((?<target>[^)\r\n]+)\)')) {
        $target = $match.Groups['target'].Value.Trim()
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { continue }
        $pathPart = [Uri]::UnescapeDataString(($target -split '#', 2)[0].Trim('<','>'))
        $resolved = $document
        if ($pathPart) { $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $document) $pathPart)) }
        [pscustomobject]@{ Document=[IO.Path]::GetRelativePath($repo,$document); Target=$target; Exists=(Test-Path -LiteralPath $resolved) }
    }
}
$links | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $record 'link_checks.csv')
$missing = @($links | Where-Object { !$_.Exists })
if ($missing.Count) {
    $missing | Format-Table -AutoSize | Out-String | Write-Output
    throw "$($missing.Count) missing local link targets; see link_checks.csv"
}
$results.Add("PASS: $($links.Count) local Markdown link destinations exist.")

Push-Location $repo
try {
    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }
    git apply --reverse --check experiments/pre_route_20261122/sv_diff/final_rtl.diff
    if ($LASTEXITCODE -ne 0) { throw 'Main reverse-patch check failed' }
    git apply --reverse --check --directory=experiments/pre_route_20261122/power/du_repair/candidate_v2/src experiments/pre_route_20261122/sv_diff/final_rtl.diff
    if ($LASTEXITCODE -ne 0) { throw 'Candidate reverse-patch check failed' }
    git apply --reverse --check experiments/pre_route_20261122/sv_diff/verification_additions.diff
    if ($LASTEXITCODE -ne 0) { throw 'Verification additions check failed' }
} finally { Pop-Location }
$results.Add('PASS: git diff --check and all three read-only patch consistency checks.')
$results.Add('NOT RUN: RTL simulation, synthesis, implementation, and power; this is a documentation-only update.')
$results | Set-Content -Encoding utf8 (Join-Path $record 'validation.txt')
$results
