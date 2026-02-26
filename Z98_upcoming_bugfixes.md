## Stabilization for Real‑World Code

### Overview
The JSON parser “baptism of fire” revealed several critical gaps in the compiler’s ability to handle realistic, mutually recursive types and cross‑module symbol access. This milestone focuses on fixing those issues and adding the necessary features to make the compiler robust enough to compile itself (i.e., to build `zig1`). The tasks are ordered by priority and dependency.

---

### Task 9.1: Recursive Type Handling – Placeholder Types
**Goal**: Prevent infinite recursion when resolving types that reference themselves (or each other) through pointers/slices.

**Why**: Currently, visiting a struct/union that contains a slice of itself (e.g., `JsonValue` containing `[]JsonValue`) causes the type checker to enter an endless loop, eventually crashing.

**Solution**:
- Introduce a “type under construction” mechanism. When starting to resolve a type (e.g., in `visitVarDecl` for a type definition), immediately create a **placeholder type** (a distinct `Type` with kind `TYPE_PLACEHOLDER`) and insert it into the symbol table under the type’s name.
- Then proceed to resolve the actual type expression (struct/union/enum). While resolving, any reference to the same type name will find the placeholder, which can be used to construct pointer/slice types (since their size doesn’t depend on the pointee’s complete definition).
- After the type is fully resolved, replace the placeholder with the real type. However, we must also update all existing references to the placeholder to point to the real type. This can be done by storing a list of “dependent” types (like pointers/slices) that were created using the placeholder, and later updating their `base` pointer.

**Implementation Sketch**:
```cpp
// In TypeChecker, while resolving a type definition:
Type* resolveTypeDefinition(ASTVarDeclNode* node) {
    const char* name = node->name;
    // Check if symbol already exists (e.g., from a previous placeholder)
    Symbol* sym = symbol_table->lookup(name);
    if (sym && sym->type->kind == TYPE_PLACEHOLDER) {
        // Already being defined – this is a self-reference
        return sym->type; // return placeholder
    }
    // Create placeholder
    Type* placeholder = createPlaceholderType();
    placeholder->as.placeholder.name = name;
    placeholder->as.placeholder.resolved = nullptr;
    // Insert into symbol table
    Symbol* new_sym = createSymbol(name, placeholder, ...);
    symbol_table->insert(new_sym);
    // Resolve the actual type
    Type* real_type = resolveType(node->type);
    // Now replace placeholder with real_type – but we need to update all uses.
    // We can store a list of dependent types (pointers, slices, etc.) in the placeholder
    // and then patch them. For simplicity, we can also just leave the placeholder and
    // let later code deal with it, but that would break size calculations.
    // Better: after full resolution, replace placeholder in symbol table and patch dependents.
    placeholder->as.placeholder.resolved = real_type;
    // For any type that was built using the placeholder (e.g., pointer), we need to replace
    // its base with the real type. We'll maintain a list in the placeholder.
    for each dependent in placeholder->dependents:
        dependent->base = real_type;
    return real_type;
}
```

**Testing**:
- Write a minimal test with a recursive struct (e.g., `Node = struct { next: *Node }`) and verify it compiles without recursion.
- Extend to mutual recursion (two types referencing each other).

---

### Task 9.2: Cross‑Module Enum Member Access [DONE]
**Goal**: Allow access to enum members from an imported module using the module prefix (e.g., `json.JsonValueTag.Number`).

**Why**: The JSON parser uses such qualified names, and they currently fail with “enum has no such member”.

**Root Cause**: When `visitMemberAccess` sees a base that is an import variable (type `TYPE_MODULE`), it looks up the member in the module’s symbol table. However, the symbol for the enum itself is found, but then the second level (the enum member) is not handled correctly.

**Solution**:
- In `visitMemberAccess`, if the base type is `TYPE_MODULE` and the member name resolves to an enum type (or struct/union), store the resulting type and also note that we need to handle further member access (e.g., `json.JsonValueTag.Number`). This means we may need to chain member accesses. The AST currently represents `json.JsonValueTag.Number` as a single `NODE_MEMBER_ACCESS` with base = `json.JsonValueTag` and member = `"Number"`. But `json.JsonValueTag` itself is a `NODE_MEMBER_ACCESS`. So we need to recursively resolve.
- The type checker already handles chained member accesses: it resolves the base expression, then looks up the member. So if `json.JsonValueTag` is properly resolved to an enum type, then the second access should work. The problem likely is that `json.JsonValueTag` is not being resolved as a symbol because the import variable `json` is of type `TYPE_MODULE`, and member access on a module returns the symbol for the module’s public declaration, but that symbol may not have a proper type? Actually, we need to ensure that when we resolve `json.JsonValueTag`, we get a symbol of kind `TYPE` (for the enum), and that symbol’s type is `TYPE_ENUM`. Then the second access will look up the enum member.

