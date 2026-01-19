# RetroZig Compiler: Master Design Document (v1.1)

## 1. Project Overview & Philosophy
**Goal:** Create a self-hosting Zig compiler targeting Windows 9x era toolchains (1998-2000).
**Philosophy:** "Progressive Enhancement" starting with a C++98 bootstrap compiler (Stage 0) that compiles a Zig-written compiler (Stage 1), eventually leading to a self-hosted executable (Stage 2).
**Target Environment:**
* **OS:** Windows 95/98/ME/NT 4.0
* **Hardware:** Intel Pentium I/II (i586), 32-64MB RAM
* **Host Compiler:** MSVC 6.0 (Visual C++ 98)
* **Output:** 32-bit Win32 PE Executables (no external linker dependency in final stage)

## 2. Technical Constraints
To ensure compatibility with 1998-era hardware and software:
* **Language Standard:** C++98 (max) for bootstrap; limited C++ STL usage due to fragmentation
* **Memory Limit:** < 16MB peak usage preferred. No smart pointers or heavy templates
* **Dependencies:** Win32 API (`kernel32.dll`) only. No third-party libs
* **C++ Standard Library Usage Policy:**
  * **Allowed:** Headers that are generally implemented by the compiler and have no external runtime library dependencies or hidden memory allocations. This includes headers like `<new>` (for placement new), `<cstddef>` (for `size_t`), `<cassert>` (for `assert`), and `<climits>`.
  * **Forbidden:** Headers that depend on a C/C++ runtime library (like `msvcrt.dll` beyond `kernel32.dll`) or perform dynamic memory allocation. This includes headers like `<cstdio>` (`fprintf`), `<cstdlib>` (`malloc`), `<string>` (`std::string`), and `<vector>` (`std::vector`).
* **Specific MSVC 6.0 Hacks:**
  * Use `__int64` instead of `long long`
  * Define `bool`, `true`, `false` manually if missing
* **Dynamic Memory:** Standard C dynamic memory allocation functions (e.g., `malloc`, `free`) are forbidden. The compiler will produce a fatal error if calls to these functions are detected.

## 3. Architecture & Memory Strategy
The compiler uses a layered architecture relying heavily on "Arena Allocation" to avoid `malloc`/`free` overhead on slow 90s allocators.

### 3.1 Memory Management (`memory.hpp`)
**Concept:** A region-based allocator that frees all memory at once (e.g., after a compilation pass)
```cpp
class ArenaAllocator {
    char* buffer;           // Large pre-allocated block (e.g., 1MB)
    size_t offset;          // Current "bump" pointer
    size_t capacity;        // Max size
public:
    void* alloc(size_t size); // Returns &buffer[offset] and increments offset
    void* alloc_aligned(size_t size, size_t align);
    void reset();           // Sets offset = 0 (fast free)
};
```
* **Usage:** AST Nodes, Types, and Symbols are allocated here
* **Alignment:** The `alloc()` method now guarantees 8-byte alignment for all allocations, which is safe for most data types. For specific alignment needs, `alloc_aligned()` is available.
* **Safety:** The allocator uses overflow-safe checks in both `alloc` and `alloc_aligned` to prevent memory corruption when the arena is full. The `DynamicArray` implementation is also safe for non-POD types, as it uses copy construction with placement new instead of `memcpy` or assignment during reallocation.

### 3.2 Utility Functions (`utils.hpp`)
**Purpose:** Provide safe string and numeric utilities that avoid modern C++ dependencies.

* **`safe_append(char*& dest, size_t& remaining, const char* src)`**: Appends a string to a buffer while tracking remaining space and ensuring null-termination (even on truncation).
* **`simple_itoa(long value, char* buffer, size_t buffer_size)`**: Converts a `long` to a string without using `sprintf` or `std::string`.

