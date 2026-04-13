# Batch 1 Details: Lexical Analysis

## Focus
Lexical Analysis

This batch contains 82 test cases focusing on lexical analysis.

## Test Case Details
### `test_DynamicArray_ShouldUseCopyConstructionOnReallocation`
- **Primary File**: `tests/dynamic_array_copy_test.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_DynamicArray_ShouldUseCopyConstructionOnReallocation specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_ArenaAllocator_AllocShouldReturn8ByteAligned`
- **Primary File**: `tests/memory_alignment_test.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_ArenaAllocator_AllocShouldReturn8ByteAligned specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_arena_alloc_out_of_memory`
- **Primary File**: `tests/test_arena_overflow.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_arena_alloc_out_of_memory specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_arena_alloc_zero_size`
- **Primary File**: `tests/test_arena_overflow.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_arena_alloc_zero_size specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_arena_alloc_aligned_out_of_memory`
- **Primary File**: `tests/test_arena_overflow.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_arena_alloc_aligned_out_of_memory specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_arena_alloc_aligned_overflow_check`
- **Primary File**: `tests/test_arena_overflow.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_arena_alloc_aligned_overflow_check specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_basic_allocation`
- **Primary File**: `tests/test_arena.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_basic_allocation specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_multiple_allocations`
- **Primary File**: `tests/test_arena.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_multiple_allocations specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_allocation_failure`
- **Primary File**: `tests/test_arena.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_allocation_failure specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_reset`
- **Primary File**: `tests/test_arena.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_reset specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_aligned_allocation`
- **Primary File**: `tests/test_arena.cpp`
- **Verification Points**: 8 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_aligned_allocation specific test data structures
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_arena_alloc_hard_limit_abort`
- **Primary File**: `tests/test_arena.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_arena_alloc_hard_limit_abort specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_dynamic_array_append`
- **Primary File**: `tests/test_memory.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_dynamic_array_append specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_dynamic_array_growth`
- **Primary File**: `tests/test_memory.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_dynamic_array_growth specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_dynamic_array_growth_from_zero`
- **Primary File**: `tests/test_memory.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_dynamic_array_growth_from_zero specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_dynamic_array_non_pod_reallocation`
- **Primary File**: `tests/memory_tests.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_dynamic_array_non_pod_reallocation specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_plat_itoa_conversion`
- **Primary File**: `tests/memory_tests.cpp`
- **Verification Points**: 6 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_plat_itoa_conversion specific test data structures
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_string_interning`
- **Primary File**: `tests/test_string_interner.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_string_interning specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_compilation_unit_creation`
- **Primary File**: `tests/test_compilation_unit.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_compilation_unit_var_decl`
- **Primary File**: `tests/test_compilation_unit.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing
- **Test Input (Zig)**:
  ```zig
const x: i32 = 42;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Syntactic Parsing phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_SymbolBuilder_BuildsCorrectly`
- **Primary File**: `tests/symbol_builder_tests.cpp`
- **Verification Points**: 9 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_SymbolBuilder_BuildsCorrectly specific test data structures
  4. Verify that the 9 semantic properties match expected values
  ```

### `test_SymbolTable_DuplicateDetection`
- **Primary File**: `tests/symbol_table_tests.cpp`
- **Verification Points**: 4 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_SymbolTable_DuplicateDetection specific test data structures
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_SymbolTable_NestedScopes_And_Lookup`
- **Primary File**: `tests/symbol_table_tests.cpp`
- **Verification Points**: 16 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_SymbolTable_NestedScopes_And_Lookup specific test data structures
  4. Verify that the 16 semantic properties match expected values
  ```

