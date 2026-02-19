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

### 2.1 Target Platform (Bootstrap)
The bootstrap compiler assumes a **32-bit little-endian** platform with the following characteristics:

| Type | Size (bytes) | Alignment |
|------|--------------|-----------|
| `usize` / `isize` | 4 | 4 |
| Pointers (`*T`) | 4 | 4 |
| `i8` / `u8` | 1 | 1 |
| `i16` / `u16` | 2 | 2 |
| `i32` / `u32` | 4 | 4 |
| `i64` / `u64` | 8 | 8 |
| `f32` | 4 | 4 |
| `f64` | 8 | 8 |
| `bool` | 4 | 4 (C89 `int`) |

This matches the target Win32/x86 environment of the late 90s.

* **Language Standard:** C++98 (max) for bootstrap; limited C++ STL usage due to fragmentation
* **Memory Limit:** < 16MB peak usage preferred. No smart pointers or heavy templates
* **Dependencies:** Win32 API (`kernel32.dll`) only for Windows target. POSIX/Standard C for Linux development.
* **Platform Abstraction Layer (PAL):** To ensure portability and strict compliance, all system calls (memory allocation, file I/O, console output, process termination) MUST go through the PAL (`platform.hpp`).
* **C++ Standard Library Usage Policy:**
  * **Allowed:** Headers that are generally implemented by the compiler and have no external runtime library dependencies or hidden memory allocations. This includes headers like `<new>` (for placement new), `<cstddef>` (for `size_t`), `<cassert>` (for `assert`), and `<climits>`.
  * **Forbidden:** Headers that depend on a C/C++ runtime library (like `msvcrt.dll` beyond `kernel32.dll`) or perform dynamic memory allocation. This includes headers like `<cstdio>` (`fprintf`), `<cstdlib>` (`malloc`), `<iostream>`, `<string>` (`std::string`), and `<vector>` (`std::vector`).
  * **Exceptions:** `<cstdlib>` is allowed *only* for `strtol`/`strtod`. Process termination MUST use `plat_abort()` from `platform.hpp`.
* **Specific MSVC 6.0 Hacks:**
  * Use `__int64` instead of `long long`
  * Define `bool`, `true`, `false` manually if missing
* **Dynamic Memory:** Standard C dynamic memory allocation functions (e.g., `malloc`, `free`) are forbidden. The compiler will produce a fatal error if calls to these functions are detected.

## 3. Architecture & Memory Strategy
The compiler uses a layered architecture relying heavily on "Arena Allocation" to avoid `malloc`/`free` overhead on slow 90s allocators.

### 3.1 Memory Management

The RetroZig project utilizes arena-based allocation for both the compiler itself (C++) and the generated programs (C89). This strategy ensures high performance on legacy hardware by minimizing fragmentation and the overhead of individual `malloc`/`free` calls.

#### 3.1.1 Bootstrap Compiler Memory (`memory.hpp`)
**Concept:** A chunked, region-based allocator that frees all memory at once. It minimizes physical memory waste by using lazy allocation.

```cpp
class ArenaAllocator {
    struct Chunk {
        Chunk* next;
        size_t capacity;
        size_t offset;
    };
    Chunk* head;            // Linked list of allocated chunks
    size_t total_cap;       // Maximum allowed total capacity (e.g., 16MB)
public:
    void* alloc(size_t size); // Allocs in current chunk or creates new one
    void* alloc_aligned(size_t size, size_t align);
    void reset();           // Frees all chunks from OS
};
```
* **Usage:** AST Nodes, Types, and Symbols are allocated here. A transient `token_arena` is used during parsing and reset immediately after to free memory early.
* **Alignment:** The `alloc()` method guarantees 8-byte alignment for all allocations.
* **Safety:** The allocator uses overflow-safe checks in both `alloc` and `alloc_aligned` to prevent memory corruption when the arena is full. The `DynamicArray` implementation is also safe for non-POD types, as it uses copy construction with placement new instead of `memcpy` or assignment during reallocation.

#### 3.1.2 Runtime Memory Management (`zig_runtime.h`, `zig_runtime.c`)
**Concept:** A C89 implementation of the linked-block arena allocator, designed to be available across all generated modules. It allows Zig programs to manage their own memory efficiently using multiple independent arenas.

