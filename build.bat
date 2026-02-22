@echo off
:: Build script for RetroZig bootstrap compiler (zig0)
:: Optimized for MSVC 6.0 on Windows 98

cl /Za /W3 /Isrc/include src\bootstrap\bootstrap_all.cpp /Fezig0.exe
