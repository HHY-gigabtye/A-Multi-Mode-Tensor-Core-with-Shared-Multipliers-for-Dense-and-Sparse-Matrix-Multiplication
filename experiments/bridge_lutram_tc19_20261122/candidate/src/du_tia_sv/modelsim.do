transcript on

if {![file exists du_tia_work]} {
  vlib du_tia_work
}
vmap du_tia_work du_tia_work

vlog -work du_tia_work -sv rtl/du_tia_pkg.sv
vlog -work du_tia_work -sv rtl/du_tia.sv
vlog -work du_tia_work -sv tb/tb_du_tia.sv

vsim du_tia_work.tb_du_tia
run -all
