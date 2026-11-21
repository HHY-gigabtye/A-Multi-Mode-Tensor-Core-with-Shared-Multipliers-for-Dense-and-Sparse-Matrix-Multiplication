# Run in the synthesized design before spending time on placement/routing.
# Verify the intended DSP mapping and the absence of a validation-driven CEP.
set shadow_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1 && NAME =~ u_tensor_core/g_arithmetic*product_q_reg*}]
if {[llength $shadow_dsps] != 64} {error "Expected 64 sparse product DSPs"}
set shadow_fd [open product_shadow_mapping.txt w]
foreach shadow_dsp $shadow_dsps {
    foreach {shadow_property shadow_expected} {AREG 0 BREG 0 MREG 0 PREG 1} {
        if {[get_property $shadow_property $shadow_dsp] != $shadow_expected} {
            error "Unexpected $shadow_property on $shadow_dsp"
        }
    }
    set shadow_cep [get_pins -of_objects $shadow_dsp -filter {REF_PIN_NAME == CEP}]
    set shadow_nets [get_nets -segments -of_objects $shadow_cep]
    set shadow_drivers [get_pins -of_objects $shadow_nets -filter {DIRECTION == OUT}]
    set shadow_driver_cells [get_cells -of_objects $shadow_drivers]
    if {[llength $shadow_driver_cells] != 1 || [get_property REF_NAME $shadow_driver_cells] ne "VCC"} {
        error "Sparse DSP CEP is not constant high: $shadow_dsp, drivers=$shadow_driver_cells"
    }
    puts $shadow_fd "$shadow_dsp AREG=0 BREG=0 MREG=0 PREG=1 CEP=VCC"
}
close $shadow_fd
puts "PRODUCT_SHADOW_MAPPING_PASS count=64 CEP=VCC PREG=1"
