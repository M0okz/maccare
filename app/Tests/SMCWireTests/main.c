// A bounded IOKit driver fixture. Never opens a real driver or writes hardware.
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <assert.h>
#include <stdio.h>
#include <sys/sysctl.h>
#include <dlfcn.h>
#define IOConnectCallMethod fixtureMethod
#define IOConnectCallStructMethod fixtureCall
#define IOServiceGetMatchingService fixtureMatch
#define IOServiceOpen fixtureOpen
#define IOObjectRelease fixtureRelease
#define IOServiceClose fixtureClose
#define dlsym fixtureSymbol
#define sysctlbyname fixtureSysctl
static void *fixtureSymbol(void *, const char *);
static int fixtureSysctl(const char *, void *, size_t *, void *, size_t);
static kern_return_t fixtureMethod(mach_port_t, uint32_t, const uint64_t *, uint32_t, const void *, size_t, uint64_t *, uint32_t *, void *, size_t *);
static kern_return_t fixtureCall(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
static io_service_t fixtureMatch(mach_port_t, CFDictionaryRef);
static kern_return_t fixtureOpen(io_service_t, task_port_t, uint32_t, io_connect_t *);
static kern_return_t fixtureRelease(io_object_t);
static kern_return_t fixtureClose(io_connect_t);
#include "../../Sources/CMacCareSMC/MacCareSMC.c"

typedef struct { const char *key; uint32_t size, type; uint8_t bytes[32]; int denyRead, denyWrite; } Field;
static Field fields[10];
static int fieldCount, writes, opens, closes, wrongReadback, failingWrite;
static int clientOpen, handshakeError, handshakeCalls;
static uint32_t clientTransport;
static int temperatureClient;
static uint32_t writeKeys[64];
static const char *fixtureBrand = "Apple M1 Max";
static int fixtureARM = 1;
static int hidMode;
static CFTypeRef hidCreate(CFAllocatorRef allocator) { return CFRetain(CFSTR("fixture-client")); }
static int hidMatch(CFTypeRef client, CFDictionaryRef dictionary) { return 0; }
static CFArrayRef hidServices(CFTypeRef client) {
    const void *names[] = {CFSTR("pACC MTR Temp Sensor0"), CFSTR("GPU MTR Temp Sensor0"), CFSTR("GPU MTR Temp Sensor1")};
    return CFArrayCreate(NULL, names, 3, &kCFTypeArrayCallBacks);
}
static CFTypeRef hidProperty(CFTypeRef service, CFStringRef key) { return CFRetain(service); }
static CFTypeRef hidEvent(CFTypeRef service, int64_t type, int32_t options, int64_t timestamp) {
    if (hidMode == 2) return NULL;
    assert(type == 15);
    double value = hidMode == 3 ? NAN : CFStringHasPrefix(service, CFSTR("pACC")) ? 98 :
        CFEqual(service, CFSTR("GPU MTR Temp Sensor0")) ? 43 : 51;
    return CFNumberCreate(NULL, kCFNumberDoubleType, &value);
}
static double hidValue(CFTypeRef event, int32_t field) {
    assert(field == (15 << 16));
    double value; assert(CFNumberGetValue(event, kCFNumberDoubleType, &value)); return value;
}
static void *fixtureSymbol(void *handle, const char *name) {
    if (!hidMode) return NULL;
    if (!strcmp(name, "IOHIDEventSystemClientCreate")) return (void *)hidCreate;
    if (!strcmp(name, "IOHIDEventSystemClientSetMatching")) return (void *)hidMatch;
    if (!strcmp(name, "IOHIDEventSystemClientCopyServices")) return (void *)hidServices;
    if (!strcmp(name, "IOHIDServiceClientCopyProperty")) return (void *)hidProperty;
    if (!strcmp(name, "IOHIDServiceClientCopyEvent")) return (void *)hidEvent;
    if (!strcmp(name, "IOHIDEventGetFloatValue")) return (void *)hidValue;
    return NULL;
}
static int fixtureSysctl(const char *name, void *output, size_t *size, void *input, size_t inputSize) {
    if (strcmp(name, "hw.optional.arm64") == 0) {
        assert(*size >= sizeof(fixtureARM));
        memcpy(output, &fixtureARM, sizeof(fixtureARM)); *size = sizeof(fixtureARM); return 0;
    }
    if (strcmp(name, "machdep.cpu.brand_string") == 0) {
        size_t needed = strlen(fixtureBrand) + 1;
        assert(*size >= needed); memcpy(output, fixtureBrand, needed); *size = needed; return 0;
    }
    return -1;
}
static void reset(void) {
    memset(fields, 0, sizeof(fields)); fieldCount = writes = opens = closes = wrongReadback = failingWrite = 0;
    memset(writeKeys, 0, sizeof(writeKeys));
    clientOpen = handshakeError = handshakeCalls = 0;
    temperatureClient = 0;
    hidMode = 0; fixtureBrand = "Apple M1 Max"; fixtureARM = 1;
}
static Field *add(const char *key, int size, const char *type, uint32_t value) {
    Field *f = &fields[fieldCount++]; f->key = key; f->size = size; f->type = code(type);
    for (int i=0;i<size && i<4;i++) f->bytes[i] = value>>(8*i);
    return f;
}
static Field *get(const char *key) {
    for (int i=0;i<fieldCount;i++) if (code(fields[i].key) == code(key)) return &fields[i];
    return NULL;
}
static void legacy(void) { reset(); add("CH0B",1,"ui8 ",0); add("CH0C",1,"ui8 ",0); }
static void modern(void) { reset(); add("CHTE",4,"ui32",0); }
static void firmware(void) { reset(); add("bfF0",1,"ui8 ",0); add("bfD0",4,"ui32",100); add("bfE0",4,"ui32",97); }
static io_service_t fixtureMatch(mach_port_t port, CFDictionaryRef dictionary) { if (dictionary) CFRelease(dictionary); return 1; }
static kern_return_t fixtureOpen(io_service_t s, task_port_t t, uint32_t type, io_connect_t *c) {
    opens++; *c=1; clientTransport = type; clientOpen = 0; return 0;
}
static kern_return_t fixtureRelease(io_object_t o) { return 0; }
static kern_return_t fixtureClose(io_connect_t o) { closes++; clientOpen = 0; return 0; }
static kern_return_t fixtureMethod(mach_port_t c, uint32_t selector, const uint64_t *input, uint32_t count, const void *data, size_t size, uint64_t *out, uint32_t *outCount, void *outData, size_t *outSize) {
    assert(selector == 0 || selector == 1);
    assert(input == NULL && count == 0 && data == NULL && size == 0);
    handshakeCalls++;
    if (selector == 0 && handshakeError) return handshakeError;
    clientOpen = selector == 0;
    return KERN_SUCCESS;
}
static kern_return_t fixtureCall(mach_port_t c, uint32_t selector, const void *input, size_t inputSize, void *output, size_t *outputSize) {
    assert(selector == 2 && inputSize == 80 && *outputSize == 80);
    const SMCMessage *in = input; SMCMessage *out = output;
    // The read-only type-0 client doesn't require the charge-control handshake.
    if (!clientOpen && (!temperatureClient || clientTransport != 0 || (in->command != 5 && in->command != 9))) return kIOReturnNotPrivileged;
    memset(out, 0, sizeof(*out));
    Field *f = NULL;
    for (int i=0;i<fieldCount;i++) if (code(fields[i].key) == in->key) f = &fields[i];
    if (!f) { out->result = 132; return 0; }
    if (f->denyRead) return kIOReturnNotPrivileged;
    out->info.size = f->size; out->info.type = f->type;
    if (in->command == 5) {
        memcpy(out->bytes, f->bytes, f->size <= 32 ? f->size : 32);
        if (wrongReadback && writes) { out->bytes[0] = 99; wrongReadback = 0; }
    }
    if (in->command == 6) {
        assert(in->info.size == f->size && in->info.type == f->type);
        writeKeys[writes % 64] = in->key; writes++;
        if (f->denyWrite || writes == failingWrite) return kIOReturnNotPrivileged;
        memcpy(f->bytes, in->bytes, f->size);
    }
    return 0;
}
static void temperatureFixture(void) { reset(); temperatureClient = 1; }
static void gpuTemperatureTests(void) {
    double temperature = -1000;
    float hot = 61.5f;
    // Missing, empty and invalid HID readings all fall back to known M1 GPU keys.
    const int unavailableModes[] = {0, 2, 3};
    for (int index = 0; index < 3; index++) {
        temperatureFixture(); hidMode = unavailableModes[index];
        memcpy(add("Tg0D", 4, "flt ", 0)->bytes, &hot, 4);
        assert(maccare_gpu_temperature(&temperature) == 0 && temperature == 61.5);
        assert(writes == 0 && opens == 1 && closes == 1 && handshakeCalls == 0 && clientTransport == 0);
    }
    temperatureFixture(); hidMode = 1;
    memcpy(add("Tg0D", 4, "flt ", 0)->bytes, &hot, 4);
    assert(maccare_gpu_temperature(&temperature) == 0 && temperature == 51 && opens == 0 && writes == 0);
    // CPU HID and SMC readings must never be substituted for the GPU.
    temperatureFixture(); hot = 99;
    memcpy(add("Tp01", 4, "flt ", 0)->bytes, &hot, 4);
    temperature = -1000;
    assert(maccare_gpu_temperature(&temperature) != 0 && temperature == -1000 && writes == 0);
    // Each GPU key is supported; choose the maximum valid reading with strict decoding.
    const char *gpuKeys[] = {"Tg05", "Tg0D", "Tg0L", "Tg0T"};
    for (int index = 0; index < 4; index++) {
        temperatureFixture(); hot = 40 + index;
        memcpy(add(gpuKeys[index], 4, "flt ", 0)->bytes, &hot, 4);
        assert(maccare_gpu_temperature(&temperature) == 0 && temperature == hot && writes == 0);
    }
    temperatureFixture();
    uint8_t fixed[] = {62, 128};
    memcpy(add("Tg05", 2, "sp78", 0)->bytes, fixed, 2);
    hot = 60; memcpy(add("Tg0D", 4, "flt ", 0)->bytes, &hot, 4);
    hot = NAN; memcpy(add("Tg0L", 4, "flt ", 0)->bytes, &hot, 4);
    hot = 200; memcpy(add("Tg0T", 4, "flt ", 0)->bytes, &hot, 4);
    assert(maccare_gpu_temperature(&temperature) == 0 && temperature == 62.5 && writes == 0);
    const float invalid[] = {NAN, INFINITY, -5, 0, 126};
    for (int index = 0; index < 5; index++) {
        temperatureFixture(); memcpy(add("Tg05", 4, "flt ", 0)->bytes, &invalid[index], 4);
        assert(maccare_gpu_temperature(&temperature) != 0 && writes == 0 && opens == closes);
    }
    temperatureFixture(); add("Tg05", 33, "flt ", 0); add("Tg0D", 2, "flt ", 0);
    add("Tg0L", 4, "ui32", 50); add("Tg0T", 2, "sp78", 0)->denyRead = 1;
    assert(maccare_gpu_temperature(&temperature) != 0 && writes == 0 && opens == closes);
    const char *brands[] = {"Apple M1", "Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra"};
    for (int index = 0; index < 4; index++) {
        temperatureFixture(); fixtureBrand = brands[index]; hot = 45;
        memcpy(add("Tg05", 4, "flt ", 0)->bytes, &hot, 4);
        assert(maccare_gpu_temperature(&temperature) == 0 && temperature == 45 && writes == 0);
    }
    const char *unknown[] = {"Apple M2 Max", "Apple M10", "Intel Core i7"};
    for (int index = 0; index < 3; index++) {
        temperatureFixture(); fixtureBrand = unknown[index];
        add("Tg05", 4, "flt ", 0);
        assert(maccare_gpu_temperature(&temperature) != 0 && opens == 0 && writes == 0);
    }
    temperatureFixture(); fixtureARM = 0;
    assert(maccare_gpu_temperature(&temperature) != 0 && opens == 0 && writes == 0);
    assert(maccare_gpu_temperature(NULL) == kIOReturnBadArgument && opens == 0);
    // Shared decoder keeps the CPU's existing fallback behavior.
    temperatureFixture(); hot = 55;
    memcpy(add("Tp01", 4, "flt ", 0)->bytes, &hot, 4);
    assert(maccare_cpu_temperature(&temperature) == 0 && temperature == 55 && writes == 0);
    puts("GPU fixtures passed: HID priority, missing/invalid events, M1 family fallback, GPU-only keys, formats, bounds and zero hardware writes.");
}
int main(void) {
    uint8_t value; int32_t backend;
    MCKeyDiagnostic diagnostic;
    reset(); add("CHIE", 1, "hex_", 0);
    assert(maccare_key_diagnostic(8, 1, 1, &diagnostic) == 0 && diagnostic.type == code("hex_") && writes == 0);
    assert(maccare_key_diagnostic(8, 0, 1, &diagnostic) == 0 && writes == 0);
    assert(maccare_key_diagnostic(8, 0, 0, &diagnostic) != 0 && writes == 0);
    assert(maccare_key_diagnostic(99, 1, 1, &diagnostic) == kIOReturnBadArgument && writes == 0);
    reset(); add("CHLS", 2, "ui16", 0x0450);
    assert(maccare_key_diagnostic(9, 1, 1, &diagnostic) == 0);
    assert(diagnostic.size == 2 && diagnostic.type == code("ui16") && diagnostic.bytes[0] == 80 && diagnostic.bytes[1] == 4 && writes == 0);
    assert(maccare_key_diagnostic(10, 1, 1, &diagnostic) == kIOReturnBadArgument && writes == 0);
    assert(maccare_key_diagnostic(-1, 1, 1, &diagnostic) == kIOReturnBadArgument && writes == 0);

    reset(); add("CHIE", 1, "hex_", 0);
    assert(maccare_adapter_probe(&backend) == 0 && backend == 2 && writes == 0);
    assert(maccare_adapter_write(backend, 1) == 0 && get("CHIE")->bytes[0] == 8);
    assert(maccare_adapter_read(backend, &value) == 0 && value == 1);
    assert(maccare_adapter_write(backend, 0) == 0 && get("CHIE")->bytes[0] == 0);
    reset(); add("CH0J", 1, "ui8 ", 0);
    assert(maccare_adapter_probe(&backend) == 0 && backend == 1);
    assert(maccare_adapter_write(backend, 1) == 0 && get("CH0J")->bytes[0] == 32);
    assert(maccare_adapter_write(backend, 0) == 0);
    assert(maccare_adapter_write(99, 1) != 0);
    reset(); add("CHIE", 1, "hex_", 99);
    assert(maccare_adapter_probe(&backend) != 0 && writes == 0);
    reset(); add("CHIE", 1, "hex_", 0); wrongReadback = 1;
    assert(maccare_adapter_write(2, 1) != 0 && get("CHIE")->bytes[0] == 0);
    legacy(); handshakeError = kIOReturnNotPrivileged;
    assert(maccare_charge_probe(&backend) == kIOReturnNotPrivileged && writes == 0 && clientOpen == 0);
    legacy();
    assert(maccare_charge_probe(&backend) == 0 && backend == MCChargeLegacyPair && writes == 0);
    assert(maccare_charge_write(backend,2) == 0 && get("CH0B")->bytes[0] == 2 && get("CH0C")->bytes[0] == 2);
    assert(maccare_charge_read(backend,&value) == 0 && value == 2);
    assert(maccare_charge_write(backend,0) == 0 && get("CH0B")->bytes[0] == 0 && get("CH0C")->bytes[0] == 0);
    int before = opens;
    assert(maccare_charge_write(99,0) == kIOReturnBadArgument && opens == before);
    assert(maccare_charge_write(backend,255) == kIOReturnBadArgument && opens == before);
    assert(maccare_charge_probe(NULL) == kIOReturnBadArgument && maccare_charge_read(backend,NULL) == kIOReturnBadArgument);

    // Second gate fails after the first was changed: both original values are restored.
    legacy(); failingWrite = 2;
    assert(maccare_charge_write(MCChargeLegacyPair,2) == kIOReturnNotPrivileged);
    assert(get("CH0B")->bytes[0] == 0 && get("CH0C")->bytes[0] == 0);
    // Restoration must try the second gate even if the first remains unavailable.
    legacy(); get("CH0B")->bytes[0] = get("CH0C")->bytes[0] = 2; get("CH0B")->denyWrite = 1;
    assert(maccare_charge_write(MCChargeLegacyPair,0) == kIOReturnNotPrivileged);
    assert(get("CH0C")->bytes[0] == 0);

    modern();
    assert(maccare_charge_probe(&backend) == 0 && backend == MCChargeGate);
    assert(maccare_charge_write(backend,2) == 0 && get("CHTE")->bytes[0] == 1);
    assert(maccare_charge_read(backend,&value) == 0 && value == 2);
    assert(maccare_charge_write(backend,0) == 0);
    writes = 0; wrongReadback = 1;
    assert(maccare_charge_write(backend,2) == kIOReturnIOError && get("CHTE")->bytes[0] == 0);
    // Discovery must never switch a previously selected writer to another backend.
    legacy();
    assert(maccare_charge_write(MCChargeGate,2) != 0 && writes == 0);
    add("CHTE",4,"ui32",0); get("CH0B")->denyRead = 1;
    assert(maccare_charge_probe(&backend) == kIOReturnNotPrivileged && backend == 0 && writes == 0);

    firmware(); add("CH0B",1,"ui8 ",0); add("CH0C",1,"ui8 ",0);
    assert(maccare_charge_probe(&backend) == 0 && backend == MCChargeFirmware);
    uint8_t active; uint32_t upper,lower;
    assert(maccare_firmware_limit_set(80,77,2) == 0);
    assert(maccare_firmware_limit_read(&active,&upper,&lower) == 0 && active == 2 && upper == 80 && lower == 77);
    assert(writes == 4 && writeKeys[0] == code("bfF0") && writeKeys[1] == code("bfD0") && writeKeys[2] == code("bfE0") && writeKeys[3] == code("bfF0"));
    assert(maccare_firmware_limit_set(80,60,2) == 0);
    assert(maccare_firmware_limit_read(&active,&upper,&lower) == 0 && upper == 80 && lower == 60);
    assert(maccare_firmware_limit_restore(100,97) == 0);
    assert(maccare_firmware_limit_read(&active,&upper,&lower) == 0 && active == 0 && upper == 100 && lower == 97);
    before = writes;
    assert(maccare_firmware_limit_set(101,98,2) == kIOReturnBadArgument && writes == before);
    assert(maccare_firmware_limit_set(80,80,2) == kIOReturnBadArgument && writes == before);
    assert(maccare_firmware_limit_restore(100,101) == kIOReturnBadArgument && writes == before);
    assert(maccare_firmware_limit_read(NULL,&upper,&lower) == kIOReturnBadArgument);
    // Each intermediate transaction failure rolls back the entire previous state.
    for (int step=1;step<=4;step++) {
        firmware(); failingWrite = step;
        assert(maccare_firmware_limit_set(80,77,2) != 0);
        assert(maccare_firmware_limit_read(&active,&upper,&lower) == 0 && active == 0 && upper == 100 && lower == 97);
    }
    firmware(); get("bfD0")->type = code("flt ");
    assert(maccare_charge_probe(&backend) == kIOReturnUnsupported && writes == 0);
    firmware(); get("bfF0")->bytes[0] = 2; get("bfE0")->bytes[0] = 100;
    assert(maccare_charge_probe(&backend) == kIOReturnUnsupported && writes == 0);
    // Oversized metadata is rejected before copying or writing.
    firmware(); get("bfD0")->size = 33;
    assert(maccare_charge_probe(&backend) != 0 && writes == 0);
    reset();
    float cold=28,hot=36,bad=NAN;
    memcpy(add("TB0T",4,"flt ",0)->bytes,&cold,4);
    memcpy(add("TB1T",4,"flt ",0)->bytes,&hot,4);
    memcpy(add("TB2T",4,"flt ",0)->bytes,&bad,4);
    double temperature;
    assert(maccare_battery_temperature(&temperature) == 0 && temperature == 36 && writes == 0);
    // M1 Max GPU sensors can be exposed by SMC while no HID event is available.
    // Keys identified by Stats' public M1-generation sensor catalog.
    temperatureFixture(); hot = 61.5f;
    memcpy(add("Tg0D", 4, "flt ", 0)->bytes, &hot, 4);
    assert(maccare_gpu_temperature(&temperature) == 0 && temperature == 61.5 && writes == 0);
    gpuTemperatureTests();
    puts("SMC fixtures passed: pinned backends, metadata, partial writes, rollback, exact firmware restoration, permissions, bounds and temperature.");
}
