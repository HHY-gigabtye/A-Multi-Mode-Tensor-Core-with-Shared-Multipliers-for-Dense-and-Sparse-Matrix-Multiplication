$ErrorActionPreference = 'Stop'
function Get-Resource([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, '(?m)^\|\s*' + [regex]::Escape($Name) + '\*?\s*\|\s*(\d+(?:\.\d+)?)\s*\|')
    if (!$match.Success) { throw "Missing utilization row: $Name" }
    return [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
}
$stages = @(
    @{Name='synthesis';Phase='post-synthesis';Util='fresh/default/utilization_synth.rpt';Timing='fresh/default/timing_synth.rpt'},
    @{Name='default';Phase='post-route';Util='fresh/default/utilization_routed.rpt';Timing='fresh/default/timing_summary_routed.rpt'},
    @{Name='refined';Phase='post-route';Util='fresh/refined/utilization_routed.rpt';Timing='fresh/refined/timing_summary_routed.rpt'},
    @{Name='replicated';Phase='post-route';Util='replicated/utilization_routed.rpt';Timing='replicated/timing_summary_routed.rpt'},
    @{Name='closure';Phase='post-route';Util='closure/utilization_routed.rpt';Timing='closure/timing_summary_routed.rpt'},
    @{Name='margin_restored_10ns';Phase='post-route';Util='margin_9p75/timing_closed_utilization.rpt';Timing='margin_9p75/timing_closed.rpt'},
    @{Name='final';Phase='post-route';Util='final_10ns/timing_closed_utilization.rpt';Timing='final_10ns/timing_closed.rpt'}
)
$trials = @(
    @{Name='baseline';Root='baseline/implementation';Stages=$stages},
    @{Name='banked';Root='banked/implementation';Stages=$stages},
    @{Name='banked_measured';Root='banked/measured';Stages=$stages},
    @{Name='banked_incremental';Root='banked/incremental_forced';Stages=@(
        @{Name='default';Phase='post-route';Util='default/utilization_routed.rpt';Timing='default/timing_summary_routed.rpt'},
        @{Name='refined';Phase='post-route';Util='refined/utilization_routed.rpt';Timing='refined/timing_summary_routed.rpt'})},
    @{Name='archived_baseline_reopened';Root='archived_baseline_audit';Stages=@(
        @{Name='audit';Phase='post-route';Util='utilization.rpt';Timing='timing_summary.rpt'})},
    @{Name='baseline_reopened';Root='baseline/final_audit';Stages=@(
        @{Name='audit';Phase='post-route';Util='utilization.rpt';Timing='timing_summary.rpt'})},
    @{Name='banked_reopened';Root='banked/final_audit';Stages=@(
        @{Name='audit';Phase='post-route';Util='utilization.rpt';Timing='timing_summary.rpt'})},
    @{Name='banked_incremental_reopened';Root='banked/incremental_audit';Stages=@(
        @{Name='audit';Phase='post-route';Util='utilization.rpt';Timing='timing_summary.rpt'})}
)
$rows = foreach ($trial in $trials) {
    foreach ($stage in $trial.Stages) {
        $root = Join-Path $PSScriptRoot $trial.Root
        $utilPath = Join-Path $root $stage.Util
        $timingPath = Join-Path $root $stage.Timing
        if (!(Test-Path -LiteralPath $utilPath) -or !(Test-Path -LiteralPath $timingPath)) { continue }
        $util = Get-Content -Raw -LiteralPath $utilPath
        $timing = Get-Content -Raw -LiteralPath $timingPath
        $summary = [regex]::Match($timing, '(?m)^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+')
        if (!$summary.Success) { continue } # A report still being written is not evidence.
        [pscustomobject]@{
            Trial=$trial.Name; Stage=$stage.Name; Phase=$stage.Phase; Period_ns=10.000
            LUT=(Get-Resource $util 'Slice LUTs'); FF=(Get-Resource $util 'Slice Registers')
            BRAM36_tiles=(Get-Resource $util 'Block RAM Tile'); DSP=(Get-Resource $util 'DSPs')
            WNS_ns=$summary.Groups[1].Value; TNS_ns=$summary.Groups[2].Value
            Setup_failing_endpoints=$summary.Groups[3].Value
            WHS_ns=$summary.Groups[5].Value; THS_ns=$summary.Groups[6].Value
            Hold_failing_endpoints=$summary.Groups[7].Value
            Utilization_report=$utilPath; Timing_report=$timingPath
        }
    }
}
$rows | Export-Csv -NoTypeInformation (Join-Path $PSScriptRoot 'timing_resource_comparison.csv')
$rows | Select-Object Trial,Stage,Phase,LUT,FF,BRAM36_tiles,DSP,WNS_ns,TNS_ns,WHS_ns,THS_ns | Format-Table -AutoSize
