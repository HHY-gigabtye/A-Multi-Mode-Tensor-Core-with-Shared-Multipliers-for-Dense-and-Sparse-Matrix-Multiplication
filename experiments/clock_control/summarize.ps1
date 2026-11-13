param([Parameter(Mandatory=$true)][string[]]$Trials)
$ErrorActionPreference = 'Stop'
$rows = foreach ($trial in $Trials) {
    $runDir = Join-Path $PSScriptRoot "$trial"
    $timing = Get-Content -Raw (Join-Path $runDir 'timing_summary_routed.rpt')
    $util = Get-Content -Raw (Join-Path $runDir 'utilization_placed.rpt')
    $routedUtil = Get-Content -Raw (Join-Path $runDir 'utilization_routed.rpt')
    $route = Get-Content -Raw (Join-Path $runDir 'route_status.rpt')
    $summary = [regex]::Match($timing, '(?m)^\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+')
    $clock = [regex]::Match($timing, '(?m)^clk\s+\{[^}]+\}\s+(\d+\.\d+)\s+')
    $errors = [regex]::Match($route, 'nets with routing errors\.+\s+:\s+(\d+)')
    if (!$summary.Success -or !$clock.Success -or !$errors.Success) { throw "Incomplete reports: $trial" }
    $period = [double]::Parse($clock.Groups[1].Value, [cultureinfo]::InvariantCulture)
    $wns = [double]::Parse($summary.Groups[1].Value, [cultureinfo]::InvariantCulture)
    [pscustomobject]@{
        Trial = $trial
        Phase = 'post-route'
        Period_ns = $period
        Target_MHz = [math]::Round(1000 / $period, 3)
        WNS_ns = $wns
        TNS_ns = $summary.Groups[2].Value
        WHS_ns = $summary.Groups[5].Value
        Slack_estimate_MHz = [math]::Round(1000 / ($period - $wns), 3)
        Placed_LUTs = [regex]::Match($util, '\| Slice LUTs\s+\|\s+(\d+)').Groups[1].Value
        Placed_Registers = [regex]::Match($util, '\| Slice Registers\s+\|\s+(\d+)').Groups[1].Value
        Routed_LUTs = [regex]::Match($routedUtil, '\| Slice LUTs\s+\|\s+(\d+)').Groups[1].Value
        Routed_Registers = [regex]::Match($routedUtil, '\| Slice Registers\s+\|\s+(\d+)').Groups[1].Value
        DSPs = [regex]::Match($util, '\| DSPs\s+\|\s+(\d+)').Groups[1].Value
        Routing_errors = $errors.Groups[1].Value
        Source = [regex]::Match($timing, 'Source:\s+([^\r\n]+)').Groups[1].Value
        Destination = [regex]::Match($timing, 'Destination:\s+([^\r\n]+)').Groups[1].Value
        Path_delay = [regex]::Match($timing, 'Data Path Delay:\s+([^\r\n]+)').Groups[1].Value
    }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot 'comparison.csv')
$rows | Format-List
