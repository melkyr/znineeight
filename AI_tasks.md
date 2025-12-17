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
17. **Task 17:** Update `TokenType` enum in `src/include/lexer.hpp` to include all missing tokens as defined in `Lexer.md`.
18. **Task 18:** Implement lexing for `TOKEN_CHAR_LITERAL` (e.g., `'a'`). (DONE)
19. **Task 19:** Implement lexing for `TOKEN_FLOAT_LITERAL` (e.g., `3.14`). (DONE)
20. **Task 20:** Implement lexing for remaining arithmetic and bitwise operators (`%`, `~`, `&`, `|`, `^`, `<<`, `>>`).
21. **Task 21:** Implement lexing for compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`). (DONE)
22. **Task 22:** Implement lexing for special and wrapping operators (`.`, `.*`, `.?`, `?`, `++`, `**`, `||`, `+%`, `-%`, `*%`).
23. **Task 23:** Implement lexing for remaining delimiters (`:`, `->`, `=>`, `...`).
24. **Task 24:** Implement keyword recognition for control flow (`break`, `catch`, `continue`, `else`, `for`, `if`, `orelse`, `resume`, `suspend`, `switch`, `try`, `while`). (DONE)
25. **Task 25:** Implement keyword recognition for type declarations (`enum`, `error`, `struct`, `union`, `opaque`).
26. **Task 26:** Implement keyword recognition for visibility and linkage (`export`, `extern`, `pub`, `linksection`, `usingnamespace`). (DONE)
27. **Task 27:** Implement keyword recognition for compile-time and special functions (`asm`, `comptime`, `errdefer`, `inline`, `noinline`, `test`, `unreachable`). (DONE)
28. **Task 28:** Implement keyword recognition for memory and calling conventions (`addrspace`, `align`, `allowzero`, `and`, `anyframe`, `anytype`, `callconv`, `noalias`, `nosuspend`, `or`, `packed`, `threadlocal`, `volatile`). (DONE)
29. **Task 29:** Implement logic to skip single-line and block comments. (This was previously part of other tasks, now consolidated).
30. **Task 30:** Write comprehensive unit tests for the lexer, covering all new token types and edge cases.
31. **Task 31:** Implement lexing for `TOKEN_STRING_LITERAL` and properly handle `TOKEN_IDENTIFIER` values. This includes storing the string content (for string literals) and the identifier name, likely using the string interner.
32. **Task 32:** Extend the lexer to handle escaped characters in string literals (e.g., `\n`, `\t`, `\\`, `\"`).
33. **Task 33:** Implement lexing for crucial missing keywords (`fn`, `var`, `defer`).
34. **Task 34:** Implement lexing for missing operators (`--`, `&&`).

### Milestone 3: Parser & AST
35. **Task 35:** Define foundational AST structures (Expressions, Statements, Declarations, Types). (DONE)
36. **Task 36:** Define AST nodes for advanced language features (Containers, Control Flow, Error Handling, etc.). (DONE)
37. **Task 37:** Implement core Parser class and foundational parsing logic (`parseType`, `parseVarDecl`, `parseFnDecl`, `parseBlockStatement`, etc.). (DONE)
38. **Task 38:** Implement a complete, precedence-aware Expression Parser. (DONE)
    - This includes primary, postfix (function calls, array access), unary, and binary expressions.
    - This task consolidates and completes the original tasks 57-62.
39. **Task 39:** Implement parsing for core statements (`if`, `while`, `defer`, `return`). (DONE)
    - This task consolidates and completes the original tasks 50, 51, 55, and 56.
40. **Task 40:** **(NEW)** Implement Parser for Control Flow.
    - Implement `parseForStatement` to handle `for` loops.
    - Implement `parseSwitchExpression` to handle `switch` expressions.
    - Integrate these functions into the main `parseStatement` or `parseExpression` dispatcher.
41. **Task 41:** **(NEW)** Implement Parser for Container Declarations.
    - Implement `parseStructDecl` for `struct` definitions.
    - Implement `parseUnionDecl` for `union` definitions.
    - Implement `parseEnumDecl` for `enum` definitions.
    - These functions will likely be called from a top-level parsing function.
42. **Task 42:** **(NEW)** Implement Parser for Error Handling.
    - Implement parsing for `try` expressions.
    - Implement parsing for `catch` expressions.
    - Implement `parseErrDeferStatement` for `errdefer` statements.
43. **Task 43:** **(NEW)** Perform a Comprehensive Update of `AST_parser.md`.
    - Synchronize the `NodeType` enum and `ASTNode` union definitions with `ast.hpp`.
    - Update the "Out-of-Line" allocation strategy section and the node size table to be fully accurate.
    - Remove the outdated "Future AST Node Requirements" section and ensure all parsing logic descriptions match the implementation.
    - Update the operator precedence table to match the one in `parser.cpp`.
