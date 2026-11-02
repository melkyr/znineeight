# Phase 3.5 — Defect Closure + Documentation Truth: Design

**Status:** approved for planning (operator, 2026-10-29).
**Milestone:** 3.5 (between the 0.21.0 release closeout and Phase 3 libraries).

## 1. Intent

Close every open compiler defect tracked in `examples/torrent_example_defects.md`
(D3, D4, D5, D7.3, D8, D10, D12) and bring the documentation back to truth:
the living language spec must describe the compiler that exists, and the
self-host documentation must live in one place, split by nature (observed
implementation vs original design intent).

The operator's architecture directive binds the D8 fix: **untie from the C89
runtime where possible.** The `__bootstrap_*` helpers and PAL C functions are a
maintenance liability and would force C into any future asm backend. The PAL
already gives OS-native separation (`@isWindows()` works); the goal is clean
layers, not a one-off patch.

## 2. Goals

- **D12** — module-scope untyped array literal (`pub var arr: [3]u32 = .{ 1, 2, 3 };`) emits valid C (today it emits an illegal array-to-array assignment).
- **D7.3** — nested aggregate writes (`arr[i].field[0..] = ...`) land in real storage, never in a by-value temporary.
- **D8** — the stdout/stderr/getchar builtins route through the PAL (OS-native), ending the buffered-C-stdio vs unbuffered-PAL split. The remaining C-runtime surface is inventoried and a reduction path recorded.
- **D3** — true lazy `@import`: a comptime-dead arm never opens its file (full Zig semantics, not a broader parse probe).
- **D5 + D10** — first-class calling conventions on **definitions**: `extern "stdcall" fn f(...) { ... }` emits a balanced stdcall definition; `extern fn f(...) { ... }` emits a cdecl definition (the body is no longer silently dropped).
- **D4** — the static analyzers get a real upgrade. First a written audit (what each analyzer should do, claims vs reality, the lie list), then the fix wave to that bar.
- **Docs** — self-host docs consolidated into `sf/docs/` with `tech_docs/` (observed) and `initial_design/` (design intent); the language spec loses its zig0-era claims (the "AST lifting" lie first) and gains the missing current-era facts.
- **Closeout** — full battery, one authorized 8-pin re-baseline, seed **v129**.

## 3. Non-goals

- No new language features beyond calling-convention definitions.
- No new std modules; no GUI/debugger/async changes.
- No removal of the C runtime — only routing the stdout family off it and documenting the reduction path.
- No touching the zig0-era docs (`docs/reference/compilation_model.md`, `docs/reference/c89_emission.md`, `docs/design/**`): they stay as-is for bootstrap-vs-zig1 comparison and get archived only when the zig0 `/src` is packed into its `zig0/` folder.
- No corpus reclassification work: the frozen-1124 component must keep its exact md5.

## 4. Constraints (binding)

