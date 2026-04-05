## Issue 1: String Literal Slice Mismatch (Signedness Warning) [RESOLVED]

**Root cause:** The `__make_slice_u8` helper expects `unsigned char*` but string literals are `char*`. C89 allows implicit conversion, but compilers warn.

**Effort:** Low (1-2 hours)

**Resolution:** Modified `CBackend::generateSpecialTypesHeader()` to specialize `__make_slice_u8` to accept `const char* ptr` and perform an explicit cast to `(unsigned char*)ptr` internally. This allows string literals to be passed without warnings.

**Verification:** Verified via reproduction script and manual GCC compilation with `-Wpointer-sign`.

---

## Issue 2: Local `const` Aggregate Declarations

**Root cause:** The compiler treats local `const` with a struct/union/enum initializer as a type declaration (like a global type alias). This is a bug in `TypeChecker::visitVarDecl` or `C89Emitter::emitLocalVarDecl`.

**Effort:** Medium (4-6 hours)

**Plan:**

1. **In `TypeChecker::visitVarDecl`,** after determining `is_local`, ensure that for a local `const` aggregate, the symbol is marked as `SYMBOL_FLAG_LOCAL` (not global) and `module_name = NULL`. The existing code already does this, but the early return (which we removed) may have been bypassed. Verify that the `existing_sym` update block sets `flags |= SYMBOL_FLAG_LOCAL` and `module_name = NULL`.

2. **In `C89Emitter::emitLocalVarDecl`,** currently there is a check that skips emitting for `const` aggregates (because it treats them as types). Modify that check to only skip if the variable is **global** and `is_const` and aggregate. For local variables, emit them normally.

   Look for code like:

   ```cpp
   if (decl->is_const && (decl->initializer->resolved_type->kind == TYPE_STRUCT || ...)) {
       return; // skip
   }
   ```

   Change to:

   ```cpp
   if (decl->is_const && !is_local && (decl->initializer->resolved_type->kind == TYPE_STRUCT || ...)) {
       return; // skip only for global
   }
   ```

3. **Add a test:** `tests/test_local_const_aggregate.zig` with:

   ```zig
   const Point = struct { x: i32, y: i32 };
   pub fn main() void {
       const p = Point{ .x = 1, .y = 2 };
       _ = p;
   }
   ```

   Ensure generated C contains `struct Point p = {1,2};` (or similar) and not a typedef.

**Workaround for now:** Use `var` instead of `const` for local aggregates. That works perfectly.

---

## Issue 3: Lisp Interpreter Recursion (Closure Capture)

**Root cause:** The interpreter’s environment model does not support self‑reference correctly. The pre‑binding attempt fails because updating the environment node in‑place may not affect the closure’s captured environment.

**Effort:** High (1-2 days) – this is an interpreter bug, not a compiler bug. However, fixing it will make the showcase work.

**Plan (to fix the interpreter, not the compiler):**

1. **Change the environment representation** to use a **boxed value** for the closure binding. Instead of storing the closure directly in the environment node, store a **mutable pointer** (e.g., `*Value`) that can be updated after closure creation.

   - In `env.zig`, change `EnvNode` to hold `value: *Value` (already does). But when we pre‑bind, we set the value to `nil`, then later we need to **update the `*Value` that the closure captured**, not just the node’s value.

2. **Modify closure creation** to capture a **reference to the environment slot**, not the value. When the lambda is evaluated, it should capture a pointer to the `Value` that will eventually hold the closure. Then, after creating the closure, we assign it to that pointer.

   Simplified algorithm:

   ```zig
   // In define
   // 1. Create a mutable slot (a pointer to a Value)
   var slot = try value_mod.alloc_nil(perm_sand);
   // 2. Bind the name to that slot in the environment
   env.* = try env_mod.env_extend(sym_name, slot, env.*, perm_sand);
   // 3. Evaluate the lambda (which captures the slot, not the value)
   const closure = try eval(lambda_expr, env, temp_sand, perm_sand);
   // 4. Update the slot's content to the closure
   slot.* = closure.*;
   ```

   This requires that the closure captures the slot address, not the value. Modify `lambda` to capture the environment slot for each free variable.

3. **Alternative (simpler):** Use a **mutable environment array** (like a vector) and store indices instead of pointers. This is more complex.

**Workaround for now:** The Lisp interpreter can still be used for non‑recursive functions. For the showcase, you can demonstrate recursion by using a built‑in recursive function (e.g., `fact` implemented in Zig, not Lisp). Or you can note that recursion is a known limitation of the interpreter, not the compiler.

---

## Issue 4: Loop State & Capture Sensitivity

**Effort:** Low to Medium (2-4 hours) – this is a compiler bug that may affect some complex loops.

**Plan:**

1. **Create a minimal repro** that isolates the problem. For example, a loop that captures a tagged union payload and uses it across iterations.

2. **Analyze the generated C code** for the loop. Look for:
   - Temporaries declared outside the loop (should be inside).
   - Payload captures being reused incorrectly.
   - Missing `break` or `continue` labels.

3. **Fix the `ControlFlowLifter`** to ensure that temporaries for `switch` captures inside loops are declared **inside the loop body**, not outside. The lifter already inserts temporaries at the position of the node; if the node is inside a loop, the temporary should be inside the loop’s block. Verify that the lifter correctly handles this.

4. **If the issue is specific to the Lisp interpreter**, you can restructure the interpreter’s code to avoid the problematic pattern (e.g., move the loop body into a separate function). That is a workaround.

**Assessment:** This issue is rare and not a blocker for self‑hosting. Most compiler loops are simple (AST traversal) and do not involve complex captures. You can safely defer it.

