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
    std::uint32_t server_connection_limit = 1;
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
    void save(const PersistedDownload &download);
    void remove(const std::string &id);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace sdm
