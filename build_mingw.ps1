# Build script for MinGW (PowerShell)
# Usage: Open PowerShell, run from repo root: .\build_mingw.ps1

Set-Location $PSScriptRoot
if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    Write-Error "gcc not found in PATH. Install mingw-w64 or MSYS2 and add gcc to PATH."
    exit 1
}

# Delete existing executable if it exists
if (Test-Path MyWinApp.exe) {
    Remove-Item MyWinApp.exe
}

gcc -o MyWinApp.exe src\main.c -mwindows -ladvapi32 -lkernel32
if ($LASTEXITCODE -eq 0) {
    Write-Output "Build succeeded: .\MyWinApp.exe"
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
}