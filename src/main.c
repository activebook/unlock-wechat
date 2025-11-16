#include <windows.h>
#include <stdio.h>
#include <tlhelp32.h>
#include "../decrypt.h"
#include "main.h"

// Global handles
HWND g_hRegisterWindow = NULL;
HWND g_hMainWindow = NULL;
BOOL g_bRegistered = FALSE;
BOOL g_bUnlockRequested = FALSE;

// License functions
BOOL LoadLicense(char* license, int maxLen) {
    FILE* f = fopen(LICENSE_FILE, "rb");
    if (!f) return FALSE;
    size_t len = fread(license, 1, maxLen - 1, f);
    fclose(f);
    license[len] = 0;
    return TRUE;
}

BOOL SaveLicense(const char* license) {
    FILE* f = fopen(LICENSE_FILE, "wb");
    if (!f) return FALSE;
    fwrite(license, 1, strlen(license), f);
    fclose(f);
    return TRUE;
}

// Register window procedure
LRESULT CALLBACK RegisterProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        {
            BYTE token[4];
            if (!GetMachineToken(token)) {
                MessageBoxA(hwnd, "Failed to get machine token.", "Error", MB_OK);
                return -1;
            }
            char hex[9];
            wsprintfA(hex, "%02X%02X%02X%02X", token[0], token[1], token[2], token[3]);

            // Static Unique Key
            CreateWindowA("STATIC", "Unique ID:", WS_CHILD | WS_VISIBLE | SS_LEFT, 20, 10, 80, 20, hwnd, NULL, NULL, NULL);

            // Readonly edit
            CreateWindowA("EDIT", hex, WS_CHILD | WS_VISIBLE | ES_LEFT | ES_READONLY, 120, 10, 120, 20, hwnd, (HMENU)EDIT_UNIQUE, NULL, NULL);

            // Static License Key
            CreateWindowA("STATIC", "License Key:", WS_CHILD | WS_VISIBLE | SS_LEFT, 20, 40, 120, 20, hwnd, NULL, NULL, NULL);

            // Multiline edit
            CreateWindowA("EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL, 20, 70, 280, 140, hwnd, (HMENU)EDIT_LICENSE, NULL, NULL);

            // Buttons
            CreateWindowA("BUTTON", "Register", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 70, 220, 80, 30, hwnd, (HMENU)BTN_REGISTER, NULL, NULL);
            CreateWindowA("BUTTON", "Exit", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 170, 220, 80, 30, hwnd, (HMENU)BTN_EXIT_APP, NULL, NULL);
        }
        break;
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case BTN_REGISTER:
            char lic[4096];
            GetWindowTextA(GetDlgItem(hwnd, EDIT_LICENSE), lic, sizeof(lic));
            if (CheckLicense(lic)) {
                SaveLicense(lic);
                g_bRegistered = TRUE;
                DestroyWindow(hwnd);
                if (g_bUnlockRequested) {
                    g_bUnlockRequested = FALSE;
                    PerformUnlock(g_hMainWindow);
                }
            } else {
                MessageBoxA(hwnd, "Invalid license key.", "Register", MB_OK | MB_ICONERROR);
            }
            break;
        case BTN_EXIT_APP:
            PostQuitMessage(0);
            break;
        }
        break;
    case WM_CTLCOLORSTATIC:
        SetBkMode((HDC)wParam, TRANSPARENT);
        SetTextColor((HDC)wParam, RGB(0, 0, 0));
        return (LRESULT)GetStockObject(NULL_BRUSH);
    case WM_DESTROY:
        g_hRegisterWindow = NULL;  // Reset when window is destroyed
        // Don't quit if not registered - main window is already open
        break;
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
    return 0;
}

 // Global button handle
HWND g_hUnlockButton = NULL;

// Function to detect WeChat (Weixin) process
DWORD GetWeChatProcessId() {
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        return 0;
    }

    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (!Process32First(hSnapshot, &pe32)) {
        CloseHandle(hSnapshot);
        return 0;
    }

    DWORD pid = 0;
    do {
        if (lstrcmpiA(pe32.szExeFile, "Weixin.exe") == 0) {
            pid = pe32.th32ProcessID;
            break;
        }
    } while (Process32Next(hSnapshot, &pe32));

    CloseHandle(hSnapshot);
    return pid;
}

BOOL FindWeChatProcess() {
    return GetWeChatProcessId() != 0;
}