**Fix**:
- In `visitMemberAccess` for a module base, after looking up the member name in the module’s symbol table, if the found symbol is a type (enum/struct/union), we need to create an appropriate node to represent that type as a value? In Zig, a type name used in a value context is not allowed (except for `@typeOf`). But `json.JsonValueTag` is a type, not a value. In the expression `json.JsonValueTag.Number`, the left part is a type, not a value. Zig allows this because `Number` is an enum member, and the syntax `Enum.Member` is valid. So we need to treat `json.JsonValueTag` as a type expression. However, our AST currently treats member access as an expression that yields a value. We need to distinguish between accessing a type member (which yields a type) and accessing a value member. For enum members, the result is a value (the enum constant). So `json.JsonValueTag.Number` should be a `NODE_MEMBER_ACCESS` where the base is a type expression (the enum type) and the member is the constant. The base `json.JsonValueTag` is itself a qualified type name. In Zig, `json.JsonValueTag` is a type, and it can be used as such. So we need to support qualified type names in type expressions.

**Alternative**: In the JSON parser, we can avoid this by importing the enum type and then using it directly. For example:
```zig
const JsonValueTag = json.JsonValueTag;
const Number = JsonValueTag.Number;
```
That would work if `json.JsonValueTag` can be resolved as a type. So the issue might be that we cannot yet use qualified names in type expressions. We need to extend `parseType` to allow qualified identifiers (like `json.JsonValueTag`). Currently, `parseType` only handles simple identifiers. That’s the root cause.

**Task**:
- Modify the parser to allow qualified names in type expressions. When parsing a type, if we see a chain of identifiers separated by dots, we should build a `NODE_QUALIFIED_TYPE` (or reuse member access). Then in the type checker, we resolve it by looking up the first identifier as a module, then subsequent as members, finally returning the type.

**Simpler**: For now, we can require that enum types used across modules are imported via a local alias. That is, the JSON parser can do:
```zig
const JsonValueTag = json.JsonValueTag;
const Number = JsonValueTag.Number;
```
This avoids the need for qualified type names. So the immediate fix may be to adjust the test code rather than implement a new feature. Given the priority, we might choose to work around it in the JSON parser and later add qualified type name support.

**Decision**: Since the JSON parser is a test, we can modify it to use local aliases. This unblocks the test while we later implement the feature properly. So for now, we document this as a known limitation and adjust the test.

---

### Task 9.3: Fix Optional Type Segfault [DONE]
**Goal**: Resolve the segmentation fault when processing optional types like `?File`.

**Result**: Resolved by adding NULL checks in `createOptionalType` and related factories, and implementing dynamic size/alignment calculation based on the payload type's completeness.

**Fix Details**:
- Added NULL checks to `createOptionalType`, `createPointerType`, `createArrayType`, `createSliceType`, and `createErrorUnionType`. These now return `TYPE_UNDEFINED` instead of crashing when given a NULL payload.
- Implemented dynamic layout calculation for `?T` in `createOptionalType`, correctly handling padding and alignment for payloads with alignment > 4 (e.g., `f64`).
- Updated `isTypeComplete` to handle `TYPE_OPTIONAL` and other complex types properly.
- Updated `TypeInterner` to bypass interning for types containing `TYPE_PLACEHOLDER`, preventing issues with mutating types.
- Updated `getMangledTypeName` in codegen to handle `TYPE_PLACEHOLDER` gracefully.

**Verification**:
- Added regression tests for undefined optional payloads and recursive optional types.
- Verified correct size calculation for `?f64` and other aligned types.

---

### Task 9.4: Tagged Union Captures in Switch
**Goal**: Support Zig’s syntax for extracting payloads from tagged unions in switch statements (e.g., `switch (val) { .Number => |n| ... }`).

**Why**: This is a common pattern and would make the JSON parser much cleaner. Currently we use a workaround with explicit tags and manual field access.

**Implementation**:
- Extend `ASTSwitchProngNode` to store an optional capture variable name.
- In the parser, when parsing a prong, if after `=>` there is a `|` identifier `|`, capture it.
- In the type checker, when visiting a switch expression, for each prong with a capture, create a new scope and insert a symbol for the capture variable with the appropriate type (the payload type of the union case). The payload type is derived from the union’s field.
- In code generation, for a prong with capture, emit a block that declares the capture variable and initializes it from the union’s payload. Then emit the prong’s expression.

**Testing**:
- Write a small test that uses a tagged union and a switch with capture.

---

### Task 9.5: Improve Error Messages and Robustness [DONE]
**Goal**: Add better error messages for common failures (e.g., undefined symbols, type mismatches) and increase overall robustness.

**Why**: During the JSON parser attempt, many errors were silent or led to crashes. Better diagnostics would speed up development.

**Actions**:
- Audit `ErrorHandler` to ensure all error codes have descriptive messages.
- Add assertions in critical places (with `assert`) in debug builds to catch null pointers early.
- Improve `TypeChecker` to report the location and reason for type mismatches more clearly.
- **Implemented a transition from fatal aborts to recoverable reporting**, enabling multi-error detection in a single pass.
- **Centralized error messages** and moved context-specific info into hints.

