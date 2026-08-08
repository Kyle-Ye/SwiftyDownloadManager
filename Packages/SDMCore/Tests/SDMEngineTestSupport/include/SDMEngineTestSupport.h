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
bool sdm_test_curl_error_is_retryable(uint32_t error_code);
uint32_t sdm_test_curl_bad_ca_file_error(void);
uint32_t sdm_test_curl_peer_verification_error(void);
uint32_t sdm_test_curl_timeout_error(void);
uint32_t sdm_test_curl_could_not_connect_error(void);
bool sdm_test_create_v1_database(
    const char *path,
    const char *download_id,
    const char *destination_directory,
    uint64_t updated_milliseconds
);
uint32_t sdm_test_database_user_version(const char *path);
bool sdm_test_set_database_user_version(const char *path, uint32_t version);
bool sdm_test_set_download_state(
    const char *path,
    const char *download_id,
    uint32_t state
);

#ifdef __cplusplus
}
#endif

#endif