### `test_SymbolTable_HashTableResize`
- **Primary File**: `tests/symbol_table_tests.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_SymbolTable_HashTableResize specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_Lexer_FloatWithUnderscores_IntegerPart`
- **Primary File**: `tests/test_lexer_decimal_float.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithUnderscores_IntegerPart specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Lexer_FloatWithUnderscores_FractionalPart`
- **Primary File**: `tests/test_lexer_decimal_float.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithUnderscores_FractionalPart specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Lexer_FloatWithUnderscores_ExponentPart`
- **Primary File**: `tests/test_lexer_decimal_float.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithUnderscores_ExponentPart specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Lexer_FloatWithUnderscores_AllParts`
- **Primary File**: `tests/test_lexer_decimal_float.cpp`
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithUnderscores_AllParts specific test data structures
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Lexer_FloatSimpleDecimal`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatSimpleDecimal specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatNoFractionalPart`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatNoFractionalPart specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatNoIntegerPart`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 1 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatNoIntegerPart specific test data structures
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Lexer_FloatWithExponent`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithExponent specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatWithNegativeExponent`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatWithNegativeExponent specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatExponentNoSign`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatExponentNoSign specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatIntegerWithExponent`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatIntegerWithExponent specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatExponentNoDigits`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatExponentNoDigits specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_Lexer_FloatHexSimple`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatHexSimple specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatHexNoFractionalPart`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatHexNoFractionalPart specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatHexNegativeExponent`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 2 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatHexNegativeExponent specific test data structures
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_FloatHexInvalidFormat`
- **Primary File**: `tests/test_lexer_float.cpp`
- **Verification Points**: 3 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_FloatHexInvalidFormat specific test data structures
  4. Verify that the 3 semantic properties match expected values
  ```

### `test_lexer_integer_overflow`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_integer_overflow specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_lexer_c_string_literal`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_c_string_literal specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_lexer_handles_unicode_correctly`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_handles_unicode_correctly specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_lexer_handles_unterminated_char_hex_escape`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_handles_unterminated_char_hex_escape specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_lexer_handles_unterminated_string_hex_escape`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_handles_unterminated_string_hex_escape specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Lexer_HandlesU64Integer`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_HandlesU64Integer specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_UnterminatedCharHexEscape`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_UnterminatedCharHexEscape specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Lexer_UnterminatedStringHexEscape`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_UnterminatedStringHexEscape specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_Lexer_UnicodeInStringLiteral`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_UnicodeInStringLiteral specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_IntegerLiterals`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_IntegerLiterals specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_Lexer_StringLiteral_EscapedCharacters`
- **Primary File**: `tests/test_string_literal.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_StringLiteral_EscapedCharacters specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_Lexer_StringLiteral_LongString`
- **Primary File**: `tests/test_string_literal.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_StringLiteral_LongString specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_IntegerLiteralParsing_UnsignedSuffix`
- **Primary File**: `tests/integer_literal_parsing.cpp`
- **Verification Points**: 7 assertions
- **Test Input (Zig)**:
  ```zig
const x: u32 = 123u;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_IntegerLiteralParsing_LongSuffix`
- **Primary File**: `tests/integer_literal_parsing.cpp`
- **Verification Points**: 7 assertions
- **Test Input (Zig)**:
  ```zig
const x: i64 = 456L;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_IntegerLiteralParsing_UnsignedLongSuffix`
- **Primary File**: `tests/integer_literal_parsing.cpp`
- **Verification Points**: 7 assertions
- **Test Input (Zig)**:
  ```zig
const x: u64 = 789UL;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_single_char_tokens`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 37 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_single_char_tokens specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 37 semantic properties match expected values
  ```

### `test_multi_char_tokens`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 13 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_multi_char_tokens specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 13 semantic properties match expected values
  ```

### `test_assignment_vs_equality`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 19 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_assignment_vs_equality specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 19 semantic properties match expected values
  ```

