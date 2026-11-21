#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
verilator --binary --timing -j 2 --top-module tb_outer_core \
    --Mdir build/obj_dir tensor_core_pkg.sv outer_product_core.sv tb_outer_core.sv
build/obj_dir/Vtb_outer_core +VECTORS=c_vectors.txt
