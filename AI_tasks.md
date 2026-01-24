# AI Agent Tasks for RetroZig Compiler

This document outlines a granular, step-by-step roadmap for an AI agent to implement the RetroZig compiler. The tasks are organized by phase and component, starting with the C++ bootstrap compiler.

## Phase 0: The Bootstrap Compiler (C++98)

### Milestone 1: Core Infrastructure (COMPLETE)
1.  **Task 1:** Set up the basic directory structure. (DONE)
2.  **Task 2:** Create the `common.hpp` compatibility header. (DONE)
3.  **Task 3:** Implement the `ArenaAllocator` class. (DONE)
4.  **Task 4:** Add alignment support to `ArenaAllocator`. (DONE)
5.  **Task 5:** Implement the `StringInterner` class. (DONE)
6.  **Task 6:** Implement the `SourceManager` class. (DONE)
7.  **Task 7:** Define the `ErrorReport` struct and `ErrorCode` enum. (DONE)
8.  **Task 8:** Implement a basic diagnostic printing function. (DONE)
9.  **Task 9:** Create a minimal unit testing framework. (DONE)
10. **Task 10:** Create initial `build.bat` and `test.bat` scripts. (DONE)

### Milestone 2: Lexer Implementation (COMPLETE)
11. **Task 11:** Define initial `TokenType` enum in `lexer.hpp`. (DONE)
12. **Task 12:** Implement the `Token` struct with a union for literal values. (DONE)
13. **Task 13:** Implement the `Lexer` class skeleton. (DONE)
14. **Task 14:** Implement lexing for single-character tokens. (DONE)
15. **Task 15:** Implement lexing for multi-character tokens. (DONE)
16. **Task 16:** Implement basic identifier and keyword recognition. (DONE)
17. **Task 17:** Update `TokenType` enum in `src/include/lexer.hpp` to include all missing tokens as defined in `Lexer.md`. (DONE)
18. **Task 18:** Implement lexing for `TOKEN_CHAR_LITERAL` (e.g., `'a'`). (DONE)
19. **Task 19:** Implement lexing for `TOKEN_FLOAT_LITERAL` (e.g., `3.14`). (DONE)
20. **Task 20:** Implement lexing for remaining arithmetic and bitwise operators (`%`, `~`, `&`, `|`, `^`, `<<`, `>>`). (DONE)
21. **Task 21:** Implement lexing for compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`). (DONE)
22. **Task 22:** Implement lexing for special and wrapping operators (`.`, `.*`, `.?`, `?`, `++`, `**`, `+%`, `-%`, `*%`). (DONE - Note: `||` was removed as it is not the correct Zig operator).
23. **Task 23:** Implement lexing for remaining delimiters (`:`, `->`, `=>`, `...`). (DONE)
24. **Task 24:** Implement keyword recognition for control flow (`break`, `catch`, `continue`, `else`, `for`, `if`, `orelse`, `resume`, `suspend`, `switch`, `try`, `while`). (DONE)
25. **Task 25:** Implement keyword recognition for type declarations (`enum`, `error`, `struct`, `union`, `opaque`). (DONE)
26. **Task 26:** Implement keyword recognition for visibility and linkage (`export`, `extern`, `pub`, `linksection`, `usingnamespace`). (DONE)
27. **Task 27:** Implement keyword recognition for compile-time and special functions (`asm`, `comptime`, `errdefer`, `inline`, `noinline`, `test`, `unreachable`). (DONE)
28. **Task 28:** Implement keyword recognition for memory and calling conventions (`addrspace`, `align`, `allowzero`, `and`, `anyframe`, `anytype`, `callconv`, `noalias`, `nosuspend`, `or`, `packed`, `threadlocal`, `volatile`). (DONE)
29. **Task 29:** Implement logic to skip single-line and block comments. (This was previously part of other tasks, now consolidated). (DONE)
30. **Task 30:** Write comprehensive unit tests for the lexer, covering all new token types and edge cases.
31. **Task 31:** Implement lexing for `TOKEN_STRING_LITERAL` and properly handle `TOKEN_IDENTIFIER` values. This includes storing the string content (for string literals) and the identifier name, likely using the string interner. (DONE)
32. **Task 32:** Extend the lexer to handle escaped characters in string literals (e.g., `\n`, `\t`, `\\`, `\"`). (DONE)
33. **Task 33:** Implement lexing for crucial missing keywords (`fn`, `var`, `defer`). (DONE)
34. **Task 34:** Implement lexing for missing operators (`--`). (Note: `&&` was removed as it is not the correct Zig operator; the correct operator is the `and` keyword, which is already implemented).