### `test_lex_arithmetic_and_bitwise_operators`
- **Primary File**: `tests/test_lexer_operators.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lex_arithmetic_and_bitwise_operators specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_Lexer_RangeExpression`
- **Primary File**: `tests/test_lexer_operators.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_RangeExpression specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_lex_compound_assignment_operators`
- **Primary File**: `tests/test_lexer_compound_operators.cpp`
- **Verification Points**: 11 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lex_compound_assignment_operators specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 11 semantic properties match expected values
  ```

### `test_LexerSpecialOperators`
- **Primary File**: `tests/test_lexer_special_ops.cpp`
- **Verification Points**: 10 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_LexerSpecialOperators specific test data structures
  4. Verify that the 10 semantic properties match expected values
  ```

### `test_LexerSpecialOperatorsMixed`
- **Primary File**: `tests/test_lexer_special_ops.cpp`
- **Verification Points**: 8 assertions
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_LexerSpecialOperatorsMixed specific test data structures
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_Lexer_Delimiters`
- **Primary File**: `tests/test_lexer_delimiters.cpp`
- **Verification Points**: 7 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_Delimiters specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_Lexer_DotOperators`
- **Primary File**: `tests/test_lexer_delimiters.cpp`
- **Verification Points**: 11 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_DotOperators specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 11 semantic properties match expected values
  ```

### `test_skip_comments`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 7 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_skip_comments specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 7 semantic properties match expected values
  ```

### `test_nested_block_comments`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_nested_block_comments specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_unterminated_block_comment`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_unterminated_block_comment specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_lex_visibility_and_linkage_keywords`
- **Primary File**: `tests/test_lexer_keywords.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lex_visibility_and_linkage_keywords specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_lex_compile_time_and_special_function_keywords`
- **Primary File**: `tests/test_compile_time_keywords.cpp`
- **Verification Points**: 8 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lex_compile_time_and_special_function_keywords specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 8 semantic properties match expected values
  ```

### `test_lex_miscellaneous_keywords`
- **Primary File**: `tests/test_lexer_keywords.cpp`
- **Verification Points**: 14 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lex_miscellaneous_keywords specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 14 semantic properties match expected values
  ```

### `test_lex_missing_keywords`
- **Primary File**: `tests/test_missing_keywords.cpp`
- **Verification Points**: 4 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
defer fn var
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 4 semantic properties match expected values
  ```

### `test_lexer_handles_tab_correctly`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_handles_tab_correctly specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_lexer_handles_long_identifier`
- **Primary File**: `tests/lexer_edge_cases.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_lexer_handles_long_identifier specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_HandlesLongIdentifier`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_HandlesLongIdentifier specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_NumericLookaheadSafety`
- **Primary File**: `tests/lexer_fixes.cpp`
- **Verification Points**: 1 assertions
- **Operations**: Syntactic Parsing
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_NumericLookaheadSafety specific test data structures
  3. Execute Syntactic Parsing phase
  4. Verify that the 1 semantic properties match expected values
  ```

### `test_token_fields_are_initialized`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_token_fields_are_initialized specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_ComprehensiveCrossGroup`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 2 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const pi = 3.14;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 2 semantic properties match expected values
  ```

### `test_Lexer_IdentifiersAndStrings`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 9 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
my_var \
  ```
  ```zig
_another_var \
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 9 semantic properties match expected values
  ```

### `test_Lexer_ErrorConditions`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 5 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_Lexer_ErrorConditions specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 5 semantic properties match expected values
  ```

### `test_IntegerRangeAmbiguity`
- **Primary File**: `tests/test_lexer.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Initialize test_IntegerRangeAmbiguity specific test data structures
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```

### `test_Lexer_MultiLineIntegrationTest`
- **Primary File**: `tests/test_lexer_integration.cpp`
- **Verification Points**: 6 assertions
- **Operations**: Source Loading
- **Test Input (Zig)**:
  ```zig
const pi = 3.14_159;
  ```
  ```zig
const limit = 100.;
  ```
  ```zig
const val = 1.2e+g;
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Lexical Analysis environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  3. Execute Source Loading phase
  4. Verify that the 6 semantic properties match expected values
  ```
