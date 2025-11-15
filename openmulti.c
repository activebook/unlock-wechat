#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <tlhelp32.h>

// Undocumented NT APIs and structures
typedef enum _OBJECT_INFORMATION_CLASS {
    ObjectBasicInformation,
    ObjectNameInformation,
    ObjectTypeInformation,
    ObjectAllInformation,
    ObjectDataInformation
} OBJECT_INFORMATION_CLASS;

typedef enum _SYSTEM_INFORMATION_CLASS {
    SystemBasicInformation = 0,
    SystemPerformanceInformation = 2,
    SystemTimeOfDayInformation = 3,
    SystemProcessInformation = 5,
    SystemProcessorPerformanceInformation = 8,
    SystemHandleInformation = 16,
    SystemInterruptInformation = 23,
    SystemExceptionInformation = 33,
    SystemRegistryQuotaInformation = 37,
    SystemLookasideInformation = 45
} SYSTEM_INFORMATION_CLASS;

typedef struct _UNICODE_STRING {
    USHORT Length;
    USHORT MaximumLength;
    PWSTR Buffer;
} UNICODE_STRING;

typedef struct _OBJECT_NAME_INFORMATION {
    UNICODE_STRING Name;
} OBJECT_NAME_INFORMATION, *POBJECT_NAME_INFORMATION;

// ObjectTypeInformation structure (simplified)
typedef struct _OBJECT_TYPE_INFORMATION {
    UNICODE_STRING Name;
    ULONG TotalNumberOfObjects;
    ULONG TotalNumberOfHandles;
    ULONG TotalPagedPoolUsage;
    ULONG TotalNonPagedPoolUsage;
    ULONG TotalNamePoolUsage;
    ULONG TotalHandleTableUsage;
    ULONG HighWaterNumberOfObjects;
    ULONG HighWaterNumberOfHandles;
    ULONG HighWaterPagedPoolUsage;
    ULONG HighWaterNonPagedPoolUsage;
    ULONG HighWaterNamePoolUsage;
    ULONG HighWaterHandleTableUsage;
    ULONG InvalidAttributes;
    GENERIC_MAPPING GenericMapping;
    ULONG ValidAccess;
    BOOLEAN SecurityRequired;
    BOOLEAN MaintainHandleCount;
    USHORT MaintainTypeList;
    ULONG PoolType; // Use ULONG instead of POOL_TYPE to avoid definition issues
    ULONG PagedPoolUsage;
    ULONG NonPagedPoolUsage;
} OBJECT_TYPE_INFORMATION, *POBJECT_TYPE_INFORMATION;

typedef struct _SYSTEM_HANDLE {
    ULONG ProcessId;
    BYTE ObjectTypeNumber;
    BYTE Flags;
    USHORT Handle;
    PVOID Object;
    ACCESS_MASK GrantedAccess;
} SYSTEM_HANDLE, *PSYSTEM_HANDLE;

typedef struct _SYSTEM_HANDLE_INFORMATION {
    ULONG HandleCount;
    SYSTEM_HANDLE Handles[1];
} SYSTEM_HANDLE_INFORMATION, *PSYSTEM_HANDLE_INFORMATION;

// Function prototypes for undocumented APIs
typedef NTSTATUS (NTAPI *PNtQuerySystemInformation)(
    SYSTEM_INFORMATION_CLASS SystemInformationClass,
    PVOID SystemInformation,
    ULONG SystemInformationLength,
    PULONG ReturnLength
);

typedef NTSTATUS (NTAPI *PNtQueryObject)(
    HANDLE Handle,
    OBJECT_INFORMATION_CLASS ObjectInformationClass,
    PVOID ObjectInformation,
    ULONG ObjectInformationLength,
    PULONG ReturnLength
);

typedef NTSTATUS (NTAPI *PNtDuplicateObject)(
    HANDLE SourceProcessHandle,
    HANDLE SourceHandle,
    HANDLE TargetProcessHandle,
    PHANDLE TargetHandle,
    ACCESS_MASK DesiredAccess,
    ULONG Attributes,
    ULONG Options
);

// Enable debug privilege
BOOL EnableDebugPrivilege(void) {
    HANDLE hToken;
    TOKEN_PRIVILEGES tp = {0};
    LUID luid;
    
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) 
        return FALSE;
        
    if (!LookupPrivilegeValue(NULL, SE_DEBUG_NAME, &luid)) { 
        CloseHandle(hToken); 
        return FALSE; 
    }
    
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    
    AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), NULL, NULL);
    CloseHandle(hToken);
    
    return (GetLastError() == ERROR_SUCCESS);
}

