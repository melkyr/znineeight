@echo off
REM Builds the main RetroZig bootstrap compiler.
echo Building zig0.exe...
cl /nologo /Za /W3 /Isrc/include src/bootstrap/bootstrap_all.cpp /Fezig0.exe

if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo zig0.exe built successfully.
