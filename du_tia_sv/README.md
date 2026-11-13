# DU + TIA SystemVerilog RTL — No-Assertion Version

This version targets ModelSim–Intel FPGA Edition installations without
SystemVerilog Assertions support. The RTL, testbench, file list, and build flow
contain no `assert property`, SVA checkers, coverage properties, or `--assert`
options.

## Contents

| File | Purpose |
|---|---|
| `rtl/du_tia_pkg.sv` | Compact types, packed unions, and helper functions |
| `rtl/du_tia.sv` | Four-stage DU/TIA pipeline without assertions |
| `tb/tb_du_tia.sv` | Golden model, scoreboard, and 3292 functional tests |
| `filelist.f` | Package, RTL, and testbench compilation order |
| `modelsim.do` | ModelSim compilation and simulation script |
| `Makefile` | Verilator lint, simulation, and VCD targets |

`verification/du_tia_sva.sv` was removed from this version. The testbench still
compares every expected packet and reports errors with `$fatal`; these checks
are not SVA and are not part of the synthesized hardware.

## Compact hardware datapath

- `transaction_id`: absent from DUT packets and stage registers.
- `du_action`, `tia_action`: absent; S1 selects operations directly from `mode`.
- `b_source_rank`: computed during S1 combinational selection, without a register or output.
- `bitmap`: used only at the input and for S1 combinational decoding; not propagated.
- `valid_mask`: removed; `count` identifies the valid packed prefix.
- `count`: retained to identify the valid value/index entries downstream.
- `index`: 3 bits per entry, identifying lanes 0–7.

Interface widths:

| Type | Width |
|---|---:|
| `du_tia_input_t` | 236 bits |
| `du_tia_output_t` | 185 bits |
| Total S0–S3 registers | 807 bits |

## ModelSim

In the Transcript, change to the package directory containing this README:

```tcl
do modelsim.do
```

Alternatively, run the commands manually:

```tcl
vlib du_tia_work
vmap du_tia_work du_tia_work
vlog -work du_tia_work -sv rtl/du_tia_pkg.sv
vlog -work du_tia_work -sv rtl/du_tia.sv
vlog -work du_tia_work -sv tb/tb_du_tia.sv
vsim du_tia_work.tb_du_tia
run -all
```

Expected final message:

```text
[PASS] DU/TIA compact RTL: 3292 packets checked
```

To compile only the DUT:

```tcl
vlog -work work -sv rtl/du_tia_pkg.sv
vlog -work work -sv rtl/du_tia.sv
```

This version does not require `+define+SYNTHESIS`, because the assertion source
was removed.

## Verilator

```bash
make lint
make sim
```

Or:

```bash
make all
```

The default testbench checks 12 directed packets, 24 exhaustive Ux2:4 packets,
256 exhaustive UxU bitmap packets, and 3000 randomized packets.