```c
typedef struct Arena Arena;

Arena* arena_create(usize initial_capacity);
void* arena_alloc(Arena* a, usize size);
void arena_reset(Arena* a);
void arena_destroy(Arena* a);

extern Arena* zig_default_arena;
```

* **Implementation:** Uses Win32 `HeapAlloc` (from `kernel32.dll`) to allocate fixed-size blocks. Each block is chained in a linked list to ensure that existing pointers remain valid (non-relocatable) as the arena grows.
* **Platform Abstraction:** Provides a fallback to standard C `malloc`/`free` for non-Windows environments to facilitate testing and development.
* **Global Arena:** A default `zig_default_arena` is provided for simple programs and backward compatibility with Milestone 4 components.

### 3.2 Utility Functions (`utils.hpp`) & Platform Utilities (`platform.hpp`)
**Purpose:** Provide safe string and numeric utilities that avoid modern C++ dependencies and satisfy strict environment constraints (no `msvcrt.dll`/`sprintf` in core bootstrap).

* **`arena_safe_append(char*& dest, size_t& remaining, const char* src)`**: Appends a string to a buffer while tracking remaining space and ensuring null-termination (even on truncation).
* **`plat_i64_to_string(i64 value, char* buffer, size_t buffer_size)`**: Converts an `i64` to a string without using `sprintf`. Part of the Platform Abstraction Layer.
* **`plat_u64_to_string(u64 value, char* buffer, size_t buffer_size)`**: Converts a `u64` to a string.
* **`plat_float_to_string(double value, char* buffer, size_t buffer_size)`**: Converts a `double` to a string using scientific or fixed-point notation.
* **`plat_abort()`**: Terminates the process immediately without calling destructors or performing CRT cleanup. Uses `ExitProcess(1)` on Windows.
* **`join_paths(const char* dir, const char* rel_path, ArenaAllocator& arena)`**: Combines a directory and a relative path into a normalized path, handling both Windows and POSIX separators.
* **`get_directory(const char* filepath, ArenaAllocator& arena)`**: Extracts the directory component from a file path.

### 3.3 String Interning (`string_interner.hpp`)
**Concept:** Deduplicate identifiers. If "varname" appears 50 times, store it once and compare pointers.
* **Structure:** Hash table (1024 buckets) with chaining
* **Hashing:** FNV-1a or similar simple hash
* **Performance:** Reduces memory usage and speeds up identifier comparisons

### 3.4 Catalogues & Feature Tracking

All catalogues (GenericCatalogue, ErrorSetCatalogue, ErrorFunctionCatalogue) follow the Arena Allocation Pattern:
- **Lifetime Safety**: All catalogue structures are allocated from the `CompilationUnit`'s arena.
- **No Manual Management**: No `malloc`/`free` or `new`/`delete` (except placement new) are used during analysis.
- **String Interning**: Feature names and identifiers are stored as interned strings for efficiency and lifetime stability.

### 3.5 Source Management (source_manager.hpp)
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
    1.  **Lexing & Parsing:** Produces the AST for the entry module.
- **Import Resolution (Task 214 & 216):** Recursively discovers, loads, and parses all imported Zig modules. This phase includes circular dependency detection and path resolution.
    - **Search Order:**
        1.  Directory of the importing file.
        2.  Directories specified via `-I` command-line flags (searched in the order they were provided).
        3.  Default `lib/` directory located relative to the compiler executable.
    - **Implementation:** Uses normalized, interned filenames for consistent module caching and `plat_file_exists` to validate paths before loading.
