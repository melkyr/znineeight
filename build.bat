@echo off
REM Builds the main RetroZig bootstrap compiler.
echo Building zig0.exe...
cl.exe /nologo /EHsc /W4 /DDEBUG /Isrc/include src/bootstrap/bootstrap_all.cpp /Fe:zig0.exe

if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo zig0.exe built successfully.
