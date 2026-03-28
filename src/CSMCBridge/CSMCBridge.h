#ifndef CSMCBridge_h
#define CSMCBridge_h

#include <stdint.h>

#define CSMC_KERNEL_INDEX_SMC 2
#define CSMC_CMD_READ_BYTES 5
#define CSMC_CMD_WRITE_BYTES 6
#define CSMC_CMD_READ_KEYINFO 9

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} CSMCKeyDataVers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} CSMCKeyDataPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} CSMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    CSMCKeyDataVers vers;
    CSMCKeyDataPLimitData pLimitData;
    CSMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} CSMCKeyData;

#endif
