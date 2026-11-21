# Validate this native run's own routed design. Never import an archived DCP.
set bram_hook_dir [file dirname [file normalize [info script]]]
source [file join $bram_hook_dir check_bram_100mhz.tcl]
set bram_hook_output [file join [pwd] bram_audit_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
check_bram_100mhz $bram_hook_output
