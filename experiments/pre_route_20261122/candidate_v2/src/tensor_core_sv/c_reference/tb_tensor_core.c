/* Tests ONLY. Generates already-decoded packets; no DU/TIA model.
 * GCC: gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
 *          tensor_core_model.c tb_tensor_core.c -o tb_tensor_core
 */
#include "tensor_core_model.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>

enum { GROUP = 4, MAX_CYCLES = 256 };
typedef struct { int8_t v[TC_DIM][TC_DIM]; } Matrix8;
typedef struct { TensorCore core; TcTickInfo info; unsigned cycle; } TestDriver;

static void check(bool condition, const char *format, ...)
{
    if (!condition) {
        va_list args;
        va_start(args, format);
        fputs("FAIL: ", stderr);
        vfprintf(stderr, format, args);
        fputc('\n', stderr);
        va_end(args);
        exit(EXIT_FAILURE);
    }
}

static void driver_reset(TestDriver *s)
{
    memset(s, 0, sizeof *s);
    tc_reset(&s->core);
}

static void driver_tick(TestDriver *s, const TcInputPacket *input, bool ready)
{
    const TcStatus status = tc_tick(&s->core, input != NULL, input, ready, &s->info);
    check(status == TC_OK, "%s", tc_status_name(status));
    ++s->cycle;
}

typedef enum { CASE_DENSE, CASE_HYBRID, CASE_DUAL, CASE_DENSE_U, CASE_COUNT } CaseKind;
static const char *const case_names[CASE_COUNT] = {
    "dense", "hybrid", "dual", "dense-unstructured"
};

/* Test fixture only: construct the post-DU/TIA value/index representation
 * directly from matrices. This does not decode any bitmap or 2:4 metadata.
 */
static void make_decoded_packets(const Matrix8 *a, const Matrix8 *b, CaseKind kind,
                                  TcInputPacket packets[TC_K])
{
    for (unsigned k = 0; k < TC_K; ++k) {
        TcInputPacket *p = &packets[k];
        memset(p, 0, sizeof *p);
        p->is_sparse = kind != CASE_DENSE;
        if (!p->is_sparse) {
            for (unsigned lane = 0; lane < TC_DIM; ++lane) {
                p->payload.dense.dense_a[lane] = a->v[lane][k];
                p->payload.dense.dense_b[lane] = b->v[k][lane];
            }
        } else {
            TcSparseVector *av = &p->payload.sparse.a;
            TcSparseVector *bv = &p->payload.sparse.b;
            /* Invalid padding indexes must never be routed or read. */
            for (unsigned lane = 0; lane < TC_DIM; ++lane) {
                av->value[lane] = 93;
                bv->value[lane] = -91;
                av->index[lane] = bv->index[lane] = 255;
            }
            for (unsigned lane = 0; lane < TC_DIM; ++lane) {
                /* Dense A may retain all eight entries, including zeros. */
                if (a->v[lane][k] != 0 || kind == CASE_DENSE_U) {
                    av->index[av->count] = (uint8_t)lane;
                    av->value[av->count++] = a->v[lane][k];
                }
                if (b->v[k][lane] != 0) {
                    bv->index[bv->count] = (uint8_t)lane;
                    bv->value[bv->count++] = b->v[k][lane];
                }
            }
        }
    }
}

static TcMatrix32 golden_gemm(const Matrix8 *a, const Matrix8 *b)
{
    TcMatrix32 c = {0};
    /* Independent original-coordinate i,j,k dot products.
     * Never calls packet generation, skew, routing, or pipeline functions.
     */
    for (unsigned i = 0; i < TC_DIM; ++i)
        for (unsigned j = 0; j < TC_DIM; ++j)
            for (unsigned k = 0; k < TC_K; ++k)
                c.v[i][j] += (int32_t)a->v[i][k] * (int32_t)b->v[k][j];
    return c;
}

static void check_matrix(const TcMatrix32 *actual, const TcMatrix32 *expected,
                         const char *name)
{
    for (unsigned i = 0; i < TC_DIM; ++i)
        for (unsigned j = 0; j < TC_DIM; ++j)
            check(actual->v[i][j] == expected->v[i][j],
                  "%s C[%u][%u]: got %ld, expected %ld", name, i, j,
                  (long)actual->v[i][j], (long)expected->v[i][j]);
}

static void print_matrix8(const char *name, const Matrix8 *m)
{
    printf("%s:\n", name);
    for (unsigned i = 0; i < TC_DIM; ++i) {
        for (unsigned j = 0; j < TC_DIM; ++j) printf("%6d", (int)m->v[i][j]);
        putchar('\n');
    }
}

static void print_matrix32(const char *name, const TcMatrix32 *m)
{
    printf("%s:\n", name);
    for (unsigned i = 0; i < TC_DIM; ++i) {
        for (unsigned j = 0; j < TC_DIM; ++j) printf("%9ld", (long)m->v[i][j]);
        putchar('\n');
    }
}

