#include "SDMEngineBridge.h"

#include "SDMEngine.h"

uint32_t sdm_engine_abi_version(void) {
    return sdm::engine_abi_version;
}

const char *sdm_engine_version(void) {
    return sdm::Engine::version().data();
}
