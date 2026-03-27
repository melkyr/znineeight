### Part 1: MSVC 6.0 Env Setup
- [x] Set up Windows 98 VM with MSVC 6.0
- [ ] Create `PEBuilder` skeleton (generating a valid empty .exe)
- [x] Implement compatibility layer (`common.hpp`)

### Part 2: Memory & Lexer
- [x] Implement Arena Allocator with alignment support
- [x] Create String Interning system
- [x] Implement lexer class with token definitions
  - [x] Define Token struct and Zig0TokenType enum
  - [x] Implement Lexer class skeleton
  - [x] Implement lexing for single-character tokens
  - [x] Implement lexing for multi-character tokens (`==`, `!=`, `<=`, `>=`)
  - [x] Implement lexing for float literals (`3.14`, `0x1.2p3`)
  - [x] Implement lexing for integer literals (`123`, `0xFF`)
  - [x] Implement line comment handling (`//`)
  - [x] Implement block comment handling (`/* */`) with nesting support
  - [x] Implement keyword recognition for type declarations (`enum`, `error`, `struct`, `union`, `opaque`)
  - [x] Implement keyword recognition for visibility and linkage (`export`, `extern`, `pub`, `linksection`, `usingnamespace`)
  - [x] Implement keyword recognition for compile-time and special functions (`asm`, `comptime`, `errdefer`, `inline`, `noinline`, `test`, `unreachable`)

### Part 3: Parser & AST
- [x] Implement recursive descent parser
- [x] Handle expressions with precedence
- [x] Parse function declarations
- [x] Implement defer statement handling

### Part 4: Type System
- [x] Define type representation (Primitives, Pointers, Slices, Error Unions)
- [x] Implement type compatibility rules
- [x] Create symbol table system

### Part 5: Basic Code Generation (C89)
- [x] Design C89 emitter (Mock emitter for Milestone 4)
- [x] Implement full C89 code generation for functions
- [x] Generate code for variable declarations
- [x] Handle basic expressions

### Part 6: Advanced Code Generation
- [x] Implement defer statement code generation
- [x] Handle slices and error unions (Slices: DONE, Error Unions: DONE)
- [x] Add Win32 imports for kernel32.dll
- [x] Test generated code correctness

### Part 7: Bootstrap Stage 0 -> Stage 1
- [ ] Write minimal Zig compiler in C++
- [ ] Test compilation of stage1.zig
- [ ] Verify generated executable works

### Part 8: Self-Hosting Verification
- [ ] Complete compiler implementation in Zig subset
- [ ] Test self-compilation cycle (Stage 1 -> Stage 2)
- [ ] Verify bootstrap integrity with binary comparison
