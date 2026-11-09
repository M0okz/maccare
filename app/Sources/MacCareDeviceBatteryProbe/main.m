// Read-only, short-lived MobileDevice adapter. No pairing or preference setters.
// Private ABI: loaded optionally, isolated from the app, bounded by alarm(4).
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
static int32_t (*retainDevice)(Device), (*releaseDevice)(Device);
static int32_t (*connectDevice)(Device), (*disconnectDevice)(Device), (*isPaired)(Device);
static int32_t (*validatePairing)(Device), (*startSession)(Device), (*stopSession)(Device);
static CFTypeRef (*copyValue)(Device, CFStringRef, CFStringRef);
static CFStringRef (*copyIdentifier)(Device);
static int32_t (*startService)(Device, CFStringRef, void *, void **);
static uint64_t (*sendMessage)(void *, CFPropertyListRef, CFPropertyListFormat);
static uint64_t (*receiveMessage)(void *, CFPropertyListRef *, CFPropertyListFormat *);
static void (*invalidateService)(void *);
static NSMutableArray<NSValue *> *devices;

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
    if (!event || !event->device) return;
    NSValue *value = [NSValue valueWithPointer:event->device];
    if (event->message == 1 && ![devices containsObject:value] && devices.count < 4) {
        if (retainDevice(event->device) == 0) [devices addObject:value];
    } else if (event->message == 2 && [devices containsObject:value]) {
        [devices removeObject:value];
        releaseDevice(event->device);
    }
}

static id value(Device device, NSString *domain, NSString *key) {
    return CFBridgingRelease(copyValue(device, (__bridge CFStringRef)domain, (__bridge CFStringRef)key));
}

static NSDictionary *exchange(void *service, NSDictionary *request) {
    if (sendMessage(service, (__bridge CFDictionaryRef)request, kCFPropertyListXMLFormat_v1_0) != 0) return nil;
    CFPropertyListRef response = NULL;
    CFPropertyListFormat format = kCFPropertyListXMLFormat_v1_0;
    uint64_t status = receiveMessage(service, &response, &format);
    id object = CFBridgingRelease(response);
    return status == 0 && [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static id watchValue(void *service, NSString *identifier, NSString *key) {
    NSDictionary *response = exchange(service, @{@"Command": @"GetValueFromRegistry",
        @"GetValueGizmoUDIDKey": identifier, @"GetValueKeyKey": key});
    id payload = response[@"RetrievedValueDictionary"];
    return [payload isKindOfClass:NSDictionary.class] ? payload[key] : payload;
}

static void readWatches(Device device, NSString *phoneID) {
    if (!startService || !sendMessage || !receiveMessage || !invalidateService) return;
    void *service = NULL;
    if (startService(device, CFSTR("com.apple.companion_proxy"), NULL, &service) != 0 || !service) return;
    @try {
        id registry = exchange(service, @{@"Command": @"GetDeviceRegistry"})[@"PairedDevicesArray"];
        if (![registry isKindOfClass:NSArray.class]) return;
        NSUInteger count = 0;
        for (id item in registry) {
            if (++count > 4) break;
            NSString *identifier = stringValue(item);
            if (!identifier) continue;
            NSNumber *level = percentage(watchValue(service, identifier, @"BatteryCurrentCapacity"));
            if (!level) continue;
            NSString *name = stringValue(watchValue(service, identifier, @"DeviceName")) ?: @"Apple Watch";
            emit(@{@"id": localID([phoneID stringByAppendingString:identifier]), @"name": name,
                   @"kind": @"watch", @"percent": level, @"viaPhone": @YES});
        }
    } @finally {
        invalidateService(service);
        CFRelease(service);
    }
}

static void readDevice(Device device) {
    // Never call AMDevicePair, enable Wi-Fi sync, or prompt an untrusted phone.
    if (connectDevice(device) != 0) return;
    BOOL session = NO;
    @try {
        if (isPaired(device) != 1 || validatePairing(device) != 0 || startSession(device) != 0) return;
        session = YES;
        NSString *kind = stringValue(value(device, nil, @"DeviceClass"));
        if (![@[@"iPhone", @"iPad"] containsObject:kind]) return;
        NSString *identifier = stringValue(CFBridgingRelease(copyIdentifier(device)));
        if (!identifier) return;
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

#ifndef MACCARE_BATTERY_PROBE_TEST
int main(void) {
    @autoreleasepool {
        alarm(4); // Also bound direct CLI use and a missing/changed private ABI.
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
        LOAD(startService, "AMDeviceSecureStartService"); LOAD(sendMessage, "AMDServiceConnectionSendMessage");
        LOAD(receiveMessage, "AMDServiceConnectionReceiveMessage"); LOAD(invalidateService, "AMDServiceConnectionInvalidate");
#undef LOAD
        if (!subscribe || !unsubscribe || !retainDevice || !releaseDevice || !connectDevice || !disconnectDevice ||
            !isPaired || !validatePairing || !startSession || !stopSession || !copyValue || !copyIdentifier) {
            emit(@{@"status": @"unavailable"}); return 0;
        }
        devices = [NSMutableArray new];
        void *subscription = NULL;
        NSDictionary *options = @{@"NotificationOptionSearchForPairedDevices": @YES};
        if (subscribe(deviceEvent, 0, 0, NULL, &subscription, (__bridge CFDictionaryRef)options) != 0) {
            emit(@{@"status": @"unavailable"}); return 0;
        }
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.75, false);
        // Stop discovery before synchronous reads; the retained device references remain valid.
        unsubscribe(subscription);
        for (NSValue *entry in devices) { readDevice(entry.pointerValue); releaseDevice(entry.pointerValue); }
        emit(@{@"status": @"complete"});
        alarm(0);
        // The system framework may have registered process-lifetime callbacks; leave it mapped until exit.
        return 0;
    }
}
#endif