// Helper: check if handle is a "Mutant" and matches target name
BOOL IsTargetMutex(HANDLE h) {
    // Query type
    ULONG sz = 0x1000;
    POBJECT_TYPE_INFORMATION pti = (POBJECT_TYPE_INFORMATION)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sz);
    if (!pti) return FALSE;
    
    NTSTATUS st = NtQueryObject(h, ObjectTypeInformation, pti, sz, &sz);
    if (st != 0) { 
        HeapFree(GetProcessHeap(), 0, pti); 
        return FALSE; 
    }
    
    BOOL isMutant = FALSE;
    if (pti->Name.Buffer && pti->Name.Length) {
        // Type name is "Mutant" for mutexes
        wchar_t *typeName = pti->Name.Buffer;
        if (_wcsicmp(typeName, L"Mutant") == 0) isMutant = TRUE;
    }
    HeapFree(GetProcessHeap(), 0, pti);
    if (!isMutant) return FALSE;

    // Query name
    sz = 0x1000;
    POBJECT_NAME_INFORMATION pni = (POBJECT_NAME_INFORMATION)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sz);
    if (!pni) return FALSE;
    
    st = NtQueryObject(h, ObjectNameInformation, pni, sz, &sz);
    if (st != 0) { 
        HeapFree(GetProcessHeap(), 0, pni); 
        return FALSE; 
    }

    BOOL match = FALSE;
    if (pni->Name.Buffer && pni->Name.Length) {
        // Expect: \BaseNamedObjects\XWeChat_App_Instance_Identity_Mutex_Name
        if (wcsstr(pni->Name.Buffer, L"\\BaseNamedObjects\\XWeChat_App_Instance_Identity_Mutex_Name")) {
            match = TRUE;
        }
    }
    HeapFree(GetProcessHeap(), 0, pni);
    return match;
}

DWORD WINAPI CloseWeChatMutex(LPVOID lpParam) {
    EnableDebugPrivilege();

    // Get the handle to ntdll
    HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
    if (!hNtDll) {
        MessageBoxA(NULL, "Failed to get ntdll handle", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }

    // Get function addresses
    PNtQuerySystemInformation NtQuerySystemInformation = 
        (PNtQuerySystemInformation)GetProcAddress(hNtDll, "NtQuerySystemInformation");
    PNtQueryObject NtQueryObject = 
        (PNtQueryObject)GetProcAddress(hNtDll, "NtQueryObject");
    PNtDuplicateObject NtDuplicateObject = 
        (PNtDuplicateObject)GetProcAddress(hNtDll, "NtDuplicateObject");
        
    if (!NtQuerySystemInformation || !NtQueryObject || !NtDuplicateObject) {
        MessageBoxA(NULL, "Failed to get required NT functions", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }

    // Query system handle information
    ULONG bufferSize = 0x40000;
    PBYTE buffer = NULL;
    NTSTATUS status;
    
    do {
        buffer = (PBYTE)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, bufferSize);
        if (!buffer) {
            MessageBoxA(NULL, "Failed to allocate memory", "Error", MB_OK | MB_ICONERROR);
            return 1;
        }
        
        status = NtQuerySystemInformation(SystemHandleInformation, buffer, bufferSize, &bufferSize);
        if (status == 0xC0000004L) { // STATUS_INFO_LENGTH_MISMATCH
            HeapFree(GetProcessHeap(), 0, buffer);
            bufferSize *= 2;
        } else {
            break;
        }
    } while (TRUE);
    
    if (status != 0) { 
        HeapFree(GetProcessHeap(), 0, buffer); 
        MessageBoxA(NULL, "Failed to query system information", "Error", MB_OK | MB_ICONERROR);
        return 1; 
    }

    PSYSTEM_HANDLE_INFORMATION handleInfo = (PSYSTEM_HANDLE_INFORMATION)buffer;

    // Find WeChat process ID
    DWORD targetProcessId = 0;
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32 pe32 = {0};
        pe32.dwSize = sizeof(PROCESSENTRY32);
        
        if (Process32First(hSnapshot, &pe32)) {
            do {
                if (lstrcmpiA(pe32.szExeFile, "Weixin.exe") == 0) {
                    targetProcessId = pe32.th32ProcessID;
                    break;
                }
            } while (Process32Next(hSnapshot, &pe32));
        }
        CloseHandle(hSnapshot);
    }
    
    if (targetProcessId == 0) {
        HeapFree(GetProcessHeap(), 0, buffer);
        MessageBoxA(NULL, "WeChat process not found", "Error", MB_OK | MB_ICONERROR);
        return 1;
    }

    HANDLE hTargetProc = OpenProcess(PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, targetProcessId);
    if (!hTargetProc) { 
        HeapFree(GetProcessHeap(), 0, buffer); 
        MessageBoxA(NULL, "Failed to open WeChat process", "Error", MB_OK | MB_ICONERROR);
        return 1; 
    }

    BOOL found = FALSE;
    for (ULONG i = 0; i < handleInfo->HandleCount; i++) {
        SYSTEM_HANDLE h = handleInfo->Handles[i];
        if (h.ProcessId != targetProcessId) continue;

        HANDLE dup = NULL;
        status = NtDuplicateObject(hTargetProc, (HANDLE)h.Handle, GetCurrentProcess(), &dup, 0, 0, 0);
        if (status != 0 || !dup) continue;

        if (IsTargetMutex(dup)) {
            // Close it in the target process
            status = NtDuplicateObject(hTargetProc, (HANDLE)h.Handle, NULL, NULL, 0, 0, 0x00000001 /* DUPLICATE_CLOSE_SOURCE */);
            CloseHandle(dup);
            if (status == 0) {
                found = TRUE;
                MessageBoxA(NULL, "Unlocked! Now you can open multiple wechat.",
                    "Success", MB_OK | MB_ICONINFORMATION);
                break;
            }
        }
        CloseHandle(dup);
    }

    CloseHandle(hTargetProc);
    HeapFree(GetProcessHeap(), 0, buffer);
    
    if (!found) {
        MessageBoxA(NULL, "Target lock handle not found in WeChat process.\n" 
            "Maybe run as Administrator and try again.",
            "Failed", MB_OK | MB_ICONWARNING);
    }
    
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        // Create a thread to perform handle enumeration
        CreateThread(NULL, 0, CloseWeChatMutex, NULL, 0, NULL);
        break;
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}