**Testing**: Added `tests/integration/multi_error_tests.cpp` to verify multiple error reporting and ensured all existing tests pass through a harness-level abort synchronization.

---

### Intermediate: Re‑run JSON Parser and Document Remaining Issues
**Goal**: After fixing the above, attempt to compile the JSON parser again and document any remaining issues.

**Steps**:
- Apply the workaround for cross‑module enum access (use local aliases).
- Run the compiler with debug prints and note any new errors.
- If it compiles, run the generated C through `gcc` and verify the output.
- Document the results in `missing_features_for_jsonparser.md` and update the Z98 specification accordingly.

---

## Refactor to ensure Slices and lifting is properly handled

### Part 1: What is RAII and Why Do We Need It Here?

**RAII (Resource Acquisition Is Initialization)** is a C++ programming idiom where resource management (memory, file handles, locks, *state*) is tied to object lifetime.
- **Acquisition:** Happens in the **Constructor**.
- **Release:** Happens in the **Destructor** (automatically called when the object goes out of scope, even during errors/returns).

**Why do you need it in `codegen.cpp`?**
Currently, your code manages state manually (e.g., `indent()`, `dedent()`, `defer_stack_.append()`, `defer_stack_.pop_back()`).
- **The Risk:** If `emitBlock` calls `indent()` and then hits an early `return` (due to an error or logic check), `dedent()` is never called. Your `indent_level_` becomes desynchronized, corrupting all subsequent output.
- **The RAII Solution:** Wrap the state change in a local object. When the function exits (for any reason), the destructor runs and fixes the state automatically.

---

### Part 2: Stabilization Plan with Pseudocode

Here is the phased plan to harden stability before attempting lifting unification.

#### Phase 1: Hardening I/O and Error Handling
*Goal: Prevent silent data corruption and invalid C generation.*

**Task 9.5.1: Fail-Hard on Buffer Overflow [DONE]**
Currently, `C89Emitter::write` truncates data if `type_def_buffer_` is full. This creates silent bugs.
**Action:** Replace truncation with a fatal error.

```cpp
// Pseudocode for C89Emitter::write
void write(const char* data, size_t len) {
    if (len == 0) return;

    if (in_type_def_mode_) {
        // CHECK: Do we have space?
        if (type_def_pos_ + len > type_def_cap_) {
            // OLD: len = type_def_cap_ - type_def_pos_; // Truncation (BAD)
            // NEW: Hard Fail
            error_handler_.report(ERR_INTERNAL, NULL, "Type definition buffer overflow");
            plat_abort(); 
        }
        plat_memcpy(type_def_buffer_ + type_def_pos_, data, len);
        type_def_pos_ += len;
        last_char_ = data[len - 1];
        return;
    }

    // ... existing buffer flush logic ...
}
```

**Task 9.5.2: Standardize Error Reporting [DONE]**
Currently, some errors write `/* error: ... */` into the C file. This makes the C compilable but logically wrong.
**Action:** Force all codegen errors to stop emission for that node.

```cpp
// Pseudocode for emitTryExpr (and similar lifting funcs)
void emitTryExpr(const ASTNode* node, const char* target_var) {
    if (!node || node->type != NODE_TRY_EXPR) {
        // OLD: writeString("/* error: try expression is NULL */");
        // NEW: Report and Return
        error_handler_.report(ERR_INTERNAL, node->loc, "Null try expression node");
        return; 
    }
    
    // ... rest of logic ...
}
```

#### Phase 2: Implementing RAII State Guards
*Goal: Ensure `indent_level_` and `defer_stack_` are always balanced.*

**Task 9.5.3: Indentation Scope Guard [DONE]**
Create a local helper class inside `codegen.cpp` (or in a helper header) to manage indentation.

```cpp
// Pseudocode: Define this class inside codegen.cpp or codegen.hpp
class IndentScope {
public:
    C89Emitter* emitter;
    IndentScope(C89Emitter* e) : emitter(e) {
        emitter->indent();
    }
    ~IndentScope() {
        emitter->dedent();
    }
};

// Usage in emitBlock
void C89Emitter::emitBlock(const ASTBlockStmtNode* node, int label_id) {
    writeString("{\n");
    
    // RAII: Automatically dedents when this function returns
    IndentScope scope(this); 

    // ... logic ...
    // Even if we 'return' early here, ~IndentScope() runs dedent()
}
```

**Task 9.5.4: Defer Scope Guard**
Manage the `defer_stack_` lifecycle similarly to prevent leaks or mismatches.

