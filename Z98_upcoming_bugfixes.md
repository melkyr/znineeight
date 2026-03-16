## Plan to Fix the Three Identified Bugs

### Overview

The three bugs discovered while compiling the JSON parser are:

1. **Tagged union initialization failure** – anonymous initializer `.{ .A = 42 }` not recognized for tagged unions.
2. **Switch expression type inference failure** – prongs returning same tagged union fail to unify.
3. **Meta‑type unwrapping in member access** – module‑qualified tag access fails.

We will tackle them in order of increasing complexity, with each phase building on the previous.

**Important:** All changes must remain compatible with MSVC 6.0. This means:
- No C99 features in generated code (we are only changing the compiler, not the output).
- Use `plat_*` functions for portability.
- Keep identifier mangling to ≤31 characters (already handled).
- Avoid stack‑allocated VLAs; use arena allocations.

---

### Phase 9a: Fix Meta‑type Unwrapping (Bug 3)

#### Problem
When accessing a tag like `json.JsonValue.Null`, the type checker sometimes fails because `json.JsonValue` is a type constant (represented as `TYPE_TYPE`) and the member access doesn't correctly unwrap to the underlying tagged union type. The symbol for `JsonValue` may be in a module, and its details point to a `var_decl` whose initializer holds the actual union type.

#### Root Cause
In `visitMemberAccess`, when the base is a module (`TYPE_MODULE`) and we look up the field, we get a symbol that is a `SYMBOL_VARIABLE` with type `TYPE_TYPE`. The code then attempts to return `get_g_type_type()` but doesn't fully resolve to the underlying type. Later, when we try to use `Null` as a tag, it fails because the type is still `TYPE_TYPE` or the member access doesn't constant‑fold.

#### Fix
In `visitMemberAccess`, after obtaining the symbol from the module, we need to:
- If the symbol's type is `TYPE_TYPE`, resolve it to the actual type stored in the symbol's initializer.
- Ensure that the node representing the member access (the tag) is constant‑folded to an integer literal (as already done for enum members) if the resolved type is an enum.

#### Pseudocode
```cpp
// Inside TypeChecker::visitMemberAccess, after resolving base and symbol
if (base_type->kind == TYPE_MODULE) {
    Symbol* sym = lookup_in_module(module, field_name);
    if (sym) {
        node->symbol = sym;
        // If symbol is a type constant, unwrap it
        if (sym->symbol_type && sym->symbol_type->kind == TYPE_TYPE) {
            // The actual type is in the initializer of the variable declaration
            if (sym->details && sym->kind == SYMBOL_VARIABLE) {
                ASTVarDeclNode* decl = (ASTVarDeclNode*)sym->details;
                if (decl->initializer && decl->initializer->resolved_type) {
                    Type* unwrapped = decl->initializer->resolved_type;
                    // If it's a placeholder, resolve it
                    if (unwrapped->kind == TYPE_PLACEHOLDER)
                        unwrapped = resolvePlaceholder(unwrapped);
                    // Now we have the real type (e.g., a tagged union)
                    // The member access is for a tag, so we need to constant‑fold it
                    if (isTaggedUnion(unwrapped)) {
                        Type* tag_type = getTagType(unwrapped);
                        if (tag_type->kind == TYPE_ENUM) {
                            // Look up the field in the enum members
                            i64 value = findEnumMemberValue(tag_type, field_name);
                            if (found) {
                                // Replace the node with an integer literal
                                parent->type = NODE_INTEGER_LITERAL;
                                parent->as.integer_literal.value = value;
                                parent->as.integer_literal.resolved_type = tag_type;
                                parent->resolved_type = tag_type;
                                return tag_type;
                            }
                        }
                    }
                }
            }
        }
        // Fallback to existing logic
        return sym->symbol_type;
    }
}
```

#### What to Watch For
- Ensure we don’t break existing enum member access (which already constant‑folds).
- Handle cases where the symbol is not a type constant (e.g., a function).
- Recursion depth: we are calling `resolvePlaceholder`; ensure no cycles.
- MSVC 6: No issues, as this is compiler‑internal logic.

---

