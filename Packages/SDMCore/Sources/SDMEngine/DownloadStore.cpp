#include "DownloadStore.h"

#include <sqlite3.h>

#include <filesystem>
#include <stdexcept>
#include <string_view>

namespace {

class Statement final {
public:
    Statement(sqlite3 *database, const char *sql) {
        if (sqlite3_prepare_v2(database, sql, -1, &value, nullptr) != SQLITE_OK) {
            throw std::runtime_error(sqlite3_errmsg(database));
        }
    }

    ~Statement() {
        sqlite3_finalize(value);
    }

    sqlite3_stmt *get() const noexcept { return value; }

private:
    sqlite3_stmt *value = nullptr;
};

void execute(sqlite3 *database, const char *sql) {
    char *message = nullptr;
    if (sqlite3_exec(database, sql, nullptr, nullptr, &message) != SQLITE_OK) {
        const auto description = message == nullptr ? "SQLite error" : message;
        std::string copied(description);
        sqlite3_free(message);
        throw std::runtime_error(copied);
    }
}

void bind_text(sqlite3_stmt *statement, int index, const std::string &value) {
    if (sqlite3_bind_text(
            statement,
            index,
            value.data(),
            static_cast<int>(value.size()),
            SQLITE_TRANSIENT
        ) != SQLITE_OK) {
        throw std::runtime_error("Unable to bind SQLite text");
    }
}

std::string column_text(sqlite3_stmt *statement, int index) {
    const auto *value = sqlite3_column_text(statement, index);
    return value == nullptr ? std::string{} : reinterpret_cast<const char *>(value);
}

void require_done(sqlite3 *database, sqlite3_stmt *statement) {
    if (sqlite3_step(statement) != SQLITE_DONE) {
        throw std::runtime_error(sqlite3_errmsg(database));
    }
}

} // namespace

class sdm::DownloadStore::Impl final {
public:
    explicit Impl(const std::string &path) {
        const auto parent = std::filesystem::path(path).parent_path();
        if (!parent.empty()) {
            std::error_code error;
            std::filesystem::create_directories(parent, error);
            if (error) {
                throw std::runtime_error("Unable to create database directory");
            }
        }
        if (sqlite3_open_v2(
                path.c_str(),
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
                nullptr
            ) != SQLITE_OK) {
            const auto message = database == nullptr
                ? std::string("Unable to open SQLite database")
                : std::string(sqlite3_errmsg(database));
            if (database != nullptr) {
                sqlite3_close(database);
                database = nullptr;
            }
            throw std::runtime_error(message);
        }
        execute(database, "PRAGMA foreign_keys = ON");
        execute(database, "PRAGMA journal_mode = WAL");
        execute(database, "PRAGMA synchronous = NORMAL");

        Statement version(database, "PRAGMA user_version");
        if (sqlite3_step(version.get()) != SQLITE_ROW) {
            throw std::runtime_error("Unable to read database schema version");
        }
        auto schema_version = sqlite3_column_int(version.get(), 0);
        if (schema_version > 3) {
            throw std::runtime_error("Database schema is newer than this engine");
        }
        if (schema_version == 0) {
            migrate_to_version_one();
            schema_version = 1;
        }
        if (schema_version == 1) {
            migrate_to_version_two();
            schema_version = 2;
        }
        if (schema_version == 2) {
            migrate_to_version_three();
        }
    }

    ~Impl() {
        if (database != nullptr) {
            sqlite3_wal_checkpoint_v2(
                database,
                nullptr,
                SQLITE_CHECKPOINT_PASSIVE,
                nullptr,
                nullptr
            );
            sqlite3_close(database);
        }
    }