- **Modular Semantic Analysis (Task 215):** Compilation passes are executed unit-wide but with module-level granularity:
    - **Context Switching:** The `CompilationUnit` iterates through all loaded modules for each pass (Type Checking, C89 Validation, Static Analyzers).
    - **Isolated Context:** Each module maintains its own `SymbolTable` and feature catalogues (Generic, ErrorSet, etc.) to prevent cross-module state leakage while allowing qualified symbol resolution.
    3.  **Pass 0: Type Checking (Permissive):** Resolves all types across all loaded modules, including non-C89 types (e.g., error unions, optionals, multi-level pointers, `isize`/`usize`), to enable accurate semantic analysis. This permissive approach ensures that the TypeChecker remains focused on understanding the language, while leaving feature restriction to later passes.
    3.  **Pass 1: C89 Feature Validation (Rejection):** Strictly rejects non-C89 features and bootstrap-specific limitations using the resolved semantic information from Pass 0. This is where descriptive error messages for unsupported features are reported.
    4.  **Pass 2: Lifetime Analysis:** Detects dangling pointers across all modules.
    5.  **Pass 3: Null Pointer Analysis:** Detects potential null dereferences.
    6.  **Pass 4: Double Free Detection (Task 127-129):** Detects arena double frees and leaks, tracks allocation/deallocation sites, and handles ownership transfers.
    7.  **Code Generation:** Emits target code (C89). All code generation MUST avoid standard C library functions like `sprintf` and instead use the `plat_*_to_string` utilities to ensure compatibility with the `kernel32.dll`-only target.
- **Parser Creation:** Provides a factory method, `createParser()`, which encapsulates the entire process of lexing a source file and preparing a `Parser` instance for syntactic analysis. It uses a `TokenSupplier` internally, which guarantees that the token stream passed to the parser has a stable memory address that will not change for the lifetime of the `CompilationUnit`'s arena. This prevents dangling pointer errors.

#### 4.0.1 Non-C89 Feature Detection Strategy
To maintain strict compatibility with C89, the compiler employs a multi-layered detection and rejection strategy for modern Zig features:
1.  **Syntactic Detection (Parser):** The parser is equipped to recognize modern Zig syntax (e.g., error sets, error unions, optionals, `@import`, `comptime` parameters) for the sole purpose of detection and cataloguing.
2.  **Feature Cataloguing:** Detected features like error sets and generic function instantiations are logged into specialized structures (e.g., `ErrorSetCatalogue`, `GenericCatalogue`, `ErrorFunctionCatalogue`) during parsing and semantic analysis. This provides a comprehensive overview of non-C89 features used in the source code for documentation and analysis purposes.
3. **Formal Rejection (C89FeatureValidator):** The `C89FeatureValidator` pass traverses the AST and issues fatal errors for any modern Zig constructs, including explicit and implicit generic function calls, error-returning functions, and `try` expressions.

#### 4.0.2 Error Handling Detection (Tasks 143-144)
Modern Zig error handling features are detected and catalogued for documentation. While these features are rejected in the bootstrap phase to maintain C89 compatibility, they are tracked to support a future mapping strategy.
- **Error Sets**: Catalogued in `ErrorSetCatalogue` during parsing.
- **Error-Returning Functions**: Catalogued in `ErrorFunctionCatalogue` during validation.
- **Try Expressions**: Catalogued in `TryExpressionCatalogue` during validation, including usage context (e.g., assignment, return) and nesting depth.
- **Catch Expressions**: Catalogued in `CatchExpressionCatalogue` during validation, including chaining information and error capture.
- **Orelse Expressions**: Catalogued in `OrelseExpressionCatalogue` during validation.
- **Success Value Extraction**: Analyzed and catalogued in `ExtractionAnalysisCatalogue` during validation. Decisions are made between `EXTRACTION_STACK`, `EXTRACTION_ARENA`, and `EXTRACTION_OUT_PARAM` based on MSVC 6.0 constraints (alignment, stack limits, and nesting depth).

For details on how these features will be mapped to C89 in Milestone 5, see [Bootstrap Type System & Semantic Analysis](Bootstrap_type_system_and_semantics.md) (Section 13).

#### 4.0.3 Compilation Pipeline Update (Task 142)
The compilation pipeline has been reordered to enable type-aware diagnostics:
1. **Pass 0: Type Checking**: Resolves all types, including non-C89 types like error unions.
2. **Pass 1: C89 Validation**: Rejects non-C89 features using resolved semantic information.

This change allows the validator to accurately detect error-returning functions even when they use type aliases for error sets.

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

