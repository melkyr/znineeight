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
* **Specific MSVC 6.0 Hacks:**
  * Use `__int64` instead of `long long`
  * Define `bool`, `true`, `false` manually if missing

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
* **Alignment:** Support aligned allocations for SIMD data (future extension)

### 3.2 String Interning (`string_interner.hpp`)
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

### 4.1 Layer 1: Lexer (`lexer.hpp`)
* **Input:** Source code text
* **Output:** Stream of `Token` structs
* **Token Definition (`TokenType`):** The core of the lexer is the `TokenType` enum, which defines all possible tokens. It is organized into logical groups for clarity.
```cpp
enum TokenType {
    // Control Tokens
    TOKEN_EOF,

    // Literals
    TOKEN_IDENTIFIER,
    TOKEN_INTEGER_LITERAL,
    TOKEN_STRING_LITERAL,

    // Keywords
    TOKEN_FN,
    TOKEN_VAR,
    TOKEN_CONST,
    TOKEN_IF,
    TOKEN_ELSE,
    TOKEN_WHILE,
    TOKEN_RETURN,
    TOKEN_DEFER,

    // Operators
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    TOKEN_PERCENT,
    TOKEN_EQUAL,            // =
    TOKEN_EQUAL_EQUAL,      // ==
    TOKEN_BANG,             // !
    TOKEN_BANG_EQUAL,       // !=
    TOKEN_LESS,             // <
    TOKEN_LESS_EQUAL,       // <=
    TOKEN_GREATER,          // >
    TOKEN_GREATER_EQUAL,    // >=

    // Delimiters
    TOKEN_LPAREN,           // (
    TOKEN_RPAREN,           // )
    TOKEN_LBRACE,           // {
    TOKEN_RBRACE,           // }
    TOKEN_LBRACKET,         // [
    TOKEN_RBRACKET,         // ]
    TOKEN_SEMICOLON,        // ;
    TOKEN_COLON,            // :
};
```
* **Value Storage:** Unions for `i64`, `double`, and `char*` (interned string)
* **Token Precedence Table:**
```cpp
const int PRECEDENCE_TABLE[] = {
    [OPERATOR_ASSIGN] = 1,
    [OPERATOR_OR] = 2,
    [OPERATOR_AND] = 3,
    [OPERATOR_EQUAL, OPERATOR_NOT_EQUAL] = 4,
    [OPERATOR_LESS, OPERATOR_GREATER, OPERATOR_LESS_EQUAL, OPERATOR_GREATER_EQUAL] = 5,
    [OPERATOR_PLUS, OPERATOR_MINUS] = 6,
    [OPERATOR_STAR, OPERATOR_SLASH, OPERATOR_PERCENT] = 7,
    [OPERATOR_BANG] = 8  // Unary operators highest
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

### 4.3 Layer 3: Type System (`type_system.hpp`)
**Supported Types (Phase 1):**
* **Primitives:** `i8`-`i64`, `u8`-`u64`, `bool`, `f32`, `f64`
* **Pointers:** `*T` (Single level initially)
* **Slices:** `[]T` (Struct of `{ ptr, len }`)
* **Error Unions:** `!T` (Enum/Int for error + Value)

**Type Representation:**
```cpp
enum TypeKind {
    TYPE_VOID, TYPE_BOOL,
    TYPE_I8, TYPE_I16, TYPE_I32, TYPE_I64,
    TYPE_U8, TYPE_U16, TYPE_U32, TYPE_U64,
    TYPE_POINTER,
    TYPE_ARRAY,
    TYPE_SLICE,         // NEW: []T
    TYPE_ERROR_UNION    // NEW: !T
};
struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;
    union {
        struct { Type* base; } pointer;
        struct { Type* elem; size_t count; } array;
        struct { Type* elem; } slice; // Implicitly { ptr, len }
        struct { Type* payload; } error_union;
    };
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

### 4.4 Layer 4: Symbol Table (`symbol_table.hpp`)
```cpp
struct Symbol {
    enum Kind { VARIABLE, FUNCTION, TYPE } kind;
    const char* name;
    Type* type;
    uint32_t address_offset;  // For variables
    void* definition;         // Pointer to AST node
};
class SymbolTable {
    std::vector<Symbol> symbols;
    SymbolTable* parent_scope;
public:
    Symbol* lookup(const char* name);
    void insert(Symbol& sym);
    void pushScope();
    void popScope();
};
```

