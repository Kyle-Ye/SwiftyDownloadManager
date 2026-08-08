#pragma once

#include <cstdint>
#include <vector>

namespace sdm {

enum class Result : std::uint32_t {
    ok = 0,
    invalid_argument = 1,
    not_found = 2,
    invalid_state = 3,
    io_error = 4,
    network_error = 5,
    protocol_error = 6,
    persistence_error = 7,
    shutting_down = 8,
    internal_error = 9,
};

enum class DownloadState : std::uint32_t {
    created = 0,
    probing = 1,
    queued = 2,
    downloading = 3,
    pausing = 4,
    paused = 5,
    retrying = 6,
    finalizing = 7,
    completed = 8,
    failed = 9,
    cancelled = 10,
};

enum class CommandKind : std::uint32_t {
    enqueue = 0,
    pause = 1,
    resume = 2,
    cancel = 3,
    retry = 4,
    remove = 5,
};

struct Segment final {
    std::uint32_t ordinal = 0;
    std::uint64_t start = 0;
    std::uint64_t end = 0;
    std::uint64_t next = 0;
};

[[nodiscard]] bool can_transition(
    DownloadState from,
    DownloadState to
) noexcept;

[[nodiscard]] Result validate_command(
    DownloadState state,
    CommandKind command
) noexcept;

[[nodiscard]] bool is_retryable_curl_error(
    std::uint32_t error_code
) noexcept;

[[nodiscard]] std::vector<Segment> plan_segments(
    std::uint64_t content_length,
    std::uint32_t requested_connections,
    std::uint32_t maximum_connections
);

} // namespace sdm
