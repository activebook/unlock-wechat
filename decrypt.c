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

// Base64 alphabet for PEM encoding
static const char BASE64_CHARS[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Suppress warnings for crypto handles
#pragma warning(disable:4047)
#pragma warning(disable:4244)

// Decode from base64
BOOL DecodeBase64(const char* str, BYTE* out, DWORD* outLen) {
    DWORD len = strlen(str);
    DWORD i = 0, j = 0;
    
    while (i < len) {
        // Skip whitespace and newlines
        if (str[i] == ' ' || str[i] == '\r' || str[i] == '\n' || str[i] == '\t') {
            i++;
            continue;
        }
        
        if (str[i] == '=') break;
        
        // Find character in BASE64_CHARS
        const char* pos_a = strchr(BASE64_CHARS, str[i]);
        if (!pos_a) return FALSE;
        DWORD sextet_a = pos_a - BASE64_CHARS;
        i++;
        if (i >= len) break;
        
        const char* pos_b = strchr(BASE64_CHARS, str[i]);
        if (!pos_b) return FALSE;
        DWORD sextet_b = pos_b - BASE64_CHARS;
        i++;
        
        DWORD sextet_c = 0, sextet_d = 0;
        BOOL has_c = FALSE, has_d = FALSE;
        
        if (i < len && str[i] != '=' && str[i] != ' ' && str[i] != '\r' && str[i] != '\n' && str[i] != '\t') {
            const char* pos_c = strchr(BASE64_CHARS, str[i]);
            if (pos_c) {
                sextet_c = pos_c - BASE64_CHARS;
                has_c = TRUE;
            }
            i++;
        }
        
        if (i < len && str[i] != '=' && str[i] != ' ' && str[i] != '\r' && str[i] != '\n' && str[i] != '\t') {
            const char* pos_d = strchr(BASE64_CHARS, str[i]);
            if (pos_d) {
                sextet_d = pos_d - BASE64_CHARS;
                has_d = TRUE;
            }
            i++;
        }
        
        DWORD triple = (sextet_a << 18) + (sextet_b << 12) + (sextet_c << 6) + sextet_d;
        
        out[j++] = (triple >> 16) & 0xFF;
        if (has_c) out[j++] = (triple >> 8) & 0xFF;
        if (has_d) out[j++] = triple & 0xFF;
    }
    
    *outLen = j;
    return TRUE;
}

// Convert PEM to BLOB
BOOL PEMToBlob(const char* pem, BYTE** blob, DWORD* blobLen) {
    // Find the base64 content (between headers)
    const char* start = strstr(pem, "-----BEGIN");
    if (!start) return FALSE;
    
    start = strchr(start, '\n');
    if (!start) return FALSE;
    start++; // Skip newline
    
    const char* end = strstr(start, "-----END");
    if (!end) return FALSE;
    
    // Copy base64 content
    DWORD contentLen = end - start;
    char* base64Content = (char*)malloc(contentLen + 1);
    memcpy(base64Content, start, contentLen);
    base64Content[contentLen] = 0;
    
    // Decode base64 - allocate enough space (base64 decodes to ~75% of input)
    DWORD maxDecodedLen = (contentLen * 3) / 4 + 4;  // +4 for safety
    BYTE* decoded = (BYTE*)malloc(maxDecodedLen);
    DWORD decodedLen;
    BOOL result = DecodeBase64(base64Content, decoded, &decodedLen);
    
    free(base64Content);
    
    if (!result || decodedLen == 0) {
        free(decoded);
        return FALSE;
    }
    
    *blob = decoded;
    *blobLen = decodedLen;
    return TRUE;
}

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

// Load public key from PEM file
BOOL LoadPublicKey() {
    if (!CryptAcquireContext(&hCryptProv, NULL, NULL, PROV_RSA_FULL, 0)) {
        if (!CryptAcquireContext(&hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_NEWKEYSET)) {
            return FALSE;
        }
    }

    FILE* f = fopen(PUBLIC_KEY_FILE, "r");
    if (!f) return FALSE;
    fseek(f, 0, SEEK_END);
    long pemLen = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* pemContent = (char*)malloc(pemLen + 1);
    fread(pemContent, 1, pemLen, f);
    pemContent[pemLen] = 0;
    fclose(f);

    // Convert PEM to BLOB
    BYTE* pbPub;
    DWORD dwPubLen;
    if (!PEMToBlob(pemContent, &pbPub, &dwPubLen)) {
        free(pemContent);
        return FALSE;
    }
    free(pemContent);

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
