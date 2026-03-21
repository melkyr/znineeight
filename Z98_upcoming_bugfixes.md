After reviewing the provided compiler source files, I've identified the root causes of the issues you're facing with your Lisp interpreter. Below are the critical problems and their fixes, presented as pseudocode patches with testing strategies.

---

## 1. Cross‑Module Type Identity: Replace Pointer Equality with Structural Equality

**Problem:** `TypeChecker::areTypesCompatible` uses `expected == actual` to decide if two types are identical. When the same type is imported from two different modules, it appears as two distinct `Type*` pointers, causing spurious type mismatch errors.

**Fix:** Use a deep structural equality check (`areTypesEqual`) for the identity case.

**Patch (type_checker.cpp):**
```cpp
bool TypeChecker::areTypesCompatible(Type* expected, Type* actual) {
    // First, check structural equality (handles placeholders, cross-module types)
    if (areTypesEqual(expected, actual)) {
        return true;
    }
    // ... rest of the function (coercions, etc.)
}
```

**Why this works:**  
`areTypesEqual` must recursively compare the structure of two types, ignoring memory addresses. It should handle placeholders by resolving them if needed, and compare fields, element types, etc. This ensures that `struct S { x: i32 }` defined in module A is considered identical to the same struct imported from module B.

**Testing:**  
Create two modules: `mod_a.zig` defining `pub const Point = struct { x: i32, y: i32 };` and `mod_b.zig` importing `Point` and assigning it to a variable of type `Point`. Compile – should succeed without type mismatch.

---

## 2. Placeholder Finalization: Always Restore the Original Type Name

**Problem:** When a placeholder is finalized, the resolved type may be anonymous (e.g., a struct defined inline). The placeholder loses its original name, leading to `struct /* anonymous */` in the generated C code, which breaks C compilation.

**Fix:** In `finalizePlaceholder`, explicitly set the name field of the mutated placeholder to the original placeholder name if the resolved type lacks one.

**Patch (type_checker.cpp):**
```cpp
void TypeChecker::finalizePlaceholder(Type* placeholder, Type* resolved) {
    const char* original_name = placeholder->as.placeholder.name;
    // ... mutate placeholder in place (copy resolved's fields) ...

    // After mutation, restore the name if the resolved type didn't have one
    if (placeholder->kind != TYPE_PLACEHOLDER) {
        if ((placeholder->kind == TYPE_STRUCT || placeholder->kind == TYPE_UNION) &&
            !placeholder->as.struct_details.name) {
            placeholder->as.struct_details.name = original_name;
        } else if (placeholder->kind == TYPE_ENUM && !placeholder->as.enum_details.name) {
            placeholder->as.enum_details.name = original_name;
        } else if (placeholder->kind == TYPE_TAGGED_UNION && !placeholder->as.tagged_union.name) {
            placeholder->as.tagged_union.name = original_name;
        } else if (placeholder->kind == TYPE_ERROR_SET && !placeholder->as.error_set.name) {
            placeholder->as.error_set.name = original_name;
        }

        // Also ensure the C name is set
        if (!placeholder->c_name && original_name) {
            placeholder->c_name = unit_.getNameMangler().mangleTypeName(
                original_name, placeholder->owner_module->name);
        }
    }
}
```

**Testing:**  
Define a recursive type:  
```zig
const Node = struct {
    value: i32,
    next: ?*Node,
};
```
Compile and inspect generated C – the struct should have a proper name like `struct Node`.

---

## 3. `main` Function Return Type: Force `int` for C89 Compatibility

**Problem:** When `main` returns `!void`, the C emitter generates an `ErrorUnion_void` struct as the return type, but the C runtime expects `int`. The linker fails because `main` has an incompatible signature.

**Fix:** Special‑case the `main` function in the C emitter to always emit an `int` return and convert the Zig return value to `int`.

**Patch (codegen.cpp):**
```cpp
void C89Emitter::emitReturn(const ASTReturnStmtNode* node) {
    if (is_main_function_) {
        writeIndent();
        if (node->expression) {
            writeString("return (int)(");
            emitExpression(node->expression);
            writeString(");\n");
        } else {
            writeString("return 0;\n");
        }
        return;
    }
    // ... existing generic return handling ...
}
```

