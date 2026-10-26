# Iterative Lowering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the LIR lowerer depth-safe on every platform by replacing `lowerExpr`/`lowerExprImpl`/`lowerStmt` C-stack recursion with an explicit continuation stack, and shrink the lowerer's per-frame cost by splitting `lowerExprImpl` into per-kind functions.

**Architecture:** A heap-allocated `ExprFrame` stack on `LirLowerer` replaces the C call stack for expression and statement lowering. Each arm that needs a child value pushes a resumable frame (node index + phase + saved temps) instead of recursing; a driver loop evaluates children and re-enters the parent arm at its saved phase, so LIR emission order is preserved exactly. Independently, `lowerExprImpl` is split into per-kind functions so its 70 KB C frame becomes ~2 KB.

**Tech Stack:** Z98 (strict subset of Zig, compiles to C89), gcc 12 (`-m32 -std=c89 -O0`), i686-w64-mingw32-gcc 12 + Wine 8.0 for the Windows side.

**Spec:** `docs/superpowers/specs/2026-10-24-phase2-z98-debugger-design.md` (adjacent; this plan fixes a compiler defect found while validating that work). The defect report and measurements live in `/tmp/spillfix_report.md` §residuals.

## Global Constraints

- **Z98 subset.** `sf/src/**` is a strict Z98 subset that self-compiles. No language feature unless it is already used in neighbouring code. See `sf/src/util/path.zig` for idioms.
- **Edit tool only** for repo source (`fastedit` errors in this env with `code.matchAll`; use `edit`). No `sed`/`perl`/`python`/`awk` bulk edits on repo source. `/tmp` scratch scripts are fine.
- **No `git checkout` to undo. No destructive git. No push.** Commits are made by the controller, not subagents.
- **`run.err` is untouchable.**
- **Emission order is a hard contract.** The 8 dump-MD5 pins, 5 runtime goldens, and marker output must stay **byte-identical**. Any change is a STOP, not a re-baseline.
- **Corpus universe is frozen.** 1188 dirs from `scripts/corpus/list_corpus_dirs.sh`. Do not add or remove dirs.
- Compiler self-build uses `-ffast`; user programs default to `-fsafe`. Seed rotation is a controller closeout step — subagents must not rotate.
- **Run economy (operator directive).** The 6-entry gate set is slow. **Emit it ONCE per task per compiler**, into one output dir, then derive *every* check from that single run: `diff -r` byte-identity, the `zig_special_types.h` name->value set comparison, and the runtime stdout/exit comparison. Do not re-emit per check. Batch the gate-script cases into one invocation.
- **Ruling (iii) verification contract** (applies from Task 1 onward): `emitErrorCodePrologue` emits `ERROR_*` in dense `reg_code` order at **both** callers (`sf/src/c89_emit.zig:1315` and `:2922` `emitModule`); `emitErrorCodePrologueBucketOrder` is deleted. Proof that runtime behavior is preserved: (1) all gate-set `.c` byte-identical, (2) `zig_special_types.h` name->value map **set-identical** (order-insensitive), (3) gate entries built+run with baseline vs fixed compilers produce byte-identical stdout and exit codes, (4) the 4 `--dump-c89` pins re-recorded **once** with explicit old->new listed in the commit message. Macro line order alone cannot change semantics while values stay unique.

## Review Focus

