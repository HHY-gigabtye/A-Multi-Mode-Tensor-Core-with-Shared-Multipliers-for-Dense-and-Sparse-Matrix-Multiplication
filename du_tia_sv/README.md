# DU + TIA SystemVerilog RTL — No-Assertion Version

This version targets ModelSim–Intel FPGA Edition environments without SystemVerilog Assertions support. The RTL, testbench, file list, and build flow contain no `assert property`, SVA checkers, coverage properties, or `--assert` option.

## Contents

| File | Purpose |
|---|---|
| `rtl/du_tia_pkg.sv` | Compact types, packed union, and helper functions |
| `rtl/du_tia.sv` | Four-stage DU/TIA pipeline without assertions |
| `tb/tb_du_tia.sv` | Golden model, scoreboard, and 3292 functional test packets |
| `filelist.f` | Compilation order for the package, RTL, and testbench |
| `modelsim.do` | ModelSim compilation and simulation script |
| `Makefile` | Verilator lint, simulation, and VCD generation |

`verification/du_tia_sva.sv` was removed from this version. The testbench still compares each output against an expected packet and reports errors with `$fatal`. These checks are not SVA and are not part of the synthesized hardware.

## Compact Hardware Datapath

- `transaction_id`: absent from DUT packets and stage registers.
- `du_action`, `tia_action`: absent; S1 selects the operation directly from `mode`.
- `b_source_rank`: calculated only during combinational selection in S1; neither registered nor output.
- `bitmap`: used only at the input and during S1 combinational decoding; not forwarded to later stages.
- `valid_mask`: removed; `count` identifies the valid packed prefix.
- `count`: retained so downstream logic knows how many value/index entries are valid.
- `index`: 3 bits per entry, identifying lane 0–7.

Interface widths:

| Type | Width |
|---|---:|
| `du_tia_input_t` | 236 bits |
| `du_tia_output_t` | 185 bits |
| Total S0–S3 registers | 807 bits |

## Running ModelSim

In the Transcript, change to the module directory containing this README, then run:

```tcl
do modelsim.do
```

Alternatively, run these commands manually:

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

To compile only the DUT, without the testbench:

```tcl
vlog -work work -sv rtl/du_tia_pkg.sv
vlog -work work -sv rtl/du_tia.sv
```

This version does not require `+define+SYNTHESIS`, because the assertion source was physically removed.

## Verilator

```bash
make lint
make sim
```

Or:

```bash
make all
```

By default, the testbench checks 12 directed packets, 24 exhaustive Ux2:4 packets, 256 exhaustive UxU bitmap packets, and 3000 randomized packets.
