#ifndef MACCARE_SMC_H
#define MACCARE_SMC_H
#include <stdint.h>
#include <IOKit/IOMessage.h>
enum { MCSystemCanSleep = kIOMessageCanSystemSleep, MCSystemWillSleep = kIOMessageSystemWillSleep, MCSystemDidWake = kIOMessageSystemHasPoweredOn };
enum { MCChargeLegacyPair = 1, MCChargeGate = 2, MCChargeFirmware = 3 };
// Discovery is read-only. Every mutation names a previously selected, closed backend.
int32_t maccare_charge_probe(int32_t *backend);
int32_t maccare_charge_read(int32_t backend, uint8_t *value);
int32_t maccare_charge_write(int32_t backend, uint8_t value);
int32_t maccare_battery_temperature(double *celsius);
int32_t maccare_firmware_limit_read(uint8_t *active, uint32_t *upper, uint32_t *lower);
int32_t maccare_firmware_limit_set(uint32_t upper, uint32_t lower, uint8_t active);
int32_t maccare_firmware_limit_restore(uint32_t upper, uint32_t lower);
int32_t maccare_adapter_probe(int32_t *backend);
int32_t maccare_adapter_read(int32_t backend, uint8_t *disabled);
int32_t maccare_adapter_write(int32_t backend, uint8_t disabled);
#endif
