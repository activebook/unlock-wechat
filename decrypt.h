#pragma once

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

// Functions for license verification
BOOL InitDecrypt();
void CleanupDecrypt();
BOOL CheckLicense(const char* license);
BOOL GetMachineToken(BYTE* token);

// Internal functions (for reference)
BOOL DecodeBase32(const char* str, BYTE* out, DWORD* outLen);
BOOL LoadPublicKey();

#ifdef __cplusplus
}
#endif
