// Short-lived MobileDevice adapter. Default mode only reads; Wi-Fi changes require explicit arguments.
// Private ABI: loaded optionally, isolated from the app, bounded by alarm(6).
// Protocol references and compatibility limits: docs/research/apple-device-batteries.md.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void *Device;
typedef struct __attribute__((packed)) { Device device; uint32_t message; } DeviceEvent;
typedef void (*DeviceCallback)(DeviceEvent *, void *);
static int32_t (*subscribe)(DeviceCallback, uint32_t, uint32_t, void *, void **, CFDictionaryRef);
static int32_t (*unsubscribe)(void *);
// Ownership operations: ignore the return register, which is not an error-status contract.
static void (*retainDevice)(Device), (*releaseDevice)(Device);
static int32_t (*connectDevice)(Device), (*disconnectDevice)(Device), (*isPaired)(Device);
static int32_t (*validatePairing)(Device), (*startSession)(Device), (*stopSession)(Device);
static CFTypeRef (*copyValue)(Device, CFStringRef, CFStringRef);
static CFStringRef (*copyIdentifier)(Device);
static int32_t (*setWirelessFlags)(Device, long);
static int32_t (*interfaceType)(Device);
static int32_t (*getWirelessFlags)(Device, long *);
static int32_t (*startService)(Device, CFStringRef, void *, void **);
static uint64_t (*sendMessage)(void *, CFPropertyListRef, CFPropertyListFormat);
static uint64_t (*receiveMessage)(void *, CFPropertyListRef *, CFPropertyListFormat *);
static void (*invalidateService)(void *);
static NSMutableArray<NSValue *> *devices;
static BOOL collecting;
typedef enum { ReadBattery, ListWiFi, SetWiFi } Operation;
static Operation operation = ReadBattery;
static NSString *targetID;
static BOOL requestedWiFi;
static BOOL targetFound, writeSucceeded;

static BOOL configureArguments(NSArray<NSString *> *arguments) {
    operation = ReadBattery; targetID = nil; targetFound = writeSucceeded = NO;
    if (arguments.count == 0) return YES;
    if (arguments.count == 1 && [arguments[0] isEqualToString:@"--list-wifi"]) { operation = ListWiFi; return YES; }
    if (arguments.count != 3 || ![arguments[0] isEqualToString:@"--set-wifi"]) return NO;
    NSString *identifier = arguments[1], *setting = arguments[2];
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (identifier.length != 64 || [identifier rangeOfCharacterFromSet:invalid].location != NSNotFound ||
        ![@[@"on", @"off"] containsObject:setting]) return NO;
    operation = SetWiFi; targetID = identifier; requestedWiFi = [setting isEqualToString:@"on"];
    return YES;
}

static void emit(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (data && data.length < 4096) {
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        fflush(stdout); // Preserve phone results even if the subsequent Watch service times out.
    }
}

static NSNumber *percentage(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 && number <= 100 ? @((int)round(number)) : nil;
}

static NSString *stringValue(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length && text.length <= 128 ? text : nil;
}