### 4.3 Layer 3: Semantic Analysis & Static Analyzers (`type_checker.hpp`, `lifetime_analyzer.hpp`, `null_pointer_analyzer.hpp`, `double_free_analyzer.hpp`)

Semantic analysis is performed in several distinct, sequential passes after the AST is generated and the basic C89 feature validation is complete.

#### Pass 1: Type Checking
The `TypeChecker` resolves identifiers, verifies type compatibility for assignments and operations, and populates the `SymbolTable` with semantic metadata.

- **Symbol Flags:** Symbols are marked with flags like `SYMBOL_FLAG_LOCAL` (stack variables), `SYMBOL_FLAG_PARAM` (function parameters), and `SYMBOL_FLAG_GLOBAL` based on their declaration context.
- **Redefinition Check:** Ensures no two symbols share the same name in the same scope.

#### Pass 2: Lifetime Analysis (Task 125)
The `LifetimeAnalyzer` is a read-only pass that detects memory safety violations, specifically dangling pointers created by returning pointers to local variables or parameters from functions.

- **Provenance Tracking:** It tracks which pointers are assigned the addresses of local variables (e.g., `p = &x;`). It uses a `DynamicArray` to store `PointerAssignment` records for the current function scope.

#### Pass 3: Null Pointer Analysis (Task 126)
The `NullPointerAnalyzer` is a read-only pass that identifies potential null pointer dereferences and uninitialized pointer usage using flow-sensitive analysis.

- **Phase 1 (Infrastructure):** Implemented the core skeleton, visitor framework, and a robust, scoped state-tracking system.
- **Phase 2 (Basic Detection):** Implements detection for obvious null dereferences and uninitialized pointer usage.
- **Phase 3 (Conditionals & Flow):** Adds support for null guards in `if` statements and `while` loops, and implements state merging for branched control flow.
- **State Tracking:** Tracks pointer nullability states (`UNINIT`, `NULL`, `SAFE`, `MAYBE`) throughout function bodies and global declarations.
- **Scope Management & Branching:** Employs a stack-based `StateMap` system. When encountering a branch (e.g., an `if` block), the analyzer creates a copy of the current state. Modifications within branches are merged back using conservative rules:
    - `NULL` + `SAFE` = `MAYBE`
    - `SAFE` + `SAFE` = `SAFE`
    - `NULL` + `NULL` = `NULL`
    - Anything + `MAYBE` = `MAYBE`
- **Null Guards:**
    - **If Statements:** Recognizes patterns like `if (p != null)`, `if (p == null)`, `if (p)`, and `if (!p)`. It refines the state of `p` within the `then` and `else` blocks accordingly.
    - **While Loops:** Recognizes `while (p != null)` and treats `p` as `SAFE` within the loop body. After the loop, variables modified within the loop are conservatively set to `MAYBE`.
- **Violation Detection:**
    - **Definite Null Dereference (`ERR_NULL_POINTER_DEREFERENCE` - 2004):** Reported when a pointer explicitly set to `null` or `0` is dereferenced.
    - **Uninitialized Pointer Warning (`WARN_UNINITIALIZED_POINTER` - 6001):** Reported when a pointer declared without an initializer is dereferenced before being assigned a value.
    - **Potential Null Dereference Warning (`WARN_POTENTIAL_NULL_DEREFERENCE` - 6002):** Reported when a pointer with an unknown state (e.g., from a function call or after a merge) is dereferenced.
- **Assignment Handling**: The analyzer tracks direct assignments (`p = q`), `null` assignments (`p = null`), and address-of assignments (`p = &x`). It correctly handles reassignments and persists state through linear and branched flow.

#### Pass 4: Double Free Detection (Tasks 127-130)
The `DoubleFreeAnalyzer` is a read-only pass that identifies potential double-free scenarios and memory leaks related to the project's `ArenaAllocator` interface (`arena_alloc` and `arena_free`).

