#include "du_tc_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); \
} } while (0)

/* Standalone port test: no MLU, MSU, DU decoder or TC implementation.
 * The mock DU schedules each accepted token exactly four edges later.
 * Expected ordering uses monotonic token numbers, not the DUT's pointers. */
enum { MAX_PACKETS = 1024 };
typedef struct {
    DuTcBridge bridge;
    unsigned due[MAX_PACKETS];
    unsigned cycle, issued, arrived, accepted, completed, total, id_base;
    unsigned simultaneous, meta_simultaneous, meta_blocked, credit_blocked;
    unsigned max_fifo, max_flight, max_meta, wraps;
} Driver;

static IoMeta token_meta(unsigned id_base, unsigned token)
{
    IoMeta m;
    m.tile_id = id_base + token / 8u;
    m.dst_addr = UINT64_C(0x100000000) + (uint64_t)m.tile_id * 256u;
    return m;
}

static IoFrame token_frame(unsigned id_base, unsigned token)
{
    IoFrame f = {0};
    f.meta = token_meta(id_base, token);
    f.k = (uint8_t)(token % 8u);
    f.packet.mode = (IoMode)((token / 8u) % 3u);
    f.packet.k_position = (uint8_t)(token % 4u);
    return f;
}

static TcInputPacket token_payload(unsigned id_base, unsigned token)
{
    TcInputPacket p = {0};
    unsigned n = token + id_base;
    p.is_sparse = (token / 8u) % 3u != 0;
    if (!p.is_sparse) {
        for (unsigned i = 0; i < 8; ++i) {
            p.payload.dense.dense_a[i] = io_signed_byte((uint8_t)(n * 17u + i));
            p.payload.dense.dense_b[i] = io_signed_byte((uint8_t)(n * 29u + 7u - i));
        }
    } else {
        p.payload.sparse.a.count = (uint8_t)(n % 9u);
        p.payload.sparse.b.count = (uint8_t)((n + 3u) % 9u);
        for (unsigned i = 0; i < p.payload.sparse.a.count; ++i) {
            p.payload.sparse.a.index[i] = (uint8_t)i;
            p.payload.sparse.a.value[i] = io_signed_byte((uint8_t)(n * 13u + i));
        }
        for (unsigned i = 0; i < p.payload.sparse.b.count; ++i) {
            p.payload.sparse.b.index[i] = (uint8_t)i;
            p.payload.sparse.b.value[i] = io_signed_byte((uint8_t)(n * 19u + i));
        }
    }
    return p;
}

static void check_meta(const IoMeta *got, IoMeta want)
{
    CHECK(got != NULL);
    CHECK(got->tile_id == want.tile_id && got->dst_addr == want.dst_addr);
}

static void check_payload(const TcInputPacket *got, const TcInputPacket *want)
{
    CHECK(got->is_sparse == want->is_sparse);
    if (!want->is_sparse) {
        CHECK(memcmp(got->payload.dense.dense_a, want->payload.dense.dense_a, 8) == 0);
        CHECK(memcmp(got->payload.dense.dense_b, want->payload.dense.dense_b, 8) == 0);
    } else {
        CHECK(got->payload.sparse.a.count == want->payload.sparse.a.count);
        CHECK(got->payload.sparse.b.count == want->payload.sparse.b.count);
        CHECK(memcmp(got->payload.sparse.a.value, want->payload.sparse.a.value, 8) == 0);
        CHECK(memcmp(got->payload.sparse.b.value, want->payload.sparse.b.value, 8) == 0);
        CHECK(memcmp(got->payload.sparse.a.index, want->payload.sparse.a.index, 8) == 0);
        CHECK(memcmp(got->payload.sparse.b.index, want->payload.sparse.b.index, 8) == 0);
    }
}

static void init_driver(Driver *d, unsigned total, unsigned id_base)
{
    CHECK(total <= MAX_PACKETS && total % 8u == 0);
    memset(d, 0, sizeof *d);
    d->total = total;
    d->id_base = id_base;
    bridge_reset(&d->bridge);
}

