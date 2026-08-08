#include "SDMEngineTestSupport.h"

#include "SDMEngineDomain.h"

#include <curl/curl.h>
#include <sqlite3.h>

#include <algorithm>
#include <string>

size_t sdm_test_plan_segments(
    uint64_t content_length,
    uint32_t requested_connections,
    uint32_t maximum_connections,
    sdm_test_segment_t *segments,
    size_t capacity
) {
    const auto plan = sdm::plan_segments(
        content_length,
        requested_connections,
        maximum_connections
    );
    const auto count = std::min(plan.size(), capacity);
    for (size_t index = 0; index < count; ++index) {
        segments[index] = sdm_test_segment_t{
            .ordinal = plan[index].ordinal,
            .start = plan[index].start,
            .end = plan[index].end,
            .next = plan[index].next,
        };
    }
    return plan.size();
}

bool sdm_test_can_transition(uint32_t from, uint32_t to) {
    return sdm::can_transition(
        static_cast<sdm::DownloadState>(from),
        static_cast<sdm::DownloadState>(to)
    );
}

uint32_t sdm_test_validate_command(uint32_t state, uint32_t command) {
    return static_cast<uint32_t>(sdm::validate_command(
        static_cast<sdm::DownloadState>(state),
        static_cast<sdm::CommandKind>(command)
    ));
}

bool sdm_test_curl_error_is_retryable(uint32_t error_code) {
    return sdm::is_retryable_curl_error(error_code);
}

uint32_t sdm_test_curl_bad_ca_file_error(void) {
    return CURLE_SSL_CACERT_BADFILE;
}

uint32_t sdm_test_curl_peer_verification_error(void) {
    return CURLE_PEER_FAILED_VERIFICATION;
}

uint32_t sdm_test_curl_timeout_error(void) {
    return CURLE_OPERATION_TIMEDOUT;
}

uint32_t sdm_test_curl_could_not_connect_error(void) {
    return CURLE_COULDNT_CONNECT;
}

bool sdm_test_create_v1_database(
    const char *path,
    const char *download_id,
    const char *destination_directory,
    uint64_t updated_milliseconds
) {
    sqlite3 *database = nullptr;
    if (path == nullptr || download_id == nullptr || destination_directory == nullptr ||
        sqlite3_open(path, &database) != SQLITE_OK) {
        if (database != nullptr) {
            sqlite3_close(database);
        }
        return false;
    }
    const auto close_database = [&] {
        sqlite3_close(database);
    };
    const char *schema = R"sql(
        PRAGMA foreign_keys = ON;
        CREATE TABLE downloads (
            id TEXT PRIMARY KEY NOT NULL,
            source_url TEXT NOT NULL,
            destination_directory TEXT NOT NULL,
            requested_filename TEXT NOT NULL,
            connection_limit INTEGER NOT NULL,
            bandwidth_limit INTEGER NOT NULL,
            conflict_policy INTEGER NOT NULL,
            final_url TEXT NOT NULL,
            destination_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            state INTEGER NOT NULL,
            content_length_known INTEGER NOT NULL,
            content_length INTEGER NOT NULL,
            downloaded_bytes INTEGER NOT NULL,
            error_code INTEGER NOT NULL,
            error_message TEXT NOT NULL,
            temporary_path TEXT NOT NULL,
            accepts_ranges INTEGER NOT NULL,
            server_connection_limit INTEGER NOT NULL,
            etag TEXT NOT NULL,
            last_modified TEXT NOT NULL,
            updated_milliseconds INTEGER NOT NULL
        );
        CREATE TABLE segments (
            download_id TEXT NOT NULL REFERENCES downloads(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            start_byte INTEGER NOT NULL,
            end_byte INTEGER NOT NULL,
            next_byte INTEGER NOT NULL,
            PRIMARY KEY (download_id, ordinal)
        );
        PRAGMA user_version = 1;
    )sql";
    if (sqlite3_exec(database, schema, nullptr, nullptr, nullptr) != SQLITE_OK) {
        close_database();
        return false;
    }

    sqlite3_stmt *statement = nullptr;
    const char *insert = R"sql(
        INSERT INTO downloads VALUES (
            ?, 'https://example.com/legacy.bin', ?, '', 8, 0, 0, '', '',
            'legacy.bin', 10, 0, 0, 0, 0, '', '', 0, 1, '', '', ?
        )
    )sql";
    if (sqlite3_prepare_v2(database, insert, -1, &statement, nullptr) != SQLITE_OK) {
        close_database();
        return false;
    }
    sqlite3_bind_text(statement, 1, download_id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, destination_directory, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement, 3, static_cast<sqlite3_int64>(updated_milliseconds));
    const auto succeeded = sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    close_database();
    return succeeded;
}

uint32_t sdm_test_database_user_version(const char *path) {
    sqlite3 *database = nullptr;
    if (path == nullptr || sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nullptr) !=
            SQLITE_OK) {
        if (database != nullptr) {
            sqlite3_close(database);
        }
        return 0;
    }
    sqlite3_stmt *statement = nullptr;
    uint32_t result = 0;
    if (sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nullptr) ==
            SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) {
        result = static_cast<uint32_t>(sqlite3_column_int(statement, 0));
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return result;
}

bool sdm_test_set_database_user_version(const char *path, uint32_t version) {
    sqlite3 *database = nullptr;
    if (path == nullptr || sqlite3_open(path, &database) != SQLITE_OK) {
        if (database != nullptr) {
            sqlite3_close(database);
        }
        return false;
    }
    const auto sql = "PRAGMA user_version = " + std::to_string(version);
    const auto succeeded = sqlite3_exec(
        database,
        sql.c_str(),
        nullptr,
        nullptr,
        nullptr
    ) == SQLITE_OK;
    sqlite3_close(database);
    return succeeded;
}

bool sdm_test_set_download_state(
    const char *path,
    const char *download_id,
    uint32_t state
) {
    sqlite3 *database = nullptr;
    if (path == nullptr || download_id == nullptr ||
        sqlite3_open(path, &database) != SQLITE_OK) {
        if (database != nullptr) {
            sqlite3_close(database);
        }
        return false;
    }
    sqlite3_stmt *statement = nullptr;
    if (sqlite3_prepare_v2(
            database,
            "UPDATE downloads SET state = ? WHERE id = ?",
            -1,
            &statement,
            nullptr
        ) != SQLITE_OK) {
        sqlite3_close(database);
        return false;
    }
    sqlite3_bind_int64(statement, 1, state);
    sqlite3_bind_text(statement, 2, download_id, -1, SQLITE_TRANSIENT);
    const auto succeeded = sqlite3_step(statement) == SQLITE_DONE;
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return succeeded;
}
