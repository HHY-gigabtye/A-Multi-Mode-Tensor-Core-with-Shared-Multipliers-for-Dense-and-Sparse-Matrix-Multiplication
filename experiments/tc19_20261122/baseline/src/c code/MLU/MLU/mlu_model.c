#include "mlu_model.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

static int find_phase(const Mlu *q, MluPhase phase)
{
    for (unsigned n = 0; n < q->count; ++n) {
        unsigned s = (q->head + n) % IO_TILE_BUFFERS;
        if (q->buffer[s].phase == phase) return (int)s;
    }
    return -1;
}

static void make_frame(const MluBuffer *slot, unsigned k, IoFrame *out)
{
    const uint8_t *image = slot->image;
    IoDuPacket *p = &out->packet;
    memset(out, 0, sizeof *out);
    out->meta = slot->command.meta;
    out->k = (uint8_t)k;
    p->mode = slot->command.mode;
    p->k_position = (uint8_t)(k % 4u);
    for (unsigned i = 0; i < 8; ++i) {
        if (p->mode == IO_DENSE) {
            p->payload.dense.dense_a[i] = io_signed_byte(image[16u*k+i]);
            p->payload.dense.dense_b[i] = io_signed_byte(image[16u*k+8u+i]);
        } else if (p->mode == IO_HYBRID) {
            unsigned b = 72u + (k / 4u) * 24u + i * 3u;
            p->payload.hybrid.a_packed[i] = io_signed_byte(image[9u*k+1u+i]);
            p->payload.hybrid.b_2to4_mask[i] = image[b];
            p->payload.hybrid.b_2to4_packed[i][0] = io_signed_byte(image[b+1u]);
            p->payload.hybrid.b_2to4_packed[i][1] = io_signed_byte(image[b+2u]);
        } else {
            p->payload.dual.a_packed[i] = io_signed_byte(image[18u*k+1u+i]);
            p->payload.dual.b_packed[i] = io_signed_byte(image[18u*k+10u+i]);
        }
    }
    if (p->mode == IO_HYBRID) p->payload.hybrid.a_bitmap = image[9u*k];
    if (p->mode == IO_DUAL) {
        p->payload.dual.a_bitmap = image[18u*k];
        p->payload.dual.b_bitmap = image[18u*k+9u];
    }
}

static bool valid_image(const MluBuffer *slot)
{
    if (slot->command.mode != IO_HYBRID) return true;
    for (unsigned g = 0; g < 2; ++g)
        for (unsigned j = 0; j < 8; ++j) {
            uint8_t mask = slot->image[72u+24u*g+3u*j];
            if (mask > 15u || io_popcount(mask) != 2u) return false;
        }
    return true;
}

void mlu_reset(Mlu *q)
{
    assert(q != NULL);
    memset(q, 0, sizeof *q);
}

void mlu_peek(const Mlu *q, MluOutputs *out)
{
    int reading, pending;
    assert(q != NULL && out != NULL);
    memset(out, 0, sizeof *out);
    out->command_ready = q->count < IO_TILE_BUFFERS;
    reading = find_phase(q, MLU_READING);
    pending = find_phase(q, MLU_PENDING);
    out->read_data_ready = reading >= 0;
    if (reading < 0 && pending >= 0) {
        const MluBuffer *s = &q->buffer[pending];
        out->read_request_valid = true;
        out->read_addr = s->command.src_addr;
        out->read_beats = io_image_beats(s->command.mode);
    }
    if (q->count != 0 && q->buffer[q->head].phase == MLU_READY) {
        out->out_valid = true;
        make_frame(&q->buffer[q->head], q->next_k, &out->out);
    }
}

IoStatus mlu_tick(Mlu *q, const MluInputs *in, MluEvents *events)
{
    MluOutputs out;
    MluEvents e = {0};
    Mlu next;
    if (q == NULL || in == NULL) return IO_BAD_ARGUMENT;
    if (events != NULL) *events = e;
    mlu_peek(q, &out);
    next = *q;
    if (in->command_valid && out.command_ready) {
        const IoCommand *c = &in->command;
        unsigned bytes = io_image_beats(c->mode) * IO_BEAT_BYTES;
        unsigned tail = (q->head + q->count) % IO_TILE_BUFFERS;
        if (io_image_bytes(c->mode) == 0 || c->src_addr % 32u != 0 ||
            c->meta.dst_addr % 32u != 0 ||
            c->src_addr > UINT64_MAX - (bytes-1u) ||
            c->meta.dst_addr > UINT64_MAX - 255u) return IO_BAD_FORMAT;
        memset(&next.buffer[tail], 0, sizeof next.buffer[tail]);
        next.buffer[tail].phase = MLU_PENDING;
        next.buffer[tail].command = *c;
        ++next.count;
        e.command_accepted = true;
    }
    if (out.read_request_valid && in->read_request_ready) {
        int s = find_phase(q, MLU_PENDING);
        next.buffer[s].phase = MLU_READING;
        e.read_request_accepted = true;
    }
    if (out.read_data_ready && in->read_data_valid) {
        int s = find_phase(q, MLU_READING);
        MluBuffer *b = &next.buffer[s];
        unsigned n = b->beats_received;
        bool last = n+1u == io_image_beats(b->command.mode);
        if (in->read_last != last) return IO_PROTOCOL_ERROR;
        memcpy(&b->image[n*IO_BEAT_BYTES], in->read_data, IO_BEAT_BYTES);
        ++b->beats_received;
        if (last) {
            if (!valid_image(b)) return IO_BAD_FORMAT;
            b->phase = MLU_READY;
        }
        e.read_data_accepted = true;
    }
    if (out.out_valid && in->out_ready) {
        e.packet_issued = true;
        e.tile_id = out.out.meta.tile_id;
        e.k = q->next_k;
        if (q->next_k == 7u) {
            next.buffer[q->head].phase = MLU_EMPTY;
            next.head = (q->head + 1u) % IO_TILE_BUFFERS;
            --next.count;
            next.next_k = 0;
            e.tile_issued = true;
        } else ++next.next_k;
    }
    assert(next.count <= IO_TILE_BUFFERS && next.next_k < 8);
    *q = next;
    if (events != NULL) *events = e;
    return IO_OK;
}
