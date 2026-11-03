#ifndef CMACCARE_POWER_UI_H
#define CMACCARE_POWER_UI_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int32_t enabled;
    int32_t limit;
    // -1: unknown, 0: no Apple override, 1: Apple override/calibration active.
    int32_t calibration_override;
} MacCarePowerUIState;

enum {
    MACCARE_POWERUI_SUCCESS = 0,
    MACCARE_POWERUI_UNAVAILABLE = -1,
    MACCARE_POWERUI_INVALID_ABI = -2,
    MACCARE_POWERUI_INVALID_STATE = -3,
    MACCARE_POWERUI_INVALID_LIMIT = -4,
    MACCARE_POWERUI_CALL_FAILED = -5,
    MACCARE_POWERUI_VERIFICATION_FAILED = -6,
    MACCARE_POWERUI_EXCEPTION = -7,
    MACCARE_POWERUI_APPLE_OVERRIDE = -8
};

// Calls must be serialized by the helper's battery queue. Read performs no
// charge mutation. Every output is committed only after a complete valid read.
int32_t maccare_powerui_read(MacCarePowerUIState *state, int32_t *limits,
                           size_t capacity, size_t *count);
// Only limits returned by read are accepted. There is no backend fallback and
// no automatic retry after an unconfirmed mutation.
int32_t maccare_powerui_set_limit(int32_t limit);
// Only representable snapshots (disabled+100, enabled+80...99) are restored.
// A failure can follow an executed mutation; callers retain recovery state.
int32_t maccare_powerui_restore(int32_t enabled, int32_t limit);

#endif
