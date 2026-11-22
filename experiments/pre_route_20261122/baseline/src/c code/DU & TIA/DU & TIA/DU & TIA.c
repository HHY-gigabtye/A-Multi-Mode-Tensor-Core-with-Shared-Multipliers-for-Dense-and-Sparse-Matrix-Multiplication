/*
 * DU / TIA unit-level verification model for an 8x8x8 INT8 design.
 *
 * Scope
 * -----
 * This program stops at the DU/TIA output packet. It does not implement the
 * Tensor Core multipliers, systolic PE array, outer-product engine, MSU, GEMM,
 * HBM, or MLU.
 *
 * The compiler supplies one operation mode:
 *
 *   COMPILER_DENSE_X_DENSE
 *     Dense A[:,k] and B[k,:] vectors bypass DU/TIA. These vectors are the
 *     logical per-k feed for a downstream systolic array. The array's skew,
 *     PE propagation, multiplication, and inner-product accumulation are out
 *     of scope here.
 *
 *   COMPILER_UNSTRUCTURED_X_2TO4
 *     Outer-product dataflow. A[:,k] arrives as a row bitmap plus an already
 *     packed non-zero stream. B supplies, for each output column, one 2:4
 *     K-group mask and its two packed values. DU forwards A and decodes the B
 *     value at this k. TIA produces row/column indexes.
 *
 *   COMPILER_UNSTRUCTURED_X_UNSTRUCTURED
 *     Outer-product dataflow. A[:,k] and B[k,:] both arrive as a bitmap plus
 *     an already packed non-zero stream. DU forwards both streams; TIA
 *     produces row/column indexes.
 *
 * Sparse encoding/packing is upstream of this verification boundary. Static
 * data can be packed offline; dynamic activation packing requires a runtime
 * encoder. Neither encoder is modeled here.
 *
 * Hardware-like pipeline
 * ----------------------
 *   S0 INPUT/CONTROL
 *      Latch compiler mode, k tag, packed streams, bitmaps, and 2:4 metadata.
 *
 *   S1 DU FORWARD/DECODE / TIA PREDECODE
 *      Dense: bypass.
 *      Ux2:4: forward packed A and decode B across columns.
 *      UxU: forward both already packed vectors.
 *      Sparse modes also decode bitmap low/high halves in TIA.
 *
 *   S2 TIA MERGE
 *      Merge the two 4-bit TIA maps into 8-lane logical index lists.
 *
 *   S3 OUTPUT/JOIN
 *      Dense: emit the unchanged systolic-feed vectors.
 *      Sparse: pair each packed value with its row/column index.
 *
 *   SCOREBOARD
 *      Compare the S3 packet against an independent non-pipelined model.
 *
 * Four pipeline registers are modeled: latency=4 cycles and II=1.
 *
 * Build:
 *   cc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
 *      du_tia_verification.c -o du_tia_verification
 *
 * Run:
 *   ./du_tia_verification
 *   ./du_tia_verification --trace --tests 0
 *   ./du_tia_verification --compiler-mode unstructured-2to4 --trace
 */

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define M_DIM 8u
#define N_DIM 8u
#define K_DIM 8u
#define VECTOR_LANES 8u
#define GROUP_SIZE 4u
#define K_GROUPS (K_DIM / GROUP_SIZE)
#define KEEP_PER_GROUP 2u
#define DIRECTED_PACKETS 4u
#define MAX_BATCH_PACKETS 256u
#define PIPELINE_LATENCY 4u
#define PIPELINE_TIMEOUT_MARGIN 16u
#define FULL_MASK_8 ((uint8_t)0xFFu)
#define INVALID_INDEX ((uint8_t)0xFFu)
#define ERROR_CAPACITY 512u

typedef enum {
    COMPILER_DENSE_X_DENSE = 0,
    COMPILER_UNSTRUCTURED_X_2TO4 = 1,
    COMPILER_UNSTRUCTURED_X_UNSTRUCTURED = 2
} CompilerMode;

typedef enum {
    DU_ACTION_BYPASS = 0,
    DU_ACTION_FORWARD_AND_DECODE_2TO4 = 1,
    DU_ACTION_FORWARD_DUAL_PACKED = 2
} DuAction;

typedef enum {
    TIA_ACTION_BYPASS = 0,
    TIA_ACTION_DECODE_BITMAP = 1
} TiaAction;

typedef struct {
    bool valid;
    uint32_t transaction_id;
    CompilerMode compiler_mode;
    uint8_t k;
} PacketTag;

/* Logical per-k feed for a downstream 8x8 systolic array. */
typedef struct {
    int8_t a_lane[M_DIM];
    int8_t b_lane[N_DIM];
} DenseSystolicPayload;

/*
 * Per-k outer-product input.
 * A is bitmap-encoded and already packed by an upstream encoder.
 * A valid values occupy a_packed[0 .. popcount(a_bitmap)-1]; later slots are
 * don't-care padding in this fixed-width C model.
 * For B, each column supplies the metadata and two values for tag.k's K-group.
 */
typedef struct {
    uint8_t a_bitmap;
    int8_t a_packed[M_DIM];
    uint8_t b_2to4_mask[N_DIM];
    int8_t b_packed[N_DIM][KEEP_PER_GROUP];
} HybridOuterInputPayload;

/*
 * Both per-k outer-product vectors arrive bitmap-encoded and packed. Each
 * stream's valid length is popcount(bitmap); remaining slots are don't-care.
 */
typedef struct {
    uint8_t a_bitmap;
    int8_t a_packed[M_DIM];
    uint8_t b_bitmap;
    int8_t b_packed[N_DIM];
} DualOuterInputPayload;

typedef struct {
    PacketTag tag;
    union {
        DenseSystolicPayload dense;
        HybridOuterInputPayload hybrid;
        DualOuterInputPayload dual;
    } payload;
} DuTiaInputPacket;

typedef struct {
    uint8_t bitmap;
    uint8_t count;
    uint8_t valid_mask;
    int8_t value[VECTOR_LANES];
} PackedSparseVector;

typedef struct {
    uint8_t count;
    uint8_t index[4];
} TiaHalfMap;

typedef struct {
    PackedSparseVector a;
    PackedSparseVector b;
    uint8_t b_source_rank[VECTOR_LANES];
    TiaHalfMap a_low;
    TiaHalfMap a_high;
    TiaHalfMap b_low;
    TiaHalfMap b_high;
} SparsePredecodePayload;

typedef struct {
    PacketTag tag;
    DuAction du_action;
    TiaAction tia_action;
    union {
        DenseSystolicPayload dense;
        SparsePredecodePayload sparse;
    } payload;
} Stage1Register;

typedef struct {
    PackedSparseVector a;
    PackedSparseVector b;
    uint8_t a_index[VECTOR_LANES];
    uint8_t b_index[VECTOR_LANES];
    uint8_t b_source_rank[VECTOR_LANES];
} SparseMergePayload;

typedef struct {
    PacketTag tag;
    DuAction du_action;
    TiaAction tia_action;
    union {
        DenseSystolicPayload dense;
        SparseMergePayload sparse;
    } payload;
} Stage2Register;

typedef struct {
    PackedSparseVector a;
    PackedSparseVector b;
    uint8_t a_index[VECTOR_LANES];
    uint8_t b_index[VECTOR_LANES];
    uint8_t b_source_rank[VECTOR_LANES];
} SparseOuterOutputPayload;

typedef struct {
    PacketTag tag;
    DuAction du_action;
    TiaAction tia_action;
    union {
        DenseSystolicPayload dense;
        SparseOuterOutputPayload sparse;
    } payload;
} DuTiaOutputPacket;

typedef struct {
    uint64_t cycles;
    uint64_t input_packets;
    uint64_t s0_validated;
    uint64_t s1_forwarded_or_bypassed;
    uint64_t s2_tia_merged;
    uint64_t s3_outputs_formed;
    uint64_t output_packets_checked;
    uint64_t du_bypass_packets;
    uint64_t du_hybrid_outer_packets;
    uint64_t du_dual_forward_packets;
    uint64_t tia_bypass_packets;
    uint64_t tia_decode_packets;
    uint64_t a_output_values;
    uint64_t b_output_values;
    uint64_t b_2to4_hits;
} PipelineStats;

typedef struct {
    uint32_t state;
} Rng;

typedef enum {
    SELECT_DENSE_DENSE = 1,
    SELECT_UNSTRUCTURED_2TO4 = 2,
    SELECT_UNSTRUCTURED_UNSTRUCTURED = 4,
    SELECT_ALL = 7
} ModeSelection;