### Phase 9b: Fix Tagged Union Initialization (Bug 1)

#### Problem
The code `return .{ .A = 42 };` fails because the type checker expects an explicit type for anonymous struct initializers. In Zig, such an initializer is allowed when the context (return type) is a tagged union. The type checker must recognize that the target type is a tagged union and validate that the field name matches a tag and that the value type matches the payload.

#### Root Cause
- `visitStructInitializer` currently only allows anonymous initializers when the context type is a struct or array (as per error message). It does not handle tagged unions.
- When an anonymous initializer appears in a return statement, the type checker calls `coerceNode` (or `IsTypeAssignableTo`) but the initializer node has no `resolved_type` yet. The coercion fails because there is no rule for `NODE_STRUCT_INITIALIZER` → tagged union.

#### Fix
1. In `coerceNode`, add a case for when `target_type` is a tagged union and the source is an anonymous struct initializer (`NODE_STRUCT_INITIALIZER` with no `type_expr`). Transform the initializer by:
   - Setting its `resolved_type` to the target union type.
   - Validating that the initializer has exactly one field, that the field name matches a tag of the union, and that the field’s value type matches the payload type.
   - Optionally, we could wrap it in a synthetic node that explicitly constructs the union, but simply setting the type and leaving the structure as‑is may be enough for later code generation (the C backend already knows how to emit tagged union initializers via `emitInitializerAssignments`).

2. In `IsTypeAssignableTo`, add a rule for `source_type` being `TYPE_UNDEFINED` (anonymous initializer) and `target_type` being tagged union? Actually, the source node doesn't have a type yet, so we need to handle it in `coerceNode` before type equality checks.

3. In `visitReturnStmt`, the coercion already happens via `coerceNode(&node->expression, current_fn_return_type_)`. So if we fix `coerceNode`, returns will work.

#### Pseudocode for `coerceNode`
```cpp
void TypeChecker::coerceNode(ASTNode** node_slot, Type* target_type) {
    ASTNode* node = *node_slot;
    if (!node || !target_type) return;

    // Existing coercions (array->slice, string->slice, etc.)

    // New: Anonymous struct initializer to tagged union
    if (node->type == NODE_STRUCT_INITIALIZER && node->as.struct_initializer->type_expr == NULL) {
        if (isTaggedUnion(target_type)) {
            // Check that the initializer has exactly one field
            if (node->as.struct_initializer->fields->length() != 1) {
                error("Tagged union initializer must have exactly one field");
                return;
            }
            ASTNamedInitializer* field = (*node->as.struct_initializer->fields)[0];
            const char* tag_name = field->field_name;

            // Find the corresponding payload field in the union
            Type* payload_type = findTaggedUnionPayload(target_type, tag_name);
            if (!payload_type) {
                error("Tag '%s' not found in union", tag_name);
                return;
            }

            // Coerce the field value to the payload type
            coerceNode(&field->value, payload_type);

            // Set the node's type to the target union type
            node->resolved_type = target_type;
            return;
        }
    }

    // ... rest of coercion logic
}
```

#### Helper function `findTaggedUnionPayload`
```cpp
Type* TypeChecker::findTaggedUnionPayload(Type* union_type, const char* tag) {
    DynamicArray<StructField>* fields = (union_type->kind == TYPE_TAGGED_UNION) ?
                                        union_type->as.tagged_union.payload_fields :
                                        union_type->as.struct_details.fields;
    for (size_t i = 0; i < fields->length(); ++i) {
        if (plat_strcmp((*fields)[i].name, tag) == 0) {
            return (*fields)[i].type;
        }
    }
    return NULL;
}
```

#### Additional Considerations
- Ensure that `coerceNode` is called in all relevant contexts: assignment, return, function arguments, variable initializers. It already is.
- The C backend's `emitInitializerAssignments` for tagged unions expects a specific structure (tag assignment then data). Our change only sets the node's type; the backend will later see a `NODE_STRUCT_INITIALIZER` with a resolved type of tagged union. In `emitInitializerAssignments`, we already have logic for tagged unions (see `is_tagged` branch). That logic assumes the initializer fields are in the order of the union's payload fields and that the tag name is the field name. It will emit:
  ```c
  target.tag = UnionTag_A;
  target.data.A = value;
  ```
  This matches what we need. So no changes in the backend are required.

