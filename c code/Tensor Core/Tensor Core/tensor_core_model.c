/*
 * Tensor Core ONLY: decoded DU/TIA packets -> 8x8 INT32 result.
 * No DU/TIA implementation, bitmap decoding, 2:4 decoding, or main().
 * See tensor_core_model.h for the input packet and public API.
 * Compile with tb_tensor_core.c to run the separate tests.
 *
 * INT8 x INT8 -> INT32, M=N=K=8, initial sums zero.
 * Dense: one tile at a time. Sparse: consecutive tiles overlap in the pipeline.
 * is_sparse=0: output-stationary systolic; is_sparse=1: outer product.
 * The first accepted decoded packet is cycle 0 (no S0-S3 delay).
 * Consecutive packets 0..7: dense result_valid@22; sparse result_valid@10.
 * Sparse with output ready: next tile starts@8, next result_valid@18.
 * Two reserved result slots guarantee room for all accepted work. Input pauses
 * only at a new sparse tile boundary when both slots are reserved/occupied.
 * Dense and sparse are behavioral branches; physical hardware sharing,
 * timing closure and Fmax are not implied by this C model.
 */
#include "tensor_core_model.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

/* Host-side contract checks, not additional pipeline stages. */
static bool valid_vector(const TcSparseVector *v)
{
    if (v->count > TC_DIM) return false;
    for (unsigned p = 0; p < v->count; ++p) {
        if (v->index[p] >= TC_DIM) return false;
        if (p > 0 && v->index[p] <= v->index[p - 1]) return false;
    }
    /* Unused lanes are ignored. Zero values inside the prefix are legal. */
    return true;
}

void tc_reset(TensorCore *core)
{
    assert(core != NULL);
    memset(core, 0, sizeof *core);
}

bool tc_input_ready(const TensorCore *core)
{
    if (core == NULL) return false;
    if (!core->busy) return true;
    if (core->is_sparse)
        return core->received != 0 || core->outstanding < TC_RESULT_SLOTS;
    return !core->result_valid && !core->finish_pending && core->received < TC_K;
}

bool tc_input_ready_for(const TensorCore *core, bool is_sparse)
{
    return tc_input_ready(core) && (!core->busy || core->is_sparse == is_sparse);
}

const char *tc_status_name(TcStatus status)
{
    switch (status) {
    case TC_OK: return "OK";
    case TC_BAD_ARGUMENT: return "NULL core or valid packet pointer";
    case TC_BAD_SPARSE_VECTOR: return "Invalid sparse count/index order/range";
    case TC_MODE_CHANGE: return "Drain all prior tiles/results before changing is_sparse";
    case TC_NOT_READY: return "Input not ready: drain dense work or wait for a sparse result credit";
    default: return "Unknown status";
    }
}

/* Dense: output-stationary systolic, one MAC / hop per PE per tick. */
static TcToken skew_tick(TcToken delay[TC_DIM - 1], unsigned length, TcToken input)
{
    TcToken output;
    if (length == 0) return input;
    output = delay[length - 1];
    /* Descending update preserves old values, like simultaneous registers. */
    for (unsigned n = length - 1; n > 0; --n) delay[n] = delay[n - 1];
    delay[0] = input;
    return output;
}

