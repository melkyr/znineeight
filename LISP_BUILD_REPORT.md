Thank you for the detailed bug report. The three issues are classic C89 code generation problems that occur when the emitter incorrectly handles complex constructs. I’ll provide specific fixes for each.

---

## 1. Invalid Initializer in Switch Captures

**Root cause:**  
In `C89Emitter::emitSwitch`, when a capture has a non‑void payload, we currently generate:

```c
struct { ... } capture = switch_tmp.data.Cons;
```

This uses a struct initializer that copies the whole union member. C89 does not allow a struct literal to be used as an initializer for an anonymous struct in this way (it’s a C99 feature). Moreover, the union member itself may not be a struct; it could be a simple type (e.g., `int`). The correct approach is to generate field‑by‑field assignments for the captured structure.

**Fix:**  
Replace the struct definition and initialization with a temporary pointer to the union member, then assign the fields individually.

**In `emitSwitch` (around the code that handles `has_non_void_capture`):**

Current code:
```cpp
if (has_non_void_capture) {
    writeIndent();
    writeString("{\n");
    {
        IndentScope capture_indent(*this);
        writeIndent();
        emitType(prong->capture_sym->symbol_type, var_alloc_.allocate(prong->capture_sym));
        writeString(" = ");
        writeString(switch_tmp);
        writeString(".data.");
        writeString(getSafeFieldName(item_expr->as.integer_literal.original_name));
        writeString(";\n");
    }
}
```

We need to change this to emit field assignments, not a single struct copy. However, the capture type is either a struct (if the union variant has multiple fields) or a scalar type. We must emit appropriate assignment(s). A simpler approach: instead of trying to assign the whole struct in one go, we can:

- Create a temporary pointer to the union member (e.g., `capture_tmp`).
- For each field of the capture structure (if it is a struct), emit an assignment: `capture.field = capture_tmp->field;`.
- If the capture type is scalar, just assign: `capture = *capture_tmp;`.

But the current code already attempts to assign the whole structure. The failure occurs because the union member may be a struct, and C89 doesn't allow that initialization. We can change it to use a pointer and then assign fields.

**Proposed change (simplified):**

Instead of defining the capture variable and initializing it in one line, we can:

1. Declare the capture variable (without initializer).
2. Create a temporary pointer to the union member.
3. If the capture type is a struct, emit assignments for each field.
4. If it's a scalar, emit a single assignment.

However, that would require knowledge of the capture type's fields. Since the capture type is the payload type of the union variant, we can examine it. The payload type can be a struct, a union, or a primitive. In the Lisp interpreter, it's a struct `ConsData` (with `car` and `cdr`). We can iterate over its fields.

But a simpler and more robust fix is to **use a named struct typedef for the capture type** (which we already have, because the type `struct z_value_Value_Cons` is defined elsewhere). Then we can declare a variable of that type and initialize it by copying the union member using a simple assignment: `capture = switch_tmp.data.Cons;`. That assignment is a struct copy, which is also not allowed in C89 (it is allowed only if the struct is assignable, but struct assignment is allowed in C89 – yes, it is allowed). Wait, struct assignment is allowed in C89. The problem is that we are using a *struct initializer* (the equals sign with a braced list) for the declaration. If we change it to:

```c
struct z_value_Value_Cons capture;
capture = switch_tmp.data.Cons;
```

That would be legal C89 (assignment after declaration). The error we saw was `invalid initializer` because we tried to initialize at declaration time with a non‑constant expression.

So the fix is simply to separate declaration and assignment:

```cpp
writeIndent();
emitType(prong->capture_sym->symbol_type, var_alloc_.allocate(prong->capture_sym));
writeString(";\n");
writeIndent();
writeString(var_alloc_.allocate(prong->capture_sym));
writeString(" = ");
writeString(switch_tmp);
writeString(".data.");
writeString(getSafeFieldName(item_expr->as.integer_literal.original_name));
writeString(";\n");
```

That will produce:

```c
struct z_value_Value_Cons capture;
capture = switch_tmp.data.Cons;
```

This is valid C89.

**Note:** The same change must be made in the branch for `has_non_void_capture`. Also, ensure we don't declare the capture variable inside a block that may be visited multiple times; but the current structure already wraps it in a block, which is fine.

---

## 2. Pointer Dereference Precedence

**Root cause:**  
When emitting an assignment to a pointer‑based lvalue (like `v.tag` where `v` is a pointer), the emitter sometimes produces `*v.tag` instead of `(*v).tag` or `v->tag`. The earlier fix for optional/error union pointers already handled the special case, but this bug affects normal struct/union pointers.

