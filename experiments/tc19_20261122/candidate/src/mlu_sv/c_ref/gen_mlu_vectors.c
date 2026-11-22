/* Golden vectors from the UNMODIFIED supplied C model. No DPI is required. */
#include "mlu_model.h"
#include "tb_support.h"
#include <inttypes.h>

static FILE *vectors;
static unsigned records, resets, errors, accepted, issued, retired;
static unsigned simultaneous_command_pop, simultaneous_data_out, full_stalls;
static unsigned both_ready, mode_issued[3], random_seed;

typedef struct { unsigned n; unsigned char bit[4096]; } Bits;
static void put(Bits *b, uint64_t x, unsigned n)
{
    TB_CHECK(n <= 64 && b->n+n <= sizeof b->bit);
    for (unsigned i = n; i != 0; --i) b->bit[b->n++] = (unsigned char)((x>>(i-1))&1u);
}
static void zero(Bits *b, unsigned n)
{
    while (n != 0) { unsigned k = n > 64 ? 64 : n; put(b, 0, k); n -= k; }
}
static void print_bits(const Bits *b)
{
    static const char hex[] = "0123456789abcdef";
    unsigned pad = (4u-b->n%4u)%4u;
    for (unsigned i = 0; i < b->n+pad; i += 4) {
        unsigned v = 0;
        for (unsigned j = 0; j < 4; ++j) {
            unsigned pos = i+j;
            v = (v<<1) | (pos < pad ? 0u : b->bit[pos-pad]);
        }
        fputc(hex[v], vectors);
    }
}
static void pack_meta(Bits *b, const IoMeta *m)
{ put(b, m->tile_id, 32); put(b, m->dst_addr, 64); }
static void pack_command(Bits *b, const IoCommand *c)
{ put(b, (unsigned)c->mode, 2); put(b, c->src_addr, 64); pack_meta(b, &c->meta); }
static void pack_lanes(Bits *b, const int8_t p[8])
{ for (int i = 7; i >= 0; --i) put(b, (uint8_t)p[i], 8); }
static void pack_packet(Bits *b, const IoDuPacket *p)
{
    put(b, (unsigned)p->mode, 2); put(b, p->k_position, 2);
    if (p->mode == IO_DENSE) {
        pack_lanes(b, p->payload.dense.dense_a);
        pack_lanes(b, p->payload.dense.dense_b); zero(b, 104);
    } else if (p->mode == IO_HYBRID) {
        put(b, p->payload.hybrid.a_bitmap, 8);
        pack_lanes(b, p->payload.hybrid.a_packed);
        for (int i = 7; i >= 0; --i) put(b, p->payload.hybrid.b_2to4_mask[i], 4);
        for (int i = 7; i >= 0; --i)
            for (int r = 1; r >= 0; --r) put(b, (uint8_t)p->payload.hybrid.b_2to4_packed[i][r], 8);
    } else {
        put(b, p->payload.dual.a_bitmap, 8); pack_lanes(b, p->payload.dual.a_packed);
        put(b, p->payload.dual.b_bitmap, 8); pack_lanes(b, p->payload.dual.b_packed);
        zero(b, 88);
    }
}
static void pack_frame(Bits *b, const IoFrame *f)
{ pack_meta(b, &f->meta); put(b, f->k, 3); pack_packet(b, &f->packet); }
static void pack_inputs(Bits *b, const MluInputs *in)
{
    put(b, in->command_valid, 1); pack_command(b, &in->command);
    put(b, in->read_request_ready, 1); put(b, in->read_data_valid, 1);
    for (int i = 31; i >= 0; --i) put(b, in->read_data[i], 8);
    put(b, in->read_last, 1); put(b, in->out_ready, 1);
}
static void pack_outputs(Bits *b, const MluOutputs *o)
{
    put(b, o->command_ready, 1); put(b, o->read_request_valid, 1);
    put(b, o->read_addr, 64); put(b, o->read_beats, 3);
    put(b, o->read_data_ready, 1); put(b, o->out_valid, 1); pack_frame(b, &o->out);
}
static void pack_events(Bits *b, const MluEvents *e)
{
    put(b, e->command_accepted, 1); put(b, e->read_request_accepted, 1);
    put(b, e->read_data_accepted, 1); put(b, e->packet_issued, 1);
    put(b, e->tile_issued, 1); put(b, e->tile_id, 32); put(b, e->k, 3);
}
static void pack_state(Bits *b, const Mlu *q)
{
    for (int s = 1; s >= 0; --s) {
        put(b, q->buffer[s].phase, 2); pack_command(b, &q->buffer[s].command);
        for (int i = 159; i >= 0; --i) put(b, q->buffer[s].image[i], 8);
        put(b, q->buffer[s].beats_received, 3);
    }
    put(b, q->head, 1); put(b, q->count, 2); put(b, q->next_k, 3);
}
static MluEvents step(Mlu *q, const MluInputs *in, bool reset, IoStatus expected)
{
    MluOutputs o;
    MluEvents e = {0};
    Bits b = {0};
    IoStatus status = IO_OK;
    if (reset) { mlu_reset(q); ++resets; }
    mlu_peek(q, &o);
    if (!reset) status = mlu_tick(q, in, &e);
    TB_CHECK(status == expected);
    fprintf(vectors, "%u ", (unsigned)reset);
    pack_inputs(&b, in); TB_CHECK(b.n == 423); print_bits(&b); fputc(' ', vectors);
    b.n = 0; pack_outputs(&b, &o); TB_CHECK(b.n == 406); print_bits(&b);
    fprintf(vectors, " %u ", (unsigned)status);
    b.n = 0; pack_events(&b, &e); TB_CHECK(b.n == 40); print_bits(&b); fputc(' ', vectors);
    b.n = 0; pack_state(&b, q); TB_CHECK(b.n == 2900); print_bits(&b); fputc('\n', vectors);
    ++records;
    if (status != IO_OK) ++errors;
    if (e.command_accepted) ++accepted;
    if (e.packet_issued) { ++issued; ++mode_issued[o.out.packet.mode]; }
    if (e.tile_issued) ++retired;
    if (e.command_accepted && e.tile_issued) ++simultaneous_command_pop;
    if (e.read_data_accepted && e.packet_issued) ++simultaneous_data_out;
    if (in->command_valid && !o.command_ready) ++full_stalls;
    if (q->buffer[0].phase == MLU_READY && q->buffer[1].phase == MLU_READY) ++both_ready;
    return e;
}
static void reset_model(Mlu *q)
{ MluInputs in = {0}; step(q, &in, true, IO_OK); }
static void command_step(Mlu *q, IoCommand c)
{ MluInputs in = {0}; in.command_valid = true; in.command = c; step(q, &in, false, IO_OK); }
static void request_step(Mlu *q)
{ MluInputs in = {0}; in.read_request_ready = true; step(q, &in, false, IO_OK); }
static void beat_step(Mlu *q, const TbTile *t, unsigned beat, bool last, IoStatus status)
{
    MluInputs in = {0}; in.read_data_valid = true; in.read_last = last;
    memcpy(in.read_data, t->image+32u*beat, 32);
    step(q, &in, false, status);
}
static void load_tile(Mlu *q, const TbTile *t)
{
    command_step(q, t->cmd); request_step(q);
    for (unsigned b = 0; b < io_image_beats(t->cmd.mode); ++b)
        beat_step(q, t, b, b+1 == io_image_beats(t->cmd.mode), IO_OK);
}
static void drain(Mlu *q, unsigned packets)
{
    MluInputs in = {0}; in.out_ready = true;
    for (unsigned k = 0; k < packets; ++k) {
        MluEvents e = step(q, &in, false, IO_OK); TB_CHECK(e.packet_issued);
    }
}

