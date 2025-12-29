#!/bin/bash
echo "Compiling and running all tests..."

g++ -std=c++98 -Wall -Isrc/include \
    tests/main.cpp \
    tests/memory_alignment_test.cpp \
    tests/dynamic_array_copy_test.cpp \
    tests/test_arena.cpp \
    tests/test_arena_guard.cpp \
    tests/test_arena_overflow.cpp \
    tests/test_string_interner.cpp \
    tests/test_memory.cpp \
    tests/memory_tests.cpp \
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
    src/bootstrap/symbol_table.cpp \
    src/bootstrap/type_system.cpp \
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
    tests/test_parser_logical_operators.cpp \
    tests/test_parser_fn_decl.cpp \
    tests/test_parser_block.cpp \
    tests/test_parser_if_statement.cpp \
    tests/test_parser_while.cpp \
    tests/test_parser_for_statement.cpp \
    tests/test_parser_defer.cpp \
    tests/test_parser_errdefer.cpp \
    tests/test_parser_comptime.cpp \
    tests/test_parser_return.cpp \
    tests/test_parser_array_slice.cpp \
    tests/test_parser_expressions.cpp \
    tests/test_parser_bitwise_expr.cpp \
    tests/test_parser_unary.cpp \
    tests/test_parser_switch.cpp \
    tests/test_parser_struct.cpp \
    tests/test_parser_union.cpp \
    tests/test_parser_enums.cpp \
    tests/test_parser_try_expr.cpp \
    tests/test_parser_catch_expr.cpp \
    tests/test_parser_integration.cpp \
    tests/test_parser_functions.cpp \
    tests/test_parser_bug.cpp \
    tests/test_parser_recursion.cpp \
    tests/test_compilation_unit.cpp \
    tests/type_system_tests.cpp \
    tests/symbol_table_tests.cpp \
    tests/symbol_builder_tests.cpp \
    tests/test_parser_lifecycle.cpp \
    tests/lexer_edge_cases.cpp \
    tests/lexer_fixes.cpp \
    tests/lexer_utils.cpp \
    tests/lexer_strings.cpp \
    tests/test_lexer_decimal_float.cpp \
    tests/test_lexer_integration.cpp \
    tests/test_parser_memory.cpp \
    tests/parser_symbol_integration_tests.cpp \
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
