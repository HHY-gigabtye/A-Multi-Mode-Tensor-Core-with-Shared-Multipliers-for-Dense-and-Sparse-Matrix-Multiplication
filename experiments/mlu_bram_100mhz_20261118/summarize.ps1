# Summarize completed routes only. Placement/intermediate router estimates
# never enter this comparison. Original reports are read-only.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$routes = @(
    @{ Name='Original FF baseline'; Path='experiments/mlu_bram_20261118/baseline/final_audit'; Timing='timing_summary.rpt'; Util='utilization.rpt' },
    @{ Name='Previous 18-BRAM candidate'; Path='experiments/mlu_bram_20261118/banked/final_audit'; Timing='timing_summary.rpt'; Util='utilization.rpt' },
    @{ Name='36 BRAM predecode'; Path='experiments/mlu_bram_100mhz_20261118/predecode/implementation' },
    @{ Name='36 BRAM refined'; Path='experiments/mlu_bram_100mhz_20261118/predecode/refined' },
    @{ Name='36 BRAM 64-driver replication'; Path='experiments/mlu_bram_100mhz_20261118/predecode/targeted/measured/replicated' },
    @{ Name='36 BRAM second refinement'; Path='experiments/mlu_bram_100mhz_20261118/predecode/targeted/refined' },
    @{ Name='18 BRAM active cache'; Path='experiments/mlu_bram_100mhz_20261118/head_cache_fast/flow/initial' },
    @{ Name='18 BRAM cache replication'; Path='experiments/mlu_bram_100mhz_20261118/head_cache_fast/flow/targeted/replicated' },
    @{ Name='18 BRAM cache refinement'; Path='experiments/mlu_bram_100mhz_20261118/head_cache_fast/flow/refined' },
    @{ Name='18 BRAM early prefetch'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/flow/initial' },
    @{ Name='18 BRAM MSU floorplan'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/msu_top' },
    @{ Name='18 BRAM local dense ACC'; Path='experiments/mlu_bram_100mhz_20261118/dense_acc_local/flow/initial' },
    @{ Name='18 BRAM prefetch refined'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/refined' },
    @{ Name='18 BRAM shared dense ACC'; Path='experiments/mlu_bram_100mhz_20261118/dense_acc_shared/flow/initial' },
    @{ Name='18 BRAM grouped Bridge mux'; Path='experiments/mlu_bram_100mhz_20261118/grouped_mux/flow/initial' },
    @{ Name='18 BRAM routed refine 1'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/routed_refine/stage1' },
    @{ Name='18 BRAM routed refine 2'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/routed_refine/stage2' },
    @{ Name='18 BRAM routed refine 3'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/routed_refine/stage3' },
    @{ Name='18 BRAM direct TC guard'; Path='experiments/mlu_bram_100mhz_20261118/direct_guard/flow/initial' },
    @{ Name='18 BRAM four measured drivers'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/four_drivers' },
    @{ Name='18 BRAM rotating physical FIFO'; Path='experiments/mlu_bram_100mhz_20261118/rotating_fifo/flow/initial' },
    @{ Name='18 BRAM four-driver refine 1'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/four_refined/stage1' },
    @{ Name='18 BRAM four-driver refine 2'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/four_refined/stage2' },
    @{ Name='18 BRAM four-driver refine 3'; Path='experiments/mlu_bram_100mhz_20261118/early_prefetch/four_refined/stage3' },
    @{ Name='18 BRAM MSU range reduction'; Path='experiments/mlu_bram_100mhz_20261118/msu_addr_reduce/flow/incremental' }
)
function Read-Match([string]$Text,[string]$Pattern,[string]$Description) {
    $found = [regex]::Match($Text,$Pattern)
    if (!$found.Success) { throw "Missing report field: $Description" }
    return $found.Groups[1].Value
}
$rows = foreach ($entry in $routes) {
    $folder = Join-Path $repo $entry.Path
    $timingName = if ($entry.Timing) { $entry.Timing } else { 'timing_summary_routed.rpt' }
    $utilName = if ($entry.Util) { $entry.Util } else { 'utilization_routed.rpt' }
    $routePath = Join-Path $folder 'route_status.rpt'
    if (!(Test-Path -LiteralPath $routePath)) { continue }
    $timing = Get-Content -Raw -LiteralPath (Join-Path $folder $timingName)
    $util = Get-Content -Raw -LiteralPath (Join-Path $folder $utilName)
    $route = Get-Content -Raw -LiteralPath $routePath
    $routable = [int](Read-Match $route '# of routable nets\.+\s*:\s*(\d+)' 'routable nets')
    $routed = [int](Read-Match $route '# of fully routed nets\.+\s*:\s*(\d+)' 'routed nets')
    $routeErrors = [int](Read-Match $route '# of nets with routing errors\.+\s*:\s*(\d+)' 'route errors')
    if ($routable -ne $routed -or $routeErrors -ne 0) { throw "Incomplete route: $($entry.Name)" }
    $values = [regex]::Match($timing,'(?m)^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)')
    if (!$values.Success) { throw "Missing timing summary: $($entry.Name)" }
    $wns = [double]::Parse($values.Groups[1].Value,[cultureinfo]::InvariantCulture)
    $whs = [double]::Parse($values.Groups[5].Value,[cultureinfo]::InvariantCulture)
    [pscustomobject]@{
        Version = $entry.Name
        Phase = 'FPGA OOC post-route'
        Clock_ns = 10.000
        LUT = [int](Read-Match $util '\| Slice LUTs\*?\s*\|\s*(\d+)' 'LUT')
        FF = [int](Read-Match $util '\|\s*Register as Flip Flop\s*\|\s*(\d+)' 'FF')
        BRAM36 = [int](Read-Match $util '\|\s*RAMB36/FIFO\*?\s*\|\s*(\d+)' 'BRAM36')
        DSP48 = [int](Read-Match $util '\|\s*DSPs\s*\|\s*(\d+)' 'DSP48')
        WNS_ns = $wns
        TNS_ns = $values.Groups[2].Value
        Failing_setup_endpoints = [int]$values.Groups[3].Value
        WHS_ns = $whs
        THS_ns = $values.Groups[6].Value
        Routed_nets = $routed
        Setup_hold_met_10ns = ($wns -ge 0 -and $whs -ge 0)
        Report_directory = $folder
    }
}
$rows | Export-Csv -LiteralPath (Join-Path $PSScriptRoot 'ppa_progress.csv') -NoTypeInformation -Encoding utf8
$rows | Format-Table Version,LUT,FF,BRAM36,@{Name='WNS_ns';Expression={$_.WNS_ns.ToString('F3')}},@{Name='WHS_ns';Expression={$_.WHS_ns.ToString('F3')}},Setup_hold_met_10ns -AutoSize
