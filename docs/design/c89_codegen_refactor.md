# C89 Codegen Refactoring Guide

## Overview

The `C89Emitter` class has been refactored to reduce code duplication and improve readability of the C code generation logic. This document describes the new infrastructure and how to use it for future changes.

## New Helpers

### Line Endings & Indentation
- `LE()`: Returns the platform-aware line ending (`\r\n` on Windows, `\n` otherwise).
- `writeLine()`: Writes a line ending.
- `writeLine(const char* str)`: Writes a string followed by a line ending.
- `writeIndentedLine(const char* str)`: Writes current indentation, the string, and a line ending.
- `endStmt()`: Writes `;` and a line ending.

### Statement Helpers
- `writeStmt(const char* str)`: Writes an indented statement (e.g., `break`, `continue`) with a semicolon and line ending.
- `writeExprStmt(const ASTNode* expr)`: Emits an expression as an indented statement.
- `writeDecl(Type* type, const char* name)`: Emits a type declaration.
- `writeFieldDecl(Type* type, const char* name)`: Emits an indented field declaration for structs/unions.

### Block & Flow Control
- `writeKeyword(const char* kw)`: Writes a keyword (from `KW_*` constants) followed by a space.
- `writeBlockOpen()`: Writes `{`, a line ending, and increases indentation.
- `writeBlockClose()`: Decreases indentation and writes an indented `}`.
- `GuardScope`: RAII helper for `#ifndef` / `#define` / `#endif` header guards.

### C Keyword Constants
Avoid hardcoded strings for C keywords. Use the static constants defined in `C89Emitter`:
`KW_BREAK`, `KW_CONTINUE`, `KW_RETURN`, `KW_IF`, `KW_ELSE`, `KW_STRUCT`, `KW_TYPEDEF`, etc.

## Examples

### Before
```cpp
void C89Emitter::emitBreak(const ASTBreakStmtNode* node) {
    writeIndent();
    if (defer_stack_.length() > 0) {
        writeString("/* defers for break */\n");
        emitDefersForScopeExit(node->target_label_id);
        writeIndent();
    }
    // ...
    if (node->label || uses_labels) {
        writeString("goto ");
        writeString(getLoopEndLabel(target_id));
        writeString(";\n");
    } else {
        writeString("break;\n");
    }
}
```

### After
```cpp
void C89Emitter::emitBreak(const ASTBreakStmtNode* node) {
    if (defer_stack_.length() > 0) {
        writeIndentedLine("/* defers for break */");
        emitDefersForScopeExit(node->target_label_id);
    }
    // ...
    if (node->label || uses_labels) {
        writeIndent();
        writeKeyword(KW_GOTO);
        writeString(getLoopEndLabel(target_id));
        endStmt();
    } else {
        writeStmt(KW_BREAK);
    }
}
```

## Future Work
Additional functions in `codegen.cpp` should be refactored using these patterns whenever they are modified for bug fixes or features.
