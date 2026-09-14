# Z98 Async Compiler Core (Track 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement umbrella async Stages 1–4 in the Z98 self-hosted compiler — program-wide suspension analysis, LIR frame layout, the LIR-to-LIR `_step` state-machine transform, and the four `@async*` builtins with explicit diagnostics — so that Track 3 (`std.async`) has a working runtime/builtin surface.

**Architecture:** A new pre-lowering AST pass (`phase_SuspensionAnalysis`, after `phase_SymbolRegistration`) computes a monotone `is_suspending` fixed point and the authoritative flat frame-size table, both stored in `CompilerContext` side tables. A new LIR pass (between `lowerFn` and `lirStreamAppend`) lays out each suspending function's frame on the existing block CFG using the `lir_opt_pass` read/write-locator pattern, then rewrites the function into a `switch_br` `_step` state machine that saves/restores live values through `load_field`/`store_field`, reads `ctx` from the current frame, and allocates child frames from a per-task LIFO frame stack. Sema registers/typing-checks the four builtins and emits the new numeric diagnostics; lowering dispatches them.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), gcc `-m32 -std=c89`, bash, git. Build via `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` (seed/forward path) or `bash sf/scripts/build_release.sh` (current-cycle while it still compiles `sf/src`).

## Global Constraints

- **Baseline (re-verify at Task 1; refreshed by Amendment 1):** branch `zig1_improvements`; HEAD `0c0e81f5`; compiler fixed point `de7137e04d62435c74e7b15281cb4540`; seed v14 archive md5 `9e6c9faad0536191f28eb60c210a0a25`; corpus 580 = 545 OK / 32 GREEN / 3 FAIL (3 `callconv_*` emission-inspection expected FAILs); `repro/mi_matrix/EXPECTED_FAIL.md` header v79. (The pre-Track-1 values are superseded; see Amendment 1.)
- **`timeout 120` on every binary execution.**
- **Binding gcc flag set for every `gcc -c`/link:** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. The fixed point reproduces only with `-Wall` present.
- **Compiler builds:** seed/forward path `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>` (gate `=== [seed] Done: <fresh_out> ===`, result `<fresh_out>/zig1_5_clean`); never invoke `zig0`. Current-cycle `bash sf/scripts/build_release.sh` (gate `=== [release] Done: sf/build/out_release/zig1 ===`) is allowed while it still compiles `sf/src`.
- **Fixture build/run recipe:** `sf/build/out_release/zig1 --dump-c89 --output-dir DIR repro/.../main.zig`, then compile every `DIR/*.c` with the flag set; classify by gcc exit code, never by empty stderr (`docs/sf/QUICK_REF.md:134-145`). For a runnable fixture link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files). Never stage `mnemoria/` or `.zig1_*.tmp`.
- **Z98 source constraints:** no generics/`@Type`/`anytype`; explicit `@intCast`; concrete maps only; `switch` needs `else`; `@panic` prints then traps; use the `var msg: []const u8 = "...";` pattern for `pal.stderr_write`.
- **Sema/lowering safety modes:** `-fsafe` is the default; every new check is mode-gated so `-ffast` bytes stay unchanged where the feature is absent. Do not change `SPILL_COUNT` (`sf/src/spill_store.zig:16`) or `-s0..-s5`.
- **Single source of truth:** `frame_sizes[key]` is written only by `phase_SuspensionAnalysis` and read by Stage 2, Stage 3, and `@asyncFrameSize`. No second writer.
- **Diagnostic codes:** every new `ErrorCode` member is appended with an explicit `= NNNN`; preserve ICE `3043` and `ERR_3048_CANNOT_READ_FILE = 3048`.
- **Seed rotation is closeout-only, and only if the fixed point moved:** `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`. Never rotate mid-plan.
- **STOP-present** after each task that says so; await GO before the next task.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-async-compiler-core-design.md`. This plan is amendable in place.

---

**Sequence:** Previous plan: [`../plans/2026-09-13-win9x-calling-convention-plan.md`](../plans/2026-09-13-win9x-calling-convention-plan.md); Next plan: [`../plans/2026-09-13-std-async-plan.md`](../plans/2026-09-13-std-async-plan.md); subspec: [`../specs/2026-09-13-async-compiler-core-design.md`](../specs/2026-09-13-async-compiler-core-design.md).

## File Structure

- `sf/src/diagnostics.zig` — append explicit `ErrorCode` members (`3017/3018/3019/3046`, optional `3047`). Shared by both tracks.
- `sf/src/async_analysis.zig` — **new**: `phase` body, `asyncKey`, `asyncIsSuspending`, `asyncFrameSizeOf`, AST edge extraction, worklist, frame-size bound.
- `sf/src/async_lowering.zig` — **new**: `AsyncFrameLayout`, `AsyncFrameField`, `asyncLayoutFrame` (Stage 2), `asyncTransform` (Stage 3).
- `sf/src/main.zig` — `CompilerContext` side-table fields + init; register `phase_SuspensionAnalysis` (`:290/:291`); call the Stage 2/3 async pass around `:719-722`.
- `sf/src/lower.zig` — `materializeFnRef` + `ERR_3017`; interning/builtin dispatch for the four `@async*` builtins (`:356-568, 3911`).
- `sf/src/semantic_analyzer.zig` — builtin name ids/interning/allow-list/typing; `ERR_3018/3019/3046`; `defer_depth`.
- `sf/src/lir.zig` — optional 12-byte ops appended after `width_wrap` (`:167`); no mandatory new variant.
- Fixtures: `repro/mi_matrix/async_callgraph_xmod/`, `async_fnptr_error_xmod/`, `async_frame_xmod/`, `async_await_xmod/`, `async_builtin_scope_xmod/`, each with `main.zig` (+ `lib.zig` for the cross-module ones).

---

### Task 1: Explicit numeric diagnostic codes

**Files:**
- Modify: `sf/src/diagnostics.zig:46-47, 72`
- Test: fixture not needed (compile-time enum check)

**Interfaces:**
- Consumes: `ErrorCode: enum(u16)` auto-increment behavior (`diagnostics.zig:10-73`).
- Produces: enum members `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017`, `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018`, `ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019`, `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046`, `WARN_3047_ASYNC_FRAME_LARGE = 3047`.

- [ ] **Step 1: Write the failing test**

There is no runtime test; the red state is a code edit that appends the members. Verify the current gaps exist first:

Run:
```bash
cd /workspace/znineeight
grep -n "ERR_3016\|ERR_3020\|ERR_3048" sf/src/diagnostics.zig
```
Expected: `3016` explicit at line 46, `ERR_3020_UNHANDLED_NODE_KIND = 3020` at line 47, `ERR_3048_CANNOT_READ_FILE = 3048` at line 72. `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017` and `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` ALREADY EXIST (Track 1, lines 73-74); the absent members to add are `3018/3019/3046/3047` (do NOT re-append `3017`).

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/asynct2/t1 /dev/null 2>&1 | head -1
grep -c "ERR_3017_SUSPENDING_FUNCTION_POINTER" sf/src/diagnostics.zig
```
Expected: `grep -c` prints `0` (member absent).

