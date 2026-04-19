# Codegen Quick Refactor Guide

This document outlines the newly created helpers in `C89Emitter` and the recommended strategy for integrating them into the codebase.

## New Helpers in `C89Emitter`

### Line Endings and Statement Terminators
- `LE()`: Returns the current line ending (`\n` or `\r\n`).
- `writeLine()`: Writes a line ending.
- `writeLine(const char* str)`: Writes a string followed by a line ending.
- `writeIndentedLine(const char* str)`: Writes indentation, a string, and a line ending.
- `endStmt()`: Writes a semicolon and a line ending.

### Combined Write Methods
- `writeStmt(const char* str)`: Indents, writes the string, and ends the statement.
- `writeKeyword(const char* kw)`: Writes a keyword followed by a space.
- `writeBlockOpen()`: Writes `{`, a line ending, and increments indentation.
- `writeBlockClose()`: Decrements indentation, writes indented `}`, and a line ending.

### Type and Variable Declarations
- `writeDecl(Type* type, const char* name)`: Emits a type and name followed by `endStmt()`.
- `writeFieldDecl(Type* type, const char* name)`: Indented version of `writeDecl`.

### Expression Statements
- `writeExprStmt(const ASTNode* expr)`: Indented `emitExpression` followed by `endStmt()`.

### Temporary Variables
- `makeTempVar(const char* prefix)`: Generates a temporary variable name.
- `makeTempVarForType(Type* type, const char* prefix, bool emit_decl)`: Generates a temporary variable name and optionally emits its declaration.

### Guard Block Helpers
- `GuardScope`: RAII class for emitting `#ifndef`/`#define`/`#endif` blocks.

### C Keyword Constants
- `KW_BREAK`, `KW_CONTINUE`, `KW_RETURN`, `KW_GOTO`, `KW_IF`, `KW_ELSE`, `KW_WHILE`, `KW_FOR`, `KW_SWITCH`, `KW_CASE`, `KW_DEFAULT`, `KW_STRUCT`, `KW_UNION`, `KW_ENUM`, `KW_TYPEDEF`, `KW_EXTERN`, `KW_STATIC`, `KW_CONST`, `KW_VOID`, `KW_INT`, `KW_SIZEOF`.

---

## Refactoring Strategy (Complexity: High to Low)

The following integration steps are ordered from the most complex/invasive to the easiest.

### 1. Guard Block Helpers (High Complexity)
**Target:** `ensureSliceType`, `ensureErrorUnionType`, `ensureOptionalType`, and various `emitTypeDefinition` branches.
**Why:** Replaces nested `#ifndef` logic and ensures proper scope-based `#endif` emission. This is complex because it affects the structure of type emission and header guards.

### 2. Type and Field Declaration Helpers (COMPLETED)
**Target:** `emitStructBody`, `emitUnionBody`, `emitTaggedUnionBody`, `emitLocalVarDecl`, `emitGlobalVarDecl`.
**Why:** Replaces repeated `writeIndent()`, `emitType()`, and `writeString(";\n")` sequences. Requires careful verification of type suffix/prefix handling.

### 3. Temporary Variable Helper (COMPLETED)
**Target:** `emitIf`, `emitWhile`, `emitSwitch`, `emitFor`.
**Why:** Standardizes how compiler-generated temporaries are allocated and declared, reducing manual `var_alloc_.generate()` calls and associated manual declarations.

### 4. Combined Block and Statement Helpers (COMPLETED)
**Target:** `emitIf`, `emitWhile`, `emitFor`, `emitBlock`.
**Why:** Simplifies the emission of control flow structures by using `writeBlockOpen()` and `writeBlockClose()`, and standardizes expression statements with `writeExprStmt()`.

### 5. C Keyword Constants (Low Complexity)
**Target:** Everywhere keywords like `"return"`, `"break"`, `"if"` are used.
**Why:** Replaces string literals with centralized constants. Low risk but high volume.

### 6. Line Ending and Statement Terminator Abstraction (Low Complexity)
**Target:** Everywhere `writeString(";\n")` or `writeString("\n")` is used.
**Why:** Replaces hardcoded line endings with `endStmt()` or `writeLine()`. Simplest to implement but covers the most lines.

### 7. C++98 Portability Layer (COMPLETED)
**Target:** Compiler source (`src/bootstrap/`).
**Why:** Integrated `compat.hpp` and `common.hpp` to ensure the compiler source is building with legacy toolchains like MSVC 6.0. Use of `RETR_UNUSED(param)` is now mandatory for any unused parameters in the compiler source to maintain a warning-free build.