static void print_tick(const TestDriver *s, const TcInputPacket *input, unsigned t,
                       const unsigned issue[TC_K])
{
    printf("cycle %03u | IN=", t);
    if (input != NULL) printf("k%u", s->info.input_k);
    else printf("--");
    printf(" | CORE_IN=");
    if (s->info.input_accepted) printf("k%u", s->info.input_k);
    else printf("--");
    if (s->info.sparse_step)
        printf(" | MUL=%u ROUTE=%u ACC=%u FIRST_ACC=%u LAST_ACC=%u",
               (unsigned)s->info.mul, (unsigned)s->info.route,
               (unsigned)s->info.acc, (unsigned)s->info.acc_first, (unsigned)s->info.acc_last);
    printf(" | MACs=%2u | result_valid=%u produced=%u accepted=%u outstanding=%u queued=%u\n",
           s->info.macs, (unsigned)s->core.result_valid, (unsigned)s->info.result_produced,
           (unsigned)s->info.result_accepted, s->core.outstanding, s->core.result_count);
    if (s->info.dense_step) {
        static const unsigned cells[5][2] = {{0,0},{1,0},{0,1},{1,1},{7,7}};
        for (unsigned n = 0; n < 5; ++n) {
            const unsigned i = cells[n][0], j = cells[n][1];
            const TcPE *pe = &s->core.state.dense.pe[i][j];
            if (!pe->a.valid) continue;
            for (unsigned k = 0; k < TC_K; ++k) {
                if (issue[k] + i + j == t) {
                    printf("    PE[%u][%u] A[%u][%u]=%4d x B[%u][%u]=%4d -> acc=%7ld%s\n",
                           i, j, i, k, (int)pe->a.value, k, j, (int)pe->b.value,
                           (long)pe->acc, pe->a.last ? " LAST" : "");
                    break;
                }
            }
        }
    }
    if (s->info.mul) {
        const TcMultiplyReg *m = &s->core.state.sparse.mul;
        printf("    MUL A_count=%u B_count=%u A_index=[",
               (unsigned)m->a_count, (unsigned)m->b_count);
        for (unsigned p = 0; p < m->a_count; ++p)
            printf("%s%u", p == 0 ? "" : ",", (unsigned)m->a_index[p]);
        printf("] B_index=[");
        for (unsigned p = 0; p < m->b_count; ++p)
            printf("%s%u", p == 0 ? "" : ",", (unsigned)m->b_index[p]);
        printf("]");
        if (m->a_count != 0 && m->b_count != 0)
            printf(" | P[0][0]=%d will target C[%u][%u]",
                   (int)m->product[0][0], (unsigned)m->a_index[0], (unsigned)m->b_index[0]);
        else printf(" | empty outer product; valid/last still propagate");
        putchar('\n');
    }
    if (s->info.route) {
        const TcRouteReg *r = &s->core.state.sparse.route;
        unsigned shown = 0;
        printf("    ROUTE examples:");
        for (unsigned i = 0; i < TC_DIM && shown < 3; ++i)
            for (unsigned j = 0; j < TC_DIM && shown < 3; ++j)
                if (r->enable[i][j]) {
                    printf(" C[%u][%u] += %d;", i, j, (int)r->delta[i][j]);
                    ++shown;
                }
        if (shown == 0) printf(" no updates");
        printf(" (ACC on next tick)\n");
    }
}

/* Check every dense PE against a closed-form arrival schedule. This catches
 * an accidentally correct final result from a non-systolic implementation.
 */
static void check_dense_timing(const TestDriver *s, const Matrix8 *a, const Matrix8 *b,
                               const unsigned issue[TC_K], unsigned t)
{
    if (!s->info.dense_step) return;
    for (unsigned i = 0; i < TC_DIM; ++i) {
        for (unsigned j = 0; j < TC_DIM; ++j) {
            const TcPE *pe = &s->core.state.dense.pe[i][j];
            int current_k = -1;
            for (unsigned k = 0; k < TC_K; ++k)
                if (issue[k] + i + j == t) current_k = (int)k;
            check(pe->a.valid == (current_k >= 0) && pe->b.valid == (current_k >= 0),
                  "Dense wavefront validity mismatch at t=%u PE[%u][%u]", t, i, j);
            if (current_k >= 0) {
                const unsigned k = (unsigned)current_k;
                check(pe->a.value == a->v[i][k] && pe->b.value == b->v[k][j],
                      "Dense operand alignment mismatch at t=%u PE[%u][%u]", t, i, j);
                check(pe->a.last == (k == TC_K - 1) && pe->b.last == (k == TC_K - 1),
                      "Dense last timing mismatch");
            }
        }
    }
}

typedef struct {
    unsigned tiles, macs, dense_tiles, sparse_tiles;
} TestTotals;

static unsigned run_tile(TestDriver *s, const Matrix8 *a, const Matrix8 *b, CaseKind kind,
                         const unsigned gap[TC_K], unsigned hold, bool trace,
                         bool show, TestTotals *totals)
{
    TcInputPacket packets[TC_K];
    unsigned issue[TC_K], next_k = 0, macs = 0, held = 0;
    unsigned result_cycle = UINT32_MAX;
    const unsigned start = s->cycle;
    const bool sparse = kind != CASE_DENSE;
    const TcMatrix32 expected = golden_gemm(a, b);
    check(!s->core.busy, "run_tile requires an idle system");
    make_decoded_packets(a, b, kind, packets);
    issue[0] = start + gap[0];
    for (unsigned k = 1; k < TC_K; ++k) issue[k] = issue[k - 1] + 1 + gap[k];
    if (show) {
        printf("\n--- %s, is_sparse=%u ---\n",
               case_names[kind], (unsigned)sparse);
        print_matrix8("A", a);
        print_matrix8("B", b);
    }
    while (s->cycle - start < MAX_CYCLES) {
        const unsigned t = s->cycle;
        const TcInputPacket *in = next_k < TC_K && t == issue[next_k] ? &packets[next_k] : NULL;
        const bool old_result_valid = s->core.result_valid;
        const bool ready = !old_result_valid || held >= hold;
        if (in != NULL) check(tc_input_ready(&s->core), "Input not ready");
        driver_tick(s, in, ready);
        check(s->info.input_accepted == (in != NULL), "Input acceptance mismatch");
        if (in != NULL) check(s->info.input_k == next_k, "Packet count mismatch");
        if (sparse) {
            bool want_route = false, want_acc = false;
            for (unsigned k = 0; k < TC_K; ++k) {
                want_route = want_route || t == issue[k] + 1;
                want_acc = want_acc || t == issue[k] + 2;
            }
            check(s->info.mul == (in != NULL) && s->info.route == want_route &&
                  s->info.acc == want_acc, "Sparse pipeline timing mismatch");
            check(s->info.acc_last == (t == issue[TC_K - 1] + 2),
                  "Sparse last packet timing mismatch");
            check(s->info.acc_first == (t == issue[0] + 2),
                  "Sparse first packet timing mismatch");
        }
        if (in != NULL) ++next_k;
        macs += s->info.macs;
        if (!sparse) check_dense_timing(s, a, b, issue, t);
        if (trace) print_tick(s, in, t, issue);
        if (s->core.result_valid) {
            const unsigned expected_cycle = issue[TC_K - 1] +
                (sparse ? 2u : (2u * (TC_DIM - 1))) + 1u;
            if (!old_result_valid) {
                result_cycle = t;
                check(t == expected_cycle, "Result timing: got %u, expected %u", t, expected_cycle);
            }
            check_matrix(&s->core.result, &expected, case_names[kind]);
        }
        if (old_result_valid && !ready) {
            ++held;
            check(s->core.result_valid && s->core.busy, "Output did not hold under backpressure");
        }
        if (s->info.result_accepted) {
            unsigned expected_macs = 0;
            check(result_cycle != UINT32_MAX && next_k == TC_K, "Premature completion");
            check(!s->core.busy && !s->core.result_valid, "Failed to release tile");
            for (unsigned k = 0; k < TC_K; ++k)
                expected_macs += sparse ?
                    (unsigned)packets[k].payload.sparse.a.count *
                    packets[k].payload.sparse.b.count : TC_DIM * TC_DIM;
            check(macs == expected_macs, "Useful MAC count: got %u, expected %u", macs, expected_macs);
            ++totals->tiles;
            totals->macs += macs;
            if (sparse) ++totals->sparse_tiles; else ++totals->dense_tiles;
            if (show) {
                print_matrix32("C = A * B (checked)", &s->core.result);
                printf("PASS: issue first@%u last@%u; result_valid@%u; consumed@%u; MACs=%u\n",
                       issue[0], issue[TC_K - 1], result_cycle, t, macs);
            }
            return result_cycle;
        }
    }
    check(false, "Tile timeout");
    return 0;
}

