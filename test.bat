@echo off
echo Running tests...
zig0.exe
test_arena.exe

echo Compiling and running string interner test...
cl.exe /EHsc tests/test_string_interner.cpp src/bootstrap/string_interner.cpp /Fe:test_string_interner.exe
if errorlevel 1 exit /b 1
test_string_interner.exe
if errorlevel 1 exit /b 1