```cpp
// Pseudocode: DeferScopeGuard
class DeferScopeGuard {
public:
    C89Emitter* emitter;
    DeferScope* scope;
    bool exited_cleanly;

    DeferScopeGuard(C89Emitter* e, int label_id) : emitter(e), exited_cleanly(false) {
        scope = (DeferScope*)e->arena_.alloc(sizeof(DeferScope));
        new (scope) DeferScope(e->arena_, label_id);
        e->defer_stack_.append(scope);
    }

    ~DeferScopeGuard() {
        // Emit defers only if we didn't hit a terminator (return/break)
        // Note: You need a way to tell the guard if the block exited early.
        // For now, assume we emit defers unless marked otherwise.
        if (!exited_cleanly) { 
             // Actually, logic is complex here. 
             // Better: The guard pops the stack. The emitter decides when to emit defers.
        }
        emitter->defer_stack_.pop_back();
    }
    
    void markCleanExit() { exited_cleanly = true; }
};

// Usage in emitBlock
void C89Emitter::emitBlock(...) {
    writeString("{\n");
    IndentScope indent(this);
    DeferScopeGuard defer_guard(this, label_id);

    // ... process statements ...
    
    if (!exits) {
        // emit defers
    }
    // ~DeferScopeGuard pops the stack automatically
}
```

#### Phase 3: Legibility and Maintainability Refactors
*Goal: Reduce cognitive load in large functions.*

**Task 9.5.5: Extract Assignment Logic**
`emitStatement` and `emitLocalVarDecl` both have massive `if/else` chains for handling `TRY`, `CATCH`, `IF` assignments. Unify this.

```cpp
// Pseudocode: Helper Function
void C89Emitter::emitAssignmentWithLifting(const char* target_var, const ASTNode* rvalue) {
    if (!target_var) {
        emitExpression(rvalue);
        return;
    }

    switch (rvalue->type) {
        case NODE_TRY_EXPR:   emitTryExpr(rvalue, target_var); break;
        case NODE_CATCH_EXPR: emitCatchExpr(rvalue, target_var); break;
        case NODE_IF_EXPR:    emitIfExpr(rvalue, target_var); break;
        case NODE_SWITCH_EXPR: emitSwitchExpr(rvalue, target_var); break;
        case NODE_ORELSE_EXPR: emitOrelseExpr(rvalue, target_var); break;
        default:
            writeString(target_var);
            writeString(" = ");
            emitExpression(rvalue);
            writeString(";");
            break;
    }
}

// Usage in emitStatement
// Replace the huge 50-line if/else block with:
emitAssignmentWithLifting(lvalue_symbol, rvalue);
```

**Task 9.5.6: Break Down `emitExpression` Switch**
The `emitExpression` switch is too large. Group related handlers into private methods.

```cpp
// Pseudocode: Grouping
void C89Emitter::emitExpression(const ASTNode* node) {
    switch (node->type) {
        case NODE_INTEGER_LITERAL:
        case NODE_FLOAT_LITERAL:
        case NODE_BOOL_LITERAL:
            emitLiteral(node); // New helper
            break;
        case NODE_BINARY_OP:
        case NODE_UNARY_OP:
            emitOperator(node); // New helper
            break;
        // ... keep control flow separate ...
    }
}
```

#### Phase 4: Type System Safety
*Goal: Prevent crashes in `type_system.cpp` due to null pointers.*

**Task 9.5.7: Guard Type Creators**
Functions like `createPointerType` assume `base_type` is valid.

```cpp
// Pseudocode: type_system.cpp
Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const, ...) {
    // NEW: Safety Check
    if (!base_type) {
        plat_print_debug("Error: Creating pointer to null type\n");
        return get_g_type_undefined();
    }
    
    // ... existing logic ...
}
```

**Task 9.5.8: Interner Null Checks**
Ensure the `TypeInterner` doesn't hash null pointers.

```cpp
// Pseudocode: TypeInterner::getPointerType
Type* TypeInterner::getPointerType(Type* base_type, ...) {
    if (!base_type) return createPointerType(...); // Handle error case first
    
    if (containsPlaceholder(base_type)) { ... }
    
    // Hashing is safe now
    u32 h = hashType(TYPE_POINTER, base_type, ...);
    // ...
}
```

---

### Part 3: 9.5.9 Additional Refactor Suggestions for Legibility

1.  **Consistent Naming Convention:**
    *   **Current:** Mix of `emitBlock`, `emit_block` (not seen but common in C), `var_alloc_`.
    *   **Suggestion:** Stick to `camelCase` for methods (`emitBlock`) and `snake_case_` for members (`indent_level_`). The code mostly follows this, but ensure new helpers do too.
    *   **Specific:** Rename `writeString` to `write` (overload) or `writeLit` to distinguish from `write` (buffer). Currently `write` takes `(const char*, size_t)` and `writeString` takes `(const char*)`. This is fine, but ensure `write` isn't called with raw strings accidentally without `strlen`.

