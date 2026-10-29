#ifndef MSU_MODEL_H
#define MSU_MODEL_H
#include "io_types.h"

typedef struct { IoMeta meta; TcMatrix32 result; } MsuBuffer;
typedef struct {
    MsuBuffer buffer[IO_TILE_BUFFERS];
    unsigned head, count, row;
} Msu;
typedef struct {
    bool result_ready;
    bool write_valid;
    uint64_t write_addr;
    uint8_t write_data[IO_BEAT_BYTES];
    bool write_last;
    IoMeta write_meta;
} MsuOutputs;
typedef struct {
    bool result_valid;
    IoMeta meta;
    TcMatrix32 result;
    bool write_ready;
} MsuInputs;
typedef struct {
    bool result_accepted, beat_written, tile_done;
    IoMeta completed;
} MsuEvents;

/* Two whole-result buffers. Standard valid/ready with stable stalled payload.
 * No arithmetic: accepts a completed 8x8 INT32 result, writes 8 row beats.
 * Each write_data[4*j +: 4] is C[row][j] in little-endian byte order.
 * write_ready means the memory endpoint commits this beat on this edge.
 * tile_done pulses only on acceptance of row 7, not on TC result reception.
 * No separate write-response/error channel in this simplified interface.
 * All observations before tick; failing calls leave state unchanged. */
void msu_reset(Msu *q);
void msu_peek(const Msu *q, MsuOutputs *out);
IoStatus msu_tick(Msu *q, const MsuInputs *in, MsuEvents *events);
#endif
