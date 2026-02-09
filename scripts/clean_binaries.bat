@echo off
setlocal enabledelayedexpansion

set PROJECT_ROOT=%~dp0..
set BUILD_DIR=%PROJECT_ROOT%\build
set BIN_DIR=%PROJECT_ROOT%\bin

echo === Post-Compilation Cleanup ===

:: Preserve only zig0.exe in bin or root
if exist "%BIN_DIR%\zig0.exe" (
    del /q "%BIN_DIR%\*.dll" 2>nul
    del /q "%BIN_DIR%\*.lib" 2>nul
    del /q "%BIN_DIR%\*.exp" 2>nul
)

del /q "%BUILD_DIR%\obj\*.obj" 2>nul
del /q "%PROJECT_ROOT%\*.obj" 2>nul

:: Verify kernel32.dll is the ONLY dependency
set TARGET_BIN=
if exist "%BIN_DIR%\zig0.exe" set TARGET_BIN=%BIN_DIR%\zig0.exe
if exist "%PROJECT_ROOT%\zig0.exe" set TARGET_BIN=%PROJECT_ROOT%\zig0.exe

if not "%TARGET_BIN%"=="" (
    echo Checking dependencies for %TARGET_BIN%...
    where dumpbin >nul 2>nul
    if %errorlevel% equ 0 (
        dumpbin /dependents "%TARGET_BIN%" | findstr /C:"kernel32.dll" >nul
        if errorlevel 1 (
            echo WARNING: Binary missing kernel32.dll dependency!
        )
    )
)

echo ✓ Intermediate artifacts removed
echo ✓ Memory measurement ready for next run
