#!/bin/bash
echo "Compiling and running all tests..."

g++ -std=c++98 -Wall -Isrc/include \
    tests/main.cpp \
    tests/test_arena.cpp \
    tests/test_string_interner.cpp \
    tests/test_memory.cpp \
    tests/test_lexer.cpp \
    tests/test_lexer_comments.cpp \
    tests/test_lexer_float.cpp \
    tests/test_lexer_operators.cpp \
    tests/test_lexer_compound_operators.cpp \
    tests/test_lexer_special_ops.cpp \
    src/bootstrap/string_interner.cpp \
    src/bootstrap/source_manager.cpp \
    src/bootstrap/lexer.cpp \
    src/bootstrap/parser.cpp \
    tests/test_char_literal.cpp \
    tests/test_lexer_delimiters.cpp \
    tests/test_lexer_keywords.cpp \
    tests/test_keywords.cpp \
    tests/test_compile_time_keywords.cpp \
    tests/test_string_literal.cpp \
    tests/test_missing_keywords.cpp \
    tests/test_ast.cpp \
    tests/test_ast_statements.cpp \
    tests/test_ast_declarations.cpp \
    tests/test_ast_container_declarations.cpp \
    tests/test_ast_types.cpp \
    tests/test_ast_control_flow.cpp \
    tests/test_ast_error_nodes.cpp \
    tests/test_ast_async.cpp \
    tests/test_ast_comptime.cpp \
    tests/test_parser_navigation.cpp \
    tests/test_parser_vars.cpp \
    tests/test_parser_types.cpp \
    tests/test_parser_errors.cpp \
    tests/test_parser_fn_decl.cpp \
    tests/test_parser_block.cpp \
    tests/test_parser_if_statement.cpp \
    tests/test_parser_while.cpp \
    tests/test_parser_defer.cpp \
    -Isrc/include \
    -o test_runner

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

./test_runner

if [ $? -ne 0 ]; then
    echo "Tests failed!"
    exit 1
fi

echo "All tests passed!"
exit 0
