# AI Agent Tasks for RetroZig Compiler

This document outlines a granular, step-by-step roadmap for an AI agent to implement the RetroZig compiler. The tasks are organized by phase and component, starting with the C++ bootstrap compiler.

## Phase 0: The Bootstrap Compiler (C++98)

### Milestone 1: Core Infrastructure
1.  **Task 1:** Set up the basic directory structure as defined in `DESIGN.md`. (DONE)
2.  **Task 2:** Create the `common.hpp` compatibility header for MSVC 6.0 specifics (`i64`, `bool`). (DONE)
3.  **Task 3:** Implement the `ArenaAllocator` class in `memory.hpp` for bump allocation. (DONE)
4.  **Task 4:** Add alignment support to `ArenaAllocator::alloc_aligned`. (DONE)
5.  **Task 5:** Implement the `StringInterner` class using a hash table. (DONE)
6.  **Task 6:** Source Manager Implementation. (DONE)
7.  **Task 7:** Define the `ErrorReport` struct and `ErrorCode` enum in `error_handler.hpp`. (DONE)
8.  **Task 8:** Implement a basic diagnostic printing function for errors. (DONE)
9.  **Task 9:** Create a minimal unit testing framework in `test_framework.h`. (DONE)
10. **Task 10:** Create initial `build.bat` and `test.bat` scripts. (DONE)

### Milestone 2: Lexer Implementation
11. **Task 11:** Define all token types (`TokenType` enum) in `lexer.hpp`. (DONE)
    - Created `src/include/lexer.hpp` with a comprehensive `TokenType` enum.
    - Expanded the initial token set as per user feedback to include keywords, operators, and delimiters to better bootstrap the lexer.
12. **Task 12:** Implement the `Token` struct with a union for literal values.
    Define minimal Token struct:
    struct Token {
    TokenType type;
    SourceLocation location;
    union {
        const char* identifier;
        i64 integer;
    } value;
  };
13. **Task 13:** Implement the `Lexer` class skeleton (`lexer.cpp`).
      class Lexer {
      const char* current;
      SourceManager& source;
  public:
      Lexer(SourceManager& src, u32 file_id) : source(src) {}
      Token nextToken();
  }; 
14. **Task 14:** Implement lexing for single-character tokens (e.g., `+`, `-`, `*`, `/`, `;`).
        Add +, -, *, /, ; to TokenType enum
        Implement handling for these tokens in nextToken()
        Write test verifying "a + b;" produces correct token sequence
        Add (, ), {, }, [, ] to token types
        Extend nextToken() to handle brackets
        Write test for bracket tokens
15. **Task 15:** Implement lexing for multi-character tokens (e.g., `==`, `!=`, `<=`, `>=`).
        Add ==, !=, <=, >= to TokenType
      Implement two-character lookahead in nextToken()
      Write test verifying ">=" lexes as single token, not two
      Add = (single) token type and test assignment vs equality
16. **Task 16:** Implement identifier and keyword recognition using a lookup table.
        Complete integer lexing for decimal numbers
        Add string literal token type and basic handling (no escapes yet)
        Implement identifier lexing (letter + alphanum)
        Add keyword recognition for "fn" only (hardcoded check)
        Write test verifying "fn test() {}" lexes correctly
        Implement space/tab skipping in nextToken()
        Add line comment handling (// to end of line)
        Add block comment handling (/* to */)
        Write test verifying comments are fully skipped
18. **Task 17:** Implement lexing for integer literals (`i64`).
24. **Task 18:** Implement lexing for string literals.
25. **Task 19:** Implement logic to skip single-line and block comments.
26. **Task 20:** Write comprehensive unit tests for the lexer, covering all token types and edge cases.

### Milestone 3: Parser & AST
21. **Task 21:** Define the base `ASTNode` and all derived node structures (e.g., `FnDeclNode`, `VarDeclNode`, `IfStmtNode`).
22. **Task 22:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`).
23. **Task 23:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`).
24. **Task 24:** Implement parsing for top-level variable declarations (`var` and `const`).
25. **Task 25:** Implement parsing for function definitions (`fn`).
26. **Task 26:** Implement `parseBlockStatement` for `{ ... }` scopes.
27. **Task 27:** Implement `parseIfStatement` including `else` branches.
28. **Task 28:** Implement `parseWhileStatement`.
29. **Task 29:** Implement `parseDeferStatement`, adding the node to a list for the current scope.
30. **Task 30:** Implement `parseReturnStatement`.
31. **Task 31:** Implement expression parsing with correct operator precedence.
32. **Task 32:** Handle unary operators (`-`, `!`).
33. **Task 33:** Handle function call expressions.
34. **Task 34:** Handle array/slice access expressions (`expr[index]`).
35. **Task 35:** Write unit tests to verify the parser constructs the correct AST for various language features.