static void check_observations(const Driver *d)
{
    const DuTcBridge *q = &d->bridge;
    unsigned metadata = (d->accepted + 7u) / 8u - d->completed;
    bool blocked = d->accepted % 8u == 0 && metadata == TC_RESULT_SLOTS;
    const BridgeEntry *head = bridge_head(q);
    CHECK(q->count == d->arrived - d->accepted);
    CHECK(q->inflight == d->issued - d->arrived);
    CHECK(q->count + q->inflight <= IO_PACKET_FIFO);
    CHECK(q->inflight <= IO_DU_STAGES);
    CHECK(q->meta_count == metadata && metadata <= TC_RESULT_SLOTS);
    CHECK(bridge_can_issue(q) == (d->issued - d->accepted < IO_PACKET_FIFO));
    CHECK((head != NULL) == (d->arrived > d->accepted && !blocked));
    if (head != NULL) {
        TcInputPacket want = token_payload(d->id_base, d->accepted);
        CHECK(head->k == d->accepted % 8u);
        check_meta(&head->meta, token_meta(d->id_base, d->accepted));
        check_payload(&head->packet, &want);
    }
    if (metadata != 0)
        check_meta(bridge_result_meta(q), token_meta(d->id_base, d->completed * 8u));
    else CHECK(bridge_result_meta(q) == NULL);
}

static void expect_rejection(DuTcBridge *q, BridgeInputs *in, IoStatus status)
{
    DuTcBridge before = *q;
    CHECK(bridge_tick(q, in) == status);
    CHECK(memcmp(q, &before, sizeof *q) == 0);
}

static void step(Driver *d, bool offer, bool tc_ready, bool take_result)
{
    BridgeInputs in = {0};
    unsigned metadata = (d->accepted + 7u) / 8u - d->completed;
    bool credit = d->issued - d->accepted < IO_PACKET_FIFO;
    bool eligible = d->arrived > d->accepted &&
        !(d->accepted % 8u == 0 && metadata == TC_RESULT_SLOTS);
    check_observations(d);
    in.issue = offer && d->issued < d->total && credit;
    if (in.issue) in.issued = token_frame(d->id_base, d->issued);
    in.du_valid = d->arrived < d->issued && d->due[d->arrived] == d->cycle;
    if (in.du_valid) in.du_packet = token_payload(d->id_base, d->arrived);
    in.tc_accept = tc_ready && eligible;
    /* The mock result is eligible only after all eight packets reached TC. */
    in.result_accept = take_result && d->completed < d->accepted / 8u;

    if (!credit && offer && d->issued < d->total) {
        BridgeInputs bad = in;
        bad.issue = true;
        bad.issued = token_frame(d->id_base, d->issued);
        expect_rejection(&d->bridge, &bad, IO_NO_CREDIT);
        ++d->credit_blocked;
    }
    if (d->arrived > d->accepted && !eligible) {
        BridgeInputs bad = in;
        bad.tc_accept = true;
        expect_rejection(&d->bridge, &bad, IO_PROTOCOL_ERROR);
        ++d->meta_blocked;
    }
    if (in.du_valid && in.tc_accept) ++d->simultaneous;
    if (in.tc_accept && d->accepted % 8u == 0 && in.result_accept)
        ++d->meta_simultaneous;
    CHECK(bridge_tick(&d->bridge, &in) == IO_OK);
    if (in.issue) d->due[d->issued++] = d->cycle + IO_DU_STAGES;
    if (in.du_valid) ++d->arrived;
    if (in.tc_accept && ++d->accepted % IO_PACKET_FIFO == 0) ++d->wraps;
    if (in.result_accept) ++d->completed;
    ++d->cycle;
    if (d->bridge.count > d->max_fifo) d->max_fifo = d->bridge.count;
    if (d->bridge.inflight > d->max_flight) d->max_flight = d->bridge.inflight;
    if (d->bridge.meta_count > d->max_meta) d->max_meta = d->bridge.meta_count;
    check_observations(d);
}

