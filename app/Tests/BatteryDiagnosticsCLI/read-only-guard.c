// Test-only interposition for the unsigned development helper. Fail before any
// SMC write, preferences mutation, notification post, or battery service startup.
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

static void forbidden(void) {
    fputs("forbidden diagnostic side effect\n", stderr);
    _exit(86);
}
__attribute__((constructor)) static void loaded(void) {
    if (geteuid() == 0) _exit(87); // This smoke test never runs as root.
    fputs("read-only guard loaded\n", stderr);
}
static kern_return_t guardedCall(mach_port_t connection, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize) {
    // SMCMessage ABI: 80 bytes, command byte at offset 42. Only metadata/read.
    if (selector == 2 && inputSize == 80 && input) {
        uint8_t command = ((const uint8_t *)input)[42];
        if (command != 5 && command != 9) forbidden();
    }
    // dyld does not interpose references from the image defining the replacement.
    return IOConnectCallStructMethod(connection, selector, input, inputSize, output, outputSize);
}
static io_connect_t guardedPower(void *refcon, IONotificationPortRef *port,
    IOServiceInterestCallback callback, io_object_t *notifier) { forbidden(); return 0; }
static void guardedPrefs(CFStringRef key, CFPropertyListRef value, CFStringRef app,
    CFStringRef user, CFStringRef host) { forbidden(); }
static void guardedMultiple(CFDictionaryRef set, CFArrayRef remove, CFStringRef app,
    CFStringRef user, CFStringRef host) { forbidden(); }
static void guardedAppPrefs(CFStringRef key, CFPropertyListRef value, CFStringRef app) { forbidden(); }
static uint32_t guardedPost(const char *name) { forbidden(); return 0; }
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *newFunction; const void *oldFunction; } \
    pair_##original __attribute__((section("__DATA,__interpose"))) = { (void *)&replacement, (void *)&original }
INTERPOSE(guardedCall, IOConnectCallStructMethod);
INTERPOSE(guardedPower, IORegisterForSystemPower);
INTERPOSE(guardedPrefs, CFPreferencesSetValue);
INTERPOSE(guardedMultiple, CFPreferencesSetMultiple);
INTERPOSE(guardedAppPrefs, CFPreferencesSetAppValue);
INTERPOSE(guardedPost, notify_post);
