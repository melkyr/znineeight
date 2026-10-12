# TCO (Tail Call Optimization) — Design Spec

**Date:** 2026-08-02
**Status:** Draft
**Branch:** `zig1_start` (base `44ccc246`)
**Feature:** Real compiler TCO — detect tail-call positions in the lowerer and emit jump-based elimination for self-recursion; `tail_call` LIR for cross-function calls (future backend lowering).

## 1. Goal

Enable Z98 functions to perform deep recursion without C-stack exhaustion. The compiler automatically detects calls in tail position and emits jumps instead of frame-preserving calls.

## 2. Architecture

Three-layer design:

| Layer | Self-recursion | Cross-function |
|-------|---------------|----------------|
| Lowerer | Detect `return self(args...)` in tail pos → arg rebind + `jump loop_header` | Emit new `tail_call` LIR variant |
| LIR | Existing `loop_header` variant (activate) + new `tail_call` variant | `tail_call: { callee, module_id, args, result, is_indirect }` |
| C89 emitter | `loop_header` → `tco_restart:` label; `jump` → `goto tco_restart;` | `tail_call` → `call_direct`/`call` + `ret` (semantic fallback; no C89-level optimization yet) |

No function wrappers. No `while(1)` trampoline. A single label at the function entry body, and gotos for self-recursion.

### LIR Variants

**Existing — to be activated:**
```zig
loop_header: u32,           // lir.zig:31 — block ID for jump target
```

**New — to be added:**
```zig
tail_call: struct {
    callee: u32,            // name_id (direct) or temp (indirect)
    module_id: u32,         // 0 for indirect, module_id for direct
    args_start: u32,
    args_count: u32,
    result: u32,            // 0 for void
    return_type: u32,       // TypeId
    is_indirect: u8,        // 0=direct, 1=indirect
}
```

## 3. Tail Position Detection (Lowerer)

When lowering `return_stmt` (lower.zig:3614-3634), after `expandDefers` fires, inspect the return expression:

| Pattern | Self case | Cross-function case |
|---------|-----------|---------------------|
| `return self(args...)` — call_direct to `self.func.name_id` + `self.func.module_id` | TCO: arg rebind + `jump loop_header` | N/A (is self) |
| `return try self(args...)` — same, through try unwrap | Same. `try` unwraps in flight; self has same return type → jump works | N/A |
| `return otherFn(args...)` — call_direct to different function | N/A | Emit `tail_call` LIR |
| `if(cond) return a() else return b()` — both branches tail | Each tail-call branch gets own TCO/jump | Each gets `tail_call` |
| Non-call return | Normal `ret val` (unchanged) | Normal `ret val` |

### Try Interaction

`return try self(args...)` lowerer expansion (simplified):
```
call_direct self → result_temp
check_error → branch → unwrap → ret unwrapped_val
```

Detection walks backward: the `ret` temp is the `try`-unwrapped value of `call_direct result`. The lowerer detects the self-call underneath the try chain. TCO arg rebind happens, then `jump header` — the function body naturally produces the error-union return. No special unwrap handling needed.

### Defer Interaction

`expandDefers` fires **before** TCO detection (existing behavior, unchanged). `defer { cleanup(); } return f();` → cleanup executes, then TCO jump. Correct: defers must run before the logical call.

## 4. Self-Recursion TCO Mechanism

Lowerer emits this LIR sequence in tail position:

```
assign local_param1 = arg_temp0
assign local_param2 = arg_temp1
...
jump loop_header_bb
```

Where `loop_header_bb` is the entry block, with a `loop_header` instruction at its start.

### Loop Header Injection

During `lowerFn`, after creating the entry basic block, inject `loop_header(header_bb_id)` as the first instruction of that block. The header block ID = entry block ID (whatever the convention is for the first basic block).

### Parity Guard

At detection time, verify `call.args_count == self.func.params.len`. Mismatch is impossible for well-typed Z98 but falls back to `call_direct + ret` if it occurs (defensive).

## 5. C89 Emitter Changes

Minimal — reuse existing infrastructure.

### loop_header (currently no-op at c89_emit.zig:2754)

```zig
.loop_header => |hdr| {
    emitLabel("tco_restart");
}
```

The label `tco_restart:` goes **after** temp declarations and local variable declarations, at the start of the first basic block's body. This avoids C89's restriction on jumping past declarations containing initializers.

### tail_call (new)

```zig
.tail_call => |tc| {
    // Fallback: emit as regular call + return
    // Semantic equivalent for C89 — no real optimization
    emitCallAndReturn(tc);
}
```

Emits the same C code as `call_direct`/`call` followed by `ret`. The LIR variant preserves tail semantics for future backends (asm).

### Existing patterns reused (no new emitter logic)

- `goto`/`label` — already used for all jumps/branches
- `assign` — already used for temp assignment
- `call_direct`/`call` — already used for function invocation
- `ret` — already used for return statements

## 6. Scope

### In Scope
- Tail-position detection in `lower.zig` (`return_stmt` lowering)
- Self-recursion jump-based TCO (arg rebind + goto header)
- `tail_call` LIR variant in `lir.zig`
- C89 emitter wiring for `loop_header` (activate) and `tail_call` (fallback)
- `try` unwrapping detection for `return try self(...)`
- Defer interaction (defers execute before TCO, unchanged)
- Multi-branch tail-position detection (`if`/`switch`)

### Out of Scope
- C89-level cross-function TCO (limited to fallback `call+ret`)
- `loop_header` lowering in the lowerer for non-TCO uses (only TCO emits it)
- ABI-level changes for calling convention compatibility
- Wasm/asm backends (only C89 in this pass)
- Handling of extern functions (never self-recursive)

## 7. Success Criteria (Gates)

| # | Gate | How |
|---|------|-----|
| 1 | Build 0 errors, self-host | `bash sf/scripts/build_release.sh` → `=== [release] Done ===` |
| 2 | Stdout md5s preserved | mud `5fb57e70c2d637276ab0264c1401cd0d`, gol `f855c9f93c73422f56378f3f73231727`, lisp `0ad0204088f91c1eae7c040da8f99a1c`, json `11a5db1d3d43acf4880e2d157590abe3` all byte-identical |
| 3 | TCO repro: deep recursion works | `factorial(100000)` via accumulator pattern produces correct result without stack overflow |
| 4 | Lisp runtime | `(+ 1 2)` → `> 3`, no regression |
| 5 | Multi-module lisp | 10-module `--output-dir` build still links and runs `> 3` |
| 6 | `tail_call` compiles clean | Any cross-function tail call emits valid C89; gcc -Wall -Werror |
| 7 | Corpus no regressions | Same A/B OK/FAIL/ICE/CRASH counts at `165/15/6/0` |
| 8 | TCO block terminates | No duplicate code emission after TCO jump (block_terminated=1) |

## 8. File Impact

| File | Change |
|------|--------|
| `sf/src/lir.zig` | Add `tail_call` variant to `LirInst` union; adjust `LirInst` format functions |
| `sf/src/lower.zig` | Tail-position detection in `return_stmt` lowering; `loop_header` injection in `lowerFn` entry block |
| `sf/src/c89_emit.zig` | Activate `.loop_header` case; add `.tail_call` case; wire label emission after temp declarations |
| `sf/docs/tech_docs/07_lir_lowering.md` | Update TCO section — remove "not implemented", document new behavior |
| `sf/docs/tech_docs/08_c89_emission.md` | Document `loop_header` and `tail_call` emission |
| `docs/sf/QUICK_REF.md` | Add TCO gate recipes |
