@echo off
:: Native Build script for MSVC 6.0 (cl.exe)

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

:: Compile net_runtime.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c net_runtime.c

:: Compile modules
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c builtin.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c lib_a.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c lib_b.c
cl /O2 /I. /Isrc/include /D_CRT_SECURE_NO_WARNINGS /D_WIN32_WINNT=0x0410 /D_CRT_NONSTDC_NO_DEPRECATE /GX /Zm400 /nologo /W3 /c main.c

link /nologo /out:app.exe *.obj wsock32.lib