- [ ] **Step 3: Write minimal implementation**

Append the members at the end of the `ErrorCode` enum, immediately before the closing `};` (after `ERR_3048_CANNOT_READ_FILE = 3048,` at line 72). Every member carries an explicit value:

```zig
    ERR_3048_CANNOT_READ_FILE = 3048,
    // ASYNCTRACK2 — explicit numeric values; never bare auto-increment members.
    // Amendment 1: ERR_3017=3017 and ERR_3045=3045 ALREADY EXIST (Track 1);
    // do NOT re-append them. Add only the absent members below.
    ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018,
    ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019,
    ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046,
    WARN_3047_ASYNC_FRAME_LARGE = 3047,
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
grep -n "= 3017\|= 3018\|= 3019\|= 3046\|= 3047" sf/src/diagnostics.zig
bash sf/scripts/build_release.sh 2>&1 | tail -3
```
Expected: the four/five members present with explicit values; build prints `=== [release] Done: sf/build/out_release/zig1 ===`. If the build reports a duplicate tag, a value collided — STOP and re-check occupied codes.

- [ ] **Step 5: Commit**

```bash
git add sf/src/diagnostics.zig
git commit -m "feat: explicit async diagnostic codes 3017/3018/3019/3046 (ASYNCTRACK2)"
```

---

### Task 2: Stage 4 surface — builtin registration, typing, and dispatch placeholders

**Files:**
- Modify: `sf/src/semantic_analyzer.zig:64-93, 99-159, 257-298, 2087-2219`
- Modify: `sf/src/lower.zig:356-426, 428-568, 3911`
- Test: `repro/mi_matrix/async_builtin_scope_xmod/main.zig`, `async_callgraph_xmod/main.zig` (created here; used again in Tasks 3/5)

**Interfaces:**
- Consumes: Task 1 codes; `semanticAnalyzerInit` signature (`semantic_analyzer.zig:97`); `LirLowerer`/`lowererInit` (`lower.zig:356, 428`).
- Produces: name ids `async_frame_size_name_id`, `async_init_name_id`, `async_resume_name_id`, `async_suspend_name_id`; sema typing; `ERR_3018`/`ERR_3019`; lowering placeholder arms (`@asyncFrameSize`→`int_const 0`, `@asyncInit`→null pointer, `@asyncResume`→null, `@asyncSuspend`→null pointer).

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/async_builtin_scope_xmod/main.zig`:

```zig
fn plain_caller() void {
    @asyncSuspend(null);
}

pub fn main() void {
    plain_caller();
}
```

Create `repro/mi_matrix/async_callgraph_xmod/lib.zig`:

```zig
pub fn leaf() void {
    @asyncSuspend(null);
}
pub fn mid() void {
    leaf();
}
pub fn top() void {
    mid();
}
pub fn explicit_only() void {
    @asyncSuspend(null);
}
```

Create `repro/mi_matrix/async_callgraph_xmod/main.zig`:

```zig
const lib = @import("lib.zig");

fn use_sizes() void {
    var a: u32 = @asyncFrameSize(lib.top);
    var b: u32 = @asyncFrameSize(lib.explicit_only);
    var c: u32 = @asyncFrameSize(lib.mid);
    _ = a; _ = b; _ = c;
}

pub fn main() void {
    use_sizes();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
OUT=/tmp/asynct2/t2; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_builtin_scope_xmod/main.zig 2>&1 | tail -5
echo "rc=$?"
```
Expected RED: `error[3000]`/`error[3013]`-class unknown-builtin diagnostic (the builtins are not in the allow-list, `semantic_analyzer.zig:257-298`), dump rc nonzero, 0 `.c` files.

- [ ] **Step 3: Write minimal implementation**

In `sf/src/semantic_analyzer.zig`, add four fields after `console_set_color_name_id` (line 93):

```zig
    async_frame_size_name_id: u32,
    async_init_name_id: u32,
    async_resume_name_id: u32,
    async_suspend_name_id: u32,
```

In `semanticAnalyzerInit` (line 97), after `csc_id` (line 159), intern them:

```zig
    var afs_s: []const u8 = "@asyncFrameSize";
    var afs_id = interner_mod.stringInternerIntern(interner, afs_s);
    var ain_s: []const u8 = "@asyncInit";
    var ain_id = interner_mod.stringInternerIntern(interner, ain_s);
    var ars_s: []const u8 = "@asyncResume";
    var ars_id = interner_mod.stringInternerIntern(interner, ars_s);
    var asu_s: []const u8 = "@asyncSuspend";
    var asu_id = interner_mod.stringInternerIntern(interner, asu_s);
```

and set them in the returned struct literal (near `.console_set_color_name_id = csc_id,`):

```zig
    .async_frame_size_name_id = afs_id,
    .async_init_name_id = ain_id,
    .async_resume_name_id = ars_id,
    .async_suspend_name_id = asu_id,
```

In `semanticAnalyzerIsBuiltinSupported` (line 257), before `return false;`:

```zig
    if (name_id == self.async_frame_size_name_id) return true;
    if (name_id == self.async_init_name_id) return true;
    if (name_id == self.async_resume_name_id) return true;
    if (name_id == self.async_suspend_name_id) return true;
```

In the `builtin_call` dispatch, insert arms before the `ec.len >= 2` fallthrough (line 2180):

```zig
        } else if (node.child_0 == self.async_frame_size_name_id) {
            if (ec.len >= @intCast(usize, 1)) { _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]); }
            result = type_mod.TYPE_INT_LIT;      // 3046 check added in Task 5
        } else if (node.child_0 == self.async_init_name_id) {
            if (ec.len >= @intCast(usize, 4)) {
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]);
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 1)]);
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 2)]);
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 3)]);
            }
            result = type_mod.TYPE_PTR_VOID;
        } else if (node.child_0 == self.async_resume_name_id) {
            if (ec.len >= @intCast(usize, 2)) {
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]);
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 1)]);
            }
            result = type_mod.TYPE_OPTIONAL_VOID_PTR;   // ?*void
        } else if (node.child_0 == self.async_suspend_name_id) {
            if (ec.len >= @intCast(usize, 1)) { _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]); }
            result = type_mod.TYPE_PTR_VOID;
        }