### 3.3 String Interning (`string_interner.hpp`)
**Concept:** Deduplicate identifiers. If "varname" appears 50 times, store it once and compare pointers.
* **Structure:** Hash table (1024 buckets) with chaining
* **Hashing:** FNV-1a or similar simple hash
* **Performance:** Reduces memory usage and speeds up identifier comparisons

### 3.3 Source Management (`source_manager.hpp`)
**Purpose:** Track source code locations and file content
```cpp
struct SourceLocation {
    uint32_t file_id;
    uint32_t line;
    uint32_t column;
};
class SourceManager {
    struct SourceFile {
        const char* filename;
        const char* content;
        size_t size;
    };
    std::vector<SourceFile> files;
public:
    SourceLocation getLocation(size_t offset);
};
```

### 3.4 Error Handling System (`error_handler.hpp`)
```cpp
class ErrorHandler {
public:
    ErrorHandler(SourceManager& sm);
    void printErrorReport(const ErrorReport& report);
};

enum ErrorCode {
    ERR_SYNTAX_ERROR = 1000,
    ERR_TYPE_MISMATCH = 2000,
    ERR_UNDEFINED_VARIABLE = 3000,
    ERR_INVALID_OPERATION = 4000,
    ERR_OUT_OF_MEMORY = 5000
};

struct ErrorReport {
    ErrorCode code;
    SourceLocation location;
    const char* message;
    const char* hint;
};
```
**Diagnostic Format:**
```
filename.zig(23:5): error 2001: Cannot assign 'string' to 'int'
    my_var = "hello";
    ^^^^^^
    Hint: Convert string to integer using parseInt()
```
**Error Recovery Strategy:**
- **Synchronization Points:** After semicolons, closing braces, or specific keywords
- **Recovery Tokens:** 'fn', 'var', 'const', ';', '}', ')'
- **Maximum Skip:** 50 tokens before giving up

## 4. Compilation Pipeline

### 4.0 Compilation Unit (`compilation_unit.hpp`)
**Concept:** A `CompilationUnit` is an ownership wrapper that manages the memory and resources for a single compilation task. It ties together the `ArenaAllocator`, `StringInterner`, and `SourceManager` to provide a clean, unified interface for compiling source code.

**Key Responsibilities:**
- **Lifetime Management:** Ensures that all objects related to a compilation (AST nodes, tokens, interned strings) are allocated from a single arena, making cleanup trivial.
- **Source Aggregation:** Manages one or more source files through the `SourceManager`.
- **Pipeline Orchestration:** Manages the sequential execution of compilation phases:
    1.  **Lexing & Parsing:** Produces the Initial AST.
    2.  **Type Checking:** Resolves types and populates the `SymbolTable` with semantic flags (e.g., `SYMBOL_FLAG_LOCAL`).
    3.  **Lifetime Analysis:** Detects memory safety issues like dangling pointers.
    4.  **Code Generation:** Emits target code (C89).
- **Parser Creation:** Provides a factory method, `createParser()`, which encapsulates the entire process of lexing a source file and preparing a `Parser` instance for syntactic analysis. It uses a `TokenSupplier` internally, which guarantees that the token stream passed to the parser has a stable memory address that will not change for the lifetime of the `CompilationUnit`'s arena. This prevents dangling pointer errors.

**Example Usage:**
```cpp
// In a test environment
ArenaAllocator arena(1024);
StringInterner interner(arena);
CompilationUnit unit(arena, interner);
u32 file_id = unit.addSource("test.zig", "const x: i32 = 42;");
Parser* parser = unit.createParser(file_id);
// ... proceed with parsing using parser->parse()...
```

This abstraction is critical for future work, as it will simplify the management of multiple files, diagnostic reporting, and the overall compilation state.

### 4.1 Layer 1: Lexer (`lexer.hpp`)
* **Input:** Source code text
* **Output:** A stable stream of `Token` structs. The memory for this stream is managed by the `TokenSupplier` and is guaranteed not to move.
* **Lexer Class Interface:**
```cpp
class Lexer {
    const char* current;
    SourceManager& source;
public:
    Lexer(SourceManager& src, u32 file_id);
    Token nextToken();
};
```
* **Token Definition (`TokenType`):** The core of the lexer is the `TokenType` enum, which defines all possible tokens. For a complete and up-to-date list of all tokens and their implementation status, please see the `Lexer.md` document.

