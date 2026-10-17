# z9play / examples — compiler defects found

Tracks compiler defects found while building the example programs. **Reset 2026-10-16:**
the earlier entries D1–D8 were all FIXED at root cause by the zig1 emitter-sanitization
milestone (2026-10-12 … 2026-10-16); their full history, and the milestone's tracked
residuals, live in git (fix commits `4056b26f`, `e526859b`, `c2772f6a`, `b7cba183`,
`649fe398`/`c4838a29`, `dcd0c9db`, `1029221f`/`40a8a36e`) and in that milestone's SDD
reports/ledger. This file now tracks only open defects; numbering restarts at D1.

_(Add new entries as D2, the next free slot, as they are found while building the
examples; entries are doc-only unless a compiler fix is separately authorized.)_

---

## D1 — A function pointer whose return type is an optional of an aggregate cannot be emitted

**Status:** OPEN (found 2026-10-16 building z9play M5b; example-only workaround documented below; compiler fix not yet authorized).

**Symptom.** A function-pointer type — or a struct field / variable of such a type —
whose return type is `?T`, where `T` is an aggregate (`struct`, `enum`, `union(enum)`;
observed with `?Key`, `?struct`, `?enum`), is not representable in seed v98:

1. **Frontend coercion rejected.** Assigning a free function whose return type is `?Key`
   to a function-pointer field fails with
   `error[3000]: type mismatch in field initialization … note: source: function / note: target: pointer`.
   The same shapes with `?u8` (optional scalar), a direct aggregate return
   (`fn (*void) Key`), or an error-union return (`fn (*void) E!T` — the D8 shape) all
   work. **Only optional-of-aggregate is broken.**
2. **Emitted C89 invalid.** Even when a shared named alias for the optional makes the
   frontend accept the coercion, the build fails at gcc:
   `zig_special_types.h:663:29: error: expected declaration specifiers or '...' before '*' token`
   / `unknown type name 'zT_…_FP_zT_…_Opt_'`. The function-pointer typedef (whose return
   type is the optional) is emitted **before** the optional typedef it references — a
   **D8-class ordering gap for `optional_type`** (the D8 fix added the edge for error
   unions; optionals are uncovered). Merely *defining* a struct with such a field (never
   assembling a literal) triggers it.

**Minimal reproducer A — frontend coercion (`probe/a.zig`):**

```zig
pub const Key = union(enum) { char: u8, sigint };
pub const Console = struct { readKey_fn: fn (*void) ?Key, state: *void };
pub fn readKey(state: *void) ?Key { _ = state; return Key{ .sigint = {} }; }
var st: u8 = 0;
pub fn main() void {
    var c: Console = Console{ .readKey_fn = readKey, .state = @ptrCast(*void, &st) };
    if (c.readKey_fn(c.state)) |k| { switch (k) { .char => |x| { _ = x; }, else => {} } }
}
```

```sh
timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -fsafe -o /tmp/probe /tmp/probe/a.zig
# error[3000]: type mismatch in field initialization (source: function, target: pointer)
```

**Minimal reproducer B — emit ordering (contract defined, never assembled):**

```zig
// contract.zig
pub const Key = union(enum) { char: u8, sigint, up, down, left, right, enter, esc };
pub const Console = struct {
    clear_fn: fn (*void) void, setCursor_fn: fn (*void, u16, u16) void,
    writeStr_fn: fn (*void, []const u8) void, readKey_fn: fn (*void) ?Key,
    enterRaw_fn: fn (*void) void, leaveRaw_fn: fn (*void) void,
    width_fn: fn (*void) u16, height_fn: fn (*void) u16,
    cursorShow_fn: fn (*void, bool) void, state: *void,
};
// main.zig
const con = @import("contract.zig");
var g_c: *con.Console = undefined;
pub fn main() void { _ = g_c; }
```

```sh
zig -fsafe -o out main.zig            # rc 0
sh out/build_target.sh linux out/prog
# zig_special_types.h:663:29: error: expected declaration specifiers or '...' before '*' token
```