- **Emission order in the 32 interleaved arms.** `bool_and`/`bool_or` (`sf/src/lower.zig:4890`, `:4913`) lower `lhs`, emit `branch`, then lower `rhs` into a *different basic block*. A flatten-children-first trampoline silently reorders LIR and moves all 8 pins. Test: pins byte-identical on `examples/z98/{mud_server,game_of_life,lisp_interpreter_curr,json_parser}/main.zig`.
- **`fn_call` argument pre-allocation.** `lowerPreallocArgs` (`:4182`) reserves arg temps *before* the args are lowered. If the trampoline lowers args first, temp numbering shifts and emitted C changes. Test: pins + goldens on the four pin entries.
- **Statement recursion is a second, independent bomb.** `lowerStmt` has an 18 KB C frame and recurses on `block` (`:7910`) and `labeled_stmt` (`:7924`/`:7931`). 100-deep nested blocks = 1.8 MB. Test: a 200-deep block fixture must pass under `ulimit -s 1024`.
- **Phase-state completeness.** A frame that resumes at the wrong phase, or a saved temp slot that is not restored, corrupts later temps silently (wrong code, no crash). Test: full battery + byte-identical emission on the whole corpus, not just the four pins.
- **The depth guard must not fire on legal input.** Any path left recursive must fail with a clean `error[...]`, never a segfault. Test: `emission_sibling_payload_xmod` and the deep-block fixture both pass at 1 MB stack.

---

### Task 0: Establish the byte-identity baseline

**Files:**
- Create: `/tmp/lowerfix_base/` (scratch, not repo)
- Test: none (this task produces the comparison baseline)

**Interfaces:**
- Consumes: committed seed `release/seed/zig1-seed.tgz` (v122, F_new `a806a3573c618496ddf956f1c746f316`)
- Produces: `/tmp/lowerfix_base/zig1_5_clean` (baseline compiler) and `/tmp/lowerfix_base/emit/` (baseline emitted C for the gate set)

- [ ] **Step 1: Build the baseline compiler from the working tree as it stands before any lowering change**

Run: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/lowerfix_base`
Expected: `=== [seed] Done: /tmp/lowerfix_base ===`, hop1 == hop2.

- [ ] **Step 2: Emit baseline C for the gate set with normal `-o` multifile emission**

The gate set is the four 8-pin entries plus the two defect fixtures:

```
for e in examples/z98/mud_server/main.zig examples/z98/game_of_life/main.zig \
         examples/z98/lisp_interpreter_curr/main.zig examples/z98/json_parser/main.zig \
         repro/mi_matrix/emission_sibling_payload_xmod/main.zig \
         repro/mi_matrix/stdlib_print_tuple_fwd_ok_xmod/main.zig; do
  n=$(basename $(dirname $e))
  /tmp/lowerfix_base/zig1_5_clean -ffast -o /tmp/lowerfix_base/emit/$n $e
