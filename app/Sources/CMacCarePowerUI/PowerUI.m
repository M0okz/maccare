#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <math.h>
#include <notify.h>
#include <string.h>
#include <unistd.h>

#include "CMacCarePowerUI.h"

typedef NSError *__autoreleasing *MacCareErrorPointer;

// An independent, closed declaration of the runtime interface. No Apple
// private headers or third-party executable code are linked or embedded.
@protocol MacCarePowerUIClient <NSObject>
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end

static void releaseClient(id client) {
#if !__has_feature(objc_arc)
    [client release];
#else
    (void)client;
#endif
}

static BOOL hasMethod(Class cls, SEL selector, const char *returnType,
                      const char *argumentType, const char *secondArgumentType) {
    Method method = class_getInstanceMethod(cls, selector);
    unsigned int extra = argumentType == NULL ? 0 : (secondArgumentType == NULL ? 1 : 2);
    if (method == NULL || method_getNumberOfArguments(method) != extra + 2) return NO;
    char *actual = method_copyReturnType(method);
    BOOL valid = actual != NULL && strcmp(actual, returnType) == 0;
    free(actual);
    const char *types[] = { @encode(id), @encode(SEL), argumentType, secondArgumentType };
    for (unsigned int i = 0; valid && i < extra + 2; i++) {
        actual = method_copyArgumentType(method, i);
        valid = actual != NULL && strcmp(actual, types[i]) == 0;
        free(actual);
    }
    return valid;
}

static BOOL validInterface(Class cls) {
    return hasMethod(cls, @selector(initWithClientName:), @encode(id), @encode(id), NULL)
        && hasMethod(cls, @selector(isMCLSupported), @encode(BOOL), NULL, NULL)
        && hasMethod(cls, @selector(getMCLLimitWithError:), @encode(unsigned char), @encode(MacCareErrorPointer), NULL)
        && hasMethod(cls, @selector(isMCLCurrentlyEnabled:), @encode(unsigned long long), @encode(MacCareErrorPointer), NULL)
        && hasMethod(cls, @selector(availableChargeLimitsWithError:), @encode(id), @encode(MacCareErrorPointer), NULL)
        && hasMethod(cls, @selector(setMCLLimit:error:), @encode(BOOL), @encode(unsigned char), @encode(MacCareErrorPointer));
}

static id<MacCarePowerUIClient> newClient(int32_t *result) NS_RETURNS_RETAINED;
static id<MacCarePowerUIClient> newClient(int32_t *result) {
    if (@available(macOS 26.4, *)) {
        // The framework stays loaded. A process-local immutable class binding is
        // shared; clients and XPC connections are owned by one call only.
        static dispatch_once_t once;
        static Class nativeClass;
        dispatch_once(&once, ^{
            void *handle = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW | RTLD_LOCAL);
            if (handle != NULL) nativeClass = NSClassFromString(@"PowerUISmartChargeClient");
        });
        if (nativeClass == Nil) { *result = MACCARE_POWERUI_UNAVAILABLE; return nil; }
        if (!validInterface(nativeClass)) { *result = MACCARE_POWERUI_INVALID_ABI; return nil; }
        id<MacCarePowerUIClient> client = [(id<MacCarePowerUIClient>)[nativeClass alloc] initWithClientName:@"org.maccare.helper"];
        if (client == nil) { *result = MACCARE_POWERUI_UNAVAILABLE; return nil; }
        if (!validInterface(object_getClass(client))) {
            releaseClient(client);
            *result = MACCARE_POWERUI_INVALID_ABI;
            return nil;
        }
        *result = MACCARE_POWERUI_SUCCESS;
        return client;
    }
    *result = MACCARE_POWERUI_UNAVAILABLE;
    return nil;
}

static int32_t appleOverride(void) {
    int token = NOTIFY_TOKEN_INVALID;
    uint64_t state = 0;
    if (notify_register_check("com.apple.system.powersources.chargingtofulloverride", &token) != NOTIFY_STATUS_OK) return -1;
    uint32_t status = notify_get_state(token, &state);
    uint32_t cancelled = notify_cancel(token);
    if (status != NOTIFY_STATUS_OK || cancelled != NOTIFY_STATUS_OK) return -1;
    return state == 0 ? 0 : 1;
}

