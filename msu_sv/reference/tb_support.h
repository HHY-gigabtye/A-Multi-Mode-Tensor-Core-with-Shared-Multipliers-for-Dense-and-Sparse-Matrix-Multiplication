#ifndef TB_SUPPORT_H
#define TB_SUPPORT_H
#include "io_types.h"
#include "mlu_model.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TB_CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); \
} } while (0)

typedef struct {
    IoCommand cmd;
    uint8_t image[IO_TILE_BYTES];
    IoFrame expected[8];
    TcMatrix32 golden;
} TbTile;

static inline uint32_t tb_random(uint32_t *seed)
{
    *seed = *seed * UINT32_C(1664525) + UINT32_C(1013904223);
    return *seed;
}

/* Test-only upstream encoder. Golden GEMM uses original A/B matrices,
 * independently of DU decoding, routing, storage and MLU byte addressing. */
static inline void tb_make_tile(TbTile *t, uint32_t id, IoMode mode, uint32_t *seed)
{
    static const uint8_t masks[6] = {3,5,6,9,10,12};
    int8_t a[8][8] = {{0}}, b[8][8] = {{0}};
    uint8_t am[8], bm[8], hm[2][8];
    memset(t, 0, sizeof *t);
    t->cmd.mode = mode;
    t->cmd.src_addr = UINT64_C(0x1000) + (uint64_t)id * IO_TILE_BYTES;
    t->cmd.meta.tile_id = id;
    t->cmd.meta.dst_addr = UINT64_C(0x100000) + (uint64_t)id * 256u;
    for (unsigned k = 0; k < 8; ++k) {
        am[k] = mode == IO_DENSE || id%9u == 0 ? 255u :
                id%9u == 1 ? 0u : (uint8_t)(tb_random(seed)>>24);
        bm[k] = mode == IO_DENSE || id%9u == 0 ? 255u :
                id%9u == 2 ? 0u : (uint8_t)(tb_random(seed)>>24);
        for (unsigned i = 0; i < 8; ++i) {
            if ((am[k] >> i) & 1u)
                a[i][k] = id%7u == 0 && i%3u == 0 ? 0 :
                    io_signed_byte((uint8_t)(tb_random(seed)>>24));
            if (mode != IO_HYBRID && ((bm[k] >> i) & 1u))
                b[k][i] = io_signed_byte((uint8_t)(tb_random(seed)>>24));
        }
    }
    for (unsigned g = 0; g < 2; ++g)
        for (unsigned j = 0; j < 8; ++j) {
            hm[g][j] = masks[(id+g+j)%6u];
            if (mode == IO_HYBRID)
                for (unsigned p = 0; p < 4; ++p)
                    if ((hm[g][j] >> p)&1u)
                        b[4u*g+p][j] = id%7u == 0 && j == 0 ? 0 :
                            io_signed_byte((uint8_t)(tb_random(seed)>>24));
        }
    for (unsigned k = 0; k < 8; ++k) {
        IoFrame *f = &t->expected[k];
        f->meta = t->cmd.meta;
        f->k = (uint8_t)k;
        f->packet.mode = mode;
        f->packet.k_position = (uint8_t)(k%4u);
        if (mode == IO_DENSE) {
            for (unsigned j = 0; j < 8; ++j) {
                t->image[k*16u+j] = (uint8_t)a[j][k];
                t->image[k*16u+8u+j] = (uint8_t)b[k][j];
                f->packet.payload.dense.dense_a[j] = a[j][k];
                f->packet.payload.dense.dense_b[j] = b[k][j];
            }
        } else {
            unsigned stride = mode == IO_HYBRID ? 9u : 18u;
            unsigned rank = 0;
            t->image[k*stride] = am[k];
            for (unsigned i = 0; i < 8; ++i)
                if ((am[k] >> i)&1u) {
                    t->image[k*stride+1u+rank] = (uint8_t)a[i][k];
                    if (mode == IO_HYBRID) f->packet.payload.hybrid.a_packed[rank] = a[i][k];
                    else f->packet.payload.dual.a_packed[rank] = a[i][k];
                    ++rank;
                }
            if (mode == IO_HYBRID) {
                f->packet.payload.hybrid.a_bitmap = am[k];
                for (unsigned j = 0; j < 8; ++j) {
                    unsigned offset = 72u+24u*(k/4u)+3u*j;
                    rank = 0;
                    t->image[offset] = hm[k/4u][j];
                    f->packet.payload.hybrid.b_2to4_mask[j] = hm[k/4u][j];
                    for (unsigned p = 0; p < 4; ++p)
                        if ((hm[k/4u][j] >> p)&1u) {
                            int8_t value = b[4u*(k/4u)+p][j];
                            t->image[offset+1u+rank] = (uint8_t)value;
                            f->packet.payload.hybrid.b_2to4_packed[j][rank++] = value;
                        }
                }
            } else {
                f->packet.payload.dual.a_bitmap = am[k];
                f->packet.payload.dual.b_bitmap = bm[k];
                t->image[k*18u+9u] = bm[k];
                rank = 0;
                for (unsigned j = 0; j < 8; ++j)
                    if ((bm[k] >> j)&1u) {
                        t->image[k*18u+10u+rank] = (uint8_t)b[k][j];
                        f->packet.payload.dual.b_packed[rank++] = b[k][j];
                    }
            }
        }
    }
    for (unsigned i = 0; i < 8; ++i)
        for (unsigned j = 0; j < 8; ++j)
            for (unsigned k = 0; k < 8; ++k)
                t->golden.v[i][j] += (int32_t)a[i][k]*(int32_t)b[k][j];
}

