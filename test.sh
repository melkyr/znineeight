#!/bin/bash
echo "Compiling and running tests..."

g++ -std=c++98 -Wall -Isrc/include \
    tests/main.cpp \
    src/bootstrap/string_interner.cpp \
    src/bootstrap/source_manager.cpp \
    src/bootstrap/error_handler.cpp \
    src/bootstrap/lexer.cpp \
    src/bootstrap/parser.cpp \
    src/bootstrap/symbol_table.cpp \
    src/bootstrap/type_system.cpp \
    src/bootstrap/type_checker.cpp \
    tests/parser_bug_fixes.cpp \
    tests/type_checker_void_tests.cpp \
    tests/type_checker_pointer_operations.cpp \
    tests/type_checker_pointer_arithmetic.cpp \
    tests/type_checker_binary_ops.cpp \
    tests/type_checker_bool_tests.cpp \
    tests/type_checker_control_flow.cpp \
    -Isrc/include \
    -o test_runner

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

./test_runner -v

if [ $? -ne 0 ]; then
    echo "Tests failed!"
    exit 1
fi

echo "All tests passed!"
exit 0
