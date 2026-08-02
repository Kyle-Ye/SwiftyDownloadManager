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
        const auto schema_version = sqlite3_column_int(version.get(), 0);
        if (schema_version > 1) {
            throw std::runtime_error("Database schema is newer than this engine");
        }
        if (schema_version == 0) {
            migrate_to_version_one();
        }
    }

    ~Impl() {
        if (database != nullptr) {
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

    std::vector<sdm::PersistedDownload> load_all() {
        Statement downloads(database, R"sql(
            SELECT id, source_url, destination_directory, requested_filename,
                   connection_limit, bandwidth_limit, conflict_policy, final_url,
                   destination_path, filename, state, content_length_known,
                   content_length, downloaded_bytes, error_code, error_message,
                   temporary_path, accepts_ranges, server_connection_limit,
                   etag, last_modified, updated_milliseconds
              FROM downloads
             ORDER BY updated_milliseconds
        )sql");
        std::vector<sdm::PersistedDownload> result;
        while (sqlite3_step(downloads.get()) == SQLITE_ROW) {
            sdm::PersistedDownload value;
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
            value.snapshot.state = static_cast<sdm::DownloadState>(
                sqlite3_column_int64(downloads.get(), 10)
            );
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
            value.server_connection_limit = static_cast<std::uint32_t>(
                sqlite3_column_int64(downloads.get(), 18)
            );
            value.etag = column_text(downloads.get(), 19);
            value.last_modified = column_text(downloads.get(), 20);
            value.snapshot.updated_milliseconds = static_cast<std::uint64_t>(
                sqlite3_column_int64(downloads.get(), 21)
            );
            load_segments(value);
            result.push_back(std::move(value));
        }
        return result;
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
                INSERT OR REPLACE INTO downloads VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
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
            sqlite3_bind_int64(statement.get(), index++, value.server_connection_limit);
            bind_text(statement.get(), index++, value.etag);
            bind_text(statement.get(), index++, value.last_modified);
            sqlite3_bind_int64(statement.get(), index++, static_cast<sqlite3_int64>(value.snapshot.updated_milliseconds));
            require_done(database, statement.get());

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

void sdm::DownloadStore::save(const PersistedDownload &download) {
    impl_->save(download);
}

void sdm::DownloadStore::remove(const std::string &id) {
    impl_->remove(id);
}