- For assignments to a variable of tagged union type, the same `coerceNode` path will be hit, so it will work.

#### What to Watch For
- The initializer could also be a single value without field name, e.g., `.{ 42 }` for a union with a single anonymous field? Zig does not support that for unions; you must name the field. So our check for exactly one named field is correct.
- Payload type might be `void`. In that case, the field value should be absent? In Zig, `.{ .A }` is allowed for a tag with no payload. Our parser currently expects `.{ .A }`? Actually, the parser for anonymous literals requires `.{ .A }` without `=`. That's a different syntax (naked tag). The JSON parser uses `.{ .A = 42 }` for payload, which is fine. We should also support the naked tag form for void payloads. In the parser, `parseAnonymousLiteral` handles the case where after the dot and identifier there is no `=`, then it treats it as a field with no value. That creates a `ASTNamedInitializer` with `value = NULL`. In our coercion, we need to handle that: if `payload_type` is `void`, the value must be `NULL` (or absent). We should check that if payload is void, the initializer has no value, and vice versa.

- MSVC 6: No issues.

---

### Phase 9c: Fix Switch Expression Type Inference (Bug 2) [RESOLVED]

#### Problem
A switch expression returning a tagged union fails to unify prongs, even when each prong returns a struct initializer of the same union type. The error is "Switch prong type does not match previous prongs". The type checker sees each prong body as a different struct initializer node, and when computing the common type, it doesn't realize they both represent the same union type.

#### Root Cause
In `validateSwitch`, when we compute the type of each prong via `visit(prong->body)`, the body might be a `NODE_STRUCT_INITIALIZER` with no explicit type. Without Phase 9b, that node's `resolved_type` is `NULL` (or undefined). Even with Phase 9b, if we set the node's type to the union, then `visit` will return that type. So after Phase 9b, the prong types will be the same union type, and the switch should unify.

But there is a nuance: the switch expression itself may be used in a context that expects a type, and the prong bodies are expressions that must be coerced to that type. The unification logic in `validateSwitch` already handles that by tracking a `common_type` and coercing later. However, currently when it sees a prong body that is a struct initializer with no type, it may not have a type yet (because `visit` returns `undefined`). We need to ensure that `visit` for a struct initializer without a type returns the type it was coerced to if it has been set by `coerceNode`. But `visit` is called before coercion? Actually, in `validateSwitch`, we call `visit(prong->body)` to get its type. At that point, no coercion to a common type has happened yet. So the prong bodies are visited in isolation. If they are anonymous struct initializers, they will have no type (return `undefined`). That's the problem.

Thus, even with Phase 9b, we need to modify `validateSwitch` to handle anonymous struct initializers by using the expected switch result type (if any) to coerce them. But the switch result type is not known until after all prongs are processed. Classic chicken‑and‑egg.

**Solution approach:** When visiting a prong body that is an anonymous struct initializer and we are inside a switch expression, we can temporarily set the expected type to the union type we are switching on? Not exactly. The switch expression's result type is the common type of all prongs, which we don't know yet. However, we can use a technique similar to how we handle `if` expressions: after determining the common type, we go back and coerce each prong. That's already done in `validateSwitch`: after computing `common_type`, it calls `coerceNode` on each prong body. So if `coerceNode` can handle anonymous struct initializers (as added in Phase 9b), then when we later coerce them to the common type (which will be the union type), they will get properly typed.

But the initial `visit(prong->body)` still returns `undefined`, which may cause the type compatibility checks to fail before we have a chance to coerce. We need to allow `undefined` to be considered compatible with anything temporarily, or we need to defer type checking of prong bodies until after we know the common type.

**Current flow in `validateSwitch`:**
```cpp
for each prong:
    Type* prong_type = visit(prong->body);
    // compare with common_type, update common_type if needed
```
If `prong_type` is `undefined`, the comparison may fail. We need to treat `undefined` as a placeholder that can be coerced later.

