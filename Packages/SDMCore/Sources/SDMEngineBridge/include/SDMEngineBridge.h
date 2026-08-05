#ifndef SDM_ENGINE_BRIDGE_UMBRELLA_H
#define SDM_ENGINE_BRIDGE_UMBRELLA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SDM_DOWNLOAD_ID_CAPACITY 37
#define SDM_URL_CAPACITY 2048
#define SDM_PATH_CAPACITY 4096
#define SDM_FILENAME_CAPACITY 512
#define SDM_ERROR_MESSAGE_CAPACITY 512
#define SDM_DIAGNOSTIC_MESSAGE_CAPACITY 1024

typedef struct sdm_engine sdm_engine_t;

typedef enum {
    SDM_RESULT_OK = 0,
    SDM_RESULT_INVALID_ARGUMENT = 1,
    SDM_RESULT_NOT_FOUND = 2,
    SDM_RESULT_INVALID_STATE = 3,
    SDM_RESULT_IO_ERROR = 4,
    SDM_RESULT_NETWORK_ERROR = 5,
    SDM_RESULT_PROTOCOL_ERROR = 6,
    SDM_RESULT_PERSISTENCE_ERROR = 7,
    SDM_RESULT_SHUTTING_DOWN = 8,
    SDM_RESULT_INTERNAL_ERROR = 9,
} sdm_result_t;

typedef enum {
    SDM_COMMAND_PAUSE = 1,
    SDM_COMMAND_RESUME = 2,
    SDM_COMMAND_CANCEL = 3,
    SDM_COMMAND_RETRY = 4,
    SDM_COMMAND_REMOVE = 5,
} sdm_command_t;

typedef enum {
    SDM_EVENT_COMMAND_RESULT = 0,
    SDM_EVENT_SNAPSHOT_CHANGED = 1,
    SDM_EVENT_REMOVED = 2,
    SDM_EVENT_ENGINE_STOPPED = 3,
    SDM_EVENT_ENGINE_READY = 4,
} sdm_event_kind_t;

typedef enum {
    SDM_DIAGNOSTIC_INFO = 0,
    SDM_DIAGNOSTIC_WARNING = 1,
    SDM_DIAGNOSTIC_ERROR = 2,
} sdm_diagnostic_level_t;

typedef struct {
    const char *data;
    size_t length;
} sdm_string_view_t;

typedef struct {
    uint32_t struct_size;
    uint32_t abi_version;
    sdm_string_view_t database_path;
    sdm_string_view_t temporary_directory;
    sdm_string_view_t certificate_authority_bundle;
    uint32_t maximum_active_downloads;
    uint32_t maximum_connections_per_download;
} sdm_engine_config_t;

typedef struct {
    uint32_t struct_size;
    sdm_string_view_t id;
    sdm_string_view_t url;
    sdm_string_view_t destination_directory;
    sdm_string_view_t filename;
    uint32_t connection_limit;
    uint64_t bandwidth_limit;
    uint32_t conflict_policy;
} sdm_download_request_t;

typedef struct {
    uint32_t struct_size;
    uint64_t sequence;
    uint64_t command_id;
    uint32_t kind;
    uint32_t result;
    char download_id[SDM_DOWNLOAD_ID_CAPACITY];
} sdm_event_t;

typedef struct {
    uint32_t struct_size;
    uint32_t state;
    uint8_t content_length_known;
    uint8_t reserved[3];
    uint64_t content_length;
    uint64_t downloaded_bytes;
    uint64_t bytes_per_second;
    uint64_t estimated_seconds_remaining;
    uint32_t segment_count;
    uint32_t error_code;
    uint64_t created_milliseconds;
    uint64_t started_milliseconds;
    uint64_t last_attempt_milliseconds;
    uint64_t completed_milliseconds;
    uint64_t updated_milliseconds;
    char id[SDM_DOWNLOAD_ID_CAPACITY];
    char source_url[SDM_URL_CAPACITY];
    char final_url[SDM_URL_CAPACITY];
    char destination_url[SDM_PATH_CAPACITY];
    char filename[SDM_FILENAME_CAPACITY];
    char error_message[SDM_ERROR_MESSAGE_CAPACITY];
} sdm_download_snapshot_t;

typedef struct {
    uint32_t struct_size;
    uint32_t ordinal;
    uint64_t start;
    uint64_t end;
    uint64_t next;
} sdm_segment_snapshot_t;

typedef struct {
    uint32_t struct_size;
    uint32_t level;
    uint32_t code;
    uint32_t reserved;
    uint64_t id;
    uint64_t timestamp_milliseconds;
    char message[SDM_DIAGNOSTIC_MESSAGE_CAPACITY];
} sdm_diagnostic_event_t;

uint32_t sdm_engine_abi_version(void);
const char *sdm_engine_version(void);
const char *sdm_curl_version(void);

sdm_result_t sdm_engine_create(
    const sdm_engine_config_t *config,
    sdm_engine_t **out_engine
);
void sdm_engine_shutdown(sdm_engine_t *engine);
void sdm_engine_destroy(sdm_engine_t *engine);

sdm_result_t sdm_engine_enqueue(
    sdm_engine_t *engine,
    const sdm_download_request_t *request,
    uint64_t *out_command_id
);
sdm_result_t sdm_engine_submit(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_command_t command,
    uint64_t *out_command_id
);

sdm_result_t sdm_engine_poll_events(
    sdm_engine_t *engine,
    sdm_event_t *events,
    size_t capacity,
    size_t *out_count
);
sdm_result_t sdm_engine_copy_snapshot(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_download_snapshot_t *out_snapshot
);
sdm_result_t sdm_engine_copy_snapshots(
    sdm_engine_t *engine,
    sdm_download_snapshot_t *snapshots,
    size_t capacity,
    size_t *out_count
);
sdm_result_t sdm_engine_copy_segments(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_segment_snapshot_t *segments,
    size_t capacity,
    size_t *out_count
);
sdm_result_t sdm_engine_copy_diagnostic_events(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_diagnostic_event_t *events,
    size_t capacity,
    size_t *out_count
);

#ifdef __cplusplus
}
#endif

#endif