### Milestone 4: Type System & Symbol Table
36. **Task 36:** Define the `Type` struct and `TypeKind` enum for all supported types.
37. **Task 37:** Implement the `Symbol` struct and `SymbolTable` class.
38. **Task 38:** Implement scope management in `SymbolTable` (`pushScope`, `popScope`).
39. **Task 39:** Implement symbol lookup and insertion logic.
40. **Task 40:** Implement the type-checking visitor/pass.
41. **Task 41:** Add type-checking logic for variable declarations, ensuring the expression type matches the declared type.
42. **Task 42:** Implement type compatibility rules for assignments (e.g., integer widening).
43. **Task 43:** Type-check binary expressions (e.g., `int + int`).
44. **Task 44:** Type-check function calls, matching argument types to parameter types.
45. **Task 45:** Write unit tests for the type checker, including tests for valid and invalid programs.

### Milestone 5: Code Generation (x86)
46. **Task 46:** Implement a basic x86 assembly emitter class in `codegen.hpp`.
47. **Task 47:** Implement the `RegisterAllocator` using a linear scan strategy.
48. **Task 48:** Generate function prologues (`push ebp; mov ebp, esp`) and epilogues.
49. **Task 49:** Generate code for loading integer literals into registers.
50. **Task 50:** Generate code for local variable access (`mov eax, [ebp-offset]`).
51. **Task 51:** Generate code for basic arithmetic operations (`add`, `sub`, `imul`, `idiv`).
52. **Task 52:** Generate code for comparison operators and conditional jumps (`cmp`, `je`, `jne`, etc.).
53. **Task 53:** Generate code for `if` statements using labels and jumps.
54. **Task 54:** Generate code for `while` loops.
55. **Task 55:** Generate code for `return` statements, placing the return value in `EAX`.
56. **Task 56:** Implement the function call ABI (pushing arguments to the stack).
57. **Task 57:** Implement code generation for `defer` statements, emitting their code in reverse order at scope exit.
58. **Task 58:** Generate code for slice types, passing pointer and length on the stack.
59. **Task 59:** Generate code for error unions, using `EDX` for the error code and `EAX` for the payload.
60. **Task 60:** Write integration tests that compile simple Zig programs and verify the output assembly.

### Milestone 6: PE Backend & Final Bootstrap
61. **Task 61:** Implement the `PEBuilder` class skeleton.
62. **Task 62:** Implement generation of the `IMAGE_DOS_HEADER` and `IMAGE_NT_HEADERS`.
63. **Task 63:** Add logic to create the `.text` (code) and `.data` (globals) sections.
64. **Task 64:** Implement logic to create the `.idata` section for `kernel32.dll` imports (`ExitProcess`).
65. **Task 65:** Integrate the `PEBuilder` with the code generator to write a complete `.exe` file.
66. **Task 66:** Compile a "hello world" style Zig program using the full C++ bootstrap compiler (`zig0.exe`).

## Phase 1: The Cross-Compiler (Zig)
67. **Task 67:** Begin translating the C++ compiler logic (`lexer`, `parser`, etc.) into the supported Zig subset in `lib/compiler.zig`.
68. **Task 68:** Use the C++ bootstrap compiler (`zig0.exe`) to compile `lib/compiler.zig` into `zig1.exe`.
69. **Task 69:** Verify that `zig1.exe` is a functional compiler by using it to compile the test suite.

## Phase 2: Self-Hosting
70. **Task 70:** Use the generated Zig compiler (`zig1.exe`) to compile its own source code (`lib/compiler.zig`) to produce `zig2.exe`.
71. **Task 71:** Perform a binary comparison (`fc /b`) between `zig1.exe` and `zig2.exe`. If they are identical, the compiler is officially self-hosting.