- **Memory Efficiency (Task 130):** Uses a memory-efficient `AllocationStateMap` based on a linked list of **deltas**. This avoids deep-copying the entire state when forking for branches, reducing memory overhead to O(1) for forks and O(k) for merges (where k is the number of modified variables).
- **Allocation Tracking:** It tracks the state of pointers using the `AllocationState` enum (`AS_UNINITIALIZED`, `AS_ALLOCATED`, `AS_FREED`, `AS_RETURNED`, `AS_UNKNOWN`). A pointer is tracked if it is initialized or assigned the result of `arena_alloc`.
- **Double Free Detection:** Reports `ERR_DOUBLE_FREE` (2005) when `arena_free` is called on an already freed pointer. Tracks both the allocation site and the first deallocation site (including defer context) for detailed diagnostics.
- **Leak Detection:**
    - **Scope Exit:** Reports `WARN_MEMORY_LEAK` (6005) when an `AS_ALLOCATED` pointer goes out of scope without being freed or returned.
    - **Immediate Reassignment:** Reports a leak if an `AS_ALLOCATED` variable is reassigned to any other value (including `null` or a new allocation) before the original memory is freed.
- **Uninitialized Free:** Reports `WARN_FREE_UNALLOCATED` (6006) when `arena_free` is called on a pointer that was never assigned an allocation or has an unknown state.
- **Expression Support:** The analyzer recursively visits all Milestone 4 node types, including `switch`, `try`, `catch`, `orelse`, binary operations, and array accesses. It can detect `arena_alloc` calls even when wrapped in other expressions (e.g., `var p = try arena_alloc(100);`).
- **Defer & Errdefer:** Employs a LIFO queue to model deferred actions. At the end of a block or upon a `return` statement, deferred actions are "executed" in reverse order to update the allocation state of tracked pointers.
- **Control Flow Analysis (Task 130):** The analyzer is path-aware. It forks the allocation state at control flow branches (`if`, `switch`, `catch`, `orelse`) and merges them at join points. If states diverge (e.g., freed in one branch but not another), the variable transitions to `AS_UNKNOWN` to remain conservative.
- **Try & Loops:** The `try` keyword and loop bodies (`while`, `for`) introduce uncertainty. Tracked pointers transition to `AS_UNKNOWN` after a `try` or if modified within a loop.
- **Ownership Transfers (Task 129):** Conservatively assumes that passing a pointer to any function (other than `arena_free`) transfers ownership. Transferred pointers are no longer checked for leaks or double frees, but a specific warning (`WARN_TRANSFERRED_MEMORY`) is issued at scope exit to remind the developer that the receiver is now responsible for the memory.
- **Conservative Merging Strategy:** This analyzer prioritizes avoiding false positives (definite errors reported when no error is possible) by transitioning divergent states (e.g., freed on one path but not another) to `AS_UNKNOWN`. This effectively implements a "path-blind" effect at join points while maintaining path-sensitivity within branches.

### 4.4 Layer 4: Type System (`type_system.hpp`)

**Bootstrap Type Subset Philosophy:**
The bootstrap compiler (Stage 0) implements a strict subset of Zig types specifically chosen for their direct compatibility with C89 and the simplified memory model of the bootstrap environment.

