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

### Milestone 3: Parser & AST
32. **Task 32:** Define the base `ASTNode` and all derived node structures (e.g., `FnDeclNode`, `VarDeclNode`, `IfStmtNode`).
33. **Task 33:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`).
34. **Task 34:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`).
35. **Task 35:** Implement parsing for top-level variable declarations (`var` and `const`).
36. **Task 36:** Implement parsing for function definitions (`fn`).
37. **Task 37:** Implement `parseBlockStatement` for `{ ... }` scopes.
38. **Task 38:** Implement `parseIfStatement` including `else` branches.
39. **Task 39:** Implement `parseWhileStatement`.
40. **Task 40:** Implement `parseDeferStatement`, adding the node to a list for the current scope.
41. **Task 41:** Implement `parseReturnStatement`.
42. **Task 42:** Implement expression parsing with correct operator precedence.
43. **Task 43:** Handle unary operators (`-`, `!`).
44. **Task 44:** Handle function call expressions.
45. **Task 45:** Handle array/slice access expressions (`expr[index]`).
46. **Task 46:** Write unit tests to verify the parser constructs the correct AST for various language features.

### Milestone 4: Type System & Symbol Table
47. **Task 47:** Define the `Type` struct and `TypeKind` enum for all supported types.
48. **Task 48:** Implement the `Symbol` struct and `SymbolTable` class.
49. **Task 49:** Implement scope management in `SymbolTable` (`pushScope`, `popScope`).
50. **Task 50:** Implement symbol lookup and insertion logic.
51. **Task 51:** Implement the type-checking visitor/pass.
52. **Task 52:** Add type-checking logic for variable declarations, ensuring the expression type matches the declared type.
53. **Task 53:** Implement type compatibility rules for assignments (e.g., integer widening).
54. **Task 54:** Type-check binary expressions (e.g., `int + int`).
55. **Task 55:** Type-check function calls, matching argument types to parameter types.
56. **Task 56:** Write unit tests for the type checker, including tests for valid and invalid programs.

### Milestone 5: Code Generation (x86)
57. **Task 57:** Implement a basic x86 assembly emitter class in `codegen.hpp`.
58. **Task 58:** Implement the `RegisterAllocator` using a linear scan strategy.
59. **Task 59:** Generate function prologues (`push ebp; mov ebp, esp`) and epilogues.
60. **Task 60:** Generate code for loading integer literals into registers.
61. **Task 61:** Generate code for local variable access (`mov eax, [ebp-offset]`).
62. **Task 62:** Generate code for basic arithmetic operations (`add`, `sub`, `imul`, `idiv`).
63. **Task 63:** Generate code for comparison operators and conditional jumps (`cmp`, `je`, `jne`, etc.).
64. **Task 64:** Generate code for `if` statements using labels and jumps.
65. **Task 65:** Generate code for `while` loops.
66. **Task 66:** Generate code for `return` statements, placing the return value in `EAX`.
67. **Task 67:** Implement the function call ABI (pushing arguments to the stack).
68. **Task 68:** Implement code generation for `defer` statements, emitting their code in reverse order at scope exit.
69. **Task 69:** Generate code for slice types, passing pointer and length on the stack.
70. **Task 70:** Generate code for error unions, using `EDX` for the error code and `EAX` for the payload.
71. **Task 71:** Write integration tests that compile simple Zig programs and verify the output assembly.

### Milestone 6: PE Backend & Final Bootstrap
72. **Task 72:** Implement the `PEBuilder` class skeleton.
73. **Task 73:** Implement generation of the `IMAGE_DOS_HEADER` and `IMAGE_NT_HEADERS`.
74. **Task 74:** Add logic to create the `.text` (code) and `.data` (globals) sections.
75. **Task 75:** Implement logic to create the `.idata` section for `kernel32.dll` imports (`ExitProcess`).
76. **Task 76:** Integrate the `PEBuilder` with the code generator to write a complete `.exe` file.
77. **Task 77:** Compile a "hello world" style Zig program using the full C++ bootstrap compiler (`zig0.exe`).

## Phase 1: The Cross-Compiler (Zig)
78. **Task 78:** Begin translating the C++ compiler logic (`lexer`, `parser`, etc.) into the supported Zig subset in `lib/compiler.zig`.
79. **Task 79:** Use the C++ bootstrap compiler (`zig0.exe`) to compile `lib/compiler.zig` into `zig1.exe`.
80. **Task 80:** Verify that `zig1.exe` is a functional compiler by using it to compile the test suite.

## Phase 2: Self-Hosting
81. **Task 81:** Use the generated Zig compiler (`zig1.exe`) to compile its own source code (`lib/compiler.zig`) to produce `zig2.exe`.
82. **Task 82:** Perform a binary comparison (`fc /b`) between `zig1.exe` and `zig2.exe`. If they are identical, the compiler is officially self-hosting.