static int32_t readState(id<MacCarePowerUIClient> client, MacCarePowerUIState *state) {
    NSError *error = nil;
    unsigned char limit = [client getMCLLimitWithError:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    unsigned long long enabled = [client isMCLCurrentlyEnabled:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    if (limit < 80 || limit > 100 || enabled > 1) return MACCARE_POWERUI_INVALID_STATE;
    // Two matching reads prevent combining a limit and enable flag from an
    // observed concurrent update. External system clients cannot be locked here.
    unsigned char secondLimit = [client getMCLLimitWithError:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    unsigned long long secondEnabled = [client isMCLCurrentlyEnabled:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    if (limit != secondLimit || enabled != secondEnabled) return MACCARE_POWERUI_INVALID_STATE;
    state->limit = limit;
    state->enabled = (int32_t)enabled;
    state->calibration_override = appleOverride();
    return MACCARE_POWERUI_SUCCESS;
}

static int32_t readLimits(id<MacCarePowerUIClient> client, int32_t limits[21], size_t *count) {
    if (![client isMCLSupported]) return MACCARE_POWERUI_UNAVAILABLE;
    NSError *error = nil;
    id values = [client availableChargeLimitsWithError:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    if (![values isKindOfClass:[NSArray class]] || [values count] == 0 || [values count] > 21) return MACCARE_POWERUI_INVALID_STATE;
    BOOL present[21] = { NO };
    for (id value in values) {
        if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return MACCARE_POWERUI_INVALID_STATE;
        double numeric = [value doubleValue];
        if (!isfinite(numeric) || numeric < 80 || numeric > 100 || floor(numeric) != numeric) return MACCARE_POWERUI_INVALID_STATE;
        size_t index = (size_t)numeric - 80;
        if (present[index]) return MACCARE_POWERUI_INVALID_STATE;
        present[index] = YES;
    }
    // 100 must remain available so every admitted activation can be disabled.
    if (!present[20]) return MACCARE_POWERUI_INVALID_STATE;
    *count = 0;
    for (int32_t value = 80; value <= 100; value++) if (present[value - 80]) limits[(*count)++] = value;
    return MACCARE_POWERUI_SUCCESS;
}

static BOOL containsLimit(const int32_t *limits, size_t count, int32_t limit) {
    for (size_t i = 0; i < count; i++) if (limits[i] == limit) return YES;
    return NO;
}

int32_t maccare_powerui_read(MacCarePowerUIState *state, int32_t *limits, size_t capacity, size_t *count) {
    if (state == NULL || limits == NULL || count == NULL || capacity < 1 || capacity > 21) return MACCARE_POWERUI_INVALID_STATE;
    @autoreleasepool {
        id<MacCarePowerUIClient> client = nil;
        @try {
            int32_t result;
            client = newClient(&result);
            if (client == nil) return result;
            MacCarePowerUIState observed;
            int32_t observedLimits[21];
            size_t observedCount = 0;
            result = readLimits(client, observedLimits, &observedCount);
            if (result != MACCARE_POWERUI_SUCCESS) return result;
            if (observedCount > capacity) return MACCARE_POWERUI_INVALID_STATE;
            result = readState(client, &observed);
            if (result != MACCARE_POWERUI_SUCCESS) return result;
            if (!containsLimit(observedLimits, observedCount, observed.limit)) return MACCARE_POWERUI_INVALID_STATE;
            memcpy(limits, observedLimits, observedCount * sizeof(int32_t));
            *state = observed;
            *count = observedCount;
            return MACCARE_POWERUI_SUCCESS;
        } @catch (NSException *exception) {
            return MACCARE_POWERUI_EXCEPTION;
        } @finally {
            releaseClient(client);
        }
    }
}

static int32_t setLimit(int32_t limit) {
    if (limit < 80 || limit > 100) return MACCARE_POWERUI_INVALID_LIMIT;
    @autoreleasepool {
        id<MacCarePowerUIClient> client = nil;
        @try {
            int32_t result;
            client = newClient(&result);
            if (client == nil) return result;
            int32_t limits[21];
            size_t count = 0;
            result = readLimits(client, limits, &count);
            if (result != MACCARE_POWERUI_SUCCESS) return result;
            if (!containsLimit(limits, count, limit)) return MACCARE_POWERUI_INVALID_LIMIT;
            MacCarePowerUIState before;
            result = readState(client, &before);
            if (result != MACCARE_POWERUI_SUCCESS) return result;
            if (before.calibration_override != 0) return MACCARE_POWERUI_APPLE_OVERRIDE;
            int32_t expectedEnabled = limit < 100 ? 1 : 0;
            if (before.limit == limit && before.enabled == expectedEnabled) return MACCARE_POWERUI_SUCCESS;
            NSError *error = nil;
            BOOL success = [client setMCLLimit:(unsigned char)limit error:&error];
            if (!success || error != nil) return MACCARE_POWERUI_CALL_FAILED;
            MacCarePowerUIState after;
            result = readState(client, &after);
            if (result != MACCARE_POWERUI_SUCCESS) return MACCARE_POWERUI_VERIFICATION_FAILED;
            if (after.calibration_override != 0) return MACCARE_POWERUI_APPLE_OVERRIDE;
            if (after.limit != limit || after.enabled != expectedEnabled) return MACCARE_POWERUI_VERIFICATION_FAILED;
            return MACCARE_POWERUI_SUCCESS;
        } @catch (NSException *exception) {
            return MACCARE_POWERUI_EXCEPTION;
        } @finally {
            releaseClient(client);
        }
    }
}

int32_t maccare_powerui_set_limit(int32_t limit) { return setLimit(limit); }

int32_t maccare_powerui_restore(int32_t enabled, int32_t limit) {
    if ((enabled != 0 && enabled != 1) || limit < 80 || limit > 100 || (enabled == 0 && limit != 100) || (enabled == 1 && limit == 100)) return MACCARE_POWERUI_INVALID_STATE;
    return setLimit(limit);
}

int32_t maccare_powerui_calibration_override(void) { return appleOverride(); }

static int32_t readEnabled(id<MacCarePowerUIClient> client, unsigned long long *enabled) {
    NSError *error = nil;
    unsigned long long first = [client isMCLCurrentlyEnabled:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    error = nil;
    unsigned long long second = [client isMCLCurrentlyEnabled:&error];
    if (error != nil) return MACCARE_POWERUI_CALL_FAILED;
    if (first > 1 || first != second) return MACCARE_POWERUI_INVALID_STATE;
    *enabled = first;
    return MACCARE_POWERUI_SUCCESS;
}

static BOOL validPolicyInterface(Class cls) {
    return hasMethod(cls, @selector(enableMCL:), @encode(BOOL), @encode(MacCareErrorPointer), NULL)
        && hasMethod(cls, @selector(disableMCL:), @encode(BOOL), @encode(MacCareErrorPointer), NULL);
}

int32_t maccare_powerui_policy_is_available(void) {
    @autoreleasepool {
        id<MacCarePowerUIClient> client = nil;
        @try {
            int32_t result;
            client = newClient(&result);
            if (client == nil || !validPolicyInterface(object_getClass(client))) return 0;
            return [client isMCLSupported] ? 1 : 0;
        } @catch (NSException *exception) {
            return 0;
        } @finally {
            releaseClient(client);
        }
    }
}

int32_t maccare_powerui_clear_limit(void) {
    if (geteuid() != 0) return MACCARE_POWERUI_CALL_FAILED;
    @autoreleasepool {
        id<MacCarePowerUIClient> client = nil;
        @try {
            int32_t result;
            client = newClient(&result);
            if (client == nil) return result;
            if (!validPolicyInterface(object_getClass(client))) return MACCARE_POWERUI_INVALID_ABI;
            if (![client isMCLSupported]) return MACCARE_POWERUI_UNAVAILABLE;
            if (appleOverride() != 0) return MACCARE_POWERUI_APPLE_OVERRIDE;
            unsigned long long enabled;
            result = readEnabled(client, &enabled);
            if (result != MACCARE_POWERUI_SUCCESS) return result;
            NSError *error = nil;
            if (enabled == 0) {
                if (![client enableMCL:&error] || error != nil) return MACCARE_POWERUI_CALL_FAILED;
                result = readEnabled(client, &enabled);
                if (result != MACCARE_POWERUI_SUCCESS || enabled != 1) return MACCARE_POWERUI_VERIFICATION_FAILED;
            }
            if (appleOverride() != 0) return MACCARE_POWERUI_APPLE_OVERRIDE;
            error = nil;
            if (![client disableMCL:&error] || error != nil) return MACCARE_POWERUI_CALL_FAILED;
            result = readEnabled(client, &enabled);
            if (result != MACCARE_POWERUI_SUCCESS || enabled != 0) return MACCARE_POWERUI_VERIFICATION_FAILED;
            if (appleOverride() != 0) return MACCARE_POWERUI_APPLE_OVERRIDE;
            return MACCARE_POWERUI_SUCCESS;
        } @catch (NSException *exception) {
            return MACCARE_POWERUI_EXCEPTION;
        } @finally {
            releaseClient(client);
        }
    }
}

int32_t maccare_powerui_policy_preferences_changed(void) {
    if (geteuid() != 0) return MACCARE_POWERUI_CALL_FAILED;
    return notify_post("com.apple.smartcharging.defaultschanged") == NOTIFY_STATUS_OK
        ? MACCARE_POWERUI_SUCCESS : MACCARE_POWERUI_CALL_FAILED;
}
