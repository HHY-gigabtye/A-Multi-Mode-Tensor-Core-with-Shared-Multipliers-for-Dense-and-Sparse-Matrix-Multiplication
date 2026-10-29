#ifndef IO_TYPES_H
#define IO_TYPES_H

#include <stdbool.h>
#include <stdint.h>
#include "tensor_core_model.h"

enum { IO_BEAT_BYTES = 32, IO_TILE_BYTES = 160, IO_TILE_BUFFERS = 2,
       IO_DU_STAGES = 4, IO_PACKET_FIFO = 8 };
typedef enum { IO_DENSE = 0, IO_HYBRID = 1, IO_DUAL = 2 } IoMode;
typedef enum { IO_OK = 0, IO_BAD_ARGUMENT, IO_BAD_FORMAT,
               IO_PROTOCOL_ERROR, IO_NO_CREDIT } IoStatus;
typedef struct { uint32_t tile_id; uint64_t dst_addr; } IoMeta;
typedef struct { IoMode mode; uint64_t src_addr; IoMeta meta; } IoCommand;

/* Field meanings match du_tia_pkg.sv; these C structs are NOT packed RTL bits.
 * Integer values are signed INT8. Bitmaps, positions and indexes are unsigned.
 * Reserved union padding from SV is deliberately absent from this C API. */
typedef struct {
    IoMode mode;
    uint8_t k_position;
    union {
        struct { int8_t dense_a[8], dense_b[8]; } dense;
        struct {
            uint8_t a_bitmap;
            int8_t a_packed[8];
            uint8_t b_2to4_mask[8];
            int8_t b_2to4_packed[8][2];
        } hybrid;
        struct {
            uint8_t a_bitmap;
            int8_t a_packed[8];
            uint8_t b_bitmap;
            int8_t b_packed[8];
        } dual;
    } payload;
} IoDuPacket;

/* meta and k are wrapper sideband, NOT extra pins required on DU/TIA or TC. */
typedef struct { IoMeta meta; uint8_t k; IoDuPacket packet; } IoFrame;

static inline unsigned io_image_bytes(IoMode mode)
{
    return mode == IO_DENSE ? 128u : mode == IO_HYBRID ? 120u :
           mode == IO_DUAL ? 144u : 0u;
}
static inline unsigned io_image_beats(IoMode mode)
{
    return (io_image_bytes(mode) + IO_BEAT_BYTES - 1u) / IO_BEAT_BYTES;
}
static inline int8_t io_signed_byte(uint8_t value)
{
    return (int8_t)(value < 128u ? (int)value : (int)value - 256);
}
static inline unsigned io_popcount(uint8_t mask)
{
    unsigned n = 0;
    for (; mask != 0; mask = (uint8_t)(mask & (uint8_t)(mask - 1u))) ++n;
    return n;
}
#endif
