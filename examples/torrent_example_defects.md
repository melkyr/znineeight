# z9play / examples — compiler defects found

Tracks compiler defects found while building the example programs. **Reset 2026-10-16:**
the earlier entries D1–D8 were all FIXED at root cause by the zig1 emitter-sanitization
milestone (2026-10-12 … 2026-10-16); their full history, and the milestone's tracked
residuals, live in git (fix commits `4056b26f`, `e526859b`, `c2772f6a`, `b7cba183`,
`649fe398`/`c4838a29`, `dcd0c9db`, `1029221f`/`40a8a36e`) and in that milestone's SDD
reports/ledger. This file now tracks only open defects; numbering restarts at D1. [updated: 2026-10-17 — compiler D1/D2 parity milestone: D1 + D2 are now FIXED at root cause (their entries keep the full pre-fix symptom/reproducer history + a dated fix block); D3 stays OPEN/deferred; D4 added — the static-analyzer issues cluster, OPEN.]

_(Add new entries as D2, the next free slot, as they are found while building the
examples; entries are doc-only unless a compiler fix is separately authorized.)_

---

## D1 — A function pointer whose return type is an optional of an aggregate cannot be emitted

**Status:** FIXED at root cause (2026-10-17, compiler D1/D2 parity milestone T1+T2 — see the dated fix block below; found 2026-10-16 building z9play M5b; the example-only `Key.none` workaround is RETAINED per operator ruling).

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

**Fixed at root cause [updated: 2026-10-17 — D1/D2 parity, T1+T2].** Root cause CONFIRMED — both halves of the hypothesis above: (1) **identity** — `typeRegistryGetOrCreateOptional` / `typeRegistryGetOrCreateArray` (`sf/src/type_registry.zig`) key-cached only when the payload/elem was already laid out (`MapPut` guarded on `state == 2`), so a field's `?Key` and a function's `?Key` minted two distinct synthetic ids and `typeRegistryIsAssignable`'s raw-id `fn_type` comparison rejected the coercion (`error[3000]` source: function / target: pointer); (2) **emit ordering** — the pointer-only / value-embedding sub-pass split could emit the fn-pointer typedef before the optional typedef it spells (the D8-class gap for `optional_type`; repro B).

Fix commits (branch `zig1_improvements`): T1 `5a56b501` `fix(type_registry): D1 — canonical synthetic composite types` — unconditional key-cache at creation (model `typeRegistryGetOrCreatePtr`), cache-hit in-place completion (`optionalCompleteIfReady`/`arrayCompleteIfReady`, `payload.state==2` guard), and structural `fn_type` comparison (`typeRegistryTypesEquiv`/`typesEquivRec` over return + params for the synthetic-composite family); T2 `1c5247b9` `fix(c89_emit): D1 — composite typedef ordering` — emit-site spelling-dependency walk (`emitDefDeps`/`emitDepRef`: fn return/params, slice elem, by-value `?T`/`E!T`/`[N]T`/tuple closure) so every composite typedef emits before every spelling reference.

Fixtures green (post-fix): `fnptr_opt_aggregate_coerce_xmod` **PASS** (runtime golden `coerce sigint ok`, rc 0) and `fnptr_opt_aggregate_emit_xmod` **PASS** (`fnptr emit ok`, all `.c` gcc-clean) — `bash scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/fnptr_opt_aggregate_{coerce,emit}_xmod` → PASS / PASS (full parity-fixture run: `9 PASS / 0 FAIL`).

**Workaround RETAINED per operator ruling.** The z9play M5b example-only `Key.none` in-band-sentinel shape above stays in the example tree (belt-and-braces; no compiler dependency either way) — the compiler now accepts the original `fn (*void) ?Key` shape (fixtures above). The "Compiler fix (not authorized)" paragraph above is superseded by this block (fix landed under the D1/D2 parity milestone).

---

## D2 — An error-union function reference in a comptime-dead `@isWindows()` branch still marks the callee module reachable

**Status:** FIXED at root cause (2026-10-17, compiler D1/D2 parity milestone T3+T4 — see the dated fix block below; found 2026-10-16 building z9play M6 Task 1; the per-platform `@isWindows()` backend selection the plan needed is unblocked).

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