```

Use the compiler's existing optional-pointer type for `?*void` (grep `type_registry.zig` for the canonical optional-pointer constructor; if none exists, resolve it via `typeRegistryGetOrCreateOptional(typeRegistryGetOrCreatePtr(TYPE_VOID))` inside the arm and assign to `result`). Do not invent a new well-known id.

In `sf/src/lower.zig`, add four name-id fields to `LirLowerer` after the `console_set_color_name_id` field (line 356-426 region, mirroring sema) and intern them in `lowererInit` (line 428):

```zig
    var afs_s: []const u8 = "@asyncFrameSize";
    self.async_frame_size_name_id = si_mod.stringInternerIntern(self.ctx.registry.interner, afs_s);
    var ain_s: []const u8 = "@asyncInit";
    self.async_init_name_id = si_mod.stringInternerIntern(self.ctx.registry.interner, ain_s);
    var ars_s: []const u8 = "@asyncResume";
    self.async_resume_name_id = si_mod.stringInternerIntern(self.ctx.registry.interner, ars_s);
    var asu_s: []const u8 = "@asyncSuspend";
    self.async_suspend_name_id = si_mod.stringInternerIntern(self.ctx.registry.interner, asu_s);
```

Add dispatch arms in the `builtin_call` branch (`lower.zig:3911`), chained before the `exit` arm at `:4087`:

```zig
            if (node.child_0 == self.async_frame_size_name_id) {
                var afs_res = nextTemp(self, type_mod.TYPE_INT_LIT);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = afs_res } });
                return afs_res;                       // real value added in Task 5
            }
            if (node.child_0 == self.async_init_name_id) {
                var ai_res = nextTemp(self, type_mod.TYPE_PTR_VOID);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = ai_res } });
                return ai_res;                        // real body added in Tasks 6/7
            }
            if (node.child_0 == self.async_resume_name_id) {
                var ar_res = nextTemp(self, type_mod.TYPE_PTR_VOID);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = ar_res } });
                return ar_res;                        // real body added in Task 6
            }
            if (node.child_0 == self.async_suspend_name_id) {
                var as_res = nextTemp(self, type_mod.TYPE_PTR_VOID);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = as_res } });
                return as_res;                        // real body added in Task 6
            }
```

Finally add `ERR_3018` enforcement. In sema, the analyzer knows the enclosing function's `fn_decl`; when the builtin is `@asyncSuspend` (or `@asyncInit`/`@asyncResume` outside a suspending function) and the enclosing function is not suspending, emit:

```zig
                var e318: []const u8 = "@asyncSuspend used outside a suspending function";
                _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0),
                    @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING)),
                    self.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), e318);
```

`is_suspending` is empty until Task 3. To avoid false `3018` before Task 3, gate the check behind a sema constructor flag `async_analysis_ready: bool` set false here and flipped true in Task 3. `@asyncFrameSize` is intentionally exempt from `3018` (a scheduler is not suspending).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -2
OUT=/tmp/asynct2/t2; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_callgraph_xmod/main.zig 2>&1 | tail -3
echo "dump rc=$?"; ls "$OUT"/*.c 2>/dev/null | wc -l
for f in "$OUT"/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
  -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || echo "GCCFAIL $f"; done
```
Expected GREEN: build done line; dump rc=0; two `.c` files (`main` + `lib`); no `GCCFAIL`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig repro/mi_matrix/async_callgraph_xmod repro/mi_matrix/async_builtin_scope_xmod
git commit -m "feat: register @asyncFrameSize/@asyncInit/@asyncResume/@asyncSuspend (ASYNCTRACK2)"
```

---

### Task 3: Stage 1 — suspension analysis and side tables

**Files:**
- Create: `sf/src/async_analysis.zig`
- Modify: `sf/src/main.zig:94-121, 253-278, 290-292`
- Modify: `sf/src/semantic_analyzer.zig` (thread `suspending_fns`)
- Modify: `sf/src/lower.zig` (thread `suspending_fns`)
- Test: `repro/mi_matrix/async_callgraph_xmod` (Task 2), `async_fnptr_error_xmod` (Task 4)

**Interfaces:**
- Consumes: Task 2 name ids; `symbolRegistryQualifiedLookup` (`symbol_table.zig:141`); `astStoreNodeExtraChildren` (`ast.zig:842`); `hash_mod.U64ToU32Map` (`util/hash.zig:122`).
- Produces: `CompilerContext.suspending_fns`; `asyncKey`, `asyncIsSuspending`; `suspensionAnalysisRun`; sema/lowerer `suspending_fns` field. `frame_sizes` is added here but first written in Task 5.

- [ ] **Step 1: Write the failing test**

Add to `repro/mi_matrix/async_callgraph_xmod/lib.zig` a mutual-recursion pair:

```zig
pub fn ping() void {
    pong();
}
pub fn pong() void {
    ping();
}
```

Add to `main.zig`:

```zig
    var d: u32 = @asyncFrameSize(lib.ping);
    var e: u32 = @asyncFrameSize(lib.pong);
    _ = d; _ = e;
```

RED signal: before Stage 1, these are not suspending, so Task 5's `3046` (not yet present) is simulated here by a temporary compile-time assertion in `suspensionAnalysisRun` that panics if `ping`/`pong` are unresolved. Simpler RED: assert the pass wrote the table. The RED evidence is the absence of `SUSP:` markers.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
timeout 120 sf/build/out_release/zig1 --markers --dump-c89 --output-dir /tmp/asynct2/t3 \
  repro/mi_matrix/async_callgraph_xmod/main.zig 2>&1 | grep -c "SUSP:"
```
Expected RED: `0` (no pass yet).

- [ ] **Step 3: Write minimal implementation**

Create `sf/src/async_analysis.zig`:

```zig
const std = @import("std") ...;   // follow sibling module import style
const ast_mod = @import("ast.zig");
const hash_mod = @import("util/hash.zig");
const mr_mod = @import("module_registry.zig");
const sym_mod = @import("symbol_table.zig");
const alloc_mod = @import("allocator.zig");
const pal = @import("pal.zig");
const main_mod = @import("main.zig");

pub fn asyncKey(module_id: u32, name_id: u32) u64 {
    return (@intCast(u64, module_id) << @intCast(u64, 32)) | @intCast(u64, name_id);
}

pub fn asyncIsSuspending(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) bool {
    var v = hash_mod.u64ToU32MapGet(map, asyncKey(module_id, name_id));
    if (v) |val| return val != @intCast(u32, 0);
    return false;
}

pub fn asyncFrameSizeOf(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?u32 {
    return hash_mod.u64ToU32MapGet(map, asyncKey(module_id, name_id));
}
```

