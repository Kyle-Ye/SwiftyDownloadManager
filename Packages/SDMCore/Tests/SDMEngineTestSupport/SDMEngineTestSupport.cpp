#include "SDMEngineTestSupport.h"

#include "SDMEngineDomain.h"

#include <algorithm>

size_t sdm_test_plan_segments(
    uint64_t content_length,
    uint32_t requested_connections,
    uint32_t maximum_connections,
    sdm_test_segment_t *segments,
    size_t capacity
) {
    const auto plan = sdm::plan_segments(
        content_length,
        requested_connections,
        maximum_connections
    );
    const auto count = std::min(plan.size(), capacity);
    for (size_t index = 0; index < count; ++index) {
        segments[index] = sdm_test_segment_t{
            .ordinal = plan[index].ordinal,
            .start = plan[index].start,
            .end = plan[index].end,
            .next = plan[index].next,
        };
    }
    return plan.size();
}

bool sdm_test_can_transition(uint32_t from, uint32_t to) {
    return sdm::can_transition(
        static_cast<sdm::DownloadState>(from),
        static_cast<sdm::DownloadState>(to)
    );
}

uint32_t sdm_test_validate_command(uint32_t state, uint32_t command) {
    return static_cast<uint32_t>(sdm::validate_command(
        static_cast<sdm::DownloadState>(state),
        static_cast<sdm::CommandKind>(command)
    ));
}
