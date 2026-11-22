# Sparse Tensor Core integration documentation

This historical filename is retained for existing links. The maintained English
specification is [README.md](README.md).

The production top uses the shared outer-product core and `tb_outer_top.sv`.
Dense, hybrid and dual-sparse tiles all publish three advancing edges after
k=7 and can start every eight cycles with available input and result credit.
The canonical README describes dense operand normalization, metadata admission,
verification coverage and the current ModelSim commands.