static uint32_t next_random(uint32_t *state)
{
    uint32_t x = *state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *state = x;
    return x;
}

static int8_t random_value(uint32_t *state)
{
    return (int8_t)((int)(next_random(state) & 255u) - 128);
}

static int8_t random_nonzero(uint32_t *state)
{
    int8_t v;
    do { v = random_value(state); } while (v == 0);
    return v;
}

static void make_matrices(Matrix8 *a, Matrix8 *b, CaseKind kind,
                          unsigned variant, uint32_t *rng, bool random_case)
{
    static const uint8_t masks[6] = {3, 5, 6, 9, 10, 12};
    const unsigned a_density = random_case ? (unsigned)(next_random(rng) % 101u) : 50u;
    const unsigned b_density = random_case ? (unsigned)(next_random(rng) % 101u) : 50u;
    memset(a, 0, sizeof *a);
    memset(b, 0, sizeof *b);
    for (unsigned i = 0; i < TC_DIM; ++i) {
        for (unsigned j = 0; j < TC_DIM; ++j) {
            if (random_case) {
                a->v[i][j] = random_value(rng);
                b->v[i][j] = random_value(rng);
                if (kind != CASE_DENSE && kind != CASE_DENSE_U &&
                    next_random(rng) % 100u >= a_density) a->v[i][j] = 0;
                if (kind != CASE_DENSE &&
                    next_random(rng) % 100u >= b_density) b->v[i][j] = 0;
            } else {
                a->v[i][j] = (int8_t)(1 + (int)(i * TC_DIM + j));
                b->v[i][j] = (int8_t)((int)(3 * i) - (int)(2 * j) + 1);
                if (variant == 0) a->v[i][j] = b->v[i][j] = 0;
                if (variant == 1) a->v[i][j] = (int8_t)(i == j);
                if (variant == 2) a->v[i][j] = b->v[i][j] = INT8_MIN;
                if (variant == 3) {
                    a->v[i][j] = ((i + j) % 2) == 0 ? INT8_MIN : INT8_MAX;
                    b->v[i][j] = ((i + 2 * j) % 3) == 0 ? INT8_MIN : INT8_MAX;
                }
                if (variant == 5) {
                    if ((i + 2 * j) % 3 != 0) a->v[i][j] = 0;
                    if ((2 * i + j) % 4 != 0) b->v[i][j] = 0;
                }
                if (variant == 6 && j != TC_K - 1) a->v[i][j] = 0;
                if (variant == 7 && j == TC_K - 1) a->v[i][j] = 0;
                if (kind == CASE_DENSE_U && variant == 4 && (i + j) % 3 != 0)
                    b->v[i][j] = 0;
            }
        }
    }
    if (kind == CASE_HYBRID) {
        for (unsigned group = 0; group < TC_K / GROUP; ++group) {
            for (unsigned j = 0; j < TC_DIM; ++j) {
                const uint8_t mask = masks[random_case ? next_random(rng) % 6u :
                                          (variant + j + group) % 6u];
                for (unsigned pos = 0; pos < GROUP; ++pos) {
                    const unsigned k = group * GROUP + pos;
                    b->v[k][j] = 0;
                    if ((mask & (1u << pos)) != 0)
                        b->v[k][j] = random_case ? random_nonzero(rng) :
                            (int8_t)(1 + (int)(k * TC_DIM + j));
                }
            }
        }
    }
}

/* Negative calls must not advance the model or consume a pending result. */
static void expect_rejection(TensorCore *q, bool valid, const TcInputPacket *p,
                              TcStatus want)
{
    TensorCore before;
    TcTickInfo info;
    memcpy(&before, q, sizeof before);
    check(tc_tick(q, valid, p, true, &info) == want, "Wrong rejection status");
    check(memcmp(&before, q, sizeof before) == 0, "Rejected input changed state");
    check(!info.input_accepted && !info.result_accepted, "Rejected handshake");
}

