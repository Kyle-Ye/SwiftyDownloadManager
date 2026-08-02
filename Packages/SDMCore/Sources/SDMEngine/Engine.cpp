#include "SDMEngine.h"

static_assert(sdm::engine_abi_version > 0);

std::string_view sdm::Engine::version() noexcept {
    return "0.1.0-dev";
}
