#!/bin/bash
echo "Compiling and running tests..."

g++ -std=c++98 -Wall -Wno-error=unused-function -Isrc/include \
    tests/main.cpp \
    src/bootstrap/string_interner.cpp \
    src/bootstrap/source_manager.cpp \
    src/bootstrap/error_handler.cpp \
    src/bootstrap/lexer.cpp \
    src/bootstrap/parser.cpp \
    src/bootstrap/symbol_table.cpp \
    src/bootstrap/type_system.cpp \
    src/bootstrap/type_checker.cpp \
    src/bootstrap/token_supplier.cpp \
    src/bootstrap/compilation_unit.cpp \
    tests/c89_type_compat_tests.cpp \
    tests/c89_type_mapping_tests.cpp \
    tests/const_var_crash_test.cpp \
    tests/dynamic_array_copy_test.cpp \
    tests/integer_literal_parsing.cpp \
    tests/lexer_edge_cases.cpp \
    tests/lexer_fixes.cpp \
    tests/lexer_strings.cpp \
    tests/lexer_utils.cpp \
    tests/memory_alignment_test.cpp \
    tests/memory_tests.cpp \
    tests/parser_bug_fixes.cpp \
    tests/parser_symbol_integration_tests.cpp \
    tests/return_type_validation_tests.cpp \
    tests/symbol_builder_tests.cpp \
    tests/symbol_table_tests.cpp \
    tests/test_arena.cpp \
    tests/test_arena_guard.cpp \
    tests/test_arena_overflow.cpp \
    tests/test_ast.cpp \
    tests/test_ast_async.cpp \
    tests/test_ast_comptime.cpp \
    tests/test_ast_container_declarations.cpp \
    tests/test_ast_control_flow.cpp \
    tests/test_ast_declarations.cpp \
    tests/test_ast_error_nodes.cpp \
    tests/test_ast_statements.cpp \
    tests/test_ast_types.cpp \
    tests/test_char_literal.cpp \
    tests/test_compilation_unit.cpp \
    tests/test_compile_time_keywords.cpp \
    tests/test_error_handler.cpp \
    tests/test_keywords.cpp \
    tests/test_lexer.cpp \
    tests/test_lexer_comments.cpp \
    tests/test_lexer_compound_operators.cpp \
    tests/test_lexer_decimal_float.cpp \
    tests/test_lexer_delimiters.cpp \
    tests/test_lexer_float.cpp \
    tests/test_lexer_integration.cpp \
    tests/test_lexer_keywords.cpp \
    tests/test_lexer_operators.cpp \
    tests/test_lexer_special_ops.cpp \
    tests/test_memory.cpp \
    tests/test_missing_keywords.cpp \
    tests/test_parser_array_slice.cpp \
    tests/test_parser_bitwise_expr.cpp \
    tests/test_parser_block.cpp \
    tests/test_parser_bug.cpp \
    tests/test_parser_catch_expr.cpp \
    tests/test_parser_comptime.cpp \
    tests/test_parser_defer.cpp \
    tests/test_parser_enums.cpp \
    tests/test_parser_errdefer.cpp \
    tests/test_parser_errors.cpp \
    tests/test_parser_expressions.cpp \
    tests/test_parser_fn_decl.cpp \
    tests/test_parser_for_statement.cpp \
    tests/test_parser_functions.cpp \
    tests/test_parser_if_statement.cpp \
    tests/test_parser_integration.cpp \
    tests/test_parser_lifecycle.cpp \
    tests/test_parser_logical_operators.cpp \
    tests/test_parser_memory.cpp \
    tests/test_parser_navigation.cpp \
    tests/test_parser_recursion.cpp \
    tests/test_parser_return.cpp \
    tests/test_parser_struct.cpp \
    tests/test_parser_switch.cpp \
    tests/test_parser_try_expr.cpp \
    tests/test_parser_types.cpp \
    tests/test_parser_unary.cpp \
    tests/test_parser_union.cpp \
    tests/test_parser_vars.cpp \
    tests/test_parser_while.cpp \
    tests/test_source_manager.cpp \
    tests/test_string_interner.cpp \
    tests/test_string_literal.cpp \
    tests/test_utils.cpp \
    tests/type_checker_array_tests.cpp \
    tests/type_checker_assignment_tests.cpp \
    tests/type_checker_binary_ops.cpp \
    tests/type_checker_bool_tests.cpp \
    tests/type_checker_c89_compat_tests.cpp \
    tests/type_checker_control_flow.cpp \
    tests/type_checker_enum_tests.cpp \
    tests/type_checker_expressions.cpp \
    tests/type_checker_float_c89_compat_tests.cpp \
    tests/type_checker_fn_decl.cpp \
    tests/type_checker_literals.cpp \
    tests/type_checker_pointer_arithmetic.cpp \
    tests/type_checker_pointer_operations.cpp \
    tests/type_checker_pointers.cpp \
    tests/type_checker_tests.cpp \
    tests/type_checker_unary_op_c89.cpp \
    tests/type_checker_var_decl.cpp \
    tests/type_checker_void_tests.cpp \
    tests/type_compatibility_tests.cpp \
    tests/type_system_tests.cpp \
    tests/type_to_string_tests.cpp \
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
