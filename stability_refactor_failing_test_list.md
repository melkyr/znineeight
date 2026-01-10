# Failing Tests after Stability Refactor

## Error: `no matching function for call to ‘ErrorHandler::ErrorHandler(SourceManager&)’`
- tests/test_error_handler.cpp

## Error: `‘class ErrorHandler’ has no member named ‘printErrorReport’; did you mean ‘printErrors’`
- tests/test_error_handler.cpp

## Error: `‘std::string’ has no member named ‘back’ or ‘pop_back’`
- tests/test_error_handler.cpp

## Error: `request for member ‘[...]’ in ‘parser’, which is of pointer type ‘Parser*’ (maybe you meant to use ‘->’ ?)`
- tests/test_parser_array_slice.cpp
- tests/test_parser_bitwise_expr.cpp
- tests/test_parser_block.cpp
- tests/test_parser_bug.cpp
- tests/test_parser_catch_expr.cpp
- tests/test_parser_defer.cpp
- tests/test_parser_for_statement.cpp
- tests/test_parser_integration.cpp
- tests/test_parser_logical_operators.cpp
- tests/test_parser_return.cpp
- tests/test_parser_switch.cpp
- tests/test_parser_types.cpp
- tests/test_parser_unary.cpp
- tests/test_parser_union.cpp
- tests/test_parser_vars.cpp
- tests/test_parser_while.cpp
- tests/type_checker_unary_op_c89.cpp

## Error: `conversion from ‘Parser*’ to non-scalar type ‘Parser’ requested`
- tests/test_parser_navigation.cpp

## Error: `request for member ‘parse’ in ‘ctx.ParserTestContext::getParser()’, which is of pointer type ‘Parser*’ (maybe you meant to use ‘->’ ?)`
- tests/type_checker_float_c89_compat_tests.cpp