static bool dense_tick(TcDenseState *q, const TcDensePayload *input,
                       bool last, TcTickInfo *info)
{
    TcToken left[TC_DIM], top[TC_DIM];
    TcPE next[TC_DIM][TC_DIM];
    bool finished = false;
    info->dense_step = true;
    for (unsigned lane = 0; lane < TC_DIM; ++lane) {
        TcToken a = {0}, b = {0};
        if (input != NULL) {
            a.valid = b.valid = true;
            a.last = b.last = last;
            a.value = input->dense_a[lane];
            b.value = input->dense_b[lane];
        }
        left[lane] = skew_tick(q->a_delay[lane], lane, a);
        top[lane] = skew_tick(q->b_delay[lane], lane, b);
    }
    for (unsigned i = 0; i < TC_DIM; ++i) {
        for (unsigned j = 0; j < TC_DIM; ++j) {
            const TcToken a = j == 0 ? left[i] : q->pe[i][j - 1].a;
            const TcToken b = i == 0 ? top[j] : q->pe[i - 1][j].b;
            next[i][j] = q->pe[i][j];
            next[i][j].a = a;
            next[i][j].b = b;
            assert(a.valid == b.valid);
            if (a.valid && b.valid) {
                assert(a.last == b.last);
                next[i][j].acc += (int32_t)a.value * (int32_t)b.value;
                ++info->macs;
                if (i == TC_DIM - 1 && j == TC_DIM - 1 && a.last) finished = true;
            }
        }
    }
    /* Do not update q->pe inside the nested loop: that would cross several
     * PEs in one C function call instead of exactly one PE per clock.
     */
    memcpy(q->pe, next, sizeof next);
    return finished;
}

/* Sparse: MUL -> ROUTE -> ACC, with a register between each operation. */
static bool sparse_tick(TcSparseState *q, const TcSparsePayload *input,
                        bool first, bool last, TcTickInfo *info)
{
    TcMultiplyReg next_mul = {0};
    TcRouteReg next_route = {0};
    bool finished = false;
    info->sparse_step = true;
    /* ACC reads only the OLD route register. */
    if (q->route.valid) {
        info->acc = true;
        info->acc_first = q->route.first;
        info->acc_last = q->route.last;
        /* Clear only when this tile's FIRST packet reaches ACC, including
         * an empty outer product. Never clear at its input/MUL boundary.
         * The previous tile has already been copied to the result FIFO.
         */
        if (q->route.first) memset(&q->acc, 0, sizeof q->acc);
        for (unsigned i = 0; i < TC_DIM; ++i)
            for (unsigned j = 0; j < TC_DIM; ++j)
                if (q->route.enable[i][j]) {
                    q->acc.v[i][j] += (int32_t)q->route.delta[i][j];
                    ++info->macs;
                }
        finished = q->route.last;
    }
    /* ROUTE reads only the OLD multiplication register. */
    if (q->mul.valid) {
        info->route = true;
        next_route.valid = true;
        next_route.first = q->mul.first;
        next_route.last = q->mul.last;
        for (unsigned p = 0; p < q->mul.a_count; ++p) {
            for (unsigned r = 0; r < q->mul.b_count; ++r) {
                const unsigned i = q->mul.a_index[p];
                const unsigned j = q->mul.b_index[r];
                assert(i < TC_DIM && j < TC_DIM);
                assert(!next_route.enable[i][j]);
                next_route.enable[i][j] = true;
                next_route.delta[i][j] = q->mul.product[p][r];
            }
        }
    }
    /* MUL: p and r are packed ranks, not the original row/column numbers. */
    if (input != NULL) {
        info->mul = true;
        next_mul.valid = true;
        next_mul.first = first;
        next_mul.last = last;
        next_mul.a_count = input->a.count;
        next_mul.b_count = input->b.count;
        memcpy(next_mul.a_index, input->a.index, sizeof next_mul.a_index);
        memcpy(next_mul.b_index, input->b.index, sizeof next_mul.b_index);
        for (unsigned p = 0; p < input->a.count; ++p)
            for (unsigned r = 0; r < input->b.count; ++r)
                next_mul.product[p][r] =
                    (int16_t)((int32_t)input->a.value[p] * (int32_t)input->b.value[r]);
    }
    q->mul = next_mul;
    q->route = next_route;
    return finished;
}

/* Completed-result FIFO. result is the externally visible registered head.
 * Credits are reserved before a tile enters MUL, not when its result appears.
 */
