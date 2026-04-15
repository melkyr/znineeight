@echo off
:: Native Build script for OpenWatcom (wcc386 / wpp386)

REM /bt=nt     : target Windows NT (also works for 9x)
REM /d_WIN32   : define _WIN32
REM /dWINVER=0x0410 : target Windows 98
REM /d_CRT_SECURE_NO_WARNINGS : ignore secure CRT warnings
REM /ox        : maximum optimization
REM /I.        : include current directory
REM /Isrc\include : include compiler path
REM /w4        : warning level 4

:: Compile zig_runtime.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 zig_runtime.c

:: Compile net_runtime.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 net_runtime.c

:: Compile modules
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 builtin.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 std_debug.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 util.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 std.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 main.c

wlink system nt file *.obj name app.exe library wsock32.lib