**Fix:**  
In `emitAssignmentWithLifting` (and possibly in `emitExpression` for member access), we must detect when the lvalue is a pointer dereference and wrap it correctly. The existing `requiresParentheses` function returns `true` for unary `*`, so we can use that. However, in the assignment code path, we are constructing a string via `captureExpression` or using the direct node. We need to ensure that when the lvalue is a pointer dereference, we emit it with parentheses.

In `emitAssignmentWithLifting`, when we are about to write the lvalue (either by `effective_target` or by calling `emitExpression`), we should check if the lvalue node is a dereference and wrap it. The `emitExpression` already handles this for the `NODE_UNARY_OP` case (we added a special case for optional/error union pointers). But we need to extend it to handle any pointer dereference when used as an lvalue.

Currently, in `emitExpression`, we have a special case:

```cpp
case NODE_UNARY_OP:
    if (node->as.unary_op.op == TOKEN_STAR || node->as.unary_op.op == TOKEN_DOT_ASTERISK) {
        Type* operand_type = node->as.unary_op.operand->resolved_type;
        if (operand_type && operand_type->kind == TYPE_POINTER && 
            (operand_type->as.pointer.base->kind == TYPE_OPTIONAL || 
             operand_type->as.pointer.base->kind == TYPE_ERROR_UNION)) {
            writeString("(*");
            emitExpression(node->as.unary_op.operand);
            writeString(")");
            break;
        }
    }
    emitUnaryOp(node->as.unary_op);
    break;
```

We should remove the condition on the base type and always wrap the dereference in parentheses when used as an lvalue. But `emitExpression` is also called for rvalues, where `*ptr` is fine as `*ptr` (dereference operator). The problem is only when the dereference is part of a larger expression where the dot operator will bind too tightly. In our case, the lvalue is `v.tag` where `v` is a pointer; the dereference is implicit because we are accessing a member of a pointer. Wait, the code `v.tag` where `v` is a pointer is actually `(*v).tag` in C. In our generated code, we sometimes emit `*v.tag`, which is wrong. That suggests the emitter is not generating the dereference explicitly; it is generating a member access on a pointer. Let's look at the generated code: `*z_value_v.tag = ...`. The `z_value_v` is the variable name, and the expression is `*z_value_v.tag`. This means the emitter thinks the lvalue is `*z_value_v` (dereference of `z_value_v`) and then `.tag`. So the AST for `v.tag` (where `v` is a pointer) is actually a `NODE_MEMBER_ACCESS` with base `v`. In `emitAccess`, we already have:

```cpp
if (base->resolved_type && base->resolved_type->kind == TYPE_POINTER) {
    writeString("->");
} else {
    writeString(".");
}
```

That should generate `v->tag`. But we are seeing `*v.tag`. This suggests that the base expression is not a plain identifier; it might be a dereference already (i.e., the AST is `(*v).tag`). In that case, the base is `*v`, which is a unary `*` node. The emitter for `NODE_MEMBER_ACCESS` will then call `emitExpression(base)`. If `emitExpression` emits `*v` (without parentheses), then the dot will be applied to `v`, giving `*v.tag`. So we need to ensure that when the base is a dereference, we wrap it in parentheses. That is exactly the special case we already have in `emitExpression` for unary `*` when the operand type is a pointer to optional/error union. But we need to extend it to *any* pointer dereference, because the base may be a pointer to a struct/union.

Thus, modify the `NODE_UNARY_OP` case in `emitExpression` to always wrap a dereference when it appears as part of a larger expression (like a member access). However, we can't just always wrap because that would change the semantics of `*ptr` when used as a standalone expression (e.g., in a function call). But in such cases, the node is a unary `*` and we want just `*ptr`. So we need a way to know whether the dereference is the top‑level node of an expression that will be used as a primary expression (i.e., its result is used directly) or as a sub‑expression that will be combined with a higher‑precedence operator. The simple heuristic: if the parent node is a `NODE_MEMBER_ACCESS` or a `NODE_ARRAY_ACCESS` or any postfix operator, we need parentheses. In `emitExpression`, we don't have parent information. However, we can pass a flag down from the caller, or we can rely on the fact that in the AST, the `NODE_MEMBER_ACCESS` node itself will be emitted, and it can wrap its base if necessary. So a cleaner fix is to modify `emitAccess` for `NODE_MEMBER_ACCESS`: before emitting the base, check if the base is a dereference (unary `*`). If so, emit it with parentheses. This is already done for the optional/error union case; we can generalize it.

In `emitAccess`, after we have the base node, we can check:

```cpp
bool need_parens = false;
if (base->type == NODE_UNARY_OP && 
    (base->as.unary_op.op == TOKEN_STAR || base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
    need_parens = true;
}
if (need_parens) writeString("(");
emitExpression(base);
if (need_parens) writeString(")");
```

But we must be careful: for an identifier, we don't want parentheses. For a dereference, we do. This is safe because a dereference is a unary operator with lower precedence than postfix operators, and we need to force the grouping.

