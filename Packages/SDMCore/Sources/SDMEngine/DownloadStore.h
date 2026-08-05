#pragma once

#include "SDMEngine.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace sdm {

struct PersistedDownload final {
    DownloadRequest request;
    DownloadSnapshot snapshot;
    std::string temporary_path;
    bool accepts_ranges = false;
    std::string etag;
    std::string last_modified;
};

class DownloadStore final {
public:
    explicit DownloadStore(const std::string &path);
    ~DownloadStore();

    DownloadStore(const DownloadStore &) = delete;
    DownloadStore &operator=(const DownloadStore &) = delete;

    [[nodiscard]] std::vector<PersistedDownload> load_all();
    [[nodiscard]] std::vector<DiagnosticEvent> load_events(
        const std::string &download_id
    );
    [[nodiscard]] DiagnosticEvent append_event(
        const std::string &download_id,
        std::uint64_t timestamp_milliseconds,
        DiagnosticLevel level,
        std::uint32_t code,
        const std::string &message
    );
    void save(const PersistedDownload &download);
    void remove(const std::string &id);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace sdm
