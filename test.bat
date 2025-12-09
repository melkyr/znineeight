@echo off
setlocal

echo Running build script...
call build.bat
if errorlevel 1 (
    echo Build script failed!
    exit /b 1
)

echo.
echo Running compiler self-test...
zig0.exe --self-test
if errorlevel 1 (
    echo Compiler self-test failed!
    exit /b 1
)

echo.
echo Compiling test runner...
cl.exe /nologo /EHsc /W4 /Isrc/include ^
    tests/main.cpp ^
    tests/test_arena.cpp ^
    tests/test_string_interner.cpp ^
    tests/test_memory.cpp ^
    src/bootstrap/string_interner.cpp ^
    /Fe:test_runner.exe

if errorlevel 1 (
    echo Test runner compilation failed!
    exit /b 1
)

echo.
echo Running tests...
test_runner.exe
if errorlevel 1 (
    echo Tests failed!
    exit /b 1
)

echo.
echo All tests passed successfully!
exit /b 0