* **Value Storage:** Unions for `i64`, `double`, and `char*` (interned string)
* **Token Precedence Table:**
```cpp
const int PRECEDENCE_TABLE[] = {
    // Example precedence, actual implementation is in the parser.
    // [KEYWORD_OR] = 2,
    // [KEYWORD_AND] = 3,
};
```

### 4.2 Layer 2: Parser (`parser.hpp`)
* **Method:** Recursive Descent
* **Output:** Abstract Syntax Tree (AST) linked to Arena
* **Parser Class Interface:**
```cpp
class Parser {
private:
    TokenStream* tokens;
    SymbolTable* symbols;
    ArenaAllocator* allocator;
    Token current_token;
    void advance();
    bool match(TokenType type);
    void expect(TokenType type);
public:
    Parser(TokenStream* ts, SymbolTable* sym, ArenaAllocator* alloc);
    ASTNode* parseProgram();
    ASTNode* parseTopLevelItem();
    ASTNode* parseStatement();
    ASTNode* parseExpression();
    ASTNode* parseType();
private:
    ASTNode* parseFunctionDefinition();
    ASTNode* parseVariableDeclaration();
    ASTNode* parseBlockStatement();
    ASTNode* parseIfStatement();
    ASTNode* parseWhileStatement();
    ASTNode* parseDeferStatement(); // NEW: Handle defer execution
};
```

* **Defer Handling:**
  * The parser treats `defer` as a statement node
  * It **does not** reorder code; it simply records the `DEFER_STMT` node in the AST block. The *Code Generator* handles the execution order.
  * During parsing of a block, `defer` statements are pushed into a vector for later processing

### 4.3 Layer 3: Semantic Analysis & Lifetime (`type_checker.hpp`, `lifetime_analyzer.hpp`)

Semantic analysis is performed in two distinct, sequential passes after the AST is generated.

#### Pass 1: Type Checking
The `TypeChecker` resolves identifiers, verifies type compatibility for assignments and operations, and populates the `SymbolTable` with semantic metadata.

- **Symbol Flags:** Symbols are marked with flags like `SYMBOL_FLAG_LOCAL` (stack variables), `SYMBOL_FLAG_PARAM` (function parameters), and `SYMBOL_FLAG_GLOBAL` based on their declaration context.
- **Redefinition Check:** Ensures no two symbols share the same name in the same scope.

#### Pass 2: Lifetime Analysis (Task 125)
The `LifetimeAnalyzer` is a read-only pass that detects memory safety violations, specifically dangling pointers created by returning pointers to local variables or parameters.

- **Provenance Tracking:** It tracks which pointers are assigned the addresses of local variables (e.g., `p = &x;`). It uses a `DynamicArray` to store `PointerAssignment` records for the current function scope.

#### Pass 3: Null Pointer Analysis (Task 126)
The `NullPointerAnalyzer` is a read-only pass that identifies potential null pointer dereferences and uninitialized pointer usage.

- **Phase 1 (Infrastructure):** Implements the core skeleton, visitor framework, and a robust, scoped state-tracking system.
- **State Tracking:** Tracks pointer nullability states (`UNINIT`, `NULL`, `SAFE`, `MAYBE`) throughout function bodies and global declarations.
- **Scope Management:** Employs a stack-based scope system to handle variable persistence and shadowing correctly across nested blocks.
- **Violation Detection (Phase 2):** Definite null dereferences (`ERR_NULL_POINTER_DEREFERENCE` - 2004), uninitialized pointer warnings (`WARN_UNINITIALIZED_POINTER` - 6001), and potential null dereference warnings (`WARN_POTENTIAL_NULL_DEREFERENCE` - 6002) are planned for implementation in Phase 2.
- **Assignment Handling**: The analyzer tracks direct address-of assignments (`ptr = &local`) and correctly handles reassignments within a function.
- **Violation Detection:** Reports `ERR_LIFETIME_VIOLATION` if a local address or a pointer to a local variable is returned from a function.
- **Parameter Safety**: Directly returning a parameter is permitted, as its lifetime is managed by the caller, but returning the address of a parameter (`&param`) is blocked as it resides on the current stack frame.