static NSString *localID(NSString *identifier) {
    NSData *data = [identifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

static void deviceEvent(DeviceEvent *event, void *context) {
    if (!collecting || !event || !event->device) return;
    NSValue *value = [NSValue valueWithPointer:event->device];
    if (event->message == 1 && ![devices containsObject:value] && devices.count < 4) {
        retainDevice(event->device);
        [devices addObject:value];
    } else if (event->message == 2 && [devices containsObject:value]) {
        [devices removeObject:value];
        releaseDevice(event->device);
    }
}

static id value(Device device, NSString *domain, NSString *key) {
    return CFBridgingRelease(copyValue(device, (__bridge CFStringRef)domain, (__bridge CFStringRef)key));
}

static NSNumber *wifiValue(Device device, long *originalFlags) {
    long flags = 0;
    if (!getWirelessFlags || getWirelessFlags(device, &flags) != 0 || flags < 0) return nil;
    if (originalFlags) *originalFlags = flags;
    return (flags & 0x2) ? @YES : @NO;
}

static void readWiFi(Device device, NSString *identifier, NSString *kind) {
    NSString *hashed = localID(identifier);
    if (operation == SetWiFi && ![hashed isEqualToString:targetID]) return;
    BOOL usb = interfaceType && interfaceType(device) == 1;
    long flags = 0;
    NSNumber *enabled = wifiValue(device, &flags);
    if (operation == SetWiFi) {
        targetFound = YES;
        // Initialize this trusted host's wireless identity when enabling, not only the device-wide flag.
        // Preserve all other flags; disabling keeps the existing host identity intact.
        if (usb && enabled && setWirelessFlags) {
            long desiredFlags = requestedWiFi ? (flags | 0x3) : (flags & ~0x2L);
            int32_t status = setWirelessFlags(device, desiredFlags);
            enabled = wifiValue(device, NULL);
            writeSucceeded = status == 0 && enabled && enabled.boolValue == requestedWiFi;
        }
    }
    NSString *name = stringValue(value(device, nil, @"DeviceName")) ?: kind;
    emit(@{@"id": hashed, @"name": name, @"wifiEnabled": enabled ?: NSNull.null,
           @"usbConnected": @(usb), @"canConfigure": @((BOOL)(usb && enabled && setWirelessFlags != NULL))});
}

static NSDictionary *exchange(void *service, NSDictionary *request) {
    if (sendMessage(service, (__bridge CFDictionaryRef)request, kCFPropertyListXMLFormat_v1_0) != 0) return nil;
    CFPropertyListRef response = NULL;
    CFPropertyListFormat format = kCFPropertyListXMLFormat_v1_0;
    uint64_t status = receiveMessage(service, &response, &format);
    id object = CFBridgingRelease(response);
    return status == 0 && [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSDictionary *companionRequest(Device device, NSDictionary *request) {
    void *service = NULL;
    if (startService(device, CFSTR("com.apple.companion_proxy"), NULL, &service) != 0 || !service) return nil;
    @try {
        // companion_proxy handles one request per service connection on the tested iPhone.
        return exchange(service, request);
    } @finally {
        invalidateService(service);
        CFRelease(service);
    }
}

static id watchValue(Device device, NSString *identifier, NSString *key) {
    NSDictionary *response = companionRequest(device, @{@"Command": @"GetValueFromRegistry",
        @"GetValueGizmoUDIDKey": identifier, @"GetValueKeyKey": key});
    id payload = response[@"RetrievedValueDictionary"];
    return [payload isKindOfClass:NSDictionary.class] ? payload[key] : payload;
}

static void readWatches(Device device, NSString *phoneID) {
    if (!startService || !sendMessage || !receiveMessage || !invalidateService) return;
    id registry = companionRequest(device, @{@"Command": @"GetDeviceRegistry"})[@"PairedDevicesArray"];
    if (![registry isKindOfClass:NSArray.class]) return;
    NSUInteger count = 0;
    for (id item in registry) {
        if (++count > 4) break;
        NSString *identifier = stringValue(item);
        if (!identifier) continue;
        NSNumber *level = percentage(watchValue(device, identifier, @"BatteryCurrentCapacity"));
        if (!level) continue;
        NSString *name = stringValue(watchValue(device, identifier, @"DeviceName")) ?: @"Apple Watch";
        emit(@{@"id": localID([phoneID stringByAppendingString:identifier]), @"name": name,
               @"kind": @"watch", @"percent": level, @"viaPhone": @YES});
    }
}

static void readDevice(Device device) {
    // No pairing call or implicit Wi-Fi change; sessions require existing trust.
    if (connectDevice(device) != 0) return;
    BOOL session = NO;
    @try {
        if (isPaired(device) != 1 || validatePairing(device) != 0 || startSession(device) != 0) return;
        session = YES;
        NSString *kind = stringValue(value(device, nil, @"DeviceClass"));
        if (![@[@"iPhone", @"iPad"] containsObject:kind]) return;
        NSString *identifier = stringValue(CFBridgingRelease(copyIdentifier(device)));
        if (!identifier) return;
        if (operation != ReadBattery) { readWiFi(device, identifier, kind); return; }
        NSNumber *level = percentage(value(device, @"com.apple.mobile.battery", @"BatteryCurrentCapacity"));
        if (level) {
            NSString *name = stringValue(value(device, nil, @"DeviceName")) ?: kind;
            emit(@{@"id": localID(identifier), @"name": name, @"kind": kind.lowercaseString,
                   @"percent": level, @"viaPhone": @NO});
        }
        if ([kind isEqualToString:@"iPhone"]) readWatches(device, identifier);
    } @finally {
        if (session) stopSession(device);
        disconnectDevice(device);
    }
}

static BOOL collectReadings(void) {
    devices = [NSMutableArray new];
    collecting = YES;
    void *subscription = NULL;
    NSDictionary *options = @{@"NotificationOptionSearchForPairedDevices": @YES};
    if (subscribe(deviceEvent, 0, 0, NULL, &subscription, (__bridge CFDictionaryRef)options) != 0) { collecting = NO; return NO; }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.75, false);
    collecting = NO;
    // Keep the observer owning discovery alive until all sessions finish.
    // Freeze the bounded device list while synchronous calls may pump the run loop.
    for (NSValue *entry in devices) readDevice(entry.pointerValue);
    unsubscribe(subscription);
    for (NSValue *entry in devices) releaseDevice(entry.pointerValue);
    return YES;
}

#ifndef MACCARE_BATTERY_PROBE_TEST
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableArray *arguments = [NSMutableArray new];
        for (int index = 1; index < argc; index++) [arguments addObject:[NSString stringWithUTF8String:argv[index]]];
        if (!configureArguments(arguments)) { emit(@{@"status": @"invalidArguments"}); return 2; }
        alarm(6); // Leave room for measured Wi-Fi latency; still bound direct CLI use and private ABI hangs.
        void *library = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_LAZY | RTLD_LOCAL);
        if (!library) { emit(@{@"status": @"unavailable"}); return 0; }
#define LOAD(variable, symbol) variable = dlsym(library, symbol)
        LOAD(subscribe, "AMDeviceNotificationSubscribeWithOptions");
        LOAD(unsubscribe, "AMDeviceNotificationUnsubscribe");
        LOAD(retainDevice, "AMDeviceRetain"); LOAD(releaseDevice, "AMDeviceRelease");
        LOAD(connectDevice, "AMDeviceConnect"); LOAD(disconnectDevice, "AMDeviceDisconnect");
        LOAD(isPaired, "AMDeviceIsPaired"); LOAD(validatePairing, "AMDeviceValidatePairing");
        LOAD(startSession, "AMDeviceStartSession"); LOAD(stopSession, "AMDeviceStopSession");
        LOAD(copyValue, "AMDeviceCopyValue"); LOAD(copyIdentifier, "AMDeviceCopyDeviceIdentifier");
        LOAD(setWirelessFlags, "AMDeviceSetWirelessBuddyFlags"); LOAD(interfaceType, "AMDeviceGetInterfaceType");
        LOAD(getWirelessFlags, "AMDeviceGetWirelessBuddyFlags");
        LOAD(startService, "AMDeviceSecureStartService"); LOAD(sendMessage, "AMDServiceConnectionSendMessage");
        LOAD(receiveMessage, "AMDServiceConnectionReceiveMessage"); LOAD(invalidateService, "AMDServiceConnectionInvalidate");
#undef LOAD
        if (!subscribe || !unsubscribe || !retainDevice || !releaseDevice || !connectDevice || !disconnectDevice ||
            !isPaired || !validatePairing || !startSession || !stopSession || !copyValue || !copyIdentifier) {
            emit(@{@"status": @"unavailable"}); return 0;
        }
        if (!collectReadings()) {
            emit(@{@"status": @"unavailable"}); return 0;
        }
        NSString *status = operation != SetWiFi || writeSucceeded ? @"complete" : targetFound ? @"writeFailed" : @"targetUnavailable";
        emit(@{@"status": status});
        alarm(0);
        // The system framework may have registered process-lifetime callbacks; leave it mapped until exit.
        return 0;
    }
}
#endif