- Operator is sole authority; only this plan is authorized. STOP and present on ambiguity. `edit`/`fastedit` only; no sed/perl/python source transforms; sequential `zig1` runs (CWD `.zig1_*.tmp` collision); no push; explicit-path staging; `run.err` untouched.
- **Runtime single source:** emitted C support files (`zig_compat.h`, `zig_runtime.{h,c}`, `zig_pal.c`, `zig_nocrt.c`, `c_exit.c`) are generated from `sf/src/emit_support.zig` via `scripts/gen_emit_support.sh`; `scripts/check_emit_support.sh` must report 8/8 after every runtime edit.
- **Single re-baseline:** emission-shifting tasks (D8, D3) are verified functionally during development; the one authorized 8-pin re-record + full battery + seed rotation happens at closeout (Task 10).
- Current anchors (must hold through the milestone except where an authorized re-baseline moves them):
  - Seed v128: fixed point `18b4b10c8e014b486b648392d55ccdbe`; archive md5 `5093ca9eaacd03bdb29c07777749cc16`; Win9x zip md5 `eb96956e3281711c452d78c05a8587da`; lib 50; manifest md5 `8b78593a7dabb86f9f01cd9e7994ab9f`.
  - Corpus live list: 1193 dirs = 1017 OK / 58 GREEN / 118 FAIL / 0 ICE / 0 CRASH; class md5 `5167393439ffb80049ba5d3d87a2773f`; frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` (this md5 never moves).
  - 8 pins (safe / fast): mud `c52b9bb9267917fa13fa7207ae84e706` / `beea82815abed32cec443b4393f18cfb`; gol `078c7c6ce29b86f4ad8b369f534eb337` / `d9eb5b2f5ef7820af4d03a568cb1203f`; lisp `4d08641e5eed3e5c90a67ab5489c5957` / `8a1905f24bc3fe0cdb0c5eeb55af4ac3`; json `c03d635c051beb66f9226b5f55285038` / `f43bb7b8be53d609edebeeee471e9fd5`.
  - Markers 3304 lines / 37896 B; stdlib 339 fixtures + 10 crosscheck; examples 26/26.
- Byte-identity comparisons between two compilers use a shared `--lib-dir` (name-hash tokens are path-dependent).
- New fixtures live under `repro/mi_matrix/` (or `known_excluded/` when they must stay out of the corpus); the live corpus count and class md5 are re-anchored only at closeout.
- `examples/torrent_example_defects.md` stays open-only: each fixed entry is removed and its history lives in git + SDD reports (the established Phase 2.5 convention).

## 5. Approaches

**Chosen: Approach 1 — risk-ordered, single re-baseline.**
Safe emitter fixes first (D12, D7.3), then the emission-wide shifts (D8, D3) so they land before the language feature (D5/D10), then the analyzer work (audit → upgrade), then documentation, then closeout. Only D8 and D3 move existing emitted C, so the pin re-baseline is one event at the end. Trade: if D3's interner landmine trips late, earlier work is safe but closeout stalls — mitigated by making the interner re-verification the first step of Task 4.

**Dropped: subsystem batches** (parser/sema, emitter, analyzers). Grouping by phase would still force two re-baselines (D8 and D3 each move emission) and interleaves dependent syntax work (D5/D10 needs the spec decision, the spec task needs D5/D10 landed).

**Dropped: small-wins closeout first** (fix D12/D7.3/D5-minimal, rotate, defer the rest). Contradicts the full-scope decision.

### 5.1 D5/D10 syntax (operator-directed; settled)

Real Zig keeps conventions on `extern`/`callconv`; C89 gives `Z98_STDCALL`
(`__stdcall` / `__attribute__((stdcall))` / empty), already used for fn-pointer
types. The design:

- `extern "stdcall" fn f(...) { ... }` — **definition** with stdcall convention. The emitter writes `Z98_STDCALL` on the C definition, so the C compiler generates the balanced callee-cleanup epilogue (`ret $N` on i386). No hand-emitted asm.
- `extern fn f(...) { ... }` / `extern "c" fn f(...) { ... }` — **cdecl definition**; the body is emitted. This is the D5 fix: today the body is analyzed and silently dropped (no definition, no prototype → `'onCtrl' undeclared` at the C toolchain with no Z98 diagnostic).
- `extern fn f(...);` (no body) stays an external declaration, unchanged.
- `callconv(...)` stays rejected (recorded Zig divergence; Z98 carries conventions as extern strings on declarations and fn-pointer types, and one spelling is better than two).
- Type identity already includes convention (fn-pointer signature matching); definitions must agree with their prototypes.

**Alternative considered (Zig-faithful reject + `callconv` keyword):** reject any
`extern fn` with a body (clean `error`, Zig parity) and add `fn f() callconv(.x86_stdcall)`.
Dropped: it introduces a second convention spelling next to `extern "stdcall"`,
and the C89 extern-with-body form is a natural definition.

### 5.2 D8 direction (operator architecture directive; settled)

- Route `@stdoutWrite`, `@stderrWrite`, `@putChar`, `@getChar` through the PAL
  (`pal_print_stdout` / `pal_print_stderr` / PAL putchar-getchar pair). `std_fmt`
  already uses PAL. After this, the whole stdout family is one unbuffered,
  OS-native stack — the reorder window between buffered `fwrite` and unbuffered
  PAL disappears.
- Record the remaining C surface (`__bootstrap_*` in `zig_runtime.c`, `zig_pal.c`,
  `zig_nocrt.c`, `c_exit.c`) and the reduction path toward a C-free asm backend in
  `sf/docs/tech_docs/10_c_runtime.md`. Full C-runtime removal is out of scope.

### 5.3 D3 depth (settled)

Full lazy import (dead-armed `@import` never opens the file), not a broader parse
probe. **Gate:** re-verify interner-order sensitivity first — the F1 landmine
(ANY intern before source lexing flips `stdlib_crypto_modpow_xmod` OK→GREEN) is
documented in `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-4-report.md`
and its T4.1 F1 round. If the flip is still reproducible on the current tree,
apply/extend the F1 fix before touching module resolution.

### 5.4 D4 shape (operator-directed; settled)

The analyzers "can analyze but are barely working" — some output lies. Two tasks:

1. **Audit (no code):** for each analyzer (Lifetime/Provenance, NullPointer,
   DoubleFree, Signature) write down (a) what it *should* do per its contract,
   (b) what it *claims* (diagnostics emitted, docs written) vs what it *actually*
   does — every inert path (symbol-table provenance dead for locals/params,
   unseeded param null state, un-walked return/init expressions, alias-chain
   blindness), (c) a **lie list** — confident-but-wrong or vacuous diagnostics
   with evidence (the measured 44 false `WARN_6002` on self-source is the
   anchor), (d) the gap to a real-analyzer bar. Deliverable:
   `docs/superpowers/specs/2026-10-29-phase35-analyzer-audit.md`. Cluster items
   (a)–(g) in the defects doc and `docs/tech_debt/static_analyzers.md` are inputs,
   not the scope ceiling.
2. **Upgrade:** fix to the audit's bar — correct the lies, close the inert paths,
   extend to the must-work set the audit defines. Tests become fixture-driven
   (`tests/analyzers/**`), never hand-fed symbols.

### 5.5 Documentation layout (operator-directed; settled)

`sf/docs/` is the single self-host home, split by nature:

- `sf/docs/tech_docs/` — **observed** implementation (current `00`–`13` + `INDEX.md`, unchanged).
- `sf/docs/initial_design/` — **design intent as first thought**: `Design_p2.md`, `AST_PARSER_p2.md`, `AST_LIR_Lowering_p2.md`, `LIR_C89_Emission_p2.md`, `TYPE_SYSTEM_p2.md`, `STATIC_ANALYZERS_p2.md`, `RUNTIME_PAL_p2.md`, `ERROR_HANDLING_p2.md`, `TEST_HARNESS_p2.md`, `Lexer_sf.md`, `Import_Symbol_reg.md`, `COMPLEMENT.md`, `z98_external.md`, `AI_TASKS_sf.md` (moved from `docs/sf/`, cross-references updated).
- `docs/sf/` keeps the operational/user-facing set: `AGENTS.md`, `QUICK_REF.md`, `manuals/`, `std_lib/`, `Debugging.md`, `std_additions.txt`, `zig0_zig1_matriuska_bug.md`.
- The zig0-era documents **stay untouched**: `docs/reference/compilation_model.md`, `docs/reference/c89_emission.md`, and all of `docs/design/` (including `ControlFlowLifter.md`, `AST_Parser.md`) — preserved so anyone can compare bootstrap vs zig1; archived only with the future `zig0/` packing.
- The living language spec `docs/reference/Language_Spec_Z98.md` is the one exception: it must be true. Its "AST lifting" claim (`:435`) is false for zig1 (no lifting pass exists; `grep -ri lift sf/src` is empty — the lowerer's phase machines emit branches and result temps straight into LIR) and gets replaced with the real mechanism, alongside the other truth-up items (§7).

## 6. Spec truth-up contents (Task 9)

`docs/reference/Language_Spec_Z98.md`:

1. Replace the **AST lifting** bullet with the real lowering mechanism.
2. Fix the std barrel list (`:352`): 12 → 14 re-exports (`fmt`, `fold` missing).
3. Document `error[3077]` (`SEMA_GUARD_MAX` = 130 nesting limit) and the codes added by this milestone's fixes, if any.
4. Document the `--check` CLI mode (sema-only, rc 0/2, `-W` warnings→2).
5. Add the calling-convention rules from Task 5 (§5.1 above).
6. Add the lazy-`@import` semantics from Task 4 (§5.3 above).
7. Reconcile the §4 builtins list with the compiler's real registration (sema `BuiltinDesc`, lower name table, `comptime_eval`) — the spec lists `@addr`, `@name`, `@enumFromInt`, `@typeName`, `@cInclude` which are not in the sema table.
8. Re-verify §5 limitations and §7 "Not Yet Supported" against the current compiler and the mi/corpus; correct every stale claim.
9. Verify every fixture named in the spec exists, and that the corpus's capability surface is reflected.

## 7. What is left to the builder

Everything the plan does not pin: the exact code shapes of the fixes, the analyzer
upgrade details (they follow the audit), and the editorial merge decisions inside
the doc consolidation. The plan pins the decisions, the anchors, the tests, and
the order.