typedef struct {
    unsigned mode_selection;
    unsigned random_packets;
    uint32_t seed;
    bool trace;
    bool exhaustive_tests;
    bool negative_tests;
} Options;

static bool set_error(char* error, size_t capacity, const char* format, ...)
{
    va_list arguments;
    if (error != NULL && capacity > 0u) {
        va_start(arguments, format);
        (void)vsnprintf(error, capacity, format, arguments);
        va_end(arguments);
    }
    return false;
}

static const char* mode_name(CompilerMode mode)
{
    switch (mode) {
    case COMPILER_DENSE_X_DENSE:
        return "DENSE_X_DENSE";
    case COMPILER_UNSTRUCTURED_X_2TO4:
        return "UNSTRUCTURED_X_2TO4";
    case COMPILER_UNSTRUCTURED_X_UNSTRUCTURED:
        return "UNSTRUCTURED_X_UNSTRUCTURED";
    default:
        return "INVALID_COMPILER_MODE";
    }
}

static const char* mode_short_name(CompilerMode mode)
{
    switch (mode) {
    case COMPILER_DENSE_X_DENSE:
        return "DD";
    case COMPILER_UNSTRUCTURED_X_2TO4:
        return "U2";
    case COMPILER_UNSTRUCTURED_X_UNSTRUCTURED:
        return "UU";
    default:
        return "??";
    }
}

static const char* du_action_name(DuAction action)
{
    switch (action) {
    case DU_ACTION_BYPASS:
        return "BYPASS";
    case DU_ACTION_FORWARD_AND_DECODE_2TO4:
        return "FORWARD+DECODE_2TO4";
    case DU_ACTION_FORWARD_DUAL_PACKED:
        return "FORWARD_DUAL_PACKED";
    default:
        return "INVALID_DU_ACTION";
    }
}

static const char* tia_action_name(TiaAction action)
{
    switch (action) {
    case TIA_ACTION_BYPASS:
        return "BYPASS";
    case TIA_ACTION_DECODE_BITMAP:
        return "DECODE_BITMAP";
    default:
        return "INVALID_TIA_ACTION";
    }
}

static bool valid_compiler_mode(CompilerMode mode)
{
    return mode == COMPILER_DENSE_X_DENSE ||
        mode == COMPILER_UNSTRUCTURED_X_2TO4 ||
        mode == COMPILER_UNSTRUCTURED_X_UNSTRUCTURED;
}

static unsigned popcount8(uint8_t value)
{
    unsigned count = 0u;
    while (value != 0u) {
        count += (unsigned)(value & 1u);
        value = (uint8_t)(value >> 1u);
    }
    return count;
}

static unsigned packed_rank_before(uint8_t mask, unsigned position)
{
    if (position == 0u) {
        return 0u;
    }
    return popcount8((uint8_t)(mask &
        (uint8_t)((1u << position) - 1u)));
}

static uint8_t low_bits_mask(unsigned count)
{
    if (count == 0u) {
        return 0u;
    }
    if (count >= 8u) {
        return FULL_MASK_8;
    }
    return (uint8_t)((1u << count) - 1u);
}

static uint32_t rng_next(Rng* rng)
{
    uint32_t x = rng->state;
    if (x == 0u) {
        x = 0x6D2B79F5u;
    }
    x ^= x << 13u;
    x ^= x >> 17u;
    x ^= x << 5u;
    rng->state = x;
    return x;
}

static unsigned rng_bounded(Rng* rng, unsigned bound)
{
    return bound == 0u ? 0u : (unsigned)(rng_next(rng) % bound);
}

static int8_t random_small_value(Rng* rng)
{
    return (int8_t)((int)rng_bounded(rng, 17u) - 8);
}

static int8_t random_nonzero_value(Rng* rng)
{
    int8_t value;
    do {
        value = random_small_value(rng);
    } while (value == 0);
    return value;
}

static int8_t deterministic_nonzero(unsigned seed)
{
    int value = (int)((seed * 5u + 3u) % 15u) - 7;
    return (int8_t)(value == 0 ? 7 : value);
}

static uint8_t random_2to4_mask(Rng* rng)
{
    unsigned first = rng_bounded(rng, GROUP_SIZE);
    unsigned second = rng_bounded(rng, GROUP_SIZE - 1u);
    if (second >= first) {
        ++second;
    }
    return (uint8_t)((1u << first) | (1u << second));
}

static void fill_packed_deterministic(uint8_t bitmap,
    int8_t packed[VECTOR_LANES],
    unsigned seed)
{
    unsigned lane;
    unsigned rank = 0u;
    (void)memset(packed, 0, VECTOR_LANES * sizeof(*packed));
    for (lane = 0u; lane < VECTOR_LANES; ++lane) {
        if ((bitmap & (uint8_t)(1u << lane)) != 0u) {
            packed[rank++] =
                deterministic_nonzero(seed + 17u * lane);
        }
    }
}

/*
 * Physical slots after popcount(bitmap) occasionally contain nonzero
 * don't-care data. Correct forwarding must use the bitmap-derived count and
 * must not reinterpret the packed stream as an uncompressed vector.
 */
static void fill_packed_random(uint8_t bitmap,
    int8_t packed[VECTOR_LANES],
    Rng* rng)
{
    unsigned rank;
    unsigned count = popcount8(bitmap);
    for (rank = 0u; rank < VECTOR_LANES; ++rank) {
        if (rank < count) {
            packed[rank] = random_nonzero_value(rng);
        }
        else if (rng_bounded(rng, 4u) == 0u) {
            packed[rank] = random_nonzero_value(rng);
        }
        else {
            packed[rank] = 0;
        }
    }
}

static void fill_2to4_values_deterministic(uint8_t mask,
    int8_t packed[KEEP_PER_GROUP],
    unsigned seed)
{
    unsigned position;
    unsigned rank = 0u;
    (void)memset(packed, 0, KEEP_PER_GROUP * sizeof(*packed));
    for (position = 0u; position < GROUP_SIZE; ++position) {
        if ((mask & (uint8_t)(1u << position)) != 0u) {
            packed[rank++] =
                deterministic_nonzero(seed + 13u * position);
        }
    }
}

static void fill_2to4_values_random(int8_t packed[KEEP_PER_GROUP], Rng* rng)
{
    packed[0] = random_nonzero_value(rng);
    packed[1] = random_nonzero_value(rng);
}

static void set_packet_tag(DuTiaInputPacket* packet,
    CompilerMode mode,
    uint32_t transaction_id)
{
    (void)memset(packet, 0, sizeof(*packet));
    packet->tag.valid = true;
    packet->tag.transaction_id = transaction_id;
    packet->tag.compiler_mode = mode;
    packet->tag.k = (uint8_t)(transaction_id % K_DIM);
}

static void make_directed_packet(CompilerMode mode,
    unsigned index,
    DuTiaInputPacket* packet)
{
    static const uint8_t a_bitmap[DIRECTED_PACKETS] = {
        0xA5u, 0x00u, 0xFFu, 0x18u
    };
    static const uint8_t dual_b_bitmap[DIRECTED_PACKETS] = {
        0x3Cu, 0xFFu, 0x00u, 0x81u
    };
    static const uint8_t valid_masks[6] = {
        0x03u, 0x05u, 0x06u, 0x09u, 0x0Au, 0x0Cu
    };
    unsigned slot = index % DIRECTED_PACKETS;
    unsigned lane;

    set_packet_tag(packet, mode, (uint32_t)index);
    if (mode == COMPILER_DENSE_X_DENSE) {
        for (lane = 0u; lane < VECTOR_LANES; ++lane) {
            packet->payload.dense.a_lane[lane] =
                (int8_t)((int)lane - (int)slot - 3);
            packet->payload.dense.b_lane[lane] =
                (int8_t)((int)(2u * lane + slot) - 6);
        }
        return;
    }

    if (mode == COMPILER_UNSTRUCTURED_X_2TO4) {
        HybridOuterInputPayload* hybrid = &packet->payload.hybrid;
        hybrid->a_bitmap = a_bitmap[slot];
        fill_packed_deterministic(hybrid->a_bitmap,
            hybrid->a_packed,
            30u + 19u * slot);
        for (lane = 0u; lane < N_DIM; ++lane) {
            uint8_t mask;
            if (slot == 0u || slot == 1u) {
                /* At k0 all columns hit 0101; at k1 none hit it. */
                mask = 0x05u;
            }
            else if (slot == 2u) {
                /* At k2 exactly the even columns are active. */
                mask = (lane & 1u) == 0u ? 0x06u : 0x09u;
            }
            else {
                mask = valid_masks[lane % 6u];
            }
            hybrid->b_2to4_mask[lane] = mask;
            fill_2to4_values_deterministic(
                mask, hybrid->b_packed[lane],
                120u + 23u * slot + 7u * lane);
        }
        return;
    }

    packet->payload.dual.a_bitmap = a_bitmap[slot];
    packet->payload.dual.b_bitmap = dual_b_bitmap[slot];
    fill_packed_deterministic(packet->payload.dual.a_bitmap,
        packet->payload.dual.a_packed,
        210u + 17u * slot);
    fill_packed_deterministic(packet->payload.dual.b_bitmap,
        packet->payload.dual.b_packed,
        330u + 29u * slot);
}

