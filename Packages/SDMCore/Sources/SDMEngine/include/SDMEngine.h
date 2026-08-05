#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "SDMEngineDomain.h"

namespace sdm {

class PersistenceError final : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

inline constexpr std::uint32_t engine_abi_version = 3;

enum class EventKind : std::uint32_t {
    command_result = 0,
    snapshot_changed = 1,
    removed = 2,
    engine_stopped = 3,
    engine_ready = 4,
};

enum class DiagnosticLevel : std::uint32_t {
    info = 0,
    warning = 1,
    error = 2,
};

struct EngineConfig final {
    std::string database_path;
    std::string temporary_directory;
    std::string certificate_authority_bundle;
    std::uint32_t maximum_active_downloads = 2;
    std::uint32_t maximum_connections_per_download = 16;
};

struct DownloadRequest final {
    std::string id;
    std::string url;
    std::string destination_directory;
    std::string filename;
    std::uint32_t connection_limit = 8;
    std::uint64_t bandwidth_limit = 0;
    std::uint32_t conflict_policy = 0;
};

struct DownloadSnapshot final {
    std::string id;
    std::string source_url;
    std::string final_url;
    std::string destination_url;
    std::string filename;
    DownloadState state = DownloadState::created;
    bool content_length_known = false;
    std::uint64_t content_length = 0;
    std::uint64_t downloaded_bytes = 0;
    std::uint64_t bytes_per_second = 0;
    std::uint64_t estimated_seconds_remaining = 0;
    std::uint32_t segment_count = 0;
    std::vector<Segment> segments;
    Result error_code = Result::ok;
    std::string error_message;
    std::uint64_t created_milliseconds = 0;
    std::uint64_t started_milliseconds = 0;
    std::uint64_t last_attempt_milliseconds = 0;
    std::uint64_t completed_milliseconds = 0;
    std::uint64_t updated_milliseconds = 0;
};

struct DiagnosticEvent final {
    std::uint64_t id = 0;
    std::string download_id;
    std::uint64_t timestamp_milliseconds = 0;
    DiagnosticLevel level = DiagnosticLevel::info;
    std::uint32_t code = 0;
    std::string message;
};

struct Event final {
    std::uint64_t sequence = 0;
    std::uint64_t command_id = 0;
    std::string download_id;
    EventKind kind = EventKind::snapshot_changed;
    Result result = Result::ok;
};

class Engine final {
public:
    explicit Engine(EngineConfig config);
    ~Engine();

    Engine(const Engine &) = delete;
    Engine &operator=(const Engine &) = delete;
    Engine(Engine &&) = delete;
    Engine &operator=(Engine &&) = delete;

    [[nodiscard]] static std::string_view version() noexcept;

    [[nodiscard]] Result enqueue(
        DownloadRequest request,
        std::uint64_t &command_id
    );
    [[nodiscard]] Result submit(
        std::string id,
        CommandKind command,
        std::uint64_t &command_id
    );
    [[nodiscard]] std::vector<Event> poll_events(std::size_t maximum_count);
    [[nodiscard]] std::optional<DownloadSnapshot> snapshot(
        std::string_view id
    ) const;
    [[nodiscard]] std::vector<DownloadSnapshot> snapshots() const;
    [[nodiscard]] std::vector<DiagnosticEvent> diagnostic_events(
        std::string_view id
    ) const;

    void shutdown() noexcept;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace sdm
