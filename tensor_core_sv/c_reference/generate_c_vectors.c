/* Replay the ORIGINAL C testbench, intercepting its public reset/tick calls.
 * The model and original tests are compiled unchanged in separate units.
 * Output: portable text vectors; no DPI, C ABI, or binary struct layout.
 */
#include "tensor_core_model.h"
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <assert.h>

static void logged_reset(TensorCore *q);
static TcStatus logged_tick(TensorCore *q, bool valid, const TcInputPacket *p,
                            bool ready, TcTickInfo *info);

#define tc_reset logged_reset
#define tc_tick logged_tick
#define main original_testbench_main
#include "tb_tensor_core.c"
#undef main
#undef tc_tick
#undef tc_reset

static FILE *vectors;
static unsigned long record_count, reset_count, host_only_count;

static uint32_t mix(uint32_t h, uint32_t v)
{
    return (h ^ v) * UINT32_C(16777619);
}

static uint32_t hash_token(uint32_t h, TcToken t)
{
    h = mix(h, t.valid); h = mix(h, t.last);
    return mix(h, (uint8_t)t.value);
}

/* Logical-field hash, not a hash of host struct padding/endianness.
 * Hardware has 3-bit indexes; inactive C padding indexes are normalized.
 */
static uint32_t state_hash(const TensorCore *q)
{
    uint32_t h = UINT32_C(2166136261);
    h = mix(h, q->busy); h = mix(h, q->is_sparse);
    h = mix(h, q->finish_pending); h = mix(h, q->result_valid);
    h = mix(h, q->received); h = mix(h, q->outstanding);
    h = mix(h, q->result_count);
    for (unsigned i = 0; i < 8; ++i)
        for (unsigned j = 0; j < 8; ++j) h = mix(h, (uint32_t)q->result.v[i][j]);
    for (unsigned i = 0; i < 8; ++i)
        for (unsigned j = 0; j < 8; ++j) h = mix(h, (uint32_t)q->result_next.v[i][j]);
    if (q->is_sparse) {
        const TcSparseState *s = &q->state.sparse;
        h = mix(h, s->mul.valid); h = mix(h, s->mul.first); h = mix(h, s->mul.last);
        h = mix(h, s->mul.a_count); h = mix(h, s->mul.b_count);
        for (unsigned p = 0; p < 8; ++p) h = mix(h, s->mul.a_index[p] & 7u);
        for (unsigned p = 0; p < 8; ++p) h = mix(h, s->mul.b_index[p] & 7u);
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned j = 0; j < 8; ++j) h = mix(h, (uint16_t)s->mul.product[i][j]);
        h = mix(h, s->route.valid); h = mix(h, s->route.first); h = mix(h, s->route.last);
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned j = 0; j < 8; ++j) {
                h = mix(h, s->route.enable[i][j]);
                h = mix(h, (uint16_t)s->route.delta[i][j]);
            }
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned j = 0; j < 8; ++j) h = mix(h, (uint32_t)s->acc.v[i][j]);
    } else {
        const TcDenseState *d = &q->state.dense;
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned n = 0; n < 7; ++n) {
                h = hash_token(h, d->a_delay[i][n]);
                h = hash_token(h, d->b_delay[i][n]);
            }
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned j = 0; j < 8; ++j) {
                h = hash_token(h, d->pe[i][j].a);
                h = hash_token(h, d->pe[i][j].b);
                h = mix(h, (uint32_t)d->pe[i][j].acc);
            }
    }
    return h;
}

static uint32_t pack_info(const TcTickInfo *i)
{
    uint32_t w = 0;
#define FLAG(f) w = (w << 1) | (unsigned)i->f
    FLAG(input_accepted); FLAG(dense_step); FLAG(sparse_step); FLAG(result_accepted);
    FLAG(input_first); FLAG(input_last); FLAG(result_produced); FLAG(mul);
    FLAG(route); FLAG(acc); FLAG(acc_first); FLAG(acc_last);
#undef FLAG
    return (((w << 4) | i->input_k) << 7) | i->macs;
}

typedef struct { unsigned nibble, bits; } HexWriter;
static void bits_out(HexWriter *w, unsigned value, unsigned width)
{
    for (unsigned n = width; n != 0; --n) {
        w->nibble = (w->nibble << 1) | ((value >> (n - 1)) & 1u);
        if (++w->bits == 4) {
            fputc("0123456789abcdef"[w->nibble], vectors);
            w->nibble = w->bits = 0;
        }
    }
}

