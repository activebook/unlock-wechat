#ifndef LICENSE_H
#define LICENSE_H

#include <Security/Security.h>
#include <Foundation/Foundation.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <net/if_dl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#define BASE32_CHARS "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

// Base32 decode
bool DecodeBase32(const char* str, unsigned char* out, int* outLen);

// Get machine-specific token from MAC address
bool GetMachineToken(unsigned char* token);

// Parse unique ID from string (supports xxxxxxxx and xx-xx-xx-xx formats)
bool ParseUniqueID(const char* str, unsigned char* out);

// Convert PEM to DER format
NSData* PEMToDER(NSString *pemContent);

// Verify license
bool VerifyLicense(const char* license, const unsigned char* expectedToken, NSString* publicKeyPath);

// Verify license with string unique ID
bool VerifyLicenseFromString(const char* license, const char* expectedUniqueID, NSString* publicKeyPath);

#endif /* LICENSE_H */