2.  **Magic Numbers:**
    *   **Current:** `65536` for `type_def_cap_`, `256` for buffers.
    *   **Suggestion:** Define constants at the top of `codegen.cpp`.
    ```cpp
    static const size_t TYPE_DEF_BUFFER_SIZE = 65536;
    static const size_t TEMP_BUFFER_SIZE = 256;
    ```

3.  **Early Returns:**
    *   **Current:** Some functions nest deeply (`if (node) { if (type) { ... } }`).
    *   **Suggestion:** Use guard clauses.
    ```cpp
    // Instead of:
    if (node) {
        if (node->type == X) { ... }
    }
    // Use:
    if (!node) return;
    if (node->type != X) return;
    ```

4.  **Comment Documentation:**
    *   **Current:** Comments explain *what* (e.g., `// Emit defers`).
    *   **Suggestion:** Explain *why* for complex logic (e.g., `// Defers must emit in reverse order to match Zig semantics`).

Yes, this is the correct file to evaluate. `type_checker.cpp` is actually **more critical** than `type_system.cpp` for stability because it:

1. **Has more recursion** (visits every AST node)
2. **Manages more state** (function context, loop depth, label stacks, defer tracking)
3. **Has more error paths** (every node type can fail type checking)

Here's my analysis and refactoring plan specifically for `type_checker.cpp`:

---

## Part 4: Critical Issues in `type_checker.cpp`

| Issue | Location | Risk Level | Win98 Impact |
| :--- | :--- | :--- | :--- |
| **No Recursion Guard** | `visit()` function | **HIGH** | Stack overflow on deep AST |
| **Manual State Restore** | `visitFnBody`, `visitDeferStmt` | **HIGH** | State corruption on early return |
| **Duplicate Logic** | `visitBreakStmt` / `visitContinueStmt` | **MEDIUM** | Code bloat, maintenance burden |
| **Silent NULL Returns** | Many `visit*` functions | **MEDIUM** | Cascading errors, hard to debug |
| **Large Switch Statement** | `visit()` (~50 cases) | **LOW** | Hard to maintain, but no runtime cost |

---

## Part 5: Refactoring Plan for Type Checker

### Task 9.5.9 Add Recursion Depth Guard 

**Problem**: `visit()` calls itself recursively without limits. On Win98 (1MB stack), deeply nested expressions could crash.

**Pseudocode**:
```cpp
// Add to TypeChecker members in type_checker.hpp
int visit_depth_;
static const int MAX_VISIT_DEPTH = 200; // Conservative for 1MB stack

// In TypeChecker constructor
: visit_depth_(0) { ... }

// In visit() function
Type* TypeChecker::visit(ASTNode* node) {
    visit_depth_++;
    if (visit_depth_ > MAX_VISIT_DEPTH) {
        unit.getErrorHandler().report(ERR_STACK_OVERFLOW, node->loc, 
            "Type checking recursion depth exceeded (max 200)");
        visit_depth_--;
        return get_g_type_undefined();
    }
    
    Type* resolved_type = NULL;
    switch (node->type) {
        // ... existing cases ...
    }
    
    visit_depth_--;
    return resolved_type;
}
```

**Memory Cost**: +4 bytes per `TypeChecker` instance (stack member).
**Safety Benefit**: Prevents hard crash on Win98.

---

### Task 9.5.10 RAII State Guards (Week 2)

**Problem**: Functions like `visitFnBody` manually save/restore state. Early returns corrupt state.

**Current Code** (Line ~1450):
```cpp
Type* TypeChecker::visitFnBody(ASTFnDeclNode* node) {
    Type* prev_fn_return_type = current_fn_return_type;
    const char* prev_fn_name = current_fn_name;
    current_fn_name = node->name;
    current_fn_return_type = fn_symbol->symbol_type->as.function.return_type;
    
    // ... many lines ...
    
    current_fn_return_type = prev_fn_return_type;  // Might not execute!
    current_fn_name = prev_fn_name;                // Might not execute!
}
```

**Pseudocode for RAII Guard**:
```cpp
// Add this class inside type_checker.cpp (stack-only, ~12 bytes)
struct FunctionContextGuard {
    TypeChecker* checker;
    Type* prev_return_type;
    const char* prev_fn_name;
    int prev_label_id;
    DynamicArray<const char*> prev_labels;  // Reference, not copy
    
    __forceinline FunctionContextGuard(TypeChecker* c, const char* fn_name, Type* ret_type)
        : checker(c), prev_return_type(c->current_fn_return_type), 
          prev_fn_name(c->current_fn_name), prev_label_id(c->next_label_id_) {
        c->current_fn_name = fn_name;
        c->current_fn_return_type = ret_type;
        c->next_label_id_ = 0;
        c->function_labels_.clear();
    }
    
    __forceinline ~FunctionContextGuard() {
        checker->current_fn_return_type = prev_return_type;
        checker->current_fn_name = prev_fn_name;
        checker->next_label_id_ = prev_label_id;
        // function_labels_ is restored by caller if needed
    }
};

// Usage in visitFnBody
Type* TypeChecker::visitFnBody(ASTFnDeclNode* node) {
    Symbol* fn_symbol = unit.getSymbolTable().lookup(node->name);
    if (!fn_symbol || !fn_symbol->symbol_type) {
        if (!visitFnSignature(node)) return NULL;
        fn_symbol = unit.getSymbolTable().lookup(node->name);
    }
    
    // RAII: State automatically restored on return
    FunctionContextGuard guard(this, node->name, 
        fn_symbol->symbol_type->as.function.return_type);
    
    unit.getSymbolTable().enterScope();
    // ... rest of logic ...
    unit.getSymbolTable().exitScope();
    
    return NULL;
}
```