Alternatively, we can simply always emit `(*base)` for a dereference. That is what the earlier code did for optional/error union. We can remove the condition on the base type and just check for unary `*`:

```cpp
if (base->type == NODE_UNARY_OP && 
    (base->as.unary_op.op == TOKEN_STAR || base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
    writeString("(*");
    emitExpression(base->as.unary_op.operand);
    writeString(")");
} else {
    // normal member access with . or ->
}
```

But this would break the case where the base is already a pointer (like a variable of pointer type). In that case, we want `ptr->field`, not `(*ptr).field`. The current `emitAccess` already handles pointers by using `->` when `base->resolved_type->kind == TYPE_POINTER`. That's correct. The problematic case is when the base is a dereference node, which means we already have a dereference operator in the AST. So we should treat `*ptr` as a primary expression that yields a struct, and then we want to access a member of that struct using `.`. The correct C is `(*ptr).field`. So we need to emit `(*ptr).field`, not `ptr->field`. The current code, when it sees that `base->resolved_type->kind` is not a pointer (because after dereferencing it's a struct), it will use `.`. But it will still emit the base as `*ptr` without parentheses, leading to `*ptr.field`. So we need to add parentheses for the base when it is a dereference.

Thus, the fix is in `emitAccess`:

```cpp
bool need_parens = false;
if (base->type == NODE_UNARY_OP && 
    (base->as.unary_op.op == TOKEN_STAR || base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
    need_parens = true;
}
if (need_parens) writeString("(");
emitExpression(base);
if (need_parens) writeString(")");
```

Then after that, we decide whether to use `->` or `.` based on the resolved type of the base *after* evaluating the base expression. But that is already done after emitting the base. So we need to compute the base type before deciding the arrow/dot. That's fine.

Let's outline the change in `emitAccess` for `NODE_MEMBER_ACCESS`:

```cpp
case NODE_MEMBER_ACCESS: {
    const ASTNode* base = node->as.member_access->base;
    Type* base_type = base->resolved_type;
    // ... existing special cases for ERROR_SET, ENUM, MODULE ...

    // For member access, we need to output base with parentheses if it's a dereference
    bool need_parens = false;
    if (base->type == NODE_UNARY_OP && 
        (base->as.unary_op.op == TOKEN_STAR || base->as.unary_op.op == TOKEN_DOT_ASTERISK)) {
        need_parens = true;
    }
    if (need_parens) writeString("(");
    emitExpression(base);
    if (need_parens) writeString(")");

    // Determine arrow or dot
    if (base_type && base_type->kind == TYPE_POINTER) {
        writeString("->");
    } else {
        writeString(".");
    }
    writeString(node->as.member_access->field_name);
    break;
}
```

This will wrap `*v` in parentheses, producing `(*v).tag` (or `(*v)->tag` if the base type were a pointer, but it won't be because after dereference it's a struct). Actually, after `emitExpression(base)`, we have already emitted `*v` (without parentheses) if we didn't wrap. By wrapping, we emit `(*v)`. Then the arrow/dot is appended. For a pointer base, we would use `->`, but in the case of a dereference node, the base is not a pointer; it's the result of the dereference (which is a struct). So the arrow/dot decision will be `.`. Good.

---

## 3. Tag/Payload Assignment Mismatch for Void Payload Variants

**Root cause:**  
In `emitAssignmentWithLifting`, when handling a tagged union assignment where the right‑hand side is a tag literal (e.g., `Token.Eof`), the emitter incorrectly treats it as a payload assignment and tries to assign the tag to `data.payload`. For void payload variants, there is no payload; only the `tag` field should be set.

