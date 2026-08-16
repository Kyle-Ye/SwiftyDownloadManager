#ifndef SDM_FILE_FINALIZER_H
#define SDM_FILE_FINALIZER_H

#include <filesystem>
#include <string>

namespace sdm {

/// Moves a completed partial file into its destination while coordinating with
/// iCloud Drive and File Provider implementations. The source remains intact
/// when the destination cannot be committed.
bool finalize_file(
    const std::filesystem::path &source,
    const std::filesystem::path &destination,
    bool replaces_existing,
    std::string &error_message
) noexcept;

} // namespace sdm

#endif