static void make_random_packet(CompilerMode mode,
    uint32_t transaction_id,
    Rng* rng,
    DuTiaInputPacket* packet)
{
    unsigned lane;
    set_packet_tag(packet, mode, transaction_id);
    if (mode == COMPILER_DENSE_X_DENSE) {
        for (lane = 0u; lane < VECTOR_LANES; ++lane) {
            packet->payload.dense.a_lane[lane] = random_small_value(rng);
            packet->payload.dense.b_lane[lane] = random_small_value(rng);
        }
    }
    else if (mode == COMPILER_UNSTRUCTURED_X_2TO4) {
        HybridOuterInputPayload* hybrid = &packet->payload.hybrid;
        hybrid->a_bitmap = (uint8_t)rng_bounded(rng, 256u);
        fill_packed_random(hybrid->a_bitmap, hybrid->a_packed, rng);
        for (lane = 0u; lane < N_DIM; ++lane) {
            hybrid->b_2to4_mask[lane] = random_2to4_mask(rng);
            fill_2to4_values_random(hybrid->b_packed[lane], rng);
        }
    }
    else {
        DualOuterInputPayload* dual = &packet->payload.dual;
        dual->a_bitmap = (uint8_t)rng_bounded(rng, 256u);
        dual->b_bitmap = (uint8_t)rng_bounded(rng, 256u);
        fill_packed_random(dual->a_bitmap, dual->a_packed, rng);
        fill_packed_random(dual->b_bitmap, dual->b_packed, rng);
    }
}

static bool validate_packed_stream(uint8_t bitmap,
    const int8_t packed[VECTOR_LANES],
    const char* name,
    char* error,
    size_t error_capacity)
{
    unsigned rank;
    unsigned count = popcount8(bitmap);
    for (rank = 0u; rank < count; ++rank) {
        if (packed[rank] == 0) {
            return set_error(error, error_capacity,
                "%s packed rank %u is zero",
                name, rank);
        }
    }
    return true;
}

static bool validate_2to4_column(uint8_t mask,
    const int8_t packed[KEEP_PER_GROUP],
    unsigned column,
    char* error,
    size_t error_capacity)
{
    unsigned rank;
    if ((mask & 0xF0u) != 0u || popcount8(mask) != KEEP_PER_GROUP) {
        return set_error(error, error_capacity,
            "B column %u invalid 2:4 metadata: mask=0x%02x",
            column, (unsigned)mask);
    }
    for (rank = 0u; rank < KEEP_PER_GROUP; ++rank) {
        if (packed[rank] == 0) {
            return set_error(error, error_capacity,
                "B column %u packed rank %u is zero",
                column, rank);
        }
    }
    return true;
}

static bool validate_input_packet(const DuTiaInputPacket* input,
    char* error,
    size_t error_capacity)
{
    unsigned column;
    if (!input->tag.valid) {
        return set_error(error, error_capacity,
            "S0 received an invalid input packet");
    }
    if (!valid_compiler_mode(input->tag.compiler_mode)) {
        return set_error(error, error_capacity,
            "S0 invalid compiler mode %d",
            (int)input->tag.compiler_mode);
    }
    if (input->tag.k >= K_DIM) {
        return set_error(error, error_capacity,
            "S0 k=%u is out of range",
            (unsigned)input->tag.k);
    }

    if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4) {
        const HybridOuterInputPayload* hybrid = &input->payload.hybrid;
        if (!validate_packed_stream(hybrid->a_bitmap,
            hybrid->a_packed,
            "A unstructured",
            error, error_capacity)) {
            return false;
        }
        for (column = 0u; column < N_DIM; ++column) {
            if (!validate_2to4_column(
                hybrid->b_2to4_mask[column],
                hybrid->b_packed[column],
                column, error, error_capacity)) {
                return false;
            }
        }
    }
    else if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        const DualOuterInputPayload* dual = &input->payload.dual;
        return validate_packed_stream(dual->a_bitmap,
            dual->a_packed,
            "A unstructured",
            error, error_capacity) &&
            validate_packed_stream(dual->b_bitmap,
                dual->b_packed,
                "B unstructured",
                error, error_capacity);
    }
    return true;
}

static void initialize_packed_vector(PackedSparseVector* vector)
{
    (void)memset(vector, 0, sizeof(*vector));
}

static unsigned du_forward_packed(uint8_t bitmap,
    const int8_t packed[VECTOR_LANES],
    PackedSparseVector* output)
{
    unsigned count = popcount8(bitmap);
    initialize_packed_vector(output);
    output->bitmap = bitmap;
    output->count = (uint8_t)count;
    output->valid_mask = low_bits_mask(count);
    if (count != 0u) {
        (void)memcpy(output->value, packed,
            count * sizeof(*output->value));
    }
    return count;
}
/*直向column的2:4轉換成k=?的一列*/
static unsigned du_decode_2to4_for_k(
    uint8_t k,
    const uint8_t mask[N_DIM],
    const int8_t packed[N_DIM][KEEP_PER_GROUP],
    PackedSparseVector* output,
    uint8_t source_rank[VECTOR_LANES])
{
    unsigned column;
    unsigned position = k % GROUP_SIZE;
    initialize_packed_vector(output);
    (void)memset(source_rank, INVALID_INDEX,
        VECTOR_LANES * sizeof(*source_rank));

    for (column = 0u; column < N_DIM; ++column) {
        uint8_t column_mask = mask[column];
        if ((column_mask & (uint8_t)(1u << position)) != 0u) {
            unsigned rank = packed_rank_before(column_mask, position);
            output->bitmap = (uint8_t)(output->bitmap |
                (uint8_t)(1u << column));
            output->value[output->count] = packed[column][rank];
            source_rank[output->count] = (uint8_t)rank;
            ++output->count;
        }
    }
    output->valid_mask = low_bits_mask(output->count);
    return output->count;
}

static void tia_decode_half(uint8_t bitmap,
    unsigned base,
    TiaHalfMap* output)
{
    unsigned position;
    (void)memset(output, 0, sizeof(*output));
    (void)memset(output->index, INVALID_INDEX, sizeof(output->index));
    for (position = 0u; position < 4u; ++position) {
        unsigned logical_index = base + position;
        if ((bitmap & (uint8_t)(1u << logical_index)) != 0u) {
            output->index[output->count++] = (uint8_t)logical_index;
        }
    }
}

static unsigned tia_merge_halves(const TiaHalfMap* low,
    const TiaHalfMap* high,
    uint8_t output[VECTOR_LANES])
{
    unsigned count = 0u;
    unsigned index;
    (void)memset(output, INVALID_INDEX,
        VECTOR_LANES * sizeof(*output));
    for (index = 0u; index < low->count; ++index) {
        output[count++] = low->index[index];
    }
    for (index = 0u; index < high->count; ++index) {
        output[count++] = high->index[index];
    }
    return count;
}

/* S0: latch and validate the compiler-selected input packet. */
static bool stage_s0_input_control(const DuTiaInputPacket* input,
    DuTiaInputPacket* output,
    PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    (void)memset(output, 0, sizeof(*output));
    if (!validate_input_packet(input, error, error_capacity)) {
        return false;
    }
    *output = *input;
    ++stats->input_packets;
    ++stats->s0_validated;
    return true;
}

static void predecode_sparse_indexes(SparsePredecodePayload* sparse)
{
    tia_decode_half(sparse->a.bitmap, 0u, &sparse->a_low);
    tia_decode_half(sparse->a.bitmap, 4u, &sparse->a_high);
    tia_decode_half(sparse->b.bitmap, 0u, &sparse->b_low);
    tia_decode_half(sparse->b.bitmap, 4u, &sparse->b_high);
}

