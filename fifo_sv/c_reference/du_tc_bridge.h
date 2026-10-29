#ifndef DU_TC_BRIDGE_H
#define DU_TC_BRIDGE_H
#include "io_types.h"

typedef struct {
    bool valid, is_sparse;
    IoMeta meta;
    uint8_t k;
} BridgeTag;
typedef struct {
    TcInputPacket packet;
    IoMeta meta;
    uint8_t k;
} BridgeEntry;
typedef struct {
    BridgeTag side[IO_DU_STAGES]; /* runs beside the unmodified DU/TIA */
    BridgeEntry fifo[IO_PACKET_FIFO];
    unsigned head, count, inflight;
    IoMeta result_meta[TC_RESULT_SLOTS];
    unsigned meta_head, meta_count;
} DuTcBridge;
typedef struct {
    bool issue;               /* actual MLU -> DU/TIA transfer this edge */
    IoFrame issued;
    bool du_valid;            /* OLD DU/TIA S3 output, never stalled */
    TcInputPacket du_packet;
    bool tc_accept;           /* actual FIFO -> TC transfer this edge */
    bool result_accept;       /* actual TC -> MSU transfer this edge */
} BridgeInputs;

void bridge_reset(DuTcBridge *q);
bool bridge_can_issue(const DuTcBridge *q);
/* NULL means no eligible head. Caller must ALSO check TC mode-aware ready. */
const BridgeEntry *bridge_head(const DuTcBridge *q);
const IoMeta *bridge_result_meta(const DuTcBridge *q);
/* No payload bypass: new DU output first enters the FIFO; TC sees it next edge.
 * Used credits = fifo.count + inflight <= IO_PACKET_FIFO at every edge.
 * issue reserves a credit; DU arrival MOVES it; TC acceptance releases it.
 * Counts include ALL valid DU stages, including S3 awaiting FIFO capture.
 * Do NOT feed FIFO valid unconditionally to the strict-contract current TC:
 * tc_in_valid = eligible_head && tc_input_ready_for(tc, head.is_sparse).
 * Metadata is queued only at the first TC packet, then paired to results in
 * order. No original DU/TIA or TC port/type changes are required.
 * Sideband has exactly four stages because the supplied DU/TIA has S0..S3.
 * Reset all connected blocks together. Pointers must not alias state. */
IoStatus bridge_tick(DuTcBridge *q, const BridgeInputs *in);
#endif