static inline void tb_check_frame(const IoFrame *got, const IoFrame *want)
{
    const IoDuPacket *g = &got->packet, *w = &want->packet;
    TB_CHECK(got->meta.tile_id == want->meta.tile_id);
    TB_CHECK(got->meta.dst_addr == want->meta.dst_addr && got->k == want->k);
    TB_CHECK(g->mode == w->mode && g->k_position == w->k_position);
    if (g->mode == IO_DENSE) {
        TB_CHECK(memcmp(g->payload.dense.dense_a, w->payload.dense.dense_a, 8) == 0);
        TB_CHECK(memcmp(g->payload.dense.dense_b, w->payload.dense.dense_b, 8) == 0);
    } else if (g->mode == IO_HYBRID) {
        TB_CHECK(g->payload.hybrid.a_bitmap == w->payload.hybrid.a_bitmap);
        TB_CHECK(memcmp(g->payload.hybrid.a_packed, w->payload.hybrid.a_packed, 8) == 0);
        TB_CHECK(memcmp(g->payload.hybrid.b_2to4_mask, w->payload.hybrid.b_2to4_mask, 8) == 0);
        TB_CHECK(memcmp(g->payload.hybrid.b_2to4_packed, w->payload.hybrid.b_2to4_packed, 16) == 0);
    } else {
        TB_CHECK(g->payload.dual.a_bitmap == w->payload.dual.a_bitmap);
        TB_CHECK(g->payload.dual.b_bitmap == w->payload.dual.b_bitmap);
        TB_CHECK(memcmp(g->payload.dual.a_packed, w->payload.dual.a_packed, 8) == 0);
        TB_CHECK(memcmp(g->payload.dual.b_packed, w->payload.dual.b_packed, 8) == 0);
    }
}

typedef struct {
    bool active, held;
    unsigned tile, beat, delay, beats;
    uint8_t data[32];
} TbMemory;

static inline void tb_read_inputs(TbMemory *m, const TbTile *tiles,
                                 unsigned cycle, bool stalls, MluInputs *in)
{
    in->read_request_ready = !m->active && (!stalls || cycle%7u != 2u);
    if (m->active && m->delay != 0) --m->delay;
    else if (m->active && !m->held && (!stalls || cycle%5u != 1u)) {
        m->held = true;
        memcpy(m->data, &tiles[m->tile].image[m->beat*32u], 32);
    }
    in->read_data_valid = m->held;
    in->read_last = m->beat+1u == m->beats;
    memcpy(in->read_data, m->data, 32);
}
static inline void tb_read_commit(TbMemory *m, const TbTile *tiles, unsigned n,
                                 const MluOutputs *out, const MluInputs *in)
{
    if (out->read_request_valid && in->read_request_ready) {
        unsigned tile = 0;
        TB_CHECK(!m->active);
        while (tile < n && tiles[tile].cmd.src_addr != out->read_addr) ++tile;
        TB_CHECK(tile < n);
        TB_CHECK(out->read_beats == io_image_beats(tiles[tile].cmd.mode));
        m->active = true;
        m->tile = tile;
        m->beat = 0;
        m->beats = out->read_beats;
        m->delay = tile%4u;
    }
    if (out->read_data_ready && in->read_data_valid) {
        TB_CHECK(m->active && m->held);
        m->held = false;
        if (++m->beat == m->beats) m->active = false;
    }
}

static inline void tb_check_write(const uint8_t data[32], const TcMatrix32 *want,
                                 unsigned row)
{
    for (unsigned j = 0; j < 8; ++j) {
        uint32_t u = 0;
        for (unsigned b = 0; b < 4; ++b) u |= (uint32_t)data[4u*j+b] << (8u*b);
        TB_CHECK(u == (uint32_t)want->v[row][j]);
    }
}
#endif
