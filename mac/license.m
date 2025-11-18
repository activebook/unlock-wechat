#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import <sys/ioctl.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <net/if_dl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "license.h"

static SecKeyRef publicKey = NULL;

// Encode to base32
void EncodeBase32(const unsigned char* data, int len, char* out) {
    int bits = 0;
    int value = 0;
    int idx = 0;

    for (int i = 0; i < len; i++) {
        value = (value << 8) | data[i];
        bits += 8;

        while (bits >= 5) {
            out[idx++] = BASE32_CHARS[(value >> (bits - 5)) & 0x1F];
            bits -= 5;
        }
    }

    if (bits > 0) {
        out[idx++] = BASE32_CHARS[(value << (5 - bits)) & 0x1F];
    }
    out[idx] = 0;
}

// Decode from base32
bool DecodeBase32(const char* str, unsigned char* out, int* outLen) {
    int bits = 0;
    int value = 0;
    int idx = 0;

    for (int i = 0; str[i]; i++) {
        if (str[i] == '-') continue;

        const char* pos = strchr(BASE32_CHARS, str[i]);
        if (!pos) return false;

        value = (value << 5) | (pos - BASE32_CHARS);
        bits += 5;

        if (bits >= 8) {
            out[idx++] = (value >> (bits - 8)) & 0xFF;
            bits -= 8;
        }
    }

    *outLen = idx;
    return true;
}

// Get machine-specific token from MAC address
bool GetMachineToken(unsigned char* token) {
    struct ifaddrs *ifap, *ifaptr;
    if (getifaddrs(&ifap) < 0) {
        return false;
    }

    for (ifaptr = ifap; ifaptr; ifaptr = ifaptr->ifa_next) {
        if (strcmp(ifaptr->ifa_name, "en0") == 0 && ifaptr->ifa_addr->sa_family == AF_LINK) {
            struct sockaddr_dl* sdl = (struct sockaddr_dl *)ifaptr->ifa_addr;
            if (sdl->sdl_alen >= 4) {
                memcpy(token, sdl->sdl_data + sdl->sdl_nlen, 4);
                freeifaddrs(ifap);
                return true;
            }
        }
    }

    freeifaddrs(ifap);
    return false;
}

// Convert PEM to DER format
NSData* PEMToDER(NSString *pemContent) {
    // Remove all PEM headers and whitespace
    NSString *stripped = pemContent;
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----BEGIN PRIVATE KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----END PRIVATE KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----BEGIN RSA PRIVATE KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"-----END RSA PRIVATE KEY-----" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@" " withString:@""];
    stripped = [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Decode base64
    return [[NSData alloc] initWithBase64EncodedString:stripped options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

// Verify license
bool VerifyLicense(const char* license, const unsigned char* expectedToken, NSString* publicKeyPath) {
    @autoreleasepool {
        // Decode base32
        unsigned char combined[512];
        int combinedLen;
        if (!DecodeBase32(license, combined, &combinedLen)) {
            fprintf(stderr, "Failed to decode license\n");
            return false;
        }

        if (combinedLen < 4) {
            fprintf(stderr, "Invalid license length\n");
            return false;
        }

        // Extract payload
        unsigned char payload[4];
        memcpy(payload, combined, 4);
        unsigned char* sigBytes = combined + 4;
        int sigLen = combinedLen - 4;

        // Check payload
        if (memcmp(payload, expectedToken, 4) != 0) {
            fprintf(stderr, "Machine token mismatch\n");
            return false;
        }

        // Load public key if not loaded
        if (!publicKey) {
            NSError *readError = nil;
            NSString *publicPEM = [NSString stringWithContentsOfFile:publicKeyPath 
                                                            encoding:NSUTF8StringEncoding 
                                                               error:&readError];
            if (!publicPEM) {
                fprintf(stderr, "Failed to read public key file: %s\n", [[readError localizedDescription] UTF8String]);
                return false;
            }

            // Convert PEM to DER
            NSData *publicDER = PEMToDER(publicPEM);
            if (!publicDER || [publicDER length] == 0) {
                fprintf(stderr, "Failed to decode public key PEM\n");
                return false;
            }

            CFMutableDictionaryRef keyAttrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictionarySetValue(keyAttrs, kSecAttrKeyType, kSecAttrKeyTypeRSA);
            CFDictionarySetValue(keyAttrs, kSecAttrKeyClass, kSecAttrKeyClassPublic);

            CFErrorRef error = NULL;
            publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicDER, keyAttrs, &error);

            CFRelease(keyAttrs);

            if (!publicKey) {
                if (error) {
                    NSError *nsError = (__bridge NSError *)error;
                    fprintf(stderr, "Failed to create public key: %s\n", [[nsError localizedDescription] UTF8String]);
                    CFRelease(error);
                }
                return false;
            }
        }

        // Verify signature
        CFDataRef payloadData = CFDataCreate(kCFAllocatorDefault, payload, 4);
        CFDataRef sigCFData = CFDataCreate(kCFAllocatorDefault, sigBytes, sigLen);

        SecKeyAlgorithm algorithm = kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1;
        CFErrorRef error = NULL;
        bool result = SecKeyVerifySignature(publicKey, algorithm, payloadData, sigCFData, &error);

        if (!result && error) {
            NSError *nsError = (__bridge NSError *)error;
            fprintf(stderr, "Signature verification failed: %s\n", [[nsError localizedDescription] UTF8String]);
            CFRelease(error);
        }

        CFRelease(payloadData);
        CFRelease(sigCFData);

        return result;
    }
}
