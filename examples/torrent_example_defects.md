# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D15**.

Open: **D4**, **D14**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

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
