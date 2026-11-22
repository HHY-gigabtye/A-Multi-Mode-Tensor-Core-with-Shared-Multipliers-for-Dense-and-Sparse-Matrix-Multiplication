#ifndef MLU_MODEL_H
#define MLU_MODEL_H
#include "io_types.h"

typedef enum { MLU_EMPTY, MLU_PENDING, MLU_READING, MLU_READY } MluPhase;
typedef struct {
    MluPhase phase;
    IoCommand command;
    uint8_t image[IO_TILE_BYTES];
    unsigned beats_received;
} MluBuffer;
typedef struct {
    MluBuffer buffer[IO_TILE_BUFFERS];
    unsigned head, count, next_k;
} Mlu;
typedef struct {
    bool command_ready;
    bool read_request_valid;
    uint64_t read_addr;
    unsigned read_beats;
    bool read_data_ready;
    bool out_valid;
    IoFrame out;
} MluOutputs;
typedef struct {
    bool command_valid;
    IoCommand command;
    bool read_request_ready;
    bool read_data_valid;
    uint8_t read_data[IO_BEAT_BYTES];
    bool read_last;
    bool out_ready; /* wrapper credit; NOT instantaneous TC ready */
} MluInputs;
typedef struct {
    bool command_accepted, read_request_accepted, read_data_accepted;
    bool packet_issued, tile_issued;
    uint32_t tile_id;
    unsigned k;
} MluEvents;

/* All outputs use OLD state. Compute all module outputs before any tick.
 * Standard valid/ready on all MLU ports; hold valid + payload until accepted.
 * One ordered read burst outstanding. No same-edge request/first response.
 * Images: dense 128 bytes, hybrid 120 bytes, dual 144 bytes, padded to 32 B.
 * Commands require 32-byte-aligned source/destination addresses.
 * No sparsity detection/encoding; input images are already packed upstream.
 * A failing tick changes neither registers nor memory transactions.
 * Call reset jointly with DU/TIA, bridge, TC, MSU and the memory responder.
 * Tick input/output pointers must not alias model state. */
void mlu_reset(Mlu *q);
void mlu_peek(const Mlu *q, MluOutputs *out);
IoStatus mlu_tick(Mlu *q, const MluInputs *in, MluEvents *events);
#endif