static void test_rejection_and_reset(TestTotals *totals)
{
    Matrix8 a, b;
    TcInputPacket packets[TC_K], bad;
    TestDriver s;
    uint32_t rng = 19;
    const unsigned gap[TC_K] = {0};
    make_matrices(&a, &b, CASE_DUAL, 4, &rng, false);
    make_decoded_packets(&a, &b, CASE_DUAL, packets);
    driver_reset(&s);
    check(tc_tick(NULL, false, NULL, false, NULL) == TC_BAD_ARGUMENT, "NULL core");
    check(!tc_input_ready(NULL) && !tc_input_ready_for(NULL, true), "NULL readiness");
    expect_rejection(&s.core, true, NULL, TC_BAD_ARGUMENT);
    for (unsigned side = 0; side < 2; ++side) {
        for (unsigned fault = 0; fault < 4; ++fault) {
            TcSparseVector *v;
            bad = packets[0];
            v = side == 0 ? &bad.payload.sparse.a : &bad.payload.sparse.b;
            v->count = 2;
            v->index[0] = 1; v->index[1] = 3;
            if (fault == 0) v->count = 9;
            if (fault == 1) v->index[1] = 8;
            if (fault == 2) v->index[1] = 1;
            if (fault == 3) v->index[1] = 0;
            expect_rejection(&s.core, true, &bad, TC_BAD_SPARSE_VECTOR);
        }
    }
    /* in_valid=false must ignore even a malformed payload. */
    check(tc_tick(&s.core, false, &bad, true, NULL) == TC_OK && !s.core.busy,
          "Bubble read the ignored payload");
    driver_tick(&s, &packets[0], true);
    bad = packets[0]; bad.is_sparse = false;
    expect_rejection(&s.core, true, &bad, TC_MODE_CHANGE);
    bad = packets[1]; bad.payload.sparse.a.count = 9;
    expect_rejection(&s.core, true, &bad, TC_BAD_SPARSE_VECTOR);
    for (unsigned k = 1; k < TC_K; ++k) driver_tick(&s, &packets[k], true);
    check(tc_input_ready_for(&s.core, true), "Sparse ninth packet must be ready");
    check(!tc_input_ready_for(&s.core, false), "Mode switched before drain");
    bad = packets[0]; bad.is_sparse = false;
    expect_rejection(&s.core, true, &bad, TC_MODE_CHANGE);
    /* Reserve the second slot; then pause at the THIRD tile, not the second. */
    for (unsigned k = 0; k < TC_K; ++k) driver_tick(&s, &packets[k], false);
    check(!tc_input_ready(&s.core), "Third tile accepted without result credit");
    expect_rejection(&s.core, true, &packets[0], TC_NOT_READY);
    for (unsigned t = 0; t < MAX_CYCLES && s.core.result_count != TC_RESULT_SLOTS; ++t)
        driver_tick(&s, NULL, false);
    check(s.core.result_count == TC_RESULT_SLOTS, "Missing queued sparse results");
    expect_rejection(&s.core, true, &packets[0], TC_NOT_READY);
    driver_tick(&s, NULL, true);
    check(s.info.result_accepted && tc_input_ready(&s.core), "Result handshake");
    check(s.core.result_valid && !tc_input_ready_for(&s.core, false),
          "Queued result lost or mode barrier released too soon");
    driver_tick(&s, NULL, true);
    check(!s.core.busy && !s.core.result_valid, "Sparse results did not drain");

    /* Dense still rejects packet nine, including while its output is held. */
    driver_reset(&s);
    make_decoded_packets(&a, &b, CASE_DENSE, packets);
    for (unsigned k = 0; k < TC_K; ++k) driver_tick(&s, &packets[k], true);
    expect_rejection(&s.core, true, &packets[0], TC_NOT_READY);
    for (unsigned t = 0; t < MAX_CYCLES && !s.core.result_valid; ++t)
        driver_tick(&s, NULL, false);
    check(s.core.result_valid, "Missing dense held result");
    expect_rejection(&s.core, true, &packets[0], TC_NOT_READY);
    driver_tick(&s, NULL, true);
    check(!s.core.busy && tc_input_ready_for(&s.core, true), "Dense drain failed");

    /* Reset during input skew, TcPE propagation, sparse stages and held output. */
    for (unsigned mode = 0; mode < 2; ++mode) {
        const CaseKind kind = mode == 0 ? CASE_DENSE : CASE_HYBRID;
        for (unsigned cut = 1; cut <= 24; ++cut) {
            driver_reset(&s);
            make_matrices(&a, &b, kind, 4, &rng, false);
            make_decoded_packets(&a, &b, kind, packets);
            for (unsigned t = 0; t < cut; ++t)
                driver_tick(&s, t < TC_K ? &packets[t] : NULL, false);
            driver_reset(&s);
            for (unsigned t = 0; t < 24; ++t) {
                driver_tick(&s, NULL, true);
                check(!s.core.result_valid && !s.core.busy && tc_input_ready(&s.core),
                      "Reset leaked old work");
            }
            (void)run_tile(&s, &a, &b, kind, gap, 0, false, false, totals);
        }
    }
}

static void test_stored_zeros(TestTotals *totals)
{
    Matrix8 a = {0}, b = {0};
    TcInputPacket packets[TC_K] = {0};
    TensorCore core;
    TcTickInfo info;
    TcMatrix32 expected;
    unsigned macs = 0;
    a.v[2][0] = -128; b.v[0][5] = 127;
    a.v[7][6] = 127; b.v[6][1] = -128;
    expected = golden_gemm(&a, &b);
    for (unsigned k = 0; k < TC_K; ++k) {
        TcSparsePayload *p = &packets[k].payload.sparse;
        packets[k].is_sparse = true;
        p->a.count = p->b.count = TC_DIM;
        for (unsigned i = 0; i < TC_DIM; ++i) {
            p->a.index[i] = p->b.index[i] = (uint8_t)i;
            p->a.value[i] = a.v[i][k]; p->b.value[i] = b.v[k][i];
        }
    }
    tc_reset(&core);
    for (unsigned t = 0; t <= 11; ++t) {
        check(tc_tick(&core, t < TC_K, t < TC_K ? &packets[t] : NULL,
                      true, &info) == TC_OK, "Stored zero rejected");
        macs += info.macs;
        check(core.result_valid == (t == 10), "Stored zero completion timing");
        if (t == 10) check_matrix(&core.result, &expected, "stored-zero");
        if (t == 11) check(info.result_accepted, "Stored zero result handshake");
    }
    check(macs == 512, "Stored zero lanes were not processed");
    ++totals->tiles; ++totals->sparse_tiles; totals->macs += macs;
}

