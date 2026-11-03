// SMC wire layout derived from SMCKit (beltex), MIT; see THIRD_PARTY_NOTICES.md.
#include "MacCareSMC.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>
#include <stddef.h>
#include <math.h>
#include <sys/sysctl.h>

typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "SMC ABI size");
_Static_assert(offsetof(SMCMessage, bytes) == 48, "SMC ABI bytes offset");

static uint32_t code(const char *s) {
    return ((uint32_t)s[0]<<24)|((uint32_t)s[1]<<16)|((uint32_t)s[2]<<8)|(uint32_t)s[3];
}
static int32_t call(io_connect_t connection, SMCMessage *in, SMCMessage *out) {
    size_t size = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size);
    if (result != KERN_SUCCESS) return result;
    if (size != sizeof(*out)) return kIOReturnBadArgument;
    return out->result == 0 ? 0 : (int32_t)(0x10000 + out->result);
}
static int32_t openSMC(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    int32_t arm64 = 0; size_t arm64Size = sizeof(arm64);
    sysctlbyname("hw.optional.arm64", &arm64, &arm64Size, NULL, 0);
    int32_t result = IOServiceOpen(service, mach_task_self(), arm64 ? 1 : 0, connection);
    IOObjectRelease(service);
    if (result) return result;
    result = IOConnectCallMethod(*connection, 0, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    if (result) { IOServiceClose(*connection); *connection = 0; }
    return result;
}
static void closeSMC(io_connect_t connection) {
    IOConnectCallMethod(connection, 1, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    IOServiceClose(connection);
}
static int32_t readKey(io_connect_t connection, const char *key, SMCMessage *out) {
    SMCMessage in = {0}, info = {0};
    in.key = code(key); in.command = 9;
    int32_t result = call(connection, &in, &info);
    if (result) return result;
    if (info.info.size == 0 || info.info.size > 32) return kIOReturnBadArgument;
    in.info = info.info; in.command = 5;
    result = call(connection, &in, out);
    out->info = info.info;
    return result;
}
static int missing(int32_t result) { return result == 0x10084 || result == kIOReturnNotFound; }
static int32_t firmwareRead(io_connect_t connection, SMCMessage fields[3]);

static int32_t gateRead(io_connect_t connection, int32_t backend, SMCMessage messages[2]) {
    if (backend != MCChargeLegacyPair && backend != MCChargeGate) return kIOReturnBadArgument;
    const char *keys[] = {backend == MCChargeGate ? "CHTE" : "CH0B", "CH0C"};
    int count = backend == MCChargeGate ? 1 : 2;
    for (int i=0;i<count;i++) {
        int32_t result = readKey(connection, keys[i], &messages[i]);
        if (result) return result;
        if (backend == MCChargeGate) {
            if (messages[i].info.size != 4 || messages[i].info.type != code("ui32") ||
                messages[i].bytes[0] > 1 || messages[i].bytes[1] || messages[i].bytes[2] || messages[i].bytes[3]) return kIOReturnUnsupported;
        } else if (messages[i].info.size != 1 || messages[i].info.type != code("ui8 ") ||
                   (messages[i].bytes[0] != 0 && messages[i].bytes[0] != 2)) return kIOReturnUnsupported;
    }
    return 0;
}
static int32_t writeField(io_connect_t connection, const char *key, const SMCMessage *field, const uint8_t *bytes) {
    SMCMessage in = {0}, out = {0};
    if (field->info.size == 0 || field->info.size > 32) return kIOReturnBadArgument;
    in.key = code(key); in.info = field->info; in.command = 6;
    memcpy(in.bytes, bytes, in.info.size);
    int32_t result = call(connection, &in, &out);
    if (!result) {
        result = readKey(connection, key, &out);
        if (!result && (out.info.size != in.info.size || out.info.type != in.info.type ||
                        memcmp(in.bytes, out.bytes, in.info.size) != 0)) result = kIOReturnIOError;
    }
    return result;
}
int32_t maccare_charge_probe(int32_t *backend) {
    if (!backend) return kIOReturnBadArgument;
    *backend = 0;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage field = {0}, messages[3] = {0};
    result = readKey(connection, "bfF0", &field);
    if (!result) {
        result = firmwareRead(connection, messages);
        if (!result) *backend = MCChargeFirmware;
    } else if (missing(result)) {
        result = gateRead(connection, MCChargeLegacyPair, messages);
        if (!result) *backend = MCChargeLegacyPair;
        else if (missing(result)) {
            result = gateRead(connection, MCChargeGate, messages);
            if (!result) *backend = MCChargeGate;
        }
    }
    // Permission errors or unknown metadata never fall through to a different backend.
    closeSMC(connection);
    return result;
}
int32_t maccare_charge_read(int32_t backend, uint8_t *value) {
    if (!value) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage fields[3] = {0};
    if (backend == MCChargeFirmware) {
        result = firmwareRead(connection, fields);
        if (!result) *value = fields[0].bytes[0];
    } else {
        result = gateRead(connection, backend, fields);
        if (!result) *value = backend == MCChargeGate ? (fields[0].bytes[0] ? 2 : 0)
            : (fields[0].bytes[0] || fields[1].bytes[0] ? 2 : 0);
    }
    closeSMC(connection);
    return result;
}
int32_t maccare_charge_write(int32_t backend, uint8_t value) {
    if ((backend != MCChargeLegacyPair && backend != MCChargeGate) || (value != 0 && value != 2)) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage fields[2] = {0};
    result = gateRead(connection, backend, fields);
    int count = backend == MCChargeGate ? 1 : 2;
    const char *keys[] = {backend == MCChargeGate ? "CHTE" : "CH0B", "CH0C"};
    uint8_t desired[32] = {0}; desired[0] = value == 0 ? 0 : (backend == MCChargeGate ? 1 : 2);
    if (!result) {
        int32_t firstError = 0;
        for (int i=0;i<count;i++) {
            int32_t writeResult = writeField(connection, keys[i], &fields[i], desired);
            if (writeResult && !firstError) firstError = writeResult;
            if (writeResult && value == 2) {
                // A partial inhibit must not strand either gate. Restore both known bytes.
                for (int j=0;j<count;j++) writeField(connection, keys[j], &fields[j], fields[j].bytes);
                break;
            }
            // When restoring normal charging, try BOTH gates even if the first fails.
        }
        result = firstError;
    }
    closeSMC(connection);
    return result;
}
int32_t maccare_battery_temperature(double *celsius) {
    if (!celsius) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    const char *keys[] = {"TB0T", "TB1T", "TB2T"};
    double highest = -1000;
    for (int i=0; i<3; ++i) {
        SMCMessage out = {0};
        if (readKey(connection, keys[i], &out)) continue;
        double value = -1000;
        if (out.info.type == code("sp78") && out.info.size == 2)
            value = (int16_t)((out.bytes[0]<<8)|out.bytes[1]) / 256.0;
        else if (out.info.type == code("flt ") && out.info.size == 4) {
            float f; memcpy(&f, out.bytes, 4); value = f;
        }
        if (isfinite(value) && value > 0 && value <= 90 && value > highest) highest = value;
    }
    closeSMC(connection);
    if (highest == -1000) return kIOReturnNotFound;
    *celsius = highest;
    return 0;
}

static uint32_t little32(const uint8_t *b) {
    return (uint32_t)b[0] | ((uint32_t)b[1]<<8) | ((uint32_t)b[2]<<16) | ((uint32_t)b[3]<<24);
}
static int32_t firmwareRead(io_connect_t connection, SMCMessage fields[3]) {
    const char *keys[] = {"bfF0", "bfD0", "bfE0"};
    for (int i=0;i<3;i++) {
        int32_t result = readKey(connection, keys[i], &fields[i]);
        if (result) return result;
        if (fields[i].info.size != (i == 0 ? 1 : 4) ||
            fields[i].info.type != code(i == 0 ? "ui8 " : "ui32")) return kIOReturnUnsupported;
    }
    if ((fields[0].bytes[0] != 0 && fields[0].bytes[0] != 2) ||
        little32(fields[1].bytes) > 100 || little32(fields[2].bytes) > 100 ||
        (fields[0].bytes[0] == 2 && (little32(fields[1].bytes) < 50 || little32(fields[2].bytes) >= little32(fields[1].bytes)))) return kIOReturnUnsupported;
    return 0;
}
static int32_t firmwareWrite(io_connect_t connection, const char *key, SMCMessage *field, uint32_t value) {
    uint8_t bytes[32] = {0};
    for (int i=0;i<field->info.size;i++) bytes[i] = (uint8_t)(value>>(i*8));
    return writeField(connection, key, field, bytes);
}
int32_t maccare_firmware_limit_read(uint8_t *active, uint32_t *upper, uint32_t *lower) {
    if (!active || !upper || !lower) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage fields[3] = {0};
    result = firmwareRead(connection, fields);
    if (!result) {
        *active = fields[0].bytes[0]; *upper = little32(fields[1].bytes); *lower = little32(fields[2].bytes);
    }
    closeSMC(connection);
    return result;
}
int32_t maccare_firmware_limit_set(uint32_t upper, uint32_t lower, uint8_t active) {
    if (upper > 100 || lower > 100 || (active != 0 && active != 2) || (active == 2 && (upper < 50 || lower < 30 || lower >= upper))) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage fields[3] = {0};
    result = firmwareRead(connection, fields);
    if (!result) {
        // Required firmware sequence: disable, upper, lower, activate. Keep a disabled
        // band's previous thresholds intact when returning control to macOS.
        result = firmwareWrite(connection, "bfF0", &fields[0], 0);
        if (!result && active == 2) result = firmwareWrite(connection, "bfD0", &fields[1], upper);
        if (!result && active == 2) result = firmwareWrite(connection, "bfE0", &fields[2], lower);
        if (!result && active == 2) result = firmwareWrite(connection, "bfF0", &fields[0], 2);
        if (result) {
            // Best-effort rollback of a partial transaction. The root recovery marker
            // remains until the controller verifies restoration independently.
            firmwareWrite(connection, "bfF0", &fields[0], 0);
            firmwareWrite(connection, "bfD0", &fields[1], little32(fields[1].bytes));
            firmwareWrite(connection, "bfE0", &fields[2], little32(fields[2].bytes));
            firmwareWrite(connection, "bfF0", &fields[0], fields[0].bytes[0]);
        }
    }
    closeSMC(connection);
    return result;
}

int32_t maccare_firmware_limit_restore(uint32_t upper, uint32_t lower) {
    if (upper > 100 || lower > 100) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage fields[3] = {0};
    result = firmwareRead(connection, fields);
    if (!result) {
        result = firmwareWrite(connection, "bfF0", &fields[0], 0);
        if (!result) result = firmwareWrite(connection, "bfD0", &fields[1], upper);
        if (!result) result = firmwareWrite(connection, "bfE0", &fields[2], lower);
    }
    closeSMC(connection);
    return result;
}

// Two documented adapter gates. Never accepts a key supplied by an XPC caller.
static int32_t adapterRead(io_connect_t connection, int32_t backend, SMCMessage *field) {
    if (backend != 1 && backend != 2) return kIOReturnBadArgument;
    int32_t result = readKey(connection, backend == 2 ? "CHIE" : "CH0J", field);
    if (result) return result;
    uint8_t inhibited = backend == 2 ? 8 : 32;
    if (field->info.size != 1 || field->info.type != code(backend == 2 ? "hex_" : "ui8 ") ||
        (field->bytes[0] != 0 && field->bytes[0] != inhibited)) return kIOReturnUnsupported;
    return 0;
}
int32_t maccare_adapter_read(int32_t backend, uint8_t *disabled) {
    if (!disabled) return kIOReturnBadArgument;
    io_connect_t connection = 0; int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage field = {0}; result = adapterRead(connection, backend, &field);
    if (!result) *disabled = field.bytes[0] != 0;
    closeSMC(connection); return result;
}
int32_t maccare_adapter_probe(int32_t *backend) {
    if (!backend) return kIOReturnBadArgument;
    *backend = 0; uint8_t disabled = 0;
    int32_t result = maccare_adapter_read(2, &disabled);
    if (!result) *backend = 2;
    else if (missing(result)) { result = maccare_adapter_read(1, &disabled); if (!result) *backend = 1; }
    return result;
}
int32_t maccare_adapter_write(int32_t backend, uint8_t disabled) {
    if ((backend != 1 && backend != 2) || disabled > 1) return kIOReturnBadArgument;
    io_connect_t connection = 0; int32_t result = openSMC(&connection);
    if (result) return result;
    SMCMessage field = {0}; result = adapterRead(connection, backend, &field);
    if (!result) {
        uint8_t desired[32] = {0}; desired[0] = disabled ? (backend == 2 ? 8 : 32) : 0;
        if (field.bytes[0] != desired[0]) {
            result = writeField(connection, backend == 2 ? "CHIE" : "CH0J", &field, desired);
            if (result && disabled) {
                uint8_t normal[32] = {0};
                writeField(connection, backend == 2 ? "CHIE" : "CH0J", &field, normal);
            }
        }
    }
    closeSMC(connection); return result;
}

// Explicit read-only support matrix. Closed key slots and closed transport values.
int32_t maccare_key_diagnostic(int32_t slot, int32_t transport, int32_t handshake, MCKeyDiagnostic *output) {
    const char *keys[] = {"bfF0", "bfD0", "bfE0", "CHTE", "CH0B", "CH0C", "CH0I", "CH0J", "CHIE"};
    if (!output || slot < 0 || slot >= 9 || transport < 0 || transport > 1 || handshake < 0 || handshake > 1) return kIOReturnBadArgument;
    memset(output, 0, sizeof(*output));
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { output->result = kIOReturnNotFound; return output->result; }
    io_connect_t connection = 0;
    int32_t result = IOServiceOpen(service, mach_task_self(), (uint32_t)transport, &connection);
    IOObjectRelease(service);
    if (result) { output->result = result; return result; }
    int opened = 0;
    if (handshake) {
        result = IOConnectCallMethod(connection, 0, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
        opened = result == 0;
    }
    SMCMessage field = {0};
    if (!result) result = readKey(connection, keys[slot], &field);
    output->result = result; output->size = field.info.size; output->type = field.info.type;
    if (!result) memcpy(output->bytes, field.bytes, field.info.size < 4 ? field.info.size : 4);
    if (opened) IOConnectCallMethod(connection, 1, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL);
    IOServiceClose(connection);
    return result;
}
