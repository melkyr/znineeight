## Final Fixes for `zig1` – Phased Plan with Pseudocode

Based on your analysis, the only compiler changes absolutely necessary to compile `zig1` are:

1. **Anonymous Union Emission Bug** – a code generator bug that must be fixed.
2. **Standard Library Conflicts** – resolved by introducing `c_char` and removing the problematic `#include`.
3. **Optional Pointer ABI** – if `zig1` uses `?*T` in `extern` signatures, we need to map them to raw pointers.
4. **Recursive Type Layout** – already worked around; no compiler change needed.

Below is a phased plan with pseudocode, test strategies, and what to watch for.

---

### Task 1: Fix Anonymous Union Emission Bug

**Goal:** Ensure that anonymous unions inside structs emit a valid C union body, not just `union /* anonymous */`.

**Impacted files:** `codegen.cpp` (emitter), `ast.hpp` (union node fields already exist).

**Pseudocode for `C89Emitter::emitTypeDefinition` (handling union nodes):**

```cpp
void C89Emitter::emitUnionDefinition(ASTUnionDeclNode* node, const char* field_name) {
    // node is an anonymous union (node->name == NULL)
    writeIndent();
    writeString("union {");
    indent();

    // Emit each field
    for (size_t i = 0; i < node->fields->length(); ++i) {
        ASTNode* field_node = (*node->fields)[i];
        ASTStructFieldNode* field = field_node->as.struct_field;

        writeIndent();
        emitType(field->type->resolved_type, field->name);
        writeString(";\n");
    }

    dedent();
    writeIndent();
    writeString("} ");
    writeString(field_name);
    writeString(";\n");
}
```

In `emitStructDefinition`, when processing a field whose type is an anonymous union, call `emitUnionDefinition` instead of the usual type emission:

```cpp
// Inside loop over struct fields
if (field_node->type == NODE_UNION_DECL && field_node->as.union_decl->name == NULL) {
    emitUnionDefinition(field_node->as.union_decl, field_name);
} else {
    // normal field emission
    emitType(field_type, field_name);
    writeString(";\n");
}
```