### 4.5 Layer 5: Code Generation (`codegen.hpp`)
**Target:** 32-bit x86 Assembly (Intel Syntax)
**Register Strategy:** Linear scan allocation
* **Volatile Registers:** `EAX`, `ECX`, `EDX` (Caller-save)
* **Non-Volatile:** `EBX`, `ESI`, `EDI`, `EBP` (Callee-save)

**Register Allocator Design:**
```cpp
enum Register {
    EAX = 0, ECX, EDX, EBX, ESP, EBP, ESI, EDI
};
class RegisterAllocator {
    bool allocated[8];      // Track register usage
    int spill_count;        // Counter for temporary variables
public:
    Register allocateRegister(Type* type);
    void freeRegister(Register reg);
    void spillRegister(Register reg);  // Move to stack
};
```

**Special Implementation Details:**
1. **Slices (`[]T`):** Passed on the stack as two 32-bit words (`ptr`, `len`)
   * `[EBP+12]` = Length
   * `[EBP+8]` = Pointer
2. **Error Unions (`!T`):**
   * **Success:** `EDX = 0`, `EAX = Result`
   * **Error:** `EDX = ErrorCode`, `EAX = Undefined`
3. **Defer Implementation:**
   * When generating code for a `{ block }`:
     1. Push `defer` nodes into a vector `defers` during parsing
     2. Emit block body code
     3. At scope exit (`}` or `return`), iterate `defers` in **reverse order** and emit their assembly

**Assembly Generation Patterns:**
```asm
; Function prologue
push ebp
mov ebp, esp
sub esp, local_var_size
; Function epilogue  
mov esp, ebp
pop ebp
ret
; Variable access
mov eax, [ebp-4]    ; Load local variable at offset -4
mov [ebp-8], ebx    ; Store register to local variable
```

### 4.6 Layer 6: PE Backend (`pe_builder.hpp`)
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
- [ ] Set up Windows 98 VM with MSVC 6.0
- [ ] Create `PEBuilder` skeleton (generating a valid empty .exe)
- [ ] Implement compatibility layer (`common.hpp`)

### Week 2: Memory & Lexer
- [ ] Implement Arena Allocator with alignment support
- [ ] Create String Interning system
- [ ] Implement lexer class with token definitions

### Week 3: Parser & AST
- [ ] Implement recursive descent parser
- [ ] Handle expressions with precedence
- [ ] Parse function declarations
- [ ] Implement defer statement handling

### Week 4: Type System
- [ ] Define type representation (Primitives, Pointers, Slices, Error Unions)
- [ ] Implement type compatibility rules
- [ ] Create symbol table system

### Week 5: Basic Code Generation
- [ ] Design register allocation system
- [ ] Implement x86 assembly emitter
- [ ] Generate function prologues/epilogues
- [ ] Handle variable access patterns

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

### 4.1 Layer 1: Lexer (`lexer.hpp`)
* **Input:** Source code text
* **Output:** Stream of `Token` structs
* **Key Tokens:** `fn`, `var`, `defer` (new), `[` `]` (slices)
* **Value Storage:** Unions for `int64`, `double`, and `char*` (interned string)
* **Token Precedence Table:**
```cpp
const int PRECEDENCE_TABLE[] = {
    [OPERATOR_ASSIGN] = 1,
    [OPERATOR_OR] = 2,
    [OPERATOR_AND] = 3,
    [OPERATOR_EQUAL, OPERATOR_NOT_EQUAL] = 4,
    [OPERATOR_LESS, OPERATOR_GREATER, OPERATOR_LESS_EQUAL, OPERATOR_GREATER_EQUAL] = 5,
    [OPERATOR_PLUS, OPERATOR_MINUS] = 6,
    [OPERATOR_STAR, OPERATOR_SLASH, OPERATOR_PERCENT] = 7,
    [OPERATOR_BANG] = 8  // Unary operators highest
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

### 4.3 Layer 3: Type System (`type_system.hpp`)
**Supported Types (Phase 1):**
* **Primitives:** `i8`-`i64`, `u8`-`u64`, `bool`, `f32`, `f64`
* **Pointers:** `*T` (Single level initially)
* **Slices:** `[]T` (Struct of `{ ptr, len }`)
* **Error Unions:** `!T` (Enum/Int for error + Value)

**Type Representation:**
```cpp
enum TypeKind {
    TYPE_VOID, TYPE_BOOL,
    TYPE_I8, TYPE_I16, TYPE_I32, TYPE_I64,
    TYPE_U8, TYPE_U16, TYPE_U32, TYPE_U64,
    TYPE_POINTER,
    TYPE_ARRAY,
    TYPE_SLICE,         // NEW: []T
    TYPE_ERROR_UNION    // NEW: !T
};
struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;
    union {
        struct { Type* base; } pointer;
        struct { Type* elem; size_t count; } array;
        struct { Type* elem; } slice; // Implicitly { ptr, len }
        struct { Type* payload; } error_union;
    };
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

