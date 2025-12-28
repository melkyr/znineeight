#!/bin/bash
echo "Compiling and running lexer tests..."

g++ -std=c++98 -Wall -Isrc/include \
    tests/main.cpp \
    tests/lexer_edge_cases.cpp \
    tests/test_lexer.cpp \
    tests/test_lexer_comments.cpp \
    tests/test_lexer_float.cpp \
    tests/test_lexer_operators.cpp \
    tests/test_lexer_compound_operators.cpp \
    tests/test_lexer_special_ops.cpp \
    tests/test_char_literal.cpp \
    tests/test_lexer_delimiters.cpp \
    tests/test_lexer_keywords.cpp \
    tests/test_string_literal.cpp \
    tests/test_lexer_decimal_float.cpp \
    tests/test_lexer_integration.cpp \
    src/bootstrap/string_interner.cpp \
    src/bootstrap/source_manager.cpp \
    src/bootstrap/lexer.cpp \
    -Isrc/include \
    -o lexer_test_runner

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

./lexer_test_runner

if [ $? -ne 0 ]; then
    echo "Lexer tests failed!"
    exit 1
fi

echo "All lexer tests passed!"
exit 0
