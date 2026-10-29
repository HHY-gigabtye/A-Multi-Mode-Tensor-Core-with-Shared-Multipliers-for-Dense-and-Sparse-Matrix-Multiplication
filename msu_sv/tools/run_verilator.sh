#!/usr/bin/env bash
set -euo pipefail
msu_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$msu_root"
mkdir -p build results vectors
cc -std=c11 -O2 -Wall -Wextra -Werror -Ireference \
    reference/tb_msu.c reference/msu_model.c -o build/tb_msu_c
./build/tb_msu_c | tee results/c_original.log
cc -std=c11 -O2 -Wall -Wextra -Werror -Ireference \
    tools/gen_msu_vectors.c reference/msu_model.c -o build/gen_msu_vectors
./build/gen_msu_vectors > vectors/msu_vectors.tmp 2> results/c_vectors.log
mv vectors/msu_vectors.tmp vectors/msu_vectors.txt
cat results/c_vectors.log
verilator --lint-only --top-module msu -Wall \
    -Wno-UNUSEDPARAM rtl/msu_pkg.sv rtl/msu.sv > results/rtl_lint.log 2>&1
verilator --binary --timing --trace -j 2 --top-module tb_msu \
    --Mdir build/obj_msu rtl/msu_pkg.sv rtl/msu.sv tb/tb_msu.sv \
    > results/verilator_build.log 2>&1
./build/obj_msu/Vtb_msu "$@" | tee results/verilator_sim.log