static void directed(void)
{
    Mlu q;
    TbTile t[3];
    uint32_t seed = 123;
    for (unsigned m = 0; m < 3; ++m) tb_make_tile(&t[m], m, (IoMode)m, &seed);
    for (unsigned m = 0; m < 3; ++m) {
        reset_model(&q);
        load_tile(&q, &t[m]);
        drain(&q, 8);
    }
    // Distinct signed extreme bytes and dense padding are forwarded exactly.
    for (unsigned i = 0; i < 128; ++i) {
        static const uint8_t v[] = {0x00,0x01,0x7f,0x80,0xff,0x55,0xaa,0xfe};
        t[0].image[i] = v[i%8];
    }
    reset_model(&q); load_tile(&q, &t[0]); drain(&q, 8);
    // One retired head + a newly admitted command on the SAME edge.
    reset_model(&q); load_tile(&q, &t[0]); drain(&q, 7);
    { MluInputs in = {0}; in.command_valid = true; in.command = t[2].cmd;
      in.out_ready = true; MluEvents e = step(&q, &in, false, IO_OK);
      TB_CHECK(e.command_accepted && e.tile_issued && q.count == 1 && q.head == 1); }
    request_step(&q);
    for (unsigned b = 0; b < 5; ++b) beat_step(&q, &t[2], b, b == 4, IO_OK);
    drain(&q, 8);
    // Both buffers READY; invalid offered command is ignored while full.
    reset_model(&q); load_tile(&q, &t[0]); load_tile(&q, &t[2]);
    { MluInputs in = {0}; in.command_valid = true; in.command.mode = (IoMode)3;
      for (unsigned n = 0; n < 16; ++n) step(&q, &in, false, IO_OK);
      in.out_ready = true;
      for (unsigned n = 0; n < 8; ++n) step(&q, &in, false, IO_OK); }
    drain(&q, 8);
    // Source/destination address alignment, mode and overflow checks.
    for (unsigned test = 0; test < 5; ++test) {
        MluInputs in = {0}; reset_model(&q); in.command_valid = true; in.command = t[0].cmd;
        if (test == 0) in.command.mode = (IoMode)3;
        if (test == 1) in.command.src_addr |= 1;
        if (test == 2) in.command.meta.dst_addr |= 16;
        if (test == 3) in.command.src_addr = UINT64_MAX-95u;
        if (test == 4) in.command.meta.dst_addr = UINT64_MAX-223u;
        step(&q, &in, false, IO_BAD_FORMAT);
    }
    for (unsigned m = 0; m < 3; ++m) {
        // Largest legal aligned address; next aligned burst would overflow.
        TbTile high = t[m];
        high.cmd.src_addr = UINT64_MAX - (32u*io_image_beats((IoMode)m)-1u);
        high.cmd.meta.dst_addr = UINT64_MAX-255u;
        high.cmd.meta.tile_id = UINT32_C(0xf1234567);
        reset_model(&q); load_tile(&q, &high); drain(&q, 8);
        reset_model(&q);
        { MluInputs in = {0}; in.command_valid = true; in.command = high.cmd;
          in.command.src_addr += 32; step(&q, &in, false, IO_BAD_FORMAT); }
        // Wrong early last, wrong missing last; correction is unit-test-only.
        reset_model(&q); command_step(&q, t[m].cmd); request_step(&q);
        beat_step(&q, &t[m], 0, true, IO_PROTOCOL_ERROR);
        for (unsigned b = 0; b+1 < io_image_beats((IoMode)m); ++b)
            beat_step(&q, &t[m], b, false, IO_OK);
        beat_step(&q, &t[m], io_image_beats((IoMode)m)-1, false, IO_PROTOCOL_ERROR);
        beat_step(&q, &t[m], io_image_beats((IoMode)m)-1, true, IO_OK);
        drain(&q, 8);
    }
    // Exercise every hybrid mask location, including masks arriving LAST.
    for (unsigned j = 0; j < 16; ++j) {
        static const uint8_t illegal[] = {0x00,0x01,0x07,0x0f,0x13,0x83,0xff};
        for (unsigned v = 0; v < sizeof illegal; ++v) {
            TbTile bad = t[1];
            bad.image[72+(j/8)*24+(j%8)*3] = illegal[v];
            reset_model(&q); command_step(&q, bad.cmd); request_step(&q);
            for (unsigned b = 0; b < 4; ++b)
                beat_step(&q, &bad, b, b == 3, b == 3 ? IO_BAD_FORMAT : IO_OK);
        }
    }
    // C's whole-tick rejection: bad command prevents a simultaneous output.
    reset_model(&q); load_tile(&q, &t[0]);
    { MluInputs in = {0}; in.command_valid = true; in.command = t[2].cmd;
      in.command.src_addr |= 1; in.out_ready = true;
      step(&q, &in, false, IO_BAD_FORMAT); }
    // Bad read_last also prevents a simultaneous output of the older tile.
    command_step(&q, t[2].cmd); request_step(&q);
    { MluInputs in = {0}; in.read_data_valid = true; in.read_last = true;
      in.out_ready = true; step(&q, &in, false, IO_PROTOCOL_ERROR);
      in.read_last = false; step(&q, &in, false, IO_OK); }
    reset_model(&q);
    // Reset at PENDING, partial READING, READY, and partially emitted tile.
    command_step(&q, t[0].cmd); reset_model(&q);
    command_step(&q, t[1].cmd); request_step(&q);
    beat_step(&q, &t[1], 0, false, IO_OK); reset_model(&q);
    load_tile(&q, &t[2]); reset_model(&q);
    load_tile(&q, &t[0]); drain(&q, 3); reset_model(&q);
    // No same-edge new-command/request or request/first-response bypass.
    { MluInputs in = {0}; in.command_valid = true; in.command = t[0].cmd;
      in.read_request_ready = true; in.read_data_valid = true;
      memcpy(in.read_data, t[0].image, 32);
      MluEvents e = step(&q, &in, false, IO_OK);
      TB_CHECK(e.command_accepted && !e.read_request_accepted && !e.read_data_accepted);
      in.command_valid = false; e = step(&q, &in, false, IO_OK);
      TB_CHECK(e.read_request_accepted && !e.read_data_accepted);
      e = step(&q, &in, false, IO_OK); TB_CHECK(e.read_data_accepted); }
    for (unsigned b = 1; b < 4; ++b) beat_step(&q, &t[0], b, b == 3, IO_OK);
    drain(&q, 8);
}

