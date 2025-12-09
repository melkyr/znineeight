@echo off
REM Deletes all build artifacts (executables and object files).
echo Cleaning build artifacts...
del /q zig0.exe > nul 2>&1
del /q test_runner.exe > nul 2>&1
del /q *.obj > nul 2>&1
echo Clean complete.
