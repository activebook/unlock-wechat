#include <windows.h>
#include <wincrypt.h>
#include <Iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Crypto handles
HCRYPTKEY hPublicKey = (HCRYPTKEY)NULL;
HCRYPTPROV hCryptProv = (HCRYPTPROV)NULL;

// File paths
#define PUBLIC_KEY_FILE "public.key"

// Base32 alphabet (no ambiguous chars like 0,O,1,I)
static const char BASE32_CHARS[] = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

// Decode from base32
BOOL DecodeBase32(const char* str, BYTE* out, DWORD* outLen) {
    int bits = 0;
    int value = 0;
    int idx = 0;

    for (int i = 0; str[i]; i++) {
        if (str[i] == '-') continue;

        const char* pos = strchr(BASE32_CHARS, str[i]);
        if (!pos) return FALSE;

        value = (value << 5) | (pos - BASE32_CHARS);
        bits += 5;

        if (bits >= 8) {
            out[idx++] = (value >> (bits - 8)) & 0xFF;
            bits -= 8;
        }
    }

    *outLen = idx;
    return TRUE;
}

// Load public key from file
BOOL LoadPublicKey() {
    if (!CryptAcquireContext(&hCryptProv, NULL, NULL, PROV_RSA_FULL, 0)) {
        if (!CryptAcquireContext(&hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_NEWKEYSET)) {
            return FALSE;
        }
    }

    FILE* f = fopen(PUBLIC_KEY_FILE, "rb");
    if (!f) return FALSE;
    fseek(f, 0, SEEK_END);
    DWORD dwPubLen = (DWORD)ftell(f);
    fseek(f, 0, SEEK_SET);
    BYTE* pbPub = (BYTE*)malloc(dwPubLen);
    fread(pbPub, 1, dwPubLen, f);
    fclose(f);

    if (!CryptImportKey(hCryptProv, pbPub, dwPubLen, 0, 0, &hPublicKey)) {
        free(pbPub);
        return FALSE;
    }
    free(pbPub);
    return TRUE;
}

// Get machine-specific token from MAC address
BOOL GetMachineToken(BYTE* token) {
    PIP_ADAPTER_INFO pAdapterInfo = (IP_ADAPTER_INFO*)malloc(sizeof(IP_ADAPTER_INFO));
    if (!pAdapterInfo) return FALSE;

    ULONG ulOutBufLen = sizeof(IP_ADAPTER_INFO);
    DWORD dwStatus = GetAdaptersInfo(pAdapterInfo, &ulOutBufLen);
    if (dwStatus == ERROR_BUFFER_OVERFLOW) {
        free(pAdapterInfo);
        pAdapterInfo = (IP_ADAPTER_INFO*)malloc(ulOutBufLen);
        if (!pAdapterInfo) return FALSE;
        dwStatus = GetAdaptersInfo(pAdapterInfo, &ulOutBufLen);
    }
    if (dwStatus != ERROR_SUCCESS) {
        free(pAdapterInfo);
        return FALSE;
    }

    for (PIP_ADAPTER_INFO pAdapter = pAdapterInfo; pAdapter; pAdapter = pAdapter->Next) {
        if (pAdapter->AddressLength >= 4) {
            memcpy(token, pAdapter->Address, 4);
            free(pAdapterInfo);
            return TRUE;
        }
    }

    free(pAdapterInfo);
    return FALSE;
}

// Verify license against machine token
BOOL VerifyLicense(const char* license, const BYTE* expectedToken) {
    if (!hPublicKey) return FALSE;

    // Decode base32
    BYTE combined[512];
    DWORD combinedLen;
    if (!DecodeBase32(license, combined, &combinedLen)) {
        return FALSE;
    }

    // Must be at least 4 bytes payload + some signature
    if (combinedLen < 4) {
        return FALSE;
    }

    // Extract payload and signature
    BYTE payload[4];
    memcpy(payload, combined, 4);
    BYTE* pbSig = combined + 4;
    DWORD dwSigLen = combinedLen - 4;

    // Check if payload matches machine token
    if (memcmp(payload, expectedToken, 4) != 0) {
        return FALSE;  // License not for this machine
    }

    // Hash payload
    HCRYPTHASH hHash;
    if (!CryptCreateHash(hCryptProv, CALG_SHA1, 0, 0, &hHash)) {
        return FALSE;
    }
    if (!CryptHashData(hHash, payload, sizeof(payload), 0)) {
        CryptDestroyHash(hHash);
        return FALSE;
    }

    // Verify signature with public key
    BOOL result = CryptVerifySignature(hHash, pbSig, dwSigLen, hPublicKey, NULL, 0);
    CryptDestroyHash(hHash);

    return result;
}

// Initialize crypto and load public key
BOOL InitDecrypt() {
    return LoadPublicKey();
}

// Cleanup crypto
void CleanupDecrypt() {
    if (hPublicKey) CryptDestroyKey(hPublicKey);
    if (hCryptProv) CryptReleaseContext(hCryptProv, 0);
    hPublicKey = NULL;
    hCryptProv = NULL;
}

// Check license: get machine token and verify
BOOL CheckLicense(const char* license) {
    BYTE token[4];
    if (!GetMachineToken(token)) {
        return FALSE;
    }
    return VerifyLicense(license, token);
}
