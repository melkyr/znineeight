@echo off
:: Build script for RetroZig bootstrap compiler (zig0)
:: Optimized for MSVC 6.0 on Windows 98

cl.exe /nologo /EHsc /W4 /DDEBUG /Isrc/include src/bootstrap/bootstrap_all.cpp /Fe:zig0.exe