**Fix:**
- In `validateSwitch`, when we visit a prong body and it returns `undefined` (i.e., `is_type_undefined(prong_type)`), we should not immediately reject. Instead, we record that this prong needs coercion and continue, using the type of the first non‑undefined prong as the candidate common type.
- If all prongs are `undefined`, we cannot determine the type; that should be an error (switch with no typed prongs). But in our case, at least one prong will have a type after coercion? Actually, if all prongs are anonymous struct initializers, they all start as `undefined`. Then we cannot determine a common type. So we need a different strategy: infer the common type from the switch's context. But the switch expression itself might be used in a context that expects a type (e.g., return). In that case, we know the expected type from the function return type. We should use that to coerce all prongs.

Thus, we need to pass the expected type (if any) into `validateSwitch`. For a switch statement, there is no expected type. For a switch expression, the expected type comes from the surrounding context (e.g., the return type, or the left‑hand side of an assignment). Currently, the type checker does not propagate expected types downward very well; it's mostly bottom‑up. This is a more pervasive issue.

**Simpler immediate fix:** In `validateSwitch`, if we encounter a prong with `undefined` type, we can look at the prong's body. If it's an anonymous struct initializer, we can attempt to infer the type from the tag. For example, if the prong body is `.{ .A = 42 }`, we know the tag name is `A`. If the switch condition is a tagged union, we can look up the corresponding union type and use its type as the prong's type. This requires that the switch condition's type is known and is a tagged union. In the JSON parser example, the switch condition is `u` which is a tagged union, and each prong body is a struct initializer with a field named after the tag. So we can deduce that the body should have the same type as the condition.

**Implementation in `validateSwitch` for expression switches:**

```cpp
if (is_expr && prong_type == get_g_type_undefined()) {
    // Attempt to infer from the condition type if it's a tagged union
    if (cond_type && isTaggedUnion(cond_type)) {
        // Check if the prong body is an anonymous struct initializer
        if (prong->body->type == NODE_STRUCT_INITIALIZER && prong->body->as.struct_initializer->type_expr == NULL) {
            // It has exactly one field
            if (prong->body->as.struct_initializer->fields->length() == 1) {
                ASTNamedInitializer* field = (*prong->body->as.struct_initializer->fields)[0];
                const char* tag = field->field_name;
                // Verify that tag exists in the union
                Type* payload = findTaggedUnionPayload(cond_type, tag);
                if (payload) {
                    // Coerce the field's value to the payload type now
                    coerceNode(&field->value, payload);
                    // Set the body's type to the union type
                    prong->body->resolved_type = cond_type;
                    prong_type = cond_type;
                }
            }
        }
    }
}
```

After this, all prongs will have the same union type, and the unification will succeed. We must also ensure that the `coerceNode` for the field value happens early enough (it does here).

### Phase 7: Incomplete Type Definition Order (Structs Referring to Unions) [RESOLVED]

- **Issue**: Even with pointers, if a struct refers back to a union that is still being defined, header emission order can cause issues.
- **Root cause**: Similar to Phase 3, but with structs referring to unions (or vice‑versa). Mutual recursion via pointers was previously blocked by strict TypeChecker completeness checks.
- **Fix**:
  - Relaxed `TypeChecker` to allow incomplete types in fields if they are reached through a pointer indirection.
  - Implemented explicit value-dependency cycle detection in the `TypeChecker`.
  - Enhanced `MetadataPreparationPass` to perform a two-phase traversal: value dependencies are visited first to establish a topological definition order, while pointer/function dependencies are found for forward declarations.
  - Updated `CBackend` to emit forward declarations for all aggregate types defined in the module at the top of the header.
- **Verification**:
  - Created Batch 73 (`tests/integration/phase7_tests.cpp`) verifying valid pointer recursion, invalid value cycles, and correct topological ordering for both structs and tagged unions.
  - Verified full test suite passes.
- **Outcome**: Mutually recursive types via pointers are now fully supported and correctly emitted in C89 headers.

```zig
return switch (u) {
    .A => |a| MyUnion{ .A = a },
    .B => |b| MyUnion{ .B = b },
};
```