**Memory Cost**: ~12 bytes per function call (stack only).
**Safety Benefit**: State always restored, even on early return.

---

### Task 9.5.11 Extract Duplicate Label Logic (Week 3)

**Problem**: `visitBreakStmt` and `visitContinueStmt` duplicate ~80% of their logic.

**Current Code** (Line ~1280-1320):
```cpp
Type* TypeChecker::visitBreakStmt(ASTNode* node) {
    ASTBreakStmtNode& break_node = node->as.break_stmt;
    if (in_defer) {
        unit.getErrorHandler().report(ERR_BREAK_INSIDE_DEFER, ...);
    } else if (current_loop_depth == 0) {
        unit.getErrorHandler().report(ERR_BREAK_OUTSIDE_LOOP, ...);
    }
    if (break_node.label) {
        bool found = false;
        for (int i = (int)label_stack_.length() - 1; i >= 0; --i) {
            if (label_stack_[i].name && plat_strcmp(label_stack_[i].name, break_node.label) == 0) {
                break_node.target_label_id = label_stack_[i].id;
                found = true;
                break;
            }
        }
        if (!found) {
            unit.getErrorHandler().report(ERR_UNKNOWN_LABEL, ...);
        }
    } else {
        if (label_stack_.length() > 0) {
            break_node.target_label_id = label_stack_.back().id;
        }
    }
    return get_g_type_noreturn();
}

// visitContinueStmt is nearly identical...
```

**Pseudocode for Extraction**:
```cpp
// Private helper function
static bool ResolveLabel(DynamicArray<LoopLabel>& label_stack, 
                         const char* label, int* target_id, 
                         SourceLocation loc, ErrorHandler& error_handler,
                         bool is_break) {
    if (label) {
        for (int i = (int)label_stack.length() - 1; i >= 0; --i) {
            if (label_stack[i].name && plat_strcmp(label_stack[i].name, label) == 0) {
                *target_id = label_stack[i].id;
                return true;
            }
        }
        error_handler.report(is_break ? ERR_UNKNOWN_LABEL : ERR_UNKNOWN_LABEL, 
            loc, "Unknown label");
        return false;
    } else {
        if (label_stack.length() > 0) {
            *target_id = label_stack.back().id;
            return true;
        }
        error_handler.report(is_break ? ERR_BREAK_OUTSIDE_LOOP : ERR_CONTINUE_OUTSIDE_LOOP,
            loc, is_break ? "break outside loop" : "continue outside loop");
        return false;
    }
}

// Simplified visitBreakStmt
Type* TypeChecker::visitBreakStmt(ASTNode* node) {
    ASTBreakStmtNode& break_node = node->as.break_stmt;
    if (in_defer) {
        unit.getErrorHandler().report(ERR_BREAK_INSIDE_DEFER, node->loc, ...);
    } else if (current_loop_depth == 0) {
        unit.getErrorHandler().report(ERR_BREAK_OUTSIDE_LOOP, node->loc, ...);
    }
    
    ResolveLabel(label_stack_, break_node.label, &break_node.target_label_id,
        node->loc, unit.getErrorHandler(), true);
    
    return get_g_type_noreturn();
}

// Simplified visitContinueStmt
Type* TypeChecker::visitContinueStmt(ASTNode* node) {
    ASTContinueStmtNode& cont_node = node->as.continue_stmt;
    if (in_defer) {
        unit.getErrorHandler().report(ERR_CONTINUE_INSIDE_DEFER, node->loc, ...);
    } else if (current_loop_depth == 0) {
        unit.getErrorHandler().report(ERR_CONTINUE_OUTSIDE_LOOP, node->loc, ...);
    }
    
    ResolveLabel(label_stack_, cont_node.label, &cont_node.target_label_id,
        node->loc, unit.getErrorHandler(), false);
    
    return get_g_type_noreturn();
}
```

**Code Savings**: ~40 lines removed.
**Maintainability**: Label resolution logic in one place.

---

### Task 9.5.12 Loop Context RAII Guard (Week 4)

**Problem**: `visitWhileStmt`, `visitForStmt` manually manage `current_loop_depth` and `label_stack_`.

