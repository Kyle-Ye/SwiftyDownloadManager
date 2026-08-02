#include "SDMEngineBridge.h"

#include "SDMEngine.h"

#include <algorithm>
#include <cstring>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>
#include <utility>

struct sdm_engine {
    std::unique_ptr<sdm::Engine> value;
};

namespace {

sdm_result_t to_bridge_result(sdm::Result result) noexcept {
    return static_cast<sdm_result_t>(result);
}

std::string copy_string(sdm_string_view_t view) {
    if (view.length == 0) {
        return {};
    }
    if (view.data == nullptr) {
        throw std::invalid_argument("null string data");
    }
    return std::string(view.data, view.length);
}

template <std::size_t Capacity>
void copy_c_string(char (&destination)[Capacity], const std::string &source) {
    const auto count = std::min(source.size(), Capacity - 1);
    std::memcpy(destination, source.data(), count);
    destination[count] = '\0';
    if (count + 1 < Capacity) {
        std::memset(destination + count + 1, 0, Capacity - count - 1);
    }
}

void copy_event(const sdm::Event &source, sdm_event_t &destination) {
    destination = {};
    destination.struct_size = sizeof(sdm_event_t);
    destination.sequence = source.sequence;
    destination.command_id = source.command_id;
    destination.kind = static_cast<std::uint32_t>(source.kind);
    destination.result = static_cast<std::uint32_t>(source.result);
    copy_c_string(destination.download_id, source.download_id);
}

void copy_snapshot(
    const sdm::DownloadSnapshot &source,
    sdm_download_snapshot_t &destination
) {
    destination = {};
    destination.struct_size = sizeof(sdm_download_snapshot_t);
    destination.state = static_cast<std::uint32_t>(source.state);
    destination.content_length_known = source.content_length_known ? 1 : 0;
    destination.content_length = source.content_length;
    destination.downloaded_bytes = source.downloaded_bytes;
    destination.bytes_per_second = source.bytes_per_second;
    destination.estimated_seconds_remaining = source.estimated_seconds_remaining;
    destination.segment_count = source.segment_count;
    destination.error_code = static_cast<std::uint32_t>(source.error_code);
    destination.updated_milliseconds = source.updated_milliseconds;
    copy_c_string(destination.id, source.id);
    copy_c_string(destination.source_url, source.source_url);
    copy_c_string(destination.final_url, source.final_url);
    copy_c_string(destination.destination_url, source.destination_url);
    copy_c_string(destination.filename, source.filename);
    copy_c_string(destination.error_message, source.error_message);
}

} // namespace

uint32_t sdm_engine_abi_version(void) {
    return sdm::engine_abi_version;
}

const char *sdm_engine_version(void) {
    return sdm::Engine::version().data();
}

sdm_result_t sdm_engine_create(
    const sdm_engine_config_t *config,
    sdm_engine_t **out_engine
) {
    if (out_engine == nullptr) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }
    *out_engine = nullptr;
    if (config == nullptr || config->struct_size < sizeof(sdm_engine_config_t) ||
        config->abi_version != sdm::engine_abi_version ||
        config->maximum_active_downloads == 0 ||
        config->maximum_connections_per_download == 0) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        auto wrapper = std::make_unique<sdm_engine>();
        wrapper->value = std::make_unique<sdm::Engine>(sdm::EngineConfig{
            .database_path = copy_string(config->database_path),
            .temporary_directory = copy_string(config->temporary_directory),
            .maximum_active_downloads = config->maximum_active_downloads,
            .maximum_connections_per_download =
                config->maximum_connections_per_download,
        });
        *out_engine = wrapper.release();
        return SDM_RESULT_OK;
    } catch (const std::invalid_argument &) {
        return SDM_RESULT_INVALID_ARGUMENT;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}

void sdm_engine_shutdown(sdm_engine_t *engine) {
    if (engine != nullptr && engine->value) {
        engine->value->shutdown();
    }
}

void sdm_engine_destroy(sdm_engine_t *engine) {
    delete engine;
}

sdm_result_t sdm_engine_enqueue(
    sdm_engine_t *engine,
    const sdm_download_request_t *request,
    uint64_t *out_command_id
) {
    if (engine == nullptr || !engine->value || out_command_id == nullptr ||
        request == nullptr || request->struct_size < sizeof(sdm_download_request_t)) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        return to_bridge_result(engine->value->enqueue(
            sdm::DownloadRequest{
                .id = copy_string(request->id),
                .url = copy_string(request->url),
                .destination_directory = copy_string(request->destination_directory),
                .filename = copy_string(request->filename),
                .connection_limit = request->connection_limit,
                .bandwidth_limit = request->bandwidth_limit,
                .conflict_policy = request->conflict_policy,
            },
            *out_command_id
        ));
    } catch (const std::invalid_argument &) {
        return SDM_RESULT_INVALID_ARGUMENT;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}

sdm_result_t sdm_engine_submit(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_command_t command,
    uint64_t *out_command_id
) {
    if (engine == nullptr || !engine->value || out_command_id == nullptr ||
        command < SDM_COMMAND_PAUSE || command > SDM_COMMAND_REMOVE) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        return to_bridge_result(engine->value->submit(
            copy_string(download_id),
            static_cast<sdm::CommandKind>(command),
            *out_command_id
        ));
    } catch (const std::invalid_argument &) {
        return SDM_RESULT_INVALID_ARGUMENT;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}

sdm_result_t sdm_engine_poll_events(
    sdm_engine_t *engine,
    sdm_event_t *events,
    size_t capacity,
    size_t *out_count
) {
    if (engine == nullptr || !engine->value || out_count == nullptr ||
        (capacity > 0 && events == nullptr)) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        const auto values = engine->value->poll_events(capacity);
        for (std::size_t index = 0; index < values.size(); ++index) {
            copy_event(values[index], events[index]);
        }
        *out_count = values.size();
        return SDM_RESULT_OK;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}

sdm_result_t sdm_engine_copy_snapshot(
    sdm_engine_t *engine,
    sdm_string_view_t download_id,
    sdm_download_snapshot_t *out_snapshot
) {
    if (engine == nullptr || !engine->value || out_snapshot == nullptr) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        const auto value = engine->value->snapshot(copy_string(download_id));
        if (!value) {
            return SDM_RESULT_NOT_FOUND;
        }
        copy_snapshot(*value, *out_snapshot);
        return SDM_RESULT_OK;
    } catch (const std::invalid_argument &) {
        return SDM_RESULT_INVALID_ARGUMENT;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}

sdm_result_t sdm_engine_copy_snapshots(
    sdm_engine_t *engine,
    sdm_download_snapshot_t *snapshots,
    size_t capacity,
    size_t *out_count
) {
    if (engine == nullptr || !engine->value || out_count == nullptr ||
        (capacity > 0 && snapshots == nullptr)) {
        return SDM_RESULT_INVALID_ARGUMENT;
    }

    try {
        const auto values = engine->value->snapshots();
        *out_count = values.size();
        if (capacity == 0) {
            return SDM_RESULT_OK;
        }
        const auto count = std::min(values.size(), capacity);
        for (std::size_t index = 0; index < count; ++index) {
            copy_snapshot(values[index], snapshots[index]);
        }
        return capacity < values.size()
            ? SDM_RESULT_INVALID_ARGUMENT
            : SDM_RESULT_OK;
    } catch (...) {
        return SDM_RESULT_INTERNAL_ERROR;
    }
}
