# AI Agent Tasks for RetroZig Compiler

This document outlines a granular, step-by-step roadmap for an AI agent to implement the RetroZig compiler. The tasks are organized by phase and component, starting with the C++ bootstrap compiler.

## Phase 0: The Bootstrap Compiler (C++98)

### Milestone 1: Core Infrastructure
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

### Milestone 2: Lexer Implementation
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
22. **Task 22:** Implement lexing for special and wrapping operators (`.`, `.*`, `.?`, `?`, `++`, `**`, `||`, `+%`, `-%`, `*%`). (DONE)
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
34. **Task 34:** Implement lexing for missing operators (`--`, `&&`).

### Milestone 3: Parser & AST
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
62. **Task 62:** Extend `parseBinaryExpr` for Logical Operators. (DONE)
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
    - Add debug logging or assertions to verify parser position advancement during complex nested expressions like a && (b || c)
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
        - The constructor sets buffer to NULL but doesn't allocate memory. Need: ArenaAllocator(size_t capacity) : offset(0), capacity(capacity) {
    buffer = (u8*)malloc(capacity);  // Or equivalent allocation
}
        - Missing Range Operator Implementation Task 75 (range operator ..) is marked as DONE, but I don't see: TOKEN_RANGE in the TokenType enum    Lexer logic for distinguishing .. from ...
        -  Uninitialized Variables in Lexer In lexer.cpp, several methods don't initialize all fields of Token: Token Lexer::lexCharLiteral() {
    Token token;
    token.type = TOKEN_CHAR_LITERAL;
    // Missing initialization of token.literal, token.value, etc.
}
        - Potential Buffer Overflows In StringInterner::hash and other string functions, no bounds checking:
          unsigned int StringInterner::hash(const char* str) {
    // Should check for null pointer
}
        - 
        - Void Pointer Arithmetic (Undefined Behavior) In src/include/memory.hpp (and likely used in ArenaAllocator), you are likely performing arithmetic on void* pointers.  The Issue: void* ptr; ptr += size; is a GCC         extension. In standard C++98 (and MSVC 6.0 for Windows 98), this is illegal because void has no size. The Fix: You must cast to char* or u8* before performing arithmetic.  C++ // BAD offset += size;  // GOOD char*         current = (char*)buffer + offset;
    DynamicArray Growth Logic

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
81. **Task 81:** Complete For Loop Statement Parsing with Slice Iteration  Task 79 (complete for loop parsing) is pending altough test exist for it suggestions:
    Complete Solution for For Loop with Slice Iteration

Looking at the error and your current parser implementation, I see that your lexer correctly handles .. as TOKEN_RANGE, but the parser isn't set up to handle slice expressions in array access. Let me provide a complete solution that fixes this issue.
1. First, Update Your AST Definitions (ast.hpp)
// Add this new node type to your NodeType enum
enum NodeType {
    // ... existing types ...
    NODE_ARRAY_ACCESS,
    NODE_ARRAY_SLICE,  // Add this new type
    // ... other types ...
};

// Add this new struct for array slices
struct ASTArraySliceNode {
    ASTNode* array;   // The array being sliced
    ASTNode* start;   // Start index (can be NULL for [:end] syntax)
    ASTNode* end;     // End index (can be NULL for [start:] syntax)
};

// Update your ASTNode union to include the new type
union ASTNodeData {
    // ... existing members ...
    ASTArrayAccessNode* array_access;
    ASTArraySliceNode* array_slice;  // Add this member
    // ... other members ...
};

2. Add peekNext() Helper to Parser Class (parser.hpp) (check if already exists)

class Parser {
    // ... existing members ...
    const Token& peekNext() const;  // Add this declaration
    // ... other members ...
};

3. Implement peekNext() in parser.cpp (check if already exists)
const Token& Parser::peekNext() const {
    if (current_index_ + 1 >= token_count_) {
        static Token eof_token;
        eof_token.type = TOKEN_EOF;
        return eof_token;
    }
    return tokens_[current_index_ + 1];
}

