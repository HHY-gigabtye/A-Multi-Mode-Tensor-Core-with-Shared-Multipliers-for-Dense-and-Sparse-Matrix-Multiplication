# Tensor Core documentation

This historical filename is retained for existing links. The maintained English
specification is [README.md](README.md).

Current production uses `outer_product_core.sv`: one shared pipeline for dense,
hybrid and dual-sparse tiles, a 184-bit indexed operand pair, result-credit
admission and unstalled tile II=8 for every format. See the canonical README
for the interface, timing and verification commands. Its
[legacy section](README.md#legacy-core-and-cycle-reference) separately documents
the retained systolic predecessor and original C model.
