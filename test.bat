@echo off
echo Compiling and running all tests...

REM Compile all test files and necessary source files together
cl.exe /EHsc /W4 /Isrc/include ^
    tests/main.cpp ^
    tests/test_arena.cpp ^
    tests/test_string_interner.cpp ^
    tests/test_memory.cpp ^
    src/bootstrap/string_interner.cpp ^
    /Fe:test_runner.exe

REM Check if compilation was successful
if errorlevel 1 (
    echo Compilation failed!
    exit /b 1
)

REM Run the tests
test_runner.exe

REM Check if tests passed
if errorlevel 1 (
    echo Tests failed!
    exit /b 1
)

echo All tests passed!
exit /b 0