done
```

Expected: 6 output dirs, rc=0 each. Record `find /tmp/lowerfix_base/emit -name '*.c' -o -name '*.h' | LC_ALL=C sort | xargs md5sum` to `/tmp/lowerfix_base/emit.md5`.

- [ ] **Step 3: Record the defect reproductions at 8 MB and 1 MB stack**

Run each of the 6 entries at `ulimit -s 8192` and `ulimit -s 1024`. Record rc for each in `/tmp/lowerfix_base/stack_matrix.txt`.
Expected: `emission_sibling_payload_xmod` is rc=0 at 8 MB, **rc=139 at 1 MB**. That rc=139 is the defect this plan fixes.

- [ ] **Step 4: Commit nothing. Report the baseline paths.**

---

### Task 1: Continuation-stack infrastructure + depth guard

**Files:**
- Modify: `sf/src/lower.zig` (`LirLowerer` struct at `:324`, new ArrayList block near `DeferActionArrayList` at `:146`)
- Test: `scripts/compiler/gate_lower_depth.sh` (new)

**Interfaces:**
- Consumes: `arrayListEnsureCapacityBytes` (already used at `:164`, `:196`), `TEMP_NONE` (`:70`), `Sand` arena
- Produces: `ExprFrame`, `ExprFrameArrayList` + `exprFrameArrayList{Init,EnsureCapacity,Append,GetSlice}`, `LirLowerer.expr_stack: ExprFrameArrayList`, `LirLowerer.expr_guard: u32`, `fn lowerExprDriver(self: *LirLowerer, root: u32) u32`, `fn lowerExprDepthGuard(self: *LirLowerer) void`

`ExprFrame` fields (exact names, for later tasks):
```
node_idx: u32       // the expression node being lowered
phase: u16          // resume point within the arm (0 = not yet entered)
slot0: u32          // saved child temp / local across the child call
slot1: u32
slot2: u32
slot3: u32
kind: u32           // AstKind as u32, cached to avoid re-fetch
```

- [ ] **Step 1: Write the failing test**

Create `scripts/compiler/gate_lower_depth.sh` asserting:
1. `repro/mi_matrix/emission_sibling_payload_xmod/main.zig` compiles rc=0 under `ulimit -s 1024` (today: rc=139 — this is RED).
2. A generated 200-deep nested-block fixture compiles rc=0 under `ulimit -s 1024` (RED today).
3. A generated 200-deep nested-expression fixture compiles rc=0 under `ulimit -s 1024`.
4. `error[3048]`/clean-error, not a segfault, if the depth guard trips.
5. All four 8-pin entries still emit and their `--dump-c89` md5 match the QUICK_REF 8-pin table.

Fixtures live in a mktemp dir and are cleaned up. Script executable.

- [ ] **Step 2: Run the gate to confirm it fails**

Run: `bash scripts/compiler/gate_lower_depth.sh /tmp/lowerfix_base/zig1_5_clean`
Expected: FAIL on cases 1 and 2 with rc=139. Cases 3-5 PASS.

- [ ] **Step 3: Implement `ExprFrame`, `ExprFrameArrayList`, `LirLowerer.expr_stack`, `LirLowerer.expr_guard`**

Mirror the `DeferActionArrayList` idiom at `:146-176` exactly (same `arrayListEnsureCapacityBytes` call shape, same `GetSlice`). `ExprFrameArrayList` stores `ExprFrame` by value. `expr_guard: u32` is a recursion counter, init `0` in `lowererInit` (`:613` region, where `pending_scope = TEMP_NONE` is set).

- [ ] **Step 4: Implement `lowerExprDepthGuard`**

Signature `fn lowerExprDepthGuard(self: *LirLowerer) void`. Increments `expr_guard`; if it exceeds `EXPR_GUARD_MAX` (const `2048`), report a clean diagnostic through the existing diag collector family (`diag_mod.ErrorCode.ERR_3048_CANNOT_READ_FILE` is wrong here — use the ICE/limit family already used for compiler limits) and leave the guard elevated so the caller unwinds. This is the safety net for any path not yet converted; it must never fire on legal input in the final state.

- [ ] **Step 5: Implement `lowerExprDriver` as a thin wrapper that still calls the existing recursive `lowerExpr`**

In this task the driver simply calls `lowerExpr(self, root)` inside a guard bracket. The recursion is replaced in Tasks 2-3. This keeps the tree green while infrastructure lands.

- [ ] **Step 6: Run gate to confirm cases 3-5 still pass and 1-2 still fail**

Run: `bash scripts/compiler/gate_lower_depth.sh /tmp/lowerfix_base/zig1_5_clean`
Expected: unchanged from Step 2 (infrastructure only, behavior identical).

- [ ] **Step 7: Confirm byte-identity**

Re-emit the 6-entry gate set with the modified compiler, `diff -r` against `/tmp/lowerfix_base/emit/`.
Expected: identical.

- [ ] **Step 8: Commit**

```bash
git add sf/src/lower.zig scripts/compiler/gate_lower_depth.sh
git commit -m "feat(lower): continuation-stack infrastructure + depth guard"
```

---

### Task 2: Post-order expression arms to the continuation stack

**Files:**
- Modify: `sf/src/lower.zig` (`lowerExprImpl` arms at `:4561`-`:7763`, `lowerBinaryArm` at `:4156`, `lowerExpr` at `:2102`)
- Test: `scripts/compiler/gate_lower_depth.sh` (extend), byte-identity diff

**Interfaces:**
- Consumes: `ExprFrame`, `expr_stack`, `lowerExprDriver` from Task 1
- Produces: `fn lowerExprStep(self: *LirLowerer) u32` (the per-kind resumable step), `fn lowerExprPushChild(self: *LirLowerer, parent: *ExprFrame, child: u32, phase: u16) void`

Scope of this task: the **129 post-order arms** — the shape `lhs = lowerExpr(child_0); rhs = lowerExpr(child_1); <emit>`. This includes `add`/`sub`/`mul`/`div`/`mod_op` (`:4746`-`:4815`), the comparison ops (`:4857`-`:4886`), `bit_and`/`bit_or`/`bit_xor` via `lowerBinaryArm` (`:4156`), wrap/sat arith, unary ops, casts, `paren_expr` (`:4739`), and the literal/leaf kinds (`int_literal` `:4597`, `float_literal`, `string_literal`, `char_literal`) which have no children.

- [ ] **Step 1: Write the failing test**

Extend `gate_lower_depth.sh` with case 6: a generated **runtime-valued, not literal-folded** 300-term left-deep `+` chain compiles rc=0 under `ulimit -s 1024`, and its `--dump-c89` md5 equals the same source compiled by `/tmp/lowerfix_base/zig1_5_clean` at 8 MB stack. (RED: today it dies at 1 MB.)

Fixture shape (validated): each term is a `u32` local seeded from a function call (`var aN: u32 = @intCast(u32, getv(7));` where `fn getv(x: u32) u32 { return x; }`) so `lowerFoldedIntConst` (`sf/src/lower.zig:4006`) cannot fold the chain — a literal-only chain folds to one const and proves nothing. Measured RED: 300 terms segfaults at **both** 8 MB and 1 MB; 30 terms is the 1 MB threshold, 120 terms the 8 MB threshold.

- [ ] **Step 2: Run to confirm RED**

Run: `bash scripts/compiler/gate_lower_depth.sh /tmp/lowerfix_base/zig1_5_clean`
Expected: case 6 FAIL (rc=139 at 1 MB).

- [ ] **Step 3: Implement `lowerExprPushChild` and the frame resume protocol**

`lowerExprPushChild(self, parent, child, phase)`: saves `parent` back onto `expr_stack` with `phase` set, pushes a fresh frame for `child` with `phase = 0`. The driver loop pops the top frame, runs `lowerExprStep` on it, and on completion writes the result temp into the parent frame's next free slot and re-enters the parent at its saved phase.

- [ ] **Step 4: Convert the post-order arms**

For each post-order arm, replace the two `lowerExpr(child_N)` calls with `lowerExprPushChild` and a phase label. The arm's emit block becomes the phase body. Example for `add` (`:4746`):

- phase 0: `resolveRtypeOrU32`, `lowerFoldedIntConst` (unchanged — these do not recurse), then push `child_0` at phase 1
- phase 1: `slot0 = result`; push `child_1` at phase 2
- phase 2: `slot1 = result`; run the original emit block (`nextTemp`, markers, `emitArith`) and return the tid

**The emit block must stay byte-for-byte in its original order relative to the child evaluations.** Do not move marker writes.

- [ ] **Step 5: Route `lowerExpr` through `lowerExprDriver`**

`lowerExpr` becomes: bracket the guard, push root frame, run driver, apply the coercion block (`:2113`-`:2141`) unchanged on the returned temp. `lowerExprImpl` keeps its name but its converted arms become `lowerExprStep` cases.

- [ ] **Step 6: Run gate**

Run: `bash scripts/compiler/gate_lower_depth.sh <new zig1>`
Expected: cases 1-6 all PASS (interleaved arms still recursive — case 2 may still fail; that is Task 3).

- [ ] **Step 7: Byte-identity gate**

Re-emit the 6-entry gate set, `diff -r` against `/tmp/lowerfix_base/emit/`.
Expected: identical. If any file differs, STOP and report the diff — do not re-baseline.

- [ ] **Step 8: Full corpus byte-identity**

Run the 1188-dir corpus with the new compiler; assert class file md5 equals `67f7ea9a169ea6147cd0512753bc24dd` (post-spill-fix baseline) and 0 movers.

- [ ] **Step 9: Commit**

```bash
git add sf/src/lower.zig scripts/compiler/gate_lower_depth.sh
git commit -m "feat(lower): post-order expression arms on the continuation stack"
```

---

### Task 3: Interleaved expression arms on the continuation stack

**Files:**
- Modify: `sf/src/lower.zig` (the 32 interleaved arms: `bool_or` `:4890`, `bool_and` `:4913`, `fn_call` `:5764`, slice expr `:7573`, `if`/`switch`, async frame, struct-init `:6166`, `:6301`, `:6361`, `:6386`, `:6537`, `:6572`, `:6612`, `:7010`, `:7311`)
- Test: `scripts/compiler/gate_lower_depth.sh` (extend), byte-identity diff

**Interfaces:**
- Consumes: Task 2's `lowerExprStep`, `lowerExprPushChild`, `ExprFrame` slots
- Produces: phase states for the interleaved arms; `lowerPreallocArgs` (`:4182`) ordering preserved

- [ ] **Step 1: Write the failing test**

Extend `gate_lower_depth.sh` with:
- case 7: 200-deep `a and b and c and ...` chain compiles rc=0 under `ulimit -s 1024`, `--dump-c89` md5 equals the 8 MB baseline.
- case 8: a call whose **argument is a deep `+` chain** — `sink(a0 + a1 + ... + a299)` with the same runtime-valued locals as case 6 — compiles rc=0 under `ulimit -s 1024`, `--dump-c89` md5 equals baseline.

  **Why not a call chain:** Z98 has no method-call syntax and no callable-returning-callable (`id(id)(7)` is `error[3000]` type mismatch). Nested `f(g(h(...)))` is parser-blocked: `sf/src/parser.zig:373-378` sets `expr_depth > 12` -> `panic: max expression recursion depth exceeded` (measured: depth 20 panics at parse, before lowering). A 120-arg call is also blocked (`MAX_FN_PARAMS` = 64). So the deep-`+`-inside-a-call shape is the only one that (a) parses at depth 2 and (b) drives the `fn_call` arm's interleaved preallocArgs/arg-lowering ordering while recursing deeply through the arg.
- case 9: an `if` **expression** whose branches are deep `+` chains — `var r: u32 = if (c) <chain> else <chain>;` with `var c: bool = true;` and the same runtime-valued locals as case 6 — rc=0 at 1 MB, `--dump-c89` md5 equals the 8 MB baseline.

  **Why not nested `if` expressions:** `if (c) if (c) ... else ...` is expression nesting and is parser-blocked at depth 12 (`sf/src/parser.zig:373-378`), measured: depth 40 panics at parse before lowering. The branch-chain shape parses at depth 3 and still drives the `if` arm's interleaved cond/branch lowering. Note the condition must be `bool` — a `u32` condition is `error[3058]`.

- [ ] **Step 2: Run to confirm RED**

Expected: cases 7-9 FAIL at 1 MB.

- [ ] **Step 3: Convert `bool_and` / `bool_or`**

These are the order-critical ones. Original shape (`:4890`): lower `lhs`; `createBlock` x3; `nextTemp`; **emit `branch`**; set `current_bb = rhs_bb`; lower `rhs`; emit `assign` + `jump`; set `current_bb = true_bb`; emit `bool_const` + `jump`; set `current_bb = done_bb`; return `result`.

Phase split: phase 1 resumes after `lhs` is in `slot0`, and must run the block creation + `branch` emit + `current_bb` switch **before** pushing `child_1`. The `createBlock` results must be saved into `slot1`/`slot2`/`slot3` so phase 2 can use them. The `current_bb` and `block_terminated` mutations must happen in the same relative position.

- [ ] **Step 4: Convert `fn_call`**

Critical ordering: `lowerPreallocArgs(self, ec_n)` (`:4182`, at `:5824` region) reserves arg temps **before** the args are lowered. Phase 1 must run `lowerPreallocArgs` and save `args_start` into a slot, then push `child_0` (callee) and each arg in order. The print-fmt special path (`lowerPrintFmt`, `:4196` region) and `lowerCallArgMaterialize` (`:4196`) keep their relative positions.

- [ ] **Step 5: Convert the remaining interleaved arms**

slice expr (`:7573`), `if` expr (`:7010`), `switch`, async frame (`:6386`, `:6537`), struct-init (`:6166`), tuple/array literals (`:7311`), and the rest of the 32. Each keeps its emits in the original position relative to its `lowerExpr` calls.

- [ ] **Step 6: Run gate — all 9 cases**

Run: `bash scripts/compiler/gate_lower_depth.sh <new zig1>`
Expected: 9/9 PASS.

- [ ] **Step 7: Byte-identity + full corpus**

6-entry `diff -r` vs `/tmp/lowerfix_base/emit/` identical; corpus class file md5 `67f7ea9a169ea6147cd0512753bc24dd`, 0 movers; goldens 5/5; **8 pins unchanged**; markers 3252/37293; examples 26/26; stdlib 336/0 + crosscheck 10/10.

- [ ] **Step 8: Windows validation**

Build MinGW CRT `zig1.exe` from the new compiler (`-osw -ffast`, then `i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32`), run the 1188-dir corpus under Wine. Expected: 1014 OK / 58 GREEN / 116 FAIL (matching Linux). The `emission_sibling_payload_xmod` dir must now be **OK** (was CRASH). Reap Wine zombies (`wineserver -k`) when the PID table clogs.

- [ ] **Step 9: Commit**

```bash
git add sf/src/lower.zig scripts/compiler/gate_lower_depth.sh
git commit -m "feat(lower): interleaved expression arms on the continuation stack"
```

---

### Task 4: Statement recursion on the continuation stack

**Files:**
- Modify: `sf/src/lower.zig` (`lowerStmt` `:7895`, `lowerStmtBody` `:7871`, `lowerExprOrBlock` `:7843`, `lowerIfArmValue` `:7834`)
- Test: `scripts/compiler/gate_lower_depth.sh` (extend)

**Interfaces:**
- Consumes: Tasks 1-3 frame infrastructure
- Produces: `StmtFrame` or reuse `ExprFrame` with a discriminator, `lowerStmtDriver`

- [ ] **Step 1: Write the failing test**

Extend `gate_lower_depth.sh` with:
- case 10: 300-deep nested blocks `{ { { ... } } }` rc=0 under `ulimit -s 1024`.
- case 11: 300-deep nested `if` statements rc=0 at 1 MB.
- case 12: 300-deep nested labeled/loop statements rc=0 at 1 MB.
Each also asserts `--dump-c89` md5 equals the 8 MB baseline from `/tmp/lowerfix_base`.

- [ ] **Step 2: Run to confirm RED**

Expected: cases 10-12 FAIL at 1 MB (18 KB `lowerStmt` frame × depth).

- [ ] **Step 3: Convert `lowerStmt` block recursion (`:7910`)**

`block` iterates extra children calling `lowerStmt` on each. Convert the loop to push child statement frames onto the same stack with a loop-index phase, so the `expandDefers`/`popScopeDepth` at the end still run after all children.

- [ ] **Step 4: Convert `labeled_stmt` (`:7924`, `:7931`), `lowerStmtBody` (`:7871`), `lowerExprOrBlock` (`:7843`), `lowerIfArmValue` (`:7834`)**

Same pattern. `LoopInfo` push/pop (`loop_stack`) must keep its relative position to the child lowering.

- [ ] **Step 5: Run gate — all 12 cases**

Expected: 12/12 PASS.

- [ ] **Step 6: Full battery + byte-identity**

6-entry `diff -r` identical; corpus 1014/58/116 md5 `67f7ea9a169ea6147cd0512753bc24dd` 0 movers; goldens 5/5; pins 8/8; markers 3252/37293; examples 26/26; stdlib 336/0 + crosscheck 10/10.

- [ ] **Step 7: Commit**

```bash
git add sf/src/lower.zig scripts/compiler/gate_lower_depth.sh
git commit -m "feat(lower): statement recursion on the continuation stack"
```

---

### Task 5 (extra, operator-requested): Split `lowerExprImpl` to shrink the C frame

**Files:**
- Modify: `sf/src/lower.zig` (`lowerExprImpl` `:4561`-`:7763`)
- Test: `scripts/compiler/gate_lower_depth.sh` (extend), `-fstack-usage` measurement

**Interfaces:**
- Consumes: Tasks 2-3's `lowerExprStep` per-kind cases
- Produces: per-kind functions `lowerExprLit`, `lowerExprBinary`, `lowerExprCmp`, `lowerExprUnary`, `lowerExprCast`, `lowerExprCall`, `lowerExprField`, `lowerExprIndex`, `lowerExprSlice`, `lowerExprIf`, `lowerExprSwitch`, `lowerExprStructInit`, `lowerExprMisc`

- [ ] **Step 1: Write the failing test**

Extend `gate_lower_depth.sh` with case 13: measure the emitted C frame of the lowerer with `gcc -m32 -std=c89 -O0 -fstack-usage` and assert `lowerExprImpl`/`lowerExprStep`'s largest frame is **< 8192 bytes**. (RED: today `lowerExprImpl` is 70,320.)

- [ ] **Step 2: Run to confirm RED**

Expected: measured 70,320 > 8192.

- [ ] **Step 3: Split by kind**

Move each kind group out of `lowerExprImpl` into its own `fn lowerExpr*(self: *LirLowerer, node_idx: u32, fr: *ExprFrame) u32`. `lowerExprStep` becomes a dispatch on `fr.kind`. Marker writes stay with their arms, byte-for-byte.

- [ ] **Step 4: Measure again**

Run: `gcc -m32 -std=c89 -O0 -fstack-usage` on the emitted lowerer C.
Expected: largest frame < 8192 bytes.

- [ ] **Step 5: Full battery + byte-identity**

6-entry `diff -r` identical; corpus 1014/58/116 0 movers; goldens 5/5; pins 8/8; markers 3252/37293; examples 26/26; stdlib 336/0 + crosscheck 10/10.

- [ ] **Step 6: Commit**

```bash
git add sf/src/lower.zig scripts/compiler/gate_lower_depth.sh
git commit -m "refactor(lower): split lowerExprImpl by kind (70 KB -> <8 KB frame)"
```

---

### Task 6: Closeout — seed rotation

**Files:**
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `release/seed/CHANGELOG.md`
- Test: two-hop closure

- [ ] **Step 1: Rebuild from the committed seed and measure F_new**

Run: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/lowerfix_close`
Expected: `=== [seed] Done: ... ===`, hop1 == hop2 == **F_new** (will move — compiler source changed). Record F_new.

- [ ] **Step 2: Full battery on the F_new compiler**

corpus 1014/58/116 frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` 0 movers; goldens 5/5; pins 8/8; markers 3252/37293; examples 26/26; stdlib 336/0 + crosscheck 10/10; `gate_lower_depth.sh` 13/13; `gate_reserved_names.sh` PASS; `gate_debug_map.sh` PASS.

- [ ] **Step 3: Rotate the seed**

Run: `bash scripts/seed/archive_seed.sh /tmp/lowerfix_close/zig1_5_clean /tmp/lowerfix_close/gen release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`

Then **verify the CHANGELOG entry's status lines are accurate** (a stale "not app-ready" claim shipped in v121 and had to be corrected — do not repeat that). Patch the recorded archive/zip md5s if the regenerated archives differ from what the entry claims.

- [ ] **Step 4: Commit**

```bash
git add release/seed/
git commit -m "chore(seed): rotate v123 (iterative lowering)"
```

- [ ] **Step 5: Report. Do not push.**