Here, `MyUnion` is a type constant (declared as `const MyUnion = union(enum) { ... }`). So `MyUnion{ .A = a }` is a struct initializer with a type expression `MyUnion`. In the AST, `type_expr` is an identifier that resolves to `MyUnion`, which is a `TYPE_TYPE`. In `visitStructInitializer`, we handle that by resolving the type_expr to the underlying union type. That should work, but there may be a bug where `MyUnion` is not properly unwrapped from `TYPE_TYPE`. That's exactly Bug 3! So fixing Bug 3 may already make this work. Good.

Thus, the switch unification may start working after Bug 3 and Bug 1 are fixed. But we still need to ensure that the common type calculation in `validateSwitch` works when prong types are the same union type. It already does: if they are equal, it sets common_type. So after Bug 3 and Bug 1, the example might just work.

However, there is another scenario: when the prong bodies are anonymous initializers (without `MyUnion{...}`), e.g., `.{ .A = a }`. That would still need our inference. But the JSON parser example uses the named form. So perhaps Bug 2 is actually a manifestation of Bug 3. Let's double-check: The error message "Switch prong type does not match previous prongs" suggests that the types were different. If both prongs returned the same union type, they'd be equal. So likely the types were not equal because of the TYPE_TYPE issue. Therefore, after fixing Bug 3, Bug 2 may be resolved.

#### Fix
- Implemented **Expected Type Propagation** using a stack-based mechanism in the `TypeChecker`.
- Updated `visitReturnStmt`, `visitAssignment`, `visitVarDecl`, and `visitFunctionCall` to push the expected type context.
- Enhanced `validateSwitch` and `coerceNode` to use the expected type for resolving anonymous initializers in switch prongs.
- Enabled recursive downward inference for nested anonymous structures.
- Added special support for `void` payloads (naked tags, empty tuples, and void-typed expressions).
- Enforced mandatory `else` prongs for switch expressions.

#### Verification
- New test batch `Batch 9c` (`tests/main_batch9c.cpp`) provides 13 tests covering return/assignment/argument context, nesting, void payloads, and error cases.
- Verified all integration tests pass (including Batch 9b/9c).

#### Outcome
Switch expressions can now correctly unify prongs returning anonymous initializers by inferring their type from the surrounding context, fully resolving Bug 2.

---

## Summary of Phases

| Phase | Description | Effort |
|-------|-------------|--------|
| 0 | 32‑bit ABI documentation | 0.5 day |
| 1 | Tagged union forward declaration | 1 day |
| 2 | `unreachable` emission | 0.5 day |
| 3 | Error union header order | 1 day |
| 4 | Recursive slice completeness | 2 days |
| 5 | i32 → usize coercion | 0.5 day |
| 6 | Braceless switch semicolon | 0.5 day |
| 7 | Incomplete type order (contingent) | 1 day |
| 8 | Documentation | 1 day |

**Total** ≈ 7–8 days of focused work.

After completing these phases, the JSON parser should compile without any of the workarounds listed, and the compiler will be robust enough to tackle `zig1`. Each phase can be implemented and tested independently, and the fixes are isolated.

---

### Phase 9a: Fix Meta-type Unwrapping (Bug 3) [RESOLVED]

- **Issue**: Accessing members of a type alias (e.g., Alias.Member) or module-qualified type (e.g., mod.Type.Member) fails because the symbol has type TYPE_TYPE and isn't correctly unwrapped to the underlying aggregate type.
- **Fix**:
  - Implemented `TypeChecker::resolveTypeConstant(Symbol* sym)` to follow type alias chains.
  - Updated `visitMemberAccess` to use this helper for unwrapping TYPE_TYPE symbols.
  - Enabled constant folding for tagged union tags, enum members, and error tags when accessed through aliases.
- **Verification**:
  - New test batch `Batch 9a` (`tests/integration/phase9a_unwrapping_tests.cpp`) verifies module-qualified access, local aliases, recursive aliases, and error set aliases.
- **Outcome**: Meta-type unwrapping now works consistently for all static member accesses, resolving a critical blocker for the JSON parser.