Add the recursive body walk (collect edges into module-arena arrays) and the worklist (CSR reverse index, `u32` queue) exactly per subspec §3.1:

```zig
// walk: for each ModuleEntry, for each fn_decl in extra-children:
//   name_id = fn_protos[payload].name_id; body = node.child_0
//   scan body recursively:
//     fn_call: resolve child_0 (ident_expr | field_access) via symbolRegistryQualifiedLookup;
//              append edge (caller_key, callee_key)
//     builtin_call: if child_0 == async_suspend_name_id, mark direct_suspend(caller_key)=1
```

Add the phase entry point (call it from `main.zig`):

```zig
pub fn suspensionAnalysisRun(ctx: *main_mod.CompilerContext) void {
    var p_msg: []const u8 = "YA\n"; pal.markerWrite(p_msg);
    // 1. collect per-function edges into module-arena arrays
    // 2. seed queue with direct-suspend functions; write suspending_fns[key]=1
    // 3. monotone worklist over reverse edges; write 1 on first propagation
    // 4. marker per suspending function: "SUSP:m<module_id>:n<name_id>\n"
}
```

In `sf/src/main.zig`:
- Add to `CompilerContext` (after `exported`, line 120):
```zig
    suspending_fns: hash_mod.U64ToU32Map,
    frame_sizes: hash_mod.U64ToU32Map,
```
- Initialize next to `exported` (line 253):
```zig
    var suspending_fns = hash_mod.u64ToU32MapInit(&compiler_alloc.module);
    var frame_sizes = hash_mod.u64ToU32MapInit(&compiler_alloc.module);
```
  and add `.suspending_fns = suspending_fns, .frame_sizes = frame_sizes,` to the ctx literal (line 254-278).
- Register the pass in `runCompiler` between `main.zig:291` and `:292`:
```zig
    alloc_mod.checkCombinedPeak(ctx.alloc);
    async_analysis.suspensionAnalysisRun(ctx);
    phase_TypeResolution(ctx);
```
- Add `suspending_fns: *hash_mod.U64ToU32Map` and `frame_sizes: *hash_mod.U64ToU32Map` to `SemanticContext` (`lower.zig:86-100`) and set them in the `SemanticContext` literal at `main.zig:656` (`&ctx.suspending_fns`, `&ctx.frame_sizes`). Add a `suspending_fns: *hash_mod.U64ToU32Map` field to `SemanticAnalyzer` and thread it through `semanticAnalyzerInit` (passed at `main.zig:484, 538`, and forwarded into the sema-owned `SemanticContext`). The lowering side reads them as `self.ctx.suspending_fns`/`self.ctx.frame_sizes` (non-optional pointers, no null check).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
timeout 120 sf/build/out_release/zig1 --markers --dump-c89 --output-dir /tmp/asynct2/t3 \
  repro/mi_matrix/async_callgraph_xmod/main.zig 2> /tmp/asynct2/t3.err | grep "SUSP:" | sort -u
echo "dump rc=$?"
```
Expected GREEN: `SUSP:` lines include `leaf`, `mid`, `top`, `explicit_only`, `ping`, `pong` (the mutual pair proves propagation); `main`/`use_sizes` absent unless they call suspending callees (they do not). rc=0.

- [ ] **Step 5: Commit**

```bash
git add sf/src/async_analysis.zig sf/src/main.zig sf/src/semantic_analyzer.zig sf/src/lower.zig repro/mi_matrix/async_callgraph_xmod
git commit -m "feat: Stage 1 suspension analysis + is_suspending side table (ASYNCTRACK2)"
```

---

### Task 4: Stage 1b — Prelude B `ERR_3017` at function-value materialization

**Files:**
- Modify: `sf/src/lower.zig:2994-3005, 3197-3204, 3290-3299`
- Test: `repro/mi_matrix/async_fnptr_error_xmod/main.zig`

**Interfaces:**
- Consumes: `asyncIsSuspending` (Task 3), `ERR_3017` (Task 1), the three `func_ref` sites.
- Produces: `materializeFnRef(self, sym) u32` used by all three sites; `error[3017]` with 0 `.c` emitted. Discharges non-negotiable concerns 1, 2, 4 (documented in subspec §3.1).

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/async_fnptr_error_xmod/main.zig`:

```zig
fn yielder() void {
    @asyncSuspend(null);
}

fn plain() void {
}

pub fn main() void {
    var fp: fn() void = yielder;
    fp();
    var gp: fn() void = plain;
    gp();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
OUT=/tmp/asynct2/t4; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_fnptr_error_xmod/main.zig 2>&1 | grep -c "error\[3017\]"
```
Expected RED: `0` (no check yet) and `.c` files present.

- [ ] **Step 3: Write minimal implementation**

Add `materializeFnRef` above `lowerIdent` and route all three sites through it. Replace the body at `lower.zig:2994-3005` with a call; the helper:

```zig
fn materializeFnRef(self: *LirLowerer, sym: *sym_mod.Symbol) u32 {
    if (async_analysis.asyncIsSuspending(self.ctx.suspending_fns, sym.module_id, sym.name_id)) {
        var m317: []const u8 = "taking the address of a suspending function is not allowed";
        _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0),
            @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3017_SUSPENDING_FUNCTION_POINTER)),
            @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), m317);
        return TEMP_NONE;
    }
    var s_t: u32 = sym.type_id;
    if (s_t == @intCast(u32, 0)) return TEMP_NONE;
    type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, s_t);
    var fr_pt = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, s_t, false);
    var fr_mid = self.module_id;
    if (sym.module_id != @intCast(u32, 0)) { fr_mid = sym.module_id; }
    var fr_res = nextTemp(self, fr_pt);
    emitInst(self, LirInst{ .func_ref = .{ .name_id = sym.name_id, .module_id = fr_mid, .result = fr_res } });
    return fr_res;
}
```

