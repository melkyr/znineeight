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
echo Compiling Batch Test Runners...

set BOOTSTRAP_SRCS=src/bootstrap/lexer.cpp src/bootstrap/parser.cpp src/bootstrap/string_interner.cpp src/bootstrap/error_handler.cpp src/bootstrap/symbol_table.cpp src/bootstrap/type_system.cpp src/bootstrap/type_checker.cpp src/bootstrap/compilation_unit.cpp src/bootstrap/source_manager.cpp src/bootstrap/token_supplier.cpp src/bootstrap/c89_feature_validator.cpp src/bootstrap/lifetime_analyzer.cpp src/bootstrap/null_pointer_analyzer.cpp src/bootstrap/double_free_analyzer.cpp src/bootstrap/utils.cpp src/bootstrap/ast_utils.cpp src/bootstrap/error_set_catalogue.cpp src/bootstrap/generic_catalogue.cpp src/bootstrap/error_function_catalogue.cpp src/bootstrap/try_expression_catalogue.cpp src/bootstrap/catch_expression_catalogue.cpp src/bootstrap/orelse_expression_catalogue.cpp src/bootstrap/extraction_analysis_catalogue.cpp src/bootstrap/c89_pattern_generator.cpp src/bootstrap/errdefer_catalogue.cpp src/bootstrap/name_collision_detector.cpp src/bootstrap/signature_analyzer.cpp src/bootstrap/name_mangler.cpp src/bootstrap/call_site_lookup_table.cpp src/bootstrap/indirect_call_catalogue.cpp src/bootstrap/call_resolution_validator.cpp src/bootstrap/codegen.cpp src/bootstrap/c_variable_allocator.cpp src/bootstrap/platform.cpp
set TEST_SRCS=tests/test_*.cpp tests/c89_*.cpp tests/dynamic_array_copy_test.cpp tests/integer_literal_parsing.cpp tests/lexer_*.cpp tests/memory_*.cpp tests/parser_*.cpp tests/return_type_validation_tests.cpp tests/symbol_*.cpp tests/task_119_test.cpp tests/type_*.cpp tests/pointer_arithmetic_test.cpp tests/const_var_crash_test.cpp tests/bug_test_memory.cpp tests/lifetime_analysis_tests.cpp tests/null_pointer_analysis_tests.cpp tests/integration_tests.cpp tests/double_free_analysis_tests.cpp tests/integration/*.cpp

for %%i in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23) do (
    echo Compiling batch %%i...
    cl.exe /nologo /EHsc /W4 /Isrc/include ^
        %BOOTSTRAP_SRCS% ^
        %TEST_SRCS% ^
        tests/main_batch%%i.cpp ^
        /Fe:test_runner_batch%%i.exe
    if errorlevel 1 (
        echo Test runner batch %%i compilation failed!
        exit /b 1
    )
)

echo.
echo Running tests...
call run_all_tests.bat %*
if errorlevel 1 (
    echo Tests failed!
    exit /b 1
)

echo.
echo All tests passed successfully!
exit /b 0