**What to watch for:**
- Ensure that nested anonymous unions are handled correctly (the function recurses via `emitUnionDefinition` on the nested union's fields).
- If the union itself has a name, it should be emitted normally (with the union tag). The condition `name == NULL` distinguishes anonymous.
- Test with a struct containing an anonymous union inside another anonymous union.

**Test:**
Create a Zig file `anon_union_test.zig`:
```zig
const S = struct {
    data: union {
        int: i32,
        float: f64,
    },
    tag: i32,
};
export fn test() void {
    var s: S = undefined;
    s.data.int = 42;
}
```
Compile and inspect the generated C. It should contain:
```c
struct S {
    union {
        int int;
        double float;
    } data;
    int tag;
};
```
Also test with a union inside a struct that is itself inside another struct.

---

### Task 2: Introduce `c_char` and Resolve Standard Library Conflicts

**Goal:** Provide a distinct type for C's `char`, allowing extern function signatures to match the C library exactly. Also remove the problematic `#include <stdio.h>` from `zig_runtime.h`.

#### Subtask 2.1: Add `c_char` to the type system

**Impacted files:** `type_system.hpp`, `type_system.cpp`, `lexer.hpp`, `parser.cpp`, `c89_type_mapping.hpp`, `codegen.cpp`.

**Steps:**
- Add `TYPE_C_CHAR` to `TypeKind` enum.
- In `resolvePrimitiveTypeName`, map `"c_char"` to `TYPE_C_CHAR`.
- In `emitBaseType`, emit `"char"` for `TYPE_C_CHAR`.
- Set size=1, alignment=1 (same as `u8`).
- Update the type checker to allow conversions between `u8` and `c_char` (optional, but we can keep them distinct; the user must use explicit casts).

**Pseudocode for `type_system.cpp`:**
```cpp
Type* createCCharType(ArenaAllocator* arena) {
    Type* t = (Type*)arena->alloc(sizeof(Type));
    t->kind = TYPE_C_CHAR;
    t->size = 1;
    t->alignment = 1;
    return t;
}
```

**What to watch for:**
- Ensure that `c_char` is not confused with `u8` in the type checker; they are distinct, so no implicit conversion unless we add a rule.
- In the JSON parser, we will update `file.zig` to use `c_char` for string parameters.

#### Subtask 2.2: Update `zig_runtime.h` to be minimal

- Remove `#include <stdio.h>`.
- If any runtime helper needs `fputs` (e.g., `__bootstrap_print`), move its implementation to a separate `.c` file that includes `<stdio.h>`, or provide a version that uses Win32 API. For simplicity, we can keep the helper in a separate file and let the user link it. However, to avoid breaking existing code, we can keep the include but also provide a way to suppress it. Since this is a one-time change for `zig1`, we can simply remove the include and update the JSON parser's build to include `<stdio.h>` manually if needed.

**Recommended:** Remove the include and document that the user must include `<stdio.h>` in their own C file if they use functions like `fopen`. For the runtime helpers, we can implement `__bootstrap_print` using `WriteFile` on Windows and `write` on POSIX, avoiding `stdio.h`. That's more portable and keeps the header independent.

**Implementation for `__bootstrap_print` (in `zig_runtime.c`):**
```c
#ifdef _WIN32
#include <windows.h>
void __bootstrap_print(const char* s) {
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), s, strlen(s), NULL, NULL);
}
#else
#include <unistd.h>
void __bootstrap_print(const char* s) {
    write(2, s, strlen(s));
}
#endif
```

Then remove `#include <stdio.h>` from `zig_runtime.h`.

**Testing:** Recompile the JSON parser after making these changes. Ensure that `__bootstrap_print` works and that there are no conflicts with `fopen` declarations.

---

### Task 3: Optional Pointer ABI for Extern Functions [DONE]

**Goal:** Make `?*T` in `extern` function signatures map to raw pointer `T*` in C, preserving ABI compatibility.

**Impacted files:** `type_checker.cpp`, `codegen.cpp`.

**Strategy:** During type checking of `extern` functions, transform any optional pointer type to a raw pointer type. Store the transformed type in the symbol. During code generation, use the transformed type for the prototype.

**Pseudocode for `TypeChecker::visitFnDecl` when `node->is_extern` is true:**

```cpp
Type* original_ret = visit(node->return_type);
Type* new_ret = transformExternType(original_ret);
// Similarly for parameters
for each param in node->params {
    Type* orig = param->type->resolved_type;
    Type* new = transformExternType(orig);
    // Store new type in param->type->resolved_type? But we must not modify the original AST node because it's shared.
    // Instead, create a new list of transformed types and store them in a separate structure.
}
```

Define `transformExternType`:

```cpp
Type* transformExternType(Type* t) {
    if (t->kind == TYPE_OPTIONAL && t->as.optional.payload->kind == TYPE_POINTER) {
        // Return a plain pointer with same constness and many-item flag
        return createPointerType(
            arena_,
            t->as.optional.payload->as.pointer.base,
            t->as.optional.payload->as.pointer.is_const,
            t->as.optional.payload->as.pointer.is_many,
            &unit_.getTypeInterner()
        );
    }
    return t;
}
```

We need a way to attach the transformed types to the function symbol. We can store a separate function type for the C prototype. For simplicity, we can create a new function type with transformed parameter and return types and store it in `sym->c_prototype_type`. In code generation, if that exists, use it; otherwise use the normal type.

**In `codegen.cpp`, `emitFnProto` for `extern` functions:**
```cpp
if (sym->c_prototype_type) {
    emitTypePrefix(sym->c_prototype_type->as.function.return_type);
    // ... emit parameters using the transformed types from sym->c_prototype_type
} else {
    // normal path
}
```

**What to watch for:**
- Only transform for `extern` functions; internal functions should keep the original optional representation.
- Ensure that const‑correctness is preserved (e.g., `?*const T` becomes `const T*`).
- If the optional is a pointer to a many‑item pointer (`?[*]T`), it should become `T*` (since `[*]T` is already a pointer). So we need to strip both optional and many‑item if needed? Actually `?[*]T` is a pointer to many‑item; after transformation we get `[*]T`, which is a pointer. That's fine.

**Testing:**
Create a test with an `extern` function returning `?*void` and another with a parameter of type `?*const i32`. Compile and verify the generated C uses `void*` and `const int*`.

---

### Task 4: Documentation Updates

Update the following documents to reflect the new features and workarounds:

- `docs/design/C89_Codegen.md` – describe anonymous union emission, `c_char` mapping, and optional pointer transformation for externs.
- `docs/reference/Language_Spec_Z98.md` – document `c_char` and the rule that `?*T` in externs becomes raw pointer.
- `Z98_upcoming_bugfixes.md` – mark issues as resolved.

---

## Summary of What to Test

| Task | Test Cases |
|------|------------|
| Anonymous Union | Struct with anonymous union field, nested anonymous unions, union inside struct inside union. |
| `c_char` | Extern function using `c_char` for string parameters, e.g., `fopen`. Also test that `u8` and `c_char` are distinct (cannot be assigned without cast). |
| Optional Pointer ABI | Extern function returning `?*void`, taking `?*const i32` parameter. Verify C prototype and that call site passes a raw pointer. |
| Runtime Header | After removing `#include <stdio.h>`, compile a program that uses `__bootstrap_print` and verify it links and works. |