At `:3197-3204` call `materializeFnRef(self, ts)`; at `:3290-3299` call `materializeFnRef(self, frfsym)`. Direct calls (the `fn_call` path) are unchanged and remain legal. Returning `TEMP_NONE` means the surrounding expression lowers to a poison temp and the diagnostic prevents emission (the diagnostic collector causes `pal.exit(2)` before emission).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
OUT=/tmp/asynct2/t4; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_fnptr_error_xmod/main.zig > /tmp/asynct2/t4.out 2> /tmp/asynct2/t4.err
echo "dump rc=$?"
echo "3017 count: $(grep -c 'error\[3017\]' /tmp/asynct2/t4.err)"
echo "c files: $(ls "$OUT"/*.c 2>/dev/null | wc -l)"
```
Expected GREEN: dump rc nonzero (2); exactly `1` `error[3017]`; `0` `.c` files. Also re-run the positive fixture from Task 2 to confirm `plain`'s address still works: dump rc=0.

- [ ] **Step 5: Record the non-negotiable concerns and commit**

Append a short note to the subspec §3.1 concerns list recording that concern 1 (`fn_ptr_struct_field`) remains a Track 3 constraint and that concerns 2/4 are discharged by the side-table design and the `3017` gate. Then:

```bash
git add sf/src/lower.zig repro/mi_matrix/async_fnptr_error_xmod
git commit -m "feat: ERR_3017 ban on suspending function pointers (ASYNCTRACK2)"
```

---

### Task 5: Stage 2 — LIR frame layout, authoritative frame-size table, real `@asyncFrameSize`

**Files:**
- Create: `sf/src/async_lowering.zig`
- Modify: `sf/src/async_analysis.zig` (write `frame_sizes` in the pass)
- Modify: `sf/src/lower.zig` (real `@asyncFrameSize` value + `ERR_3046`)
- Modify: `sf/src/semantic_analyzer.zig` (`ERR_3046` in the `@asyncFrameSize` arm)
- Test: `repro/mi_matrix/async_frame_xmod/main.zig`

**Interfaces:**
- Consumes: `suspending_fns`/`frame_sizes` (Task 3), `LirFunction` (`lir.zig:494-513`), `lir_opt_pass` Ctx pattern (`lir_opt_pass.zig:163-361`), natural layout (`type_resolver.zig:125-160`).
- Produces: `AsyncFrameLayout`, `AsyncFrameField`, `asyncLayoutFrame`, `ERR_3046`, real `@asyncFrameSize` `int_const`.

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/async_frame_xmod/main.zig`:

```zig
fn worker(x: i32) i32 {
    var y: i32 = x;
    @asyncSuspend(null);
    y = y + 1;
    return y;
}

fn plain() i32 {
    return 7;
}

const Expected = struct {
    ctx: *void,
    state: u8,
    x: i32,
    y: i32,
};

pub fn main() void {
    var got: u32 = @asyncFrameSize(worker);
    var want: u32 = @sizeOf(Expected);
    if (got != want) {
        @panic("frame size mismatch");
    }
}
```

Create `repro/mi_matrix/async_framesize_invalid_xmod/main.zig`:

```zig
fn plain() void {
}

pub fn main() void {
    var s: u32 = @asyncFrameSize(plain);
    _ = s;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
OUT=/tmp/asynct2/t5; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_frame_xmod/main.zig 2>&1 | tail -2
# got==0 (Task-2 placeholder), want==16 -> @panic at runtime? dump alone won't run it.
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/asynct2/t5b \
  repro/mi_matrix/async_framesize_invalid_xmod/main.zig 2>&1 | grep -c "error\[3046\]"
```
Expected RED: first dump succeeds but the frame-size value is `0` (assert by running the linked program: it traps `panic: frame size mismatch`); second dump prints `0` `error[3046]`.

- [ ] **Step 3: Write minimal implementation**

Create `sf/src/async_lowering.zig` with the layout types and `asyncLayoutFrame` implementing the exact field order and natural alignment from subspec §3.2 (ctx, state, params, live-across temps). Reuse the `lir_opt_pass` scratch pattern: `maxTempOf`, `resetScratch`, `markRead`/`markDef`, `scanAll`-style scan, and the `df_bb`/`df_ii` vs `rd_bb`/`rd_ii` locators. Emit the field list and `layout_size`; require `layout_size <= frame_size` and pad to `frame_size`.

Extend `suspensionAnalysisRun` (Task 3) to compute and write the authoritative `frame_sizes[key]` for each suspending function from the AST candidate set (params + named body locals eligible to cross a suspension; conservative upper bound), so the writer is unique (single source of truth). Emit a marker `FRAME:m<module_id>:n<name_id>:s<bytes>`.

In `sf/src/lower.zig`, replace the `@asyncFrameSize` placeholder arm:

```zig
            if (node.child_0 == self.async_frame_size_name_id) {
                var fs_res = nextTemp(self, type_mod.TYPE_INT_LIT);
                var fs_val: u64 = @intCast(u64, 0);
                if (ec.len >= @intCast(usize, 1)) {
                    var afs_sym = resolvedFunctionSymbol(self, ec[@intCast(usize, 0)]);
                    if (afs_sym) |as| {
                        if (async_analysis.asyncFrameSizeOf(self.ctx.frame_sizes, as.module_id, as.name_id)) |fsz| {
                            fs_val = @intCast(u64, fsz);
                        }
                    }
                }
                emitInst(self, LirInst{ .int_const = .{ .value = fs_val, .result = fs_res } });
                return fs_res;
            }
```

In sema, add the `ERR_3046` check in the `@asyncFrameSize` arm: resolve the argument to a function symbol; if it is not a known suspending function, emit `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046` and set `result = TYPE_INT_LIT` (so lowering still runs).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
OUT=/tmp/asynct2/t5; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" \
  repro/mi_matrix/async_frame_xmod/main.zig > /dev/null 2>/tmp/asynct2/t5.err
echo "dump rc=$?"
for f in "$OUT"/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
  -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || echo "GCCFAIL $f"; done