static void test_mode_switches(TestTotals *totals)
{
    TestDriver s;
    Matrix8 a, b;
    uint32_t rng = 37;
    const unsigned gaps[TC_K] = {0, 1, 0, 2, 0, 1, 0, 0};
    driver_reset(&s);
    /* Reuse one instance across dense/sparse and decoded sparse workload changes.
     * Never reset between these tiles; each next tile starts after handshake.
     */
    for (unsigned round = 0; round < 4; ++round) {
        static const CaseKind sequence[4] = {
            CASE_DENSE, CASE_HYBRID, CASE_DENSE, CASE_DUAL
        };
        for (unsigned n = 0; n < 4; ++n) {
            const CaseKind kind = sequence[n];
            make_matrices(&a, &b, kind, round + n, &rng, true);
            (void)run_tile(&s, &a, &b, kind, gaps, n, false, false, totals);
        }
    }
}

/* Streaming scoreboard. Expected matrices use independent i/j/k GEMM above.
 * Unlike run_tile(), this driver sends the next tile without waiting for output.
 */
typedef struct {
    TcInputPacket packet[TC_K];
    TcMatrix32 expected;
    unsigned issue[TC_K];
    unsigned macs;
} StreamTile;

typedef enum { STREAM_FULL, STREAM_DIRECTED, STREAM_SPARSE_RANDOM, STREAM_MIXED } StreamFixture;
typedef struct {
    bool gaps, output_stalls, serial, trace;
    unsigned hold_until;
} StreamOptions;
typedef struct {
    unsigned cycles, overlap_starts, credit_waits, mode_waits, max_queued;
    unsigned input_and_output, input_and_publish, pop_and_push;
    uint64_t macs;
} StreamStats;

static void make_stream_tile(StreamTile *tile, unsigned n, StreamFixture fixture,
                              uint32_t *rng)
{
    static const CaseKind mixed[] = {
        CASE_DUAL, CASE_HYBRID, CASE_DENSE_U, CASE_DENSE,
        CASE_DUAL, CASE_DENSE, CASE_HYBRID, CASE_DUAL
    };
    CaseKind kind = CASE_DUAL;
    Matrix8 a, b;
    if (fixture == STREAM_SPARSE_RANDOM) kind = (CaseKind)(1u + n % 3u);
    if (fixture == STREAM_MIXED) kind = mixed[n % 8u];
    make_matrices(&a, &b, kind, n % 8u, rng,
                  fixture == STREAM_SPARSE_RANDOM || fixture == STREAM_MIXED);
    if (fixture == STREAM_FULL) {
        for (unsigned i = 0; i < TC_DIM; ++i)
            for (unsigned j = 0; j < TC_DIM; ++j) {
                a.v[i][j] = random_nonzero(rng);
                b.v[i][j] = random_nonzero(rng);
            }
    } else if (fixture == STREAM_DIRECTED) {
        /* Full -> empty -> empty-first -> stored-zero -> empty-last -> signed
         * extremes. These transitions expose stale accumulators across tiles.
         */
        if (n % 6u == 0) make_matrices(&a, &b, kind, 2, rng, false);
        if (n % 6u == 1) memset(&a, 0, sizeof a);
        if (n % 6u == 2)
            for (unsigned i = 0; i < TC_DIM; ++i) a.v[i][0] = 0;
        if (n % 6u == 3) {
            memset(&a, 0, sizeof a); memset(&b, 0, sizeof b);
            a.v[2][0] = INT8_MIN; b.v[0][5] = INT8_MAX;
            a.v[7][6] = INT8_MAX; b.v[6][1] = INT8_MIN;
        }
        if (n % 6u == 4)
            for (unsigned i = 0; i < TC_DIM; ++i) a.v[i][TC_K - 1] = 0;
        if (n % 6u == 5) make_matrices(&a, &b, kind, 3, rng, false);
    }
    tile->expected = golden_gemm(&a, &b);
    make_decoded_packets(&a, &b, kind, tile->packet);
    tile->macs = 0;
    for (unsigned k = 0; k < TC_K; ++k) {
        TcInputPacket *p = &tile->packet[k];
        if (fixture == STREAM_DIRECTED && n % 6u == 3) {
            p->payload.sparse.a.count = p->payload.sparse.b.count = TC_DIM;
            for (unsigned i = 0; i < TC_DIM; ++i) {
                p->payload.sparse.a.index[i] = p->payload.sparse.b.index[i] = (uint8_t)i;
                p->payload.sparse.a.value[i] = a.v[i][k];
                p->payload.sparse.b.value[i] = b.v[k][i];
            }
        }
        tile->macs += p->is_sparse ?
            (unsigned)p->payload.sparse.a.count * p->payload.sparse.b.count : TC_DIM * TC_DIM;
        tile->issue[k] = UINT32_MAX;
    }
}

typedef struct { bool valid, first, last; unsigned macs; } SparseEvent;

