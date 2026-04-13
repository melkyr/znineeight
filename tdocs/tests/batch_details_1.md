# Z98 Test Batch 1 Technical Specification

## High-Level Objective
Core compiler infrastructure: Arena Allocator for memory safety and <16MB compliance, DynamicArray for efficient growth, and String Interner for identifier deduplication.

This test batch comprises 82 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_DynamicArray_ShouldUseCopyConstructionOnReallocation`
- **Implementation Source**: `tests/dynamic_array_copy_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `copy_constructions` matches `8`
  2. Assert that `copy_assignments` matches `9`
  ```

### `test_ArenaAllocator_AllocShouldReturn8ByteAligned`
- **Implementation Source**: `tests/memory_alignment_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `uintptr_t` is satisfied
  ```

### `test_arena_alloc_out_of_memory`
- **Implementation Source**: `tests/test_arena_overflow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `ptr equals null` is satisfied
  ```

### `test_arena_alloc_zero_size`
- **Implementation Source**: `tests/test_arena_overflow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `ptr equals null` is satisfied
  ```

### `test_arena_alloc_aligned_out_of_memory`
- **Implementation Source**: `tests/test_arena_overflow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `ptr equals null` is satisfied
  ```

### `test_arena_alloc_aligned_overflow_check`
- **Implementation Source**: `tests/test_arena_overflow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `ptr equals null` is satisfied
  ```

### `test_basic_allocation`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `pointer is valid` is satisfied
  ```

### `test_multiple_allocations`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `p1 not equals null` is satisfied
  2. Validate that `p2 not equals null` is satisfied
  ```

### `test_allocation_failure`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `p2 equals null` is satisfied
  ```