static void test_bad_inputs(void)
{
    DuTcBridge q;
    BridgeInputs in = {0};
    bridge_reset(&q);
    CHECK(!bridge_can_issue(NULL) && bridge_head(NULL) == NULL);
    CHECK(bridge_result_meta(NULL) == NULL);
    CHECK(bridge_tick(NULL, &in) == IO_BAD_ARGUMENT);
    CHECK(bridge_tick(&q, NULL) == IO_BAD_ARGUMENT);
    in.tc_accept = true;
    expect_rejection(&q, &in, IO_PROTOCOL_ERROR);
    in.tc_accept = false;
    in.result_accept = true;
    expect_rejection(&q, &in, IO_PROTOCOL_ERROR);
    in.result_accept = false;
    in.du_valid = true;
    expect_rejection(&q, &in, IO_PROTOCOL_ERROR);
    in.du_valid = false;
    in.issue = true;
    in.issued.k = 8;
    expect_rejection(&q, &in, IO_BAD_FORMAT);
    in.issued.k = 0;
    in.issued.packet.mode = (IoMode)99;
    expect_rejection(&q, &in, IO_BAD_FORMAT);
    in.issued.packet.mode = IO_DENSE;
    CHECK(bridge_tick(&q, &in) == IO_OK);
    memset(&in, 0, sizeof in);
    for (unsigned i = 0; i < IO_DU_STAGES - 1u; ++i)
        CHECK(bridge_tick(&q, &in) == IO_OK);
    expect_rejection(&q, &in, IO_PROTOCOL_ERROR); /* Scheduled DU output missing. */
    in.du_valid = true;
    in.du_packet.is_sparse = true;
    expect_rejection(&q, &in, IO_PROTOCOL_ERROR); /* Wrong decoded mode. */
    in.du_packet.is_sparse = false;
    CHECK(bridge_tick(&q, &in) == IO_OK);
    CHECK(q.count == 1 && q.inflight == 0);
    puts("BRIDGE PASS guards: empty/format/DU timing/mode/rejected state unchanged");
}

static void test_stream(bool stalls)
{
    Driver d;
    init_driver(&d, 768, stalls ? 1000u : 0u);
    while (d.completed * 8u < d.total && d.cycle < 20000) {
        unsigned c = d.cycle;
        bool offer = !stalls || c < 24 || (c % 7u != 2 && c % 11u != 3);
        bool ready = !stalls || (c >= 40 && c % 5u != 1 && !(c >= 300 && c < 380));
        bool result = !stalls || (c >= 120 && c % 13u != 5);
        step(&d, offer, ready, result);
    }
    CHECK(d.issued == d.total && d.arrived == d.total && d.accepted == d.total);
    CHECK(d.completed * 8u == d.total && d.bridge.meta_count == 0);
    CHECK(d.simultaneous != 0 && d.wraps == d.total / IO_PACKET_FIFO);
    CHECK(d.max_flight == IO_DU_STAGES);
    if (stalls) {
        CHECK(d.max_fifo == IO_PACKET_FIFO && d.max_meta == TC_RESULT_SLOTS);
        CHECK(d.credit_blocked != 0 && d.meta_blocked != 0);
    } else CHECK(d.meta_simultaneous != 0);
    printf("BRIDGE PASS %s: packets=%u tiles=%u cycles=%u max_fifo=%u max_inflight=%u "
           "max_meta=%u push_pop=%u meta_push_pop=%u wraps=%u credit_blocks=%u meta_blocks=%u\n",
           stalls ? "stalls" : "continuous", d.total, d.completed, d.cycle,
           d.max_fifo, d.max_flight, d.max_meta, d.simultaneous,
           d.meta_simultaneous, d.wraps, d.credit_blocked, d.meta_blocked);
}

static void test_reset(unsigned edges)
{
    Driver d;
    init_driver(&d, 64, 2000);
    for (unsigned c = 0; c < edges; ++c) step(&d, true, edges > 8, false);
    CHECK(d.bridge.count != 0 || d.bridge.inflight != 0 || d.bridge.meta_count != 0);
    /* Reset the bridge AND cancel pending arrivals in the mock DU. */
    init_driver(&d, 64, 9000);
    check_observations(&d);
    while (d.completed * 8u < d.total && d.cycle < 2000) step(&d, true, true, true);
    CHECK(d.completed == 8 && d.accepted == 64 && d.bridge.count == 0);
    printf("BRIDGE PASS reset after %u edges: fresh stream 8 tiles, no stale metadata\n", edges);
}

int main(void)
{
    test_bad_inputs();
    test_stream(false);
    test_stream(true);
    test_reset(2);  /* Inflight data. */
    test_reset(8);  /* FIFO and inflight data. */
    test_reset(24); /* Metadata full, next tile waiting. */
    puts("ALL BRIDGE TESTS PASS (standalone, no DU/TC/MLU/MSU model linked)");
    return 0;
}