static void publish_result(TensorCore *q, const TcMatrix32 *value, TcTickInfo *info)
{
    assert(q->result_count < TC_RESULT_SLOTS);
    assert(q->result_count < q->outstanding);
    if (q->result_count == 0) q->result = *value;
    else q->result_next = *value;
    ++q->result_count;
    q->result_valid = true;
    info->result_produced = true;
}

static void consume_result(TensorCore *q, TcTickInfo *info)
{
    assert(q->result_count != 0 && q->outstanding != 0);
    if (q->result_count == 2) q->result = q->result_next;
    --q->result_count;
    --q->outstanding;
    q->result_valid = q->result_count != 0;
    info->result_accepted = true;
}

/* Tile control: all readiness/validation uses the state before this edge. */
TcStatus tc_tick(TensorCore *q, bool in_valid, const TcInputPacket *in_packet,
                 bool result_ready, TcTickInfo *info)
{
    TcTickInfo unused_info;
    const TcInputPacket *input = in_valid ? in_packet : NULL;
    bool first = false, last = false, old_result_valid;
    if (info == NULL) info = &unused_info;
    memset(info, 0, sizeof *info);

    /* Reject bad calls before touching any clocked core state. */
    if (q == NULL || (in_valid && input == NULL)) return TC_BAD_ARGUMENT;
    if (input != NULL) {
        if (!tc_input_ready(q)) return TC_NOT_READY;
        if (q->busy && input->is_sparse != q->is_sparse) return TC_MODE_CHANGE;
        if (input->is_sparse &&
            (!valid_vector(&input->payload.sparse.a) ||
             !valid_vector(&input->payload.sparse.b)))
            return TC_BAD_SPARSE_VECTOR;
    }

    old_result_valid = q->result_valid;
    if (old_result_valid && result_ready) consume_result(q, info);
    if (!q->busy) {
        if (input == NULL) return TC_OK;
        tc_reset(q);               /* Start a new idle-to-busy mode epoch. */
        q->busy = true;
        q->is_sparse = input->is_sparse;
    }
    if (!q->is_sparse && old_result_valid) {
        q->busy = q->outstanding != 0;
        return TC_OK;              /* Dense still waits for its result handshake. */
    }
    if (q->is_sparse && q->finish_pending) {
        /* Read the OLD ACC before sparse_tick may clear it for the next tile.
         * This preserves result_valid@last_input+3 without stopping MUL/ROUTE.
         */
        publish_result(q, &q->state.sparse.acc, info);
        q->finish_pending = false;
    } else if (!q->is_sparse && q->finish_pending) {
        TcMatrix32 result;
        assert(input == NULL && q->received == TC_K);
        for (unsigned i = 0; i < TC_DIM; ++i)
            for (unsigned j = 0; j < TC_DIM; ++j)
                result.v[i][j] = q->state.dense.pe[i][j].acc;
        publish_result(q, &result, info);
        q->finish_pending = false;
        return TC_OK;
    }
    if (input != NULL) {
        info->input_accepted = true;
        info->input_k = q->received;
        first = q->received == 0;
        last = q->received == TC_K - 1;
        info->input_first = first;
        info->input_last = last;
        if (first) {
            assert(q->outstanding < TC_RESULT_SLOTS);
            ++q->outstanding;      /* Reserve storage for this tile's result. */
        }
        q->received = q->is_sparse && last ? 0 : q->received + 1;
    }
    if (q->is_sparse)
        q->finish_pending = sparse_tick(&q->state.sparse,
            input != NULL ? &input->payload.sparse : NULL, first, last, info);
    else
        q->finish_pending = dense_tick(&q->state.dense,
            input != NULL ? &input->payload.dense : NULL, last, info);
    q->busy = q->outstanding != 0;
    assert(q->result_count <= q->outstanding && q->outstanding <= TC_RESULT_SLOTS);
    assert(q->result_valid == (q->result_count != 0));
    return TC_OK;
}