    void migrate_to_version_one() {
        execute(database, "BEGIN IMMEDIATE");
        try {
            execute(database, R"sql(
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
                )
            )sql");
            execute(database, R"sql(
                CREATE TABLE segments (
                    download_id TEXT NOT NULL REFERENCES downloads(id) ON DELETE CASCADE,
                    ordinal INTEGER NOT NULL,
                    start_byte INTEGER NOT NULL,
                    end_byte INTEGER NOT NULL,
                    next_byte INTEGER NOT NULL,
                    PRIMARY KEY (download_id, ordinal)
                )
            )sql");
            execute(database, "PRAGMA user_version = 1");
            execute(database, "COMMIT");
        } catch (...) {
            execute(database, "ROLLBACK");
            throw;
        }
    }

    void migrate_to_version_two() {
        execute(database, "BEGIN IMMEDIATE");
        try {
            execute(database, R"sql(
                ALTER TABLE downloads
                ADD COLUMN created_milliseconds INTEGER NOT NULL DEFAULT 0
            )sql");
            execute(database, R"sql(
                ALTER TABLE downloads
                ADD COLUMN started_milliseconds INTEGER NOT NULL DEFAULT 0
            )sql");
            execute(database, R"sql(
                ALTER TABLE downloads
                ADD COLUMN last_attempt_milliseconds INTEGER NOT NULL DEFAULT 0
            )sql");
            execute(database, R"sql(
                ALTER TABLE downloads
                ADD COLUMN completed_milliseconds INTEGER NOT NULL DEFAULT 0
            )sql");
            execute(database, R"sql(
                UPDATE downloads
                   SET created_milliseconds = updated_milliseconds,
                       last_attempt_milliseconds = updated_milliseconds,
                       completed_milliseconds = CASE
                           WHEN state = 8 THEN updated_milliseconds
                           ELSE 0
                       END
            )sql");
            execute(database, R"sql(
                CREATE TABLE download_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    download_id TEXT NOT NULL
                        REFERENCES downloads(id) ON DELETE CASCADE,
                    timestamp_milliseconds INTEGER NOT NULL,
                    level INTEGER NOT NULL,
                    code INTEGER NOT NULL,
                    message TEXT NOT NULL
                )
            )sql");
            execute(database, R"sql(
                CREATE INDEX downloads_state_updated_index
                    ON downloads(state, updated_milliseconds DESC)
            )sql");
            execute(database, R"sql(
                CREATE INDEX downloads_updated_index
                    ON downloads(updated_milliseconds DESC)
            )sql");
            execute(database, R"sql(
                CREATE INDEX download_events_download_index
                    ON download_events(download_id, id DESC)
            )sql");
            execute(database, "PRAGMA user_version = 2");
            execute(database, "COMMIT");
        } catch (...) {
            execute(database, "ROLLBACK");
            throw;
        }
    }

    void migrate_to_version_three() {
        execute(database, "BEGIN IMMEDIATE");
        try {
            execute(database, R"sql(
                ALTER TABLE downloads
                DROP COLUMN server_connection_limit
            )sql");
            execute(database, "PRAGMA user_version = 3");
            execute(database, "COMMIT");
        } catch (...) {
            execute(database, "ROLLBACK");
            throw;
        }
    }

    std::vector<sdm::PersistedDownload> load_all() {
        Statement downloads(database, R"sql(
            SELECT id, source_url, destination_directory, requested_filename,
                   connection_limit, bandwidth_limit, conflict_policy, final_url,
                   destination_path, filename, state, content_length_known,
                   content_length, downloaded_bytes, error_code, error_message,
                   temporary_path, accepts_ranges, etag, last_modified,
                   created_milliseconds,
                   started_milliseconds, last_attempt_milliseconds,
                   completed_milliseconds, updated_milliseconds
              FROM downloads
             ORDER BY updated_milliseconds DESC
        )sql");
        std::vector<sdm::PersistedDownload> result;
        while (sqlite3_step(downloads.get()) == SQLITE_ROW) {
            sdm::PersistedDownload value;
            bool has_invalid_state = false;
            value.request.id = column_text(downloads.get(), 0);
            value.request.url = column_text(downloads.get(), 1);
            value.request.destination_directory = column_text(downloads.get(), 2);
            value.request.filename = column_text(downloads.get(), 3);
            value.request.connection_limit = static_cast<std::uint32_t>(
                sqlite3_column_int64(downloads.get(), 4)
            );
            value.request.bandwidth_limit = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 5)
            );
            value.request.conflict_policy = static_cast<std::uint32_t>(
                sqlite3_column_int64(downloads.get(), 6)
            );
            value.snapshot.id = value.request.id;
            value.snapshot.source_url = value.request.url;
            value.snapshot.final_url = column_text(downloads.get(), 7);
            value.snapshot.destination_url = column_text(downloads.get(), 8);
            value.snapshot.filename = column_text(downloads.get(), 9);
            const auto raw_state = sqlite3_column_int64(downloads.get(), 10);
            if (raw_state < static_cast<sqlite3_int64>(sdm::DownloadState::created) ||
                raw_state > static_cast<sqlite3_int64>(sdm::DownloadState::cancelled)) {
                value.snapshot.state = sdm::DownloadState::failed;
                has_invalid_state = true;
            } else {
                value.snapshot.state = static_cast<sdm::DownloadState>(raw_state);
            }
            value.snapshot.content_length_known = sqlite3_column_int(downloads.get(), 11) != 0;
            value.snapshot.content_length = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 12)
            );
            value.snapshot.downloaded_bytes = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 13)
            );
            value.snapshot.error_code = static_cast<sdm::Result>(
                sqlite3_column_int64(downloads.get(), 14)
            );
            value.snapshot.error_message = column_text(downloads.get(), 15);
            value.temporary_path = column_text(downloads.get(), 16);
            value.accepts_ranges = sqlite3_column_int(downloads.get(), 17) != 0;
            value.etag = column_text(downloads.get(), 18);
            value.last_modified = column_text(downloads.get(), 19);
            value.snapshot.created_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 20)
            );
            value.snapshot.started_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 21)
            );
            value.snapshot.last_attempt_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 22)
            );
            value.snapshot.completed_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 23)
            );
            value.snapshot.updated_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 24)
            );
            if (has_invalid_state) {
                value.snapshot.error_code = sdm::Result::persistence_error;
                value.snapshot.error_message = "Persisted download state was invalid";
            }
            load_segments(value);
            result.push_back(std::move(value));
        }
        return result;
    }

    std::vector<sdm::DiagnosticEvent> load_events(const std::string &download_id) {
        Statement statement(database, R"sql(
            SELECT id, timestamp_milliseconds, level, code, message
              FROM (
                    SELECT id, timestamp_milliseconds, level, code, message
                      FROM download_events
                     WHERE download_id = ?
                     ORDER BY id DESC
                     LIMIT 500
                   )
             ORDER BY id
        )sql");
        bind_text(statement.get(), 1, download_id);
        std::vector<sdm::DiagnosticEvent> result;
        while (sqlite3_step(statement.get()) == SQLITE_ROW) {
            result.push_back(sdm::DiagnosticEvent{
                .id = static_cast<std::uint64_t>(sqlite3_column_int64(statement.get(), 0)),
                .download_id = download_id,
                .timestamp_milliseconds = static_cast<std::uint64_t>(
                    sqlite3_column_int64(statement.get(), 1)
                ),
                .level = static_cast<sdm::DiagnosticLevel>(
                    sqlite3_column_int64(statement.get(), 2)
                ),
                .code = static_cast<std::uint32_t>(
                    sqlite3_column_int64(statement.get(), 3)
                ),
                .message = column_text(statement.get(), 4),
            });
        }
        return result;
    }

    sdm::DiagnosticEvent append_event(
        const std::string &download_id,
        std::uint64_t timestamp_milliseconds,
        sdm::DiagnosticLevel level,
        std::uint32_t code,
        const std::string &message
    ) {
        Statement statement(database, R"sql(
            INSERT INTO download_events(
                download_id, timestamp_milliseconds, level, code, message
            ) VALUES (?, ?, ?, ?, ?)
        )sql");
        bind_text(statement.get(), 1, download_id);
        sqlite3_bind_int64(
            statement.get(),
            2,
            static_cast<sqlite3_int64>(timestamp_milliseconds)
        );
        sqlite3_bind_int64(statement.get(), 3, static_cast<std::uint32_t>(level));
        sqlite3_bind_int64(statement.get(), 4, code);
        bind_text(statement.get(), 5, message);
        require_done(database, statement.get());
        const auto event_id = static_cast<std::uint64_t>(sqlite3_last_insert_rowid(database));

        Statement prune(database, R"sql(
            DELETE FROM download_events
             WHERE download_id = ?
               AND id NOT IN (
                    SELECT id
                      FROM download_events
                     WHERE download_id = ?
                     ORDER BY id DESC
                     LIMIT 500
               )
        )sql");
        bind_text(prune.get(), 1, download_id);
        bind_text(prune.get(), 2, download_id);
        require_done(database, prune.get());

        return sdm::DiagnosticEvent{
            .id = event_id,
            .download_id = download_id,
            .timestamp_milliseconds = timestamp_milliseconds,
            .level = level,
            .code = code,
            .message = message,
        };
    }

    void load_segments(sdm::PersistedDownload &download) {
        Statement segments(database, R"sql(
            SELECT ordinal, start_byte, end_byte, next_byte
              FROM segments
             WHERE download_id = ?
             ORDER BY ordinal
        )sql");
        bind_text(segments.get(), 1, download.request.id);
        while (sqlite3_step(segments.get()) == SQLITE_ROW) {
            download.snapshot.segments.push_back(sdm::Segment{
                .ordinal = static_cast<std::uint32_t>(sqlite3_column_int64(segments.get(), 0)),
                .start = static_cast<std::uint64_t>(sqlite3_column_int64(segments.get(), 1)),
                .end = static_cast<std::uint64_t>(sqlite3_column_int64(segments.get(), 2)),
                .next = static_cast<std::uint64_t>(sqlite3_column_int64(segments.get(), 3)),
            });
        }
        download.snapshot.segment_count = static_cast<std::uint32_t>(
            download.snapshot.segments.size()
        );
    }

    void save(const sdm::PersistedDownload &value) {
        execute(database, "BEGIN IMMEDIATE");
        try {
            Statement statement(database, R"sql(
                INSERT INTO downloads (
                    id, source_url, destination_directory, requested_filename,
                    connection_limit, bandwidth_limit, conflict_policy, final_url,
                    destination_path, filename, state, content_length_known,
                    content_length, downloaded_bytes, error_code, error_message,
                    temporary_path, accepts_ranges, etag, last_modified,
                    created_milliseconds,
                    started_milliseconds, last_attempt_milliseconds,
                    completed_milliseconds, updated_milliseconds
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?
                )
                ON CONFLICT(id) DO UPDATE SET
                    source_url = excluded.source_url,
                    destination_directory = excluded.destination_directory,
                    requested_filename = excluded.requested_filename,
                    connection_limit = excluded.connection_limit,
                    bandwidth_limit = excluded.bandwidth_limit,
                    conflict_policy = excluded.conflict_policy,
                    final_url = excluded.final_url,
                    destination_path = excluded.destination_path,
                    filename = excluded.filename,
                    state = excluded.state,
                    content_length_known = excluded.content_length_known,
                    content_length = excluded.content_length,
                    downloaded_bytes = excluded.downloaded_bytes,
                    error_code = excluded.error_code,
                    error_message = excluded.error_message,
                    temporary_path = excluded.temporary_path,
                    accepts_ranges = excluded.accepts_ranges,
                    etag = excluded.etag,
                    last_modified = excluded.last_modified,
                    created_milliseconds = excluded.created_milliseconds,
                    started_milliseconds = excluded.started_milliseconds,
                    last_attempt_milliseconds = excluded.last_attempt_milliseconds,
                    completed_milliseconds = excluded.completed_milliseconds,
                    updated_milliseconds = excluded.updated_milliseconds
            )sql");
            int index = 1;
            bind_text(statement.get(), index++, value.request.id);
            bind_text(statement.get(), index++, value.request.url);
            bind_text(statement.get(), index++, value.request.destination_directory);
            bind_text(statement.get(), index++, value.request.filename);
            sqlite3_bind_int64(statement.get(), index++, value.request.connection_limit);
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.request.bandwidth_limit));
            sqlite3_bind_int64(statement.get(), index++, value.request.conflict_policy);
            bind_text(statement.get(), index++, value.snapshot.final_url);
            bind_text(statement.get(), index++, value.snapshot.destination_url);
            bind_text(statement.get(), index++, value.snapshot.filename);
            sqlite3_bind_int64(statement.get(), index++, static_cast<std::uint32_t>(value.snapshot.state));
            sqlite3_bind_int(statement.get(), index++, value.snapshot.content_length_known ? 1 : 0);
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.content_length));
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.downloaded_bytes));
            sqlite3_bind_int64(statement.get(), index++, static_cast<std::uint32_t>(value.snapshot.error_code));
            bind_text(statement.get(), index++, value.snapshot.error_message);
            bind_text(statement.get(), index++, value.temporary_path);
            sqlite3_bind_int(statement.get(), index++, value.accepts_ranges ? 1 : 0);
            bind_text(statement.get(), index++, value.etag);
            bind_text(statement.get(), index++, value.last_modified);
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.created_milliseconds));
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.started_milliseconds));
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.last_attempt_milliseconds));
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.completed_milliseconds));
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.updated_milliseconds));
            require_done(database, statement.get());

            Statement remove_segments(
                database,
                "DELETE FROM segments WHERE download_id = ?"
            );
            bind_text(remove_segments.get(), 1, value.request.id);
            require_done(database, remove_segments.get());

            Statement segment(database, R"sql(
                INSERT INTO segments(download_id, ordinal, start_byte, end_byte, next_byte)
                VALUES (?, ?, ?, ?, ?)
            )sql");
            for (const auto &item : value.snapshot.segments) {
                sqlite3_reset(segment.get());
                sqlite3_clear_bindings(segment.get());
                bind_text(segment.get(), 1, value.request.id);
                sqlite3_bind_int64(segment.get(), 2, item.ordinal);
                sqlite3_bind_int64(segment.get(), 3, static_cast<sqlite3_int64>(item.start));
                sqlite3_bind_int64(segment.get(), 4, static_cast<sqlite3_int64>(item.end));
                sqlite3_bind_int64(segment.get(), 5, static_cast<sqlite3_int64>(item.next));
                require_done(database, segment.get());
            }
            execute(database, "COMMIT");
        } catch (...) {
            execute(database, "ROLLBACK");
            throw;
        }
    }

    void remove(const std::string &id) {
        Statement statement(database, "DELETE FROM downloads WHERE id = ?");
        bind_text(statement.get(), 1, id);
        require_done(database, statement.get());
    }

    sqlite3 *database = nullptr;
};

sdm::DownloadStore::DownloadStore(const std::string &path)
    : impl_(std::make_unique<Impl>(path)) {}

sdm::DownloadStore::~DownloadStore() = default;

std::vector<sdm::PersistedDownload> sdm::DownloadStore::load_all() {
    return impl_->load_all();
}

std::vector<sdm::DiagnosticEvent> sdm::DownloadStore::load_events(
    const std::string &download_id
) {
    return impl_->load_events(download_id);
}

sdm::DiagnosticEvent sdm::DownloadStore::append_event(
    const std::string &download_id,
    std::uint64_t timestamp_milliseconds,
    DiagnosticLevel level,
    std::uint32_t code,
    const std::string &message
) {
    return impl_->append_event(
        download_id,
        timestamp_milliseconds,
        level,
        code,
        message
    );
}

void sdm::DownloadStore::save(const PersistedDownload &download) {
    impl_->save(download);
}

void sdm::DownloadStore::remove(const std::string &id) {
    impl_->remove(id);
}
