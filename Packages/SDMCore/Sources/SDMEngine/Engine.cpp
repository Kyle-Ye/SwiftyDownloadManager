#include "SDMEngine.h"
#include "DownloadStore.h"
#include "SDMFileFinalizer.h"

#include <curl/curl.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <condition_variable>
#include <cctype>
#include <deque>
#include <fcntl.h>
#include <filesystem>
#include <functional>
#include <limits>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <unistd.h>
#include <utility>

static_assert(sdm::engine_abi_version > 0);

std::string_view sdm::Engine::version() noexcept {
    return "0.5.0";
}

bool sdm::is_retryable_curl_error(std::uint32_t error_code) noexcept {
    switch (static_cast<CURLcode>(error_code)) {
    case CURLE_SSL_ENGINE_NOTFOUND:
    case CURLE_SSL_ENGINE_SETFAILED:
    case CURLE_SSL_CERTPROBLEM:
    case CURLE_SSL_CIPHER:
    case CURLE_PEER_FAILED_VERIFICATION:
    case CURLE_SSL_ENGINE_INITFAILED:
    case CURLE_SSL_CACERT_BADFILE:
    case CURLE_SSL_CRL_BADFILE:
    case CURLE_SSL_ISSUER_ERROR:
    case CURLE_SSL_PINNEDPUBKEYNOTMATCH:
    case CURLE_SSL_INVALIDCERTSTATUS:
    case CURLE_SSL_CLIENTCERT:
        return false;
    default:
        return true;
    }
}

namespace {

using Clock = std::chrono::steady_clock;

constexpr std::uint64_t minimum_adaptive_segment_length = 1024 * 1024;
constexpr std::size_t maximum_segments_per_connection = 8;

std::uint64_t current_milliseconds() noexcept {
    const auto now = std::chrono::system_clock::now().time_since_epoch();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(now).count()
    );
}

std::string trim(std::string value) {
    const auto is_space = [](unsigned char character) {
        return std::isspace(character) != 0;
    };
    value.erase(value.begin(), std::find_if_not(value.begin(), value.end(), is_space));
    value.erase(std::find_if_not(value.rbegin(), value.rend(), is_space).base(), value.end());
    return value;
}

