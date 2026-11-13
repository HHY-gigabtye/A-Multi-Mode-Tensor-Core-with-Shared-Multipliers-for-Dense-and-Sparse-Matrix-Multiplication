#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
verilator --binary --timing -j 2 --top-module tb_tensor_core \
    --Mdir build/obj_dir tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
build/obj_dir/Vtb_tensor_core +VECTORS=c_vectors.txt
