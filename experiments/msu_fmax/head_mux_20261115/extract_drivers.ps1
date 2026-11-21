param(
    [Parameter(Mandatory=$true)][string[]]$Reports,
    [Parameter(Mandatory=$true)][string]$OutputCsv,
    [double]$SlackLimitNs = 0.300,
    [double]$RouteLimitNs = 1.000
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputCsv) { throw "Use a new output file: $OutputCsv" }
$observations = @(
    foreach ($report in $Reports) {
        $reportText = Get-Content -Raw -LiteralPath $report
        foreach ($block in ([regex]::Split($reportText, '(?m)^Slack \(') | Select-Object -Skip 1)) {
            $slackMatch = [regex]::Match($block, '^[A-Z]+\)\s*:\s*(-?[0-9.]+)ns')
            if (!$slackMatch.Success) { throw "Unrecognized slack in $report" }
            $slack = [double]::Parse($slackMatch.Groups[1].Value, [cultureinfo]::InvariantCulture)
            if ($slack -ge $SlackLimitNs) { continue }
            $startpoint = [regex]::Match($block, '(?m)^\s*Source:\s*(\S+)').Groups[1].Value
            $endpoint = [regex]::Match($block, '(?m)^\s*Destination:\s*(\S+)').Groups[1].Value
            if (!$startpoint -or !$endpoint) { throw "Missing endpoint in $report" }
            $lines = $block -split '\r?\n'
            for ($lineIndex = 0; $lineIndex -lt $lines.Count-1; $lineIndex++) {
                $lutMatch = [regex]::Match($lines[$lineIndex], '^\s+\S+\s+(LUT[1-6])\s+\(Prop_\S+\)\s+[0-9.]+\s+[0-9.]+\s+[rf]\s+(\S+)/O\s*$')
                if (!$lutMatch.Success) { continue }
                $netMatch = [regex]::Match($lines[$lineIndex+1], '^\s+net \(fo=(\d+), routed\)\s+([0-9.]+)\s+[0-9.]+\s+(\S+)\s*$')
                if (!$netMatch.Success) { continue }
                $routeDelay = [double]::Parse($netMatch.Groups[2].Value, [cultureinfo]::InvariantCulture)
                $fanout = [int]$netMatch.Groups[1].Value
                if ($routeDelay -lt $RouteLimitNs -or $fanout -lt 2) { continue }
                [pscustomobject]@{
                    Driver = $lutMatch.Groups[2].Value
                    RefType = $lutMatch.Groups[1].Value
                    Net = $netMatch.Groups[3].Value
                    Fanout = $fanout
                    RouteNs = $routeDelay
                    SlackNs = $slack
                    Startpoint = $startpoint
                    Endpoint = $endpoint
                    Report = $report
                }
            }
        }
    }
)
if ($observations.Count -eq 0) { throw 'No matching routed LUT-driver observations' }
$drivers = foreach ($driverGroup in ($observations | Group-Object Driver)) {
    # Keep one actual path observation intact; do not combine fields from
    # different paths into a fictitious representative path.
    $representative = $driverGroup.Group | Sort-Object RouteNs -Descending | Select-Object -First 1
    $representative | Add-Member -NotePropertyName WorstObservedSlackNs -NotePropertyValue (($driverGroup.Group | Measure-Object SlackNs -Minimum).Minimum)
    $representative | Add-Member -NotePropertyName Observations -NotePropertyValue $driverGroup.Count
    $representative
}
$drivers | Sort-Object RouteNs -Descending | Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $OutputCsv
"Extracted $($drivers.Count) measured LUT drivers from $($observations.Count) observations."
