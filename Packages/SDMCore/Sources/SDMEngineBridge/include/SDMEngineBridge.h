#ifndef SDM_ENGINE_BRIDGE_UMBRELLA_H
#define SDM_ENGINE_BRIDGE_UMBRELLA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t sdm_engine_abi_version(void);
const char *sdm_engine_version(void);

#ifdef __cplusplus
}
#endif

#endif
