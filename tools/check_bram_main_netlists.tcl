# Re-synthesize both changed main modules and rerun immutable cycle comparisons.
if {$argc != 1} {error "Expected NEW_OUTPUT_DIR"}
set main_eq_root [file normalize [file join [file dirname [info script]] ..]]
set main_eq_output [file normalize [lindex $argv 0]]
if {[file exists $main_eq_output]} {error "Preserve previous netlist tests"}
file mkdir $main_eq_output
set argv [list $main_eq_root [file join $main_eq_output mlu_synthesis]]
set argc 2
source [file join $main_eq_root experiments mlu_bram_20261118 probe_mlu.tcl]
if {[llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]] != 18} {error "Expected 18 MLU BRAMs"}
close_project
set argv [list $main_eq_root [file join $main_eq_output mlu_synthesis mlu_netlist.v] [file join $main_eq_output mlu_equivalence]]
set argc 3
source [file join $main_eq_root experiments mlu_bram_20261118 equiv.tcl]
close_project
set argv [list $main_eq_root [file join $main_eq_output bridge_equivalence]]
set argc 2
source [file join $main_eq_root experiments mlu_bram_100mhz_20261118 bridge_netlist_check.tcl]
close_project
set fd [open [file join $main_eq_output PASS.txt] w]
puts $fd "PASS newly synthesized main MLU and Bridge observable-cycle comparisons against original RTL and immutable C vectors"
close $fd
puts "MAIN_BRAM_NETLISTS_PASS"