### 4.4 Layer 4: Type System (`type_system.hpp`)
**Supported Types (Bootstrap Phase):**
* **Primitives:** `i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `bool`, `f32`, `f64`, `void`
* **Pointers:** `*T` (Single level)

**Type Representation:**
```cpp
// Forward-declare Type for the pointer union member
struct Type;

enum TypeKind {
    TYPE_VOID,
    TYPE_BOOL,
    // Integer Types
    TYPE_I8, TYPE_I16, TYPE_I32, TYPE_I64,
    TYPE_U8, TYPE_U16, TYPE_U32, TYPE_U64,
    // Platform-dependent Integer Types
    TYPE_ISIZE, // Maps to i32 on 32-bit target
    TYPE_USIZE, // Maps to u32 on 32-bit target
    // Floating-Point Types
    TYPE_F32,
    TYPE_F64,
    // Complex Types
    TYPE_POINTER
};

struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;
    union {
        struct {
            Type* base;
        } pointer;
    } as;
};
```

**Validation Logic:**
* **Strict Typing:** No implicit coercion between pointers (e.g., `*i32` to `*u8` requires cast)
* **Implicit Widening:** Allowed for integers (`i32` -> `i64`)
* **Type Compatibility Matrix:**
  | From Type | To Type | Implicit | Explicit |
  |-----------|---------|----------|----------|
  | i8 | i16, i32, i64 | ✓ | - |
  | u8 | u16, u32, u64 | ✓ | - |
  | i32 | f32, f64 | - | ✓ |
  | f32 | f64 | ✓ | - |
  | T | *T | ✓ | - |
  | *T | *const T | ✓ | - |

### 4.5 Layer 5: Symbol Table (`symbol_table.hpp`)
**Concept:** A hierarchical table for managing identifiers (variables, functions, types) across different scopes. It is designed to be extensible to support the growing complexity of the language.

**Scoping:** The table uses a stack of `Scope` objects. When the parser enters a new block, it calls `enterScope()`, and when it exits, it calls `exitScope()`. Lookups search from the innermost scope outwards, correctly handling symbol shadowing.

**Symbol Creation:** To manage the creation of increasingly complex `Symbol` structs, a `SymbolBuilder` is used. This follows the Builder pattern, allowing for clear and flexible symbol construction.

```cpp
// The core identifier structure, expanded for richer semantics.
struct Symbol {
    const char* name;
    SymbolType type;
    SourceLocation location; // Where the symbol was defined
    void* details;           // Pointer to an ASTNode (e.g., ASTStructDeclNode)
    unsigned int scope_level;
    unsigned int flags;      // e.g., MUTABLE, CONST
};

// Builder for ergonomic Symbol creation.
class SymbolBuilder {
public:
    SymbolBuilder(ArenaAllocator& arena);
    SymbolBuilder& withName(const char* name);
    SymbolBuilder& ofType(SymbolType type);
    // ... other setters ...
    Symbol build();
};

// A single level in the scope stack.
struct Scope {
    DynamicArray<Symbol> symbols;
    Scope(ArenaAllocator& arena);
};