**Supported Types (Bootstrap Phase):**
* **Primitives:** `i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `bool`, `f32`, `f64`, `void`.
* **Pointers:** `*T`, `[*]T`. Supports multi-level pointers (`**T`, etc.) and pointer arithmetic with `usize`/`u32` on `[*]T`.
* **Arrays:** `[N]T` (Constant size only).
* **Structs/Enums:** C-style declarations only.
* **Functions:** `fn(...) T` as function pointers.

**Explicitly Rejected Types (Bootstrap Phase):**
* **Slices:** `[]T` (Requires runtime support and complex ABI mapping).
* **Optionals:** `?T` (Rejected until Milestone 5 translation).
* **Error Unions:** `!T` (Rejected until Milestone 5 translation).

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
    TYPE_ISIZE, // Maps to int in C89 (32-bit)
    TYPE_USIZE, // Maps to unsigned int in C89 (32-bit)
    // Floating-Point Types
    TYPE_F32,
    TYPE_F64,
    // Complex Types
    TYPE_POINTER,
    TYPE_FUNCTION
};

struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;
    union {
        struct {
            Type* base;
            bool is_many;
        } pointer;
        struct {
            DynamicArray<Type*>* params;
            Type* return_type;
        } function;
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
* **Structs:** Supported with C89-compliant layout (aligned fields, trailing padding). Zig-specific features like methods and default values are rejected in the bootstrap phase.
2. **Error Unions (`!T`):** Mapped to a C struct `{ union { T payload; int err; } data; bool is_error; }`
3. **Defer Implementation:**
   * When generating code for a `{ block }`:
     1. Push `defer` nodes into a vector `defers` during parsing
     2. Emit block body code
     3. At scope exit (`}` or `return`), iterate `defers` in **reverse order** and emit their C code

### 4.7 Enum Semantics (C89 Compatibility)

#### Type Representation
Enums are represented as distinct nominal types with:
- Unique type identity per declaration
- Implicit conversion to integer types
- Compile-time constant values

#### C89 Mapping
Zig enums map directly to C89 enums:
```zig
// Zig source
const Color = enum(u8) {
    Red,
    Green,
    Blue,
};
```

```c
/* Generated C89 */
typedef unsigned char Color;
#define COLOR_RED 0
#define COLOR_GREEN 1
#define COLOR_BLUE 2
```

#### Member Access
Enum members use dot notation: `Color.Red`
Type checking ensures member exists in enum.

### 4.8 Layer 7: PE Backend (`pe_builder.hpp`)
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

## 5. The "Zig Subset" Language Specification (Milestone 4)
This is the restricted version of Zig the bootstrap compiler supports as of Milestone 4.

### 5.1 Supported Syntax & Features
*   **Variable Declarations**: `var` and `const` with explicit types or type inference from literals.
*   **Primitive Types**: `i8` through `i64`, `u8` through `u64`, `isize`, `usize`, `f32`, `f64`, `bool`, `void`.
*   **Pointers**: Single-level pointers `*T` and `*const T`. Many-item pointers `[*]T`. Supports multi-level pointers (`**T`, etc.).
*   **Address-of & Dereference**: Supports `&` for address-of and `ptr.*` for dereference.
*   **Pointer Arithmetic**: Supported on `[*]T` with `+`, `-`, and distance `ptr1 - ptr2`.
*   **Fixed-size Arrays**: `[N]T` with constant size. Supports indexing `arr[i]`.
*   **Structs**: Named structs via `const S = struct { ... };`. Supports initialization `S { .x = 1 }` and member access `s.x`.
*   **Enums**: Named enums via `const E = enum { ... };` or `enum(backing_type) { ... };`.
*   **Unions**: Named bare unions via `const U = union { ... };`.
*   **Functions**: Function declarations and calls with support for any number of parameters.
*   **Control Flow**:
    *   `if (cond) { ... } else { ... }` (Braced blocks required).
    *   `while (cond) { ... }` (Supports `break` and `continue`).
    *   `switch (expr) { ... }` (Basic support, typically mapped to comments in Milestone 4 mock emission).
    *   `for (iterable) |item| { ... }` (Basic support, typically mapped to comments in Milestone 4 mock emission).
*   **Defer**: `defer statement;` or `defer { ... }`.
*   **Expressions**: Arithmetic (`+`, `-`, `*`, `/`, `%`), Comparison (`==`, `!=`, `<`, `>`, `<=`, `>=`), Logical (`and`, `or`, `!`), and Parentheses.
*   **Built-ins (Compile-Time)**: Intrinsics evaluated at compile-time and replaced with constants:
    *   `@sizeOf(T)` -> `usize` literal
    *   `@alignOf(T)` -> `usize` literal
    *   `@offsetOf(T, "f")` -> `usize` literal
    *   Numeric casts (`@intCast`, `@floatCast`) when operands are constant.
*   **Built-ins (Codegen)**: Intrinsics mapped to C constructs or runtime helpers:
    *   `@ptrCast(T, v)` -> C-style cast `(T*)v`.
    *   `@intCast(T, v)`, `@floatCast(T, v)` -> C-style casts (for safe widening) or runtime checked conversion functions.

### 5.2 Runtime Safety & Panic Strategy (Milestone 5)
For operations that cannot be proven safe at compile-time (e.g., unsafe `@intCast`, array indexing with dynamic indices), the compiler will emit calls to runtime helper functions.
- **Panic Handler**: A panic handler `__bootstrap_panic(const char* msg)` is implemented as a `static` function in `zig_runtime.h`.
- **Checked Conversions**: Helper functions like `__bootstrap_i32_from_i64` are implemented in `zig_runtime.h` to perform bounds checks and call the panic handler on failure.
- **Historical Compatibility**: The panic handler uses `fputs` to `stderr` and then calls `abort()`, ensuring compatibility with 1998-era hardware and modern environments.
- **Debug Output**: A minimal `__bootstrap_print(const char* s)` is provided for debugging purposes, wrapping `fputs` to `stderr`.

### 5.3 Explicit Limitations & Rejections
To maintain C89 compatibility and compiler simplicity:
*   **No Slices**: `[]T` is strictly rejected.
*   **No Error Handling**: `!T`, `try`, `catch`, `orelse`, and `errdefer` are rejected (though catalogued for future use).
*   **No Generics**: `comptime` parameters, `anytype`, and `type` parameters/variables are rejected.
*   **No Anonymous Types**: Structs, enums, and unions must be named via `const` assignment.
*   **No Struct Methods**: Functions cannot be declared inside a struct.
*   **No Tagged Unions**: Only bare (untagged) unions are supported.
*   **No Variadic Functions**: Ellipsis `...` is not supported.
*   **No Generic Built-ins**: Most Zig built-ins and `@import` are rejected, except for the documented supported subset.
*   **No SIMD Vectors**: SIMD vector types and operations are not supported.
*   **No Closures/Captures**: Anonymous functions and closures with variable captures are not supported.
*   **No Async/Await**: Asynchronous programming constructs (`async`, `await`, `suspend`, `resume`) are not supported.
*   **Syntax**: All control flow blocks (`if`, `while`, `for`, `fn`) MUST use braces `{ ... }`.

### 5.3 C89 Mapping Decisions
*   **Boolean**: Mapped to `int` (1 for true, 0 for false).
*   **Integer 64-bit**: Mapped to `__int64` (and `unsigned __int64`) for MSVC 6.0 compatibility. Literals use MSVC-specific suffixes `i64` and `ui64` (see `docs/reference/c89_emission.md`).
*   **Null**: Mapped to `((void*)0)`.
*   **Strings**: String literals are mapped to `const char*`.
*   **Name Mangling**:
    *   Zig identifiers that are C89 keywords (e.g., `int`, `register`) are mangled (e.g., `z_int`).
    *   Identifiers exceeding 31 characters are truncated for MSVC 6.0.
    *   Enum members are mangled as `EnumName_MemberName`.
*   **Struct Initializers**: Zig named initializers are reordered to match C89 positional initialization.

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

The testing strategy is designed to handle the complexity of the compiler while respecting strict memory and performance constraints.

### Batch Testing Architecture
To avoid arena fragmentation and out-of-memory errors during large-scale test runs, the unit test suite is split into multiple independent "batches".
- **Single Translation Unit (STU) Strategy**: Each batch is compiled as a single translation unit that `#include`s the entire bootstrap core (`bootstrap_all.cpp`) and only the necessary test implementation files. This "dumb" compilation approach ensures maximum reliability by avoiding complex linking and ODR violations.
- **Isolation**: Each batch runs in its own process, ensuring a clean memory heap and arena.
- **Reliable Termination**: Test runners use `_exit()` (or `ExitProcess`) to terminate immediately after results are reported. This bypasses potentially unstable global destructor sequences, preventing exit-time segmentation faults.
- **Scalability**: New tests can be added to existing batches or new ones without increasing the memory footprint of a single run.
- **Verification**: A master script (`run_all_tests.sh`) orchestrates the sequential execution of all batches and aggregates results.
- **Cleanup**: By default, batch runner binaries are deleted after execution to maintain environment cleanliness. This can be disabled using the `--no-postclean` flag in the test scripts.

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