static void packet_out(const TcInputPacket *p)
{
    const TcInputPacket empty = {0};
    HexWriter w = {0};
    if (p == NULL) p = &empty;
    bits_out(&w, 0, 3); /* left pad 185 bits to 47 hex digits */
    bits_out(&w, p->is_sparse, 1);
    if (p->is_sparse) {
        for (unsigned side = 0; side < 2; ++side) {
            const TcSparseVector *v = side == 0 ? &p->payload.sparse.a : &p->payload.sparse.b;
            bits_out(&w, v->count, 4);
            for (int n = 7; n >= 0; --n) bits_out(&w, (uint8_t)v->value[n], 8);
            for (int n = 7; n >= 0; --n) bits_out(&w, v->index[n] & 7u, 3);
        }
    } else {
        for (int n = 7; n >= 0; --n) bits_out(&w, (uint8_t)p->payload.dense.dense_a[n], 8);
        for (int n = 7; n >= 0; --n) bits_out(&w, (uint8_t)p->payload.dense.dense_b[n], 8);
        for (unsigned n = 0; n < 7; ++n) bits_out(&w, 0, 8);
    }
    assert(w.bits == 0);
}

static void matrix_out(const TcMatrix32 *m)
{
    for (int i = 7; i >= 0; --i)
        for (int j = 7; j >= 0; --j) fprintf(vectors, "%08" PRIx32, (uint32_t)m->v[i][j]);
}

static void emit(const TensorCore *q, bool reset, bool valid, const TcInputPacket *p,
                 bool ready, bool base_ready, bool mode_ready, TcStatus status,
                 const TcTickInfo *info)
{
    fprintf(vectors, "%u %u %u ", (unsigned)reset, (unsigned)valid, (unsigned)ready);
    packet_out(p);
    fprintf(vectors, " %u %u %u %06" PRIx32 " %u %u %08" PRIx32 " ",
            (unsigned)base_ready, (unsigned)mode_ready, (unsigned)status, pack_info(info),
            (unsigned)q->result_valid, (unsigned)q->busy, state_hash(q));
    matrix_out(&q->result); fputc(' ', vectors);
    matrix_out(&q->result_next); fputc('\n', vectors);
    ++record_count;
}

static void logged_reset(TensorCore *q)
{
    const TcTickInfo zero = {0};
    tc_reset(q);
    emit(q, true, false, NULL, false, true, true, TC_OK, &zero);
    ++reset_count;
}

static TcStatus logged_tick(TensorCore *q, bool valid, const TcInputPacket *p,
                            bool ready, TcTickInfo *info)
{
    TcTickInfo local;
    const bool base_ready = tc_input_ready(q);
    const bool mode_ready = tc_input_ready_for(q, p != NULL && p->is_sparse);
    const TcStatus status = tc_tick(q, valid, p, ready, &local);
    bool representable = q != NULL && (!valid || p != NULL);
    if (valid && p != NULL && p->is_sparse) {
        for (unsigned side = 0; side < 2; ++side) {
            const TcSparseVector *v = side == 0 ? &p->payload.sparse.a : &p->payload.sparse.b;
            for (unsigned n = 0; n < v->count && n < 8; ++n)
                if (v->index[n] >= 8) representable = false;
        }
    }
    if (info != NULL) *info = local;
    if (representable) emit(q, false, valid, p, ready, base_ready, mode_ready, status, &local);
    else {
        /* Pointer errors and active index>=8 cannot exist on this hardware
         * interface. The ORIGINAL C tests still check these rejections. */
        check(status != TC_OK, "Unrepresentable accepted input");
        ++host_only_count;
    }
    return status;
}

int main(int argc, char **argv)
{
    int rc;
    if (argc < 2) {
        fprintf(stderr, "Usage: %s output.txt [original testbench options]\n", argv[0]);
        return EXIT_FAILURE;
    }
    vectors = fopen(argv[1], "w");
    if (vectors == NULL) { perror(argv[1]); return EXIT_FAILURE; }
    rc = original_testbench_main(argc - 1, argv + 1);
    if (fclose(vectors) != 0) { perror("fclose vectors"); return EXIT_FAILURE; }
    printf("C VECTORS: %lu records, %lu reset records, %lu C-only rejection calls\n",
           record_count, reset_count, host_only_count);
    return rc;
}