### Milestone 3: Parser & AST (COMPLETE)
35. **Task 35:** Define foundational AST structures and nodes for Expressions (Literals, Unary, Binary). (DONE)
36. **Task 36:** Define AST nodes for Statements (`IfStmt`, `WhileStmt`, `ReturnStmt`, `DeferStmt`, `BlockStmt`). (DONE)
37. **Task 37:** Define AST nodes for Declarations (`FnDecl`, `VarDecl`, `ParamDecl`). (DONE)
38. **Task 38:** Define AST nodes for Type Expressions (`TypeName`, `PointerType`, `ArrayType`). (DONE)
39. **Task 39:** Define AST nodes for Container Declarations (`struct`, `enum`, `union`). (DONE)
40. **Task 40:** Define AST nodes for Control Flow (`for`, `switch`). (DONE)
41. **Task 41:** Define AST nodes for Error Handling (`try`, `catch`, `errdefer`). (DONE)
42. **Task 42:** Define AST nodes for Async Operations (`async`, `await`). (DONE)
43. **Task 43:** Define AST nodes for Comptime Operations (`comptime`). (DONE)
44. **Task 44:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`). (DONE)
45. **Task 45:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`). (DONE)
46. **Task 46:** Implement parsing for top-level variable declarations (`var` and `const`). (DONE)
47. **Task 47:** Refactor Parser Error Handling and Cleanup. (DONE)
48. **Task 48:** Implement `parseFnDecl` for function definitions. (DONE)
49. **Task 49:** Implement `parseBlockStatement`. (DONE)
50. **Task 50:** Implement `parseIfStatement`. (DONE)
51. **Task 51:** Implement `parseWhileStatement`. (DONE)
52. **Task 52:** Refactor `AST_parser.md` for clarity and correctness. (DONE)
53. **Task 53:** Add Doxygen comments to `parser.cpp` functions. (DONE)
54. **Task 54:** Resolve Technical Constraint Violations in Parser. (DONE)
55. **Task 55:** Implement `parseDeferStatement`. (DONE)
56. **Task 56:** Implement `parseReturnStatement`. (DONE)
57. **Task 57:** Implement `parsePrimaryExpr` for primary expressions. (DONE)
58. **Task 58:** Implement parsing for postfix expressions. (DONE)
59. **Task 59:** Implement `parseUnaryExpr` for unary operators. (DONE)
60. **Task 60:** Implement `parseBinaryExpr` for Core Binary Operators. (DONE)
61. **Task 61:** Extend `parseBinaryExpr` for Bitwise Operators. (DONE)
62. **Task 62:** Extend `parseBinaryExpr` for Logical Operators (`and`, `or`). (DONE)
63. **Task 63:** Implement `parseForStatement`.
    - Implement the parsing logic for `for` loops.
    - Update `parseStatement` to dispatch to the new function.
64. **Task 64:** Implement `parseSwitchExpression`.
    - Implement the parsing logic for `switch` expressions.
    - Update the expression parsing hierarchy to include it.
65. **Task 65:** Implement `parseStructDeclaration`.
    - Implement the parsing logic for `struct` declarations.
    - This should be handled as a type expression.
66. **Task 66:** Implement `parseUnionDeclaration`.
    - Implement the parsing logic for `union` declarations.
    - This should be handled as a type expression.
67. **Task 67:** Implement `parseEnumDeclaration`.
    - Implement the parsing logic for `enum` declarations.
    - This should be handled as a type expression.
68. **Task 68:** Implement `parseTryExpression`. (DONE)
    - Implement the parsing logic for `try` expressions.
    - Update the expression parsing hierarchy.
69. **Task 69:** Implement `parseCatchExpression`.
    - Implement the parsing logic for `catch` expressions.
    - Update the expression parsing hierarchy.
70. **Task 70:** Implement `parseErrDeferStatement`.
    - Implement the parsing logic for `errdefer` statements.
    - Update `parseStatement` to dispatch to the new function.
71. **Task 71:** Implement `parseAsyncExpression`. (DONE - NOT SUPPORTED BY DESIGN)
72. **Task 72:** Implement `parseAwaitExpression`. (DONE - NOT SUPPORTED BY DESIGN)
    - Implement the parsing logic for `await` expressions.
    - Update the expression parsing hierarchy.
73. **Task 73:** Implement `parseComptimeBlock`. (DONE)
    - Implement the parsing logic for `comptime` blocks.
    - Update `parseStatement` to dispatch to the new function.
74. **Task 74:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement with complex expressions).
    - Verify that the resulting AST is structured correctly.
75. **Task 75:** Implement Range Operator (..) Lexing. (DONE)
    - Add TOKEN_RANGE to the TokenType enum in src/include/lexer.hpp
    - Update the lexer's dot handling logic in src/bootstrap/lexer.cpp to recognize .. as TOKEN_RANGE before attempting to parse ... (ELLIPSIS)
    - Add unit tests for the range operator lexing
    - Recommendation: This is critical as it's blocking the for loop test case and will likely be needed for slice operations throughout the language.
76. **Task 76:** Implement Non-Empty Function Body Support
    - Modify parseFnDecl in src/bootstrap/parser.cpp to remove the restriction on empty function bodies
    - Instead of expecting TOKEN_RBRACE immediately, call parseBlockStatement to handle the function body contents
    - Ensure parseBlockStatement correctly parses multiple statements until the closing brace
    - Recommendation: This is essential for completing the integration test. The function declaration parser needs to delegate to the general statement parser for the body.
77. **Task 77:** Enhance Expression Parsing State Management
    - Review and fix the Pratt parser (parsePrecedenceExpr) in src/bootstrap/parser.cpp to ensure correct token consumption, especially after parsing parenthesized expressions
    - Add debug logging or assertions to verify parser position advancement during complex nested expressions like `a and (b or c)`
    - Consider adding a maximum recursion depth check to prevent stack overflows during expression parsing
    - Recommendation: This addresses the potential infinite loop/memory corruption issue in complex boolean expressions. Proper state management is crucial for parser stability.
78. **Task 78:** Implement Array Slice Expression Parsing
    - Extend parsePostfixExpression to handle range expressions within array access brackets [start..end]
    - This will enable parsing of expressions like my_slice[0..4] used in the for loop test
    - Recommendation: This builds on Task 75 (range operator) and is necessary for the for loop functionality.