**Boundary probes:** `?u8` field assignment → OK; `fn (*void) Key` → OK;
`fn (*void) E!i32` → OK; `?struct`, `?enum`, `?union(enum)` → **fail**;
`var x: ?Key = f();` → only `warning[3000]` (rc 0), i.e. the optional identity mismatch
is systemic and is a hard error only on the function-pointer coercion path. A
`*const fn (*void) ?Key` cast is accepted by the frontend but emits an undefined
`zT_…_FP_…_Opt_` type name (still invalid C89).

**Root cause (hypothesis).** `typeRegistryGetOrCreateOptional`
(`sf/src/type_registry.zig:814`) caches an optional only when the payload's `state == 2`
(layout resolved), so a field's `?Key` and a function's `?Key` can be two distinct
synthetic optional ids; `typeRegistryIsAssignable`
(`sf/src/type_registry.zig:1830-1849`) compares the two `fn_type`s' `return_type` ids
directly ⇒ rejection. The emitter additionally mis-orders the fn-pointer typedef vs the
optional-return typedef (the D8-class gap).

**Example-only workaround (used by z9play M5b).** Avoid an optional-of-aggregate
fn-pointer return: return the aggregate **directly** and add an in-band sentinel.
`Key = union(enum){ none, char: u8, sigint, up, down, left, right, enter, esc }` with
`readKey_fn: fn (*void) Key` ("no key ready" = `.none`). No compiler change required.

**Compiler fix (not authorized).** Add the `fn_type`→`optional_type` return-type edge to
the C89 type-dependency relation, and intern/canonicalize optional-of-aggregate so the
fn-pointer coercion unifies. A compiler change (outside an example-only milestone);
author under a future compiler plan.

---

## D2 — An error-union function reference in a comptime-dead `@isWindows()` branch still marks the callee module reachable

**Status:** OPEN (found 2026-10-16 building z9play M6 Task 1; blocks the plan's
"select per-platform backends via `@isWindows()`" approach; compiler fix not yet
authorized).

**Symptom.** When a function in a comptime-dead `@isWindows()` branch references
another module's **error-union-returning** function (direct `call`/`catch`, a
`func_ref` in a vtable literal, or a `load_global` of an error-union-vtable
global), that callee module is emitted anyway even though the branch is folded
away and **no call to it survives in the emitted C**. Non-error-union references
in the same dead branch are pruned correctly, so the emitter's module
reachability (`sf/src/main.zig:1339-1354`, the `call_direct`/`tail_call`/
`func_ref`/`load_global` edge scan) still sees the dead `func_ref` and follows it.
Consequence for cross-target builds: the "wrong-platform" backend module is
emitted, and its platform-only `@cInclude` (e.g. `<sys/ioctl.h>` for Linux OSS,
`<windows.h>` for waveOut) makes the other toolchain's compile fail — so
separate per-platform backend modules cannot be selected by `@isWindows()` alone
in seed v98.

**Minimal reproducer:**

```zig
// errdep.zig — only referenced from the dead (non-Windows) arm below
@cInclude("<linux_only_header.h>");
pub const E = error{ OpenFailed };
var g: u32 = 0;
pub fn open(rate: u32, channels: u8) E!*void {
    if (rate == 0) return error.OpenFailed;
    _ = channels;
    return @ptrCast(*void, &g);
}
// main.zig
const errdep = @import("errdep.zig");
pub fn main() void {
    var ctx: *void = undefined;
    if (@isWindows()) {
        ctx = @intToPtr(*void, 0);
    } else {
        ctx = errdep.open(44100, 2) catch return;
    }
    _ = ctx;
}
```

```sh
timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -osw --dump-c89 --output-dir out main.zig
ls out/errdep_*.c                       # PRESENT (should be pruned on the Windows target)
i686-w64-mingw32-gcc -std=c89 -m32 -I out -c out/errdep_*.c
# fatal error: linux_only_header.h: No such file or directory
```