std::string lowercase(std::string value) {
    std::ranges::transform(value, value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

std::string sanitize_filename(std::string value) {
    value = std::filesystem::path(value).filename().string();
    for (auto &character : value) {
        if (character == '/' || character == '\\' || character == ':' ||
            static_cast<unsigned char>(character) < 0x20) {
            character = '_';
        }
    }
    value = trim(std::move(value));
    if (value.empty() || value == "." || value == "..") {
        return "download.bin";
    }
    return value;
}

std::string inferred_filename(const sdm::DownloadRequest &request) {
    if (!request.filename.empty()) {
        return sanitize_filename(request.filename);
    }

    const auto query = request.url.find_first_of("?#");
    const auto path = request.url.substr(0, query);
    const auto slash = path.find_last_of('/');
    if (slash != std::string::npos && slash + 1 < path.size()) {
        return sanitize_filename(path.substr(slash + 1));
    }
    return "download.bin";
}

std::optional<std::uint64_t> parse_unsigned(std::string_view text) {
    std::uint64_t result = 0;
    const auto conversion = std::from_chars(
        text.data(),
        text.data() + text.size(),
        result
    );
    if (conversion.ec != std::errc{} || conversion.ptr != text.data() + text.size()) {
        return std::nullopt;
    }
    return result;
}

struct ContentRange final {
    std::uint64_t start = 0;
    std::uint64_t end = 0;
    std::optional<std::uint64_t> total;
};

std::optional<ContentRange> parse_content_range(std::string value) {
    value = trim(std::move(value));
    if (value.rfind("bytes ", 0) != 0) {
        return std::nullopt;
    }
    const auto dash = value.find('-', 6);
    const auto slash = value.find('/', dash == std::string::npos ? 6 : dash + 1);
    if (dash == std::string::npos || slash == std::string::npos) {
        return std::nullopt;
    }
    const auto start = parse_unsigned(std::string_view(value).substr(6, dash - 6));
    const auto end = parse_unsigned(
        std::string_view(value).substr(dash + 1, slash - dash - 1)
    );
    const auto total_text = std::string_view(value).substr(slash + 1);
    std::optional<std::uint64_t> total;
    if (total_text != "*") {
        total = parse_unsigned(total_text);
        if (!total) {
            return std::nullopt;
        }
    }
    if (!start || !end || *end < *start || (total && *end >= *total)) {
        return std::nullopt;
    }
    return ContentRange{.start = *start, .end = *end, .total = total};
}

std::string extension_for_content_type(std::string value) {
    const auto separator = value.find(';');
    if (separator != std::string::npos) {
        value.erase(separator);
    }
    value = lowercase(trim(std::move(value)));
    if (value == "text/html") {
        return ".html";
    }
    return {};
}

std::string infer_filename_extension(std::string filename, std::string_view content_type) {
    if (!std::filesystem::path(filename).extension().empty()) {
        return filename;
    }
    const auto extension = extension_for_content_type(std::string(content_type));
    if (!extension.empty()) {
        filename += extension;
    }
    return sanitize_filename(std::move(filename));
}

std::string content_disposition_filename(std::string_view value) {
    auto lower = lowercase(std::string(value));
    const auto marker = lower.find("filename=");
    if (marker == std::string::npos) {
        return {};
    }
    auto candidate = trim(std::string(value.substr(marker + 9)));
    const auto separator = candidate.find(';');
    if (separator != std::string::npos) {
        candidate.erase(separator);
    }
    candidate = trim(std::move(candidate));
    if (candidate.size() >= 2 && candidate.front() == '"' && candidate.back() == '"') {
        candidate = candidate.substr(1, candidate.size() - 2);
    }
    return sanitize_filename(std::move(candidate));
}

void ensure_curl_runtime() {
    static std::once_flag once;
    static CURLcode result = CURLE_OK;
    std::call_once(once, [] { result = curl_global_init(CURL_GLOBAL_DEFAULT); });
    if (result != CURLE_OK) {
        throw std::runtime_error("curl_global_init failed");
    }
}

} // namespace

class sdm::Engine::Impl final {
public:
    explicit Impl(EngineConfig engine_config)
        : config(std::move(engine_config)) {
        ensure_curl_runtime();
        multi = curl_multi_init();
        if (multi == nullptr) {
            throw std::runtime_error("curl_multi_init failed");
        }
        try {
            store = std::make_unique<DownloadStore>(config.database_path);
            restore_tasks();
        } catch (const std::exception &error) {
            curl_multi_cleanup(multi);
            multi = nullptr;
            throw PersistenceError(error.what());
        }
        worker = std::jthread([this](std::stop_token stop_token) {
            run(stop_token);
        });
    }

    ~Impl() {
        shutdown();
        if (multi != nullptr) {
            curl_multi_cleanup(multi);
        }
    }

    struct Command final {
        std::uint64_t command_id = 0;
        CommandKind kind = CommandKind::enqueue;
        std::string id;
        std::optional<DownloadRequest> request;
    };

    enum class TransferKind {
        probe,
        probe_range,
        body,
    };

    struct Task final {
        DownloadRequest request;
        DownloadSnapshot snapshot;
        std::filesystem::path temporary_path;
        std::filesystem::path destination_path;
        int file_descriptor = -1;
        std::unordered_set<CURL *> active_handles;
        bool accepts_ranges = false;
        std::vector<Segment> segments;
        std::string etag;
        std::string last_modified;
        std::uint64_t write_offset = 0;
        std::uint64_t speed_baseline_bytes = 0;
        std::uint32_t retry_attempt = 0;
        std::optional<Clock::time_point> retry_at;
        std::optional<DownloadState> last_published_state;
        Result last_published_error_code = Result::ok;
        std::string last_published_error_message;
        Clock::time_point transfer_started = Clock::now();
        Clock::time_point last_published = Clock::now();
        Clock::time_point last_checkpoint = Clock::now();
    };

    struct Transfer final {
        Impl *owner = nullptr;
        Task *task = nullptr;
        CURL *easy = nullptr;
        curl_slist *request_headers = nullptr;
        TransferKind kind = TransferKind::probe;
        std::string error_buffer = std::string(CURL_ERROR_SIZE, '\0');
        std::string status_line;
        std::unordered_map<std::string, std::string> headers;
        std::uint32_t segment_ordinal = std::numeric_limits<std::uint32_t>::max();
        std::uint64_t start_offset = 0;
        std::uint64_t end_offset = 0;
        std::uint64_t expected_bytes = 0;
        std::uint64_t received_bytes = 0;
        std::optional<std::uint64_t> content_length;
        std::string effective_url;
        long response_status = 0;
        bool expects_partial_response = false;
        bool response_validated = false;
        bool protocol_failed = false;
        bool write_failed = false;
    };

    Result enqueue(DownloadRequest request, std::uint64_t &command_id) {
        if (request.id.empty() || request.url.empty() ||
            request.destination_directory.empty() || request.connection_limit == 0 ||
            request.connection_limit > config.maximum_connections_per_download) {
            return Result::invalid_argument;
        }

        std::lock_guard lock(mutex);
        if (stopping) {
            return Result::shutting_down;
        }
        if (snapshots_by_id.contains(request.id) || pending_ids.contains(request.id)) {
            return Result::invalid_argument;
        }

        command_id = next_command_id++;
        pending_ids.insert(request.id);
        commands.push_back(Command{
            .command_id = command_id,
            .kind = CommandKind::enqueue,
            .id = request.id,
            .request = std::move(request),
        });
        wake();
        return Result::ok;
    }

    Result submit(std::string id, CommandKind command, std::uint64_t &command_id) {
        if (id.empty() || command == CommandKind::enqueue) {
            return Result::invalid_argument;
        }

        std::lock_guard lock(mutex);
        if (stopping) {
            return Result::shutting_down;
        }
        const auto iterator = snapshots_by_id.find(id);
        if (iterator == snapshots_by_id.end()) {
            return Result::not_found;
        }
        const auto validation = validate_command(iterator->second.state, command);
        if (validation != Result::ok) {
            return validation;
        }

        command_id = next_command_id++;
        commands.push_back(Command{
            .command_id = command_id,
            .kind = command,
            .id = std::move(id),
            .request = std::nullopt,
        });
        wake();
        return Result::ok;
    }

    std::vector<Event> poll_events(std::size_t maximum_count) {
        std::lock_guard lock(mutex);
        const auto count = std::min(maximum_count, events.size());
        std::vector<Event> result;
        result.reserve(count);
        for (std::size_t index = 0; index < count; ++index) {
            result.push_back(std::move(events.front()));
            events.pop_front();
        }
        return result;
    }

    std::optional<DownloadSnapshot> snapshot(std::string_view id) const {
        std::lock_guard lock(mutex);
        const auto iterator = snapshots_by_id.find(std::string(id));
        if (iterator == snapshots_by_id.end()) {
            return std::nullopt;
        }
        return iterator->second;
    }

    std::vector<DownloadSnapshot> snapshots() const {
        std::lock_guard lock(mutex);
        std::vector<DownloadSnapshot> result;
        result.reserve(snapshots_by_id.size());
        for (const auto &[id, snapshot] : snapshots_by_id) {
            (void)id;
            result.push_back(snapshot);
        }
        std::ranges::sort(
            result,
            std::greater{},
            &DownloadSnapshot::updated_milliseconds
        );
        return result;
    }

    std::vector<DiagnosticEvent> diagnostic_events(std::string_view id) const {
        std::lock_guard lock(mutex);
        const auto iterator = diagnostic_events_by_id.find(std::string(id));
        if (iterator == diagnostic_events_by_id.end()) {
            return {};
        }
        return iterator->second;
    }

    void shutdown() noexcept {
        {
            std::lock_guard lock(mutex);
            if (stopping) {
                return;
            }
            stopping = true;
        }
        worker.request_stop();
        wake();
        if (worker.joinable()) {
            worker.join();
        }
    }

private:
    static size_t header_callback(
        char *data,
        size_t size,
        size_t count,
        void *context
    ) noexcept {
        const auto byte_count = size * count;
        auto &transfer = *static_cast<Transfer *>(context);
        try {
            std::string line(data, byte_count);
            if (line.rfind("HTTP/", 0) == 0) {
                transfer.headers.clear();
                transfer.status_line = trim(line);
                const auto first_space = line.find(' ');
                if (first_space != std::string::npos) {
                    const auto second_space = line.find(' ', first_space + 1);
                    const auto status_text = std::string_view(line).substr(
                        first_space + 1,
                        second_space - first_space - 1
                    );
                    if (const auto status = parse_unsigned(status_text)) {
                        transfer.response_status = static_cast<long>(*status);
                    }
                }
            } else if (const auto colon = line.find(':'); colon != std::string::npos) {
                auto name = lowercase(trim(line.substr(0, colon)));
                auto value = trim(line.substr(colon + 1));
                transfer.headers.insert_or_assign(std::move(name), std::move(value));
            }
            return byte_count;
        } catch (...) {
            return 0;
        }
    }

    static size_t write_callback(
        char *data,
        size_t size,
        size_t count,
        void *context
    ) noexcept {
        const auto byte_count = size * count;
        auto &transfer = *static_cast<Transfer *>(context);
        if (transfer.kind != TransferKind::body) {
            return byte_count;
        }
        if (transfer.task == nullptr || transfer.task->file_descriptor < 0) {
            transfer.write_failed = true;
            return 0;
        }

        if (transfer.expects_partial_response && !transfer.response_validated) {
            const auto iterator = transfer.headers.find("content-range");
            const auto content_range = iterator == transfer.headers.end()
                ? std::nullopt
                : parse_content_range(iterator->second);
            if (transfer.response_status != 206 || !content_range ||
                content_range->start != transfer.start_offset ||
                content_range->end != transfer.end_offset ||
                !content_range->total ||
                transfer.task == nullptr ||
                !transfer.task->snapshot.content_length_known ||
                *content_range->total != transfer.task->snapshot.content_length) {
                transfer.protocol_failed = true;
                return 0;
            }
            transfer.response_validated = true;
        }
        if (!transfer.expects_partial_response &&
            (transfer.response_status < 200 || transfer.response_status >= 300)) {
            transfer.write_failed = true;
            return 0;
        }

        std::size_t written = 0;
        while (written < byte_count) {
            const auto result = ::pwrite(
                transfer.task->file_descriptor,
                data + written,
                byte_count - written,
                static_cast<off_t>(
                    transfer.start_offset + transfer.received_bytes + written
                )
            );
            if (result <= 0) {
                transfer.write_failed = true;
                return 0;
            }
            written += static_cast<std::size_t>(result);
        }
        transfer.received_bytes += byte_count;
        if (transfer.segment_ordinal < transfer.task->segments.size()) {
            transfer.task->segments[transfer.segment_ordinal].next =
                transfer.start_offset + transfer.received_bytes;
        } else {
            transfer.task->write_offset = transfer.start_offset + transfer.received_bytes;
        }
        return byte_count;
    }

    void wake() noexcept {
        condition.notify_one();
        if (multi != nullptr) {
            (void)curl_multi_wakeup(multi);
        }
    }

    void run(std::stop_token stop_token) noexcept {
        {
            std::lock_guard lock(mutex);
            emit_locked(Event{
                .kind = EventKind::engine_ready,
                .result = Result::ok,
            });
        }
        while (!stop_token.stop_requested()) {
            process_commands();
            schedule_queued_tasks();

            int running_handles = 0;
            CURLMcode multi_result;
            do {
                multi_result = curl_multi_perform(multi, &running_handles);
            } while (multi_result == CURLM_CALL_MULTI_PERFORM);
            if (multi_result != CURLM_OK) {
                fail_active_transfers(Result::network_error, curl_multi_strerror(multi_result));
            }
            process_completed_transfers();
            publish_progress();

            if (stop_token.stop_requested()) {
                break;
            }
            if (running_handles > 0) {
                int descriptor_count = 0;
                (void)curl_multi_poll(multi, nullptr, 0, 25, &descriptor_count);
            } else {
                std::unique_lock lock(mutex);
                condition.wait_for(lock, std::chrono::milliseconds(25), [this] {
                    return !commands.empty() || stopping;
                });
            }
        }

        stop_all_transfers();
        for (auto &[id, task] : tasks) {
            (void)id;
            update_snapshot_segments(*task);
            task->snapshot.downloaded_bytes = downloaded_bytes(*task);
            persist_task(*task);
            close_file(*task);
        }
        std::lock_guard lock(mutex);
        emit_locked(Event{
            .kind = EventKind::engine_stopped,
            .result = Result::ok,
        });
    }

    void process_commands() {
        while (true) {
            Command command;
            {
                std::lock_guard lock(mutex);
                if (commands.empty()) {
                    return;
                }
                command = std::move(commands.front());
                commands.pop_front();
            }
            process_command(std::move(command));
        }
    }

    void restore_tasks() {
        for (auto &stored : store->load_all()) {
                bool refresh_timestamp = false;
                std::optional<std::string> recovery_message;
                auto task = std::make_unique<Task>();
                task->request = std::move(stored.request);
                task->snapshot = std::move(stored.snapshot);
                task->temporary_path = std::move(stored.temporary_path);
                task->destination_path = task->snapshot.destination_url;
                task->accepts_ranges = stored.accepts_ranges;
                task->segments = task->snapshot.segments;
                task->etag = std::move(stored.etag);
                task->last_modified = std::move(stored.last_modified);
                task->last_published_state = task->snapshot.state;
                task->last_published_error_code = task->snapshot.error_code;
                task->last_published_error_message = task->snapshot.error_message;
                if (task->segments.empty()) {
                    task->write_offset = task->snapshot.downloaded_bytes;
                }

                switch (task->snapshot.state) {
                case DownloadState::probing:
                case DownloadState::downloading:
                case DownloadState::pausing:
                case DownloadState::retrying:
                case DownloadState::finalizing:
                    task->snapshot.state = DownloadState::paused;
                    refresh_timestamp = true;
                    break;
                default:
                    break;
                }

                std::error_code error;
                if (task->snapshot.state == DownloadState::completed &&
                    (task->destination_path.empty() ||
                     !std::filesystem::exists(task->destination_path, error))) {
                    task->snapshot.state = DownloadState::failed;
                    task->snapshot.error_code = Result::io_error;
                    task->snapshot.error_message = "Finalized file no longer exists";
                    refresh_timestamp = true;
                } else if (task->snapshot.state == DownloadState::completed) {
                    error.clear();
                    const auto final_size = std::filesystem::file_size(
                        task->destination_path,
                        error
                    );
                    if (!error) {
                        task->snapshot.downloaded_bytes = final_size;
                    }
                    if (task->segments.empty()) {
                        task->write_offset = task->snapshot.downloaded_bytes;
                    } else {
                        for (auto &segment : task->segments) {
                            segment.next = segment.end + 1;
                        }
                    }
                } else if (task->snapshot.downloaded_bytes > 0 &&
                           (task->temporary_path.empty() ||
                            !std::filesystem::exists(task->temporary_path, error))) {
                    task->write_offset = 0;
                    reset_segments(*task);
                    task->snapshot.downloaded_bytes = 0;
                    refresh_timestamp = true;
                    recovery_message =
                        "Partial download file was missing; resumable progress was reset.";
                }

                auto id = task->request.id;
                tasks.insert_or_assign(id, std::move(task));
                task_order.push_back(id);
                {
                    std::lock_guard lock(mutex);
                    diagnostic_events_by_id.insert_or_assign(
                        id,
                        store->load_events(id)
                    );
                }
                publish_snapshot(*tasks.at(id), refresh_timestamp);
                if (recovery_message) {
                    record_diagnostic(
                        *tasks.at(id),
                        DiagnosticLevel::warning,
                        static_cast<std::uint32_t>(Result::io_error),
                        *recovery_message
                    );
                }
                if (diagnostic_events(id).empty()) {
                    record_diagnostic(
                        *tasks.at(id),
                        DiagnosticLevel::info,
                        0,
                        "Loaded persisted download history."
                    );
                }
        }
    }

    void process_command(Command command) {
        Result result = Result::ok;
        if (command.kind == CommandKind::enqueue && command.request) {
            auto request = std::move(*command.request);
            const auto now = current_milliseconds();
            auto snapshot = DownloadSnapshot{
                .id = request.id,
                .source_url = request.url,
                .filename = inferred_filename(request),
                .state = DownloadState::queued,
                .created_milliseconds = now,
                .updated_milliseconds = now,
            };
            auto task = std::make_unique<Task>(Task{
                .request = std::move(request),
                .snapshot = std::move(snapshot),
            });
            command.id = task->request.id;
            tasks.insert_or_assign(command.id, std::move(task));
            task_order.push_back(command.id);
            {
                std::lock_guard lock(mutex);
                pending_ids.erase(command.id);
            }
            publish_snapshot(*tasks.at(command.id));
        } else {
            const auto iterator = tasks.find(command.id);
            if (iterator == tasks.end()) {
                result = Result::not_found;
            } else {
                result = apply_command(*iterator->second, command.kind);
                if (result == Result::ok && command.kind == CommandKind::remove) {
                    try {
                        store->remove(command.id);
                    } catch (...) {
                        result = Result::persistence_error;
                    }
                }
                if (result == Result::ok && command.kind == CommandKind::remove) {
                    {
                        std::lock_guard lock(mutex);
                        snapshots_by_id.erase(command.id);
                        diagnostic_events_by_id.erase(command.id);
                        emit_locked(Event{
                            .command_id = command.command_id,
                            .download_id = command.id,
                            .kind = EventKind::removed,
                            .result = Result::ok,
                        });
                    }
                    tasks.erase(iterator);
                    std::erase(task_order, command.id);
                }
            }
        }

        std::lock_guard lock(mutex);
        emit_locked(Event{
            .command_id = command.command_id,
            .download_id = command.id,
            .kind = EventKind::command_result,
            .result = result,
        });
    }

    Result apply_command(Task &task, CommandKind command) {
        const auto validation = validate_command(task.snapshot.state, command);
        if (validation != Result::ok) {
            return validation;
        }

        switch (command) {
        case CommandKind::pause:
            remove_transfers(task);
            task.retry_at.reset();
            task.snapshot.state = DownloadState::paused;
            close_file(task);
            break;
        case CommandKind::resume:
            task.retry_at.reset();
            task.snapshot.state = DownloadState::queued;
            break;
        case CommandKind::cancel:
            remove_transfers(task);
            close_file(task);
            remove_temporary_file(task);
            task.snapshot.state = DownloadState::cancelled;
            task.snapshot.downloaded_bytes = 0;
            task.write_offset = 0;
            task.retry_at.reset();
            reset_segments(task);
            break;
        case CommandKind::retry:
            remove_transfers(task);
            close_file(task);
            remove_temporary_file(task);
            task.snapshot.state = DownloadState::queued;
            task.snapshot.downloaded_bytes = 0;
            task.snapshot.error_code = Result::ok;
            task.snapshot.error_message.clear();
            task.write_offset = 0;
            task.retry_attempt = 0;
            task.retry_at.reset();
            reset_segments(task);
            break;
        case CommandKind::remove:
            remove_transfers(task);
            close_file(task);
            remove_temporary_file(task);
            return Result::ok;
        case CommandKind::enqueue:
            return Result::invalid_argument;
        }
        publish_snapshot(task);
        return Result::ok;
    }

    void schedule_queued_tasks() {
        const auto now = Clock::now();
        for (const auto &id : task_order) {
            auto &task = *tasks.at(id);
            if (task.snapshot.state == DownloadState::retrying && task.retry_at &&
                now >= *task.retry_at) {
                task.retry_at.reset();
                task.snapshot.state = DownloadState::queued;
                task.snapshot.error_code = Result::ok;
                task.snapshot.error_message.clear();
                publish_snapshot(task);
            }
        }

        std::size_t active_tasks = 0;
        for (const auto &[id, task] : tasks) {
            (void)id;
            if (!task->active_handles.empty()) {
                ++active_tasks;
            }
        }

        for (const auto &id : task_order) {
            auto &task = tasks.at(id);
            if (active_tasks >= config.maximum_active_downloads) {
                break;
            }
            if (task->snapshot.state != DownloadState::queued ||
                !task->active_handles.empty()) {
                continue;
            }
            if (task->snapshot.content_length_known || task->write_offset > 0 ||
                !task->segments.empty()) {
                start_body(*task);
            } else {
                start_probe(*task);
            }
            if (!task->active_handles.empty()) {
                ++active_tasks;
            }
        }
    }

    std::unique_ptr<Transfer> make_transfer(Task &task, TransferKind kind) {
        auto transfer = std::make_unique<Transfer>();
        transfer->owner = this;
        transfer->task = &task;
        transfer->kind = kind;
        transfer->easy = curl_easy_init();
        if (transfer->easy == nullptr) {
            fail_task(task, Result::network_error, "curl_easy_init failed");
            return nullptr;
        }

        curl_easy_setopt(transfer->easy, CURLOPT_URL, task.request.url.c_str());
        curl_easy_setopt(transfer->easy, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_MAXREDIRS, 10L);
        curl_easy_setopt(transfer->easy, CURLOPT_CONNECTTIMEOUT_MS, 15'000L);
        curl_easy_setopt(transfer->easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_LOW_SPEED_TIME, 30L);
        curl_easy_setopt(transfer->easy, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_USERAGENT, "SwiftyDownloadManager/0.3 libcurl");
        curl_easy_setopt(transfer->easy, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(transfer->easy, CURLOPT_SSL_VERIFYHOST, 2L);
        if (!config.certificate_authority_bundle.empty()) {
            curl_easy_setopt(
                transfer->easy,
                CURLOPT_CAINFO,
                config.certificate_authority_bundle.c_str()
            );
        }
        curl_easy_setopt(transfer->easy, CURLOPT_ERRORBUFFER, transfer->error_buffer.data());
        curl_easy_setopt(transfer->easy, CURLOPT_HEADERFUNCTION, header_callback);
        curl_easy_setopt(transfer->easy, CURLOPT_HEADERDATA, transfer.get());
        curl_easy_setopt(transfer->easy, CURLOPT_WRITEFUNCTION, write_callback);
        curl_easy_setopt(transfer->easy, CURLOPT_WRITEDATA, transfer.get());
        curl_easy_setopt(transfer->easy, CURLOPT_PRIVATE, transfer.get());
        return transfer;
    }

    void start_probe(Task &task) {
        auto transfer = make_transfer(task, TransferKind::probe);
        if (!transfer) {
            return;
        }
        curl_easy_setopt(transfer->easy, CURLOPT_NOBODY, 1L);
        task.snapshot.state = DownloadState::probing;
        task.snapshot.last_attempt_milliseconds = current_milliseconds();
        add_transfer(task, std::move(transfer));
        publish_snapshot(task);
    }

    void start_probe_range(Task &task) {
        auto transfer = make_transfer(task, TransferKind::probe_range);
        if (!transfer) {
            return;
        }
        curl_easy_setopt(transfer->easy, CURLOPT_RANGE, "0-0");
        add_transfer(task, std::move(transfer));
    }

    bool start_segment_transfer(
        Task &task,
        std::uint32_t segment_ordinal,
        std::uint32_t bandwidth_share_count,
        bool must_use_ranges
    ) {
        if (segment_ordinal >= task.segments.size()) {
            fail_task(task, Result::internal_error, "Segment ordinal was out of bounds");
            return false;
        }
        const auto &segment = task.segments[segment_ordinal];
        if (segment.next > segment.end) {
            return true;
        }

        auto transfer = make_transfer(task, TransferKind::body);
        if (!transfer) {
            return false;
        }
        transfer->segment_ordinal = segment_ordinal;
        transfer->start_offset = segment.next;
        transfer->end_offset = segment.end;
        transfer->expected_bytes = segment.end - segment.next + 1;
        apply_bandwidth_limit(*transfer, task, bandwidth_share_count);
        if (must_use_ranges) {
            transfer->expects_partial_response = true;
            const auto range = std::to_string(segment.next) + "-" +
                std::to_string(segment.end);
            curl_easy_setopt(transfer->easy, CURLOPT_RANGE, range.c_str());
            const auto &validator = !task.etag.empty()
                ? task.etag
                : task.last_modified;
            if (!validator.empty()) {
                const auto header = "If-Range: " + validator;
                transfer->request_headers = curl_slist_append(
                    transfer->request_headers,
                    header.c_str()
                );
                curl_easy_setopt(
                    transfer->easy,
                    CURLOPT_HTTPHEADER,
                    transfer->request_headers
                );
            }
        }
        auto *easy = transfer->easy;
        add_transfer(task, std::move(transfer));
        return task.active_handles.contains(easy);
    }

    void start_body(Task &task) {
        if (!task.snapshot.content_length_known && task.segments.empty() &&
            task.write_offset > 0) {
            task.write_offset = 0;
            task.snapshot.downloaded_bytes = 0;
        }
        if (!prepare_file(task)) {
            return;
        }
        if (task.segments.empty() && task.snapshot.content_length_known &&
            task.snapshot.content_length > 0) {
            const auto connection_limit = task.accepts_ranges
                ? task.request.connection_limit
                : 1U;
            task.segments = plan_segments(
                task.snapshot.content_length,
                connection_limit,
                config.maximum_connections_per_download
            );
        }

        task.transfer_started = Clock::now();
        task.last_published = task.transfer_started;
        task.speed_baseline_bytes = downloaded_bytes(task);
        task.snapshot.state = DownloadState::downloading;
        task.snapshot.last_attempt_milliseconds = current_milliseconds();
        task.snapshot.segment_count = static_cast<std::uint32_t>(task.segments.size());
        task.snapshot.segments = task.segments;

        if (task.segments.empty()) {
            auto transfer = make_transfer(task, TransferKind::body);
            if (!transfer) {
                return;
            }
            transfer->start_offset = task.write_offset;
            apply_bandwidth_limit(*transfer, task, 1);
            add_transfer(task, std::move(transfer));
        } else {
            const bool must_use_ranges = task.segments.size() > 1 ||
                task.segments.front().next > task.segments.front().start;
            const auto unfinished_count = static_cast<std::uint32_t>(std::ranges::count_if(
                task.segments,
                [](const Segment &segment) { return segment.next <= segment.end; }
            ));
            for (std::uint32_t ordinal = 0; ordinal < task.segments.size(); ++ordinal) {
                const auto &segment = task.segments[ordinal];
                if (segment.next > segment.end) {
                    continue;
                }
                if (!start_segment_transfer(
                        task,
                        ordinal,
                        unfinished_count,
                        must_use_ranges
                    )) {
                    return;
                }
            }
        }
        publish_snapshot(task);
    }

    void add_transfer(Task &task, std::unique_ptr<Transfer> transfer) {
        auto *easy = transfer->easy;
        if (curl_multi_add_handle(multi, easy) != CURLM_OK) {
            cleanup_easy(*transfer);
            fail_task(task, Result::network_error, "Unable to add curl transfer");
            return;
        }
        task.active_handles.insert(easy);
        transfers.insert_or_assign(easy, std::move(transfer));
    }

    static void apply_bandwidth_limit(
        Transfer &transfer,
        const Task &task,
        std::uint32_t active_count
    ) {
        if (task.request.bandwidth_limit == 0 || active_count == 0) {
            return;
        }
        const auto per_transfer = std::max<std::uint64_t>(
            1,
            task.request.bandwidth_limit / active_count
        );
        curl_easy_setopt(
            transfer.easy,
            CURLOPT_MAX_RECV_SPEED_LARGE,
            static_cast<curl_off_t>(per_transfer)
        );
    }

    bool rebalance_segmented_task(Task &task) {
        const auto connection_limit = std::min(
            task.request.connection_limit,
            config.maximum_connections_per_download
        );
        const auto maximum_segment_count =
            static_cast<std::size_t>(connection_limit) *
            maximum_segments_per_connection;
        if (!task.accepts_ranges || connection_limit < 2 ||
            task.segments.size() >= maximum_segment_count) {
            return false;
        }

        bool rebalanced = false;
        while (task.active_handles.size() < connection_limit &&
               task.segments.size() < maximum_segment_count) {
            CURL *donor_handle = nullptr;
            std::uint32_t donor_ordinal = std::numeric_limits<std::uint32_t>::max();
            std::uint64_t largest_remaining_length = 0;

            for (auto *handle : task.active_handles) {
                const auto transfer_iterator = transfers.find(handle);
                if (transfer_iterator == transfers.end()) {
                    continue;
                }
                const auto &transfer = *transfer_iterator->second;
                if (transfer.kind != TransferKind::body ||
                    transfer.segment_ordinal >= task.segments.size()) {
                    continue;
                }
                const auto &segment = task.segments[transfer.segment_ordinal];
                if (segment.next > segment.end) {
                    continue;
                }
                const auto remaining_length = segment.end - segment.next + 1;
                if (remaining_length / 2 < minimum_adaptive_segment_length ||
                    remaining_length <= largest_remaining_length) {
                    continue;
                }
                donor_handle = handle;
                donor_ordinal = transfer.segment_ordinal;
                largest_remaining_length = remaining_length;
            }

            if (donor_handle == nullptr) {
                break;
            }

            auto transfer_iterator = transfers.find(donor_handle);
            auto donor_transfer = std::move(transfer_iterator->second);
            transfers.erase(transfer_iterator);
            curl_multi_remove_handle(multi, donor_handle);
            task.active_handles.erase(donor_handle);
            cleanup_easy(*donor_transfer);

            const auto new_ordinal = static_cast<std::uint32_t>(task.segments.size());
            auto tail = split_segment_tail(
                task.segments[donor_ordinal],
                new_ordinal,
                minimum_adaptive_segment_length
            );
            if (!tail) {
                fail_task(task, Result::internal_error, "Unable to split Range segment");
                return rebalanced;
            }
            const auto split_start = tail->start;
            task.segments.push_back(*tail);

            if (!start_segment_transfer(
                    task,
                    donor_ordinal,
                    connection_limit,
                    true
                ) ||
                !start_segment_transfer(
                    task,
                    new_ordinal,
                    connection_limit,
                    true
                )) {
                return rebalanced;
            }

            record_diagnostic(
                task,
                DiagnosticLevel::info,
                0,
                "Reused an idle connection by splitting Range segment " +
                    std::to_string(donor_ordinal + 1) + " at byte " +
                    std::to_string(split_start) + "."
            );
            rebalanced = true;
        }

        if (rebalanced) {
            task.snapshot.downloaded_bytes = downloaded_bytes(task);
            publish_snapshot(task);
        }
        return rebalanced;
    }

    void process_completed_transfers() {
        int remaining_messages = 0;
        while (auto *message = curl_multi_info_read(multi, &remaining_messages)) {
            if (message->msg != CURLMSG_DONE) {
                continue;
            }
            auto iterator = transfers.find(message->easy_handle);
            if (iterator == transfers.end()) {
                continue;
            }
            auto transfer = std::move(iterator->second);
            transfers.erase(iterator);
            curl_multi_remove_handle(multi, message->easy_handle);
            curl_easy_getinfo(message->easy_handle, CURLINFO_RESPONSE_CODE, &transfer->response_status);
            curl_off_t content_length = -1;
            if (curl_easy_getinfo(
                    message->easy_handle,
                    CURLINFO_CONTENT_LENGTH_DOWNLOAD_T,
                    &content_length
                ) == CURLE_OK && content_length >= 0) {
                transfer->content_length = static_cast<std::uint64_t>(content_length);
            }
            char *effective_url = nullptr;
            if (curl_easy_getinfo(
                    message->easy_handle,
                    CURLINFO_EFFECTIVE_URL,
                    &effective_url
                ) == CURLE_OK && effective_url != nullptr) {
                transfer->effective_url = effective_url;
            }
            if (transfer->task != nullptr) {
                transfer->task->active_handles.erase(message->easy_handle);
            }
            const auto curl_result = message->data.result;
            cleanup_easy(*transfer);
            transfer->easy = nullptr;
            finish_transfer(*transfer, curl_result);
        }
    }

    void finish_transfer(Transfer &transfer, CURLcode curl_result) {
        auto &task = *transfer.task;
        if (transfer.protocol_failed) {
            fail_task(task, Result::protocol_error, "Range response metadata did not match request");
            return;
        }
        if (curl_result != CURLE_OK || transfer.write_failed) {
            const auto message = transfer.error_buffer.c_str()[0] != '\0'
                ? std::string(transfer.error_buffer.c_str())
                : std::string(curl_easy_strerror(curl_result));
            if (transfer.write_failed) {
                fail_task(task, Result::io_error, message);
            } else if (!sdm::is_retryable_curl_error(
                           static_cast<std::uint32_t>(curl_result)
                       )) {
                fail_task(task, Result::network_error, message);
            } else {
                retry_or_fail(task, Result::network_error, message);
            }
            return;
        }
        if (transfer.kind == TransferKind::probe &&
            (transfer.response_status == 405 || transfer.response_status == 501)) {
            start_probe_range(task);
            return;
        }
        if (transfer.response_status < 200 || transfer.response_status >= 300) {
            const auto message = "HTTP status " + std::to_string(transfer.response_status);
            if (transfer.response_status == 408 || transfer.response_status == 429 ||
                transfer.response_status >= 500) {
                retry_or_fail(task, Result::network_error, message);
            } else {
                fail_task(task, Result::protocol_error, message);
            }
            return;
        }

        if (transfer.kind == TransferKind::probe ||
            transfer.kind == TransferKind::probe_range) {
            finish_probe(task, transfer);
            return;
        }

        if (transfer.expected_bytes > 0 &&
            transfer.received_bytes != transfer.expected_bytes) {
            fail_task(task, Result::protocol_error, "Response length did not match metadata");
            return;
        }
        update_snapshot_segments(task);
        task.snapshot.downloaded_bytes = downloaded_bytes(task);
        if (!task.active_handles.empty()) {
            const auto rebalanced = rebalance_segmented_task(task);
            if (task.snapshot.state != DownloadState::downloading) {
                return;
            }
            if (!rebalanced) {
                publish_snapshot(task);
            }
            return;
        }
        if (task.snapshot.content_length_known &&
            task.snapshot.downloaded_bytes != task.snapshot.content_length) {
            fail_task(task, Result::protocol_error, "Download ended before the expected length");
            return;
        }
        finalize(task);
    }

    void finish_probe(Task &task, Transfer &transfer) {
        task.snapshot.final_url = transfer.effective_url.empty()
            ? task.request.url
            : transfer.effective_url;
        if (transfer.kind == TransferKind::probe_range) {
            const auto iterator = transfer.headers.find("content-range");
            const auto range = iterator == transfer.headers.end()
                ? std::nullopt
                : parse_content_range(iterator->second);
            if (transfer.response_status != 206 || !range || range->start != 0 ||
                range->end != 0) {
                fail_task(task, Result::protocol_error, "Range probe returned invalid metadata");
                return;
            }
            if (range->total) {
                task.snapshot.content_length_known = true;
                task.snapshot.content_length = *range->total;
                task.accepts_ranges = true;
            } else {
                task.accepts_ranges = false;
            }
        } else if (transfer.content_length) {
            task.snapshot.content_length_known = true;
            task.snapshot.content_length = *transfer.content_length;
        } else if (const auto iterator = transfer.headers.find("content-length");
                   iterator != transfer.headers.end()) {
            if (const auto parsed = parse_unsigned(iterator->second)) {
                task.snapshot.content_length_known = true;
                task.snapshot.content_length = *parsed;
            }
        }
        if (const auto iterator = transfer.headers.find("accept-ranges");
            iterator != transfer.headers.end()) {
            task.accepts_ranges = lowercase(iterator->second).find("bytes") !=
                std::string::npos;
        }
        if (const auto iterator = transfer.headers.find("etag");
            iterator != transfer.headers.end()) {
            task.etag = iterator->second;
        }
        if (const auto iterator = transfer.headers.find("last-modified");
            iterator != transfer.headers.end()) {
            task.last_modified = iterator->second;
        }
        bool response_supplied_filename = false;
        if (task.request.filename.empty()) {
            if (const auto iterator = transfer.headers.find("content-disposition");
                iterator != transfer.headers.end()) {
                const auto name = content_disposition_filename(iterator->second);
                if (!name.empty()) {
                    task.snapshot.filename = name;
                    response_supplied_filename = true;
                }
            }
        }
        if (task.request.filename.empty() && !response_supplied_filename) {
            if (const auto iterator = transfer.headers.find("content-type");
                iterator != transfer.headers.end()) {
                task.snapshot.filename = infer_filename_extension(
                    std::move(task.snapshot.filename),
                    iterator->second
                );
            }
        }
        start_body(task);
    }

    bool prepare_file(Task &task) {
        std::error_code error;
        std::filesystem::create_directories(config.temporary_directory, error);
        if (error) {
            fail_task(task, Result::io_error, "Unable to create temporary directory");
            return false;
        }
        std::filesystem::create_directories(task.request.destination_directory, error);
        if (error) {
            fail_task(task, Result::io_error, "Unable to create destination directory");
            return false;
        }
        if (task.temporary_path.empty()) {
            task.temporary_path = std::filesystem::path(config.temporary_directory) /
                ("." + task.request.id + ".sdmpart");
        }
        if (task.destination_path.empty()) {
            task.destination_path = resolve_destination(task, error);
            if (error || task.destination_path.empty()) {
                fail_task(task, Result::io_error, "Unable to resolve destination filename");
                return false;
            }
            task.snapshot.destination_url = task.destination_path.string();
        }

        if (task.file_descriptor < 0) {
            task.file_descriptor = ::open(
                task.temporary_path.c_str(),
                O_CREAT | O_RDWR,
                S_IRUSR | S_IWUSR
            );
            if (task.file_descriptor < 0) {
                fail_task(task, Result::io_error, "Unable to open temporary file");
                return false;
            }
        }
        if (downloaded_bytes(task) == 0 &&
            ::ftruncate(
                task.file_descriptor,
                task.snapshot.content_length_known
                    ? static_cast<off_t>(task.snapshot.content_length)
                    : 0
            ) != 0) {
            fail_task(task, Result::io_error, "Unable to allocate temporary file");
            return false;
        }
        return true;
    }

    std::filesystem::path resolve_destination(Task &task, std::error_code &error) {
        auto destination = std::filesystem::path(task.request.destination_directory) /
            task.snapshot.filename;
        if (!std::filesystem::exists(destination, error)) {
            return destination;
        }
        if (task.request.conflict_policy == 1) {
            return destination;
        }
        if (task.request.conflict_policy == 2) {
            error = std::make_error_code(std::errc::file_exists);
            return {};
        }

        const auto parent = destination.parent_path();
        const auto stem = destination.stem().string();
        const auto extension = destination.extension().string();
        for (std::uint32_t index = 1; index < 100'000; ++index) {
            auto candidate = parent /
                (stem + " (" + std::to_string(index) + ")" + extension);
            if (!std::filesystem::exists(candidate, error)) {
                return candidate;
            }
        }
        error = std::make_error_code(std::errc::file_exists);
        return {};
    }

    void finalize(Task &task) {
        task.snapshot.state = DownloadState::finalizing;
        publish_snapshot(task);
        if (task.file_descriptor >= 0 && ::fsync(task.file_descriptor) != 0) {
            fail_task(task, Result::io_error, "Unable to synchronize temporary file");
            return;
        }
        close_file(task);

        std::string finalization_error;
        if (!finalize_file(
                task.temporary_path,
                task.destination_path,
                task.request.conflict_policy == 1,
                finalization_error
            )) {
            fail_task(
                task,
                Result::io_error,
                "Unable to finalize downloaded file: " + finalization_error
            );
            return;
        }
        task.snapshot.state = DownloadState::completed;
        task.snapshot.completed_milliseconds = current_milliseconds();
        task.retry_attempt = 0;
        task.retry_at.reset();
        task.snapshot.bytes_per_second = 0;
        task.snapshot.estimated_seconds_remaining = 0;
        publish_snapshot(task);
    }

    void publish_progress() {
        const auto now = Clock::now();
        for (auto &[id, task] : tasks) {
            (void)id;
            if (task->snapshot.state != DownloadState::downloading ||
                now - task->last_published < std::chrono::milliseconds(50)) {
                continue;
            }
            update_snapshot_segments(*task);
            task->snapshot.downloaded_bytes = downloaded_bytes(*task);
            const auto elapsed = std::chrono::duration<double>(
                now - task->transfer_started
            ).count();
            if (elapsed > 0) {
                task->snapshot.bytes_per_second = static_cast<std::uint64_t>(
                    static_cast<double>(
                        task->snapshot.downloaded_bytes - task->speed_baseline_bytes
                    ) / elapsed
                );
            }
            if (task->snapshot.content_length_known &&
                task->snapshot.bytes_per_second > 0) {
                task->snapshot.estimated_seconds_remaining =
                    (task->snapshot.content_length - task->snapshot.downloaded_bytes) /
                    task->snapshot.bytes_per_second;
            }
            task->last_published = now;
            constexpr auto checkpoint_interval = std::chrono::milliseconds(500);
            const bool should_checkpoint =
                now - task->last_checkpoint >= checkpoint_interval;
            publish_snapshot(*task, true, should_checkpoint);
        }
    }

    void fail_task(Task &task, Result result, std::string message) {
        remove_transfers(task);
        task.retry_at.reset();
        close_file(task);
        task.snapshot.state = DownloadState::failed;
        task.snapshot.error_code = result;
        task.snapshot.error_message = std::move(message);
        task.snapshot.bytes_per_second = 0;
        task.snapshot.estimated_seconds_remaining = 0;
        publish_snapshot(task);
    }

    void retry_or_fail(Task &task, Result result, std::string message) {
        constexpr std::uint32_t maximum_attempts = 3;
        if (task.retry_attempt >= maximum_attempts) {
            fail_task(task, result, std::move(message));
            return;
        }
        remove_transfers(task);
        close_file(task);
        ++task.retry_attempt;
        const auto exponent = std::min<std::uint32_t>(task.retry_attempt - 1, 4);
        const auto delay = std::chrono::milliseconds(250 * (1U << exponent));
        task.retry_at = Clock::now() + delay;
        task.snapshot.state = DownloadState::retrying;
        task.snapshot.error_code = result;
        task.snapshot.error_message = std::move(message);
        task.snapshot.bytes_per_second = 0;
        task.snapshot.estimated_seconds_remaining = 0;
        publish_snapshot(task);
    }

    void fail_active_transfers(Result result, const std::string &message) {
        std::unordered_set<Task *> affected;
        for (const auto &[easy, transfer] : transfers) {
            (void)easy;
            affected.insert(transfer->task);
        }
        stop_all_transfers();
        for (auto *task : affected) {
            fail_task(*task, result, message);
        }
    }

    void remove_transfers(Task &task) {
        const auto handles = task.active_handles;
        for (auto *handle : handles) {
            const auto iterator = transfers.find(handle);
            if (iterator != transfers.end()) {
                curl_multi_remove_handle(multi, iterator->first);
                cleanup_easy(*iterator->second);
                transfers.erase(iterator);
            }
        }
        task.active_handles.clear();
    }

    void stop_all_transfers() {
        for (auto &[easy, transfer] : transfers) {
            if (transfer->task != nullptr) {
                transfer->task->active_handles.clear();
            }
            curl_multi_remove_handle(multi, easy);
            cleanup_easy(*transfer);
        }
        transfers.clear();
    }

    static void reset_segments(Task &task) {
        for (auto &segment : task.segments) {
            segment.next = segment.start;
        }
        update_snapshot_segments(task);
    }

    static std::uint64_t downloaded_bytes(const Task &task) noexcept {
        if (task.segments.empty()) {
            return task.write_offset;
        }
        std::uint64_t result = 0;
        for (const auto &segment : task.segments) {
            const auto next = std::min(segment.next, segment.end + 1);
            if (next > segment.start) {
                result += next - segment.start;
            }
        }
        return result;
    }

    static void update_snapshot_segments(Task &task) {
        task.snapshot.segment_count = static_cast<std::uint32_t>(task.segments.size());
        task.snapshot.segments = task.segments;
    }

    static void close_file(Task &task) noexcept {
        if (task.file_descriptor >= 0) {
            ::close(task.file_descriptor);
            task.file_descriptor = -1;
        }
    }

    static void cleanup_easy(Transfer &transfer) noexcept {
        if (transfer.easy != nullptr) {
            curl_easy_cleanup(transfer.easy);
            transfer.easy = nullptr;
        }
        if (transfer.request_headers != nullptr) {
            curl_slist_free_all(transfer.request_headers);
            transfer.request_headers = nullptr;
        }
    }

    static void remove_temporary_file(Task &task) noexcept {
        if (!task.temporary_path.empty()) {
            std::error_code error;
            std::filesystem::remove(task.temporary_path, error);
        }
    }

    static std::string_view state_title(DownloadState state) noexcept {
        switch (state) {
        case DownloadState::created: return "Created";
        case DownloadState::probing: return "Connecting";
        case DownloadState::queued: return "Queued";
        case DownloadState::downloading: return "Downloading";
        case DownloadState::pausing: return "Pausing";
        case DownloadState::paused: return "Paused";
        case DownloadState::retrying: return "Retrying";
        case DownloadState::finalizing: return "Finalizing";
        case DownloadState::completed: return "Completed";
        case DownloadState::failed: return "Failed";
        case DownloadState::cancelled: return "Cancelled";
        }
        return "Unknown";
    }

    void record_diagnostic(
        Task &task,
        DiagnosticLevel level,
        std::uint32_t code,
        std::string message
    ) noexcept {
        try {
            auto event = store->append_event(
                task.snapshot.id,
                current_milliseconds(),
                level,
                code,
                message
            );
            std::lock_guard lock(mutex);
            auto &events = diagnostic_events_by_id[task.snapshot.id];
            events.push_back(std::move(event));
            constexpr std::size_t maximum_event_count = 500;
            if (events.size() > maximum_event_count) {
                events.erase(
                    events.begin(),
                    events.begin() + static_cast<std::ptrdiff_t>(
                        events.size() - maximum_event_count
                    )
                );
            }
        } catch (...) {
            // The snapshot write remains authoritative if a diagnostic row fails.
        }
    }

    void publish_snapshot(
        Task &task,
        bool refresh_timestamp = true,
        bool persist_to_store = true
    ) {
        update_snapshot_segments(task);
        if (refresh_timestamp) {
            task.snapshot.updated_milliseconds = current_milliseconds();
        }
        if (task.snapshot.created_milliseconds == 0) {
            task.snapshot.created_milliseconds = task.snapshot.updated_milliseconds;
        }
        if (task.snapshot.state == DownloadState::downloading &&
            task.snapshot.started_milliseconds == 0) {
            task.snapshot.started_milliseconds = task.snapshot.updated_milliseconds;
        }
        if (task.snapshot.state == DownloadState::completed &&
            task.snapshot.completed_milliseconds == 0) {
            task.snapshot.completed_milliseconds = task.snapshot.updated_milliseconds;
        }
        const auto previous_state = task.last_published_state;
        const auto previous_error_code = task.last_published_error_code;
        const auto previous_error_message = task.last_published_error_message;
        if (persist_to_store) {
            persist_task(task);
            task.last_checkpoint = Clock::now();
        }
        if (persist_to_store && !previous_state) {
            record_diagnostic(
                task,
                DiagnosticLevel::info,
                static_cast<std::uint32_t>(task.snapshot.state),
                "Added to download history in " +
                    std::string(state_title(task.snapshot.state)) + " state."
            );
        } else if (persist_to_store && *previous_state != task.snapshot.state) {
            record_diagnostic(
                task,
                task.snapshot.state == DownloadState::failed
                    ? DiagnosticLevel::error
                    : DiagnosticLevel::info,
                static_cast<std::uint32_t>(task.snapshot.state),
                "State changed: " + std::string(state_title(*previous_state)) +
                    " -> " + std::string(state_title(task.snapshot.state)) + "."
            );
        }
        if (persist_to_store && task.snapshot.error_code != Result::ok &&
            (previous_error_code != task.snapshot.error_code ||
             previous_error_message != task.snapshot.error_message)) {
            record_diagnostic(
                task,
                DiagnosticLevel::error,
                static_cast<std::uint32_t>(task.snapshot.error_code),
                task.snapshot.error_message
            );
        }
        task.last_published_state = task.snapshot.state;
        task.last_published_error_code = task.snapshot.error_code;
        task.last_published_error_message = task.snapshot.error_message;
        std::lock_guard lock(mutex);
        snapshots_by_id.insert_or_assign(task.snapshot.id, task.snapshot);
        emit_locked(Event{
            .download_id = task.snapshot.id,
            .kind = EventKind::snapshot_changed,
            .result = task.snapshot.error_code,
        });
    }

    void persist_task(Task &task) noexcept {
        try {
            store->save(PersistedDownload{
                .request = task.request,
                .snapshot = task.snapshot,
                .temporary_path = task.temporary_path.string(),
                .accepts_ranges = task.accepts_ranges,
                .etag = task.etag,
                .last_modified = task.last_modified,
            });
        } catch (...) {
            task.snapshot.state = DownloadState::failed;
            task.snapshot.error_code = Result::persistence_error;
            task.snapshot.error_message = "Unable to persist download state";
        }
    }

    void emit_locked(Event event) {
        event.sequence = next_event_sequence++;
        events.push_back(std::move(event));
        constexpr std::size_t maximum_event_count = 4096;
        if (events.size() > maximum_event_count) {
            const auto progress = std::find_if(events.begin(), events.end(), [](const Event &value) {
                return value.kind == EventKind::snapshot_changed;
            });
            if (progress != events.end()) {
                events.erase(progress);
            }
        }
    }

    EngineConfig config;
    CURLM *multi = nullptr;
    std::unique_ptr<DownloadStore> store;
    mutable std::mutex mutex;
    std::condition_variable condition;
    std::deque<Command> commands;
    std::deque<Event> events;
    std::unordered_map<std::string, DownloadSnapshot> snapshots_by_id;
    std::unordered_map<std::string, std::vector<DiagnosticEvent>>
        diagnostic_events_by_id;
    std::unordered_set<std::string> pending_ids;
    std::unordered_map<std::string, std::unique_ptr<Task>> tasks;
    std::vector<std::string> task_order;
    std::unordered_map<CURL *, std::unique_ptr<Transfer>> transfers;
    std::uint64_t next_command_id = 1;
    std::uint64_t next_event_sequence = 1;
    bool stopping = false;
    std::jthread worker;
};

sdm::Engine::Engine(EngineConfig config)
    : impl_(std::make_unique<Impl>(std::move(config))) {}

sdm::Engine::~Engine() = default;

sdm::Result sdm::Engine::enqueue(
    DownloadRequest request,
    std::uint64_t &command_id
) {
    return impl_->enqueue(std::move(request), command_id);
}

sdm::Result sdm::Engine::submit(
    std::string id,
    CommandKind command,
    std::uint64_t &command_id
) {
    return impl_->submit(std::move(id), command, command_id);
}

std::vector<sdm::Event> sdm::Engine::poll_events(std::size_t maximum_count) {
    return impl_->poll_events(maximum_count);
}

std::optional<sdm::DownloadSnapshot> sdm::Engine::snapshot(
    std::string_view id
) const {
    return impl_->snapshot(id);
}

std::vector<sdm::DownloadSnapshot> sdm::Engine::snapshots() const {
    return impl_->snapshots();
}

std::vector<sdm::DiagnosticEvent> sdm::Engine::diagnostic_events(
    std::string_view id
) const {
    return impl_->diagnostic_events(id);
}

void sdm::Engine::shutdown() noexcept {
    impl_->shutdown();
}