**Why this works:**  
The `is_main_function_` flag is already set in `emitFnDecl` when the function name is `"main"`. This branch bypasses the error‑union wrapping and simply returns the integer result (or `0` if no expression).

**Testing:**  
Write a `pub fn main() !void` that calls a function returning an error union and uses `try`. Compile to C and then compile with a C89 compiler (e.g., MSVC 6.0). Should link and run without error.

---

## 4. Lifted Variables: Declare at the Beginning of the Block

**Problem:** The AST lifter inserts temporary variable declarations at the exact position where the expression appears. If that position is not the first statement in a block, C89 compilers reject it because declarations must precede all statements in a block.

**Fix:** In `liftNode`, always insert the temporary variable declaration at the **beginning** of the current block, and insert the lowering statements at the original position.

**Patch (ast_lifter.cpp):**
```cpp
void ControlFlowLifter::liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix, bool needs_wrapping) {
    // ... generate var_decl_node and lowering_stmts ...

    if (block_stack_.length() > 0 && stmt_stack_.length() > 0) {
        ASTBlockStmtNode* current_block = block_stack_.back();
        ASTNode* current_stmt = stmt_stack_.back();
        int insert_idx = findStatementIndex(current_block, current_stmt);

        if (insert_idx != -1) {
            size_t offset = 0;
            if (var_decl_node) {
                // Insert variable declaration at the top of the block
                current_block->statements->insert(0, var_decl_node);
                offset = 1;
                // The original statement's index increased by 1
                insert_idx++;
            }
            // Insert the lowering statements at the original position
            for (size_t i = 0; i < lowering_stmts.length(); ++i) {
                current_block->statements->insert(insert_idx + offset + i, lowering_stmts[i]);
            }
        }
    }

    // ... replace node_slot with identifier ...
}
```

**Why this works:**  
C89 allows declarations only at the start of a block. Moving the temporary declaration to index 0 satisfies this. The lowering statements (e.g., `if` statements) are inserted after the original statement, preserving execution order. The original statement's index is adjusted because a new element was added at the beginning.

**Testing:**  
Create a function that uses `try` inside a block after a preceding statement, e.g.:
```zig
fn test() !void {
    _ = @import("std").debug.print("Hello\n", .{});
    try someErrorFunction();
}
```
The generated C should have the temporary for `try` declared at the top of the function block, not after the `print` call.

---

## 5. Guard Against Null Dereferences and Type Mismatches

To avoid segfaults during comparisons and casts, add explicit null checks and type kind checks before accessing union fields.

**Example (type_checker.cpp):**
```cpp
bool TypeChecker::areTypesEqual(Type* a, Type* b) {
    if (!a || !b) return a == b;
    if (a->kind == TYPE_PLACEHOLDER) a = resolvePlaceholder(a);
    if (b->kind == TYPE_PLACEHOLDER) b = resolvePlaceholder(b);
    if (a->kind != b->kind) return false;
    // ... now safe to compare kind-specific fields ...
}
```

**Also check in `areTypesCompatible`:**  
Before using `expected` or `actual` in pointer arithmetic, ensure they are non‑null and of the expected kind.

**Testing:**  
Create a test that deliberately passes `null` to a function expecting a type, or uses an invalid cast. The compiler should not crash.

---

## Overall Testing Plan

1. **Cross‑module type identity** – compile a multi‑module program with shared structs.
2. **Recursive types** – compile a self‑referential struct or union.
3. **Main with `!void`** – compile a program that uses `try` in `main` and verify the C output.
4. **Lifting in blocks** – compile a function with `try` after other statements and inspect C code for declaration order.
5. **Null safety** – run the compiler on intentionally invalid code to ensure it reports errors gracefully.

If you have the Lisp interpreter source, run these tests on it and check the generated C code for the issues mentioned. If any errors persist, the compiler's `debug_trace_` flag can be enabled to log the lifting and code generation steps.

Let me know if you need further assistance or more detailed explanations for any of these patches.