// The main symbol table class.
class SymbolTable {
    ArenaAllocator& arena_;
    DynamicArray<Scope*> scopes;
public:
    SymbolTable(ArenaAllocator& arena);
    void enterScope();
    void exitScope();
    bool insert(const Symbol& symbol); // Inserts into the current scope.
    Symbol* lookup(const char* name);  // Searches from current scope outwards.
};
```

### 4.6 Layer 6: Code Generation (`codegen.hpp`)
**Target:** C89
**Register Strategy:** N/A (Handled by C compiler)

**Special Implementation Details:**
1. **Slices (`[]T`):** Mapped to a C struct `{ T* ptr, size_t len }`
2. **Error Unions (`!T`):** Mapped to a C struct `{ union { T payload; int err; } data; bool is_error; }`
3. **Defer Implementation:**
   * When generating code for a `{ block }`:
     1. Push `defer` nodes into a vector `defers` during parsing
     2. Emit block body code
     3. At scope exit (`}` or `return`), iterate `defers` in **reverse order** and emit their C code

### 4.7 Layer 7: PE Backend (`pe_builder.hpp`)
**Goal:** Direct `.exe` generation (No `LINK.EXE` needed for Stage 2)
* **Headers:** `IMAGE_DOS_HEADER`, `IMAGE_NT_HEADERS`
* **Sections:** `.text` (Code), `.data` (Globals), `.idata` (Imports)
* **Imports:** Manually synthesize Import Address Table (IAT) for `kernel32.dll` (`ExitProcess`, `WriteFile`) so the OS loader works
* **Alignment:** 0x200 (File) / 0x1000 (Virtual)

**PE Builder Implementation:**
```cpp
class PEBuilder {
    // DOS Stub, PE Header, Optional Header
    struct PEHeader pe_header;
    // Sections (.text, .data, .rdata, .idata)
    std::vector<uint8_t> text_section;
    std::vector<uint8_t> data_section;
    std::vector<uint8_t> import_section; // For Kernel32.dll calls
public:
    void addCode(const void* data, size_t len);
    void addData(const void* data, size_t len);
    void addImport(const char* dll, const char* func);
    void writeToFile(const char* filename);
};
```

## 5. The "Zig Subset" Language Specification
This is the restricted version of Zig this compiler will support.

**Grammar:**
```ebnf
program      ::= (fn_decl | var_decl)*
fn_decl      ::= 'fn' IDENT '(' param_list ')' type_expr block
var_decl     ::= ('var'|'const') IDENT ':' type_expr '=' expr ';'
statement    ::= block | if_stmt | while_stmt | defer_stmt | return_stmt | expr ';'
defer_stmt   ::= 'defer' statement
slice_expr   ::= '[' ']' type_expr
```

**Features explicitly EXCLUDED in Phase 1:**
* Async/Await
* Closures/Captures
* Complex Comptime (only basic integer math allowed)
* SIMD Vectors

**Defer Statement Semantics:**
```zig
{
    var x = alloc(10);
    defer free(x); // Must execute on scope exit
    process(x);
}
```
* Defer statements execute in reverse order of declaration
* They execute on all paths out of scope (normal exit, return, or error)
* They cannot capture variables that are not in scope

## 6. Compile-Time Evaluation (`comptime.hpp`)
**Supported Operations:**
- Integer arithmetic: +, -, *, /, %, bitwise ops
- Boolean logic: and, or, !
- Comparisons: ==, !=, <, >, <=, >=
- Array length calculation
- Basic string concatenation
- Conditional compilation flags

**Unsupported Operations:**
- File I/O during compilation
- Network operations
- Complex data structures
- Runtime code generation

**Comptime Context Structure:**
```cpp
struct ComptimeContext {
    struct Variable {
        const char* name;
        Value value;
        Type* type;
    };
    std::vector<Variable> variables;
    ArenaAllocator* allocator;
    size_t memory_limit;  // Default: 64KB
    Value evaluateExpression(ASTNode* expr);
    bool isComptimeConstant(ASTNode* expr);
};
```

## 7. Performance Optimization Strategies
### Critical Performance Metrics
- **Parse Speed:** Target < 1ms per 100 lines
- **Type Check:** Target < 2ms per 100 lines
- **Code Gen:** Target < 3ms per 100 lines
- **Memory Usage:** Peak < 16MB per 1000-line file

### Optimization Techniques
#### String Interning
```cpp
// Instead of copying strings everywhere
char* name1 = strdup("variable");  // 8 bytes allocated
char* name2 = strdup("variable");  // Another 8 bytes
// Use interned strings
const char* name1 = interner.intern("variable");  // 1 allocation ever
const char* name2 = interner.intern("variable");  // Returns same pointer
```

#### Arena Allocation
```cpp
// Instead of individual allocations
ASTNode* node1 = new ASTNode();  // Heap allocation
ASTNode* node2 = new ASTNode();  // Another allocation
// Use arena
ArenaAllocator arena(1024 * 1024);  // 1MB buffer
ASTNode* node1 = arena.alloc<ASTNode>();  // Fast bump-pointer alloc
ASTNode* node2 = arena.alloc<ASTNode>();  // Even faster
arena.reset();  // Free all at once
```

#### Lookup Tables
```cpp
// Keyword recognition
static const struct { const char* keyword; TokenType type; } KEYWORDS[] = {
    {"fn", TOKEN_FN}, {"var", TOKEN_VAR}, {"const", TOKEN_CONST},
    {"if", TOKEN_IF}, {"else", TOKEN_ELSE}, {"while", TOKEN_WHILE}
};
TokenType getKeywordType(const char* word) {
    for (auto& kw : KEYWORDS) {
        if (strcmp(kw.keyword, word) == 0) return kw.type;
    }
    return TOKEN_IDENTIFIER;
}
```

## 8. Testing Strategy
### Unit Test Framework
```cpp
// test_framework.h
#define ASSERT_TRUE(condition) do { \
    if (!(condition)) { \
        printf("FAIL: %s at %s:%d\n", #condition, __FILE__, __LINE__); \
        return 1; \
    } \
} while(0)
#define ASSERT_EQ(expected, actual) do { \
    if ((expected) != (actual)) { \
        printf("FAIL: %s != %s at %s:%d\n", #expected, #actual, __FILE__, __LINE__); \
        return 1; \
    } \
} while(0)
```

### Defer Order Test
**Input**:
```zig
fn main() -> i32 {
    var x: i32 = 0;
    defer x = x + 1;
    defer x = x * 2;
    x = 10;
    return x;
}
```
**Expected Behavior**:
1. `x = 10`
2. `x = x * 2` (20)
3. `x = x + 1` (21)
4. Return 21.

### Integration Test Suite
```batch
@echo off
set TEST_DIR=tests/
set PASS_COUNT=0
set FAIL_COUNT=0
for %%f in (%TEST_DIR%*.zig) do (
    echo Testing %%f...
    zigc.exe %%f -o test_output.exe
    if errorlevel 1 (
        echo FAIL: %%f
        set /a FAIL_COUNT+=1
    ) else (
        test_output.exe
        if errorlevel 1 (
            echo FAIL: %%f (runtime)
            set /a FAIL_COUNT+=1
        ) else (
            echo PASS: %%f
            set /a PASS_COUNT+=1
        )
    )
)
echo Results: %PASS_COUNT% passed, %FAIL_COUNT% failed
```

## 9. Implementation Roadmap

### Phase 0: The Bootstrap (C++98)
* **Objective:** Build `zig0.exe` using MSVC 6.0
* **Codebase:** `src/bootstrap/*.cpp`
* **Dependencies:** `common.hpp` (MSVC compat), `pe_builder.cpp`
* **Result:** A compiler that can read `stage1.zig` and emit `stage1.exe`

### Phase 1: The Cross-Compiler (Zig)
* **Objective:** Rewrite the compiler in Zig (`lib/compiler.zig`)
* **Process:**
  1. `zig0.exe` compiles `lib/compiler.zig` -> `zig1.exe`
  2. `zig1.exe` is now a native Windows binary generated by our own logic

### Phase 2: Self-Hosting
* **Objective:** `zig1.exe` compiles `lib/compiler.zig` -> `zig2.exe`
* **Verification:** `fc /b zig1.exe zig2.exe`. If they are identical, the compiler is self-hosting and deterministic

## 10. Detailed Implementation Checklist

### Week 1: MSVC 6.0 Env Setup
- [x] Set up Windows 98 VM with MSVC 6.0
- [ ] Create `PEBuilder` skeleton (generating a valid empty .exe)
- [x] Implement compatibility layer (`common.hpp`)

### Week 2: Memory & Lexer
- [x] Implement Arena Allocator with alignment support
- [x] Create String Interning system
- [x] Implement lexer class with token definitions
  - [x] Define Token struct and TokenType enum
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

### Week 3: Parser & AST
- [ ] Implement recursive descent parser
- [ ] Handle expressions with precedence
- [ ] Parse function declarations
- [ ] Implement defer statement handling

### Week 4: Type System
- [ ] Define type representation (Primitives, Pointers, Slices, Error Unions)
- [ ] Implement type compatibility rules
- [ ] Create symbol table system

### Week 5: Basic Code Generation (C89)
- [ ] Design C89 emitter
- [ ] Implement C89 code generation for functions
- [ ] Generate code for variable declarations
- [ ] Handle basic expressions

### Week 6: Advanced Code Generation
- [ ] Implement defer statement code generation
- [ ] Handle slices and error unions
- [ ] Add Win32 imports for kernel32.dll
- [ ] Test generated code correctness

### Week 7: Bootstrap Stage 0 -> Stage 1
- [ ] Write minimal Zig compiler in C++
- [ ] Test compilation of stage1.zig
- [ ] Verify generated executable works

### Week 8: Self-Hosting Verification
- [ ] Complete compiler implementation in Zig subset
- [ ] Test self-compilation cycle (Stage 1 -> Stage 2)
- [ ] Verify bootstrap integrity with binary comparison

## 11. Specific Win9x Constraints
* **Filename lengths:** Keep source filenames < 8.3 characters if possible to avoid VFAT issues in pure DOS mode
* **Stack Size:** Default stack is 1MB. Recursion depth is limited
* **Memory Fragmentation:** Use arena allocators to minimize fragmentation
* **Error Reporting:** No stack traces on Win9x; errors must be clear and contextual

## 12. Directory Structure
```text
/
├── src/
│   ├── bootstrap/      # C++98 Source for Phase 0
│   │   ├── main.cpp
│   │   ├── lexer.cpp
│   │   ├── parser.cpp
│   │   ├── typecheck.cpp
│   │   ├── codegen.cpp
│   │   └── pe_builder.cpp
│   └── include/
│       ├── common.hpp  # MSVC compat hacks
│       ├── memory.hpp
│       ├── string_interner.hpp
│       ├── source_manager.hpp
│       └── error_handler.hpp
├── lib/
│   └── compiler.zig    # Stage 1 source code (Zig subset)
├── tests/
│   ├── defer.zig       # Test: Defer ordering
│   ├── slice.zig       # Test: Slice ABI
│   └── error_union.zig # Test: Error handling
├── build.bat           # Win32 batch script for building
├── test.bat            # Test execution script
└── DESIGN.md           # This document
```

## 13. Compatibility Layer (`common.hpp`)
```cpp
#ifndef COMMON_HPP
#define COMMON_HPP
// MSVC 6.0 specific integer handling
#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
    typedef int i32;
    typedef unsigned int u32;
    typedef short i16;
    typedef unsigned short u16;
    typedef signed char i8;
    typedef unsigned char u8;
#else
    #include <stdint.h>
    typedef int64_t i64;
    typedef uint64_t u64;
    // ... others ...
#endif
// Boolean support for pre-standard C++
#ifdef _MSC_VER
    #ifndef bool
    typedef int bool;
    #define true 1
    #define false 0
    #endif
#endif
#endif // COMMON_HPP
```