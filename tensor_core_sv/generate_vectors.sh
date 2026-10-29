#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
    c_reference/tensor_core_model.c c_reference/generate_c_vectors.c \
    -o build/generate_c_vectors
build/generate_c_vectors c_vectors.txt "$@" > c_reference_results.txt
cat c_reference_results.txt