static StreamStats run_stream(unsigned count, StreamFixture fixture, StreamOptions options,
                               uint32_t seed, TestTotals *totals)
{
    StreamTile *tiles = (StreamTile *)calloc(count, sizeof *tiles);
    TestDriver s;
    StreamStats stats = {0};
    SparseEvent previous = {0}, previous2 = {0};
    unsigned next_packet = 0, started = 0, produced = 0, consumed = 0;
    uint64_t expected_macs = 0;
    uint32_t rng = seed != 0 ? seed : UINT32_C(0x6d2b79f5);
    check(tiles != NULL && count != 0, "Stream allocation/count");
    for (unsigned n = 0; n < count; ++n) {
        make_stream_tile(&tiles[n], n, fixture, &rng);
        expected_macs += tiles[n].macs;
    }
    driver_reset(&s);
    while (consumed < count) {
        const unsigned t = s.cycle, n = next_packet / TC_K, k = next_packet % TC_K;
        const TcInputPacket *input = NULL;
        const bool old_valid = s.core.result_valid;
        const TcMatrix32 old_result = s.core.result;
        const unsigned old_outstanding = s.core.outstanding;
        const bool ready = t >= options.hold_until &&
            (!options.output_stalls || ((t % 97u) >= 31u && next_random(&rng) % 4u != 0));
        SparseEvent now = {0};
        check(t < count * 200u + 1000u, "Streaming timeout: sent=%u consumed=%u", next_packet, consumed);
        if (n < count) {
            const bool sparse = tiles[n].packet[k].is_sparse;
            const bool can_send = tc_input_ready_for(&s.core, sparse);
            if (!can_send) {
                if (s.core.busy && s.core.is_sparse != sparse) ++stats.mode_waits;
                else if (s.core.is_sparse) ++stats.credit_waits;
            }
            if (can_send && (!options.serial || k != 0 || consumed == n) &&
                (!options.gaps || next_random(&rng) % 3u != 0)) input = &tiles[n].packet[k];
        }
        driver_tick(&s, input, ready);
        check(s.info.input_accepted == (input != NULL), "Stream input handshake");
        check(s.info.result_accepted == (old_valid && ready), "Stream output handshake");
        if (input != NULL) {
            check(s.info.input_k == k && s.info.input_first == (k == 0) &&
                  s.info.input_last == (k == TC_K - 1), "Input tile boundary");
            tiles[n].issue[k] = t;
            if (k == 0) {
                ++started;
                if (old_outstanding != 0) ++stats.overlap_starts;
            }
            if (input->is_sparse) {
                now.valid = true; now.first = k == 0; now.last = k == TC_K - 1;
                now.macs = (unsigned)input->payload.sparse.a.count * input->payload.sparse.b.count;
            }
            ++next_packet;
        }
        /* Contract-level timing oracle: sparse input@t routes@t+1, ACC@t+2.
         * Reservations mean an accepted packet never stalls inside this path.
         */
        check(s.info.mul == now.valid && s.info.route == previous.valid &&
              s.info.acc == previous2.valid, "Stream sparse stage timing at t=%u", t);
        check(s.info.acc_first == (previous2.valid && previous2.first) &&
              s.info.acc_last == (previous2.valid && previous2.last), "Stream first/last propagation");
        if (s.info.sparse_step) check(s.info.macs == previous2.macs, "Stream sparse MAC count");
        previous2 = previous; previous = now;
        if (s.info.result_accepted) {
            check(consumed < produced, "Output consumed before publication");
            check_matrix(&old_result, &tiles[consumed].expected, "stream-consumed");
            ++consumed;
        }
        if (s.info.result_produced) {
            const TcMatrix32 *new_result;
            unsigned latency;
            check(produced < count && tiles[produced].issue[TC_K - 1] != UINT32_MAX,
                  "Result before eight accepted packets");
            latency = tiles[produced].packet[0].is_sparse ? 3u : 15u;
            check(t == tiles[produced].issue[TC_K - 1] + latency, "Stream publication latency");
            new_result = s.core.result_count == 1 ? &s.core.result : &s.core.result_next;
            check_matrix(new_result, &tiles[produced].expected, "stream-published");
            ++produced;
        }
        if (old_valid && !ready) {
            check(s.core.result_valid, "Held output valid dropped");
            check_matrix(&s.core.result, &old_result, "held-output-stability");
        }
        if (s.core.result_valid)
            check_matrix(&s.core.result, &tiles[consumed].expected, "FIFO-head-order");
        check(s.core.outstanding == started - consumed &&
              s.core.result_count == produced - consumed &&
              s.core.outstanding <= TC_RESULT_SLOTS, "Result reservation/accounting");
        check(s.core.busy == (started != consumed), "Busy released with work remaining");
        check(s.info.macs <= TC_DIM * TC_DIM, "Exceeded physical MAC capacity");
        stats.macs += s.info.macs;
        if (s.core.result_count > stats.max_queued) stats.max_queued = s.core.result_count;
        if (s.info.input_accepted && s.info.result_accepted) ++stats.input_and_output;
        if (s.info.input_accepted && s.info.result_produced) ++stats.input_and_publish;
        if (s.info.result_accepted && s.info.result_produced) ++stats.pop_and_push;
        if (options.trace) {
            printf("stream cycle %03u | IN=", t);
            if (input != NULL) printf("tile%u/k%u", n, k); else printf("--");
            printf(" | MUL=%u ROUTE=%u ACC=%u FIRST=%u LAST=%u MACs=%u"
                   " | publish=%u consume=%u outstanding=%u queued=%u\n",
                   (unsigned)s.info.mul, (unsigned)s.info.route, (unsigned)s.info.acc,
                   (unsigned)s.info.acc_first, (unsigned)s.info.acc_last, s.info.macs,
                   (unsigned)s.info.result_produced, (unsigned)s.info.result_accepted,
                   s.core.outstanding, s.core.result_count);
        }
    }
    stats.cycles = s.cycle;
    check(next_packet == count * TC_K && produced == count && stats.macs == expected_macs,
          "Stream dropped/duplicated packets, results or MACs");
    check(!s.core.busy && !s.core.result_valid && s.core.result_count == 0,
          "Stream did not become idle");
    if (fixture == STREAM_FULL && !options.gaps && !options.output_stalls && options.hold_until == 0) {
        check(stats.cycles == (options.serial ? count * 12u : count * TC_K + 4u),
              "Full-pattern elapsed cycles");
        for (unsigned n = 0; n < count; ++n)
            for (unsigned k = 0; k < TC_K; ++k)
                check(tiles[n].issue[k] == n * (options.serial ? 12u : TC_K) + k,
                      "Unexpected bubble between ideal sparse tiles");
    }
    for (unsigned n = 0; n < count; ++n) {
        ++totals->tiles; totals->macs += tiles[n].macs;
        if (tiles[n].packet[0].is_sparse) ++totals->sparse_tiles;
        else ++totals->dense_tiles;
    }
    /* No late output is allowed after the final acknowledged result. */
    for (unsigned n = 0; n < 24; ++n) {
        driver_tick(&s, NULL, true);
        check(!s.core.busy && !s.core.result_valid && s.info.macs == 0, "Late stream work");
    }
    free(tiles);
    return stats;
}

