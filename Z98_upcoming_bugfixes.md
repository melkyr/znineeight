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

### Summary of Milestone 9 Tasks

| Task | Description | Priority |
|------|-------------|----------|
| 9.1 | Recursive type handling (placeholder types) | Critical |
| 9.2 | Cross‑module enum access (workaround or fix) | High |
| 9.3 | Optional type size/alignment and segfault fix | High |
| 9.4 | Tagged union captures in switch | Medium |
| 9.5 | Improve error messages and robustness | Medium |
| 9.6 | Re‑run JSON parser and document | Verification |

After these tasks, the compiler should be able to handle the JSON parser and similar real‑world code, paving the way for self‑compilation.

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
