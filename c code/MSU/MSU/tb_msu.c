#include "msu_model.h"
#include "tb_support.h"
#include <limits.h>

int main(void)
{
    enum { N = 120 };
    TcMatrix32 values[N];
    Msu q;
    unsigned offered = 0, beats = 0, cycles = 0, max_count = 0, simultaneous = 0;
    bool held = false;
    MsuOutputs saved = {0};
    uint32_t seed = 7;
    for (unsigned t = 0; t < N; ++t)
        for (unsigned i = 0; i < 8; ++i)
            for (unsigned j = 0; j < 8; ++j)
                values[t].v[i][j] = i == 0 ? INT32_MIN : i == 1 ? INT32_MAX :
                    (int32_t)(tb_random(&seed) & UINT32_C(0x7fffffff)) * (j%2u ? -1 : 1);
    msu_reset(&q);
    for (; cycles < 20000 && beats < N*8u; ++cycles) {
        MsuOutputs out;
        MsuInputs in = {0};
        MsuEvents ev;
        msu_peek(&q, &out);
        in.result_valid = offered < N && (offered != 1 || cycles >= 8);
        in.meta.tile_id = offered;
        in.meta.dst_addr = (uint64_t)offered*256u;
        if (in.result_valid) in.result = values[offered];
        in.write_ready = cycles < 10 || (!(cycles >= 40 && cycles < 180) && cycles%5u != 2);
        if (held) {
            TB_CHECK(out.write_valid && out.write_addr == saved.write_addr);
            TB_CHECK(out.write_last == saved.write_last && out.write_meta.tile_id == saved.write_meta.tile_id);
            TB_CHECK(memcmp(out.write_data, saved.write_data, 32) == 0);
        }
        held = out.write_valid && !in.write_ready;
        saved = out;
        if (out.write_valid) {
            unsigned tile = beats/8u, row = beats%8u;
            TB_CHECK(out.write_addr == (uint64_t)tile*256u + row*32u);
            TB_CHECK(out.write_meta.tile_id == tile && out.write_last == (row == 7));
            tb_check_write(out.write_data, &values[tile], row);
        }
        TB_CHECK(msu_tick(&q, &in, &ev) == IO_OK);
        if (ev.result_accepted) ++offered;
        if (ev.beat_written) ++beats;
        if (ev.tile_done) TB_CHECK(ev.completed.tile_id == beats/8u-1u);
        if (ev.tile_done && ev.result_accepted) ++simultaneous;
        if (q.count > max_count) max_count = q.count;
    }
    TB_CHECK(offered == N && beats == N*8u && q.count == 0 && max_count == 2 && simultaneous != 0);
    {
        MsuInputs in = {0};
        Msu before = q;
        in.result_valid = true;
        in.meta.dst_addr = 1;
        TB_CHECK(msu_tick(&q, &in, NULL) == IO_BAD_FORMAT);
        TB_CHECK(memcmp(&q, &before, sizeof q) == 0);
        in.meta.dst_addr = 0;
        TB_CHECK(msu_tick(&q, &in, NULL) == IO_OK);
        msu_reset(&q);
        TB_CHECK(q.count == 0 && q.row == 0);
    }
    printf("MSU PASS: %u results, %u beats, %u cycles; stalls/INT32/reset/simultaneous=%u\n", N, beats, cycles, simultaneous);
    return 0;
}
