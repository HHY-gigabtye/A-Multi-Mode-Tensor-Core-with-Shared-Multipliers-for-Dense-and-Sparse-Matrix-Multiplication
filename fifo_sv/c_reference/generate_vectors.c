/* Run the UNCHANGED supplied C model/testbench and serialize every call.
 * Do not memcpy C structs into RTL: padding/union widths differ.
 * Also append deterministic randomized schedules using the original driver.
 */
#include "du_tc_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static FILE *trace_file;
static unsigned trace_rows, reject_rows;
typedef struct { char bit[4096]; unsigned n; } Bits;

static void put(Bits *b, uint64_t value, unsigned width)
{
    if (b->n + width > sizeof b->bit) abort();
    for (unsigned i = width; i > 0; --i)
        b->bit[b->n++] = (char)((value >> (i - 1)) & 1u);
}
static void hexout(const Bits *b)
{
    static const char hex[] = "0123456789abcdef";
    unsigned pad = (4u - b->n % 4u) % 4u, value = 0;
    for (unsigned i = 0; i < pad + b->n; ++i) {
        value = (value << 1) | (i < pad ? 0u : (unsigned)b->bit[i - pad]);
        if (i % 4u == 3u) { fputc(hex[value], trace_file); value = 0; }
    }
}
static void meta_bits(Bits *b, const IoMeta *m)
{
    put(b, m->tile_id, 32); put(b, m->dst_addr, 64);
}
static void vector_bits(Bits *b, const TcSparseVector *v)
{
    put(b, v->count, 4);
    for (int i = 7; i >= 0; --i) put(b, (uint8_t)v->value[i], 8);
    for (int i = 7; i >= 0; --i) put(b, v->index[i], 3);
}
static void packet_bits(Bits *b, const TcInputPacket *p)
{
    put(b, p->is_sparse, 1);
    if (p->is_sparse) {
        vector_bits(b, &p->payload.sparse.a);
        vector_bits(b, &p->payload.sparse.b);
    } else {
        for (int i = 7; i >= 0; --i) put(b, (uint8_t)p->payload.dense.dense_a[i], 8);
        for (int i = 7; i >= 0; --i) put(b, (uint8_t)p->payload.dense.dense_b[i], 8);
        put(b, 0, 56); /* RTL dense reserved field. */
    }
}
static void state_bits(Bits *b, const DuTcBridge *q)
{
    for (int i = IO_DU_STAGES-1; i >= 0; --i) {
        put(b, q->side[i].valid, 1); put(b, q->side[i].is_sparse, 1);
        meta_bits(b, &q->side[i].meta); put(b, q->side[i].k, 8);
    }
    for (int i = IO_PACKET_FIFO-1; i >= 0; --i) {
        packet_bits(b, &q->fifo[i].packet);
        meta_bits(b, &q->fifo[i].meta); put(b, q->fifo[i].k, 8);
    }
    put(b, q->head, 3); put(b, q->count, 4); put(b, q->inflight, 3);
    for (int i = TC_RESULT_SLOTS-1; i >= 0; --i) meta_bits(b, &q->result_meta[i]);
    put(b, q->meta_head, 1); put(b, q->meta_count, 2);
    if (b->n != 2941u) abort();
}
static void emit(unsigned reset, const BridgeInputs *in, IoStatus status,
                 const DuTcBridge *q)
{
    Bits b = {{0}, 0};
    /* C invalid enum 99 is represented by RTL's only invalid code: 3. */
    unsigned mode = io_image_bytes(in->issued.packet.mode) ?
                    (unsigned)in->issued.packet.mode : 3u;
    fprintf(trace_file, "%u %u %x %x ", reset, in->issue, mode, in->issued.k);
    meta_bits(&b, &in->issued.meta); hexout(&b); b.n = 0;
    fprintf(trace_file, " %u ", in->du_valid);
    packet_bits(&b, &in->du_packet); hexout(&b); b.n = 0;
    fprintf(trace_file, " %u %u %u ", in->tc_accept, in->result_accept, status);
    state_bits(&b, q); hexout(&b); fputc('\n', trace_file);
    ++trace_rows;
    if (status != IO_OK) ++reject_rows;
}
static void traced_reset(DuTcBridge *q)
{
    BridgeInputs in = {0};
    bridge_reset(q);
    emit(1, &in, IO_OK, q);
}
static IoStatus traced_tick(DuTcBridge *q, const BridgeInputs *in)
{
    IoStatus s = bridge_tick(q, in);
    if (q && in) emit(0, in, s, q); /* NULL-pointer guards have no RTL pins. */
    return s;
}

#define bridge_reset traced_reset
#define bridge_tick traced_tick
#define main supplied_test_main
#include "tb_bridge.c"
#undef main
#undef bridge_tick
#undef bridge_reset

static uint32_t rng_next(uint32_t *x)
{
    *x ^= *x << 13; *x ^= *x >> 17; *x ^= *x << 5;
    return *x;
}
int main(int argc, char **argv)
{
    if (argc != 2) { fprintf(stderr, "usage: %s vectors.txt\n", argv[0]); return 2; }
    trace_file = fopen(argv[1], "w");
    if (!trace_file) { perror(argv[1]); return 2; }
    if (supplied_test_main() != 0) return 1;
    for (unsigned seed = 1; seed <= 4; ++seed) {
        Driver d;
        uint32_t random = UINT32_C(0x19283746) * seed;
        init_driver(&d, 1024, 10000u + seed * 1000u);
        while (d.completed * 8u < d.total && d.cycle < 100000u) {
            uint32_t r = rng_next(&random);
            bool offer = (r & 7u) != 0;
            bool ready = (r & 0x30u) != 0 && (d.cycle % 421u >= 91u);
            bool result = (r & 0x700u) != 0 && (d.cycle % 509u >= 163u);
            step(&d, offer, ready, result);
        }
        CHECK(d.completed == 128 && d.accepted == 1024);
        printf("BRIDGE PASS random seed=%u packets=%u cycles=%u\n", seed, d.accepted, d.cycle);
    }
    if (fclose(trace_file) != 0) return 2;
    printf("VECTORS rows=%u rejected_edges=%u state_bits=2941\n", trace_rows, reject_rows);
    return 0;
}