4. Fix parsePostfixExpression to Handle Slices
ASTNode* Parser::parsePostfixExpression() {
    ASTNode* expr = parsePrimaryExpr();

    while (true) {
        if (match(TOKEN_LPAREN)) {
            // Function call logic (unchanged)
            ASTFunctionCallNode* call_node = (ASTFunctionCallNode*)arena_->alloc(sizeof(ASTFunctionCallNode));
            call_node->callee = expr;
            call_node->args = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            new (call_node->args) DynamicArray<ASTNode*>(*arena_);
            if (!match(TOKEN_RPAREN)) {
                do {
                    call_node->args->append(parseExpression());
                } while (match(TOKEN_COMMA) && peek().type != TOKEN_RPAREN);
                expect(TOKEN_RPAREN, "Expected ')' after function arguments");
            }
            ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
            new_expr_node->type = NODE_FUNCTION_CALL;
            new_expr_node->loc = expr->loc;
            new_expr_node->as.function_call = call_node;
            expr = new_expr_node;
        } 
        else if (match(TOKEN_LBRACKET)) {
            // Check if this is a slice expression by looking for ".." token
            if (peek().type == TOKEN_RANGE || 
               (peek().type != TOKEN_RBRACKET && peekNext().type == TOKEN_RANGE)) {
                
                ASTArraySliceNode* slice_node = (ASTArraySliceNode*)arena_->alloc(sizeof(ASTArraySliceNode));
                slice_node->array = expr;
                
                // Parse start index (optional)
                if (peek().type != TOKEN_RANGE) {
                    slice_node->start = parseExpression();
                    // After parsing start, we must have a range operator
                    expect(TOKEN_RANGE, "Expected '..' after start index in slice expression");
                } else {
                    slice_node->start = NULL; // Implicit start (array[..end])
                    advance(); // Consume the '..'
                }
                
                // Parse end index (optional)
                if (peek().type != TOKEN_RBRACKET) {
                    slice_node->end = parseExpression();
                } else {
                    slice_node->end = NULL; // Implicit end
                }
                
                expect(TOKEN_RBRACKET, "Expected ']' after slice expression");
                
                ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
                new_expr_node->type = NODE_ARRAY_SLICE;
                new_expr_node->loc = expr->loc;
                new_expr_node->as.array_slice = slice_node;
                expr = new_expr_node;
            } 
            else {
                // Standard array access
                ASTArrayAccessNode* access_node = (ASTArrayAccessNode*)arena_->alloc(sizeof(ASTArrayAccessNode));
                access_node->array = expr;
                access_node->index = parseExpression();
                expect(TOKEN_RBRACKET, "Expected ']' after array index");
                
                ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
                new_expr_node->type = NODE_ARRAY_ACCESS;
                new_expr_node->loc = expr->loc;
                new_expr_node->as.array_access = access_node;
                expr = new_expr_node;
            }
        } 
        else {
            break;
        }
    }
    return expr;
}
5. Verify For Loop Statement (Already Correct)

Your current parseForStatement implementation is actually correct and doesn't need changes. It properly uses parseExpression() for the iterable part, which will now correctly handle slice expressions thanks to the updated parsePostfixExpression:

Key Points of This Solution

    Lexer Compatibility: Your lexer already correctly identifies .. as TOKEN_RANGE, so no lexer changes are needed.
    Complete Slice Syntax Support: This implementation handles all slice syntax variations:
        my_slice[0..4] (both bounds specified)
        my_slice[..4] (implicit start)
        my_slice[0..] (implicit end)
        my_slice[..] (full slice)
    Backwards Compatibility: Standard array access like my_array[5] continues to work exactly as before.
    Correct For Loop Integration: The for loop parser naturally benefits from the improved expression parsing without requiring changes.
81. **Task 82:** Final Integration Test Suite Validation
    - Run all previous integration tests again to ensure no regressions were introduced
    - Add edge cases discovered during the fixing process as separate, focused regression tests
    - Document any remaining known limitations in a TODO.md or similar file
    - Recommendation: Always validate that fixes don't break existing functionality.


    
### Milestone 4: Bootstrap Type System & Semantic Analysis
81. **Task 81:** Define core Type struct and TypeKind for C89-compatible types
    - Risk Level: LOW
    - Focus only on types that map directly to C89: i8, i16, i32, i64, u8, u16, u32, u64, isize, usize, f32, f64, bool, void, *T
    - No advanced Zig types like slices, error unions, or optionals for now
    - Constraint Check: All these types can map to C89 equivalent types
82. **Task 82:** Implement minimal Symbol struct and SymbolTable
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
90. **Task 90:** Implement function call checking
    - Risk Level: HIGH ⚠️
    - Argument count validation and basic type matching for arguments
    - Constraint Risk: Function pointers, variadic functions, and calling conventions may not be C89-compatible
    - May need to reject many Zig-specific calling patterns
