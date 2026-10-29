#!/usr/bin/env bash
# Standalone MLU unit test; the only RTL module compiled from sim.f is mlu.
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build logs
if [[ -n "${VERILATOR:-}" ]]; then
  vl_bin="$VERILATOR"
elif command -v verilator >/dev/null 2>&1; then
  vl_bin="$(command -v verilator)"
elif command -v verilator-cli >/dev/null 2>&1; then
  vl_bin="$(command -v verilator-cli)"
else
  echo 'Set VERILATOR to the installed verilator (or verilator-cli) executable.' >&2
  exit 1
fi
extra_args=()
# Optional override for installations whose make configuration omits PCH/C++20 flags.
if [[ -n "${MLU_VERILATOR_MAKEFLAGS:-}" ]]; then
  extra_args+=(-MAKEFLAGS "$MLU_VERILATOR_MAKEFLAGS")
fi
"$vl_bin" --binary --timing -j "${JOBS:-4}" --top-module tb_mlu \
  --Mdir build/obj -o mlu_sim -Wall -Wno-UNUSEDSIGNAL \
  "${extra_args[@]}" -f sim.f > logs/verilator_build.log 2>&1
build/obj/mlu_sim "$@" | tee logs/rtl_simulation.log
