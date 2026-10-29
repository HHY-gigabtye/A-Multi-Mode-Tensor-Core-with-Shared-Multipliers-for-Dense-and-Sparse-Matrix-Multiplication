#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define ROWS 8
#define COLS 8
#define K 8
#define RANDOM_TESTS 1000

/*
 * DUT model:
 *   A is an 8x1 INT8 column vector.
 *   B is a 1x8 INT8 row vector.
 *   C is an 8x8 INT32 output matrix.
 *
 * Equation: C[row][col] = A[row] * B[col]
 */

static void outer_product_dut(const int8_t a[ROWS][COLS],
    const int8_t b[ROWS][COLS],
    int32_t c[ROWS][COLS])
{
    int row;
    int col;
    int k;

    for (row = 0; row < ROWS; ++row) {
        for (col = 0; col < COLS; ++col) {
            c[row][col] = 0;
        }
    }

    for (k = 0; k < K; ++k) {
        for (row = 0; row < ROWS; ++row) {
            for (col = 0; col < COLS; ++col) {
                c[row][col] = c[row][col] + (int32_t)a[row][k] * (int32_t)b[k][col];
            }
        }
    }
}

/* Golden reference used by the randomized verification. */
static void outer_product_reference(const int8_t a[ROWS][COLS],
    const int8_t b[ROWS][COLS],
    int32_t expected[ROWS][COLS])
{
    int row;
    int col;
    int k;

    for (row = 0; row < ROWS; ++row) {
        for (col = 0; col < COLS; ++col) {
            expected[row][col] = 0;
        }
    }

    for (row = 0; row < ROWS; ++row) {
        for (col = 0; col < COLS; ++col) {
            for (k = 0; k < K; ++k) {
                expected[row][col] = expected[row][col] + (int32_t)a[row][k] * (int32_t)b[k][col];
            }
        }
    }
}

static int compare_matrices(int32_t actual[ROWS][COLS],
    int32_t expected[ROWS][COLS])
{
    int row;
    int col;

    for (row = 0; row < ROWS; ++row) {
        for (col = 0; col < COLS; ++col) {
            if (actual[row][col] != expected[row][col]) {
                printf("Mismatch at C[%d][%d]: actual=%d, expected=%d\n",
                    row,
                    col,
                    (int)actual[row][col],
                    (int)expected[row][col]);
                return 0;
            }
        }
    }

    return 1;
}

static void print_int8_matrix(const char* name,
    int8_t matrix[ROWS][COLS])
{
    int row;
    int col;

    printf("%s =\n", name);
    for (row = 0; row < ROWS; ++row) {
        printf("  [");
        for (col = 0; col < COLS; ++col) {
            printf("%4d%s",
                (int)matrix[row][col],
                (col == COLS - 1) ? "" : ",");
        }
        printf("]\n");
    }
}

static void print_int32_matrix(const char* name,
    int32_t matrix[ROWS][COLS])
{
    int row;
    int col;

    printf("%s =\n", name);
    for (row = 0; row < ROWS; ++row) {
        printf("  [");
        for (col = 0; col < COLS; ++col) {
            printf("%6d%s",
                (int)matrix[row][col],
                (col == COLS - 1) ? "" : ",");
        }
        printf("]\n");
    }
}

static int run_directed_test(void)
{
    int8_t a[ROWS][COLS] = {
        { 1,  2,  0, -1,  3,  0,  2,  1},
        { 0,  1,  2,  3, -1,  2,  0,  1},
        { 2,  0, -2,  1,  0,  3,  1, -1},
        { 1, -1,  1,  0,  2,  2, -2,  3},
        { 3,  1,  0,  2,  1, -1,  1,  0},
        {-1,  2,  3,  1,  0,  1,  2, -2},
        { 2,  1, -1,  2,  3,  0,  1,  1},
        { 0, -2,  1,  3,  1,  2,  0,  2}
    };
    int8_t b[ROWS][COLS] = {
        { 1,  0,  2, -1,  3,  1,  0,  2},
        { 2,  1, -1,  0,  1,  3,  2, -2},
        { 0,  3,  1,  2, -2,  1,  1,  0},
        {-1,  2,  0,  1,  1, -1,  3,  2},
        { 3, -1,  2,  0,  2,  1, -2,  1},
        { 1,  2,  3, -2,  0,  2,  1,  3},
        { 2,  0, -2,  3,  1,  0,  2, -1},
        { 0,  1,  1,  2,  3, -2,  0,  1}
    };
    int32_t reference[ROWS][COLS];
    int32_t dut[ROWS][COLS];

    outer_product_reference(a, b, reference);
    outer_product_dut(a, b, dut);

    printf("=== Directed 8x8x8 matrix-multiplication test ===\n");
    print_int8_matrix("A", a);
    print_int8_matrix("B", b);
    print_int32_matrix("reference = A x B", reference);
    print_int32_matrix("result = A x B", dut);

    if (!compare_matrices(dut, reference)) {
        printf("Directed test: FAIL\n");
        return 0;
    }

    printf("Directed test: PASS\n\n");
    return 1;
}

static int random_int8_value(void)
{
    return (rand() % 256) - 128;
}

static int run_random_tests(void)
{
    int test;

    /* Fixed seed: a failure can be reproduced on the next run. */
    srand(20260814u);

    for (test = 0; test < RANDOM_TESTS; ++test) {
        int8_t a[ROWS][COLS];
        int8_t b[ROWS][COLS];
        int32_t reference[ROWS][COLS];
        int32_t outer_product_result[ROWS][COLS];
        int i;
        int j;

        for (i = 0; i < ROWS; ++i) {
            for (j = 0; j < COLS; ++j) {
                a[i][j] = (int8_t)random_int8_value();
                b[i][j] = (int8_t)random_int8_value();
            }
        }

        outer_product_reference(a, b, reference);
        outer_product_dut(a, b, outer_product_result);

        if (!compare_matrices(outer_product_result, reference)) {
            printf("Random test %d: FAIL\n", test + 1);
            print_int8_matrix("A", a);
            print_int8_matrix("B", b);
            return 0;
        }
    }

    printf("Random tests (%d cases): PASS\n", RANDOM_TESTS);
    return 1;
}

int main(void)
{
    if (!run_directed_test()) {
        return EXIT_FAILURE;
    }

    if (!run_random_tests()) {
        return EXIT_FAILURE;
    }

    printf("\nAll 8x8x8 matrix-multiplication tests PASSED.\n");
    return EXIT_SUCCESS;
}