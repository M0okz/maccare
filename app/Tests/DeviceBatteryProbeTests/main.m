#define MACCARE_BATTERY_PROBE_TEST 1
#include "../../Sources/MacCareDeviceBatteryProbe/main.m"
#include <assert.h>

static int paired, validationStatus, sessionStatus, connects, disconnects, starts, stops, validations, serviceCloses;
static BOOL isPhone = YES;
static BOOL subscriptionActive = YES;
static int messagesOnConnection;
static NSDictionary *lastRequest;
static NSMutableArray *requests;
static int32_t connected(Device d) { connects++; return subscriptionActive ? 0 : -1; }
static void retained(Device d) { }
static int32_t subscribed(DeviceCallback callback, uint32_t a, uint32_t b, void *context, void **subscription, CFDictionaryRef options) {
    subscriptionActive = YES; *subscription = (void *)1;
    DeviceEvent event = {.device = (Device)1, .message = 1};
    callback(&event, NULL); return 0;
}
static int32_t unsubscribed(void *subscription) { subscriptionActive = NO; return 0; }
static int32_t disconnected(Device d) { disconnects++; return 0; }
static int32_t pairedStatus(Device d) { return paired; }
static int32_t validated(Device d) { validations++; return validationStatus; }
static int32_t sessionStarted(Device d) { starts++; return sessionStatus; }
static int32_t sessionStopped(Device d) { stops++; return 0; }
static CFStringRef identifier(Device d) { return CFRetain(CFSTR("test-phone-only")); }
static CFTypeRef copied(Device d, CFStringRef domain, CFStringRef key) {
    NSString *name = (__bridge NSString *)key;
    if ([name isEqual:@"DeviceClass"]) return CFRetain(isPhone ? CFSTR("iPhone") : CFSTR("AppleTV"));
    if ([name isEqual:@"DeviceName"]) return CFRetain(CFSTR("iPhone QA"));
    assert(CFEqual(domain, CFSTR("com.apple.mobile.battery")));
    assert([name isEqual:@"BatteryCurrentCapacity"]);
    return CFBridgingRetain(@80);
}
static int32_t serviceStarted(Device d, CFStringRef name, void *options, void **connection) {
    assert(CFEqual(name, CFSTR("com.apple.companion_proxy")));
    assert(options == NULL);
    *connection = (void *)CFBridgingRetain(@{});
    messagesOnConnection = 0;
    return 0;
}
static void serviceClosed(void *connection) { serviceCloses++; }
static uint64_t sent(void *connection, CFPropertyListRef object, CFPropertyListFormat format) {
    lastRequest = (__bridge NSDictionary *)object;
    NSString *command = lastRequest[@"Command"];
    assert([command isEqual:@"GetDeviceRegistry"] || [command isEqual:@"GetValueFromRegistry"]);
    [requests addObject:lastRequest];
    if (messagesOnConnection++ > 0) return 1; // The registry service closes after one response.
    return 0;
}
static uint64_t received(void *connection, CFPropertyListRef *response, CFPropertyListFormat *format) {
    if ([lastRequest[@"Command"] isEqual:@"GetDeviceRegistry"]) {
        *response = CFBridgingRetain(@{@"PairedDevicesArray": @[@"watch-fixture"]});
    } else {
        assert([lastRequest[@"GetValueGizmoUDIDKey"] isEqual:@"watch-fixture"]);
        NSString *key = lastRequest[@"GetValueKeyKey"];
        assert([key isEqual:@"BatteryCurrentCapacity"] || [key isEqual:@"DeviceName"]);
        id object = [key isEqual:@"DeviceName"] ? @"Watch QA" : @65;
        *response = CFBridgingRetain(@{@"RetrievedValueDictionary": @{key: object}});
    }
    return 0;
}
static void reset(void) {
    paired = 1; validationStatus = sessionStatus = 0;
    connects = disconnects = starts = stops = validations = serviceCloses = 0;
    isPhone = YES; subscriptionActive = YES; requests = [NSMutableArray new];
    startService = NULL;
}
int main(void) {
    @autoreleasepool {
        connectDevice = connected; disconnectDevice = disconnected;
        isPaired = pairedStatus; validatePairing = validated;
        startSession = sessionStarted; stopSession = sessionStopped;
        copyValue = copied; copyIdentifier = identifier;
        reset(); paired = 0; readDevice((Device)1);
        assert(connects == 1 && disconnects == 1 && validations == 0 && starts == 0 && stops == 0);
        reset(); validationStatus = -1; readDevice((Device)1);
        assert(disconnects == 1 && validations == 1 && starts == 0 && stops == 0);
        reset(); sessionStatus = -1; readDevice((Device)1);
        assert(disconnects == 1 && starts == 1 && stops == 0);
        reset(); isPhone = NO; readDevice((Device)1);
        assert(disconnects == 1 && starts == 1 && stops == 1);
        reset(); readDevice((Device)1);
        assert(disconnects == 1 && starts == 1 && stops == 1);
        reset(); startService = serviceStarted; invalidateService = serviceClosed;
        sendMessage = sent; receiveMessage = received;
        readDevice((Device)1);
        assert(serviceCloses == 3 && requests.count == 3 && stops == 1 && disconnects == 1);
        assert(percentage(@YES) == nil && percentage(@(-1)) == nil && percentage(@101) == nil);
        assert(percentage(@(NAN)) == nil && percentage(@0).intValue == 0);
        assert(percentage(@100).intValue == 100);
        assert(stringValue(@"   ") == nil && stringValue(@1) == nil);
        reset(); subscribe = subscribed; unsubscribe = unsubscribed;
        retainDevice = retained; releaseDevice = retained;
        assert(collectReadings());
        assert(starts == 1 && stops == 1 && disconnects == 1 && !subscriptionActive);
        fputs("Device battery trust, cleanup and protocol fixtures passed\n", stderr);
    }
}
