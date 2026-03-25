@echo off
:: Default build script for RetroZig
:: Optimized for MSVC 6.0 on Windows 98

cl.exe /nologo /W3 /I. /c zig_runtime.c
cl.exe /nologo /W3 /I. /c builtin.c
:: No default main.c
link.exe /nologo /out:app.exe *.obj