### `test_reset`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `p1` is satisfied
  ```

### `test_aligned_allocation`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `p1 not equals null` is satisfied
  2. Validate that `p1` is satisfied
  3. Validate that `p2 not equals null` is satisfied
  4. Validate that `p2` is satisfied
  5. Validate that `arena.alloc(16` is satisfied
  6. Validate that `p3 not equals null` is satisfied
  7. Validate that `p3` is satisfied
  8. Validate that `p4 equals null` is satisfied
  ```

### `test_arena_alloc_hard_limit_abort`
- **Implementation Source**: `tests/test_arena.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_arena_alloc_hard_limit_abort and validate component behavior
  ```

### `test_dynamic_array_append`
- **Implementation Source**: `tests/test_memory.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `arr.length` is satisfied
  2. Validate that `arr[0] equals 10` is satisfied
  3. Validate that `arr[1] equals 20` is satisfied
  ```

### `test_dynamic_array_growth`
- **Implementation Source**: `tests/test_memory.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `arr.length` is satisfied
  2. Validate that `arr[19] equals 19` is satisfied
  ```

### `test_dynamic_array_growth_from_zero`
- **Implementation Source**: `tests/test_memory.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `1` matches `length of arr`
  2. Validate that `arr.getCapacity` is satisfied
  3. Assert that `42` matches `arr[0]`
  ```

### `test_dynamic_array_non_pod_reallocation`
- **Implementation Source**: `tests/memory_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `copy_assignment_calls` matches `9`
  ```

### `test_plat_itoa_conversion`
- **Implementation Source**: `tests/memory_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
) == 0);

    // Test large values using plat_u64_to_string for unsigned
    plat_u64_to_string(4294967295ULL, buffer, sizeof(buffer));
    ASSERT_TRUE(strcmp(buffer,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `strcmp(buffer, "0"` is satisfied
  2. Validate that `strcmp(buffer, "5"` is satisfied
  3. Validate that `strcmp(buffer, "12345"` is satisfied
  4. Validate that `strcmp(buffer, "987654321"` is satisfied
  5. Validate that `strcmp(buffer, "4294967295"` is satisfied
  6. Validate that `strcmp(buffer, "9223372036854775807"` is satisfied
  ```

### `test_string_interning`
- **Implementation Source**: `tests/test_string_interner.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    const char* s2 = interner.intern(
  ```
  ```zig
);
    const char* s3 = interner.intern(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `s1 not equals s2` is satisfied
  2. Validate that `s1 equals s3` is satisfied
  3. Validate that `strcmp(s1, "hello"` is satisfied
  4. Validate that `strcmp(s2, "world"` is satisfied
  ```

### `test_compilation_unit_creation`
- **Implementation Source**: `tests/test_compilation_unit.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `!parser.is_at_end` is satisfied
  2. Validate that `parser.peek` is satisfied
  ```

### `test_compilation_unit_var_decl`
- **Implementation Source**: `tests/test_compilation_unit.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_VAR_DECL` matches `node.type`
  ```

### `test_SymbolBuilder_BuildsCorrectly`
- **Implementation Source**: `tests/symbol_builder_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `strcmp(sym.name, symbol_name` is satisfied
  2. Validate that `sym.kind equals symbol_kind` is satisfied
  3. Validate that `sym.kind of symbol_type equals TYPE_F64` is satisfied
  4. Validate that `sym.location.file_id equals loc.file_id` is satisfied
  5. Validate that `sym.location.line equals loc.line` is satisfied
  6. Validate that `sym.location.column equals loc.column` is satisfied
  7. Validate that `sym.details equals details_ptr` is satisfied
  8. Validate that `sym.scope_level equals scope_level` is satisfied
  9. Validate that `sym.flags equals flags` is satisfied
  ```

### `test_SymbolTable_DuplicateDetection`
- **Implementation Source**: `tests/symbol_table_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `table.insert(symbol` is satisfied
  2. Ensure that `table.insert(symbol` is false
  ```

### `test_SymbolTable_NestedScopes_And_Lookup`
- **Implementation Source**: `tests/symbol_table_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `found_a not equals null` is satisfied
  2. Assert that `1` matches `found_a.scope_level`
  3. Validate that `found_b not equals null` is satisfied
  4. Assert that `2` matches `found_b.scope_level`
  5. Validate that `table.lookup("a"` is satisfied
  6. Validate that `table.lookup("b"` is satisfied
  7. Validate that `found_c not equals null` is satisfied
  8. Assert that `3` matches `found_c.scope_level`
  9. Validate that `shadowed_a not equals null` is satisfied
  10. Assert that `3` matches `shadowed_a.scope_level`
  11. Validate that `table.lookup("c"` is satisfied
  12. Validate that `global_a not equals null` is satisfied
  13. Assert that `1` matches `global_a.scope_level`
  ```

### `test_SymbolTable_HashTableResize`
- **Implementation Source**: `tests/symbol_table_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
, i);
        const char* var_name = interner.intern(buffer, strlen(buffer));
        Symbol symbol = builder.withName(var_name).ofType(SYMBOL_VARIABLE).build();
        ASSERT_TRUE(table.insert(symbol));
    }

    // Verify that all symbols can be found after the resizes
    for (int i = 0; i < num_symbols_to_insert; ++i) {
        char buffer[32];
        sprintf(buffer,
  ```
  ```zig
, i);
        const char* var_name = interner.intern(buffer, strlen(buffer));
        ASSERT_TRUE(table.lookup(var_name) != NULL);
    }

    // Check lookup of a non-existent symbol
    ASSERT_TRUE(table.lookup(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `table.insert(symbol` is satisfied
  2. Validate that `table.lookup(var_name` is satisfied
  3. Validate that `table.lookup("non_existent_var"` is satisfied
  ```

### `test_Lexer_FloatWithUnderscores_IntegerPart`
- **Implementation Source**: `tests/test_lexer_decimal_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Lexer_FloatWithUnderscores_IntegerPart and validate component behavior
  ```

### `test_Lexer_FloatWithUnderscores_FractionalPart`
- **Implementation Source**: `tests/test_lexer_decimal_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Lexer_FloatWithUnderscores_FractionalPart and validate component behavior
  ```

### `test_Lexer_FloatWithUnderscores_ExponentPart`
- **Implementation Source**: `tests/test_lexer_decimal_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Lexer_FloatWithUnderscores_ExponentPart and validate component behavior
  ```

### `test_Lexer_FloatWithUnderscores_AllParts`
- **Implementation Source**: `tests/test_lexer_decimal_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Lexer_FloatWithUnderscores_AllParts and validate component behavior
  ```

### `test_Lexer_FloatSimpleDecimal`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 3.14` is satisfied
  ```

### `test_Lexer_FloatNoFractionalPart`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 123.0` is satisfied
  ```

### `test_Lexer_FloatNoIntegerPart`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_ERROR` matches `token.type`
  ```

### `test_Lexer_FloatWithExponent`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 1.23e+4` is satisfied
  ```

### `test_Lexer_FloatWithNegativeExponent`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 5.67E-8` is satisfied
  ```

### `test_Lexer_FloatExponentNoSign`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 9.0e10` is satisfied
  ```

### `test_Lexer_FloatIntegerWithExponent`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 1e10` is satisfied
  ```

### `test_Lexer_FloatExponentNoDigits`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `t1.type`
  2. Validate that `compare_floats(t1.value.floating_point, 1.2` is satisfied
  3. Assert that `TOKEN_IDENTIFIER` matches `t2.type`
  ```

### `test_Lexer_FloatHexSimple`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 6.5` is satisfied
  ```

### `test_Lexer_FloatHexNoFractionalPart`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 8.0` is satisfied
  ```

### `test_Lexer_FloatHexNegativeExponent`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FLOAT_LITERAL` matches `token.type`
  2. Validate that `compare_floats(token.value.floating_point, 10.737548828125` is satisfied
  ```

### `test_Lexer_FloatHexInvalidFormat`
- **Implementation Source**: `tests/test_lexer_float.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_ERROR` matches `token1.type`
  2. Assert that `TOKEN_ERROR` matches `token2.type`
  3. Assert that `TOKEN_ERROR` matches `token3.type`
  ```

### `test_lexer_integer_overflow`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_ERROR`
  ```

### `test_lexer_c_string_literal`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_ERROR`
  ```

### `test_lexer_handles_unicode_correctly`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_CHAR_LITERAL`
  2. Assert that `token.value.character` matches `0x1F4A9`
  ```

### `test_lexer_handles_unterminated_char_hex_escape`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_ERROR`
  ```

### `test_lexer_handles_unterminated_string_hex_escape`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_ERROR`
  ```

### `test_Lexer_HandlesU64Integer`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
18446744073709551610
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_INTEGER_LITERAL` is satisfied
  2. Validate that `token.value.integer_literal.value equals 0xFFFFFFFFFFFFFFFAULL` is satisfied
  ```

### `test_Lexer_UnterminatedCharHexEscape`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_ERROR` is satisfied
  ```

### `test_Lexer_UnterminatedStringHexEscape`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
' at the end of the file could cause a read past the null terminator.
    const char* source =
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_ERROR` is satisfied
  ```

### `test_Lexer_UnicodeInStringLiteral`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
\xE2\x82\xAC
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_STRING_LITERAL` is satisfied
  2. Validate that `strcmp(token.value.identifier, expected_utf8` is satisfied
  ```

### `test_IntegerLiterals`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
123 0xFF
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_INTEGER_LITERAL`
  2. Assert that `token.value.integer_literal.value` matches `123`
  3. Assert that `token.value.integer_literal.value` matches `255`
  4. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_Lexer_StringLiteral_EscapedCharacters`
- **Implementation Source**: `tests/test_string_literal.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
, t1.value.identifier);

    // 2. Test a mix of escapes
    const char* source2 =
  ```
  ```zig
, t2.value.identifier);

    // 3. Test hex escape sequence
    const char* source3 =
  ```
  ```zig
, t3.value.identifier);

    // 4. Test invalid escape sequence
    const char* source4 =
  ```
  ```zig
, source4, strlen(source4));
    Lexer lexer4(sm4, interner, arena, file_id4);
    Token t4 = lexer4.nextToken();
    ASSERT_EQ(TOKEN_ERROR, t4.type);

    // 5. Test unterminated string
    const char* source5 =
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t1.type` matches `TOKEN_STRING_LITERAL`
  2. Assert that `t2.type` matches `TOKEN_STRING_LITERAL`
  3. Assert that `t3.type` matches `TOKEN_STRING_LITERAL`
  4. Assert that `t4.type` matches `TOKEN_ERROR`
  5. Assert that `t5.type` matches `TOKEN_ERROR`
  ```

### `test_Lexer_StringLiteral_LongString`
- **Implementation Source**: `tests/test_string_literal.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    for (int i = 0; i < 300; ++i) {
        strcat(long_string_source,
  ```
  ```zig
);
     for (int i = 0; i < 300; ++i) {
        strcat(expected_string,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `TOKEN_STRING_LITERAL`
  ```

### `test_IntegerLiteralParsing_UnsignedSuffix`
- **Implementation Source**: `tests/integer_literal_parsing.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: u32 = 123u;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals (ASTNode*` is satisfied
  2. Assert that `NODE_VAR_DECL` matches `node.type`
  3. Validate that `var_decl.initializer not equals (ASTNode*` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `var_decl.initializer.type`
  5. Assert that `123` matches `int_literal.value`
  6. Validate that `int_literal.is_unsigned` is satisfied
  7. Ensure that `int_literal.is_long` is false
  ```

### `test_IntegerLiteralParsing_LongSuffix`
- **Implementation Source**: `tests/integer_literal_parsing.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i64 = 456L;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals (ASTNode*` is satisfied
  2. Assert that `NODE_VAR_DECL` matches `node.type`
  3. Validate that `var_decl.initializer not equals (ASTNode*` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `var_decl.initializer.type`
  5. Assert that `456` matches `int_literal.value`
  6. Ensure that `int_literal.is_unsigned` is false
  7. Validate that `int_literal.is_long` is satisfied
  ```

### `test_IntegerLiteralParsing_UnsignedLongSuffix`
- **Implementation Source**: `tests/integer_literal_parsing.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: u64 = 789UL;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals (ASTNode*` is satisfied
  2. Assert that `NODE_VAR_DECL` matches `node.type`
  3. Validate that `var_decl.initializer not equals (ASTNode*` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `var_decl.initializer.type`
  5. Assert that `789` matches `int_literal.value`
  6. Validate that `int_literal.is_unsigned` is satisfied
  7. Validate that `int_literal.is_long` is satisfied
  ```

### `test_single_char_tokens`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
+\t-
/ *;(){}[]@
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_PLUS`
  2. Assert that `token.location.line` matches `1`
  3. Assert that `token.location.column` matches `1`
  4. Assert that `token.type` matches `TOKEN_MINUS`
  5. Assert that `token.location.column` matches `5`
  6. Assert that `token.type` matches `TOKEN_SLASH`
  7. Assert that `token.location.line` matches `2`
  8. Assert that `token.type` matches `TOKEN_STAR`
  9. Assert that `token.location.column` matches `3`
  10. Assert that `token.type` matches `TOKEN_SEMICOLON`
  11. Assert that `token.location.column` matches `4`
  12. Assert that `token.type` matches `TOKEN_LPAREN`
  13. Assert that `token.type` matches `TOKEN_RPAREN`
  14. Assert that `token.location.column` matches `6`
  15. Assert that `token.type` matches `TOKEN_LBRACE`
  16. Assert that `token.location.column` matches `7`
  17. Assert that `token.type` matches `TOKEN_RBRACE`
  18. Assert that `token.location.column` matches `8`
  19. Assert that `token.type` matches `TOKEN_LBRACKET`
  20. ... (additional verification assertions)
  ```

### `test_multi_char_tokens`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
== != <= >=
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_EQUAL_EQUAL`
  2. Assert that `token.location.line` matches `1`
  3. Assert that `token.location.column` matches `1`
  4. Assert that `token.type` matches `TOKEN_BANG_EQUAL`
  5. Assert that `token.location.column` matches `4`
  6. Assert that `token.type` matches `TOKEN_LESS_EQUAL`
  7. Assert that `token.location.column` matches `7`
  8. Assert that `token.type` matches `TOKEN_GREATER_EQUAL`
  9. Assert that `token.location.column` matches `10`
  10. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_assignment_vs_equality`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
= == = > >= < <= ! !=
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_EQUAL`
  2. Assert that `token.location.column` matches `1`
  3. Assert that `token.type` matches `TOKEN_EQUAL_EQUAL`
  4. Assert that `token.location.column` matches `3`
  5. Assert that `token.location.column` matches `6`
  6. Assert that `token.type` matches `TOKEN_GREATER`
  7. Assert that `token.location.column` matches `8`
  8. Assert that `token.type` matches `TOKEN_GREATER_EQUAL`
  9. Assert that `token.location.column` matches `10`
  10. Assert that `token.type` matches `TOKEN_LESS`
  11. Assert that `token.location.column` matches `13`
  12. Assert that `token.type` matches `TOKEN_LESS_EQUAL`
  13. Assert that `token.location.column` matches `15`
  14. Assert that `token.type` matches `TOKEN_BANG`
  15. Assert that `token.location.column` matches `18`
  16. Assert that `token.type` matches `TOKEN_BANG_EQUAL`
  17. Assert that `token.location.column` matches `20`
  18. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_lex_arithmetic_and_bitwise_operators`
- **Implementation Source**: `tests/test_lexer_operators.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
% ~ & | ^ << >>
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_PERCENT` matches `t.type`
  2. Assert that `TOKEN_TILDE` matches `t.type`
  3. Assert that `TOKEN_AMPERSAND` matches `t.type`
  4. Assert that `TOKEN_PIPE` matches `t.type`
  5. Assert that `TOKEN_CARET` matches `t.type`
  6. Assert that `TOKEN_LARROW2` matches `t.type`
  7. Assert that `TOKEN_RARROW2` matches `t.type`
  8. Assert that `TOKEN_EOF` matches `t.type`
  ```

### `test_Lexer_RangeExpression`
- **Implementation Source**: `tests/test_lexer_operators.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_INTEGER_LITERAL` matches `t.type`
  2. Assert that `3` matches `t.value.integer_literal.value`
  3. Assert that `TOKEN_RANGE` matches `t.type`
  4. Assert that `7` matches `t.value.integer_literal.value`
  5. Assert that `TOKEN_EOF` matches `t.type`
  ```

### `test_lex_compound_assignment_operators`
- **Implementation Source**: `tests/test_lexer_compound_operators.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
+= -= *= /= %= &= |= ^= <<= >>=
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_PLUS_EQUAL` matches `t.type`
  2. Assert that `TOKEN_MINUS_EQUAL` matches `t.type`
  3. Assert that `TOKEN_STAR_EQUAL` matches `t.type`
  4. Assert that `TOKEN_SLASH_EQUAL` matches `t.type`
  5. Assert that `TOKEN_PERCENT_EQUAL` matches `t.type`
  6. Assert that `TOKEN_AMPERSAND_EQUAL` matches `t.type`
  7. Assert that `TOKEN_PIPE_EQUAL` matches `t.type`
  8. Assert that `TOKEN_CARET_EQUAL` matches `t.type`
  9. Assert that `TOKEN_LARROW2_EQUAL` matches `t.type`
  10. Assert that `TOKEN_RARROW2_EQUAL` matches `t.type`
  11. Assert that `TOKEN_EOF` matches `t.type`
  ```

### `test_LexerSpecialOperators`
- **Implementation Source**: `tests/test_lexer_special_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
. .* .? ? ** +% -% *%
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_DOT` matches `t.type`
  2. Assert that `TOKEN_DOT_ASTERISK` matches `t.type`
  3. Assert that `TOKEN_DOT_QUESTION` matches `t.type`
  4. Assert that `TOKEN_QUESTION` matches `t.type`
  5. Assert that `TOKEN_STAR` matches `t.type`
  6. Assert that `TOKEN_PLUSPERCENT` matches `t.type`
  7. Assert that `TOKEN_MINUSPERCENT` matches `t.type`
  8. Assert that `TOKEN_STARPERCENT` matches `t.type`
  9. Assert that `TOKEN_EOF` matches `t.type`
  ```

### `test_LexerSpecialOperatorsMixed`
- **Implementation Source**: `tests/test_lexer_special_ops.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
.+*?**+
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_DOT` matches `t.type`
  2. Assert that `TOKEN_PLUS` matches `t.type`
  3. Assert that `TOKEN_STAR` matches `t.type`
  4. Assert that `TOKEN_QUESTION` matches `t.type`
  5. Assert that `TOKEN_EOF` matches `t.type`
  ```

### `test_Lexer_Delimiters`
- **Implementation Source**: `tests/test_lexer_delimiters.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
: -> =>
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_COLON`
  2. Assert that `token.location.column` matches `1`
  3. Assert that `token.type` matches `TOKEN_ARROW`
  4. Assert that `token.location.column` matches `3`
  5. Assert that `token.type` matches `TOKEN_FAT_ARROW`
  6. Assert that `token.location.column` matches `6`
  7. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_Lexer_DotOperators`
- **Implementation Source**: `tests/test_lexer_delimiters.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
. .. ... .ident
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_DOT`
  2. Assert that `token.location.column` matches `1`
  3. Assert that `token.type` matches `TOKEN_RANGE`
  4. Assert that `token.location.column` matches `3`
  5. Assert that `token.type` matches `TOKEN_ELLIPSIS`
  6. Assert that `token.location.column` matches `6`
  7. Assert that `token.location.column` matches `10`
  8. Assert that `token.type` matches `TOKEN_IDENTIFIER`
  9. Assert that `token.location.column` matches `11`
  10. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_skip_comments`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
// this is a line comment
+
/* this is a block comment */
-
// another line comment at EOF
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_PLUS`
  2. Assert that `token.location.line` matches `2`
  3. Assert that `token.location.column` matches `1`
  4. Assert that `token.type` matches `TOKEN_MINUS`
  5. Assert that `token.location.line` matches `4`
  6. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_nested_block_comments`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
/* start /* nested */ end */+
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_PLUS`
  2. Assert that `token.location.line` matches `1`
  3. Assert that `token.location.column` matches `29`
  4. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_unterminated_block_comment`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
/* this comment is not closed
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_lex_visibility_and_linkage_keywords`
- **Implementation Source**: `tests/test_lexer_keywords.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
export extern pub linksection usingnamespace
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `parser.advance` matches `TOKEN_EXPORT`
  2. Assert that `parser.advance` matches `TOKEN_EXTERN`
  3. Assert that `parser.advance` matches `TOKEN_PUB`
  4. Assert that `parser.advance` matches `TOKEN_LINKSECTION`
  5. Assert that `parser.advance` matches `TOKEN_USINGNAMESPACE`
  6. Assert that `parser.peek` matches `TOKEN_EOF`
  ```

### `test_lex_compile_time_and_special_function_keywords`
- **Implementation Source**: `tests/test_compile_time_keywords.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
asm comptime errdefer inline noinline test unreachable
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `parser.advance` matches `TOKEN_ASM`
  2. Assert that `parser.advance` matches `TOKEN_COMPTIME`
  3. Assert that `parser.advance` matches `TOKEN_ERRDEFER`
  4. Assert that `parser.advance` matches `TOKEN_INLINE`
  5. Assert that `parser.advance` matches `TOKEN_NOINLINE`
  6. Assert that `parser.advance` matches `TOKEN_TEST`
  7. Assert that `parser.advance` matches `TOKEN_UNREACHABLE`
  8. Assert that `parser.peek` matches `TOKEN_EOF`
  ```

### `test_lex_miscellaneous_keywords`
- **Implementation Source**: `tests/test_lexer_keywords.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
addrspace align allowzero and anyframe anytype callconv noalias nosuspend or packed threadlocal volatile
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `parser.advance` matches `TOKEN_ADDRSPACE`
  2. Assert that `parser.advance` matches `TOKEN_ALIGN`
  3. Assert that `parser.advance` matches `TOKEN_ALLOWZERO`
  4. Assert that `parser.advance` matches `TOKEN_AND`
  5. Assert that `parser.advance` matches `TOKEN_ANYFRAME`
  6. Assert that `parser.advance` matches `TOKEN_ANYTYPE`
  7. Assert that `parser.advance` matches `TOKEN_CALLCONV`
  8. Assert that `parser.advance` matches `TOKEN_NOALIAS`
  9. Assert that `parser.advance` matches `TOKEN_NOSUSPEND`
  10. Assert that `parser.advance` matches `TOKEN_OR`
  11. Assert that `parser.advance` matches `TOKEN_PACKED`
  12. Assert that `parser.advance` matches `TOKEN_THREADLOCAL`
  13. Assert that `parser.advance` matches `TOKEN_VOLATILE`
  14. Assert that `parser.peek` matches `TOKEN_EOF`
  ```

### `test_lex_missing_keywords`
- **Implementation Source**: `tests/test_missing_keywords.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
defer fn var
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `parser.advance` matches `TOKEN_DEFER`
  2. Assert that `parser.advance` matches `TOKEN_FN`
  3. Assert that `parser.advance` matches `TOKEN_VAR`
  4. Assert that `parser.peek` matches `TOKEN_EOF`
  ```

### `test_lexer_handles_tab_correctly`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_IDENTIFIER`
  2. Assert that `token.location.column` matches `5`
  ```

### `test_lexer_handles_long_identifier`
- **Implementation Source**: `tests/lexer_edge_cases.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_IDENTIFIER`
  ```

### `test_Lexer_HandlesLongIdentifier`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_IDENTIFIER` is satisfied
  2. Validate that `strcmp(token.value.identifier, long_identifier` is satisfied
  ```

### `test_Lexer_NumericLookaheadSafety`
- **Implementation Source**: `tests/lexer_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
should result in an integer token '1', not a float.
    const char* source =
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `token.type equals TOKEN_INTEGER_LITERAL` is satisfied
  ```

### `test_token_fields_are_initialized`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_FN` matches `token.type`
  2. Validate that `token.value.integer_literal.value equals 0` is satisfied
  ```

### `test_Lexer_ComprehensiveCrossGroup`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
if (x > 10) {
  return 0xFF;
} else {
  while (i < 100) {
    i += 1;
  }
}
const pi = 3.14;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `expected_tokens[i]`
  ```

### `test_Lexer_IdentifiersAndStrings`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
my_var \
  ```
  ```zig
_another_var \
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `TOKEN_IDENTIFIER`
  2. Assert that `t.type` matches `TOKEN_STRING_LITERAL`
  3. Assert that `t.type` matches `TOKEN_EOF`
  ```

### `test_Lexer_ErrorConditions`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `TOKEN_ERROR`
  2. Assert that `t.type` matches `TOKEN_FLOAT_LITERAL`
  3. Assert that `t.type` matches `TOKEN_IDENTIFIER`
  4. Assert that `t.type` matches `TOKEN_EOF`
  ```

### `test_IntegerRangeAmbiguity`
- **Implementation Source**: `tests/test_lexer.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `token.type` matches `TOKEN_INTEGER_LITERAL`
  2. Assert that `token.value.integer_literal.value` matches `0`
  3. Assert that `token.type` matches `TOKEN_RANGE`
  4. Assert that `token.value.integer_literal.value` matches `10`
  5. Assert that `token.type` matches `TOKEN_EOF`
  ```

### `test_Lexer_MultiLineIntegrationTest`
- **Implementation Source**: `tests/test_lexer_integration.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const pi = 3.14_159;
const limit = 100.;
for (i in 1..10) {
    const val = 1.2e+g;
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `e.type`
  2. Assert that `t.location.line` matches `e.line`
  3. Assert that `t.location.column` matches `e.col`
  4. Validate that `compare_floats(e.float_val, t.value.floating_point` is satisfied
  5. Assert that `t.value.integer_literal.value` matches `u64)atoi(e.value`
  ```