/* S1: DU forward/decode and TIA half-map generation. */
static bool stage_s1_du_forward_tia_predecode(
    const DuTiaInputPacket* input,
    Stage1Register* output,
    PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    SparsePredecodePayload* sparse;
    (void)memset(output, 0, sizeof(*output));
    if (!input->tag.valid) {
        return set_error(error, error_capacity,
            "S1 received an invalid S0 register");
    }
    output->tag = input->tag;

    if (input->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        output->du_action = DU_ACTION_BYPASS;
        output->tia_action = TIA_ACTION_BYPASS;
        output->payload.dense = input->payload.dense;
        ++stats->du_bypass_packets;
        ++stats->tia_bypass_packets;
        ++stats->s1_forwarded_or_bypassed;
        return true;
    }

    output->tia_action = TIA_ACTION_DECODE_BITMAP;
    sparse = &output->payload.sparse;
    (void)memset(sparse->b_source_rank, INVALID_INDEX,
        sizeof(sparse->b_source_rank));

    if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4) {
        output->du_action =
            DU_ACTION_FORWARD_AND_DECODE_2TO4;
        (void)du_forward_packed(input->payload.hybrid.a_bitmap,
            input->payload.hybrid.a_packed,
            &sparse->a);
        (void)du_decode_2to4_for_k(
            input->tag.k,
            input->payload.hybrid.b_2to4_mask,
            input->payload.hybrid.b_packed,
            &sparse->b,
            sparse->b_source_rank);//rank其實不用往下面的stages傳
        ++stats->du_hybrid_outer_packets;
        stats->b_2to4_hits += sparse->b.count;
    }
    else if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        output->du_action = DU_ACTION_FORWARD_DUAL_PACKED;
        (void)du_forward_packed(input->payload.dual.a_bitmap,
            input->payload.dual.a_packed,
            &sparse->a);
        (void)du_forward_packed(input->payload.dual.b_bitmap,
            input->payload.dual.b_packed,
            &sparse->b);
        ++stats->du_dual_forward_packets;
    }
    else {
        return set_error(error, error_capacity,
            "S1 invalid compiler mode %d",
            (int)input->tag.compiler_mode);
    }

    predecode_sparse_indexes(sparse);
    ++stats->tia_decode_packets;
    stats->a_output_values += sparse->a.count;
    stats->b_output_values += sparse->b.count;
    ++stats->s1_forwarded_or_bypassed;
    return true;
}

/* S2: merge the two TIA halves for each packed sparse vector. */
static bool stage_s2_tia_merge(const Stage1Register* input,
    Stage2Register* output,
    PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    unsigned a_count;
    unsigned b_count;
    (void)memset(output, 0, sizeof(*output));
    if (!input->tag.valid) {
        return set_error(error, error_capacity,
            "S2 received an invalid S1 register");
    }
    output->tag = input->tag;
    output->du_action = input->du_action;
    output->tia_action = input->tia_action;

    if (input->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        output->payload.dense = input->payload.dense;
        ++stats->s2_tia_merged;
        return true;
    }

    output->payload.sparse.a = input->payload.sparse.a;
    output->payload.sparse.b = input->payload.sparse.b;
    (void)memcpy(output->payload.sparse.b_source_rank,
        input->payload.sparse.b_source_rank,
        sizeof(output->payload.sparse.b_source_rank));
    a_count = tia_merge_halves(&input->payload.sparse.a_low,
        &input->payload.sparse.a_high,
        output->payload.sparse.a_index);
    b_count = tia_merge_halves(&input->payload.sparse.b_low,
        &input->payload.sparse.b_high,
        output->payload.sparse.b_index);
    if (a_count != output->payload.sparse.a.count ||
        b_count != output->payload.sparse.b.count) {
        return set_error(error, error_capacity,
            "S2 TIA/DU count mismatch: A=%u/%u B=%u/%u",
            a_count,
            (unsigned)output->payload.sparse.a.count,
            b_count,
            (unsigned)output->payload.sparse.b.count);
    }
    ++stats->s2_tia_merged;
    return true;
}

static void initialize_output_packet(DuTiaOutputPacket* output)
{
    (void)memset(output, 0, sizeof(*output));
    (void)memset(output->payload.sparse.a_index, INVALID_INDEX,
        sizeof(output->payload.sparse.a_index));
    (void)memset(output->payload.sparse.b_index, INVALID_INDEX,
        sizeof(output->payload.sparse.b_index));
    (void)memset(output->payload.sparse.b_source_rank, INVALID_INDEX,
        sizeof(output->payload.sparse.b_source_rank));
}

/* S3: form the final systolic-feed or packed outer-product packet. */
static bool stage_s3_output_join(const Stage2Register* input,
    DuTiaOutputPacket* output,
    PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    initialize_output_packet(output);
    if (!input->tag.valid) {
        return set_error(error, error_capacity,
            "S3 received an invalid S2 register");
    }
    output->tag = input->tag;
    output->du_action = input->du_action;
    output->tia_action = input->tia_action;

    if (input->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        output->payload.dense = input->payload.dense;
    }
    else if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4 ||
        input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        output->payload.sparse.a = input->payload.sparse.a;
        output->payload.sparse.b = input->payload.sparse.b;
        (void)memcpy(output->payload.sparse.a_index,
            input->payload.sparse.a_index,
            sizeof(output->payload.sparse.a_index));
        (void)memcpy(output->payload.sparse.b_index,
            input->payload.sparse.b_index,
            sizeof(output->payload.sparse.b_index));
        (void)memcpy(output->payload.sparse.b_source_rank,
            input->payload.sparse.b_source_rank,
            sizeof(output->payload.sparse.b_source_rank));
    }
    else {
        return set_error(error, error_capacity,
            "S3 invalid compiler mode %d",
            (int)input->tag.compiler_mode);
    }
    ++stats->s3_outputs_formed;
    return true;
}

/*
 * Independent non-pipelined oracle. It interprets the bitmap plus packed
 * streams directly rather than calling the DU/TIA stage helpers.
 */
static bool golden_du_tia(const DuTiaInputPacket* input,
    DuTiaOutputPacket* output,
    char* error,
    size_t error_capacity)
{
    unsigned lane;
    unsigned a_count = 0u;
    unsigned b_count = 0u;
    initialize_output_packet(output);
    if (!validate_input_packet(input, error, error_capacity)) {
        return false;
    }
    output->tag = input->tag;

    if (input->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        output->du_action = DU_ACTION_BYPASS;
        output->tia_action = TIA_ACTION_BYPASS;
        output->payload.dense = input->payload.dense;
        return true;
    }

    output->tia_action = TIA_ACTION_DECODE_BITMAP;
    if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4) {
        const HybridOuterInputPayload* source = &input->payload.hybrid;
        unsigned position = input->tag.k % GROUP_SIZE;
        output->du_action =
            DU_ACTION_FORWARD_AND_DECODE_2TO4;
        output->payload.sparse.a.bitmap = source->a_bitmap;
        for (lane = 0u; lane < M_DIM; ++lane) {
            if ((source->a_bitmap & (uint8_t)(1u << lane)) != 0u) {
                output->payload.sparse.a.value[a_count] =
                    source->a_packed[a_count];
                output->payload.sparse.a_index[a_count] =
                    (uint8_t)lane;
                ++a_count;
            }
        }
        for (lane = 0u; lane < N_DIM; ++lane) {
            uint8_t mask = source->b_2to4_mask[lane];
            if ((mask & (uint8_t)(1u << position)) != 0u) {
                unsigned rank = packed_rank_before(mask, position);
                output->payload.sparse.b.bitmap =
                    (uint8_t)(output->payload.sparse.b.bitmap |
                        (uint8_t)(1u << lane));
                output->payload.sparse.b.value[b_count] =
                    source->b_packed[lane][rank];
                output->payload.sparse.b_index[b_count] =
                    (uint8_t)lane;
                output->payload.sparse.b_source_rank[b_count] =
                    (uint8_t)rank;
                ++b_count;
            }
        }
    }
    else if (input->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        const DualOuterInputPayload* source = &input->payload.dual;
        output->du_action = DU_ACTION_FORWARD_DUAL_PACKED;
        output->payload.sparse.a.bitmap = source->a_bitmap;
        output->payload.sparse.b.bitmap = source->b_bitmap;
        for (lane = 0u; lane < VECTOR_LANES; ++lane) {
            if ((source->a_bitmap & (uint8_t)(1u << lane)) != 0u) {
                output->payload.sparse.a.value[a_count] =
                    source->a_packed[a_count];
                output->payload.sparse.a_index[a_count] =
                    (uint8_t)lane;
                ++a_count;
            }
            if ((source->b_bitmap & (uint8_t)(1u << lane)) != 0u) {
                output->payload.sparse.b.value[b_count] =
                    source->b_packed[b_count];
                output->payload.sparse.b_index[b_count] =
                    (uint8_t)lane;
                ++b_count;
            }
        }
    }
    else {
        return set_error(error, error_capacity,
            "Golden received invalid compiler mode %d",
            (int)input->tag.compiler_mode);
    }

    output->payload.sparse.a.count = (uint8_t)a_count;
    output->payload.sparse.a.valid_mask = low_bits_mask(a_count);
    output->payload.sparse.b.count = (uint8_t)b_count;
    output->payload.sparse.b.valid_mask = low_bits_mask(b_count);
    return true;
}

