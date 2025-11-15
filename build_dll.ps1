# Build script for the injection DLL (PowerShell)
# Usage: Launch "Developer Command Prompt for VS" or run vcvars, then run this script from repository root:

Set-Location $PSScriptRoot
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Error "cl (MSVC) not found in PATH. Open Developer Command Prompt or run vcvarsall.bat first."
    exit 1

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

Write-Output "Running: cl /LD openmulti.c openmulti.res /link user32.lib advapi32.lib ntdll.lib /OUT:openmulti.dll"
cl /LD openmulti.c openmulti.res /link user32.lib advapi32.lib ntdll.lib /OUT:openmulti.dll
if ($LASTEXITCODE -eq 0) {
    Write-Output "Build succeeded: .\openmulti.dll"
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
}