**Pseudocode**:
```cpp
// RAII Guard for loop context
struct LoopContextGuard {
    TypeChecker* checker;
    int prev_depth;
    
    __forceinline LoopContextGuard(TypeChecker* c, const char* label, int label_id)
        : checker(c), prev_depth(c->current_loop_depth) {
        c->current_loop_depth++;
        if (label) {
            // Check duplicate
            for (size_t i = 0; i < c->function_labels_.length(); ++i) {
                if (plat_strcmp(c->function_labels_[i], label) == 0) {
                    c->unit.getErrorHandler().report(ERR_DUPLICATE_LABEL, ...);
                }
            }
            c->function_labels_.append(label);
        }
        LoopLabel ll = { label, label_id };
        c->label_stack_.append(ll);
    }
    
    __forceinline ~LoopContextGuard() {
        checker->current_loop_depth = prev_depth;
        checker->label_stack_.pop_back();
        if (checker->function_labels_.length() > 0) {
            checker->function_labels_.pop_back();
        }
    }
};

// Usage in visitForStmt
Type* TypeChecker::visitForStmt(ASTForStmtNode* node) {
    Type* iterable_type = visit(node->iterable_expr);
    
    node->label_id = next_label_id_++;
    
    // RAII: Loop context automatically managed
    LoopContextGuard guard(this, node->label, node->label_id);
    
    // ... symbol table setup ...
    
    visit(node->body);
    
    return NULL;
}
```

**Memory Cost**: ~8 bytes per loop (stack only).
**Safety Benefit**: Loop depth always restored, even on errors.

---

### Task 9.5.13 Defer Context Guard (Week 5)

**Problem**: `visitDeferStmt` and `visitErrdeferStmt` manually toggle `in_defer`.

**Pseudocode**:
```cpp
// RAII Guard for defer context
struct DeferContextGuard {
    TypeChecker* checker;
    bool prev_in_defer;
    
    __forceinline DeferContextGuard(TypeChecker* c)
        : checker(c), prev_in_defer(c->in_defer) {
        c->in_defer = true;
    }
    
    __forceinline ~DeferContextGuard() {
        checker->in_defer = prev_in_defer;
    }
};

// Usage in visitDeferStmt
Type* TypeChecker::visitDeferStmt(ASTDeferStmtNode* node) {
    DeferContextGuard guard(this);
    visit(node->statement);
    return NULL;
}

// Usage in visitErrdeferStmt
Type* TypeChecker::visitErrdeferStmt(ASTErrDeferStmtNode* node) {
    DeferContextGuard guard(this);
    visit(node->statement);
    return NULL;
}
```

**Memory Cost**: ~5 bytes per defer (stack only).
**Safety Benefit**: `in_defer` always restored.

---
### Task 9.5.14 Error Reporting Consistency (Week 6)

**Problem**: Some functions return `NULL` without reporting errors, causing cascading failures.

**Current Pattern** (inconsistent):
```cpp
// Some functions report errors
if (!operand_type) {
    unit.getErrorHandler().report(...);
    return NULL;
}

// Others don't
if (!base_type) return NULL;  // No error reported!
```

**Pseudocode for Standardization**:
```cpp
// Add this helper to TypeChecker
__forceinline Type* ReportAndReturnNull(SourceLocation loc, ErrorType err, const char* msg) {
    unit.getErrorHandler().report(err, loc, msg);
    return get_g_type_undefined();  // Return undefined instead of NULL
}

// Usage in visitMemberAccess
Type* TypeChecker::visitMemberAccess(ASTNode* parent, ASTMemberAccessNode* node) {
    Type* base_type = visit(node->base);
    if (!base_type) {
        // Error already reported by visit()
        return get_g_type_undefined();
    }
    // ... rest of logic ...
}
```

**Benefit**: Easier to trace error chains in test output.

---

### Task 9.5.14 Memory & Stack Analysis

| Component | Size | Per-Call Cost | Max Depth | Total Stack |
| :--- | :--- | :--- | :--- | :--- |
| `visit_depth_` | 4 bytes | 0 | 1 | 4 bytes |
| `FunctionContextGuard` | 12 bytes | 12 bytes | 50 (functions) | 600 bytes |
| `LoopContextGuard` | 8 bytes | 8 bytes | 20 (nested loops) | 160 bytes |
| `DeferContextGuard` | 5 bytes | 5 bytes | 20 (nested defers) | 100 bytes |
| **Total** | | | | **~1KB max** |

**Well within 1MB Win98 stack limit.**



### Task 9.6: Fix Recursive Type Instability for Slices

Goal: Ensure that types containing slices of themselves (e.g., JsonValue with []JsonValue) resolve correctly without incomplete‑type errors.

Root Cause: The placeholder system currently handles pointers well, but slices are represented as structs that contain a pointer and a length. When a slice’s element type is the type being defined, the placeholder resolution may not properly update the slice’s element type, leading to “incomplete type” errors when accessing fields later.