44. **Task 44:** **(NEW)** Add Missing Doxygen Comments to Parser.
    - Add Doxygen-style comments to all undocumented functions in `parser.hpp` and `parser.cpp`.
    - Ensure existing comments are accurate and reflect the current implementation.
45. **Task 45:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement with complex expressions).
    - Verify that the resulting AST is structured correctly.

### Milestone 4: Bootstrap Type System & Semantic Analysis
46. **Task 46:** Define core Type struct and TypeKind for C89-compatible types.
    - Focus only on types that map directly to C89: i8, i16, i32, i64, u8, u16, u32, u64, isize, usize, f32, f64, bool, void, *T.
    - No advanced Zig types like slices, error unions, or optionals for now.
47. **Task 47:** Implement minimal Symbol struct and SymbolTable.
    - Basic symbol storage for functions, global variables, and local variables.
    - Simple name-to-type mapping.
48. **Task 48:** Implement basic scope management.
    - Only global and function scopes are needed initially.
49. **Task 49:** Implement symbol insertion and lookup.
    - Basic name resolution for variables/functions with simple duplicate detection.
50. **Task 50:** Implement TypeChecker skeleton for bootstrap types.
    - Focus only on basic C89-compatible operations with minimal error reporting.
51. **Task 51:** Implement basic type compatibility.
    - Integer and pointer type compatibility; basic function signature matching.
52. **Task 52:** Type-check variable declarations (basic).
    - Simple type annotation checking and basic initializer compatibility.
53. **Task 53:** Type-check function signatures.
    - Parameter and return type verification.
54. **Task 54:** Implement basic expression type checking.
    - Handle literals, variable access, basic arithmetic, and simple comparisons.
55. **Task 55:** Implement function call checking.
    - Argument count validation and basic type matching for arguments.
56. **Task 56:** Implement basic control flow checking.
    - Ensure `if` and `while` statements have boolean conditions.
57. **Task 57:** Implement basic pointer operation checking.
    - Check address-of (`&`) and dereference (`*`) operators.
58. **Task 58:** Implement C89 compatibility checking.
    - Ensure all generated types map to C89 equivalents and no unsupported Zig features are used.
59. **Task 59:** Implement basic memory safety for bootstrap.
    - Simple pointer safety and compile-time array bounds checking.
60. **Task 60:** Implement struct type checking (simple).
    - Basic struct field access and initialization.
61. **Task 61:** Implement basic enum type checking.
    - Simple enum value access and compatibility.
62. **Task 62:** Implement basic error checking.
    - Simple function return type validation.
63. **Task 63:** Implement basic function overloading resolution.
    - Only simple function resolution needed, focusing on C89-compatible generation.
64. **Task 64:** Write bootstrap-specific unit tests.
    - Test basic type checking functionality and verify C89 compatibility of generated types.
65. **Task 65:** Implement basic integration tests.
    - Parse, type-check, and generate C89 for simple Zig code, and verify the C89 output compiles.
66. **Task 66:** Optimize for bootstrap performance.
    - Minimal type checking overhead and fast symbol lookups.
67. **Task 67:** Document bootstrap limitations clearly.
    - List unsupported Zig features and document C89 mapping decisions.

### Milestone 5: Code Generation (C89)
68. **Task 68:** Implement a basic C89 emitter class in `codegen.hpp`.
69. **Task 69:** Implement `CVariableAllocator` to manage C variable names.
70. **Task 70:** Generate C89 function declarations.
71. **Task 71:** Generate C89 code for integer literals.
72. **Task 72:** Generate C89 code for local variable declarations.
73. **Task 73:** Generate C89 code for basic arithmetic operations.
74. **Task 74:** Generate C89 code for comparison and logical operations.
75. **Task 75:** Generate C89 code for if statements.
76. **Task 76:** Generate C89 code for while and for loops.
77. **Task 77:** Generate C89 code for return statements.
78. **Task 78:** Implement C89 function call generation.
79. **Task 79:** Implement C89 code generation for defer statements.
80. **Task 80:** Generate C89 code for slice types.
81. **Task 81:** Generate C89 code for error unions.
82. **Task 82:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
83. **Task 83:** Implement the CBackend class skeleton for final code emission.
84. **Task 84:** Add logic to generate proper C89 headers and include guards.
85. **Task 85:** Implement wrappers for Zig runtime features to C library calls.
86. **Task 86:** Handle Zig memory management with C89-compatible patterns.
87. **Task 87:** Integrate CBackend to write complete C89 `.c` files.
88. **Task 88:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
89. **Task 89:** Translate the C++ compiler logic into the supported Zig subset.
90. **Task 90:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
91. **Task 91:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
92. **Task 92:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
93. **Task 93:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
