#include <windows.h>
#include <stdio.h>
#include <tlhelp32.h>

// Icon identifier
#define IDI_ICON1 101

// Button identifier
#define BTN_UNLOCK 1001

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

// Function to inject DLL into WeChat process
BOOL InjectDllIntoWeChat() {
    DWORD pid = GetWeChatProcessId();
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

    if (InjectDllIntoWeChat()) {
        // Don't show success message as DLL will show it
    } else {
        MessageBoxA(hwnd, "Failed to inject DLL into WeChat process.", "Injection Failed", MB_OK | MB_ICONERROR);
    }
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

    // Load the icon
    HICON hIcon = LoadIconA(hInstance, MAKEINTRESOURCE(IDI_ICON1));

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

    HWND hwnd = CreateWindowExA(
        0,
        CLASS_NAME,
        "Unlock WeChat",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, // Non-resizable window
        CW_USEDEFAULT, CW_USEDEFAULT, 300, 120,
        NULL, NULL, hInstance, NULL
    );

    if (!hwnd) {
        MessageBoxA(NULL, "Failed to create window.", "Error", MB_OK | MB_ICONERROR);
        return 0;
    }

    // Set window icons
    SendMessageA(hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
    SendMessageA(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);

    // Center the window on screen
    RECT rc;
    GetWindowRect(hwnd, &rc);
    int windowWidth = rc.right - rc.left;
    int windowHeight = rc.bottom - rc.top;
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    int x = (screenWidth - windowWidth) / 2;
    int y = (screenHeight - windowHeight) / 2;
    MoveWindow(hwnd, x, y, windowWidth, windowHeight, TRUE);

    ShowWindow(hwnd, nShowCmd);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    return (int)msg.wParam;
}