Implementation:

    In createSliceType, if the element type is a placeholder, store a reference to that placeholder and mark the slice as “pending.”

    After the placeholder is resolved to a real type, update all dependent slice types in‑place (similar to how pointers are handled). This may require keeping a list of dependent slices on the placeholder.

    Alternatively, ensure that slice types are always created with the placeholder and that any later use forces resolution of the placeholder before the slice’s size/alignment is needed. Currently, slice size is fixed (two words) regardless of element type, so the slice itself can be considered complete even if the element type is a placeholder. The problem arises when trying to access fields of the element type. So we need to ensure that when we access an element of the slice, the element type is resolved.

Verification:
Write a test that defines a mutually recursive slice type across two modules:
zig

// a.zig
const b = @import("b.zig");
pub const A = struct { data: []B };

// b.zig
const a = @import("a.zig");
pub const B = struct { value: i32, next: ?*A };

Compile a.zig and ensure no “incomplete type” errors occur. Also verify that the generated C code contains the correct struct definitions.

### Task 9.7: Implicit Coercion from Slices to Many‑Item Pointers

Goal: Allow a slice []T to be implicitly converted to a many‑item pointer [*]T when used as an argument to an extern function expecting a raw pointer.

Rationale: Currently, passing a string literal or slice to a C function like fopen requires explicit .ptr and @ptrCast. This is verbose and error‑prone. Adding implicit coercion makes the code more natural.

Implementation:

    In areTypesCompatible, add a rule: if the destination type is a many‑item pointer ([*]T) and the source type is a slice ([]T) with the same element type, they are compatible. This allows the type checker to accept the conversion.

    In code generation, when emitting a slice as a many‑item pointer, just use the slice’s .ptr field. No extra code is needed because the representation already stores the pointer.

    Ensure that this coercion only works in contexts where a raw pointer is expected (e.g., function arguments, assignments to [*]T variables). It should not be allowed in other contexts (e.g., arithmetic) because that would change semantics.

Verification:
Write a test that calls an external C function expecting a [*]const u8 (like puts) with a string literal and a slice:
zig

extern fn puts(s: [*]const u8) i32;
const msg = "hello";
pub fn main() void {
    _ = puts(msg);          // should work implicitly
    const slice = msg[0..3];
    _ = puts(slice);        // should also work implicitly
}

Compile and run (if possible) to confirm no type errors and correct output.

### Task 9.8: Parser Support for while Continue Expressions

Goal: Implement the Zig syntax while (cond) : (iter) stmt, where iter is an expression evaluated after each loop iteration.

Rationale: The JSON parser originally used this pattern. While we can work around it by moving the iteration to the end of the loop, supporting the syntax directly improves compatibility.

Implementation:

    Extend the AST: add an optional iter_expr field to ASTWhileStmtNode.

    Modify parseWhileStatement to look for a colon after the condition. If present, parse the iteration expression (which can be any expression) and expect a closing parenthesis.

    In the type checker, ensure the iteration expression is well‑typed (it can be any expression, typically an assignment or increment).

    In code generation, emit the loop as:
    c

    while (cond) {
        // body
        iter_expr;
    }

    This matches Zig semantics (the iteration expression is evaluated after the body, before the next condition check).

Verification:
Write a test that uses a while loop with a continue expression to sum numbers:
zig

pub fn sum_up_to(n: u32) u32 {
    var i: u32 = 0;
    var total: u32 = 0;
    while (i < n) : (i += 1) {
        total += i;
    }
    return total;
}

Ensure it parses, type‑checks, and generates correct C code that when run returns the correct sum.

### Task 9.9: Stabilize Tagged Unions and Switch Captures

Goal: Fix remaining issues with tagged unions (union(enum)) and switch captures (|payload|) that cause type‑checking failures in complex nested initializations.

Root Cause: The current implementation may not fully resolve placeholders when accessing union fields or capturing payloads. Also, the type of the capture variable may not be correctly inferred from the union field.

Implementation:

    Audit visitTaggedUnionDecl to ensure that field types are correctly resolved (using placeholders where needed) and that the union’s layout is computed after all fields are resolved.

    In visitSwitchExpr, when a prong has a capture, look up the corresponding field in the union’s field list and set the capture variable’s type to that field’s type. Ensure that any placeholders in the field type are resolved before use.

    Add defensive checks: if a field type is still a placeholder when the switch is being checked, trigger resolution (similar to resolveTypePlaceholder).

    Test with a variety of tagged union initializations and switch captures, including nested unions and recursive types.

Verification:
Write a test that defines a tagged union and uses it in a switch with capture:
zig

const Value = union(enum) {
    Int: i32,
    Float: f64,
    Text: []const u8,
};

fn describe(val: Value) []const u8 {
    return switch (val) {
        .Int => |i| "int",
        .Float => |f| "float",
        .Text => |s| "text",
    };
}

Also test nested tagged unions (e.g., a union containing another union) and ensure captures work correctly. Compile and run (if possible) to verify correct values.
