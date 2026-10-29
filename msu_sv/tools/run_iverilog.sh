#!/usr/bin/env bash
set -euo pipefail
msu_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$msu_root"
mkdir -p build results
iverilog -g2012 -s tb_msu -o build/tb_msu_ivl -f sim/files.f \
    > results/iverilog_build.log 2>&1
vvp build/tb_msu_ivl "$@" | tee results/iverilog_sim.log