static bool tags_equal(const PacketTag* left, const PacketTag* right)
{
    return left->valid == right->valid &&
        left->transaction_id == right->transaction_id &&
        left->compiler_mode == right->compiler_mode &&
        left->k == right->k;
}

static bool compare_packed_vector(const PackedSparseVector* actual,
    const PackedSparseVector* expected)
{
    return actual->bitmap == expected->bitmap &&
        actual->count == expected->count &&
        actual->valid_mask == expected->valid_mask &&
        memcmp(actual->value, expected->value,
            sizeof(actual->value)) == 0;
}

static bool compare_output_packets(const DuTiaOutputPacket* actual,
    const DuTiaOutputPacket* expected,
    char* error,
    size_t error_capacity)
{
    CompilerMode mode = expected->tag.compiler_mode;
    if (!tags_equal(&actual->tag, &expected->tag)) {
        return set_error(error, error_capacity,
            "Output tag mismatch for transaction %u",
            expected->tag.transaction_id);
    }
    if (actual->du_action != expected->du_action ||
        actual->tia_action != expected->tia_action) {
        return set_error(error, error_capacity,
            "Action mismatch for transaction %u: "
            "DU=%s/%s TIA=%s/%s",
            expected->tag.transaction_id,
            du_action_name(actual->du_action),
            du_action_name(expected->du_action),
            tia_action_name(actual->tia_action),
            tia_action_name(expected->tia_action));
    }

    if (mode == COMPILER_DENSE_X_DENSE) {
        if (memcmp(&actual->payload.dense,
            &expected->payload.dense,
            sizeof(actual->payload.dense)) != 0) {
            return set_error(error, error_capacity,
                "Dense systolic-feed bypass mismatch "
                "for transaction %u",
                expected->tag.transaction_id);
        }
        return true;
    }

    if (mode == COMPILER_UNSTRUCTURED_X_2TO4 ||
        mode == COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        if (!compare_packed_vector(&actual->payload.sparse.a,
            &expected->payload.sparse.a) ||
            !compare_packed_vector(&actual->payload.sparse.b,
                &expected->payload.sparse.b) ||
            memcmp(actual->payload.sparse.a_index,
                expected->payload.sparse.a_index,
                sizeof(actual->payload.sparse.a_index)) != 0 ||
            memcmp(actual->payload.sparse.b_index,
                expected->payload.sparse.b_index,
                sizeof(actual->payload.sparse.b_index)) != 0 ||
            memcmp(actual->payload.sparse.b_source_rank,
                expected->payload.sparse.b_source_rank,
                sizeof(actual->payload.sparse.b_source_rank)) != 0) {
            return set_error(error, error_capacity,
                "%s packed outer-product packet mismatch "
                "for transaction %u",
                mode_name(mode),
                expected->tag.transaction_id);
        }
        return true;
    }

    return set_error(error, error_capacity,
        "Comparison received invalid compiler mode %d",
        (int)mode);
}

static void print_bits(uint8_t value, unsigned width)
{
    unsigned bit;
    for (bit = width; bit > 0u; --bit) {
        (void)putchar((value &
            (uint8_t)(1u << (bit - 1u))) != 0u
            ? '1'
            : '0');
    }
}

static void print_tag_slot(const PacketTag* tag)
{
    if (!tag->valid) {
        (void)printf("--");
        return;
    }
    (void)printf("%s#%u(k%u)",
        mode_short_name(tag->compiler_mode),
        tag->transaction_id,
        (unsigned)tag->k);
}

static void print_value_list(const int8_t* value, unsigned count)
{
    unsigned lane;
    (void)putchar('{');
    for (lane = 0u; lane < count; ++lane) {
        if (lane != 0u) {
            (void)putchar(',');
        }
        (void)printf("%d", (int)value[lane]);
    }
    (void)putchar('}');
}

static void print_index_list(const uint8_t* index, unsigned count)
{
    unsigned lane;
    (void)putchar('{');
    for (lane = 0u; lane < count; ++lane) {
        if (lane != 0u) {
            (void)putchar(',');
        }
        (void)printf("%u", (unsigned)index[lane]);
    }
    (void)putchar('}');
}

static void print_raw_vector(const int8_t value[VECTOR_LANES])
{
    print_value_list(value, VECTOR_LANES);
}

static void print_2to4_masks(const uint8_t mask[N_DIM])
{
    unsigned column;
    (void)putchar('{');
    for (column = 0u; column < N_DIM; ++column) {
        if (column != 0u) {
            (void)putchar(',');
        }
        print_bits(mask[column], GROUP_SIZE);
    }
    (void)putchar('}');
}

static void print_2to4_packed_values(
    const int8_t packed[N_DIM][KEEP_PER_GROUP])
{
    unsigned column;
    (void)putchar('{');
    for (column = 0u; column < N_DIM; ++column) {
        if (column != 0u) {
            (void)putchar(',');
        }
        (void)printf("[%d,%d]", (int)packed[column][0],
            (int)packed[column][1]);
    }
    (void)putchar('}');
}

static void trace_s0_detail(const DuTiaInputPacket* s0)
{
    if (!s0->tag.valid) {
        return;
    }
    if (s0->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        (void)printf("    S0 dense systolic feed A[:,k]=");
        print_raw_vector(s0->payload.dense.a_lane);
        (void)printf(" B[k,:]=");
        print_raw_vector(s0->payload.dense.b_lane);
        (void)printf("\n");
    }
    else if (s0->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4) {
        (void)printf("    S0 A bitmap=");
        print_bits(s0->payload.hybrid.a_bitmap, 8u);
        (void)printf(" packed=");
        print_value_list(s0->payload.hybrid.a_packed,
            popcount8(s0->payload.hybrid.a_bitmap));
        (void)printf(" | B group=%u position=%u masks=",
            (unsigned)(s0->tag.k / GROUP_SIZE),
            (unsigned)(s0->tag.k % GROUP_SIZE));
        print_2to4_masks(s0->payload.hybrid.b_2to4_mask);
        (void)printf(" packed2=");
        print_2to4_packed_values(s0->payload.hybrid.b_packed);
        (void)printf("\n");
    }
    else {
        (void)printf("    S0 A bitmap=");
        print_bits(s0->payload.dual.a_bitmap, 8u);
        (void)printf(" packed=");
        print_value_list(s0->payload.dual.a_packed,
            popcount8(s0->payload.dual.a_bitmap));
        (void)printf(" | B bitmap=");
        print_bits(s0->payload.dual.b_bitmap, 8u);
        (void)printf(" packed=");
        print_value_list(s0->payload.dual.b_packed,
            popcount8(s0->payload.dual.b_bitmap));
        (void)printf("\n");
    }
}

static void trace_s1_detail(const Stage1Register* s1)
{
    if (!s1->tag.valid) {
        return;
    }
    (void)printf("    S1 DU=%s TIA=%s",
        du_action_name(s1->du_action),
        tia_action_name(s1->tia_action));
    if (s1->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        (void)printf("\n");
        return;
    }
    (void)printf(" | A forwarded=");
    print_value_list(s1->payload.sparse.a.value,
        s1->payload.sparse.a.count);
    (void)printf(" bitmap=");
    print_bits(s1->payload.sparse.a.bitmap, 8u);
    (void)printf(s1->tag.compiler_mode ==
        COMPILER_UNSTRUCTURED_X_2TO4
        ? " | B 2:4-selected="
        : " | B forwarded=");
    print_value_list(s1->payload.sparse.b.value,
        s1->payload.sparse.b.count);
    (void)printf(" bitmap=");
    print_bits(s1->payload.sparse.b.bitmap, 8u);
    (void)printf("\n");
}

