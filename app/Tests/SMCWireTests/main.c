// A bounded IOKit driver fixture. Never opens a real driver or writes hardware.
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <assert.h>
#include <stdio.h>
#define IOConnectCallMethod fixtureMethod
#define IOConnectCallStructMethod fixtureCall
#define IOServiceGetMatchingService fixtureMatch
#define IOServiceOpen fixtureOpen
#define IOObjectRelease fixtureRelease
#define IOServiceClose fixtureClose
static kern_return_t fixtureMethod(mach_port_t, uint32_t, const uint64_t *, uint32_t, const void *, size_t, uint64_t *, uint32_t *, void *, size_t *);
static kern_return_t fixtureCall(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
static io_service_t fixtureMatch(mach_port_t, CFDictionaryRef);
static kern_return_t fixtureOpen(io_service_t, task_port_t, uint32_t, io_connect_t *);
static kern_return_t fixtureRelease(io_object_t);
static kern_return_t fixtureClose(io_connect_t);
#include "../../Sources/CMacCareSMC/MacCareSMC.c"

typedef struct { const char *key; uint32_t size, type; uint8_t bytes[32]; int denyRead, denyWrite; } Field;
static Field fields[10];
static int fieldCount, writes, opens, wrongReadback, failingWrite;
static int clientOpen, handshakeError, handshakeCalls;
static uint32_t writeKeys[64];
static void reset(void) {
    memset(fields, 0, sizeof(fields)); fieldCount = writes = opens = wrongReadback = failingWrite = 0;
    memset(writeKeys, 0, sizeof(writeKeys));
    clientOpen = handshakeError = handshakeCalls = 0;
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
static kern_return_t fixtureOpen(io_service_t s, task_port_t t, uint32_t type, io_connect_t *c) { opens++; *c=1; return 0; }
static kern_return_t fixtureRelease(io_object_t o) { return 0; }
static kern_return_t fixtureClose(io_connect_t o) { return 0; }
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
    if (!clientOpen) return kIOReturnNotPrivileged;
    const SMCMessage *in = input; SMCMessage *out = output;
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
    puts("SMC fixtures passed: pinned backends, metadata, partial writes, rollback, exact firmware restoration, permissions, bounds and temperature.");
}
