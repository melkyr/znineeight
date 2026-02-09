@echo off
setlocal enabledelayedexpansion

set PROJECT_ROOT=%~dp0..
set BUILD_DIR=%PROJECT_ROOT%\build
set BIN_DIR=%PROJECT_ROOT%\bin

echo === RetroZig Clean Environment Setup ===

:: Verify MSVC 6.0-era compatibility (heuristic check)
if not exist "C:\Program Files (x86)\Microsoft Visual Studio\VC98\Bin\cl.exe" (
    echo INFO: MSVC 6.0 toolchain not found. Using modern MSVC with /Zc:wchar_t- /GR- flags recommended.
)

:: Purge and recreate build directories
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%BIN_DIR%" rmdir /s /q "%BIN_DIR%"
mkdir "%BUILD_DIR%\obj"
mkdir "%BIN_DIR%"

:: Clean root directory of legacy artifacts
if exist "%PROJECT_ROOT%\zig0.exe" del /f /q "%PROJECT_ROOT%\zig0.exe"
if exist "%PROJECT_ROOT%\test_runner_batch*.exe" del /f /q "%PROJECT_ROOT%\test_runner_batch*.exe"
if exist "%PROJECT_ROOT%\*.obj" del /f /q "%PROJECT_ROOT%\*.obj"

echo ✓ Build environment initialized at %BUILD_DIR%
echo ✓ Binary output directory: %BIN_DIR%
echo ✓ Ready for compilation.