static void trace_s2_detail(const Stage2Register* s2)
{
    if (!s2->tag.valid) {
        return;
    }
    if (s2->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        (void)printf("    S2 dense bypass remains unchanged\n");
        return;
    }
    (void)printf("    S2 TIA A row indexes=");
    print_index_list(s2->payload.sparse.a_index,
        s2->payload.sparse.a.count);
    (void)printf(" | B column indexes=");
    print_index_list(s2->payload.sparse.b_index,
        s2->payload.sparse.b.count);
    (void)printf("\n");
}

static void trace_s3_detail(const DuTiaOutputPacket* s3)
{
    unsigned lane;
    if (!s3->tag.valid) {
        return;
    }
    if (s3->tag.compiler_mode == COMPILER_DENSE_X_DENSE) {
        (void)printf("    S3 systolic packet A[:,k]=");
        print_raw_vector(s3->payload.dense.a_lane);
        (void)printf(" B[k,:]=");
        print_raw_vector(s3->payload.dense.b_lane);
        (void)printf("\n");
        return;
    }
    (void)printf("    S3 packed outer packet A={");
    for (lane = 0u; lane < s3->payload.sparse.a.count; ++lane) {
        if (lane != 0u) {
            (void)putchar(',');
        }
        (void)printf("%d@r%u",
            (int)s3->payload.sparse.a.value[lane],
            (unsigned)s3->payload.sparse.a_index[lane]);
    }
    (void)printf("} B={");
    for (lane = 0u; lane < s3->payload.sparse.b.count; ++lane) {
        if (lane != 0u) {
            (void)putchar(',');
        }
        (void)printf("%d@c%u",
            (int)s3->payload.sparse.b.value[lane],
            (unsigned)s3->payload.sparse.b_index[lane]);
        if (s3->tag.compiler_mode ==
            COMPILER_UNSTRUCTURED_X_2TO4) {
            (void)printf("[rank%u]",
                (unsigned)s3->payload.sparse
                .b_source_rank[lane]);
        }
    }
    (void)printf("} -> %u x %u outer-product pairs\n",
        (unsigned)s3->payload.sparse.a.count,
        (unsigned)s3->payload.sparse.b.count);
}

static void trace_cycle(unsigned cycle,
    const DuTiaInputPacket* inject,
    const DuTiaInputPacket* s0,
    const Stage1Register* s1,
    const Stage2Register* s2,
    const DuTiaOutputPacket* s3)
{
    PacketTag empty = { 0 };
    (void)printf("cycle %03u | IN=", cycle);
    print_tag_slot(inject != NULL ? &inject->tag : &empty);
    (void)printf(" | S0 INPUT/CTRL=");
    print_tag_slot(&s0->tag);
    (void)printf(" | S1 DU FWD/DEC+TIA PRE=");
    print_tag_slot(&s1->tag);
    (void)printf(" | S2 TIA MERGE=");
    print_tag_slot(&s2->tag);
    (void)printf(" | S3 OUTPUT=");
    print_tag_slot(&s3->tag);
    (void)printf("\n");
    trace_s0_detail(s0);
    trace_s1_detail(s1);
    trace_s2_detail(s2);
    trace_s3_detail(s3);
}

static bool pipeline_not_empty(const DuTiaInputPacket* s0,
    const Stage1Register* s1,
    const Stage2Register* s2,
    const DuTiaOutputPacket* s3)
{
    return s0->tag.valid || s1->tag.valid ||
        s2->tag.valid || s3->tag.valid;
}

static bool verify_stream_accounting(size_t input_count,
    const PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    uint64_t expected_cycles = input_count == 0u
        ? 0u
        : (uint64_t)input_count +
        PIPELINE_LATENCY;
    if (stats->cycles != expected_cycles ||
        stats->input_packets != input_count ||
        stats->s0_validated != input_count ||
        stats->s1_forwarded_or_bypassed != input_count ||
        stats->s2_tia_merged != input_count ||
        stats->s3_outputs_formed != input_count ||
        stats->output_packets_checked != input_count) {
        return set_error(
            error, error_capacity,
            "Pipeline accounting mismatch: inputs=%llu cycles=%llu "
            "S0=%llu S1=%llu S2=%llu S3=%llu outputs=%llu",
            (unsigned long long)stats->input_packets,
            (unsigned long long)stats->cycles,
            (unsigned long long)stats->s0_validated,
            (unsigned long long)stats->s1_forwarded_or_bypassed,
            (unsigned long long)stats->s2_tia_merged,
            (unsigned long long)stats->s3_outputs_formed,
            (unsigned long long)stats->output_packets_checked);
    }
    return true;
}

static bool run_pipeline_stream(const DuTiaInputPacket* inputs,
    size_t input_count,
    bool trace,
    PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    DuTiaInputPacket s0 = { 0 };
    Stage1Register s1 = { 0 };
    Stage2Register s2 = { 0 };
    DuTiaOutputPacket s3 = { 0 };
    size_t next_input = 0u;
    size_t next_output = 0u;
    unsigned cycle = 0u;

    (void)memset(stats, 0, sizeof(*stats));
    while (next_input < input_count ||
        pipeline_not_empty(&s0, &s1, &s2, &s3)) {
        DuTiaInputPacket next_s0 = { 0 };
        Stage1Register next_s1 = { 0 };
        Stage2Register next_s2 = { 0 };
        DuTiaOutputPacket next_s3 = { 0 };
        const DuTiaInputPacket* inject =
            next_input < input_count ? &inputs[next_input] : NULL;

        if ((uint64_t)cycle >
            (uint64_t)input_count + PIPELINE_LATENCY +
            PIPELINE_TIMEOUT_MARGIN) {
            return set_error(error, error_capacity,
                "DU/TIA pipeline timeout");
        }
        if (trace) {
            trace_cycle(cycle, inject, &s0, &s1, &s2, &s3);
        }

        if (s3.tag.valid) {
            DuTiaOutputPacket expected;
            if (next_output >= input_count) {
                return set_error(error, error_capacity,
                    "Pipeline produced an unexpected output");
            }
            if (!golden_du_tia(&inputs[next_output], &expected,
                error, error_capacity) ||
                !compare_output_packets(&s3, &expected,
                    error, error_capacity)) {
                return false;
            }
            ++next_output;
            ++stats->output_packets_checked;
        }
        if (s2.tag.valid &&
            !stage_s3_output_join(&s2, &next_s3, stats,
                error, error_capacity)) {
            return false;
        }
        if (s1.tag.valid &&
            !stage_s2_tia_merge(&s1, &next_s2, stats,
                error, error_capacity)) {
            return false;
        }
        if (s0.tag.valid &&
            !stage_s1_du_forward_tia_predecode(
                &s0, &next_s1, stats, error, error_capacity)) {
            return false;
        }
        if (inject != NULL) {
            if (!stage_s0_input_control(inject, &next_s0, stats,
                error, error_capacity)) {
                return false;
            }
            ++next_input;
        }

        s0 = next_s0;
        s1 = next_s1;
        s2 = next_s2;
        s3 = next_s3;
        ++cycle;
        ++stats->cycles;
    }

    if (next_output != input_count) {
        return set_error(error, error_capacity,
            "Pipeline retired %llu outputs for %llu inputs",
            (unsigned long long)next_output,
            (unsigned long long)input_count);
    }
    return verify_stream_accounting(input_count, stats,
        error, error_capacity);
}

static void add_stats(PipelineStats* total,
    const PipelineStats* value)
{
    total->cycles += value->cycles;
    total->input_packets += value->input_packets;
    total->s0_validated += value->s0_validated;
    total->s1_forwarded_or_bypassed +=
        value->s1_forwarded_or_bypassed;
    total->s2_tia_merged += value->s2_tia_merged;
    total->s3_outputs_formed += value->s3_outputs_formed;
    total->output_packets_checked += value->output_packets_checked;
    total->du_bypass_packets += value->du_bypass_packets;
    total->du_hybrid_outer_packets +=
        value->du_hybrid_outer_packets;
    total->du_dual_forward_packets +=
        value->du_dual_forward_packets;
    total->tia_bypass_packets += value->tia_bypass_packets;
    total->tia_decode_packets += value->tia_decode_packets;
    total->a_output_values += value->a_output_values;
    total->b_output_values += value->b_output_values;
    total->b_2to4_hits += value->b_2to4_hits;
}

