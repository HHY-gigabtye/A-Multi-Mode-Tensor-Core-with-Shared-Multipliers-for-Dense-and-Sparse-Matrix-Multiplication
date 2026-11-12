$ErrorActionPreference = 'Stop'
$taskRepo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$taskVectors = Join-Path $taskRepo 'tensor_core_sv/c_vectors.txt'
$taskCompressed = [System.IO.File]::OpenRead((Join-Path $taskRepo 'tensor_core_sv/c_vectors.txt.gz'))
$taskGzip = [System.IO.Compression.GZipStream]::new($taskCompressed, [System.IO.Compression.CompressionMode]::Decompress)
$taskHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $taskExpectedHash = [Convert]::ToHexString($taskHasher.ComputeHash($taskGzip))
} finally {
    $taskHasher.Dispose()
    $taskGzip.Dispose()
    $taskCompressed.Dispose()
}
$taskActualHash = (Get-FileHash -LiteralPath $taskVectors -Algorithm SHA256).Hash
if ($taskExpectedHash -ne $taskActualHash) { throw 'Uncompressed vectors differ from the pinned matching gzip' }
Write-Output "VECTOR_CONTENT_SHA256=$taskActualHash"

# Read the existing golden tick_info records; do not alter vectors or TB.
# tc_tick_info_t: accepted[22], sparse_step[20], result_accepted[19],
# input_first[18], result_produced[16], route[14], acc[13], acc_last[11].
$taskRecord = 0
$taskFirst = $null
$taskFound = @{}
foreach ($taskLine in [System.IO.File]::ReadLines($taskVectors)) {
    $taskRecord++
    $taskFields = $taskLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($taskFields.Count -ne 13) { throw "Unexpected record $taskRecord" }
    if ($taskFields[0] -eq '1') { $taskFirst = $null; continue }
    $taskInfo = [Convert]::ToUInt32($taskFields[7], 16)
    if ($null -eq $taskFirst -and ($taskInfo -band (1 -shl 18))) {
        $taskMode = if ($taskInfo -band (1 -shl 20)) { 'sparse' } else { 'dense' }
        $taskFirst = @{ mode=$taskMode; first_record=$taskRecord; inputs=[System.Collections.Generic.List[int]]::new(); clean=$true; ready=$true; done=$false }
    }
    if ($null -eq $taskFirst -or $taskFirst.done) { continue }
    if ($taskFields[6] -ne '0') { $taskFirst.clean = $false }
    if ($taskFields[2] -ne '1') { $taskFirst.ready = $false }
    if (($taskInfo -band (1 -shl 22)) -and $taskFirst.inputs.Count -lt 8) { $taskFirst.inputs.Add($taskRecord) }
    if (($taskInfo -band (1 -shl 14)) -and !$taskFirst.ContainsKey('first_route_record')) { $taskFirst.first_route_record = $taskRecord }
    if (($taskInfo -band (1 -shl 13)) -and !$taskFirst.ContainsKey('first_acc_record')) { $taskFirst.first_acc_record = $taskRecord }
    if (($taskInfo -band (1 -shl 11)) -and !$taskFirst.ContainsKey('last_acc_record')) { $taskFirst.last_acc_record = $taskRecord }
    if (($taskInfo -band (1 -shl 16)) -and !$taskFirst.ContainsKey('produced_record')) { $taskFirst.produced_record = $taskRecord }
    if (($taskInfo -band (1 -shl 19)) -and $taskFirst.ContainsKey('produced_record')) {
        $taskFirst.done = $true
        $taskContiguous = $taskFirst.inputs.Count -eq 8
        for ($taskIndex = 0; $taskIndex -lt $taskFirst.inputs.Count; $taskIndex++) {
            if ($taskFirst.inputs[$taskIndex] -ne $taskFirst.first_record + $taskIndex) { $taskContiguous = $false }
        }
        if ($taskContiguous -and $taskFirst.clean -and $taskFirst.ready -and !$taskFound.ContainsKey($taskFirst.mode)) {
            $taskFound[$taskFirst.mode] = [ordered]@{
                mode=$taskFirst.mode
                first_input_record=$taskFirst.first_record
                last_input_record=$taskFirst.inputs[7]
                first_route_record=$taskFirst.first_route_record
                first_acc_record=$taskFirst.first_acc_record
                last_acc_record=$taskFirst.last_acc_record
                result_produced_record=$taskFirst.produced_record
                result_accepted_record=$taskRecord
                produced_offset=$taskFirst.produced_record - $taskFirst.first_record
                accepted_offset=$taskRecord - $taskFirst.first_record
            }
        }
    }
    if ($taskFound.Count -eq 2) { break }
}
if ($taskFound.Count -ne 2) { throw 'No unstalled dense/sparse examples found' }
$taskNominal = @($taskFound.dense, $taskFound.sparse)
$taskNominal | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'nominal_cycles.json') -Encoding utf8
$taskNominal | ConvertTo-Json -Depth 4
