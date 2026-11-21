# Read-only audit of the standalone synthesized physical RAM implementation.
if {$argc != 2} {error "Expected INPUT_DCP NEW_OUTPUT_DIR"}
set input_dcp [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} {error "Preserve previous audit"}
file mkdir $output_dir
cd $output_dir
set_param general.maxThreads 4
open_checkpoint $input_dcp
report_drc -checks [get_drc_checks REQP-1839] -file bram_control_drc.rpt
set brams [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]
if {[llength $brams] != 36} {error "Expected 36 RAMB36E1 primitives"}
set fd [open bram_modes.tsv w]
puts $fd "cell\tmode\twrite_mode_a\twrite_mode_b\tdoa_reg\tdob_reg"
foreach cell $brams {
    puts $fd "$cell\t[get_property RAM_MODE $cell]\t[get_property WRITE_MODE_A $cell]\t[get_property WRITE_MODE_B $cell]\t[get_property DOA_REG $cell]\t[get_property DOB_REG $cell]"
}
close $fd
puts "BRAM_CONTROL_AUDIT_COMPLETE count=[llength $brams]"