static bool run_exhaustive_hybrid(PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    static const uint8_t valid_masks[6] = {
        0x03u, 0x05u, 0x06u, 0x09u, 0x0Au, 0x0Cu
    };
    DuTiaInputPacket inputs[48];
    unsigned k;
    unsigned pattern;
    unsigned column;
    size_t count = 0u;

    for (k = 0u; k < K_DIM; ++k) {
        for (pattern = 0u; pattern < 6u; ++pattern) {
            HybridOuterInputPayload* hybrid;
            set_packet_tag(&inputs[count],
                COMPILER_UNSTRUCTURED_X_2TO4,
                (uint32_t)(4000u + count));
            inputs[count].tag.k = (uint8_t)k;
            hybrid = &inputs[count].payload.hybrid;
            hybrid->a_bitmap =
                (uint8_t)((37u * pattern + 19u * k) & 0xFFu);
            fill_packed_deterministic(hybrid->a_bitmap,
                hybrid->a_packed,
                (unsigned)(500u + count));
            for (column = 0u; column < N_DIM; ++column) {
                uint8_t mask =
                    valid_masks[(pattern + column) % 6u];
                hybrid->b_2to4_mask[column] = mask;
                fill_2to4_values_deterministic(
                    mask, hybrid->b_packed[column],
                    (unsigned)(900u + 13u * count + column));
            }
            ++count;
        }
    }
    return run_pipeline_stream(inputs, count, false, stats,
        error, error_capacity);
}

static bool run_exhaustive_packed_tia(PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    DuTiaInputPacket inputs[256];
    unsigned bitmap;
    for (bitmap = 0u; bitmap < 256u; ++bitmap) {
        DualOuterInputPayload* dual;
        set_packet_tag(&inputs[bitmap],
            COMPILER_UNSTRUCTURED_X_UNSTRUCTURED,
            (uint32_t)(5000u + bitmap));
        dual = &inputs[bitmap].payload.dual;
        dual->a_bitmap = (uint8_t)bitmap;
        dual->b_bitmap = (uint8_t)(~bitmap);
        unsigned a_count = popcount8(dual->a_bitmap);
        unsigned b_count = popcount8(dual->b_bitmap);
        fill_packed_deterministic(dual->a_bitmap,
            dual->a_packed,
            100u + bitmap);
        fill_packed_deterministic(dual->b_bitmap,
            dual->b_packed,
            600u + bitmap);
        /*
         * Add nonzero data immediately after each valid packed stream. A
         * correct DU forwards only popcount(bitmap) values.
         */
        if (a_count < VECTOR_LANES) {
            dual->a_packed[a_count] =
                deterministic_nonzero(1300u + bitmap);
        }
        if (b_count < VECTOR_LANES) {
            dual->b_packed[b_count] =
                deterministic_nonzero(1700u + bitmap);
        }
    }
    return run_pipeline_stream(inputs, 256u, false, stats,
        error, error_capacity);
}

static bool verify_mode_action_counts(CompilerMode mode,
    const PipelineStats* stats,
    char* error,
    size_t error_capacity)
{
    uint64_t packets = stats->output_packets_checked;
    if (mode == COMPILER_DENSE_X_DENSE) {
        if (stats->du_bypass_packets != packets ||
            stats->tia_bypass_packets != packets ||
            stats->du_hybrid_outer_packets != 0u ||
            stats->du_dual_forward_packets != 0u ||
            stats->tia_decode_packets != 0u) {
            return set_error(error, error_capacity,
                "Dense action accounting mismatch");
        }
    }
    else if (mode == COMPILER_UNSTRUCTURED_X_2TO4) {
        if (stats->du_hybrid_outer_packets != packets ||
            stats->tia_decode_packets != packets ||
            stats->du_bypass_packets != 0u ||
            stats->du_dual_forward_packets != 0u ||
            stats->tia_bypass_packets != 0u ||
            stats->b_2to4_hits != stats->b_output_values) {
            return set_error(error, error_capacity,
                "Hybrid outer action accounting mismatch");
        }
    }
    else if (mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        if (stats->du_dual_forward_packets != packets ||
            stats->tia_decode_packets != packets ||
            stats->du_bypass_packets != 0u ||
            stats->du_hybrid_outer_packets != 0u ||
            stats->tia_bypass_packets != 0u ||
            stats->b_2to4_hits != 0u) {
            return set_error(error, error_capacity,
                "Dual outer action accounting mismatch");
        }
    }
    return true;
}

static bool run_mode_suite(CompilerMode mode,
    unsigned random_packets,
    uint32_t seed,
    bool trace,
    bool exhaustive_tests,
    char* error,
    size_t error_capacity)
{
    DuTiaInputPacket batch[MAX_BATCH_PACKETS];
    PipelineStats stream_stats;
    PipelineStats total_stats = { 0 };
    Rng rng = { seed };
    unsigned index;
    unsigned completed = 0u;
    unsigned exhaustive_packets = 0u;

    for (index = 0u; index < DIRECTED_PACKETS; ++index) {
        make_directed_packet(mode, index, &batch[index]);
    }
    if (trace) {
        (void)printf(
            "\n=== DU/TIA dataflow trace: compiler mode %s ===\n",
            mode_name(mode));
        if (mode == COMPILER_DENSE_X_DENSE) {
            (void)printf(
                "    Dense packets bypass toward a downstream "
                "systolic inner-product array.\n");
        }
        else {
            (void)printf(
                "    Sparse values arrive packed; DU only forwards or "
                "2:4-decodes, and TIA produces indexes. The outer-product "
                "multiply is downstream.\n");
        }
    }
    if (!run_pipeline_stream(batch, DIRECTED_PACKETS, trace,
        &stream_stats, error, error_capacity)) {
        return false;
    }
    add_stats(&total_stats, &stream_stats);

    if (exhaustive_tests &&
        mode == COMPILER_UNSTRUCTURED_X_2TO4) {
        if (!run_exhaustive_hybrid(&stream_stats,
            error, error_capacity)) {
            return false;
        }
        exhaustive_packets = 48u;
        add_stats(&total_stats, &stream_stats);
    }
    else if (exhaustive_tests &&
        mode ==
        COMPILER_UNSTRUCTURED_X_UNSTRUCTURED) {
        if (!run_exhaustive_packed_tia(
            &stream_stats, error, error_capacity)) {
            return false;
        }
        exhaustive_packets = 256u;
        add_stats(&total_stats, &stream_stats);
    }

    while (completed < random_packets) {
        unsigned count = random_packets - completed;
        if (count > MAX_BATCH_PACKETS) {
            count = MAX_BATCH_PACKETS;
        }
        for (index = 0u; index < count; ++index) {
            make_random_packet(
                mode,
                (uint32_t)(100000u + completed + index),
                &rng, &batch[index]);
        }
        if (!run_pipeline_stream(batch, count, false,
            &stream_stats,
            error, error_capacity)) {
            return false;
        }
        add_stats(&total_stats, &stream_stats);
        completed += count;
    }

    if (!verify_mode_action_counts(mode, &total_stats,
        error, error_capacity)) {
        return false;
    }
    (void)printf("[PASS] %-29s directed=%u exhaustive=%u "
        "random=%u checked=%llu",
        mode_name(mode), DIRECTED_PACKETS,
        exhaustive_packets, random_packets,
        (unsigned long long)
        total_stats.output_packets_checked);
    if (mode != COMPILER_DENSE_X_DENSE) {
        (void)printf(" output-values(A/B)=%llu/%llu",
            (unsigned long long)
            total_stats.a_output_values,
            (unsigned long long)
            total_stats.b_output_values);
    }
    if (mode == COMPILER_UNSTRUCTURED_X_2TO4) {
        (void)printf(" B-2:4-hits=%llu",
            (unsigned long long)
            total_stats.b_2to4_hits);
    }
    (void)printf("\n");
    return true;
}

static bool expect_failure(const DuTiaInputPacket* input,
    const char* expected_text,
    char* error,
    size_t error_capacity)
{
    PipelineStats stats;
    char local_error[ERROR_CAPACITY] = { 0 };
    if (run_pipeline_stream(input, 1u, false, &stats,
        local_error, sizeof(local_error))) {
        return set_error(error, error_capacity,
            "Negative test unexpectedly passed; "
            "expected '%s'",
            expected_text);
    }
    if (strstr(local_error, expected_text) == NULL) {
        return set_error(error, error_capacity,
            "Negative test returned '%s'; expected '%s'",
            local_error, expected_text);
    }
    return true;
}

