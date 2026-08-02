#ifndef SDM_ENGINE_TEST_SUPPORT_H
#define SDM_ENGINE_TEST_SUPPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t ordinal;
    uint64_t start;
    uint64_t end;
    uint64_t next;
} sdm_test_segment_t;

size_t sdm_test_plan_segments(
    uint64_t content_length,
    uint32_t requested_connections,
    uint32_t maximum_connections,
    sdm_test_segment_t *segments,
    size_t capacity
);

bool sdm_test_can_transition(uint32_t from, uint32_t to);
uint32_t sdm_test_validate_command(uint32_t state, uint32_t command);

#ifdef __cplusplus
}
#endif

#endif
