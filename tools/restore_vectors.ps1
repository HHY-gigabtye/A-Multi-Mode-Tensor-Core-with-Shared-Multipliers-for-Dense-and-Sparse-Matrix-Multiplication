# Restore the unchanged TC golden vectors distributed as gzip.
# Requires PowerShell 5.1+; no C compiler, Python, or Git LFS required.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'tensor_core_sv/c_vectors.txt'
$archive = "$target.gz"
$expected = '95906DB99B23A97FDF4580A768C481B861C2983F017742E513711DBEE3D39935'
if (Test-Path -LiteralPath $target) {
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expected) {
        throw 'Existing c_vectors.txt differs from the published baseline. No file was overwritten.'
    }
    Write-Host 'TC vectors already present; SHA-256 verified.'
    exit 0
}
$temporary = "$target.$([guid]::NewGuid().ToString('N')).tmp"
try {
    $inputStream = [IO.File]::OpenRead($archive)
    try {
        $gzip = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
        try {
            $outputStream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew)
            try { $gzip.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $inputStream.Dispose() }
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $expected) {
        throw 'Restored vector SHA-256 mismatch; c_vectors.txt was not installed.'
    }
    [IO.File]::Move($temporary, $target)
    Write-Host 'TC vectors restored; SHA-256 verified.'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
