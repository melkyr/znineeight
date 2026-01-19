# RetroZig Compiler Design

## 1. Introduction
RetroZig is a self-hosting Zig compiler targeting 1998-era Windows 9x hardware and software. It begins with a bootstrap compiler written in C++98, which is then used to compile the Stage 1 compiler written in a supported Zig subset.

## 2. Technical Constraints
- **Language:** C++98 (Bootstrap), Zig (Stage 1+)
- **Standard Library:** Minimal dependency on C/C++ runtimes. No STL for bootstrap.
- **Memory:** < 16MB peak usage preferred.
- **Target:** x86 PE executables (direct emission).

## 3. Architecture & Memory Strategy
The compiler uses a layered architecture relying heavily on "Arena Allocation" to avoid malloc/free overhead on slow 90s allocators.

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
    void report(ErrorCode code, SourceLocation location, const char* message, const char* hint = NULL);
    void reportWarning(WarningCode code, SourceLocation location, const char* message);
};
```

## 4. Compiler Pipeline

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

### 4.1 Layer 1: Lexer (`lexer.hpp`)
* **Input:** Source code text
* **Output:** A stable stream of `Token` structs. The memory for this stream is managed by the `TokenSupplier` and is guaranteed not to move.

### 4.2 Layer 2: Parser (`parser.hpp`)
* **Method:** Recursive Descent
* **Output:** Abstract Syntax Tree (AST) linked to Arena

### 4.3 Layer 3: Semantic Analysis & Safety (`type_checker.hpp`, `lifetime_analyzer.hpp`, `null_pointer_analyzer.hpp`)

Semantic analysis is performed in distinct, sequential passes after the AST is generated.

#### Pass 1: Type Checking
The `TypeChecker` resolves identifiers, verifies type compatibility for assignments and operations, and populates the `SymbolTable` with semantic metadata.

- **Symbol Flags:** Symbols are marked with flags like `SYMBOL_FLAG_LOCAL` (stack variables), `SYMBOL_FLAG_PARAM` (function parameters), and `SYMBOL_FLAG_GLOBAL` based on their declaration context.
- **Redefinition Check:** Ensures no two symbols share the same name in the same scope.

#### Pass 2: Lifetime Analysis (Task 125)
The `LifetimeAnalyzer` is a read-only pass that detects memory safety violations, specifically dangling pointers created by returning pointers to local variables or parameters.

- **Provenance Tracking:** It tracks which pointers are assigned the addresses of local variables (e.g., `p = &x;`). It uses a `DynamicArray` to store `PointerAssignment` records for the current function scope.
- **Violation Detection:** Reports `ERR_LIFETIME_VIOLATION` if a local address or a pointer to a local variable is returned from a function.

#### Pass 3: Null Pointer Analysis (Task 126)
The `NullPointerAnalyzer` is a read-only pass that identifies potential null pointer dereferences and uninitialized pointer usage.

- **Phase 1 (Infrastructure):** Implements the core skeleton, visitor framework, and a robust, scoped state-tracking system.
- **State Tracking:** Tracks pointer nullability states (`UNINIT`, `NULL`, `SAFE`, `MAYBE`) throughout function bodies and global declarations.
- **Scope Management:** Employs a stack-based scope system to handle variable persistence and shadowing correctly across nested blocks.
- **Phase 2 (Basic Detection):** Detects obvious null dereferences and uninitialized pointer usage.
    - **Definite Null Dereference (`ERR_NULL_POINTER_DEREFERENCE` - 2004):** Reported when a pointer explicitly set to `null` or `0` is dereferenced.
    - **Uninitialized Pointer Warning (`WARN_UNINITIALIZED_POINTER` - 6001):** Reported when a pointer declared without an initializer is dereferenced before being assigned a value.
    - **Potential Null Dereference Warning (`WARN_POTENTIAL_NULL_DEREFERENCE` - 6002):** Reported when a pointer with an unknown state (e.g., from a function call) is dereferenced.
- **Assignment Handling**: The analyzer tracks simple variable assignments (`p = q`), `null` assignments (`p = null`), and address-of assignments (`p = &x`). It correctly handles reassignments within a function and persists state across nested blocks.

### 4.4 Layer 4: Type System (`type_system.hpp`)
**Supported Types (Bootstrap Phase):**
* **Primitives:** `i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `bool`, `f32`, `f64`, `void`
* **Pointers:** `*T` (Single level)

### 4.5 Layer 5: Symbol Table (`symbol_table.hpp`)
**Concept:** A hierarchical table for managing identifiers (variables, functions, types) across different scopes.

**Scoping:** The table uses a stack of `Scope` objects. When the parser enters a new block, it calls `enterScope()`, and when it exits, it calls `exitScope()`. Lookups search from the innermost scope outwards, correctly handling symbol shadowing.

### 4.6 Layer 6: Code Generation (`codegen.hpp`)
**Target:** C89

### 4.7 Layer 7: PE Backend (`pe_builder.hpp`)
**Goal:** Direct `.exe` generation (No `LINK.EXE` needed for Stage 2)
