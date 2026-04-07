@echo off
:: Experimental Native Build script (MSVC 6.0 / OpenWatcom)

REM ========== MSVC 6.0 (cl.exe) ==========
REM /O2        : optimize for speed
REM /I.        : add current directory for includes
REM /Isrc\include : add compiler include path
REM /D_CRT_SECURE_NO_WARNINGS : silence deprecated CRT warnings
REM /D_WIN32_WINNT=0x0410 : target Windows 98
REM /D_CRT_NONSTDC_NO_DEPRECATE : avoid deprecation warnings
REM /GX        : enable C++ exception handling (required for some STL)
REM /Zm400     : increase PCH memory limit (optional)
REM /nologo    : suppress copyright banner
REM /W3        : warning level 3
REM /c         : compile only (no link)

:: Compile zig_runtime.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c zig_runtime.c

:: Compile modules
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c builtin.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c hello.c

link /nologo /out:app.exe *.obj

REM ========== OpenWatcom (wcc386 / wpp386) ==========
REM /bt=nt     : target Windows NT (also works for 9x)
REM /d_WIN32   : define _WIN32
REM /dWINVER=0x0410 : target Windows 98
REM /d_CRT_SECURE_NO_WARNINGS : ignore secure CRT warnings
REM /ox        : maximum optimization
REM /I.        : include current directory
REM /Isrc\include : include compiler path
REM /w4        : warning level 4
REM /c         : compile only

:: Compile zig_runtime.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 /c zig_runtime.c

:: Compile modules
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 /c builtin.c
wcc386 /bt=nt /d_WIN32 /dWINVER=0x0410 /d_CRT_SECURE_NO_WARNINGS /ox /I. /Isrc/include /w4 /c hello.c

wlink system nt file {*.obj} name app.exe