### 8.1 End-to-End Example (Milestone 6)
The ultimate verification of the bootstrap toolchain is the successful compilation and execution of a multi-module Zig program. This is demonstrated by the `EndToEnd_HelloWorld` test case.

**Example Modules:**
- `main.zig`: Imports `greetings.zig` and calls `sayHello()`.
- `greetings.zig`: Imports `std.zig` and calls `std.debug.print()`.
- `std.zig`: Mimics the Zig standard library namespace using module imports.

**Pipeline Flow:**
1. **Bootstrap Compiler (`zig0`)**: Parses Zig source, resolves symbols across modules, and validates C89 compatibility.
2. **CBackend**: Generates `.c` and `.h` files for each module.
3. **C Toolchain (`gcc`)**: Compiles the generated C code, linked with `zig_runtime.c`, into a native executable.
4. **Execution**: The resulting binary runs and produces output (e.g., "Hello, world!") via runtime helpers.

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

### Milestone 5: Code Generation (C89)
- [x] Task 189: Implement `C89Emitter` class skeleton with buffered file I/O
- [x] Task 190: Implement `CVariableAllocator` for C89-compliant local name management
- [x] Task 191: Generate integer literals
- [x] Task 192: Generate float literals
- [x] Task 193: Generate string literals
- [x] Task 194: Generate global variable declarations
- [x] Task 195: Generate local variable declarations (with two-pass block logic)
- [x] Task 196: Generate function definitions
- [x] Task 197: Binary operators (arithmetic, comparisons, logical)
- [x] Task 198: Unary operators
- [x] Task 199: Member access
- [x] Task 200: Array indexing
- [x] Task 201: if statement
- [x] Task 202: while loop
- [x] Task 203: return statement
- [x] Task 204: @ptrCast
- [x] Task 205: @intCast / @floatCast (runtime checked)
- [ ] Task 206: defer (placeholder)
- [x] Task 207: Integration tests with real C89 compiler

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
- [x] Implement recursive descent parser
- [x] Handle expressions with precedence
- [x] Parse function declarations
- [x] Implement defer statement handling

