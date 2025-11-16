# Build script for MSVC `cl` (PowerShell)
# Usage: Launch "Developer Command Prompt for VS" or run vcvars, then run this script from repository root:

Set-Location $PSScriptRoot
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Error "cl (MSVC) not found in PATH. Open Developer Command Prompt or run vcvarsall.bat first."
    exit 1
}

# Delete existing executable if it exists
if (Test-Path UnlockWeChat.exe) {
    Remove-Item UnlockWeChat.exe
}

# Delete existing DLL if it exists
if (Test-Path openmulti.dll) {
    Remove-Item openmulti.dll
}

# Compile the resource file
Write-Output "Compiling resources..."
rc openmulti.rc
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to compile resources with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Build the injection DLL with resources
Write-Output "Building openmulti.dll..."
cl /LD openmulti.c openmulti.res /link user32.lib advapi32.lib ntdll.lib /OUT:openmulti.dll
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build openmulti.dll with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Compile main resources
Write-Output "Compiling main resources..."
rc main.rc
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to compile main resources with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Output "Running: cl /W4 src\main.c decrypt.c main.res /link /SUBSYSTEM:WINDOWS user32.lib advapi32.lib kernel32.lib gdi32.lib crypt32.lib iphlpapi.lib /OUT:UnlockWeChat.exe"
# link explicitly against required libraries to resolve API symbols
cl /W4 src\main.c decrypt.c main.res /link /SUBSYSTEM:WINDOWS user32.lib advapi32.lib kernel32.lib gdi32.lib crypt32.lib iphlpapi.lib /OUT:UnlockWeChat.exe
if ($LASTEXITCODE -eq 0) {
    Write-Output "Build succeeded: .\UnlockWeChat.exe"
    Write-Output "DLL built: .\openmulti.dll"
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
}
