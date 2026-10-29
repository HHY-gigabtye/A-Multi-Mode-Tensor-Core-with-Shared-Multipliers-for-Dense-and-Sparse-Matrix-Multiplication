# Outer-Product Pseudocode

## Matrix Specification

- Input matrix `A[8][8]`: INT8
- Input matrix `B[8][8]`: INT8
- Output matrix `C[8][8]`: INT32
- Inner dimension `K = 8`

## Mathematical Definition

The matrix multiplication is calculated as the sum of eight outer products:

\[
C = \sum_{k=0}^{7} A[:,k] \times B[k,:]
\]

## Input

```text
A[M][K] : INT8
B[K][N] : INT8
```

## Output

```text
C[M][N] : INT32
```

## Outer-Product Algorithm

```text
Set M = 8
Set K = 8
Set N = 8

Initialize every element of C[M][N] to 0

for k = 0 to K - 1:

    for i = 0 to M - 1:

        for j = 0 to N - 1:

            product = INT32(A[i][k]) * INT32(B[k][j])

            C[i][j] = C[i][j] + product

return C
```

## Verification

```text
Calculate C_reference using standard matrix multiplication

Calculate C_outer using the outer-product algorithm

for i = 0 to M - 1:
    for j = 0 to N - 1:

        if C_reference[i][j] is not equal to C_outer[i][j]:
            Print "FAIL"
            Print i, j
            Print C_reference[i][j]
            Print C_outer[i][j]
            Stop verification

Print "PASS"
```