gcc -m32 -std=c89 -O0 -I "$OUT" -I sf/src/include "$OUT"/*.c sf/src/include/zig_runtime.c \
  sf/src/include/zig_pal.c -o /tmp/asynct2/frame && timeout 120 /tmp/asynct2/frame; echo "run rc=$?"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/asynct2/t5b \
  repro/mi_matrix/async_framesize_invalid_xmod/main.zig 2>&1 | grep -c "error\[3046\]"
```
Expected GREEN: dump rc=0; no `GCCFAIL`; `run rc=0` (no `@panic`); `1` `error[3046]`. The `got == @sizeOf(Expected) == 16` equality confirms the layout (`ctx` 0, `state` 4, `x` 8, `y` 12, size 16 pad 0).

- [ ] **Step 5: Commit**

```bash
git add sf/src/async_lowering.zig sf/src/async_analysis.zig sf/src/lower.zig sf/src/semantic_analyzer.zig \
  repro/mi_matrix/async_frame_xmod repro/mi_matrix/async_framesize_invalid_xmod
git commit -m "feat: Stage 2 LIR frame layout + authoritative @asyncFrameSize (ASYNCTRACK2)"
```

---

### Task 6: Stage 3a — `_step` state machine with `switch_br` and save/restore

**Files:**
- Modify: `sf/src/async_lowering.zig` (`asyncTransform`)
- Modify: `sf/src/main.zig:719-722`
- Modify: `sf/src/lower.zig` (`@asyncSuspend`/`@asyncResume`/`@asyncInit` real dispatch)
- Test: `repro/mi_matrix/async_await_xmod/main.zig`, `async_suspend_store_xmod/main.zig`

**Interfaces:**
- Consumes: Tasks 3–5; `switch_br`/`load_field`/`store_field`/`int_const` (`lir.zig:37, 45-46, 74`); `nameManglerMangle` (`c89_emit.zig:455`); `lirStreamAppend` (`main.zig:720`).
- Produces: `asyncTransform`; `__async_frame_<f>` type; `__async_step_<f>(frame: *void, arg: ?*void) ?*void`; `@asyncSuspend`/`@asyncResume`/`@asyncInit` control flow. 0 mandatory new `LirInst`.

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/async_suspend_store_xmod/main.zig` — a single function with one explicit suspend, driven by `@asyncInit`/`@asyncResume`:

```zig
fn worker(out: *i32) void {
    var acc: i32 = 1;
    @asyncSuspend(null);
    acc = acc + 2;
    out.* = acc;
}

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [64]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var ctxp: *void = @ptrCast(&cbuf);
    var args: *const void = @ptrCast(&result);
    var frame: *void = @asyncInit(ctxp, &fbuf, worker, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 3) {
        @panic("async result mismatch");
    }
}
```

Create `repro/mi_matrix/async_await_xmod/main.zig` — caller awaits callee (child frame from `ctx`; full pool logic completed in Task 7, so this task's RED is the emit shape only):

```zig
fn callee(out: *i32) void {
    @asyncSuspend(null);
    out.* = 10;
}

fn caller(out: *i32) void {
    var tmp: i32 = 0;
    callee(&tmp);
    out.* = tmp;
}

pub fn main() void {
    var result: i32 = 0;
    var cbuf: [256]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var ctxp: *void = @ptrCast(&cbuf);
    var args: *const void = @ptrCast(&result);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (result != 10) {
        @panic("await result mismatch");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
for d in async_suspend_store_xmod async_await_xmod; do
  OUT=/tmp/asynct2/t6_$d; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" repro/mi_matrix/$d/main.zig 2>&1 | tail -1
  echo "$d dump rc=$?"
  grep -c "switch" "$OUT"/*.c 2>/dev/null | head -1
done
```
Expected RED: placeholders return null immediately, so `@asyncInit` yields a frame whose `state` is never advanced and `@asyncSuspend` is a no-op returning null; the linked program either traps or never delivers the result; emitted C has no `_step` function and no `switch (`. `grep -c` is `0`.

- [ ] **Step 3: Write minimal implementation**

Implement `asyncTransform(lf, actx)` in `sf/src/async_lowering.zig` per subspec §3.3:

1. Synthesize `__async_frame_<f>` (Stage 2 fields) in the `TypeRegistry`.
2. Renumber suspension points in program order; entry `0`, terminal `K+1`.
3. Rewrite the function to `__async_step_<f>(frame: *void, arg: ?*void) ?*void`; original name stays the `@asyncInit` entry.
4. Emit entry `load_field state`, `switch_br { cond, cases_start/count, else_bb=terminate }`, state-0 prologue initializing params/frame from `arg`, `jump` to the post-prologue block.
5. At each explicit `@asyncSuspend`: `store_field` each live temp, `int_const next_state`, `store_field state`, `ret` null. Resume case reloads and `jump`s past the suspend.
6. Terminal: write result through the caller slot and `ret` null.

Wire it in `main.zig` between line 719 and 720:

```zig
                        var lf = lower_mod.lowerFn(&lowerer, decls[di]);
                        async_lowering.asyncTransform(&lf, &async_ctx);
                        var slot = lir_stream.lirStreamAppend(&ctx.lir_stream, lf);
```

Implement real `@asyncInit` (zero the root frame in `buf`, store `ctx`, `state=0`, return frame), real `@asyncSuspend` (suspend transition of the enclosing function), and real `@asyncResume` (the `_step` drive returning non-null while yielded) in `lower.zig`. Do not add any new `LirInst` variant. If a synthetic struct type proves difficult, fall back to an opaque `[N]u8` frame + `load`/`store` at the same natural offsets.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
for d in async_suspend_store_xmod async_await_xmod; do
  OUT=/tmp/asynct2/t6_$d; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" repro/mi_matrix/$d/main.zig >/dev/null 2>/tmp/asynct2/t6_$d.err
  echo "$d dump rc=$?"
  for f in "$OUT"/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || echo "GCCFAIL $d $f"; done
  gcc -m32 -std=c89 -O0 -I "$OUT" -I sf/src/include "$OUT"/*.c sf/src/include/zig_runtime.c \
    sf/src/include/zig_pal.c -o /tmp/asynct2/$d && timeout 120 /tmp/asynct2/$d; echo "$d run rc=$?"
  grep -c "switch (" "$OUT"/*.c | head -1
done
```
Expected GREEN: both dump rc=0; no `GCCFAIL`; both `run rc=0` (`@asyncSuspend` result 3, await result 10); emitted C contains a `switch (` dispatch (grep count ≥ 1); 3-run stdout md5 identical for any fixture that prints.

- [ ] **Step 5: Commit**

```bash
git add sf/src/async_lowering.zig sf/src/main.zig sf/src/lower.zig \
  repro/mi_matrix/async_suspend_store_xmod repro/mi_matrix/async_await_xmod
git commit -m "feat: Stage 3 LIR-to-LIR _step state machine (ASYNCTRACK2)"
```

---

### Task 7: Stage 3b — per-task LIFO child frames, implicit await, `error.OutOfFrame`

**Files:**
- Modify: `sf/src/async_lowering.zig` (child-frame allocation at implicit-await sites)
- Modify: `sf/src/lower.zig` (`@asyncInit` records the Context pool header; `@asyncSuspend` reads `ctx`)
- Test: `repro/mi_matrix/async_pool_xmod/main.zig` (`-fsafe` OutOfFrame probe)

**Interfaces:**
- Consumes: Task 6 transform; pinned Context contract (subspec §4: `buf` outside pool; per-task LIFO child-frame stack; bump + mark).
- Produces: child-frame bump/mark allocation at suspending call sites; `ctx` read from the current frame; `error.OutOfFrame` (no crash) on exhaustion.

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/async_pool_xmod/main.zig` — a deep chain of suspending calls with a deliberately small Context pool. Model the pool header as the first bytes of `cbuf` read by `@asyncInit`/child allocation (Track 3 will define the full `Context`; for the compiler-core test the pool is a fixed `[pool_bytes]u8` region with a bump pointer and mark, and a capacity supplied through a small header the test writes):

```zig
fn level3(out: *i32) void {
    @asyncSuspend(null);
    out.* = 3;
}
fn level2(out: *i32) void {
    var t: i32 = 0;
    level3(&t);
    out.* = t + 1;
}
fn level1(out: *i32) void {
    var t: i32 = 0;
    level2(&t);
    out.* = t + 1;
}

pub fn main() void {
    var result: i32 = 0;
    var pool: [24]u8 = undefined;      // intentionally too small for 3 child frames
    var cbuf: [64]u8 = undefined;
    var fbuf: [64]u8 = undefined;
    var ctxp: *void = @ptrCast(&pool);
    var args: *const void = @ptrCast(&result);
    var frame: *void = @asyncInit(ctxp, &cbuf, level1, args);
    _ = frame;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
OUT=/tmp/asynct2/t7; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" repro/mi_matrix/async_pool_xmod/main.zig 2>&1 | tail -1
grep -c "OutOfFrame\|OUT_OF_FRAME" "$OUT"/*.c
```
Expected RED: `0` — no pool/OutOfFrame logic yet.

- [ ] **Step 3: Write minimal implementation**

At each implicit-await site in `asyncTransform`, emit: read `ctx` from the caller frame (`load_field ctx`), read the current bump pointer, compute the child frame address, advance the bump pointer by `frame_sizes[callee]`, store the mark, initialize the child, then drive the child `_step` in a loop and restore the mark when it returns null. On `new_bump > capacity`, return `error.OutOfFrame` rather than writing (the compiler core represents this as the `null`/error path of the builtin drive; Track 3 maps it to the `OutOfFrame` error value). `@asyncInit` must treat `buf` as the root frame (outside the pool) and store `ctx` as the pool handle. Confirm `frame_sizes[callee]` is already in the table (Task 5) before use; if absent, emit an ICE (`ERR_9001_ICE`).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh 2>&1 | tail -1
OUT=/tmp/asynct2/t7; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 sf/build/out_release/zig1 --dump-c89 --output-dir "$OUT" repro/mi_matrix/async_pool_xmod/main.zig >/dev/null 2>/tmp/asynct2/t7.err
echo "dump rc=$?"
for f in "$OUT"/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
  -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || echo "GCCFAIL $f"; done
grep -c "mark\|bump\|capacity" "$OUT"/main.c
```
Expected GREEN: dump rc=0; no `GCCFAIL`; emitted C shows the bump/mark/`OutOfFrame` path. Then re-run the Task 6 fixtures with a correctly sized pool: both still `run rc=0` (3 and 10), proving no regression.

- [ ] **Step 5: Commit**

```bash
git add sf/src/async_lowering.zig sf/src/lower.zig repro/mi_matrix/async_pool_xmod
git commit -m "feat: per-task LIFO child frames + error.OutOfFrame (ASYNCTRACK2)"
```

---

### Task 8: Closeout — gates, N-hop fixed-point movement, seed rotation

**Files:**
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (rotation only)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump only if a corpus class moved)
- Modify: `docs/superpowers/specs/2026-09-13-async-compiler-core-design.md` (amendable: record the landed anchors)

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: a moved compiler fixed point (N-hop closure), rotated seed v11, gate battery evidence, amended subspec.

- [ ] **Step 1: Full gate battery (RED before closeout)**

Run:
```bash
cd /workspace/znineeight
bash scripts/corpus/list_corpus_dirs.sh | wc -l
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/asynct2/sc sf/src/main.zig >/tmp/asynct2/sc.out 2>/tmp/asynct2/sc.err
echo "self-compile rc=$?"; grep -c "error\[" /tmp/asynct2/sc.err
```
Expected: corpus count = 570 + new async dirs; self-compile rc=0 with 0 `error[` lines.

- [ ] **Step 2: Run the seeded N-hop closure**

Run:
```bash
cd /workspace/znineeight
for hop in 1 2 3; do
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/asynct2/hop$hop 2>&1 | tail -1
  md5sum /tmp/asynct2/hop$hop/zig1_5_clean
done
```
Expected: successive hops; record the first hop `H1` and confirm `H1 == H2` (N-hop closure). If hops oscillate, STOP-present.

- [ ] **Step 3: Re-baseline the corpus and 4-MD5 gates**

Run the corpus classifier from `docs/sf/QUICK_REF.md:134-145` over `-s0` and the 4-MD5 gate table. Expected: zero asymmetric class movement on the pre-existing 570 dirs; the new `async_*_xmod` dirs classify OK (or GREEN where intentionally a rejection fixture); `EXPECTED_FAIL` v77→v78 only if a class moved.

- [ ] **Step 4: Rotate the seed at closeout**

Only after Step 2's fixed point is recorded:

```bash
cd /workspace/znineeight
bash scripts/seed/archive_seed.sh /tmp/asynct2/hop2/zig1_5_clean /tmp/asynct2/hop2/gen \
  release/seed/zig1-seed.tgz --update-changelog
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
```

- [ ] **Step 5: Amend the subspec and commit closeout**

Record the landed anchors, the new fixed point md5, and the rotated seed md5 in the subspec (status stays "draft, amendable in place"), then:

```bash
git add docs/superpowers/specs/2026-09-13-async-compiler-core-design.md repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "docs: record Track 2 async compiler core closeout (ASYNCTRACK2)"
```

- [ ] **Step 6: STOP-present**

Present the gate battery, the N-hop closure (hop md5s), the new fixed point, the rotated seed md5, and the async fixture results. Await GO: Track 3 (`std.async`) consumes the produced surface.

---

## Self-Review

**Spec coverage** (against `2026-09-13-async-compiler-core-design.md`):
- §3.1 Stage 1 → Tasks 3 (pass, side table, edges, worklist) and 4 (`ERR_3017`, concerns).
- §3.2 Stage 2 → Task 5 (`asyncLayoutFrame`, layout, size table, no new spill level).
- §3.3 Stage 3 → Tasks 6 (`switch_br`, save/restore, ctx-in-frame) and 7 (child frames, OutOfFrame).
- §3.4 Stage 4 → Task 2 (sema/typing/allow-list + lowering dispatch), Task 5 (real `@asyncFrameSize`/`3046`), Task 6 (`@asyncInit`/`@asyncResume`/`@asyncSuspend`).
- §5 Diagnostics → Task 1 (codes), Tasks 2/5 (sites).
- §6 Testing → every task's RED/GREEN fixture; Task 8 gate battery + N-hop + seed.
- §7 Risks → fallbacks stated in Tasks 5/6; concern gates in Task 4.
- §8 Dependencies → Global Constraints (Track 1 band, Track 3 produced surface).

**Placeholder scan:** no `TBD`/`TODO`/`later`; each task names files, exact anchors, code, commands, and expected evidence. The only deferred items are the explicitly marker-gated placeholders in Task 2 (replaced in Tasks 5–7) and the future precise-shrink layout, both documented as v1 choices.

**Type consistency:** the key formula `(module_id << 32) | name_id`, the four builtin names, `AsyncFrameLayout`/`AsyncFrameField`, `__async_frame_<f>`/`__async_step_<f>`, the `?*void`/`*void`/`u32` result types, and the diagnostic names are identical across spec and plan. `frame_sizes` has exactly one writer (`phase_SuspensionAnalysis`) and the readers agree on `@asyncFrameSize(f) == frame_sizes[f]`.

## Amendments

### Amendment 1 (2026-09-14) — Track-2 pre-flight: refreshed baseline, Task-1 code list, build path

Recorded before Task 1, per operator GO. Four facts:

1. **Baseline drift (Global Constraints refreshed).** At Track-2 start: branch `zig1_improvements`; HEAD `0c0e81f5`; compiler fixed point `de7137e04d62435c74e7b15281cb4540`; seed v14 archive md5 `9e6c9faad0536191f28eb60c210a0a25`; canonical corpus 580 = 545 OK / 32 GREEN / 3 FAIL (the 3 are the `callconv_*` emission-inspection expected FAILs); `repro/mi_matrix/EXPECTED_FAIL.md` header v79. The values originally in Global Constraints (HEAD `f755dbed`, fixed point `1467d932…`, seed v10 `ca18fc9f…`, corpus 570, v77) predate Track 1 and the SCRIPTWARN/seed rotations.
2. **Task 1 must NOT re-append `3017`.** `sf/src/diagnostics.zig:73-74` already has `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` and `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017` (Track 1), with matching `u16` consts at `:85-86`. Task 1 appends only the absent members `ERR_3018=3018`, `ERR_3019=3019`, `ERR_3046=3046`, `WARN_3047=3047`; re-adding `3017` is a duplicate enum tag.
3. **Build path.** `sf/build/out_release` did not exist at Track-2 start (verified: no directory, no lock, no running build). Task 1 must first confirm `bash sf/scripts/build_release.sh` still compiles the current `sf/src`; if it does not, use the seed path (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` → `<out>/zig1_5_clean`) for every task's fixture recipe and record the substitution.
4. **Tree hygiene.** The v13→v14 seed rotation was uncommitted at Track-2 start; committed as `0c0e81f5` (docs GATE) before Task 1. `scripts/seed/archive_seed.sh` (SEED_README fixed-point recipe fix) is part of that commit.

## Amendment 2 (2026-09-14) — Build path substitution: seed path (zig0/current-cycle path is dead)

Confirmed at Task-1 pre-flight: `bash sf/scripts/build_release.sh` does NOT build `sf/build/out_release/zig1`. It drives the frozen C++ bootstrap `zig0` (`sf/build/zig0`) and writes `/tmp/fx_subfolder/zig1` (ASAN); against current `sf/src` it aborts with `error: syntax error` at `sf/src/c89_emit.zig:1996` (`@bitCast(...)` unsupported by zig0). The current-cycle/zig0 path is therefore DEAD (as Amendment 1 fact 3 anticipated).

Substitution for every Track-2 task (replaces all `sf/build/out_release/zig1` and `bash sf/scripts/build_release.sh` references):

- Build the measurement compiler from the CURRENT `sf/src` via the seed path:
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/zt2/t<N>`
  → hop1 `<out>/zig1_5_clean` (new source compiled by the committed seed); the script prints hop1/hop2(/hop3) and the closure. Converged binary is `<out>/hop2/zig1_hop2` when hop1==hop2, else `<out>/hop3/zig1_hop3` when hop2==hop3 (moving point).
- Fixture recipe: `<measurement_compiler> --dump-c89 --output-dir DIR repro/.../main.zig`, then compile every `DIR/*.c` with the binding flag set; classify by gcc exit code, never by empty stderr.
- RED baseline = the previously converged compiler (or the extracted seed binary `zig1-seed/zig1`); GREEN = the converged compiler rebuilt from the post-change `sf/src`.
- The recorded fixed point moves per task and is re-established at Task 8 (`FIXED_POINT_MD5=` optional gate).
- Workdir: `/tmp/zt2` (created; `/tmp` swept per operator). Do not use `sf/build/out_release`.

## Amendment 3 (2026-09-14) — Task 3 marker evidence: markers-enabled build + off-corpus `known_excluded` fixture

Operator rulings (Q1/Q2/Q3, m1379):

1. **No marker API substitution.** Keep the plan's `pal.markerWrite("SUSP:m<module_id>:n<name_id>\n")` in `async_analysis.zig`; do NOT use `pal.measureMarkerWrite`.
2. **Build with markers enabled for the evidence only.** `pal.markerWrite*` is compile-time-dead while `sf/src/pal.zig` `g_markers_debug = 0` (`pal.zig:210`). For Task-3 RED/GREEN evidence, temporarily set `g_markers_debug = 1` (UNCOMMITTED), build the compiler from current `sf/src` via the seed path, capture the `SUSP:` markers, then REVERT `g_markers_debug = 0` before the Task-3 commit. The committed source and the corpus build keep markers off.
3. **Marker fixture is off-corpus.** Task-3 marker RED/GREEN fixtures live under `repro/mi_matrix/known_excluded/` (committed evidence, excluded from classification). `scripts/corpus/list_corpus_dirs.sh` gains a guard skipping any directory named `known_excluded` (at any of its three enumeration levels), so the corpus count is unchanged. The corpus `async_callgraph_xmod` may still gain the `ping`/`pong` mutual pair (Task-5 value), but no corpus fixture asserts markers.
4. **Evidence channel.** Markers are written to **stderr**; every marker run uses `--markers` and reads stderr (never stdout).

Consequence for Task 3 Steps 2/4: replace the marker commands with — build a markers-enabled compiler (temporary `g_markers_debug=1`), run the `known_excluded` fixture with `--markers`, read `SUSP:` from stderr. RED = pre-Task-3 marker build → 0 `SUSP:`; GREEN = post-Task-3 marker build → `SUSP:` for `leaf/mid/top/explicit_only/ping/pong`.

Task-3 commit scope therefore adds `scripts/corpus/list_corpus_dirs.sh` (guard) and `repro/mi_matrix/known_excluded/…` (marker fixture), with `sf/src/pal.zig` `g_markers_debug` left `0`.

## Amendable note

This plan is amendable in place. Amendments record the reason, the affected task, and the re-verified baseline; do not rotate the seed or bump `EXPECTED_FAIL` outside Task 8.
