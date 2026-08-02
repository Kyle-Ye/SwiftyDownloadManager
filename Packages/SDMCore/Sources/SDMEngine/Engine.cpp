#include "SDMEngine.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>

static_assert(sdm::engine_abi_version > 0);

std::string_view sdm::Engine::version() noexcept {
    return "0.1.0-dev";
}

namespace {

std::uint64_t current_milliseconds() noexcept {
    const auto now = std::chrono::system_clock::now().time_since_epoch();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(now).count()
    );
}

std::string inferred_filename(const sdm::DownloadRequest &request) {
    if (!request.filename.empty()) {
        return request.filename;
    }

    const auto query = request.url.find_first_of("?#");
    const auto path = request.url.substr(0, query);
    const auto slash = path.find_last_of('/');
    if (slash != std::string::npos && slash + 1 < path.size()) {
        return path.substr(slash + 1);
    }
    return "download.bin";
}

} // namespace

class sdm::Engine::Impl final {
public:
    explicit Impl(EngineConfig engine_config)
        : config(std::move(engine_config)),
          worker([this](std::stop_token stop_token) { run(stop_token); }) {}

    ~Impl() {
        shutdown();
    }

    struct Command final {
        std::uint64_t command_id = 0;
        CommandKind kind = CommandKind::enqueue;
        std::string id;
        std::optional<DownloadRequest> request;
    };

    Result enqueue(DownloadRequest request, std::uint64_t &command_id) {
        if (request.id.empty() || request.url.empty() ||
            request.destination_directory.empty() ||
            request.connection_limit == 0) {
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
        condition.notify_one();
        return Result::ok;
    }

    Result submit(
        std::string id,
        CommandKind command,
        std::uint64_t &command_id
    ) {
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
        condition.notify_one();
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
        std::ranges::sort(result, {}, &DownloadSnapshot::updated_milliseconds);
        return result;
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
        condition.notify_all();
        if (worker.joinable()) {
            worker.join();
        }
    }

private:
    void run(std::stop_token stop_token) {
        while (!stop_token.stop_requested()) {
            Command command;
            {
                std::unique_lock lock(mutex);
                condition.wait(lock, stop_token, [this] {
                    return !commands.empty() || stopping;
                });
                if (stop_token.stop_requested() || stopping) {
                    break;
                }
                command = std::move(commands.front());
                commands.pop_front();
            }
            process(std::move(command));
        }

        std::lock_guard lock(mutex);
        emit_locked(Event{
            .sequence = 0,
            .command_id = 0,
            .download_id = {},
            .kind = EventKind::engine_stopped,
            .result = Result::ok,
        });
    }

    void process(Command command) {
        std::lock_guard lock(mutex);
        Result result = Result::ok;

        if (command.kind == CommandKind::enqueue && command.request) {
            auto request = std::move(*command.request);
            auto snapshot = DownloadSnapshot{
                .id = request.id,
                .source_url = request.url,
                .final_url = {},
                .destination_url = {},
                .filename = inferred_filename(request),
                .state = DownloadState::queued,
                .content_length_known = false,
                .content_length = 0,
                .downloaded_bytes = 0,
                .bytes_per_second = 0,
                .estimated_seconds_remaining = 0,
                .segment_count = 0,
                .error_code = Result::ok,
                .error_message = {},
                .updated_milliseconds = current_milliseconds(),
            };
            pending_ids.erase(request.id);
            snapshots_by_id.insert_or_assign(request.id, std::move(snapshot));
        } else {
            const auto iterator = snapshots_by_id.find(command.id);
            if (iterator == snapshots_by_id.end()) {
                result = Result::not_found;
            } else {
                auto &snapshot = iterator->second;
                result = validate_command(snapshot.state, command.kind);
                if (result == Result::ok) {
                    switch (command.kind) {
                    case CommandKind::pause:
                        snapshot.state = DownloadState::paused;
                        break;
                    case CommandKind::resume:
                    case CommandKind::retry:
                        snapshot.state = DownloadState::queued;
                        snapshot.error_code = Result::ok;
                        snapshot.error_message.clear();
                        break;
                    case CommandKind::cancel:
                        snapshot.state = DownloadState::cancelled;
                        break;
                    case CommandKind::remove:
                        snapshots_by_id.erase(iterator);
                        emit_locked(Event{
                            .sequence = 0,
                            .command_id = command.command_id,
                            .download_id = command.id,
                            .kind = EventKind::removed,
                            .result = Result::ok,
                        });
                        emit_command_result_locked(command, Result::ok);
                        return;
                    case CommandKind::enqueue:
                        result = Result::invalid_argument;
                        break;
                    }
                    if (result == Result::ok) {
                        snapshot.updated_milliseconds = current_milliseconds();
                    }
                }
            }
        }

        if (result == Result::ok) {
            emit_locked(Event{
                .sequence = 0,
                .command_id = command.command_id,
                .download_id = command.id,
                .kind = EventKind::snapshot_changed,
                .result = Result::ok,
            });
        }
        emit_command_result_locked(command, result);
    }

    void emit_command_result_locked(const Command &command, Result result) {
        emit_locked(Event{
            .sequence = 0,
            .command_id = command.command_id,
            .download_id = command.id,
            .kind = EventKind::command_result,
            .result = result,
        });
    }

    void emit_locked(Event event) {
        event.sequence = next_event_sequence++;
        events.push_back(std::move(event));
    }

    EngineConfig config;
    mutable std::mutex mutex;
    std::condition_variable_any condition;
    std::deque<Command> commands;
    std::deque<Event> events;
    std::unordered_map<std::string, DownloadSnapshot> snapshots_by_id;
    std::unordered_set<std::string> pending_ids;
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

void sdm::Engine::shutdown() noexcept {
    impl_->shutdown();
}
