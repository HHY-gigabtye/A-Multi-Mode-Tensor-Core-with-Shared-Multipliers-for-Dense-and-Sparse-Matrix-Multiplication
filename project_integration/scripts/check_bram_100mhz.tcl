# Audit the currently open implemented design without changing its constraints.
proc check_bram_100mhz {output} {
    if {[file exists $output]} {error "Preserve previous audit: $output"}
    file mkdir $output
    if {[get_property PART [current_design]] ne "xc7z020clg484-1"} {error "Unexpected device"}
    if {[llength [get_clocks]] != 1 || [get_property NAME [get_clocks]] ne "clk" ||
        abs([get_property PERIOD [get_clocks clk]] - 10.000) > 0.000001} {
        error "Expected the single 10.000 ns clock"
    }
    report_clocks -file [file join $output clocks.rpt]
    report_timing_summary -max_paths 20 -report_unconstrained -file [file join $output timing_summary.rpt]
    report_timing -delay_type max -max_paths 100 -input_pins -file [file join $output critical_paths.rpt]
    report_utilization -file [file join $output utilization.rpt]
    report_route_status -file [file join $output route_status.rpt]
    report_exceptions -file [file join $output exceptions.rpt]
    report_drc -file [file join $output drc.rpt]
    if {[llength [get_drc_violations -filter {SEVERITY == Error}]] != 0} {error "DRC errors"}
    set brams [get_cells -hier -filter {REF_NAME == RAMB36E1}]
    if {[llength $brams] != 18 || [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]] != 0} {
        error "Expected 18 RAMB36E1 and no RAMB18E1"
    }
    foreach ram $brams {
        foreach {property expected} {
            RAM_MODE SDP READ_WIDTH_A 72 READ_WIDTH_B 0 WRITE_WIDTH_A 0
            WRITE_WIDTH_B 72 DOA_REG 0 DOB_REG 0
            WRITE_MODE_A READ_FIRST WRITE_MODE_B READ_FIRST
        } {
            if {[get_property $property $ram] ne $expected} {error "BRAM configuration changed: $ram / $property"}
        }
    }
    set dsps [get_cells -hier -filter {REF_NAME == DSP48E1}]
    if {[llength $dsps] != 64} {error "Expected 64 outer-product DSP48E1s"}
    foreach dsp $dsps {
        foreach property {AREG BREG MREG} {
            if {[get_property $property $dsp] != 0} {error "DSP pipeline changed: $dsp / $property"}
        }
        if {[get_property PREG $dsp] != 1} {error "Missing registered product: $dsp"}
    }
    report_drc -checks [get_drc_checks REQP-1839] -file [file join $output bram_control_drc.rpt]
    set fd [open [file join $output bram_control_drc.rpt] r]
    set controls [read $fd]
    close $fd
    if {![regexp {Violations found:\s*0\s} $controls]} {error "BRAM control DRC failed"}
    set fd [open [file join $output route_status.rpt] r]
    set routes [read $fd]
    close $fd
    foreach {pattern variable} {
        {# of routable nets\.+\s*:\s*(\d+)} routable
        {# of fully routed nets\.+\s*:\s*(\d+)} routed
        {# of nets with routing errors\.+\s*:\s*(\d+)} errors
    } {
        if {![regexp $pattern $routes all $variable]} {error "Missing route status: $variable"}
    }
    if {$routed != $routable || $errors != 0} {error "Routing incomplete or erroneous"}
    set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    if {$setup eq "" || $hold eq "" || $setup < 0 || $hold < 0} {
        error "100 MHz timing failed: setup=$setup hold=$hold"
    }
    set fd [open [file join $output PASS.txt] w]
    puts $fd "PASS internal FPGA OOC post-route STA, 10.000 ns"
    puts $fd "setup_slack_ns=$setup hold_slack_ns=$hold routed_nets=$routed"
    puts $fd "18 RAMB36E1; 64 DSP48E1 (PREG=1); DRC errors=0; REQP-1839 violations=0; routing errors=0"
    close $fd
    puts "NATIVE_BRAM_100MHZ_PASS setup=$setup hold=$hold routed=$routed"
}
