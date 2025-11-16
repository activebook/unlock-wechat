#pragma once

#include <windows.h>

// Icon identifier
#define IDI_ICON1 101

// Register window control IDs
#define EDIT_UNIQUE 1101
#define EDIT_LICENSE 1102
#define BTN_REGISTER 1103
#define BTN_EXIT_APP 1104

// License file
#define LICENSE_FILE "license.key"

// Button identifier
#define BTN_UNLOCK 1001

// Global handles (declared in main.c)
extern HWND g_hRegisterWindow;
extern HWND g_hMainWindow;
extern BOOL g_bRegistered;
extern BOOL g_bUnlockRequested;

// Function declarations
BOOL LoadLicense(char* license, int maxLen);
BOOL SaveLicense(const char* license);
LRESULT CALLBACK RegisterProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
void PerformUnlock(HWND hwnd);
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd);