void GetAllWeChatPids(DWORD* pids, int* count) {
    *count = 0;
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        return;
    }

    PROCESSENTRY32 pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (!Process32First(hSnapshot, &pe32)) {
        CloseHandle(hSnapshot);
        return;
    }

    do {
        if (lstrcmpiA(pe32.szExeFile, "Weixin.exe") == 0) {
            if (*count < 100) {  // Max 100 processes
                pids[*count] = pe32.th32ProcessID;
                (*count)++;
            }
        }
    } while (Process32Next(hSnapshot, &pe32));

    CloseHandle(hSnapshot);
}

// Function to inject DLL into a specific process
BOOL InjectDllIntoProcess(DWORD pid) {
    if (pid == 0) {
        return FALSE;
    }

    // Get the full path to our DLL
    char dllPath[MAX_PATH];
    GetModuleFileNameA(NULL, dllPath, MAX_PATH);
    char* lastSlash = strrchr(dllPath, '\\');
    if (lastSlash) {
        *(lastSlash + 1) = '\0';
        lstrcatA(dllPath, "openmulti.dll");
    }

    // Check if DLL exists
    DWORD attrib = GetFileAttributesA(dllPath);
    if (attrib == INVALID_FILE_ATTRIBUTES || (attrib & FILE_ATTRIBUTE_DIRECTORY)) {
        MessageBoxA(NULL, "openmulti.dll not found. Please place it in the same directory.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Open the target process
    HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (hProcess == NULL) {
        MessageBoxA(NULL, "Failed to open WeChat process. Try running as administrator.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Allocate memory in the target process
    LPVOID pRemoteMem = VirtualAllocEx(hProcess, NULL, strlen(dllPath) + 1, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (pRemoteMem == NULL) {
        CloseHandle(hProcess);
        MessageBoxA(NULL, "Failed to allocate memory in target process.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Write the DLL path to the target process
    if (!WriteProcessMemory(hProcess, pRemoteMem, dllPath, strlen(dllPath) + 1, NULL)) {
        VirtualFreeEx(hProcess, pRemoteMem, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        MessageBoxA(NULL, "Failed to write DLL path to target process.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Get address of LoadLibraryA
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    FARPROC pLoadLibrary = GetProcAddress(hKernel32, "LoadLibraryA");
    if (pLoadLibrary == NULL) {
        VirtualFreeEx(hProcess, pRemoteMem, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        MessageBoxA(NULL, "Failed to get address of LoadLibraryA.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Create remote thread to load the DLL
    HANDLE hThread = CreateRemoteThread(hProcess, NULL, 0, (LPTHREAD_START_ROUTINE)pLoadLibrary, pRemoteMem, 0, NULL);
    if (hThread == NULL) {
        VirtualFreeEx(hProcess, pRemoteMem, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        MessageBoxA(NULL, "Failed to create remote thread.", "Injection Error", MB_OK | MB_ICONERROR);
        return FALSE;
    }

    // Wait for the thread to complete
    WaitForSingleObject(hThread, INFINITE);

    // Clean up
    CloseHandle(hThread);
    VirtualFreeEx(hProcess, pRemoteMem, 0, MEM_RELEASE);
    CloseHandle(hProcess);

    return TRUE;
}

// Function to handle unlock process
void PerformUnlock(HWND hwnd) {
    // Check license first
    char license[4096];
    if (!LoadLicense(license, sizeof(license)) || !CheckLicense(license)) {
        // Not licensed, show register window
        g_bUnlockRequested = TRUE;  // Flag that unlock was attempted
        if (!g_hRegisterWindow) {  // prevent multiple register windows
            // Create register window class (should already be registered)
            // Create register window
            g_hRegisterWindow = CreateWindowExA(
                0,
                "RegisterClass",
                "Register",
                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
                CW_USEDEFAULT, CW_USEDEFAULT, 340, 300,
                NULL, NULL, GetModuleHandle(NULL), NULL
            );

            if (g_hRegisterWindow) {
                // Center the register window
                RECT rc;
                GetWindowRect(g_hRegisterWindow, &rc);
                int ww = rc.right - rc.left;
                int wh = rc.bottom - rc.top;
                int sx = GetSystemMetrics(SM_CXSCREEN);
                int sy = GetSystemMetrics(SM_CYSCREEN);
                int xx = (sx - ww) / 2;
                int yy = (sy - wh) / 2;
                MoveWindow(g_hRegisterWindow, xx, yy, ww, wh, TRUE);
            } else {
                MessageBoxA(hwnd, "Failed to create register window.", "Error", MB_OK);
            }
        } else {
            // Bring existing register window to front
            SetForegroundWindow(g_hRegisterWindow);
        }
        return;
    }

    if (!FindWeChatProcess()) {
        MessageBoxA(hwnd, "WeChat (Weixin) process not found.\n"
            "Please start WeChat (Weixin) first.",
            "Process Detection", MB_OK | MB_ICONWARNING);
        return;
    }

    // Check if already unlocked
    HANDLE hMutex = OpenMutex(MUTEX_ALL_ACCESS, FALSE, "XWeChat_App_Instance_Identity_Mutex_Name");
    if (hMutex == NULL) {
        MessageBoxA(hwnd, "WeChat is already unlocked.", "Already Unlocked", MB_OK | MB_ICONINFORMATION);
        return;
    } else {
        CloseHandle(hMutex);
    }

    // Get all WeChat PIDs
    DWORD pids[100];
    int pidCount;
    GetAllWeChatPids(pids, &pidCount);

    // Inject into all running WeChat processes
    BOOL success = TRUE;
    for (int i = 0; i < pidCount; i++) {
        if (!InjectDllIntoProcess(pids[i])) {
            success = FALSE;
        }
    }

    if (!success) {
        MessageBoxA(hwnd, "Failed to inject DLL into some WeChat processes.", "Injection Failed", MB_OK | MB_ICONERROR);
    }
    // Don't show success message as DLL will show it
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        {
            // Create button and position it in the window
            RECT rcClient;
            GetClientRect(hwnd, &rcClient);
            
            int btnWidth = 220;
            int btnHeight = 30;
            
            // Unlock button
            int btnX = (rcClient.right - btnWidth) / 2;
            int btnY = (rcClient.bottom - btnHeight) / 2;
            g_hUnlockButton = CreateWindowExA(
                0,
                "BUTTON",
                "Unlock Multiple WeChat",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                btnX, btnY, btnWidth, btnHeight,
                hwnd,
                (HMENU)BTN_UNLOCK,
                ((LPCREATESTRUCT)lParam)->hInstance,
                NULL
            );
        }
        break;
    case WM_COMMAND:
        // Handle button clicks
        switch (LOWORD(wParam)) {
        case BTN_UNLOCK:
            PerformUnlock(hwnd);
            break;
        }
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd) {
    // Fix unreferenced parameter warnings
    (void)hPrevInstance;
    (void)lpCmdLine;

    const char CLASS_NAME[] = "WeChatInjectClass";
    const char REGISTER_CLASS_NAME[] = "RegisterClass";

    // Load the icon
    HICON hIcon = LoadIconA(hInstance, MAKEINTRESOURCE(IDI_ICON1));

    // Register main window class
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    wc.hCursor = LoadCursorA(NULL, IDC_ARROW);
    wc.hIcon = hIcon;

    if (!RegisterClassA(&wc)) {
        MessageBoxA(NULL, "Failed to register window class.", "Error", MB_OK | MB_ICONERROR);
        return 0;
    }

    // Register register window class
    WNDCLASSA registerWc = {0};
    registerWc.lpfnWndProc = RegisterProc;
    registerWc.hInstance = hInstance;
    registerWc.lpszClassName = REGISTER_CLASS_NAME;
    registerWc.hCursor = LoadCursorA(NULL, IDC_ARROW);

    if (!RegisterClassA(&registerWc)) {
        MessageBoxA(NULL, "Failed to register register class.", "Error", MB_OK);
        return 0;
    }

    // Initialize crypto
    if (!InitDecrypt()) {
        MessageBoxA(NULL, "Failed to initialize crypto.", "Error", MB_OK);
        return 1;
    }

    // Always create main window
    g_hMainWindow = CreateWindowExA(
        0,
        CLASS_NAME,
        "Unlock WeChat",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 300, 120,
        NULL, NULL, hInstance, NULL
    );

    if (!g_hMainWindow) {
        MessageBoxA(NULL, "Failed to create window.", "Error", MB_OK | MB_ICONERROR);
        return 0;
    }

    // Set window icons
    SendMessageA(g_hMainWindow, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
    SendMessageA(g_hMainWindow, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);

    // Center the window
    RECT rc;
    GetWindowRect(g_hMainWindow, &rc);
    int ww = rc.right - rc.left;
    int wh = rc.bottom - rc.top;
    int sx = GetSystemMetrics(SM_CXSCREEN);
    int sy = GetSystemMetrics(SM_CYSCREEN);
    int xx = (sx - ww) / 2;
    int yy = (sy - wh) / 2;
    MoveWindow(g_hMainWindow, xx, yy, ww, wh, TRUE);

    ShowWindow(g_hMainWindow, nShowCmd);
    UpdateWindow(g_hMainWindow);

    // Message loop
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    CleanupDecrypt();
    return (int)msg.wParam;
}
