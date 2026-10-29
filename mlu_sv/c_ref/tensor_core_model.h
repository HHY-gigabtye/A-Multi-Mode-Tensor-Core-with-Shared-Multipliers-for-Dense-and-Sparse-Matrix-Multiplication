#ifndef TENSOR_CORE_MODEL_H
#define TENSOR_CORE_MODEL_H

#include <stdbool.h>
#include <stdint.h>

/* The result FIFO below is explicitly implemented with two physical slots. */
enum { TC_DIM = 8, TC_K = 8, TC_RESULT_SLOTS = 2 };

/* Decoded DU/TIA output. Field meanings match du_tia_output_t.
 * No bitmap, 2:4 mask, compiler mode, k_position, or decoder is needed.
 * C structs are not binary-compatible with an SV packed struct/union.
 * Data is signed INT8; cast the RTL's 8-bit vectors as signed at each MAC.
 */
typedef struct {
    int8_t dense_a[TC_DIM];       /* A[:,k], before input skew. */
    int8_t dense_b[TC_DIM];       /* B[k,:], before input skew. */
} TcDensePayload;

typedef struct {
    uint8_t count;               /* 0..8; only this prefix is valid. */
    int8_t value[TC_DIM];        /* Stored zero values are legal. */
    uint8_t index[TC_DIM];       /* Increasing original coordinates, 0..7. */
} TcSparseVector;

typedef struct { TcSparseVector a, b; } TcSparsePayload;
typedef struct {
    bool is_sparse;              /* false: systolic; true: outer product. */
    union {
        TcDensePayload dense;
        TcSparsePayload sparse;
    } payload;
} TcInputPacket;

typedef struct { int32_t v[TC_DIM][TC_DIM]; } TcMatrix32;

/* Model registers. Exposed to make the cycle-level state easy to inspect. */
typedef struct { bool valid, last; int8_t value; } TcToken;
typedef struct {
    TcToken a, b;                /* One registered hop right/down. */
    int32_t acc;                 /* Output-stationary accumulator. */
} TcPE;
typedef struct {
    TcToken a_delay[TC_DIM][TC_DIM - 1]; /* Lane i uses i slots. */
    TcToken b_delay[TC_DIM][TC_DIM - 1];
    TcPE pe[TC_DIM][TC_DIM];
} TcDenseState;

typedef struct {
    bool valid, first, last;
    uint8_t a_count, b_count;
    uint8_t a_index[TC_DIM], b_index[TC_DIM];
    int16_t product[TC_DIM][TC_DIM];    /* Packed-rank coordinates. */
} TcMultiplyReg;
typedef struct {
    bool valid, first, last;
    bool enable[TC_DIM][TC_DIM];
    int16_t delta[TC_DIM][TC_DIM];      /* Original row/column coordinates. */
} TcRouteReg;
typedef struct {
    TcMultiplyReg mul;
    TcRouteReg route;
    TcMatrix32 acc;
} TcSparseState;

typedef struct {
    bool busy, is_sparse, finish_pending, result_valid;
    unsigned received;           /* Dense: 0..8. Sparse: next input k, 0..7. */
    unsigned outstanding;        /* Started tiles whose results are not consumed. */
    unsigned result_count;       /* Completed results: 0..TC_RESULT_SLOTS. */
    TcMatrix32 result;           /* FIFO head; valid while result_valid is true. */
    TcMatrix32 result_next;      /* Second FIFO slot, valid if result_count == 2. */
    union { TcDenseState dense; TcSparseState sparse; } state;
} TensorCore;

/* Optional observations for tests/trace, not extra packet signals. */
typedef struct {
    bool input_accepted, dense_step, sparse_step, result_accepted;
    bool input_first, input_last, result_produced;
    bool mul, route, acc, acc_first, acc_last;
    unsigned input_k, macs;
} TcTickInfo;

typedef enum {
    TC_OK = 0,
    TC_BAD_ARGUMENT,
    TC_BAD_SPARSE_VECTOR,
    TC_MODE_CHANGE,
    TC_NOT_READY
} TcStatus;

void tc_reset(TensorCore *core);
/* Readiness for the current mode (either mode when idle). Does not use the
 * current result_ready input: a credit freed this tick is visible next tick.
 */
bool tc_input_ready(const TensorCore *core);
/* Use this when the next packet may change dense/sparse mode. A mode change
 * waits until every prior result has been consumed and busy becomes false.
 */
bool tc_input_ready_for(const TensorCore *core, bool is_sparse);
const char *tc_status_name(TcStatus status);

/* One call = one clock edge, reading old registers before committing new ones.
 * Feed DU/TIA out_valid into in_valid and its decoded output into in_packet.
 * in_valid=false inserts a bubble; in_packet is ignored and may be NULL.
 * Exactly 8 accepted packets form one tile, ordered k=0..7. No explicit
 * k/first/last enters the core; markers are generated from the input count.
 * Sparse: packet 9 can start the next tile without draining the pipeline.
 * A result slot is reserved on each tile's first accepted packet. Already
 * started tiles can finish even if the output is blocked. At most two tiles
 * may be outstanding; only the first packet of a new tile can wait for credit.
 * Dense: drain and consume the result before starting the next tile, unchanged.
 * Busy includes partially received tiles, pipeline work and unconsumed results.
 * Switch dense/sparse mode only when idle; all sparse formats use one path.
 * A result is consumed only if result_valid was true BEFORE this call and
 * result_ready is true. Read/copy core->result BEFORE calling tc_tick when
 * consuming it: the FIFO head can advance or be replaced on the same tick.
 * Sparse input may overlap result publication or consumption. The FIFO also
 * supports consuming its old head and publishing a new result on the same tick.
 * tc_input_ready[_for]() must be checked before offering an input. This API
 * retains its original strict contract: valid input while not ready is an
 * error, NOT a stalled clock. To drain while waiting, call with in_valid=false.
 * Non-OK returns reject the call without advancing core state.
 * info is optional (NULL). Other pointer arguments must not alias core.
 * Reset once before the first call. No allocation or main() in the core.
 */
TcStatus tc_tick(TensorCore *core, bool in_valid,
                 const TcInputPacket *in_packet, bool result_ready,
                 TcTickInfo *info);

#endif