Confirmed symmetric: the reverse (`-osl` with a Windows-only module referenced in
a dead `@isWindows()` true arm) emits that module too. Non-error-union calls
(`pub fn f(x: i32) i32`) and plain constants in the same dead arm are pruned, so
the trigger is specifically the error-union call/reference.

**Example-only workaround (proposed, not applied — plan ruling pending).** Either
(a) guard each backend's own `@cInclude`s and function bodies with `if
(@isWindows())` / `else` (so the wrongly-emitted module is empty and header-safe
on the other target), which requires touching the existing Linux backends; or
(b) restructure the selection so the two platforms live in one module behind a
target-neutral prelude (the `std_file.zig` / `z9torr/console.zig` pattern),
instead of separate per-platform backend modules.

**Compiler fix (not authorized).** Eliminate dead `@isWindows()` branches (and
their `func_ref`/`call_direct`/`load_global` edges) in LIR before the emitter's
module-reachability scan, so a comptime-dead branch cannot keep a module
reachable. Compiler change (outside an example-only milestone); author under a
future compiler plan.

## D3 — Conditional `@import`: lazy-load gap class (evaluator-foldable conditions the parse-time probe misses)

**Status:** OPEN / DEFERRED (found 2026-10-16 during the compiler D1/D2 parity milestone, Task 4; derived from the D2 solution; not a defect in the milestone's scoped idiom — a feature-completeness item).

**Symptom.** With the conditional-`@import` idiom (`const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");`, or the `switch` form), the untaken arm's `@import` is eliminated semantically (T3 comptime-if fold) and never emitted (T3 module-closure fix backstops any `@cInclude` leak), but a **parse-time eager load** still opens the dead arm's file when the condition is not folded by the parse-time probe (`parserFoldComptimeBool`). If that file is absent or unparsable on the current target, the compile fails with a spurious `error[3048]`-class diagnostic where Zig (lazy file loading) would never open the file.

**Gap class.** The parse probe folds `@isWindows()`, bool literals, `!`/`and`/`or`, and in-order same-module simple-bool consts — but NOT the evaluator's broader constant-fold `KIND_BOOL` class: comparison/arith const inits (`if (1 == 1) …`), module-scope forward-ref consts, cross-module const conditions. For those shapes the dead arm is semantically dead yet its `@import` file is still loaded. Failure direction is **false REJECT only** (over-load; never wrong-module selection — probe ⊊ evaluator). Target idiom (`@isWindows()` and the M6/M7 shapes) is unaffected; z9play M6 is unblocked.

**Why deferred (feature, not gap-in-scope).** Full semantics = true Zig laziness for every comptime-known condition, i.e. the import-queue/phase restructure (deferred option (c)). This milestone's task set is not adequate to feature-complete it; the parse-probe gate is a conservative approximation.

**Relation to F1 (interner id-order landmine).** The full (c) fix moves module resolution across phases and inevitably perturbs interner id assignment order; ANY intern before source lexing deterministically flips `stdlib_crypto_modpow_xmod` OK→GREEN. F1 is being root-caused/fixed in its own Investigate/Fix round (T4.1); **the (c) fix must not be attempted until F1 is root-fixed.** Evidence: Task 4 report (`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4-report.md`, incl. the `conditional_import_lazy_xmod` pin and the F2 boundary analysis) + the T4.1 F1 report (same workspace) — these two documents are the strategy inputs for a future correction.

**Reference points.** Parse gate: `parserFoldComptimeBool` / `dead_import_depth` (`sf/src/parser.zig`); evaluator fold set: `comptimeEvalEvaluate` (`sf/src/comptime_eval.zig:859-984`); T3 sema gate: `semantic_analyzer.zig:3948`; closure fix: `sf/src/main.zig` runtime-init reachability. Same clobber class family: `parserParseBuiltinCall` `child_buf_len = 0` (fixed in T4 C2 ruling) and `parserParseFnDecl` param `child_buf` (F4, folded into T4.1).
