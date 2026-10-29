#include "mlu_model.h"
#include "tb_support.h"

static void test_bad_inputs(void)
{
    Mlu q, before;
    MluInputs in = {0};
    mlu_reset(&q);
    before = q;
    in.command_valid = true;
    in.command.mode = (IoMode)99;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_BAD_FORMAT);
    TB_CHECK(memcmp(&q, &before, sizeof q) == 0);
    in.command.mode = IO_HYBRID;
    in.command.src_addr = 1;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_BAD_FORMAT);
    in.command.src_addr = 0;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_OK);
    memset(&in, 0, sizeof in);
    in.read_request_ready = true;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_OK);
    before = q;
    in.read_data_valid = true;
    in.read_last = true;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_PROTOCOL_ERROR);
    TB_CHECK(memcmp(&q, &before, sizeof q) == 0);
    in.read_last = false;
    for (unsigned i = 0; i < 3; ++i) TB_CHECK(mlu_tick(&q, &in, NULL) == IO_OK);
    in.read_last = true;
    before = q;
    TB_CHECK(mlu_tick(&q, &in, NULL) == IO_BAD_FORMAT); /* 2:4 masks all zero */
    TB_CHECK(memcmp(&q, &before, sizeof q) == 0);
    mlu_reset(&q);
    TB_CHECK(q.count == 0);
}

int main(void)
{
    enum { N = 120 };
    TbTile *tiles = (TbTile *)calloc(N, sizeof *tiles);
    Mlu q;
    TbMemory mem = {0};
    unsigned commands = 0, packets = 0, max_count = 0, cycles = 0;
    uint32_t seed = 55;
    TB_CHECK(tiles != NULL);
    test_bad_inputs();
    for (unsigned n = 0; n < N; ++n) tb_make_tile(&tiles[n], n, (IoMode)(n%3u), &seed);
    mlu_reset(&q);
    for (; cycles < 20000 && packets < N*8u; ++cycles) {
        MluOutputs out;
        MluInputs in = {0};
        MluEvents ev;
        mlu_peek(&q, &out);
        in.command_valid = commands < N;
        if (in.command_valid) in.command = tiles[commands].cmd;
        in.out_ready = !(cycles >= 40 && cycles < 180) && cycles%7u != 3u;
        tb_read_inputs(&mem, tiles, cycles, true, &in);
        if (out.out_valid) tb_check_frame(&out.out, &tiles[packets/8u].expected[packets%8u]);
        TB_CHECK(mlu_tick(&q, &in, &ev) == IO_OK);
        tb_read_commit(&mem, tiles, N, &out, &in);
        if (ev.command_accepted) ++commands;
        if (ev.packet_issued) {
            TB_CHECK(ev.k == packets%8u && ev.tile_id == packets/8u);
            TB_CHECK(ev.tile_issued == (packets%8u == 7u));
            ++packets;
        }
        if (q.count > max_count) max_count = q.count;
    }
    TB_CHECK(packets == N*8u && commands == N && q.count == 0 && max_count == 2);
    free(tiles);
    printf("MLU PASS: %u tiles, %u packets, %u cycles; stalls/order/format/reset\n", N, packets, cycles);
    return 0;
}
