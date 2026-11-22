# Reopen the completed candidate route and run the production OOC audit.
if {$argc != 2} {error "Expected ROUTED_CHECKPOINT NEW_AUDIT_DIRECTORY"}
set repo [file normalize [file join [file dirname [info script]] ../..]]
source [file join $repo project_integration scripts check_bram_100mhz.tcl]
open_checkpoint [file normalize [lindex $argv 0]]
set memories [get_cells -hier -filter {NAME =~ u_bridge/* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS* || REF_NAME =~ RAM16* || REF_NAME =~ RAM32* || REF_NAME =~ RAM64*)}]
if {![llength $memories]} {error "No distributed RAM primitives in the packet bridge"}
puts "Bridge distributed RAM primitives: [llength $memories]"
check_bram_100mhz [file normalize [lindex $argv 1]]