static void test_stream_reset(TestTotals *totals)
{
    StreamTile tiles[2];
    Matrix8 a, b;
    TestDriver s;
    uint32_t rng = 83;
    const unsigned gap[TC_K] = {0};
    make_stream_tile(&tiles[0], 0, STREAM_FULL, &rng);
    make_stream_tile(&tiles[1], 1, STREAM_DIRECTED, &rng);
    for (unsigned cut = 1; cut <= 30; ++cut) {
        unsigned sent = 0;
        driver_reset(&s);
        for (unsigned t = 0; t < cut; ++t) {
            const TcInputPacket *p = NULL;
            if (sent < 2u * TC_K && tc_input_ready_for(&s.core, true)) {
                p = &tiles[sent / TC_K].packet[sent % TC_K]; ++sent;
            }
            driver_tick(&s, p, false);
        }
        tc_reset(&s.core);
        for (unsigned t = 0; t < 24; ++t) {
            driver_tick(&s, NULL, true);
            check(!s.core.busy && !s.core.result_valid && s.core.outstanding == 0 &&
                  s.core.result_count == 0 && s.info.macs == 0, "Overlapped reset leaked work");
        }
        make_matrices(&a, &b, CASE_DUAL, cut % 8u, &rng, true);
        run_tile(&s, &a, &b, CASE_DUAL, gap, 0, false, false, totals);
    }
}

static void test_consume_and_start(TestTotals *totals)
{
    StreamTile first, second;
    TestDriver s;
    uint32_t rng = 97;
    unsigned macs = 0;
    make_stream_tile(&first, 0, STREAM_FULL, &rng);
    make_stream_tile(&second, 1, STREAM_DIRECTED, &rng); /* All-zero next tile. */
    driver_reset(&s);
    for (unsigned t = 0; t <= 10; ++t) {
        driver_tick(&s, t < TC_K ? &first.packet[t] : NULL, false);
        macs += s.info.macs;
    }
    check(s.core.result_valid && s.core.outstanding == 1, "First held boundary result");
    check_matrix(&s.core.result, &first.expected, "boundary-old-result");
    /* Same edge consumes the old result and reserves a new tile: busy must
     * not drop or erase the accepted new packet in an intermediate idle reset.
     */
    driver_tick(&s, &second.packet[0], true);
    macs += s.info.macs;
    check(s.info.input_first && s.info.result_accepted && s.core.busy &&
          s.core.outstanding == 1 && s.core.received == 1, "Simultaneous consume/start");
    for (unsigned k = 1; k < TC_K; ++k) {
        driver_tick(&s, &second.packet[k], true); macs += s.info.macs;
    }
    while (!s.core.result_valid) {
        check(s.cycle < 64, "Boundary result timeout");
        driver_tick(&s, NULL, true); macs += s.info.macs;
    }
    check_matrix(&s.core.result, &second.expected, "boundary-new-result");
    driver_tick(&s, NULL, true);
    check(!s.core.busy && macs == first.macs + second.macs, "Boundary completion/accounting");
    totals->tiles += 2; totals->sparse_tiles += 2; totals->macs += macs;
}

static void test_streaming(unsigned count, unsigned bench_count, bool trace,
                             uint32_t seed, TestTotals *totals)
{
    StreamOptions ideal = {false, false, false, false, 0};
    StreamOptions serial = {false, false, true, false, 0};
    StreamOptions stalled = {false, false, false, false, 128};
    StreamOptions simultaneous = {false, false, false, false, 18};
    StreamOptions random = {true, true, false, false, 0};
    StreamStats a, b, stress;
    run_stream(36, STREAM_DIRECTED, ideal, seed, totals);
    stress = run_stream(12, STREAM_DIRECTED, stalled, seed, totals);
    check(stress.max_queued == TC_RESULT_SLOTS && stress.credit_waits != 0,
          "Did not exercise a full FIFO and reservation backpressure");
    stress = run_stream(12, STREAM_FULL, simultaneous, seed, totals);
    check(stress.pop_and_push != 0, "Did not exercise same-cycle result pop/push");
    run_stream(count, STREAM_SPARSE_RANDOM, random, seed, totals);
    run_stream(count, STREAM_MIXED, random, seed ^ UINT32_C(0xa511e9b3), totals);
    test_stream_reset(totals);
    test_consume_and_start(totals);
    printf("PASS sparse streaming: empty/stored-zero/boundary tiles, long output stalls, FIFO pop/push\n");
    printf("PASS %u sparse + %u mixed-mode random stream tiles, and 30 overlapped reset cases\n", count, count);
    a = run_stream(bench_count, STREAM_FULL, serial, seed, totals);
    b = run_stream(bench_count, STREAM_FULL, ideal, seed, totals);
    if (bench_count > 1)
        check(b.overlap_starts == bench_count - 1 && b.input_and_output != 0 &&
              b.input_and_publish != 0, "Ideal run did not overlap tiles/results");
    printf("BENCH full 8x8 outer-product packets, %u tiles; all results checked; includes initial fill/final output handshake\n", bench_count);
    printf("  serial scheduling : %u cycles, %llu MACs, utilization %.4f%%\n", a.cycles,
           (unsigned long long)a.macs, 100.0 * (double)a.macs / (64.0 * a.cycles));
    printf("  sparse overlap    : %u cycles, %llu MACs, utilization %.4f%%; %.4fx throughput\n", b.cycles,
           (unsigned long long)b.macs, 100.0 * (double)b.macs / (64.0 * b.cycles),
           (double)a.cycles / b.cycles);
    if (trace) {
        ideal.trace = true;
        printf("\n--- three full sparse tiles; starts at cycles 0, 8, 16 ---\n");
        run_stream(3, STREAM_FULL, ideal, seed, totals);
    }
}

typedef struct {
    unsigned tests, stream_tiles, bench_tiles;
    uint32_t seed;
    int selected;
    bool demo, trace, bubbles, stream_trace;
} Options;

static bool parse_u32(const char *text, uint32_t *out)
{
    char *end;
    unsigned long value;
    if (text[0] == '\0' || text[0] == '-' || text[0] == '+') return false;
    errno = 0;
    value = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' || value > UINT32_MAX) return false;
    *out = (uint32_t)value;
    return true;
}