static void stream(unsigned n, uint32_t seed, unsigned style)
{
    TbTile *tiles = calloc(n, sizeof *tiles);
    Mlu q; TbMemory mem = {0};
    unsigned commands = 0, packets = 0, cycles = 0;
    bool pending_command = false;
    TB_CHECK(tiles != NULL);
    for (unsigned i = 0; i < n; ++i) tb_make_tile(&tiles[i], i, (IoMode)(i%3u), &seed);
    reset_model(&q);
    for (; cycles < 100000 && packets < n*8u; ++cycles) {
        MluInputs in = {0}; MluOutputs out; MluEvents ev;
        uint32_t r = tb_random(&seed);
        mlu_peek(&q, &out);
        if (commands < n && (!style || style == 1 || (r&3u) != 0)) pending_command = true;
        in.command_valid = commands < n && pending_command;
        if (in.command_valid) in.command = tiles[commands].cmd;
        if (style == 0) in.out_ready = !(cycles >= 40 && cycles < 180) && cycles%7u != 3u;
        else if (style == 1) in.out_ready = true;
        else in.out_ready = (r&7u) > 1 && !(cycles%601u >= 100 && cycles%601u < 190);
        tb_read_inputs(&mem, tiles, style > 1 ? r>>8 : cycles, style != 1, &in);
        if (out.out_valid) tb_check_frame(&out.out, &tiles[packets/8u].expected[packets%8u]);
        ev = step(&q, &in, false, IO_OK);
        tb_read_commit(&mem, tiles, n, &out, &in);
        if (ev.command_accepted) { ++commands; pending_command = false; }
        if (ev.packet_issued) {
            TB_CHECK(ev.k == packets%8 && ev.tile_id == packets/8);
            TB_CHECK(ev.tile_issued == (packets%8 == 7)); ++packets;
        }
    }
    TB_CHECK(packets == n*8u && commands == n && q.count == 0);
    printf("C stream PASS: style=%u tiles=%u packets=%u cycles=%u\n", style, n, packets, cycles);
    free(tiles);
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "mlu_vectors.txt";
    Mlu q; MluInputs idle = {0};
    random_seed = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 0) : 20261024u;
    vectors = fopen(path, "w"); TB_CHECK(vectors != NULL);
    directed();
    stream(120, 55, 0); // The original supplied tb_mlu stream.
    stream(120, 86, 1);
    for (unsigned s = 0; s < 4; ++s) stream(256, random_seed + s*1729u, 2);
    reset_model(&q);
    for (unsigned n = 0; n < 8; ++n) step(&q, &idle, false, IO_OK);
    TB_CHECK(simultaneous_command_pop && simultaneous_data_out && full_stalls && both_ready);
    TB_CHECK(fclose(vectors) == 0);
    printf("Golden vectors: %s\n", path);
    printf("records=%u resets=%u rejected=%u commands=%u packets=%u retired=%u\n",
           records, resets, errors, accepted, issued, retired);
    printf("command+retire=%u read+output=%u full_stalls=%u both_ready=%u\n",
           simultaneous_command_pop, simultaneous_data_out, full_stalls, both_ready);
    printf("dense=%u hybrid=%u dual=%u random_seed=%u\n", mode_issued[0], mode_issued[1], mode_issued[2], random_seed);
    return 0;
}