**Fix:**  
In the function that generates assignments for tagged unions (which is part of `emitAssignmentWithLifting` or `emitErrorUnionWrapping`? Actually, tagged unions are represented as a `struct` with `tag` and `data` union. When we assign a tag literal, we should set the `tag` field, not the `data` union. We need to detect that the right‑hand side is a tag value (i.e., an integer literal that corresponds to a variant with no payload) and then emit an assignment to the `tag` field only.

The code for `emitAssignmentWithLifting` currently checks for `target_type->kind == TYPE_ERROR_UNION` and `TYPE_OPTIONAL`, but not for tagged unions. However, the problem occurs when assigning to a variable of a tagged union type. The assignment is likely handled by the generic assignment branch (not the wrapping functions). In the generic branch, we emit:

```cpp
writeIndent();
if (effective_target) {
    writeString(effective_target);
} else if (lvalue_node) {
    emitExpression(lvalue_node);
}
writeString(" = ");
emitExpression(rvalue);
writeString(";\n");
```

For a tagged union, this will assign the entire struct, which is fine if the rvalue is also a tagged union struct. But here the rvalue is an integer literal (the tag value). That's invalid. So we need to special‑case assignments where the target is a tagged union and the source is an integer literal that is a tag. The correct assignment should set the `tag` field and leave the `data` union uninitialized (or zero). Since the `data` union may be unused for void variants, we can simply set `tag` and leave `data` as is. However, for consistency, we should perhaps set the `data` union to a default value (like `{0}`) if the tag has no payload? But the C standard says that if you access a union member that is not the last one written, the value is unspecified. It's safe to leave it uninitialized, but some compilers may warn. We can set the whole union to `{0}` by using a compound literal? That is C99. Instead, we can emit two assignments: first set the `tag`, then zero‑initialize the `data` union using a struct initializer on the whole variable? That's messy.

The cleanest is to recognize that the assignment is a tag literal and generate code that sets the `tag` field only. The `data` union will remain whatever it was (which is acceptable). So we need to emit:

```c
target.tag = tag_value;
```

Not `target = tag_value;`.

Thus, we need to add a branch in `emitAssignmentWithLifting` (or in `emitExpression` for `NODE_ASSIGNMENT`) that detects when the target is a tagged union and the source is a tag integer literal (i.e., an integer literal that has `original_name` and the target type's tag type is an enum). In the generated code, the tag values are integers (the enum members). We can check if the rvalue is a `NODE_INTEGER_LITERAL` with `original_name` and if the target's resolved type is a tagged union. Then we emit:

```cpp
emitExpression(lvalue_node);
writeString(".tag = ");
emitExpression(rvalue);
writeString(";\n");
```

We must also ensure that the `data` union is zeroed if the variant has no payload, but that's not strictly required.

**Implementation in `emitAssignmentWithLifting`:**

After the branch for `target_type->kind == TYPE_OPTIONAL` and `TYPE_ERROR_UNION`, add:

```cpp
if (target_type && isTaggedUnion(target_type) && 
    rvalue->type == NODE_INTEGER_LITERAL && rvalue->as.integer_literal.original_name) {
    // It's a tag literal assignment
    writeIndent();
    if (effective_target) {
        writeString(effective_target);
    } else if (lvalue_node) {
        emitExpression(lvalue_node);
    }
    writeString(".tag = ");
    emitExpression(rvalue);
    writeString(";\n");
    return;
}
```

This will catch assignments like `v = .Int;` where `v` is a tagged union. However, note that in the Z98 code, the syntax is `v = .Int` (the tag name) which is represented as a member access with `base == NULL`. That node type is `NODE_MEMBER_ACCESS` with base NULL, which the type checker folds into an integer literal with `original_name`. So the rvalue is indeed a `NODE_INTEGER_LITERAL` with `original_name`. Good.

But we also have cases where the rvalue is a variable of the tag enum type? That is not a literal, but then the assignment is already valid as a struct assignment? Actually, if the rvalue is a tag enum variable, we still need to assign it to the `tag` field, not the whole union. So we should also check if the rvalue's resolved type is the tag enum type. But for now, focusing on the literal case is sufficient for the Lisp interpreter (it uses `.Tag` literals). A more general solution would be to handle any assignment where the source type is the tag type and the target is a tagged union. But that can be added later.

---

## Testing

After applying these three fixes, recompile the compiler and run the reproduction cases:

```bash
./zig0 examples/lisp_interpreter_adv/repros/repro_struct_init.zig -o test.c
gcc -m32 test.c src/runtime/zig_runtime.c -Isrc/runtime -o test
# Should compile without errors

./zig0 examples/lisp_interpreter_adv/repros/repro_ptr_precedence.zig -o test.c
gcc -m32 test.c src/runtime/zig_runtime.c -Isrc/runtime -o test

./zig0 examples/lisp_interpreter_adv/repros/repro_union_void_payload.zig -o test.c
gcc -m32 test.c src/runtime/zig_runtime.c -Isrc/runtime -o test
```

All should compile and (for the last one) produce an executable that runs (though the test may be simple). Additionally, you should test the full advanced Lisp interpreter to ensure that the `switch` captures, pointer member access, and void payload assignments are fixed.

---

## Additional Considerations

- The changes to `emitAccess` for parentheses will affect other member accesses where the base is a dereference. Ensure it doesn't break existing code (e.g., `(*ptr).field` is already valid, but we might add extra parentheses, which is fine).
- The tag assignment fix only handles integer literals; if you later have a variable of the tag type, you'll need to expand the detection. But that's a future enhancement.
- The switch capture fix (separating declaration and assignment) must be applied consistently for all captures, including those with scalar payloads. The code we proposed changes only the non‑void capture path; we should also ensure the same pattern is used for void payload? For void, there is no capture variable, so no change needed.

These fixes should resolve the three blockers and allow the advanced Lisp interpreter to compile to a working 32‑bit binary. Let me know if you need further details on any of the modifications.