static void usage(const char *program)
{
    printf("Usage: %s [--mode all|dense|hybrid|dual|dense-unstructured]\n"
           "       [--tests N] [--seed N] [--demo] [--trace] [--bubbles]\n"
           "       [--stream-tiles N] [--bench-tiles N] [--stream-trace]\n"
           "Default: eight directed + 1000 random tiles per mode, and reset/contract tests.\n"
           "--tests N       random tiles per selected case (0..100000)\n"
           "--trace         show one demo tile per selected case, cycle by cycle\n"
           "--demo          show demo A, B, C and timing\n"
           "--bubbles       insert gaps in demo; randomized tests always exercise gaps\n"
           "--seed N        unsigned 32-bit seed; zero maps to 0x6d2b79f5\n", program);
    printf("--stream-tiles N  tiles per random streaming suite (1..100000, default 1000)\n"
           "--bench-tiles N   full-vector benchmark tiles (1..100000, default 100)\n"
           "--stream-trace    trace three overlapping sparse tiles\n"
           "--mode filters the original single-tile tests; streaming/regression suites always run.\n");
}

int main(int argc, char **argv)
{
    Options o = {1000, 1000, 100, UINT32_C(20260915), -1, false, false, false, false};
    TestTotals totals = {0};
    uint32_t rng;
    TestDriver system;
    for (int arg = 1; arg < argc; ++arg) {
        if (strcmp(argv[arg], "--help") == 0 || strcmp(argv[arg], "-h") == 0) {
            usage(argv[0]); return EXIT_SUCCESS;
        } else if (strcmp(argv[arg], "--demo") == 0) {
            o.demo = true;
        } else if (strcmp(argv[arg], "--trace") == 0) {
            o.demo = o.trace = true;
        } else if (strcmp(argv[arg], "--bubbles") == 0) {
            o.bubbles = true;
        } else if (strcmp(argv[arg], "--stream-trace") == 0) {
            o.stream_trace = true;
        } else if (strcmp(argv[arg], "--mode") == 0 && arg + 1 < argc) {
            const char *name = argv[++arg];
            o.selected = -2;
            if (strcmp(name, "all") == 0) o.selected = -1;
            for (int n = 0; n < CASE_COUNT; ++n)
                if (strcmp(name, case_names[n]) == 0) o.selected = n;
            check(o.selected != -2, "Unknown mode: %s", name);
        } else if ((strcmp(argv[arg], "--tests") == 0 || strcmp(argv[arg], "--seed") == 0 ||
                    strcmp(argv[arg], "--stream-tiles") == 0 || strcmp(argv[arg], "--bench-tiles") == 0) &&
                   arg + 1 < argc) {
            const bool is_tests = strcmp(argv[arg], "--tests") == 0;
            const bool is_stream = strcmp(argv[arg], "--stream-tiles") == 0;
            const bool is_bench = strcmp(argv[arg], "--bench-tiles") == 0;
            uint32_t value = 0;
            ++arg;
            check(parse_u32(argv[arg], &value), "Invalid unsigned integer: %s", argv[arg]);
            if (is_tests) {
                check(value <= 100000u, "--tests must be at most 100000");
                o.tests = (unsigned)value;
            } else if (is_stream || is_bench) {
                check(value >= 1u && value <= 100000u, "Stream/benchmark tiles must be 1..100000");
                if (is_stream) o.stream_tiles = (unsigned)value;
                else o.bench_tiles = (unsigned)value;
            } else o.seed = value;
        } else {
            fprintf(stderr, "Unknown or incomplete option: %s\n", argv[arg]);
            usage(argv[0]); return EXIT_FAILURE;
        }
    }
    rng = o.seed != 0 ? o.seed : UINT32_C(0x6d2b79f5);
    printf("Standalone INT8 tensor core (decoded input): dense=systolic; sparse=outer product; seed=%lu\n",
           (unsigned long)o.seed);
    driver_reset(&system);
    for (int mode = 0; mode < CASE_COUNT; ++mode) {
        const CaseKind kind = (CaseKind)mode;
        Matrix8 a, b;
        unsigned gap[TC_K] = {0};
        if (o.selected >= 0 && o.selected != mode) continue;
        if (o.demo) {
            TestDriver demo_system;
            TestTotals demo_totals = {0};
            driver_reset(&demo_system);
            make_matrices(&a, &b, kind, 4, &rng, false);
            for (unsigned k = 0; k < TC_K; ++k) gap[k] = o.bubbles ? k % 3u : 0u;
            (void)run_tile(&demo_system, &a, &b, kind, gap, 2, o.trace, true, &demo_totals);
        }
        for (unsigned variant = 0; variant < 8; ++variant) {
            make_matrices(&a, &b, kind, variant, &rng, false);
            for (unsigned k = 0; k < TC_K; ++k) gap[k] = variant % 2u != 0 ? k % 3u : 0u;
            (void)run_tile(&system, &a, &b, kind, gap, variant % 4u, false, false, &totals);
        }
        for (unsigned test = 0; test < o.tests; ++test) {
            make_matrices(&a, &b, kind, test, &rng, true);
            for (unsigned k = 0; k < TC_K; ++k)
                gap[k] = test % 2u == 0 ? 0u : (unsigned)(next_random(&rng) % 4u);
            (void)run_tile(&system, &a, &b, kind, gap,
                           (unsigned)(next_random(&rng) % 5u), false, false, &totals);
        }
        printf("PASS %-20s : 8 directed + %u random tiles\n", case_names[kind], o.tests);
    }
    test_rejection_and_reset(&totals);
    test_mode_switches(&totals);
    test_stored_zeros(&totals);
    test_streaming(o.stream_tiles, o.bench_tiles, o.stream_trace, o.seed, &totals);
    printf("PASS input-contract rejection and 48 reset/restart cases\n");
    printf("PASS 16 tiles with dense/sparse switching without reset\n");
    printf("PASS stored zero values in both sparse vectors\n");
    printf("ALL PASS: %u tiles (%u dense, %u sparse); %u checked MACs\n",
           totals.tiles, totals.dense_tiles, totals.sparse_tiles, totals.macs);
    return EXIT_SUCCESS;
}