### 4.4 Layer 4: Symbol Table (`symbol_table.hpp`)
```cpp
struct Symbol {
    enum Kind { VARIABLE, FUNCTION, TYPE } kind;
    const char* name;
    Type* type;
    uint32_t address_offset;  // For variables
    void* definition;         // Pointer to AST node
};
class SymbolTable {
    std::vector<Symbol> symbols;
    SymbolTable* parent_scope;
public:
    Symbol* lookup(const char* name);
    void insert(Symbol& sym);
    void pushScope();
    void popScope();
};
```

### 4.5 Layer 5: Code Generation (`codegen.hpp`)
**Target:** 32-bit x86 Assembly (Intel Syntax)
**Register Strategy:** Linear scan allocation
* **Volatile Registers:** `EAX`, `ECX`, `EDX` (Caller-save)
* **Non-Volatile:** `EBX`, `ESI`, `EDI`, `EBP` (Callee-save)

**Register Allocator Design:**
```cpp
enum Register {
    EAX = 0, ECX, EDX, EBX, ESP, EBP, ESI, EDI
};
class RegisterAllocator {
    bool allocated[8];      // Track register usage
    int spill_count;        // Counter for temporary variables
public:
    Register allocateRegister(Type* type);
    void freeRegister(Register reg);
    void spillRegister(Register reg);  // Move to stack
};
```

**Special Implementation Details:**
1. **Slices (`[]T`):** Passed on the stack as two 32-bit words (`ptr`, `len`)
   * `[EBP+12]` = Length
   * `[EBP+8]` = Pointer
2. **Error Unions (`!T`):**
   * **Success:** `EDX = 0`, `EAX = Result`
   * **Error:** `EDX = ErrorCode`, `EAX = Undefined`
3. **Defer Implementation:**
   * When generating code for a `{ block }`:
     1. Push `defer` nodes into a vector `defers` during parsing
     2. Emit block body code
     3. At scope exit (`}` or `return`), iterate `defers` in **reverse order** and emit their assembly

**Assembly Generation Patterns:**
```asm
; Function prologue
push ebp
mov ebp, esp
sub esp, local_var_size
; Function epilogue
mov esp, ebp
pop ebp
ret
; Variable access
mov eax, [ebp-4]    ; Load local variable at offset -4
mov [ebp-8], ebx    ; Store register to local variable
```

### 4.6 Layer 6: PE Backend (`pe_builder.hpp`)
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
for %%f in (%Test_DIR%*.zig) do (
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
- [ ] Implement lexer class with token definitions

### Week 3: Parser & AST
- [ ] Implement recursive descent parser
- [ ] Handle expressions with precedence
- [ ] Parse function declarations
- [ ] Implement defer statement handling

### Week 4: Type System
- [ ] Define type representation (Primitives, Pointers, Slices, Error Unions)
- [ ] Implement type compatibility rules
- [ ] Create symbol table system

### Week 5: Basic Code Generation
- [ ] Design register allocation system
- [ ] Implement x86 assembly emitter
- [ ] Generate function prologues/epilogues
- [ ] Handle variable access patterns

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