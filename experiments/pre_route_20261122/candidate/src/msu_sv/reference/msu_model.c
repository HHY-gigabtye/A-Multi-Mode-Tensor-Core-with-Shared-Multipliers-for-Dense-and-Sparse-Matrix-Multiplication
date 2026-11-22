#include "msu_model.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

void msu_reset(Msu *q)
{
    assert(q != NULL);
    memset(q, 0, sizeof *q);
}

void msu_peek(const Msu *q, MsuOutputs *out)
{
    assert(q != NULL && out != NULL);
    memset(out, 0, sizeof *out);
    out->result_ready = q->count < IO_TILE_BUFFERS;
    if (q->count != 0) {
        const MsuBuffer *b = &q->buffer[q->head];
        out->write_valid = true;
        out->write_meta = b->meta;
        out->write_addr = b->meta.dst_addr + q->row*IO_BEAT_BYTES;
        out->write_last = q->row == 7u;
        for (unsigned j = 0; j < 8; ++j) {
            uint32_t value = (uint32_t)b->result.v[q->row][j];
            for (unsigned byte = 0; byte < 4; ++byte)
                out->write_data[4u*j+byte] = (uint8_t)(value >> (byte*8u));
        }
    }
}

IoStatus msu_tick(Msu *q, const MsuInputs *in, MsuEvents *events)
{
    MsuOutputs out;
    MsuEvents e = {0};
    Msu next;
    if (q == NULL || in == NULL) return IO_BAD_ARGUMENT;
    if (events != NULL) *events = e;
    msu_peek(q, &out);
    next = *q;
    if (in->result_valid && out.result_ready) {
        unsigned tail = (q->head + q->count) % IO_TILE_BUFFERS;
        if (in->meta.dst_addr % 32u != 0 ||
            in->meta.dst_addr > UINT64_MAX-255u) return IO_BAD_FORMAT;
        next.buffer[tail].meta = in->meta;
        next.buffer[tail].result = in->result;
        ++next.count;
        e.result_accepted = true;
    }
    if (out.write_valid && in->write_ready) {
        e.beat_written = true;
        if (out.write_last) {
            e.tile_done = true;
            e.completed = out.write_meta;
            next.head = (q->head+1u) % IO_TILE_BUFFERS;
            --next.count;
            next.row = 0;
        } else ++next.row;
    }
    assert(next.count <= IO_TILE_BUFFERS && next.row < 8);
    *q = next;
    if (events != NULL) *events = e;
    return IO_OK;
}
