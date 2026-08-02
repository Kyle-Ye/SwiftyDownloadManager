#include "SDMEngineDomain.h"

#include <algorithm>

namespace sdm {

std::vector<Segment> plan_segments(
    std::uint64_t content_length,
    std::uint32_t requested_connections,
    std::uint32_t maximum_connections
) {
    if (content_length == 0 || requested_connections == 0 ||
        maximum_connections == 0) {
        return {};
    }

    const auto bounded_connections = std::min(
        requested_connections,
        maximum_connections
    );
    const auto count = static_cast<std::uint32_t>(std::min<std::uint64_t>(
        bounded_connections,
        content_length
    ));
    const auto base_length = content_length / count;
    const auto remainder = content_length % count;

    std::vector<Segment> segments;
    segments.reserve(count);

    std::uint64_t start = 0;
    for (std::uint32_t ordinal = 0; ordinal < count; ++ordinal) {
        const auto length = base_length + (ordinal < remainder ? 1 : 0);
        const auto end = start + length - 1;
        segments.push_back(Segment{
            .ordinal = ordinal,
            .start = start,
            .end = end,
            .next = start,
        });
        start = end + 1;
    }

    return segments;
}

} // namespace sdm