79. **Task 79:** Complete For Loop Statement Parsing with Slice Iteration
    - Update parseForStatement to handle slice/iterator expressions like my_slice[0..4] in addition to simple identifiers
    - Ensure the parser can handle the pipe syntax |item| for loop variables
    - Recommendation: This combines the range operator and slice parsing to fully support the failing for loop test case.
80.   **Task 80:** Fixing minor concerns
       -In memory.hpp, the ArenaAllocator constructor allocates but there's no destructor: ArenaAllocator(size_t capacity) : buffer(NULL), offset(0), capacity(capacity) {
    // Missing buffer allocation
}

        -  Uninitialized Variables in Lexer In lexer.cpp, several methods don't initialize all fields of Token: Token Lexer::lexCharLiteral() {
    Token token;
    token.type = TOKEN_CHAR_LITERAL;
    // Missing initialization of token.literal, token.value, etc.
}
        - Potential Buffer Overflows In StringInterner::hash and other string functions, no bounds checking:
          unsigned int StringInterner::hash(const char* str) {
    // Should check for null pointer
}
      -In src/include/memory.hpp, verify your ensure_capacity logic: Potential Bug: If capacity is initially 0, the line size_t new_cap = capacity * 2; results in 0.    Consequence: If you rely solely on doubling, the array will never grow from 0, potentially causing a crash or infinite allocation attempts when append is called.    The Fix: Ensure a minimum fallback:  size_t new_cap = (capacity == 0) ? 8 : capacity * 2; 

    -Lexer::match Buffer Over-read In src/bootstrap/lexer.cpp: The Issue: bool Lexer::match(char expected) typically checks source[current] == expected. If current is already at EOF (end of source), accessing source[current] is an out-of-bounds read.   The Fix: Ensure the bounds check happens before the memory access.
    bool Lexer::match(char expected) {
    if (isAtEnd()) return false; // Critical check
    if (source[current] != expected) return false;
    current++;
    return true;
}
        -Integer vs. Range Operator Ambiguity (Task 75) You implemented TOKEN_RANGE (..), but this creates a conflict with TOKEN_FLOAT_LITERAL. The Scenario: Consider the valid Zig for-loop syntax: 0..10. The Bug: The lexer encounters 0, sees a ., and may aggressively consume it as a float (0.). This leaves the second . as a simplified dot operator, resulting in FLOAT(0.) followed by DOT(.) and INT(10), instead of INT(0) and RANGE(..).   Verification: Check lexNumericLiteral. It must peek two characters ahead when it encounters a dot.  If it sees . followed by another ., it must abort float parsing immediately and return the integer 0.
       -// In Parser class Recommendation: Add a depth counter to parseExpression or parsePrecedenceExpr.
    int recursion_depth;
    const int MAX_DEPTH = 500
    ASTNode* parseExpression() {
        if (++recursion_depth > MAX_DEPTH) error("Expression too complex");
        // ... parse ...
        recursion_depth--;
        return result;
    }
    Solve also that there is No validation that tokens are being consumed
     - Function Body Parsing Incomplete Task 76 says to implement non-empty function body support, but parseFnDecl likely still expects empty bodies.
    - Type Safety Issues In ast.hpp, the ASTNode uses a raw void* union without type checking: truct ASTNode {
    NodeType type;
    union {
        ASTBinaryOpNode* binary_op;
        // ... other types
    };
    // No way to ensure the union field matches NodeType
};
    
     -String Interning Lifetime In src/bootstrap/string_interner.cpp: Verification: Does StringInterner::intern(const char* str) copy the string into the Arena? The Risk: If it just stores the str pointer passed from the Lexer, and the Lexer is using a temporary buffer or pointing into a file buffer that might move/close, the AST nodes will hold dangling pointers.    Correct behavior: intern must allocate strlen(str) + 1 bytes in the ArenaAllocator, strcpy the data there, and store that pointer.
      - Review of "Task 76: Non-Empty Function Body" You implemented support for non-empty function bodies by calling parseBlockStatement. Potential Edge Case: Zig allows functions to return immediately with an expression in some contexts (though usually block-bound).  Check: Ensure parseBlockStatement correctly consumes the closing brace }.  If parseBlockStatement expects { to start, but parseFnDecl has already consumed the { (to check for empty body), the parser will error expecting {.  Fix: parseFnDecl should consume arguments, checks for return_type, and then delegate immediately to parseBlockStatement without peeking inside, allowing parseBlockStatement to handle the opening {.

81. **Task 81:** Final Integration Test Suite Validation
    - Run all previous integration tests again to ensure no regressions were introduced
    - Add edge cases discovered during the fixing process as separate, focused regression tests
    - Document any remaining known limitations in a TODO.md or similar file
    - Recommendation: Always validate that fixes don't break existing functionality.


    
### Milestone 4: Bootstrap Type System & Semantic Analysis (IN PROGRESS)
81. **Task 81:** Define core Type struct and TypeKind for C89-compatible types
    - Risk Level: LOW
    - Focus only on types that map directly to C89: i8, i16, i32, i64, u8, u16, u32, u64, isize, usize, f32, f64, bool, void, *T
    - No advanced Zig types like slices, error unions, or optionals for now
    - Constraint Check: All these types can map to C89 equivalent types
82. **Task 82:** Implement minimal Symbol struct and SymbolTable (DONE)
    - Risk Level: LOW
    - Basic symbol storage for functions, global variables, and local variables
    - Simple name-to-type mapping using C++98 compatible data structures
    - Constraint Check: Standard symbol table implementation works fine
83. **Task 83:** Implement basic scope management 
    - Risk Level: LOW
    - Only global and function scopes are needed initially
    - Constraint Check: Scope management is language-independent
84. **Task 84:** Implement symbol insertion and lookup 
    - Risk Level: LOW
    - Basic name resolution for variables/functions with simple duplicate detection
    - Constraint Check: Standard hash table/string interning techniques work
85. **Task 85:** Implement TypeChecker skeleton for bootstrap types
    - Risk Level: MEDIUM
    - Focus only on basic C89-compatible operations with minimal error reporting
    - Constraint Risk: Need to carefully validate against C89 subset - may miss some restrictions
86. **Task 86:** Implement basic type compatibility
    - Risk Level: LOW
    - Integer and pointer type compatibility; basic function signature matching
    - Constraint Check: C89 type compatibility rules are well-defined
87. **Task 87:** Type-check variable declarations (basic)
    - Risk Level: LOW
    - Simple type annotation checking and basic initializer compatibility
    - Constraint Check: C89 variable declarations are straightforward
88. **Task 88:** Type-check function signatures
    - Risk Level: MEDIUM
    - Parameter and return type verification
    - Constraint Risk: Must reject function pointers, complex return types that don't map to C89
89. **Task 89:** Implement basic expression type checking
    - Risk Level: MEDIUM
    - Handle literals, variable access, basic arithmetic, and simple comparisons
    - Constraint Risk: Need to ensure all operations map to C89-compatible operations

**DETAILED MICRO-TASK BREAKDOWN WITH RISK MITIGATION**
Operation Compatibility Validator (MEDIUM RISK)  

    Validate expressions against C89 operations matrix:  
    Operation
    	
    Allowed Types
    +, -
    	
    Numeric only
    *, /
    	
    Exclude bool
    &, *
    	
    Pointers only
    []
    	
    REJECT (defer to Milestone 5)
    Mitigation: Explicit allow-list prevents unsafe ops. Rejects array indexing entirely for now.  
    Output: Operation validation table in TypeChecker

**RESOURCE ALLOCATION RECOMMENDATION:**

Given memory constraints, allocate:

    Static arrays for type mapping tables (93A)

    Arena allocation for validation state (93O)

    String interning for error messages (97 series)

    Pre-allocated buffers for integration test output (100 series)
    
90. **Task 90:** Reject Complex Calls (LOW RISK)
        Immediately reject:  
            Calls with >4 arguments (C89 stack limits)  
            Any function pointer calls  
            Variadic calls (printf-style)
        Output: Early AST validation pass
91. **Task 91:** Basic Call Validation (LOW RISK)
        For allowed calls:  
            Verify argument count matches declaration  
            Check type compatibility using is_c89_compatible() (Task 93a)
        Mitigation: Leverages existing type validation. No overloading resolution needed.  
        Output: Call validation in TypeChecker
92. **Task 92:** Implement basic control flow checking
    - Risk Level: LOW
    - Ensure control flow conditions are C-style compatible (boolean, integer, or pointer)
    - Constraint Check: C89 control flow is supported
93. **Task 93:** Implement basic pointer operation checking (Partially Implemented)
    - Risk Level: MEDIUM
    - Check address-of (&) and dereference (*) operators (DONE)
    - Check for pointer arithmetic (TODO)
    - Constraint Risk: Must ensure no unsafe pointer arithmetic beyond C89 capabilities
94. **Task 94:** PRIMITIVE TYPE MAPPING TABLE SETUP (LOW)

    What to implement: Static arrays/maps for type equivalency
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Memory allocation (use static arrays only)
        Missing Zig primitive types in mapping
        Incorrect C89 equivalents (e.g., bool vs int)
    Validation: Print all mappings to console for verification
    Success criteria: All basic types (void, bool, i8-u64, f32-f64) have C89 equivalents

    Create is_c89_compatible(Type*) function that ONLY accepts:
    i8..i64, u8..u64, f32/f64, bool, void, *T (where T is whitelisted)  
    Mitigation: Hardcoded whitelist avoids complex validation logic. Rejects isize/usize since no C89 equivalent.  
    Output: Header file with type validation functions

95. **Task 95:** INTEGER TYPE COMPATIBILITY VALIDATION (LOW)

    What to implement: Check integer sizes match C89 requirements
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Platform-specific integer sizes (test on 32-bit vs 64-bit)
        Signed vs unsigned mismatches
        Range overflow in conversions
    Validation: Compare sizeof() results between Zig and C89 types
    Success criteria: All integer operations stay within C89 range limits
    Create is_c89_compatible(Type*) function that ONLY accepts:
    i8..i64, u8..u64, f32/f64, bool, void, *T (where T is whitelisted)  
    Mitigation: Hardcoded whitelist avoids complex validation logic. Rejects isize/usize since no C89 equivalent.  
    Output: Header file with type validation functions

96. **Task 96:** FLOAT TYPE COMPATIBILITY VALIDATION (LOW)

    What to implement: Validate float precision and representation
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        IEEE 754 compliance differences
        Precision loss in float-to-double conversions
        NaN/infinity handling differences
    Validation: Compare floating-point behavior edge cases
    Success criteria: All float operations maintain C89 precision standards
    Create is_c89_compatible(Type*) function that ONLY accepts:
    i8..i64, u8..u64, f32/f64, bool, void, *T (where T is whitelisted)  
    Mitigation: Hardcoded whitelist avoids complex validation logic. Rejects isize/usize since no C89 equivalent.  
    Output: Header file with type validation functions

97. **Task 97:** BOOLEAN TYPE COMPATIBILITY VALIDATION (LOW)

    What to implement: Map Zig bool to C89 int (0/1 convention)
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Non-zero values being treated as true in C89
        Size differences between Zig bool and C int
        Boolean operation result types
    Validation: Test boolean logic consistency across translation
    Success criteria: Boolean expressions behave identically in both languages
    Create is_c89_compatible(Type*) function that ONLY accepts:
    i8..i64, u8..u64, f32/f64, bool, void, *T (where T is whitelisted)  
    Mitigation: Hardcoded whitelist avoids complex validation logic. Rejects isize/usize since no C89 equivalent.  
    Output: Header file with type validation functions

98. **Task 98:** VOID TYPE COMPATIBILITY VALIDATION (LOW)

    What to implement: Verify void type usage restrictions
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Attempting to declare void variables
        Void function return handling
        Void pointer compatibility
    Validation: Ensure no void-related compilation errors in C89
    Success criteria: All void uses translate to legal C89 constructs
    Create is_c89_compatible(Type*) function that ONLY accepts:
    i8..i64, u8..u64, f32/f64, bool, void, *T (where T is whitelisted)  
    Mitigation: Hardcoded whitelist avoids complex validation logic. Rejects isize/usize since no C89 equivalent.  
    Output: Header file with type validation functions

99. **Task 99:** POINTER TYPE COMPATIBILITY VALIDATION (MEDIUM)

    What to implement: Validate pointer operations and types
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Void pointer vs typed pointer handling
        Pointer arithmetic beyond C89 capabilities
        Const/volatile qualifier mismatches
    Validation: Test pointer operations compile in C89 environment
    Success criteria: All pointer operations remain C89-compliant

100. **Task 100:** ARRAY TYPE COMPATIBILITY VALIDATION (DONE)

    What to implement: Validate array declaration and access patterns
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Runtime-sized arrays (not C89-compatible)
        Multidimensional array mapping
        Array-to-pointer decay differences
    Validation: Ensure array declarations compile in C89
    Success criteria: All array operations map to legal C89 syntax

101. **Task 101:** FUNCTION TYPE COMPATIBILITY VALIDATION (HIGH)

    What to implement: Validate function signatures and calling
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Function pointers (may require special handling)
        Parameter passing conventions
        Return type limitations in C89
    Validation: Test function declarations compile in C89
    Success criteria: All function types translate to C89-compatible declarations

102. **Task 102:** STRUCT FIELD TYPE COMPATIBILITY VALIDATION (MEDIUM)

    What to implement: Validate struct member types
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Nested struct compatibility
        Function members (not allowed in C89 structs)
        Alignment differences between languages
    Validation: Ensure struct definitions compile in C89
    Success criteria: All struct fields map to C89-compatible types

103. **Task 103:** ENUM VALUE TYPE COMPATIBILITY VALIDATION (LOW)

    What to implement: Validate enum value types and ranges
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Enum value size differences
        Negative enum values
        Enum comparison compatibility
    Validation: Test enum usage in C89 context
    Success criteria: All enum operations remain C89-compliant

104. **Task 104:** LITERAL EXPRESSION COMPATIBILITY VALIDATION (LOW)

    What to implement: Validate literal expressions map to C89
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        String literal null-termination
        Character literal differences
        Number literal precision
    Validation: Ensure all literals compile correctly in C89
    Success criteria: All literal expressions translate to valid C89 syntax

105. **Task 105:** BINARY OPERATOR COMPATIBILITY VALIDATION (MEDIUM) - (Note: This task was unblocked by a refactor to replace incorrect `&&`/`||` operators with the correct `and`/`or` keywords).

    What to implement: Validate binary operators map to C89
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Operator precedence differences
        Short-circuit evaluation requirements
        Bitwise vs logical operator differences
    Validation: Test all binary operations compile in C89
    Success criteria: All binary operators behave identically in both languages

106. **Task 106:** UNARY OPERATOR COMPATIBILITY VALIDATION (MEDIUM)

    What to implement: Validate unary operators map to C89
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Pre/post increment/decrement differences
        Logical vs bitwise NOT
        Address-of and dereference restrictions
    Validation: Ensure unary operations compile in C89
    Success criteria: All unary operators translate to valid C89 operations

107. **Task 107:** ASSIGNMENT COMPATIBILITY VALIDATION (MEDIUM)

    What to implement: Validate assignment operations
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Assignment return values (different in C vs C++)
        Type coercion differences
        Compound assignment operators
    Validation: Test assignment operations in C89 context
    Success criteria: All assignments remain C89-compliant

108. **Task 108:** C89 FEATURE REJECTION FRAMEWORK (DONE)

    What to implement: System to detect and reject non-C89 features
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Missing rejection rules
        Performance impact of validation
        False positives in rejection
    Validation: Test that rejected features actually fail compilation
    Success criteria: Any non-C89 feature triggers compilation error


	AST Pre-Scan for Forbidden Nodes (MEDIUM RISK)  
    Before type checking, traverse AST to reject:  
        Function pointers (FnPtrType)  
        Variadic parameters (...)  
        Error unions (!T), optionals (?T), slices ([]T)  
        Struct methods (only allow C-style struct + external functions)
    Mitigation: Early rejection avoids complex error recovery later.  
    Output: AST visitor that fails compilation immediately on forbidden constructs
	
    Type Emission Verifier (LOW RISK)  

    After type checking, verify every used type has a C89 emission mapping:  
	// In codegen phase  
	assert(map_to_c89_type(zig_type) != nullptr);  
Mitigation: Decouples validation from type checking. Final safety net before codegen.  
Output: Runtime assertions in codegen module
109. **Task 109:** ADDRESS-OF OPERATOR VALIDATION (LOW)

    What to implement: Validate & operator usage
    Watch for: 
        Taking address of rvalues
        Address of temporary objects
        Address of register variables (if any)
    Validation: Ensure address-of generates valid C89 syntax
    Success criteria: All & operations translate to legal C89 address-taking

110. **Task 110:** DEREFERENCE OPERATOR VALIDATION (LOW)

    What to implement: Validate * operator usage
    Watch for: 
        Dereferencing non-pointer types
        Double dereferencing issues
        Null pointer dereference detection
    Validation: Test dereference operations compile in C89
    Success criteria: All * operations remain safe and valid in C89

111. **Task 111:** POINTER ARITHMETIC VALIDATION (MEDIUM)

    What to implement: Validate pointer arithmetic operations
    Watch for: 
        Pointer arithmetic beyond array bounds
        Mixed pointer arithmetic (different types)
        Pointer subtraction limitations in C89
    Validation: Ensure arithmetic operations stay within C89 safety limits
    Success criteria: All pointer arithmetic remains within C89-compliant bounds

112. **Task 112:** ARRAY ACCESS BOUNDS CHECKING (MEDIUM)

    What to implement: Compile-time array bounds analysis
    Watch for: 
        Dynamic index bounds checking (runtime impossible in C89)
        Multi-dimensional array access
        Array slice operations (not C89-compatible)
    Validation: Flag all potentially out-of-bounds accesses
    Success criteria: All static array accesses are proven safe at compile time

113. **Task 113:** SLICE OPERATION DETECTION (HIGH)

    What to implement: Detect when slice operations are used
    Watch for: 
        Array slicing syntax [start..end]
        Slice parameter passing
        Slice return values
    Validation: Log all slice operations as incompatible with C89
    Success criteria: All slice operations are identified and flagged as non-C89

114. **Task 114:** Detect array slicing syntax [start..end]
115. **Task 115:** Detect slice parameter types
116. **Task 116:** Detect slice return types
117. **Task 117:** Detect slice literal creation
118. **Task 118:** Report slice operations as compilation errors

119. **Task 119:** MEMORY ALLOCATION DETECTION (HIGH)

    What to implement: Identify memory allocation operations
    Watch for: 
        new, create, destroy operations
        Heap allocation functions
        Memory management calls
    Validation: Flag all allocation operations as C89-incompatible
    Success criteria: All dynamic memory operations are detected and rejected
120. **Task 120:** Scan for allocation keywords (new, create, etc.)
121. **Task 121:** Detect heap allocation function calls
122. **Task 122:** Identify memory management utilities
123. **Task 123:** Flag all allocation operations
124. **Task 124:** Provide C89-safe allocation alternatives

125. **Task 125:** LIFETIME ANALYSIS FRAMEWORK (COMPLETE)

    What to implement: Track object lifetimes and validity
    Watch for: 
        Use-after-free scenarios
        Dangling pointer references
        Stack variable lifetime issues
    Validation: Create lifetime tracking system that doesn't require runtime support
    Success criteria: All lifetime violations are caught at compile time

126. **Task 126:** NULL POINTER DETECTION (COMPLETE)

    What to implement: Identify potential null pointer dereferences
    Watch for: 
        Uninitialized pointer usage
        Function returning null pointers
        Conditional null checks
    Validation: Flag all potential null dereference points
    Success criteria: All null pointer risks are identified in advance. Phase 3 (Conditionals & Flow) is implemented.

127. **Task 127:** DOUBLE FREE DETECTION (HIGH)

    What to implement: Detect potential double-free scenarios
    Watch for: 
        Multiple deallocation calls
        Shared ownership situations
        Conditional deallocation paths
    Validation: Track allocation/deallocation pairs
    Success criteria: All potential double-free scenarios are identified
128. **Task 128:** Track allocation sites (DONE)
129. **Task 129:** Track deallocation sites (DONE 2024-05-24)
130. **Task 130:** Analyze control flow paths
131. **Task 131:** Identify potential multiple deallocations
132. **Task 132:** Flag all double-free risks

133. **Task 133:** Implement struct type checking (simple)
    - Risk Level: MEDIUM
    - Basic struct field access and initialization
    - Constraint Risk: Must ensure no Zig-specific struct features (like methods, etc.)
134. **Task 134:** Implement basic enum type checking
    - Risk Level: LOW
    - Simple enum value access and compatibility
    - Constraint Check: C89 enums are supported
135. **Task 135:** ERROR UNION TYPE DETECTION (LOW)

    What to implement: Identify when error union types are used
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Nested error union types
        Error union in function parameters
        Complex error union expressions
    Validation: Log all detected error union locations
    Success criteria: All error union usages are identified and flagged

136. **Task 136:** ERROR SET DEFINITION DETECTION (LOW)

    What to implement: Find all error set declarations
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Anonymous error sets
        Nested error set references
        Imported error sets
    Validation: List all error sets found in source
    Success criteria: All error set definitions are catalogued
137. **Task 137:** Detect explicit template instantiation
138. **Task 138:** Detect implicit template instantiation
139. **Task 139:** Track template specialization
140. **Task 140:** Catalog instantiation parameters
141. **Task 141:** Validate instantiation safety

142. **Task 142:** ERROR FUNCTION SIGNATURE DETECTION (LOW)

    What to implement: Identify functions that return errors
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Functions returning error unions
        Functions returning error sets
        Generic functions with error returns
    Validation: Flag all functions with error return types
    Success criteria: All error-returning functions are identified

143. **Task 143:** TRY EXPRESSION DETECTION (LOW)

    What to implement: Find all try expressions in code
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Nested try expressions
        Try in different contexts (assignments, parameters, etc.)
        Multiple try expressions in single statement
    Validation: Log location and context of all try expressions
    Success criteria: All try expressions are located and catalogued

144. **Task 144:** CATCH EXPRESSION DETECTION (LOW)

    What to implement: Find all catch expressions
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Catch with multiple handlers
        Nested catch expressions
        Catch in complex expressions
    Validation: Document all catch expression locations
    Success criteria: All catch expressions are identified

145. **Task 145:** ERROR CODE MAPPING STRATEGY (MEDIUM)

    What to implement: Design how to map errors to C89 integers
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Error code collision risks
        Negative vs positive error code conventions
        Error code range limitations
    Validation: Create mapping table example
    Success criteria: Clear strategy for converting all errors to integers

146. **Task 146:** SUCCESS VALUE EXTRACTION MAPPING (MEDIUM)

    What to implement: Strategy to extract success values from error unions
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Success value type preservation
        Memory layout considerations
        Out-parameter design choices
    Validation: Design sample success value extraction patterns
    Success criteria: Clear method for separating success from error paths

147. **Task 147:** ERROR PROPAGATION ALTERNATIVE DESIGN (MEDIUM)

    What to implement: Design C89 alternative to error propagation
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Performance implications of error handling
        Stack unwinding alternatives
        Error context preservation
    Validation: Create prototype error propagation patterns
    Success criteria: Viable C89 replacement for Zig error propagation

148. **Task 148:** ERROR RETURN PATTERN GENERATION (HIGH)

    What to implement: Generate C89-compatible error return patterns
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Generated code compilation issues
        Performance degradation
        Code complexity explosion
    Validation: Test generated patterns compile in C89
    Success criteria: All error-returning functions generate valid C89 code

149. **Task 149:** ERROR HANDLING VALIDATION RULES (MEDIUM)

    What to implement: Rules to validate error handling patterns
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Inconsistent error handling approaches
        Missing error checks in translated code
        Invalid error handling combinations
    Validation: Apply rules to sample error-handling code
    Success criteria: All error handling follows consistent C89 patterns

150. **Task 150:** ERROR TYPE ELIMINATION IMPLEMENTATION (HIGH)

    What to implement: Actually remove error types from type system
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Breaking existing type relationships
        Performance impact on type checking
        Memory leaks during elimination
    Validation: Ensure type system remains consistent after elimination
    Success criteria: No error types remain in final type system

151. **Task 151:** ERROR-FREE TYPE CONVERSION (MEDIUM)

    What to implement: Convert error union types to base types
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Type safety violations after conversion
        Loss of important type information
        Inconsistent conversion across codebase
    Validation: Test that converted types still work correctly
    Success criteria: All types remain safe and functional without error components
152. **Task 152:** FUNCTION NAME COLLISION DETECTION (LOW)

    What to implement: Find functions with identical names
    Watch for: 
        Functions with same name but different signatures
        Namespace collisions
        Hidden function declarations
    Validation: Catalog all function names and their signatures
    Success criteria: All function name conflicts are identified

153. **Task 153:** PARAMETER TYPE SIGNATURE ANALYSIS (MEDIUM)

    What to implement: Analyze function parameter types for uniqueness
    Watch for: 
        Type aliases creating apparent differences
        Pointer vs array parameter confusion
        Const/volatile qualifiers affecting signatures
    Validation: Ensure signature analysis correctly distinguishes functions
    Success criteria: Each function signature is uniquely identifiable

154. **Task 154:** GENERIC FUNCTION DETECTION (MEDIUM)

    What to implement: Identify generic/polymporphic functions
    Watch for: 
        Template functions
        Generic type parameters
        Type inference in function calls
    Validation: Log all generic function definitions
    Success criteria: All generic functions are identified as needing special handling

155. **Task 155:** TEMPLATE INSTANTIATION DETECTION (HIGH)

    What to implement: Find where templates are instantiated
    Watch for: 
        Implicit template instantiation
        Explicit instantiation requests
        Recursive template instantiations
    Validation: Track all template instantiation sites
    Success criteria: All template usage is catalogued for processing
156. **Task 156:** Detect explicit template instantiation
157. **Task 157:** Detect implicit template instantiation
158. **Task 158:** Track template specialization
159. **Task 159:** Catalog instantiation parameters
160. **Task 160:** Validate instantiation safety

161. **Task 161:** NAME MANGLING ALGORITHM DESIGN (MEDIUM)

    What to implement: Design algorithm to create unique C89 function names
    Watch for: 
        Name length limitations in C89 compilers
        Reserved word conflicts
        Readability vs uniqueness tradeoffs
    Validation: Test algorithm with various function signatures
    Success criteria: Algorithm produces unique, C89-compliant names consistently

162. **Task 162:** UNIQUE NAME GENERATION (MEDIUM)

    What to implement: Generate actual unique names for functions
    Watch for: 
        Name collision in generated output
        Excessive name length
        Debugging readability issues
    Validation: Verify all generated names are truly unique
    Success criteria: Every function gets a unique C89-safe name

163. **Task 163:** CALL SITE RESOLUTION UPDATES (HIGH)

    What to implement: Update function calls to use new mangled names
    Watch for: 
        Missing call site updates
        Performance impact of name resolution
        Indirect call handling
    Validation: Ensure all function calls point to correct mangled names
    Success criteria: All function calls resolve to the correct target functions
164. **Task 164:** Build call site lookup table
165. **Task 165:** Update direct function calls
166. **Task 166:** Update indirect function calls
167. **Task 167:** Update recursive calls
168. **Task 168:** Validate all call resolutions work correctly

169. **Task 169:** Write bootstrap-specific unit tests
    - Risk Level: MEDIUM
    - Test basic type checking functionality and verify C89 compatibility of generated types
    - Constraint Risk: Tests must cover all rejected features, not just accepted ones
170. **Task 170:** LITERAL EXPRESSION INTEGRATION TEST (LOW)

    What to implement: Test literal expressions end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Literal value corruption during translation
        Type mismatch in generated C code
        Compilation errors in C89 compiler
    Validation: Run generated C through C89 compiler
    Success criteria: All literal expressions generate and compile successfully

171. **Task 171:** VARIABLE DECLARATION INTEGRATION TEST (LOW)

    What to implement: Test variable declarations end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Variable name conflicts in C89
        Type declaration errors
        Initialization problems
    Validation: Verify C89 compilation succeeds
    Success criteria: All variable declarations work in C89 environment

172. **Task 172:** BASIC ARITHMETIC INTEGRATION TEST (LOW)

    What to implement: Test arithmetic operations end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Operator precedence issues
        Type promotion differences
        Overflow/underflow behavior changes
    Validation: Compare arithmetic results between Zig and C89
    Success criteria: Arithmetic operations produce identical results

173. **Task 173:** FUNCTION DECLARATION INTEGRATION TEST (MEDIUM)

    What to implement: Test function declarations end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Function name mangling issues
        Parameter type mismatches
        Return type problems
    Validation: Ensure C89 compiler accepts function declarations
    Success criteria: All function declarations compile successfully

174. **Task 174:** SIMPLE FUNCTION CALL INTEGRATION TEST (MEDIUM)

    What to implement: Test function calls end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Calling convention mismatches
        Parameter passing errors
        Return value handling issues
    Validation: Execute generated C code and verify correctness
    Success criteria: Function calls work identically in both versions

175. **Task 175:** IF STATEMENT INTEGRATION TEST (MEDIUM)

    What to implement: Test if statements end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Condition evaluation differences
        Scoping issues in generated C
        Branch prediction differences
    Validation: Test all if statement variations compile and run
    Success criteria: Control flow behaves identically in both languages

176. **Task 176:** WHILE LOOP INTEGRATION TEST (MEDIUM)

    What to implement: Test while loops end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Loop condition evaluation
        Variable scoping in loops
        Break/continue statement handling
    Validation: Ensure loops execute correctly in C89
    Success criteria: Loops produce identical results in both implementations

177. **Task 177:** BASIC STRUCT INTEGRATION TEST (MEDIUM)

    What to implement: Test struct usage end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Struct definition compatibility
        Member access translation
        Memory layout differences
    Validation: Verify struct operations compile and work in C89
    Success criteria: Struct operations function identically in both languages

178. **Task 178:** POINTER OPERATION INTEGRATION TEST (HIGH)

    What to implement: Test pointer operations end-to-end
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        Pointer arithmetic limitations
        Memory safety issues
        Compilation warnings/errors in C89
    Validation: Run comprehensive pointer operation tests
    Success criteria: All pointer operations work safely in C89 environment

179. **Task 179:** C89 COMPILER VALIDATION FRAMEWORK (HIGH)

    What to implement: Framework to validate generated C89 code
    Watch for: "Memory overhead of validation data structures", "Avoid heap allocations in validation logic"
        External compiler dependency issues
        Performance impact of validation
        False positive/negative validation results
    Validation: Test framework with known good and bad C89 samples
    Success criteria: Framework accurately identifies valid/invalid C89 code
180. **Task 180:** Optimize for bootstrap performance
    - Risk Level: LOW
    - Minimal type checking overhead and fast symbol lookups
    - Constraint Check: Performance optimization within C++98 constraints
181. **Task 181:** Document bootstrap limitations clearly
    - Risk Level: MEDIUM
    - List unsupported Zig features and document C89 mapping decisions
    - Constraint Risk: Documentation must be accurate to prevent false expectations

### Milestone 5: Code Generation (C89)
182. **Task 182:** Implement a basic C89 emitter class in `codegen.hpp`.
183. **Task 183:** Implement `CVariableAllocator` to manage C variable names.
184. **Task 184:** Generate C89 function declarations.
185. **Task 185:** Generate C89 code for integer literals.
186. **Task 186:** Generate C89 code for local variable declarations.
187. **Task 187:** Generate C89 code for basic arithmetic operations.
188. **Task 188:** Generate C89 code for comparison and logical operations.
189. **Task 189:** Generate C89 code for if statements.
190. **Task 190:** Generate C89 code for while and for loops.
191. **Task 191:** Generate C89 code for return statements.
192. **Task 192:** Implement C89 function call generation.
193. **Task 193:** Implement C89 code generation for defer statements.
194. **Task 194:** Generate C89 code for slice types.
195. **Task 195:** Generate C89 code for error unions.
196. **Task 196:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
197. **Task 197:** Implement the CBackend class skeleton for final code emission.
198. **Task 198:** Add logic to generate proper C89 headers and include guards.
199. **Task 199:** Implement wrappers for Zig runtime features to C library calls.
200. **Task 200:** Handle Zig memory management with C89-compatible patterns.
201. **Task 201:** Integrate CBackend to write complete C89 `.c` files.
202. **Task 202:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
203. **Task 203:** Translate the C++ compiler logic into the supported Zig subset.
204. **Task 204:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
205. **Task 205:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
206. **Task 206:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
207. **Task 207:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