91. **Task 91:** Implement basic control flow checking
    - Risk Level: LOW
    - Ensure if and while statements have boolean conditions
    - Constraint Check: C89 control flow is supported
92. **Task 92:** Implement basic pointer operation checking
    - Risk Level: MEDIUM
    - Check address-of (&) and dereference (*) operators
    - Constraint Risk: Must ensure no unsafe pointer arithmetic beyond C89 capabilities
93. **Task 93:** Implement C89 compatibility checking
    - Risk Level: CRITICAL ⚠️⚠️⚠️
    - Ensure all generated types map to C89 equivalents and no unsupported Zig features are used
    - Constraint Risk: This is the main gatekeeper - failure here means generated C code won't compile
    - Most complex validation task
94. **Task 94:** Implement basic memory safety for bootstrap
    - Risk Level: HIGH ⚠️
    - Simple pointer safety and compile-time array bounds checking
    - Constraint Risk: C89 has limited safety mechanisms - must be very conservative
95. **Task 95:** Implement struct type checking (simple)
    - Risk Level: MEDIUM
    - Basic struct field access and initialization
    - Constraint Risk: Must ensure no Zig-specific struct features (like methods, etc.)
96. **Task 96:** Implement basic enum type checking
    - Risk Level: LOW
    - Simple enum value access and compatibility
    - Constraint Check: C89 enums are supported
97. **Task 97:** Implement basic error checking
    - Risk Level: CRITICAL ⚠️⚠️⚠️
    - Simple function return type validation
    - Constraint Risk: Zig error handling doesn't exist in C89 - must map to int/error codes or similar
98. **Task 98:** Implement basic function overloading resolution
    - Risk Level: HIGH ⚠️
    - Only simple function resolution needed, focusing on C89-compatible generation
    - Constraint Risk: C89 doesn't support function overloading - must resolve to unique function names
99. **Task 99:** Write bootstrap-specific unit tests
    - Risk Level: MEDIUM
    - Test basic type checking functionality and verify C89 compatibility of generated types
    - Constraint Risk: Tests must cover all rejected features, not just accepted ones
100. **Task 100:** Implement basic integration tests
    - Risk Level: CRITICAL ⚠️⚠️⚠️
    - Parse, type-check, and generate C89 for simple Zig code, and verify the C89 output compiles
    - Constraint Risk: Final validation - if generated C doesn't compile, entire phase fails
101. **Task 101:** Optimize for bootstrap performance
    - Risk Level: LOW
    - Minimal type checking overhead and fast symbol lookups
    - Constraint Check: Performance optimization within C++98 constraints
102. **Task 102:** Document bootstrap limitations clearly
    - Risk Level: MEDIUM
    - List unsupported Zig features and document C89 mapping decisions
    - Constraint Risk: Documentation must be accurate to prevent false expectations

### Milestone 5: Code Generation (C89)
103. **Task 103:** Implement a basic C89 emitter class in `codegen.hpp`.
104. **Task 104:** Implement `CVariableAllocator` to manage C variable names.
105. **Task 105:** Generate C89 function declarations.
106. **Task 106:** Generate C89 code for integer literals.
107. **Task 107:** Generate C89 code for local variable declarations.
108. **Task 108:** Generate C89 code for basic arithmetic operations.
109. **Task 109:** Generate C89 code for comparison and logical operations.
110. **Task 110:** Generate C89 code for if statements.
111. **Task 111:** Generate C89 code for while and for loops.
112. **Task 112:** Generate C89 code for return statements.
113. **Task 113:** Implement C89 function call generation.
114. **Task 114:** Implement C89 code generation for defer statements.
115. **Task 115:** Generate C89 code for slice types.
116. **Task 116:** Generate C89 code for error unions.
117. **Task 117:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
118. **Task 118:** Implement the CBackend class skeleton for final code emission.
119. **Task 119:** Add logic to generate proper C89 headers and include guards.
120. **Task 120:** Implement wrappers for Zig runtime features to C library calls.
121. **Task 121:** Handle Zig memory management with C89-compatible patterns.
122. **Task 122:** Integrate CBackend to write complete C89 `.c` files.
123. **Task 123:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
124. **Task 124:** Translate the C++ compiler logic into the supported Zig subset.
125. **Task 125:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
126. **Task 126:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
127. **Task 127:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
128. **Task 128:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
