#pragma once

#include <cstdint>
#include <string_view>

namespace sdm {

inline constexpr std::uint32_t engine_abi_version = 1;

class Engine final {
public:
    [[nodiscard]] static std::string_view version() noexcept;
};

} // namespace sdm