### Week 4: Type System
- [x] Define type representation (Primitives, Pointers, Slices, Error Unions)
- [x] Implement type compatibility rules
- [x] Create symbol table system

### Week 5: Basic Code Generation (C89)
- [x] Design C89 emitter (Mock emitter for Milestone 4)
- [ ] Implement full C89 code generation for functions
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

## 13. Code Generation Infrastructure (`codegen.hpp`, `c_variable_allocator.hpp`)
The compiler utilizes a buffered emission system and a robust variable name allocator to ensure valid C89 output.

### 13.1 CBackend
- **Orchestration**: Manages multiple `C89Emitter` instances for multi-file generation.
- **Module Mapping**: Generates one `.c` and one `.h` file per Zig module.
- **Master Entry Point**: If a `pub fn main` is present, generates a master `main.c` (or `master.c` if conflicted) that `#include`s all module implementation files, facilitating a Single Translation Unit (STU) build.
- **Build Scripts**: Automatically generates `build.bat` (MSVC) and `Makefile` (GCC) in the output directory.
- **Visibility**: Enforces Zig visibility rules by marking non-`pub` symbols as `static`.
- **Header Generation**: Public types and function prototypes are automatically exported to `.h` files with robust include guards.
- **Import Handling**: Translates Zig `@import` into C `#include` directives.

### 13.2 C89Emitter
- **Buffering**: 4KB stack-based buffer to minimize system call overhead.
- **Indentation**: Automatic indentation management (4 spaces).
- **Comments**: Standard C89 `/* ... */` comment emission.
- **Two-Pass Block Emission**: Collects local declarations and emits them at the top of C blocks to comply with C89 scope rules.
- **Platform Agnostic**: Uses the Platform Abstraction Layer (PAL) for all file I/O.

### 13.3 CVariableAllocator
- **Keyword Avoidance**: Automatically prefixes C89 keywords with `z_`.
- **MSVC 6.0 Compatibility**: Enforces a strict 31-character limit for all identifiers.
- **Uniquification**: Appends numeric suffixes to resolve name collisions within a function scope.
- **Temporary Generation**: Provides safe generation of compiler-internal temporary variables.

## 14. Compatibility Layer (`common.hpp`)
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