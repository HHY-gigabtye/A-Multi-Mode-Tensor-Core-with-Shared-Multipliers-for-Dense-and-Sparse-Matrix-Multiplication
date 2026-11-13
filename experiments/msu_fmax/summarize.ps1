$ErrorActionPreference = 'Stop'
$rows = foreach ($report in (Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter timing_summary_routed.rpt)) {
    $text = Get-Content -LiteralPath $report.FullName -Raw
    $timing = [regex]::Match($text, '(?m)^\s*([\d.-]+)\s+([\d.-]+)\s+(\d+)\s+(\d+)\s+([\d.-]+)\s+([\d.-]+)\s+(\d+)\s+(\d+)\s+[\d.-]+\s+[\d.-]+\s+\d+\s+\d+\s*$')
    $clock = [regex]::Match($text, '(?m)^clk\s+\{[^}]+\}\s+([\d.]+)\s+([\d.]+)')
    $path = [regex]::Match($text, '(?s)Max Delay Paths.*?Source:\s*(\S+).*?Destination:\s*(\S+).*?Data Path Delay:\s*([\d.]+)ns\s*\(logic ([\d.]+)ns.*?route ([\d.]+)ns')
    if (!$timing.Success -or !$clock.Success -or !$path.Success) { throw "Unrecognized timing report: $($report.FullName)" }
    $period = [double]$clock.Groups[1].Value
    $wns = [double]$timing.Groups[1].Value
    $util = Get-Content -Raw (Join-Path $report.DirectoryName 'utilization_routed.rpt')
    $route = Get-Content -Raw (Join-Path $report.DirectoryName 'route_status.rpt')
    [pscustomobject]@{
        Run=$report.DirectoryName.Substring($PSScriptRoot.Length+1).Replace('\','/')
        Period_ns=$period; Target_MHz=[double]$clock.Groups[2].Value
        WNS_ns=$wns; TNS_ns=[double]$timing.Groups[2].Value
        WHS_ns=[double]$timing.Groups[5].Value
        Routed_LUTs=[regex]::Match($util, '\| Slice LUTs\s+\|\s+(\d+)').Groups[1].Value
        Registers=[regex]::Match($util, '\| Slice Registers\s+\|\s+(\d+)').Groups[1].Value
        DSPs=[regex]::Match($util, '\| DSPs\s+\|\s+(\d+)').Groups[1].Value
        RoutingErrors=[regex]::Match($route, 'nets with routing errors\.+\s+:\s+(\d+)').Groups[1].Value
        SlackDerived_MHz=[math]::Round(1000/($period-$wns),3)
        Source=$path.Groups[1].Value; Destination=$path.Groups[2].Value
        Data_ns=$path.Groups[3].Value; Logic_ns=$path.Groups[4].Value; Route_ns=$path.Groups[5].Value
    }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot 'comparison.csv')
$rows | Format-Table Run,Period_ns,WNS_ns,TNS_ns,WHS_ns,SlackDerived_MHz -AutoSize
