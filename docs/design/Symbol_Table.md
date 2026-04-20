# Symbol Table Design

This document describes the design and implementation of the Symbol Table in the Z98 compiler.

## 1. Overview

The Symbol Table is responsible for managing identifiers (variables, functions, types, modules) across different scopes. As of Milestone 11, it supports **multi-kind symbols**, allowing multiple entities with the same name but different kinds to coexist in the same scope.

## 2. Core Structures

### 2.1 SymbolType
Defines the kind of entity a symbol represents:
- `SYMBOL_VARIABLE`: A variable or constant.
- `SYMBOL_FUNCTION`: A function declaration.
- `SYMBOL_TYPE`: A type definition (struct, enum, etc.).
- `SYMBOL_UNION_TYPE`: Specifically for union/tagged union types.
- `SYMBOL_MODULE`: An internal representation of a module.
- `SYMBOL_UNKNOWN`: A sentinel used for kind-agnostic lookups.

### 2.2 Symbol
Represents a single named entity. It contains the name, module name, kind, resolved type, source location, and semantic flags.

### 2.3 SymbolEntry
The internal storage unit within a `Scope`.
```cpp
struct SymbolEntry {
    Symbol symbol;
    SymbolEntry* next;           // Next entry in the hash bucket (different name/module)
    SymbolEntry* next_same_name; // Next symbol with SAME name and module, but DIFFERENT kind
};
```

## 3. Scope and Hierarchical Lookups

The `SymbolTable` maintains a stack of `Scope` objects.
- **Global Scope**: The bottom of the stack (level 1).
- **Local Scopes**: Created for function bodies, blocks, and loop captures.

### 3.1 Insertion Logic
When inserting a symbol:
1. The compiler checks for a collision in the current scope.
2. A collision only occurs if a symbol with the same **name**, **module**, AND **kind** already exists.
3. If a symbol with the same name/module but a different kind exists, the new symbol is appended to the `next_same_name` chain.

### 3.2 Lookup Logic
Lookups search from the innermost scope to the outermost.
- **Kind-Aware Lookup**: If a specific `SymbolType` is requested, the search traverses the `next_same_name` chain to find the first match.
- **Kind-Agnostic Lookup**: If `SYMBOL_UNKNOWN` is used, the first symbol encountered (usually the first one inserted) is returned.

## 4. Multi-Kind Use Cases

The primary motivation for multi-kind support is resolving collisions between modules and types.

### 4.1 Module vs. Type Collision
In Zig, a file `dungeon.zig` defines a module named `dungeon`. Inside that file, a user may define `pub const Dungeon = struct { ... };`.
On case-insensitive filesystems (like Windows 98), or when the user intentionally uses the same name, the `SYMBOL_MODULE` (injected by the compiler) and the `SYMBOL_VARIABLE` (the user's type constant) would previously collide.

With multi-kind support:
1. `@import("dungeon.zig")` inserts a `SYMBOL_MODULE` named `"dungeon"`.
2. `pub const Dungeon = ...` inserts a `SYMBOL_VARIABLE` named `"Dungeon"`.
3. The `TypeChecker` can specifically look for the `SYMBOL_VARIABLE` when resolving `dungeon.Dungeon`.

## 5. Memory Management

The Symbol Table is entirely arena-allocated. `SymbolEntry` nodes are allocated from the `CompilationUnit`'s global arena. The overhead of the `next_same_name` pointer is minimal (4 bytes on 32-bit) and fits well within the 16MB constraint.