**Fixed at root cause [updated: 2026-10-17 — D1/D2 parity, T3+T4].** Mechanism truth-up (supersedes the "dead `func_ref` survives LIR" framing in the Symptom and the "Compiler fix" paragraph above — that channel was measured **wrong** for this shape: the comptime-fold path already eliminated the dead arm's LIR before emission; see `task-0-report.md` §1.2 measured nuance). The wrong-platform module was kept by the **module-reachability type-owner pin**: `pruneTypeMarkByValue` (`sf/src/main.zig`) runs over every lowered fn's hoisted temps / return / params and marks the **owner module of every by-value-named type** reachable — the `E!*void` return type is a cross-module type name (shared EU typedef + per-module `E` error-set names pin the owner module) — together with the `call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` edge scan over ALL lowered functions, including the never-called module's own fns. Non-error-union dead-arm references pin nothing (they create no cross-module type name and their instruction edges fold away with the arm), which is why the defect looked error-union-specific.

Fix commits (branch `zig1_improvements`): T3 `58c4cb1c` `fix(semantic_analyzer): D2 — comptime-if eliminates the untaken arm` — sema fold gate `semanticAnalyzerIfComptimeCondition` (untaken arm NOT analyzed; `TYPE_NORETURN`-stamped; Zig rule "the untaken branch does not exist") + the reachability-consistent runtime-init edge in `main.zig` (the root edge is added only for ALREADY-reachable modules — exactly the set whose `__module_init` the synthesized wrapper emits, `prune_active` gate — so a module nothing calls or references is dropped whole); T3 `3583668b` else-less Variant B (a comptime-dead else-less `if` skips its then arm; the `error[3059]` value-use rejection kept — census 10/10); T4 `a7828e5e` `feat(semantic_analyzer): conditional @import` (the if/switch idiom resolves to the LIVE module on both targets; `import_expr` works in expression position; use-site alias fold) + `d568880c` `fix(parser): true Zig laziness for dead-arm @import + builtin-call clobber` (a dead arm's `@import` NEVER loads its file — parse-time `dead_import_depth` + `parserFoldComptimeBool` probe, CLI-target polarity wire; `parserParseBuiltinCall` `@import` `child_buf_len = 0` clobber deleted).

Fixtures green (post-fix, `bash scripts/stdlib/run_fixtures.sh <zig1> …` → `9 PASS / 0 FAIL` over the 9 parity fixtures; the D2 set specifically): `iswindows_deadarm_errunion_xmod`, `iswindows_deadarm_prune_xmod`, `iswindows_deadarm_cond_if_xmod`, `comptime_if_noelse_deadarm_xmod`, `conditional_import_if_xmod`, `conditional_import_switch_xmod`, `conditional_import_lazy_xmod` — **7 PASS / 0 FAIL**. Cross-target contract: the wrong-platform module is absent on both `-osw` and `-osl` (no platform-only `@cInclude` leak; `windep_*.c` absent on linux, `linuxdep_*.c` absent on windows). Residual gap class: **D3** (below) — parse-probe ⊊ evaluator, OPEN/deferred, untouched.

## D3 — Conditional `@import`: lazy-load gap class (evaluator-foldable conditions the parse-time probe misses)

**Status:** OPEN / DEFERRED (found 2026-10-16 during the compiler D1/D2 parity milestone, Task 4; derived from the D2 solution; not a defect in the milestone's scoped idiom — a feature-completeness item).

**Symptom.** With the conditional-`@import` idiom (`const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");`, or the `switch` form), the untaken arm's `@import` is eliminated semantically (T3 comptime-if fold) and never emitted (T3 module-closure fix backstops any `@cInclude` leak), but a **parse-time eager load** still opens the dead arm's file when the condition is not folded by the parse-time probe (`parserFoldComptimeBool`). If that file is absent or unparsable on the current target, the compile fails with a spurious `error[3048]`-class diagnostic where Zig (lazy file loading) would never open the file.

**Gap class.** The parse probe folds `@isWindows()`, bool literals, `!`/`and`/`or`, and in-order same-module simple-bool consts — but NOT the evaluator's broader constant-fold `KIND_BOOL` class: comparison/arith const inits (`if (1 == 1) …`), module-scope forward-ref consts, cross-module const conditions. For those shapes the dead arm is semantically dead yet its `@import` file is still loaded. Failure direction is **false REJECT only** (over-load; never wrong-module selection — probe ⊊ evaluator). Target idiom (`@isWindows()` and the M6/M7 shapes) is unaffected; z9play M6 is unblocked.

**Why deferred (feature, not gap-in-scope).** Full semantics = true Zig laziness for every comptime-known condition, i.e. the import-queue/phase restructure (deferred option (c)). This milestone's task set is not adequate to feature-complete it; the parse-probe gate is a conservative approximation.

**Relation to F1 (interner id-order landmine).** The full (c) fix moves module resolution across phases and inevitably perturbs interner id assignment order; ANY intern before source lexing deterministically flips `stdlib_crypto_modpow_xmod` OK→GREEN. F1 is being root-caused/fixed in its own Investigate/Fix round (T4.1); **the (c) fix must not be attempted until F1 is root-fixed.** Evidence: Task 4 report (`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4-report.md`, incl. the `conditional_import_lazy_xmod` pin and the F2 boundary analysis) + the T4.1 F1 report (same workspace) — these two documents are the strategy inputs for a future correction.

**Reference points.** Parse gate: `parserFoldComptimeBool` / `dead_import_depth` (`sf/src/parser.zig`); evaluator fold set: `comptimeEvalEvaluate` (`sf/src/comptime_eval.zig:859-984`); T3 sema gate: `semantic_analyzer.zig:3948`; closure fix: `sf/src/main.zig` runtime-init reachability. Same clobber class family: `parserParseBuiltinCall` `child_buf_len = 0` (fixed in T4 C2 ruling) and `parserParseFnDecl` param `child_buf` (F4, folded into T4.1).

---

## D4 — Static-analyzer issues cluster (inert base, dead-arm parity, residual walks)

**Status:** OPEN (recorded 2026-10-17 at the compiler D1/D2 parity milestone, T5→T6; a CLUSTER, not a single defect). Operator ruling, quoted in essence: the analyzer issues **"require its own plan to fix whatever is good to fix, but there are several defects worth fixing"** — so this entry is the intake list for a future dedicated analyzer plan; nothing here is fixed by the D1/D2 parity milestone beyond T5's landed revivals below, and no fix is authorized by this entry.

**T5's landed revivals STAND (do not re-litigate).** `5cc7107f` `fix(analyzer): D1/D2 surface + drift truth-up` (report `3e4d5209`) revived three inert mechanisms and those fixes stand: (1) **Lifetime provenance substrate** — analyzer-internal `Provenance` (incl. `external = 6`) base classification + bare-vs-interior `&` rules (the `symbol_registrator`-fed lookup was inert on every real compile); (2) **capture wiring** — `bindCaptureState`/`captureNameIdOf` for `if`/`while`/`for`/switch-prong/`catch |e|` captures, including the miss-keyed `if_stmt` SAFE binding; (3) **Signature surface** — recursive `validateSignatureType`: fn-ptr `?Aggregate`/`E!Aggregate` returns, nested incompletes, arbitrary-width ints, `.tag`/member type exprs, packed-union incomplete reject. 59/59 analyzer tests green at T5 (10 new unit tests + 5 `tests/analyzers/**` fixtures).

**Known defect list (the "several defects worth fixing" — each needs its own scoping decision in the future plan):**

(a) **Full comptime-dead-arm parity missing.** Per Zig (the T3 rule) a comptime-untaken arm does not exist for analysis; the analyzers fold only a conservative bool-literal family (`analyzerFoldComptimeBool`: literals, parens, `!`/`&&`/`||`) and skip only the untaken arm of a capture-free `if`. The shared `comptime_folds` table is **not plumbed into `AnalyzerContext`** (that touches `main.zig`/`comptime_eval.zig`), so evaluator-only folds (named consts, compounds, `@isWindows()`) and `switch` prongs still walk both sides → false diagnostics in comptime-dead code. Sources: tech-debt `docs/tech_debt/static_analyzers.md` §4.1.

(b) **NullPointer: return/init expressions not walked + params unseeded.** `analyzeExpr` covers conditions, expression statements and assignment RHS, but NOT `return`-statement expressions or `var` initializers (`return p.*` unchecked); parameters are not seeded in the null state map — measured 44 false WARN_6002 on the compiler self-source. Sources: tech-debt §4.2.

(c) **DoubleFree misses capture alias chains.** `var p = sandAlloc(...); var op = p; if (op) |q|` keeps `op` untracked (assign-propagation gap), so frees through `q` warn "untracked" and cross-name double frees are not checked. Sources: tech-debt §4.3.

(d) **Symbol-table provenance structurally dead for fn locals/params.** `symbol_registrator` inserts module-root names only (globals/functions/modules/type aliases), so `classifyProvenance`'s `symbolTableLookup` always misses for function locals/params. T5 routed around it with the analyzer-internal `Provenance` substrate; a proper fix registers locals or passes a front-end scope map into the analyzer.

(e) **Vacuous hand-fed-symbol unit-test pattern.** The analyzer unit tests insert `Symbol` records manually, so they exercise a lookup path the real pipeline never takes for locals/params — the old "revival illusion" that masked (d). Future tests should drive the `tests/analyzers/**` fixture runner (the T5 direction) instead of hand-feeding.

(f) **Docs residue.** `docs/design/static_analyzers.md` C++-era prose remnants + `docs/sf/STATIC_ANALYZERS_p2.md` p2 §5.3 aspirational slice row — T5 truth-upped the load-bearing sections; the residue is still open.

(g) **`Symbol` test-init missing `file_id`.** `sf/src/tests/test_analyzer_bin.zig`'s `Symbol{...}` initializers omit `file_id` (zig1 zero-fills missing struct-init fields so it compiles/runs; zig0 would reject) — pre-existing rot, disclosed in the T5 report.

**Provenance of this list.** `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-5-report.md` (§1 root causes + Concerns) + `docs/tech_debt/static_analyzers.md` §4.1/§4.2/§4.3 (appended at T5) + the T5 review minors. The future plan starts from those documents; this entry is the ledger intake.

---

## D5 — `extern fn` with a body is accepted, analyzed, then silently treated as a declaration (body never emitted)

**Status:** OPEN (found 2026-10-18 during the z9play M6 T2 review; operator ruling: "file the issue found and the clarity as a feature gap").

**Defect.** An `extern fn` declaration that carries a body — e.g. `pub extern "stdcall" fn cb(x: u32) i32 { ... }` (also the default-cdecl `extern fn`) — is accepted with rc=0, its body is analyzed/typechecked, and then the declaration is treated as an external declaration: the emitted C contains NO definition and NO prototype for the symbol. A later registration call (`SetConsoleCtrlHandler(cb, 1)`, `atexit(cb)`) compiles to a reference to a symbol the C toolchain has never seen, so the failure surfaces at the C toolchain with no Z98 diagnostic (observed: gcc `'onCtrl' undeclared`; where a header does supply a prototype it becomes an undefined symbol at link). The construction is a Zig error (`extern` functions cannot have a body), not a valid declaration, so this is a diagnostic-correctness defect.

**Feature gap (clarity).** Z98 has no syntax for DEFINING a non-cdecl function. The win9x-calling-convention spec allows `"c"`/`"cdecl"`/`"stdcall"` only on `extern` declarations and fn-pointer types; non-extern definitions are always cdecl; `callconv(...)` is rejected by the parser; `export fn` is cdecl. Therefore a real Win32 `__stdcall` callback (e.g. `PHANDLER_ROUTINE`) cannot be written in Z98 at all — only faked with a cdecl function cast to a stdcall function pointer, which is a real i386 stack-cleanup ABI defect (the cdecl callee does not pop the argument; the stdcall caller assumes it did).

**Minimal fix (compiler).** Clean reject with a dedicated error code/diagnostic when an `extern fn` declaration carries a body (parse/sema): "extern function declarations cannot have a body". Audit the `extern fn ... { }`, `pub extern fn ... { }`, and `extern "stdcall" fn ... { }` forms; all currently rc=0.

**Full fix (compiler).** Support stdcall function DEFINITIONS (e.g. `fn f(...) callconv(.x86_stdcall)`, or `extern "stdcall" fn f(...) { }` emitting `Z98_STDCALL` on the definition), so Win32 callbacks are expressible without a cast. This is the D5 counterpart of the already-landed stdcall declaration/fn-pointer/call-site work.

**Hit by.** z9play M6 Win9x console backend (T2, commit `d86b3441`): Ctrl-C was first implemented with a `SetConsoleCtrlHandler` callback (`onCtrl`) cast from cdecl to `PHANDLER_ROUTINE`; the T2 review flagged the resulting ABI defect. M6 Amendment 1 (operator ruling, Option 3) removed the handler.

**Workaround (example-only).** M6 Amendment 1 Option 3: `enterRaw` also clears `ENABLE_PROCESSED_INPUT`; Ctrl-C is then reported in the input buffer as a `KEY_EVENT` with `uChar == 0x03`, which `readKey` maps to `Key.sigint`. `SetConsoleCtrlHandler` and its cast are gone; the `atexit` mode-restore backstop remains. Commit `example(z9play): M6 T2 fix — Ctrl-C via processed-input off (option 3)`. Known limits: Ctrl-Break still terminates via the default handler; console-close/shutdown restore is moot (the console is gone).

**Evidence.** T2 review of `d86b3441` (`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/review-323bff07..d86b3441.diff`): objdump of the emitted callback path shows a plain `ret` (cdecl) where a `__stdcall` callback must `ret $4`, so the `@ptrCast(CtrlHandler, onCtrl)` bridge is a real stack-cleanup mismatch. Direct probe: the compiler accepts `pub extern "stdcall" fn onCtrl(t: u32) i32 { ... }` with rc=0, emits only the registration-site reference (`zT_1 = ((...)onCtrl);`) and no definition, and mingw then rejects the emitted C with `error: 'onCtrl' undeclared` (no Z98 diagnostic); see the T2 fix-round report (`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-2-report.md`, "Fix round 1"). Workaround verification: the new `-osw` probe dump has no `SetConsoleCtrlHandler`/`PHANDLER_ROUTINE`/`onCtrl`/cast, `XRUNRC=0`, `--dump-c89` md5 `81c052098c89218b96da2ea908f77310`.

**Reference points.** `sf/src/parser.zig` `parserParseExternDecl`/`parserParseFnDecl` (`is_extern` + body accepted); `docs/superpowers/specs/2026-09-13-win9x-calling-convention-design.md` §1 (conventions only on extern declarations + fn-pointer types; non-extern definitions never carry a convention); D1/D2/D4 entries above for the intake style.

---

## D6 — Decimal `f64` literals are not correctly rounded by the lexer

**Status:** FIXED at root cause (2026-10-20, std-algorithms M2 T1B lexer fix + T1D literal restore — see the dated fix block below; found 2026-10-19 while pinning `std_noise` for M2; the `std_noise.zig` workaround literals are REMOVED).

**Defect.** `parseF64` in `sf/src/lexer.zig` accumulates the fractional part digit-by-digit with `result += digit * frac_mul` and `frac_mul *= 0.1`. That is not a correctly-rounded decimal-to-binary conversion, so a literal can land one or more ULPs away from the double a conforming compiler (`gcc`, Zig) produces. The error is silent and propagates into emitted C.

**Reproducer.** Build a program with the two literals and inspect the dumped C:

```zig
const std = @import("std");
const a: f64 = 0.366025403784439;
const c: f64 = -0.16666666666666666;
pub fn main() void {
    std.io.print("{} {}\n", .{a, c});
}
```

```sh
mkdir -p /tmp/f64_round/out
/tmp/t4_review/zig1_5_clean -ffast -o /tmp/f64_round/out /tmp/f64_round.zig
grep -n "3.660254\|1.666666" /tmp/f64_round/out/*.c
```

Observed emitted C:

```c
zF_..._printF64((zT_..._f64)(3.660254037844391e-1));
...
zG_..._c = (zT_..._f64)(-(zT_..._f64)(1.6666666666666669e-1));
```

The correct round-to-nearest-even doubles are `3fd76cf5d0b0995b` (`0.366025403784439`) and `bfc5555555555555` (`-0.16666666666666666`). The lexer produces `3fd76cf5d0b0995d` (2 ULP high) and `bfc5555555555556` (1 ULP high). A second adjacent literal, `0.3660254037844389`, lands on `3fd76cf5d0b0995b`, which is why `std_noise` currently uses that noncanonical spelling as a workaround; `sf/src/std_math.zig:208` documents the same limitation.

**Proper behavior.** Parse decimal `f64` literals with correct rounding (round-to-nearest-even), matching `strtod`/Zig. At minimum, `0.366025403784439` must produce `3fd76cf5d0b0995b` and `-0.16666666666666666` must produce `bfc5555555555555`, without source-level adjacent-literal compensation.

**Impact.** Any bit-exact algorithm, crosscheck vector, or serialized constant can silently differ by ULPs; the workaround makes source literals misleading and will break if the lexer is fixed. The M2 `std_noise` crosscheck pins the current workaround, so a lexer fix is expected to fail that vector until the literals are restored.

**Reference points.** `sf/src/lexer.zig:610-645` (`parseF64` fractional loop); `sf/src/std_math.zig:208` (known-lexer note); M2 Task 1 report `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1-report.md` §Fix round 1 (literal workaround + bit evidence).

**Fixed at root cause [updated: 2026-10-20 — std-algorithms M2 T1B + T1D].** The lexer is now correctly rounded and the `std_noise` compensation is gone.

Fix commits (branch `std_algorithms_m2`): T1B `f967aeff` `fix(lexer): correctly round decimal f64 literals` — `parseF64` (`sf/src/lexer.zig`) rewritten as a correctly-rounded decimal-to-binary conversion (Clinger fast path + slow-path decimal correction), so `0.366025403784439` produces `3fd76cf5d0b0995b` and `-0.16666666666666666` produces `bfc5555555555555` (the "Proper behavior" bar above) and the 17-sig-digit round-trip holds; T1D `fix(std_noise): restore canonical f64 literals after lexer fix` — `sf/src/std_noise.zig` literals restored to the canonical 2014-reference spellings `0.366025403784439` / `-0.16666666666666666` and the compensating comment deleted (the adjacent-literal workaround is REMOVED — it now parsed 1–2 ULPs off under the fixed lexer and failed the crosscheck grid).

Verification (T1D, seed-built fixed compiler `21c957730d268f1e7883176fa5413b65`): `scripts/stdlib/run_crosscheck.sh <zig1> std_noise` **PASS 3/3** (Z98 == C89 ref == committed `grid.expected`, md5 `94314ebd32053089b226387770c0cd5d` UNCHANGED); `verify_stdlib` **STDLIB GATE OK 3/3** (294/0 fixtures; `stdlib_noise_basic_xmod` PGM hash `4921c94f3ec08543` re-captured byte-identical). Full detail: `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1d-report.md`.

The "Reproducer" / "Impact" paragraphs above are the historical record at intake (pre-fix). `sf/src/std_math.zig`'s bit-pattern constant style remains valid engineering (no dependency on parser precision) — only its parenthetical "the lexer's decimal-float parser is not correctly rounded" note is now historical (T1B fixed it).

---

## D7 — Phase 1 (TLS + WireGuard) closeout sweep

**Status:** SWEPT at Phase 1 M7 closeout (2026-10-23). Two std-library defects
were fixed during the phase; one demo workaround is retained for an open
emitter shape. No compiler source was changed at closeout.

**Phase 1 STOP cross-reference (historical, not renumbered).** The earlier
Phase 1 STOP items are covered here rather than as new entries:

- **M2 const-rodata STOP-1** — a non-first-member union const initializer is
  not representable as a single C89 constant initializer, so the specified
  `.bss` + field-store fallback was kept. Zero occurrences in the M2 corpus
  trees; the decision and evidence are in
  `.superpowers/sdd/2026-10-21-phase1-m2-crypto-core-plan/task-1c-i-report.md`
  §7 (STOP-1). Documented behavior, not a shipped defect. The companion
  **STOP-2** (plan fixed-point anchor vs compiler-fix seed rotation) was
  resolved by **v112** (1C-F, fixed point `21c95773…` → `45158dce…`) and then
  **v113** (Task 4), as recorded in the seed CHANGELOG.
- **M4 demo review fixes (Medium/Low, not STOPs)** — `tls_demo`'s Winsock
  lifetime and clock-overflow handling were review findings fixed inside
  Phase 1 M4 (`e9c039df` `fix(demo): tls_demo Winsock lifetime + clock overflow
  (Phase1 M4)`). `tier_tls.sh` only builds/import-gates the `-osw` executable
  (the clock-overflow assertion runs the Linux binary and expects
  `tls: BadArgs`); **no tier runs `tls_demo` under Wine**, and the Winsock
  lifetime currently has **no automated regression coverage**. The manual Wine
  recipe in `examples/z98/demo/tls_demo/README.md` is the only current check.

**D7.1 — RSA-PSS top mask overflowed under `-fsafe` (std_crypto).** Status:
FIXED (`27722aea` `fix(std_crypto): safe PSS topmask under -fsafe`,
Phase 1 M2 fix round). `pssCheck` shifted a `u8` mask by `8 - unused`, which
traps on an `@intCast` overflow under the default `-fsafe`; the fix computes
the mask in `u32` and truncates. A follow-up `7a0bf60c` rejects an oversized
PSS `salt_len` instead of reading past the encoded message. Regression gates:
`repro/mi_matrix/stdlib_rsa_verify_xmod` under `scripts/stdlib/run_crypto_safe.sh`
(3×, default `-fsafe`) plus the `-fsafe` crypto/ecc gates.

**D7.2 — X.509 path build had no same-subject backtracking and accepted weak
leaf keys / mismatched signature OIDs (std_x509).** Status: FIXED (`9c849209`
`fix(std_x509): path backtracking + leaf key size + sigalg equality`,
Phase 1 M3 security carry-over; report
`.superpowers/sdd/2026-10-21-phase1-m4-tls12-https-plan/task-x509-security-report.md`).
The verifier now performs a bounded DFS over same-subject intermediates,
signature-checks each anchor candidate before acceptance, rejects an RSA leaf
key below 2048 bits with `UnsupportedAlgorithm`, and rejects a TBS/outer
signature-algorithm OID mismatch with `Corrupt`. Pinned by the security vectors
in `stdlib_x509_verify_xmod` / `stdlib_x509_parse_xmod` (3× targeted + full
gate).

**D7.3 — `arr[i].field[0..]` write can target a by-value temporary (emitter).**
Status: **OPEN, demo-worked-around** (found 2026-10-23 building
`wireguard_demo`, Phase 1 M7 T3; recorded in
`examples/z98/demo/wireguard_demo/NOTES.md`). In the current emitter a nested
write through an indexed aggregate field can materialise a by-value temporary,
so the store is lost. The demo takes an explicit pointer first
(`var pp: *wg.WgPeer = &g_peers[0];` then `pp.field[0..]`) and works. This is
an emitter lvalue/temporary-materialisation defect in nested aggregate field
indexing; it is a distinct family from D1 (optional-of-aggregate type identity
and typedef ordering) and D2 (comptime-dead-arm module reachability), not an
lvalue/address-of-lowering instance of either. No compiler fix was authorized
in Phase 1 and `sf/src` was frozen at closeout.
A future compiler plan should reproduce it with a minimal `arr[i].field = ...`
fixture before fixing.

**Also fixed inside M7 (demo-only, not compiler defects).** The demo's base64
accumulator needed a 24-bit mask (an unmasked `u32` corrupted key material and
surfaced as `wg: InvalidPeer`), and the poll/`wgSend` output buffers had to be
distinct (aliasing corrupted the inner packet). Both fixes and the full
bring-up log are in `wireguard_demo/NOTES.md`; neither changes a library
contract.

**Closeout evidence.** Phase 1 M7 full gate on seed v119:
`verify_stdlib.sh` **336 PASS / 0 FAIL** + crosscheck **10 PASS / 0 FAIL**;
`tier_tls.sh` **19/19**, `tier_wireguard.sh` **5/5**; both on the rotated
compiler `45158dce…`.
