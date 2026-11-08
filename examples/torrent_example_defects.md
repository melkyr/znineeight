# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D15**.

Open: **D3**, **D4**, **D5**, **D8**, **D10**, **D13**, **D14**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

---

## D3 — Conditional `@import`: lazy-load gap class (evaluator-foldable conditions the parse-time probe misses)

**Status:** OPEN / DEFERRED (found 2026-10-16 during the conditional-`@import` work, Task 4; derived from that solution; not a defect in that work's scoped idiom — a feature-completeness item).

**Symptom.** With the conditional-`@import` idiom (`const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");`, or the `switch` form), the untaken arm's `@import` is eliminated semantically (T3 comptime-if fold) and never emitted (T3 module-closure fix backstops any `@cInclude` leak), but a **parse-time eager load** still opens the dead arm's file when the condition is not folded by the parse-time probe (`parserFoldComptimeBool`). If that file is absent or unparsable on the current target, the compile fails with a spurious `error[3048]`-class diagnostic where Zig (lazy file loading) would never open the file.

**Gap class.** The parse probe folds `@isWindows()`, bool literals, `!`/`and`/`or`, and in-order same-module simple-bool consts — but NOT the evaluator's broader constant-fold `KIND_BOOL` class: comparison/arith const inits (`if (1 == 1) …`), module-scope forward-ref consts, cross-module const conditions. For those shapes the dead arm is semantically dead yet its `@import` file is still loaded. Failure direction is **false REJECT only** (over-load; never wrong-module selection — probe ⊊ evaluator). Target idiom (`@isWindows()` and the M6/M7 shapes) is unaffected; z9play M6 is unblocked.

**Why deferred (feature, not gap-in-scope).** Full semantics = true Zig laziness for every comptime-known condition, i.e. the import-queue/phase restructure (deferred option (c)). This milestone's task set is not adequate to feature-complete it; the parse-probe gate is a conservative approximation.

**Relation to F1 (interner id-order landmine).** The full (c) fix moves module resolution across phases and inevitably perturbs interner id assignment order; ANY intern before source lexing deterministically flips `stdlib_crypto_modpow_xmod` OK→GREEN. F1 was root-caused/fixed in its own Investigate/Fix round (T4.1); **the (c) fix must not be attempted until interner-order sensitivity is re-verified.** Evidence: Task 4 report (`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4-report.md`, incl. the `conditional_import_lazy_xmod` pin and the F2 boundary analysis) + the T4.1 F1 report (same workspace) — these two documents are the strategy inputs for a future correction.

**Reference points.** Parse gate: `parserFoldComptimeBool` / `dead_import_depth` (`sf/src/parser.zig`); evaluator fold set: `comptimeEvalEvaluate` (`sf/src/comptime_eval.zig:859-984`); T3 sema gate: `semantic_analyzer.zig:3948`; closure fix: `sf/src/main.zig` runtime-init reachability. Same clobber class family: `parserParseBuiltinCall` `child_buf_len = 0` (fixed in T4 C2 ruling) and `parserParseFnDecl` param `child_buf` (F4, folded into T4.1).

---

## D4 — Static-analyzer issues cluster (inert base, dead-arm parity, residual walks)

**Status:** OPEN (recorded 2026-10-17 at the compiler parity milestone, T5→T6; a CLUSTER, not a single defect). Operator ruling, quoted in essence: the analyzer issues **"require its own plan to fix whatever is good to fix, but there are several defects worth fixing"** — so this entry is the intake list for a future dedicated analyzer plan; nothing here is fixed by that milestone beyond T5's landed revivals below, and no fix is authorized by this entry.

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

**Reference points.** `sf/src/parser.zig` `parserParseExternDecl`/`parserParseFnDecl` (`is_extern` + body accepted); `docs/superpowers/specs/2026-09-13-win9x-calling-convention-design.md` §1 (conventions only on extern declarations + fn-pointer types; non-extern definitions never carry a convention); the D4 entry above for the intake style.

---

## D8 — stdout is split across two layers: compiler builtins emit C stdio, `std.fmt` uses the PAL

**Found:** 2026-10-24 (Phase 2 P3-M3, while reviewing `z9dbg` output). **Status:
OPEN / DEFERRED — documented, no emission change** (operator ruling A,
2026-10-24: keep the current paths; document the two stdout stacks, fix the
misleading "no cstdio" comments, and cover the CRT/no-CRT story in the M4 docs
task. Changing the builtins' emission would re-baseline every pin/golden and is
therefore a separate mini-plan if strict PAL purity is ever required.)

**Symptom / inconsistency.** `std.io.write` / `writeByte` / `writeStr` /
`printInt` route through the compiler builtins `@stdoutWrite` / `@putChar`, and
those builtins are lowered to **C stdio**, not to the PAL:

- `.builtin_stdout_write` → `fwrite(..., stdout)`; `.builtin_stderr_write` →
  `fwrite(..., stderr)`; `.builtin_get_char` → `getchar()`; `@putChar` →
  `putchar` (`sf/src/c89_emit.zig:8341-8365`).
- `#include <stdio.h>` is emitted per module whenever one of those builtins
  appears (`sf/src/c89_emit.zig:2208-2211`, `2100-2140`).
- In contrast, formatted `std.io.print` goes through `std_fmt`, which calls
  `pal_print_stdout` (PAL; `WriteConsoleA`/`WriteFile` on Windows, `write(1)`
  on POSIX) — see `sf/src/std_fmt.zig:12-28` and
  `sf/src/include/zig_pal.c:100-112`.
- `std.io` **file** I/O is PAL (`pal_file_*`), so the inconsistency is confined
  to **stdout/stderr and getchar**.

The comments at `sf/src/std_io.zig:63` and `sf/src/std_debug.zig:3` say "no
cstdio"; they mean "no direct `@cInclude`", not "no C stdio in the emitted C".
`std_fmt.zig:15` already records the split: PAL stdout is unbuffered, the
`@stdoutWrite` builtin is buffered `fwrite`.

**Impact.** Mixing the two stacks on the same stream can reorder output because
`fwrite` is buffered while `pal_print_stdout` is not; buffered stdout can also
be lost on a trap/abnormal exit. This bit P3-M2: `z9dbg` switched
`std.fmt.printU32` → `std.io.printInt` so all its writes stay on the buffered
builtin path (the deviation is recorded in that fix report). On the no-CRT
Win9x path the shim's `fwrite` writes straight to `WriteFile`, so the ordering
window is narrower there.

**Windows / CRT consequence.** Default Win9x builds (mingw/MSVC/Watcom) link
their CRT, so `fwrite`/`putchar`/`getchar` require the normal CRT (msvcrt on
mingw/MSVC). **No msvcrt is required under `ZIG_NO_CRT`:** the emitted
`build_target.sh` sets `-DZIG_NO_CRT` (`sf/src/c89_emit.zig:9177,9221,9277`),
`sf/src/include/zig_nocrt.c` shims `fwrite`, `getchar`, `fgetc`, `putchar`,
`fputc`, `getenv`, `time` over `GetStdHandle`/`WriteFile`, and
`zig_runtime.c` shims `strlen`/`memcpy`/`memset`. The no-CRT harness is
`scripts/win32_cross/cross_nocrt.sh`. Any CRT symbol outside that shim set
would still need the CRT.

**Fix direction (not authorized now).** Either route the stdout/stderr/getchar
builtins through the PAL (`pal_print_stdout`/`pal_print_stderr` + a PAL
getchar), or unify `std_fmt` onto `@stdoutWrite`. Both change emitted C for
every `std.io` user, so they need their own plan + pin/golden re-baseline and a
seed rotation. Until then: document, and keep mixed `print`/`write` usage out
of latency-sensitive or panic-path output.

---

## D10 — No first-class calling conventions: callbacks need a C trampoline

**Status:** OPEN — worked around in P4-M1 with a C shim; language feature deferred. Found
2026-10-27 while building the P4 GUI layer (`docs/superpowers/plans/2026-10-24-phase2-gfx-editor-plan.md`),
Task 1.

**Symptom.** Z98 cannot declare a function or function type with a non-default calling
convention, so it cannot supply a callback to an ABI that requires one. On Win32 this blocks
`WNDPROC` (`stdcall`). The same gap blocks audio callbacks, timer/enum callbacks, COM
callbacks, and callbacks for non-Win32 ABIs — a real wall for a game or any callback-driven
API written in Z98 alone.

**Root cause.** `fn` types and `extern fn` declarations carry no calling-convention syntax,
and the emitter has no per-function convention annotation for Z98-defined functions.
`Z98_STDCALL` exists only for fn-pointer *types* (see `emitFnPtrType`); a Z98-defined
`stdcall` callback cannot be expressed. This is therefore two things: a compiler defect
(the callback cannot be written) and a language feature (first-class calling conventions).

**Workaround (P4-M1).** `sf/src/include/zig_gfx_wndproc.c` — a ~30-line C trampoline with the
`stdcall` WndProc (records `WM_SIZE`/`WM_CLOSE`, forwards to the PAL-supplied
`DefWindowProcA`). The build harness gained `EXTRA_CSRC` (default empty) to link it. The shim
imports nothing of its own (`nm -u` empty); Z98 remains the host (`main.zig`), C is a leaf.

**Feature to investigate (not scheduled).** Calling-convention support on `fn` types and
`extern fn` declarations (at least `cdecl`/`stdcall`/`fastcall`), plus the ability to define
and pass callbacks across ABIs without C glue. Touches the parser (convention syntax), sema
(type identity includes convention), and LIR/emitter (extend `Z98_STDCALL` to Z98-defined
functions), plus a fixture proving a Z98-defined `stdcall` function is callable by Win32.

**Impact.** Cosmetic for the editor (one shim); structural for future game/audio/COM work.
Left here as the "feature to investigate" so it is not lost when the language is pushed
beyond console programs.

---


## D13 — `enum(u64)` discriminants above the i64 storage maximum are unsupported

**Status:** OPEN — documented compiler limitation (found 2026-11-04 during the
syntax-emission-defects investigation; the Task 6c brief makes an enum-storage
change a STOP, so it is recorded, not fixed).

**Defect.** Enum member values are stored in an i64 slot, so a legal Zig
`enum(u64)` discriminant above `9223372036854775807` cannot be represented. The
compiler rejects it cleanly (rc 2, no `.c`) with a level-0 `error[3000]` that
names the limitation, but valid Zig source is still rejected.

**Reproducer.**

```zig
const E = enum(u64) { A = 18446744073709551615 };
```

`zig1` exits rc 2 and emits no C:

```text
error[3000]: enum member value exceeds the supported enum value range
  (values above 9223372036854775807 require u64 enum storage, not supported yet)
```

The fixture `repro/mi_matrix/enum_u64_max_reject_xmod` pins this reject, and
`repro/mi_matrix/enum_u64_max_implicit_reject_xmod` pins the implicit successor
after the storage maximum. Values at or below i64 max (including the full
`enum(i64)` and `enum(u63)` ranges) work.

**Root cause.** The enum member table (`em_items[].value`) and the shared member
walk in `sf/src/type_resolver.zig` (`enumMembersResolve`) store discriminants as
`i64`; the backing-fit gates in the local validator and
`sf/src/semantic_analyzer.zig` therefore cannot materialise a `u64` value above
i64 max. Supporting the full `u64` range needs a storage/registry-layout change
(e.g. a u64 value slot plus sign-aware fit checks), not a literal-spelling
change.

**Impact / workaround.** `enum(u64)` declarations are limited to
`0 .. 9223372036854775807` today; this is a bounded, documented divergence from
Zig. Use a plain `u64` (plus named constants) when a value above i64 max is
needed, or keep enum discriminants within the supported range. The limitation is
stated in `docs/reference/Language_Spec_Z98.md` §1.3 and the emission notes in
`docs/sf/QUICK_REF.md`.

**Reference points.** `sf/src/type_resolver.zig` `enumMembersResolve` /
`validateLocalEnumBackingFit`; `sf/src/semantic_analyzer.zig`
`semanticAnalyzerGateEnumTypeDecl`; `sf/src/type_registry.zig` enum payload
`em_items[].value`; fixtures `enum_u64_max_reject_xmod`,
`enum_u64_max_implicit_reject_xmod`; Task 6c brief STOP condition on enum
storage/layout changes.

---

## D14 — Suspending convenience wrapper cannot return an error-union payload

**Status:** OPEN — **[suspicious]** documented compiler limitation (found
2026-11-07 during Phase 3.3 Task 7; no compiler fix authorized).

**Defect.** The original D14 report claimed that a suspending function which
calls another suspending function and returns a non-void error-union payload
was rejected with `error[3043]: async parent_result slot type mismatch`. Task
0.2 could not reproduce that frontend error: the exact two-level
`Http2Error!u32` shape and 19 matrix variants emitted C with zig1 rc 0 and no
frontend diagnostic. The reproducible defect is the **tail-return step ABI**:
`return wait(c);` from an EU-returning suspending wrapper emits GCC-incompatible
C (`EU`/`Opt` result mismatch; nested tail/tail also calls the wrong tail
callee). The non-tail payload itself compiles and runs. D14 remains planned to
fix the reproducible tail-return lowering/ABI issue; the `error[3043]`
frontend claim is marked **[suspicious]** and is not to be assumed.

**Reproducer.**

```zig
fn waitAndReturn(c: *Conn) Http2Error!u32 {
    try wait(c);          // suspending callee: implicit await
    return 32;            // non-void error-union result across the frame
}
```

Observed (Task 0.2): the exact non-tail shape compiles and runs; the
tail-return variant emits a step function whose result handling is not
GCC-compatible. No `error[3043]` was observed in any run.

**Workaround.** Use `Http2Error!void` and write the value through an
out-parameter (`id_out: *u32`), as
`std_http2.http2Get/Post/GetStream/PostStream` now do; or make the convenience
function submit-only and call `http2Wait` separately.

**Reference points.** `sf/src/std_http2.zig` convenience wrappers; async
frame/result lowering (`sf/src/async_state_machine.zig`,
`sf/src/async_frame_layout.zig`); Task 7 report
`.superpowers/sdd/2026-11-07-phase33-http2-plan/task-7-report.md` fix round 2;
Task 0.2 report/inventory
`.superpowers/sdd/2026-10-29-phase35-defects-plan/task-0.2-report.md` and
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md` §9.
