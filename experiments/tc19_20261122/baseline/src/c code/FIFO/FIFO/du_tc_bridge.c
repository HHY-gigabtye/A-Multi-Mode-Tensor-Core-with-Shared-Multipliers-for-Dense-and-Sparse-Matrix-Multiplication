#include "du_tc_bridge.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

void bridge_reset(DuTcBridge *q)
{
    assert(q != NULL);
    memset(q, 0, sizeof *q);
}
bool bridge_can_issue(const DuTcBridge *q)
{
    return q != NULL && q->count + q->inflight < IO_PACKET_FIFO;
}
const BridgeEntry *bridge_head(const DuTcBridge *q)
{
    if (q == NULL || q->count == 0) return NULL;
    if (q->fifo[q->head].k == 0 && q->meta_count == TC_RESULT_SLOTS) return NULL;
    return &q->fifo[q->head];
}
const IoMeta *bridge_result_meta(const DuTcBridge *q)
{
    return q != NULL && q->meta_count != 0 ? &q->result_meta[q->meta_head] : NULL;
}
IoStatus bridge_tick(DuTcBridge *q, const BridgeInputs *in)
{
    DuTcBridge next;
    const BridgeTag *arriving;
    if (q == NULL || in == NULL) return IO_BAD_ARGUMENT;
    arriving = &q->side[IO_DU_STAGES-1];
    if (in->issue && !bridge_can_issue(q)) return IO_NO_CREDIT;
    if (in->issue && (in->issued.k >= 8 ||
        io_image_bytes(in->issued.packet.mode) == 0)) return IO_BAD_FORMAT;
    if (in->du_valid != arriving->valid) return IO_PROTOCOL_ERROR;
    if (in->du_valid && (q->inflight == 0 || q->count >= IO_PACKET_FIFO ||
        in->du_packet.is_sparse != arriving->is_sparse)) return IO_PROTOCOL_ERROR;
    if (in->tc_accept && bridge_head(q) == NULL) return IO_PROTOCOL_ERROR;
    if (in->result_accept && q->meta_count == 0) return IO_PROTOCOL_ERROR;
    next = *q;
    if (in->result_accept) {
        next.meta_head = (q->meta_head+1u) % TC_RESULT_SLOTS;
        --next.meta_count;
    }
    if (in->tc_accept) {
        const BridgeEntry *head = &q->fifo[q->head];
        if (head->k == 0) {
            unsigned tail = (q->meta_head + q->meta_count) % TC_RESULT_SLOTS;
            next.result_meta[tail] = head->meta;
            ++next.meta_count;
        }
        next.head = (q->head+1u) % IO_PACKET_FIFO;
        --next.count;
    }
    if (in->du_valid) {
        unsigned tail = (q->head + q->count) % IO_PACKET_FIFO;
        next.fifo[tail].packet = in->du_packet;
        next.fifo[tail].meta = arriving->meta;
        next.fifo[tail].k = arriving->k;
        ++next.count;
        --next.inflight;
    }
    for (unsigned s = IO_DU_STAGES-1; s > 0; --s) next.side[s] = q->side[s-1];
    memset(&next.side[0], 0, sizeof next.side[0]);
    if (in->issue) {
        next.side[0].valid = true;
        next.side[0].is_sparse = in->issued.packet.mode != IO_DENSE;
        next.side[0].meta = in->issued.meta;
        next.side[0].k = in->issued.k;
        ++next.inflight;
    }
    assert(next.count + next.inflight <= IO_PACKET_FIFO);
    assert(next.meta_count <= TC_RESULT_SLOTS);
    *q = next;
    return IO_OK;
}