static bool run_negative_tests(unsigned mode_selection,
    char* error,
    size_t error_capacity)
{
    DuTiaInputPacket input;

    make_directed_packet(COMPILER_DENSE_X_DENSE, 0u, &input);
    input.tag.compiler_mode = (CompilerMode)99;
    if (!expect_failure(&input, "invalid compiler mode",
        error, error_capacity)) {
        return false;
    }

    make_directed_packet(COMPILER_DENSE_X_DENSE, 0u, &input);
    input.tag.k = K_DIM;
    if (!expect_failure(&input, "out of range",
        error, error_capacity)) {
        return false;
    }

    if ((mode_selection & SELECT_UNSTRUCTURED_2TO4) != 0u) {
        make_directed_packet(COMPILER_UNSTRUCTURED_X_2TO4,
            0u, &input);
        input.payload.hybrid.b_2to4_mask[0] = 0x07u;
        if (!expect_failure(&input,
            "B column 0 invalid 2:4 metadata",
            error, error_capacity)) {
            return false;
        }

        make_directed_packet(COMPILER_UNSTRUCTURED_X_2TO4,
            0u, &input);
        input.payload.hybrid.b_packed[0][0] = 0;
        if (!expect_failure(&input,
            "B column 0 packed rank 0 is zero",
            error, error_capacity)) {
            return false;
        }

        make_directed_packet(COMPILER_UNSTRUCTURED_X_2TO4,
            0u, &input);
        input.payload.hybrid.a_packed[0] = 0;
        if (!expect_failure(
            &input,
            "A unstructured packed rank 0 is zero",
            error, error_capacity)) {
            return false;
        }
    }

    if ((mode_selection &
        SELECT_UNSTRUCTURED_UNSTRUCTURED) != 0u) {
        make_directed_packet(
            COMPILER_UNSTRUCTURED_X_UNSTRUCTURED,
            0u, &input);
        input.payload.dual.b_packed[0] = 0;
        if (!expect_failure(
            &input,
            "B unstructured packed rank 0 is zero",
            error, error_capacity)) {
            return false;
        }
    }
    return true;
}

static void print_usage(const char* program)
{
    (void)printf(
        "Usage: %s [options]\n"
        "  --compiler-mode all|dense-dense|unstructured-2to4|"
        "unstructured-unstructured\n"
        "                         Select compiler-provided mode "
        "(default all)\n"
        "  --tests N              Random packets per selected mode "
        "(default 1000)\n"
        "  --seed N               32-bit random seed\n"
        "  --trace                Trace four directed packets "
        "cycle by cycle\n"
        "  --no-exhaustive        Skip 2:4 and bitmap exhaustive tests\n"
        "  --no-negative          Skip malformed-input rejection tests\n"
        "  --help                 Show this help\n",
        program);
}

static bool parse_u32(const char* text, uint32_t* value)
{
    char* end = NULL;
    unsigned long parsed;
    errno = 0;
    parsed = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' ||
        parsed > UINT32_MAX) {
        return false;
    }
    *value = (uint32_t)parsed;
    return true;
}

static bool parse_compiler_mode(const char* text,
    unsigned* selection,
    char* error,
    size_t error_capacity)
{
    if (strcmp(text, "all") == 0) {
        *selection = SELECT_ALL;
    }
    else if (strcmp(text, "dense-dense") == 0 ||
        strcmp(text, "dense") == 0) {
        *selection = SELECT_DENSE_DENSE;
    }
    else if (strcmp(text, "unstructured-2to4") == 0 ||
        strcmp(text, "hybrid") == 0) {
        *selection = SELECT_UNSTRUCTURED_2TO4;
    }
    else if (strcmp(text,
        "unstructured-unstructured") == 0 ||
        strcmp(text, "dual") == 0) {
        *selection = SELECT_UNSTRUCTURED_UNSTRUCTURED;
    }
    else {
        return set_error(error, error_capacity,
            "Unknown compiler mode '%s'", text);
    }
    return true;
}

static bool parse_options(int argc,
    char** argv,
    Options* options,
    char* error,
    size_t error_capacity)
{
    int index;
    options->mode_selection = SELECT_ALL;
    options->random_packets = 1000u;
    options->seed = 0x00C0FFEEu;
    options->trace = false;
    options->exhaustive_tests = true;
    options->negative_tests = true;

    for (index = 1; index < argc; ++index) {
        const char* argument = argv[index];
        if (strcmp(argument, "--help") == 0) {
            print_usage(argv[0]);
            exit(EXIT_SUCCESS);
        }
        else if (strcmp(argument, "--trace") == 0) {
            options->trace = true;
        }
        else if (strcmp(argument,
            "--no-exhaustive") == 0) {
            options->exhaustive_tests = false;
        }
        else if (strcmp(argument,
            "--no-negative") == 0) {
            options->negative_tests = false;
        }
        else if (strcmp(argument,
            "--compiler-mode") == 0 ||
            strcmp(argument, "--mode") == 0) {
            if (++index >= argc ||
                !parse_compiler_mode(
                    argv[index], &options->mode_selection,
                    error, error_capacity)) {
                if (index >= argc) {
                    return set_error(error, error_capacity,
                        "%s requires a value",
                        argument);
                }
                return false;
            }
        }
        else if (strcmp(argument, "--tests") == 0) {
            uint32_t parsed;
            if (++index >= argc ||
                !parse_u32(argv[index], &parsed)) {
                return set_error(
                    error, error_capacity,
                    "--tests requires a 32-bit unsigned integer");
            }
            options->random_packets = (unsigned)parsed;
        }
        else if (strcmp(argument, "--seed") == 0) {
            if (++index >= argc ||
                !parse_u32(argv[index], &options->seed)) {
                return set_error(
                    error, error_capacity,
                    "--seed requires a 32-bit unsigned integer");
            }
        }
        else {
            return set_error(error, error_capacity,
                "Unknown option '%s'", argument);
        }
    }
    return true;
}

int main(int argc, char** argv)
{
    Options options;
    char error[ERROR_CAPACITY] = { 0 };

    if (!parse_options(argc, argv, &options,
        error, sizeof(error))) {
        (void)fprintf(stderr, "Argument error: %s\n", error);
        print_usage(argv[0]);
        return EXIT_FAILURE;
    }

    (void)printf(
        "DU/TIA unit verification only "
        "(no TC multiply, systolic PE, MSU, or GEMM)\n");
    (void)printf(
        "Pipeline: S0 INPUT/CONTROL -> "
        "S1 DU FORWARD/DECODE + TIA PREDECODE -> "
        "S2 TIA MERGE -> S3 OUTPUT/JOIN; latency=4, II=1\n");
    (void)printf(
        "Dataflow: dense -> systolic inner-product feed; "
        "sparse bitmap+packed inputs -> outer-product feed\n");

    if ((options.mode_selection & SELECT_DENSE_DENSE) != 0u &&
        !run_mode_suite(
            COMPILER_DENSE_X_DENSE,
            options.random_packets,
            options.seed ^ 0x13579BDFu,
            options.trace, options.exhaustive_tests,
            error, sizeof(error))) {
        (void)fprintf(stderr, "[FAIL] %s\n", error);
        return EXIT_FAILURE;
    }
    if ((options.mode_selection &
        SELECT_UNSTRUCTURED_2TO4) != 0u &&
        !run_mode_suite(
            COMPILER_UNSTRUCTURED_X_2TO4,
            options.random_packets,
            options.seed ^ 0xA5A5A5A5u,
            options.trace, options.exhaustive_tests,
            error, sizeof(error))) {
        (void)fprintf(stderr, "[FAIL] %s\n", error);
        return EXIT_FAILURE;
    }
    if ((options.mode_selection &
        SELECT_UNSTRUCTURED_UNSTRUCTURED) != 0u &&
        !run_mode_suite(
            COMPILER_UNSTRUCTURED_X_UNSTRUCTURED,
            options.random_packets,
            options.seed ^ 0x5A5A5A5Au,
            options.trace, options.exhaustive_tests,
            error, sizeof(error))) {
        (void)fprintf(stderr, "[FAIL] %s\n", error);
        return EXIT_FAILURE;
    }

    if (options.negative_tests) {
        if (!run_negative_tests(options.mode_selection,
            error, sizeof(error))) {
            (void)fprintf(stderr, "[FAIL] %s\n", error);
            return EXIT_FAILURE;
        }
        (void)printf(
            "[PASS] compiler-control and malformed-input tests\n");
    }

    (void)printf("ALL SELECTED DU/TIA TESTS PASSED\n");
    return EXIT_SUCCESS;
}
