@echo off
REM build_owc.bat - build the manual's Z98 example programs for Win9x with
REM OpenWatcom. This is the Win9x companion to build_linux.sh.
REM
REM Emit the Windows-target C89 for an example first:
REM     zig1 -osw -o out hello.z98
REM zig1 writes a self-contained tree into out\ and, because the target is
REM Windows, its own build_target.bat (MSVC) and build_owc.bat (OpenWatcom).
REM This companion follows those emitted conventions; run it from inside an
REM emitted output directory to compile every .c and link one console exe:
REM
REM     cd out
REM     build_owc.bat [OUT]
REM
REM wcc386 /za /we /dZIG_WIN32 /i=.  strict ANSI C, warnings as errors
REM wlink system console op q opt stack=65536
setlocal
if "%~1"=="" (set OUT=prog.exe) else (set OUT=%~1)
echo Compiling...
wcc386 /za /we /dZIG_WIN32 /i=. *.c
if errorlevel 1 goto fail
echo Linking...
wlink system console op q opt stack=65536 file {*.obj} name %OUT%
if errorlevel 1 goto fail
echo Built: %OUT%
goto :eof
:fail
echo Build failed.
exit /b 1
