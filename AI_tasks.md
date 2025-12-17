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
68. **Task 68:** Implement `parseTryExpression`.
    - Implement the parsing logic for `try` expressions.
    - Update the expression parsing hierarchy.
69. **Task 69:** Implement `parseCatchExpression`.
    - Implement the parsing logic for `catch` expressions.
    - Update the expression parsing hierarchy.
70. **Task 70:** Implement `parseErrDeferStatement`.
    - Implement the parsing logic for `errdefer` statements.
    - Update `parseStatement` to dispatch to the new function.
71. **Task 71:** Implement `parseAsyncExpression`.
    - Implement the parsing logic for `async` expressions.
    - Update the expression parsing hierarchy.
72. **Task 72:** Implement `parseAwaitExpression`.
    - Implement the parsing logic for `await` expressions.
    - Update the expression parsing hierarchy.
73. **Task 73:** Implement `parseComptimeBlock`.
    - Implement the parsing logic for `comptime` blocks.
    - Update `parseStatement` to dispatch to the new function.
74. **Task 74:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement with complex expressions).
    - Verify that the resulting AST is structured correctly.

### Milestone 4: Bootstrap Type System & Semantic Analysis
Task 75: Define core Type struct and TypeKind for C89-compatible types

Risk Level: LOW

    Focus only on types that map directly to C89: i8, i16, i32, i64, u8, u16, u32, u64, isize, usize, f32, f64, bool, void, *T
    No advanced Zig types like slices, error unions, or optionals for now
    Constraint Check: All these types can map to C89 equivalent types

Task 76: Implement minimal Symbol struct and SymbolTable

Risk Level: LOW 

    Basic symbol storage for functions, global variables, and local variables
    Simple name-to-type mapping using C++98 compatible data structures
    Constraint Check: Standard symbol table implementation works fine

Task 77: Implement basic scope management

Risk Level: LOW

    Only global and function scopes are needed initially
    Constraint Check: Scope management is language-independent

Task 78: Implement symbol insertion and lookup

Risk Level: LOW

    Basic name resolution for variables/functions with simple duplicate detection
    Constraint Check: Standard hash table/string interning techniques work

Task 79: Implement TypeChecker skeleton for bootstrap types

Risk Level: MEDIUM

    Focus only on basic C89-compatible operations with minimal error reporting
    Constraint Risk: Need to carefully validate against C89 subset - may miss some restrictions

Task 80: Implement basic type compatibility

Risk Level: LOW

    Integer and pointer type compatibility; basic function signature matching
    Constraint Check: C89 type compatibility rules are well-defined

Task 81: Type-check variable declarations (basic)

Risk Level: LOW

    Simple type annotation checking and basic initializer compatibility
    Constraint Check: C89 variable declarations are straightforward

Task 82: Type-check function signatures

Risk Level: MEDIUM

    Parameter and return type verification
    Constraint Risk: Must reject function pointers, complex return types that don't map to C89

Task 83: Implement basic expression type checking

Risk Level: MEDIUM

    Handle literals, variable access, basic arithmetic, and simple comparisons
    Constraint Risk: Need to ensure all operations map to C89-compatible operations

Task 84: Implement function call checking

Risk Level: HIGH ⚠️

    Argument count validation and basic type matching for arguments
    Constraint Risk: Function pointers, variadic functions, and calling conventions may not be C89-compatible
    May need to reject many Zig-specific calling patterns

Task 85: Implement basic control flow checking

Risk Level: LOW

    Ensure if and while statements have boolean conditions
    Constraint Check: C89 control flow is supported

Task 86: Implement basic pointer operation checking

Risk Level: MEDIUM

    Check address-of (&) and dereference (*) operators
    Constraint Risk: Must ensure no unsafe pointer arithmetic beyond C89 capabilities

Task 87: Implement C89 compatibility checking

Risk Level: CRITICAL ⚠️⚠️⚠️

    Ensure all generated types map to C89 equivalents and no unsupported Zig features are used
    Constraint Risk: This is the main gatekeeper - failure here means generated C code won't compile
    Most complex validation task

Task 88: Implement basic memory safety for bootstrap

Risk Level: HIGH ⚠️

    Simple pointer safety and compile-time array bounds checking
    Constraint Risk: C89 has limited safety mechanisms - must be very conservative

Task 89: Implement struct type checking (simple)

Risk Level: MEDIUM

    Basic struct field access and initialization
    Constraint Risk: Must ensure no Zig-specific struct features (like methods, etc.)

Task 90: Implement basic enum type checking

Risk Level: LOW

    Simple enum value access and compatibility
    Constraint Check: C89 enums are supported

Task 91: Implement basic error checking

Risk Level: CRITICAL ⚠️⚠️⚠️

    Simple function return type validation
    Constraint Risk: Zig error handling doesn't exist in C89 - must map to int/error codes or similar

Task 92: Implement basic function overloading resolution

Risk Level: HIGH ⚠️

    Only simple function resolution needed, focusing on C89-compatible generation
    Constraint Risk: C89 doesn't support function overloading - must resolve to unique function names

Task 93: Write bootstrap-specific unit tests

Risk Level: MEDIUM

    Test basic type checking functionality and verify C89 compatibility of generated types
    Constraint Risk: Tests must cover all rejected features, not just accepted ones

Task 94: Implement basic integration tests

Risk Level: CRITICAL ⚠️⚠️⚠️

    Parse, type-check, and generate C89 for simple Zig code, and verify the C89 output compiles
    Constraint Risk: Final validation - if generated C doesn't compile, entire phase fails

Task 95: Optimize for bootstrap performance

Risk Level: LOW

    Minimal type checking overhead and fast symbol lookups
    Constraint Check: Performance optimization within C++98 constraints

Task 96: Document bootstrap limitations clearly

Risk Level: MEDIUM

    List unsupported Zig features and document C89 mapping decisions
    Constraint Risk: Documentation must be accurate to prevent false expectations

### Milestone 5: Code Generation (C89)
97. **Task 97:** Implement a basic C89 emitter class in `codegen.hpp`.
98. **Task 98:** Implement `CVariableAllocator` to manage C variable names.
99. **Task 99:** Generate C89 function declarations.
100. **Task 100:** Generate C89 code for integer literals.
101. **Task 101:** Generate C89 code for local variable declarations.
102. **Task 102:** Generate C89 code for basic arithmetic operations.
103. **Task 103:** Generate C89 code for comparison and logical operations.
104. **Task 104:** Generate C89 code for if statements.
105. **Task 105:** Generate C89 code for while and for loops.
106. **Task 106:** Generate C89 code for return statements.
107. **Task 107:** Implement C89 function call generation.
108. **Task 108:** Implement C89 code generation for defer statements.
109. **Task 109:** Generate C89 code for slice types.
110. **Task 110:** Generate C89 code for error unions.
111. **Task 111:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
112. **Task 112:** Implement the CBackend class skeleton for final code emission.
113. **Task 113:** Add logic to generate proper C89 headers and include guards.
114. **Task 114:** Implement wrappers for Zig runtime features to C library calls.
115. **Task 115:** Handle Zig memory management with C89-compatible patterns.
116. **Task 116:** Integrate CBackend to write complete C89 `.c` files.
117. **Task 117:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
118. **Task 118:** Translate the C++ compiler logic into the supported Zig subset.
119. **Task 119:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
120. **Task 120:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
121. **Task 121:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
122. **Task 122:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
