#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build logs
cc_bin="${CC:-gcc}"
"$cc_bin" -std=c11 -O2 -Wall -Wextra -Werror -pedantic -I c_ref \
  c_ref/mlu_model.c c_ref/tb_mlu.c -o build/tb_mlu_c
"$cc_bin" -std=c11 -O2 -Wall -Wextra -Werror -pedantic -I c_ref \
  c_ref/mlu_model.c c_ref/gen_mlu_vectors.c -o build/gen_mlu_vectors
build/tb_mlu_c | tee logs/c_baseline.log
build/gen_mlu_vectors mlu_vectors.txt "${1:-20261024}" | tee logs/c_vectors.log
