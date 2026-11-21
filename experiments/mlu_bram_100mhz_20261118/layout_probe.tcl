# Read-only physical inventory for interpreting measured congestion.
if {$argc != 2} {error "Expected CHECKPOINT NEW_OUTPUT_DIR"}
set layout_input [file normalize [lindex $argv 0]]
set layout_output [file normalize [lindex $argv 1]]
if {[file exists $layout_output]} {error "Preserve existing inventory"}
file mkdir $layout_output
cd $layout_output
set_param general.maxThreads 1
open_checkpoint $layout_input
set fd [open clock_regions.tsv w]
puts $fd "region\tslice_sites\tramb36_sites\tslice_min_x\tslice_max_x\tslice_min_y\tslice_max_y"
foreach region [lsort [get_clock_regions]] {
    set slices [get_sites -of_objects $region -filter {SITE_TYPE =~ SLIC*}]
    set rams [get_sites -of_objects $region -filter {SITE_TYPE == RAMB36E1}]
    set xs {}; set ys {}
    foreach site $slices {
        if {[regexp {SLICE_X(\d+)Y(\d+)} $site all x y]} {lappend xs $x; lappend ys $y}
    }
    if {[llength $xs] == 0} {error "No slice coordinates in $region"}
    set xs [lsort -integer $xs]; set ys [lsort -integer $ys]
    puts $fd "$region\t[llength $slices]\t[llength $rams]\t[lindex $xs 0]\t[lindex $xs end]\t[lindex $ys 0]\t[lindex $ys end]"
}
close $fd
set fd [open module_regions.tsv w]
puts $fd "module\tregion\tprimitive_count"
foreach module {u_mlu u_du_tia u_bridge u_tensor_core u_msu} {
    set counts [dict create]
    foreach cell [get_cells -hier -filter "IS_PRIMITIVE == 1 && NAME =~ $module/*"] {
        set loc [get_property LOC $cell]
        if {$loc eq ""} {continue}
        set site [get_sites -quiet $loc]
        if {[llength $site] != 1} {continue}
        set region [get_clock_regions -of_objects $site]
        dict incr counts $region
    }
    dict for {region count} $counts {puts $fd "$module\t$region\t$count"}
}
close $fd
set fd [open ram_locations.tsv w]
puts $fd "cell\tlocation\tmode"
foreach cell [get_cells -hier -filter {REF_NAME == RAMB36E1}] {
    puts $fd "$cell\t[get_property LOC $cell]\t[get_property RAM_MODE $cell]"
}
close $fd
puts "LAYOUT_READ_ONLY_PROBE_COMPLETE"
