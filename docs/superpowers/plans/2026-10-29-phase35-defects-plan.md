# Phase 3.5 — Defect Closure + Documentation Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Milestone order (2026-11-07):** milestones **3.1 — general-purpose allocator** and **3.3 — HTTP/2 client** (separate plans/specs) precede this plan. 3.5 remains the compiler-improvement milestone and now includes D13/D14; nothing else in this plan changes.

**Goal:** Close all nine open defects (D3, D4, D5, D7.3, D8, D10, D12, D13, D14) and restore documentation truth (one self-host doc home, a spec that describes the real compiler), then rotate final seed v147 (v146 was an interim closeout invalidated by the expected-type sentinel regression).

**Architecture:** Risk-ordered single pass — safe emitter fixes first (D12, D7.3), then the emission-wide shifts (D8 PAL routing, D3 lazy import, D14 async result ABI), then the language/type features (D5/D10 calling conventions, D13 full `enum(u64)`), then the analyzer audit→upgrade pair, then docs, then one closeout re-baseline. Emission shifts accumulate; the 8 pins move once, at closeout.

**Tech Stack:** Z98 (strict Zig subset) compiler `sf/src/*.zig` emitting C89; PAL runtime (`zig_pal.c`, `zig_nocrt.c`, `zig_runtime.c` via `sf/src/emit_support.zig` single source); shell gates under `scripts/compiler/`; fixtures under `repro/mi_matrix/`; Wine/i686-w64-mingw32-gcc for Win32 checks.

**Spec:** `docs/superpowers/specs/2026-10-29-phase35-defects-design.md` (the plan argues from the spec; executors read both).

## Global Constraints

- Only this plan is authorized. STOP and present on ambiguity; if the plan says A, do A. `edit`/`fastedit` only (no sed/perl/python/awk source transforms); one edit at a time; no subagents inside implementers; explicit-path staging only; no push; `run.err` untouched; sequential `zig1` runs in separate CWDs (`.zig1_*.tmp` collide).
- **Runtime single source:** any edit to emitted C support files goes through `sf/src/emit_support.zig` → `bash scripts/gen_emit_support.sh <zig1>` → `bash scripts/check_emit_support.sh <zig1>` = 9/9. Never edit `sf/src/include/*` by hand.
- **Single re-baseline:** the 8 pins move exactly once, in Task 12. Tasks 3, 4, and 7 change emission; Task 6 may shift enum emission; verify them functionally and record interim diffs — do NOT touch `gate_lower_depth.sh` pins or the QUICK_REF pin table before Task 12.
- **Root-cause gate:** Task 0.5's report is the upstream map. Every fixing task (Tasks 1–9) must begin by verifying the report's root cause against its repro. If the symptom is only downstream, or the report's cause does not match, STOP. Do not patch a downstream symptom.
- Anchors (hold unless Task 12 re-anchors them): frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` NEVER moves; **seed baseline is v145** (`abbc017d…`, fixed point `cd8d283b…`); corpus live list re-measured before Task 1 (last 3.1-closeout count 1265; 3.3 added fixture dirs), growth additive only; markers 4281 lines / 49573 B (re-record at Task 12); stdlib 376 + crosscheck 10; examples 28/28; 8 pins = spec §4 list.
- **Reserved-word escape coordination (hotfix ↔ D5/D10):** the Win9x hotfix extends the mangler's C-keyword escape to the Microsoft/OpenWatcom extension words (`cdecl`, `pascal`, `near`, `far`, `huge`, `fortran`, `interrupt`, `export`, `readonly`, `stdcall`, `self`, `segment`, …) and to the Z98 runtime names (`Z98_*`, `zig_*`, `pal_*`). It escapes **source identifiers only**; emitter template tokens and convention spellings stay raw. Task 5's `extern "stdcall"` definitions must write `Z98_STDCALL` as raw template text and must not route the convention token through the mangler; its fixtures may freely use `cdecl`/`stdcall` as local names.
- Byte-identity between two compilers: shared `--lib-dir`, sequential runs.
- New fixtures: `repro/mi_matrix/` (corpus-visible) or `repro/mi_matrix/known_excluded/` (kept out). The live corpus count/class md5 is re-anchored in Task 12 only.
- Defects doc `examples/torrent_example_defects.md` stays open-only: each fixed entry is deleted in the same commit as its fix; history lives in git + the SDD report.
- Windows-facing checks run under Wine (timeout-guarded, sequential); real Win98/MSVC/OWC validation is operator-owned.
- SDD workspace: `.superpowers/sdd/2026-10-29-phase35-defects-plan/` (ledger `progress.md`, per-task briefs/reports). Every task appends its report there.

## Review Focus

| # | Input class / failure mode | Owning task + test |
|---|---|---|
| 1 | Mixed stdout traffic ordering (the D8 defect being fixed): `std.io.print` + `@stdoutWrite` + `@putChar` on one stream must interleave in program order on BOTH the CRT and no-CRT paths; buffered data must not be lost on a trap | Task 3: ordering fixture run under gcc-CRT and `cross_nocrt.sh` |
| 2 | D3 intern-order landmine: moving module resolution flips `stdlib_crypto_modpow_xmod` OK→GREEN (F1 class) | Task 4 step 1 re-verification; full corpus run before/after |
| 3 | D3 false-load surface: a dead arm importing a file that EXISTS but is unparsable on this target must also not load (not just missing files) | Task 4: fixture with an unparsable dead-arm import |
| 4 | D5/D10 ABI balance: a `extern "stdcall"` definition called directly (not via fn pointer) and registered as a Win32 callback must both clean the stack correctly; prototype and definition conventions must agree | Task 5: objdump `ret $N` check + Wine C-host callback run |
| 5 | D12/D7.3 non-regression: the already-working typed array-literal and simple aggregate-write paths must stay byte-identical | Tasks 1–2: emitted-C diff on the working shapes (must be empty) |
| 6 | D13 enum range: `enum(u64)` at `18446744073709551615`, implicit successor beyond `u64` max, negative/`enum(i64)` behavior, duplicate tags | Task 6: `enum_u64_max_ok_xmod`, `enum_u64_max_implicit_reject_xmod`, existing signed/duplicate fixtures |
| 7 | D14 tail-return EU wrapper: `return wait(c);` must emit a GCC-compatible step ABI, with the nested tail/tail wrong-callee symptom gone; the non-tail `error[3043]` claim is **[suspicious]** and not assumed | Task 7: `d14_original_http2_eu`, `d14_two_level_matrix`, existing `recvSomeAsync`/`mud_server` shapes |

---

### Task 0: Repro inventory — all nine defects + adjacent/sibling scan

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`
- Create: `repro/mi_matrix/module_untyped_array_init_ok_xmod/` (D12)
- Create: `repro/mi_matrix/known_excluded/nested_agg_write_ok/` (D7.3)
- Create: `repro/mi_matrix/known_excluded/stdout_order_ok/` (D8)
- Create: `repro/mi_matrix/known_excluded/lazy_import_fold_ok/` and `known_excluded/lazy_import_unparsable_dead_ok/` (D3)
- Create: `repro/mi_matrix/known_excluded/stdcall_def_ok/` and `known_excluded/cdecl_def_ok/` (D5/D10)
- Create: `repro/mi_matrix/enum_u64_max_ok_xmod/` (D13)
- Create: `repro/mi_matrix/async_wrapper_eu_payload_ok_xmod/` (D14)
- Create: `tests/analyzers/d4_contract_probe.zig` (D4 probe; the audit expands this set)

**Interfaces:**
- Produces: one committed repro per defect (D4 is a probe set), a written inventory, and the **adjacent/sibling findings list**. Tasks 1–9 consume these fixtures; they do not recreate them. No fix is made here.
- Consumes: the defect descriptions in `examples/torrent_example_defects.md` and the code locations in the Phase 3.5 spec.

- [ ] **Step 1: Create the inventory document.** Table columns: defect, fixture path, expected post-fix contract, current RED/baseline evidence, owner task. Add an "Adjacent/sibling findings" section with `ADJ-<n>` entries and a disposition (`in-scope under D<n>` or `deferred / next free D15+`). No fixes in this task.
- [ ] **Step 2: D12 repro.** `pub var arr: [3]u32 = .{ 1, 2, 3 };` + mutation/print; expected post-fix output; current RED is gcc `assignment to expression with array type`. Also cover a 1-D struct-array and a 2-D untyped literal as sibling probes; record whether they are the same or adjacent.
- [ ] **Step 3: D7.3 repro.** `arr[i].field[0..] = ...` / `arr[i].field = ...` where `field` is a slice/array; expected post-fix storage; current RED shows pre-write values. Add a sibling probe for pointer-to-aggregate and nested index/field chains.
- [ ] **Step 4: D8 repro.** Interleave `std.io.print("A\n")`, `@stdoutWrite("B\n")`, `@putChar('C')`, `@getChar()`; expect program order. Record the current CRT and no-CRT baseline; the ordering value is proven post-fix on both.
- [ ] **Step 5: D3 repros.** `if (1 == 1) @import("exists.zig") else @import("missing.zig")` and the same with an **unparsable** dead-arm file. Current RED is the parse-probe `error[3048]` class. Add sibling probes for `switch`, `and`/`or`, nested dead imports, and live-arm selection.
- [ ] **Step 6: D5/D10 repros.** `pub extern "stdcall" fn cb(x: u32) i32 { return x + 1; }` and a bare/`"c"` body definition. Current RED is no definition / `'cb' undeclared`. Add sibling probes for variadic externs, prototype/definition convention mismatch, and direct vs fn-pointer calls; the Wine callback host stays Task 5.
- [ ] **Step 7: D13 repro.** `const E = enum(u64) { A = 18446744073709551615 };` with a runtime read/print; current RED is the explicit `error[3000]` limitation. Keep the existing `enum_u64_max_reject_xmod` and `enum_u64_max_implicit_reject_xmod` as current-behavior fixtures; Task 6 retires the max-reject fixture and retargets the implicit-reject fixture to the `u64` max successor. Add sibling probes for signed enums, implicit successors, duplicate tags, and const enum switches.
- [ ] **Step 8: D14 repro.** Suspending `wait(c)` plus `fn wrapper(c: *u32) E!u32 { try wait(c); return 32; }`, success and error paths. Record the current evidence and classify it: `error[3043]` if actually reproduced (**[suspicious]/unproven**) or the tail-return GCC-incompatible step ABI. Add sibling probes for void, optional, aggregate, and tail-vs-non-tail returns.
- [ ] **Step 9: D4 probe.** `tests/analyzers/d4_contract_probe.zig` captures a current false positive/negative across the four analyzers (Lifetime/Provenance, NullPointer, DoubleFree, Signature). Record current diagnostics; the Task 8 audit defines the full must-work set.
- [ ] **Step 10: Run everything and record evidence.** For each repro: exact command, rc, diagnostics, emitted-C/compile result, and expected post-fix output. Use `-ffast` and `-fsafe` where the fixture runs. A fixture that is expected to fail pre-fix records the failure; a fixture that passes pre-fix records why it is a regression oracle.
- [ ] **Step 11: Adjacent/sibling scan.** For each defect, inspect the same lowering/emitter/analyzer/import/async path and record `ADJ-<n>` findings. Classify in-scope vs deferred. If an adjacent finding blocks the planned fix or contradicts the spec, STOP and present; do not fix it here.
- [ ] **Step 12: Commit.** These are compiler repros, not stdlib fixtures: do **not** edit `scripts/stdlib/expected_dirs.txt`. Corpus-visible dirs are classified by `scripts/corpus/`; `known_excluded/` and `tests/analyzers/` stay out. Commit `test(repro): add Phase 3.5 defect repros and inventory` + the inventory doc. No source fix in this commit.

### Task 0.1: D14 exact-shape repro retry (test-only)

**Files:**
- Modify: `repro/mi_matrix/async_wrapper_eu_payload_ok_xmod/main.zig` (add the exact `Http2Error`-shaped error set + runtime id shape)
- Create: `repro/mi_matrix/known_excluded/d14_http2_wrapper_ok/` (real `std_http2.http2Wait`/`http2Get` wrapper shapes; compile-only if a server is required)
- Create: `repro/mi_matrix/known_excluded/d14_tail_http2_wrapper_ok/` (exact-shape tail-return variant)
- Modify: `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md` (D14 / ADJ-17 evidence)
- No source fix; no Task 7 work.

**Interfaces:**
- Consumes: Task 0's D14 fixtures and inventory; `examples/torrent_example_defects.md` D14; Phase 3.5 spec §5.7; `sf/src/std_http2.zig` convenience wrappers.
- Produces: a definitive D14 matrix — exact `Http2Error!u32` shape, non-tail `try wait(c); return id;`, tail `return wait(c);`, error propagation, and the real `http2Wait`/`http2Get` wrapper shapes. Either a committed fixture that reproduces `error[3043]`, or exact evidence that it is not reproducible and the spec claim is wrong. The tail-return GCC ABI RED must remain a required D14 fix.

- [ ] **Step 1: Context pass.** Read the spec §5.7, the D14 entry, Task 0's D14 fixture/inventory, and `std_http2.http2Wait`/`http2Get`. Record the exact documented shape and the current claim before writing fixtures.
- [ ] **Step 2: Exact local shape.** Use an error set with the same name count/shape as `Http2Error` (not `error{Boom}`) and a runtime `id` value, not a literal `32`; test non-tail `try wait(c); return id;`.
- [ ] **Step 3: Tail shape.** Test `fn wrapper(c) E!u32 { return wait(c); }` with the exact error set; preserve the `sibling_tail.zig` GCC ABI failure as the known RED.
- [ ] **Step 4: Real std_http2 shapes.** Compile `http2Wait` and `http2Get` wrapper forms against the current `std_http2`; if a live server is needed, do compile-only and record that limitation.
- [ ] **Step 5: Error/edge matrix.** Test error propagation, optional payload, aggregate payload, and non-tail vs tail; record which pass and which fail.
- [ ] **Step 6: Run and record.** Use `/workspace/znineeight/zig1/zig1_5_clean`; for each shape record exact command, rc, diagnostics, emitted-C/compile result, and `-ffast`/`-fsafe` where runnable. Do not claim an unobserved `error[3043]`.
- [ ] **Step 7: Resolve and STOP.** If `error[3043]` reproduces, commit the fixture and inventory evidence. If it does not, commit the exact-shape fixture plus the negative evidence and STOP; do not amend the spec or re-scope Task 7 in this task. If the evidence contradicts the spec, present it and wait for the operator.
- [ ] **Step 8: Commit** `test(repro): retry D14 exact-shape wrapper and record evidence` (only Task 0.1 files). No source fix.

### Task 0.2: D14 frontend-vs-tail-ABI matrix (test-only)

**Files:**
- Create: `repro/mi_matrix/known_excluded/d14_original_http2_eu/` (exact old `Http2Error!u32` two-level shape)
- Create: `repro/mi_matrix/known_excluded/d14_two_level_matrix/` (multi-await/order/type variants)
- Modify: `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`
- No source fix; no Task 7 work.

**Interfaces:**
- Consumes: Task 0.1's exact-shape evidence; the old `submitUrl`/`http2Get` shape in `git show 022a59f2:sf/src/std_http2.zig` (and `022a59f2^` for the prior void shape); `sf/src/async_analysis.zig` P2 and `sf/src/async_state_machine.zig` P4.
- Produces: a frontend-vs-ABI classification. Either a fixture that reproduces the D14-specific `error[3043]` (`async parent_result slot type mismatch`), or exact evidence that only the GCC tail ABI fails. If both occur, record **two distinct D14 bugs**.

- [ ] **Step 1: Reconstruct the exact chain.** Use `git show 022a59f2:sf/src/std_http2.zig` to recover the `submitUrl(...) Http2Error!u32 { ...; try http2Wait(c, id); return id; }` + `http2Get(...) Http2Error!u32 { return submitUrl(...); }` shape. Reproduce it compile-only in `d14_original_http2_eu`; do not edit `std_http2`.
- [ ] **Step 2: Two-level matrix.** Add: inner `E!u32` with one leaf await; outer tail `return inner(c);`; outer non-tail `var x = try inner(c); return x;`; local 15-name `E` vs imported `h2.Http2Error`; exact runtime id.
- [ ] **Step 3: Order matrix.** Add two value-returning awaits in source order and swapped; mixed void/value awaits in both orders; nested non-tail/tail. Record which shape changes P2/P4 slot order.
- [ ] **Step 4: Wrapper matrix.** Add `try`/`catch`/`if` wrappers around the awaits; record whether they change slot reservation.
- [ ] **Step 5: Run and classify.** For each shape run `zig1 -ffast` and `-fsafe` with `--dump-c89` and `-o`; record rc, exact diagnostic, emitted-C presence, and gcc result. Classify: frontend `error[3043]` exact message / GCC tail ABI / both / unrelated.
- [ ] **Step 6: STOP and record.** Update the inventory with the exact evidence and classification. If the frontend message reproduces, commit it. If only the tail ABI reproduces, commit the negative frontend evidence. If both reproduce, record two D14 bugs and STOP for the operator. Do not amend the spec or re-scope Task 7 in this task.
- [ ] **Step 7: Commit** `test(repro): classify D14 frontend vs tail-ABI triggers` (only Task 0.2 files). No source fix.

### Task 0.5: Upstream root-cause investigation (no fixes)

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-upstream-root-cause.md`
- Read-only inputs: the Task 0/0.1/0.2 repros, `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`, `examples/torrent_example_defects.md`, the Phase 3.5 spec, and the compiler pipeline (`sf/src/parser.zig`, `semantic_analyzer.zig`, `type_resolver.zig`, `type_registry.zig`, `lower.zig`, `c89_emit.zig`, `analyzer.zig`, `async_*.zig`, `import_resolver.zig`)
- No source fix; no Task 1 work.

**Interfaces:**
- Consumes: the nine defect repros and their recorded RED/baseline evidence.
- Produces: one upstream root-cause entry per defect, with the failing pass/layer, exact `file:line`, the causal chain from source to symptom, why lower-layer patches would be wrong, a **fix contract** (what must become true at the root), and the regression probes that prove it. D5 and D10 get separate entries if their causes differ; D4 is one cluster with per-analyzer causes; D14 records the tail-ABI root cause and the **[suspicious]** `error[3043]` claim separately.

- [ ] **Step 1: Build the matrix.** For each defect, list the repro path, exact symptom, whether it is frontend/ICE, emitted-C/gcc, analyzer, or documentation, and the pass where the wrong state first appears.
- [ ] **Step 2: Trace each defect upstream.** Follow the pipeline from parsing/type resolution through lowering and emission (or analyzer/import/async) to the first incorrect state. Record `file:line` and the code responsible, not the first place the symptom is visible.
- [ ] **Step 3: Separate root cause from symptom.** For each defect, list the downstream sites that could be patched and why each would be a patch. The report must name the single upstream cause (or explicitly say the defect has two independent causes).
- [ ] **Step 4: Write the fix contract.** For each defect, state what must change at the root, what must not change, and the exact repros/sibling probes that prove the root fix. The fixing task must verify this contract before editing.
- [ ] **Step 5: D14 split.** Record the tail-return step-ABI root cause separately from the `error[3043]` frontend claim. State that `error[3043]` is **[suspicious]**/unreproduced and must not be “fixed” by guessing.
- [ ] **Step 6: STOP gate.** If a root cause cannot be established, if two defects share a cause, or if the evidence contradicts the spec/plan, STOP and present the ambiguity instead of inventing a cause.
- [ ] **Step 7: Commit** `docs(specs): Phase 3.5 upstream root-cause investigation` (only the report). No source fix.

### Task 1: D12 — module-scope untyped array literal

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (module-scope var-decl typing; mirror the local rule at `:6681-6685`). Use `sf/src/lower.zig` only if the sema rule cannot be applied there; the emitter is not the fix site.
- Test: `repro/mi_matrix/module_untyped_array_init_ok_xmod/main.zig` (+ `expected.txt`/`expected.rc`)

**Interfaces:**
- Consumes: the existing typed array-literal path (the one `repro/mi_matrix/multiarray_literal_init_xmod` exercises — element-wise copy, no whole-aggregate `=`) and the local var-decl typing rule.
- Produces: `pub var arr: [3]u32 = .{ 1, 2, 3 };` compiles rc=0 and the emitted C builds with gcc. Later tasks rely on nothing else from this fix.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D12 report entry; compare its cause/evidence with `module_untyped_array_init_ok_xmod`. If it does not match or is only a downstream symptom, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0 fixture.** Use `module_untyped_array_init_ok_xmod` from Task 0; confirm its expected post-fix contract and RED baseline. If Task 0 recorded an adjacent D12 shape, extend this fixture here; do not recreate the base repro.
- [ ] **Step 2: Verify RED.** `zig1 -o out module_untyped_array_init_ok_xmod/main.zig` → rc=0 today but gcc rejects the emitted C with `assignment to expression with array type` (the defect). Record the exact C (`zG_..._arr = zT_...;`).
- [ ] **Step 3: Fix at the root** — apply the declared array type to the module-scope initializer in sema, mirroring the local `var` rule at `sf/src/semantic_analyzer.zig:6681-6685`, so lowering uses the existing element-wise array path instead of materialising a `Tup_*` temp + whole-aggregate assignment. Do not patch the emitter.
- [ ] **Step 4: Verify GREEN** — fixture compiles, gcc-clean, output matches `expected.txt`, rc matches. Re-emit `multiarray_literal_init_xmod` and diff its C against the pre-fix emission: **must be unchanged** (Review Focus 5).
- [ ] **Step 5: Commit** `fix(sema): type module-scope untyped array literals as the declared array (Phase3.5 D12)` + delete D12 from `examples/torrent_example_defects.md` + SDD report.

### Task 2: D7.3 — nested aggregate write targets a by-value temp

**Files:**
- Modify: `sf/src/lower.zig` (slice-base lvalue composition, `slice_expr` assignment arm, field-array element copy).
- Modify: `sf/src/semantic_analyzer.zig` (same-type whole-array assignment through an lvalue chain is assignable; remove the false `warning[3000]`; incompatible types still warn/error).
- Do not patch `c89_emit.zig`.
- Test: `repro/mi_matrix/known_excluded/nested_agg_write_ok/main.zig` (+ expected), plus the sibling `sibling_slice_of_array.zig` direct-assignment case and `sibling_field_array_assign.zig`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `arr[i].field[0..] = ...` / `arr[i].field = ...` writes land in `arr`'s storage, including the direct slice-assignment form. The wireguard demo's explicit-pointer workaround becomes unnecessary (but is left in place).
- Direct slice assignment is equal-length: static mismatch is a clean `error[3000]`; dynamic mismatch traps as a mode-independent precondition in both `-fsafe` and `-ffast`; array-element slices are a clean reject. Partial copies use an explicit destination slice or `std.mem.copyU8`.
- `arr[i].field = srcArray` compiles without `warning[3000]` when the source and field types are the same array type.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D7.3 report entry; compare both lower causes and the sema warning source with `nested_agg_write_ok`. If either is only a downstream symptom or the warning is not sema assignability, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0 fixture.** Use `known_excluded/nested_agg_write_ok` from Task 0; confirm the store is lost pre-fix (output shows pre-write values). Extend it here if the adjacent scan found another nested-store shape in scope; do not recreate the base repro.
- [ ] **Step 2: Locate the temp** — identify where the nested write materialises a by-value temp (lowering of `field_access`/`index_access` lvalues, emitter `emitBaseIdxAccess` family). Record the mechanism in the report before fixing.
- [ ] **Step 3: Fix the root causes.** (a) Compose the slice base as an lvalue storage address instead of lowering it as an rvalue (`sf/src/lower.zig:12527`); reuse the existing `lowerLValueAddr` composition. (b) Add the missing `slice_expr` arm to `lowerAssignLValue` (`:6664`) so direct `arr[i].field[0..] = src[0..]` composes the same storage address instead of hitting the unsupported-lvalue ICE. (c) In `sf/src/semantic_analyzer.zig`, treat a same-type whole-array assignment through a field/index/deref lvalue chain as assignable, because lowering now performs the element-wise copy; remove the false `warning[3000]` for that shape and keep genuine type mismatches. Do not suppress the warning in lowering or the emitter.
- [ ] **Step 4: Verify GREEN** — `nested_agg_write_ok` prints `77 88 77 88`; `sibling_slice_of_array.zig` builds and writes to the aggregate; `sibling_nested_chain` prints the written values; `sibling_field_array_assign.zig` prints `21 24` with **no** `warning[3000]`; direct slice assignment enforces equal lengths (static reject; dynamic mode-independent trap); `gate_warn_clean.sh` stays green; the simple working shapes (`s.f = v`, `a[i] = v`, typed slice writes) re-emit **byte-identical** (Review Focus 5).
- [ ] **Step 5: Commit** `fix(lower,sema): compose slice lvalues and accept same-type array field assignment (Phase3.5 D7.3)` + delete D7.3 + report.

### Task 3: D8 — stdout builtins through the PAL + runtime-C surface doc

**Files:**
- Modify: `sf/src/c89_emit.zig` (builtin lowering `@stdoutWrite`/`@stderrWrite`/`@putChar`/`@getChar` → PAL calls; the `#include <stdio.h>` decision those builtins trigger)
- Modify: `sf/src/emit_support.zig` (PAL putchar/getchar additions; any `zig_nocrt.c` shim adjustment) → regenerate `sf/src/include/*`
- Modify: `sf/docs/tech_docs/10_c_runtime.md` (C-runtime surface inventory + reduction path)
- Test: `repro/mi_matrix/known_excluded/stdout_order_ok/main.zig` (mixed `std.io.print` + `@stdoutWrite` + `@putChar`)

**Interfaces:**
- Consumes: PAL print entry points (`pal_print_stdout` in `zig_pal.c`); the runtime single-source loop.
- Produces: `pal_print_stderr`, `pal_putchar`, `pal_getchar` (or equivalent PAL read) usable by the emitter; emitted stdio dependency from the stdout family removed. D8 has no pre-fix RED (it passes by luck); the fixture is the post-fix CRT + no-CRT regression oracle. Task 11 documents the new behavior in the spec.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D8 report entry; compare its cause/evidence with `stdout_order_ok`. If it does not match or is only a downstream symptom, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0 fixture.** Use `known_excluded/stdout_order_ok` from Task 0; record the pre-fix CRT and no-CRT baseline. It may pass or pass-by-luck; the ordering test's value is post-fix on BOTH paths. Extend it here only if the adjacent scan found an in-scope stdout shape.
- [ ] **Step 2: Inventory the current surface** (write-first): which emitted symbols come from `stdio.h`, `zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c`, `__bootstrap_*`. Record in the report; this becomes the doc body.
- [ ] **Step 3: Implement PAL routing** — lower the four builtins to PAL calls; add the missing PAL putchar/getchar in `emit_support.zig`; regen + `check_emit_support.sh` 9/9.
- [ ] **Step 4: Verify** — ordering fixture byte-exact under gcc CRT AND `scripts/win32_cross/cross_nocrt.sh` (no-CRT); existing stdlib/examples outputs unchanged (they use `std.io.print`, already PAL); `check_emit_support.sh` 9/9; gate `gate_warn_clean.sh` still GREEN (the new PAL calls must stay `-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long`-clean). Record the emitted-C diff vs base (expected non-empty for std.io users — this is the authorized shift).
- [ ] **Step 5: Runtime-C surface doc** in `10_c_runtime.md`: the inventory + reduction path toward a C-free backend (which PAL calls would become raw syscalls / OS calls in an asm backend; what `__bootstrap_*` would become).
- [ ] **Step 6: Commit** `fix(emit): route stdout/stderr/getchar builtins through the PAL (Phase3.5 D8)` + delete D8 + report.

### Task 4: D3 — interner re-verification + full lazy `@import`

**Files:**
- Modify: `sf/src/parser.zig`, `sf/src/import_resolver.zig`, `sf/src/main.zig` (module closure / phase order), `sf/src/semantic_analyzer.zig` (sema import gate) — exact shape follows the verification result
- Test: `repro/mi_matrix/known_excluded/lazy_import_fold_ok/main.zig` (+ an unparsable-dead-arm variant)

**Interfaces:**
- Consumes: `parserFoldComptimeBool` / `dead_import_depth` (current probe), `comptimeEvalEvaluate`'s fold set (the superset), the F1 fix from `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/` (T4.1).
- Produces: a comptime-dead `@import` arm never opens its file. Task 11 documents the semantics.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D3 report entry; compare its cause/evidence with the lazy-import repros. If it does not match or is only a downstream symptom, STOP. Do not patch a symptom.
- [ ] **Step 1: Re-verify the interner landmine (gate before any code).** With the current tree: confirm `stdlib_crypto_modpow_xmod` is OK; then perturb intern order (one extra intern before source lexing) in a throwaway build and confirm/deny the OK→GREEN flip. Result goes in the report. **If it still flips:** apply/extend the T4.1 F1 fix and re-verify before proceeding. If unfixable in-scope: STOP and present.
- [ ] **Step 2: Run the Task 0 fixtures.** Use `known_excluded/lazy_import_fold_ok` and `known_excluded/lazy_import_unparsable_dead_ok` from Task 0; confirm the current `error[3048]`-class RED. Extend them here if the adjacent scan found another dead-arm shape in scope.
- [ ] **Step 3: Implement full deferral.** `@import` resolution must be deferred until the comptime evaluator selects the live arm; the parse-time probe must no longer be the gate that opens files. Extending `parserFoldComptimeBool` to match more fold cases is a symptom patch and is not sufficient. Wrong-module selection must remain impossible.
- [ ] **Step 4: Verify GREEN** — both fixtures rc=0, no file open on the dead arm (strace/open-count evidence in report); the established conditional-import shapes (`@isWindows()` idiom, `conditional_import_lazy_xmod`) unchanged; full corpus run: only new fixtures move, `stdlib_crypto_modpow_xmod` stays OK, frozen-1124 md5 unchanged. Record emitted-C diff vs base (authorized shift).
- [ ] **Step 5: Commit** `fix(import): comptime-dead import arms never load files (Phase3.5 D3)` + delete D3 + report.

### Task 5: D5 + D10 — calling conventions on definitions

**Files:**
- Modify: `sf/src/parser.zig` (`parserParseExternDecl`/`parserParseFnDecl` — extern-with-body becomes a definition), `sf/src/semantic_analyzer.zig` (definition/prototype convention agreement), `sf/src/lower.zig`, `sf/src/c89_emit.zig` (emit `Z98_STDCALL` on definitions; mirror the fn-pointer pattern at the `emitFnPtrType` call sites)
- Test: `repro/mi_matrix/known_excluded/stdcall_def_ok/main.zig` (+ cdecl extern-body variant), plus a Wine C-host callback harness under `examples/z98/` or `scripts/win32_cross/` evidence

**Interfaces:**
- Consumes: `Z98_STDCALL` macro (`sf/src/include/zig_compat.h` — via `emit_support.zig` if changed), existing convention strings on declarations/fn-pointer types.
- Produces: `extern "stdcall" fn f(...) { ... }` = stdcall definition; `extern fn f(...) { ... }` = cdecl definition; `callconv(...)` still rejects. Task 11 documents this.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D5 and D10 report entries; compare them with the definition fixtures. If either is only a downstream symptom, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0 fixtures.** Use `known_excluded/stdcall_def_ok` and `known_excluded/cdecl_def_ok` from Task 0; record the current emission (no definition / `'cb' undeclared` at gcc, zero Z98 diagnostics). Extend them here if the adjacent scan found another definition shape in scope.
- [ ] **Step 2: Implement definitions at the root.** Fix the `is_extern` conflation (`sf/src/lower.zig:15006`): `is_extern` must mean declaration-only (no body); a body-carrying `extern` is a definition under the original symbol name (extern linkage), not a mangled name. Emit `Z98_STDCALL` for `"stdcall"` and cdecl for bare/`"c"`. Prototype and definition conventions must agree (sema check). `callconv(...)` still rejects `error[2000]`. Do not fix this by only flipping the emitter’s definition gate.
- [ ] **Step 3: ABI evidence.** Build the stdcall fixture with i686-w64-mingw32-gcc; objdump the definition showing the callee-cleanup epilogue (`ret $N`, N = arg bytes); a Wine run where a small C host registers the Z98-defined function as a callback and invokes it (balanced stack, correct return) — the shape z9play M6 needed.
- [ ] **Step 4: Verify GREEN** — both fixtures rc=0 gcc-clean; existing extern *declarations* unchanged (byte-identical C for declaration-only programs); corpus + stdlib green; `callconv` still rejects (fixture).
- [ ] **Step 5: Commit** `feat(sema): extern function definitions with calling conventions (Phase3.5 D5/D10)` + delete D5 and D10 + report.

### Task 6: D13 — full `enum(u64)` discriminant range

**Files:**
- Modify: `sf/src/type_registry.zig` (`EnumMember.value` representation), `sf/src/type_resolver.zig` (`enumMembersResolve`, the `evalConstI64Full`/u64 constant path, `validateLocalEnumBackingFit`, `evalConstEnumSourceExceedsI64Max`), `sf/src/semantic_analyzer.zig` (`semanticAnalyzerGateEnumTypeDecl` and local enum validation), `sf/src/const_init_eval.zig` (enum-member consumers), `sf/src/c89_emit.zig` (u64 constant emission if needed)
- Test: `repro/mi_matrix/enum_u64_max_ok_xmod/`, `repro/mi_matrix/enum_u64_max_implicit_reject_xmod/`, plus the existing signed/negative/duplicate enum fixtures

**Interfaces:**
- Consumes: the current `EnumMember` (`name_id`, `value: i64`) and the shared `enumMembersResolve` walk; `evalConstI64Full`; the existing enum-member consumers in the type resolver, semantic analyzer, emitter, and const-init evaluator.
- Produces: full `enum(u64)` discriminants. `18446744073709551615` is accepted and emitted correctly; an implicit successor beyond `u64` max is rejected cleanly; signed/negative enums and duplicate-tag behavior are unchanged. Later tasks rely only on the compiler accepting the new range.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D13 report entry; compare its cause/evidence with `enum_u64_max_ok_xmod`. If it does not match or is only a downstream symptom, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0 fixture.** Use `enum_u64_max_ok_xmod` from Task 0; confirm the current `error[3000]` RED. Also run the existing `enum_u64_max_reject_xmod` and `enum_u64_max_implicit_reject_xmod` (current-behavior fixtures). Do not recreate the success repro; extend it here if the adjacent scan found another in-scope enum shape. Retire `enum_u64_max_reject_xmod` and retarget `enum_u64_max_implicit_reject_xmod` to an implicit successor beyond `u64` max as part of this task.
- [ ] **Step 2: Verify RED.** `zig1 -o out enum_u64_max_ok_xmod/main.zig` → rc 2 with `error[3000]: enum member value exceeds the supported enum value range (values above 9223372036854775807 require u64 enum storage, not supported yet)`. Record the emitted diagnostic and the rejected member.
- [ ] **Step 3: Audit and STOP gate.** The root is the `i64` `EnumMember.value` / `evalConstI64Full` representation (`sf/src/type_registry.zig:108`, `sf/src/type_resolver.zig:1405-1408`); the validators are downstream. Map every `em_items[].value` consumer and choose the representation (64-bit raw value plus backing-signed interpretation, or paired signed/unsigned). If full support requires a broad enum-layout migration or changes emitted C for existing enums beyond the new range, STOP and present the options before coding.
- [ ] **Step 4: Implement the representation change.** Change `EnumMember.value` and the constant-evaluation path to carry the full u64 range, then update the shared member walk, duplicate/auto-successor logic, backing-fit validation, const-init/lowering consumers, and the C emitter. Do not merely relax the validators. Keep signed behavior and the existing `error[3062]`/`error[3055]` paths intact.
- [ ] **Step 5: Verify GREEN.** The max fixture compiles and selects the max branch (prints `7`); the emitted C carries the u64 max constant or a comparison against the literal, proving the numeric value, not only branch selection; the implicit-successor fixture rejects at `u64` max; signed/negative/duplicate fixtures are unchanged; emitted C is gcc-clean under `-ffast` and `-fsafe`; the fixture stays corpus-visible (or moves to `known_excluded/` if it must stay out of the corpus).
- [ ] **Step 6: Commit** `feat(type): support the full enum(u64) discriminant range (Phase3.5 D13)` + delete D13 from `examples/torrent_example_defects.md` + SDD report.

### Task 7: D14 — tail-return EU wrapper step ABI

**Files:**
- Modify: `sf/src/lower.zig` (tail-call suppression for suspending callees), `sf/src/async_state_machine.zig` (tail-call handling, parent-result slot typing and step result path), `sf/src/async_frame_layout.zig` (result/parent-result fields), and `sf/src/async_analysis.zig` only if P2 reservation/counting needs adjustment
- Create: `repro/mi_matrix/known_excluded/d14_sync_tail_ok/` (synchronous tail call inside an async frame; the `copyTailCall` name-id probe)
- Test: `repro/mi_matrix/known_excluded/d14_original_http2_eu/`, `repro/mi_matrix/known_excluded/d14_two_level_matrix/`, `repro/mi_matrix/known_excluded/d14_sync_tail_ok/`, `repro/mi_matrix/known_excluded/d14_tail_http2_wrapper_ok/`, and `async_wrapper_eu_payload_ok_xmod/` (success and error propagation), plus existing `recvSomeAsync`/`mud_server` async shapes

**Interfaces:**
- Consumes: Task 0.2's classification; the current P2/P3/P4 async layout and step ABI; the ASYNC_FIELD_RESULT / ASYNC_FIELD_PARENT_RESULT machinery; `@asyncSuspend`/implicit-await lowering.
- Produces: a tail-returning suspending EU wrapper emits a GCC-compatible step ABI. The non-tail `error[3043]` claim is **[suspicious]/unproven** and is not a Task 7 target. `std_http2` keeps its `id_out` workaround; no public API change is required.

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D14 tail-ABI report entry; confirm the tail-callee/result root cause matches the tail fixtures. The `error[3043]` frontend claim is [suspicious]; if the report treats it as real without evidence, STOP. Do not patch a symptom.
- [ ] **Step 1: Run the Task 0.2 result.** Task 0.2 records no reproducible frontend `error[3043]`; the scope is the tail-return GCC step ABI. If it ever records a frontend `error[3043]`, STOP and present rather than fix an unproven frontend defect. Do not assume the non-tail RED.
- [ ] **Step 2: Verify RED.** Record the tail-return failure only: the exact `EU`/`Opt` result mismatch, and the nested tail/tail wrong-callee symptom. Keep the exact diagnostics and emitted step signature in the report.
- [ ] **Step 3: Audit and STOP gate.** Map the P2/P3/P4 layout, the reserved parent-result slot, and the step-result return path for the tail-return shape. If the fix requires redefining the step ABI for all suspending functions or breaks the `mud_server` async shape, STOP and present the options before coding.
- [ ] **Step 4: Implement both root fixes.** (a) Suppress the generic tail-call optimization for a suspending callee so the call remains `call_direct` and is rewritten into the normal implicit await (do not teach the async transform to treat `.tail_call` as an await; the tail call is not a real tail call here). (b) Fix `copyTailCall` so it rebases only real temp indices and preserves the callee name id (`sf/src/async_state_machine.zig:317-323`). Then correct the tail-return result/parent-result typing so the EU payload is returned through the GCC-compatible step ABI; preserve async frame sizes and `recvSomeAsync` behavior where possible.
- [ ] **Step 5: Verify GREEN.** The imported exact fixture compiles (compile-only; expected `d14 original http2 eu compile-only`), the local tail fixture builds and runs (`42 0`/`0 1`), and the new synchronous-tail probe proves the `copyTailCall` name-id fix (the tail/tail wrong-callee alone is not sufficient because TCO suppression removes it); the non-tail, two-value-order, mixed void/value, `try`, `catch`, and `if` shapes stay green; `recvSomeAsync`, `http2Wait`, `mud_server`, and z9torr async fixtures remain green in `-ffast` and `-fsafe`; record the emitted-C diff versus base.
- [ ] **Step 6: Commit** `fix(async): correct the tail-return EU wrapper step ABI (Phase3.5 D14)` + delete D14 from the defects doc + SDD report.

### Task 8: D4-pre — analyzer audit (no code)

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-analyzer-audit.md`
- Inputs (read-only): `sf/src/analyzer*.zig`, `sf/src/semantic_analyzer.zig`, `docs/tech_debt/static_analyzers.md`, the D4 cluster entry in `examples/torrent_example_defects.md`, `.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-5-report.md`, the Task 0 `tests/analyzers/d4_contract_probe.zig` and `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`, `sf/docs/initial_design/STATIC_ANALYZERS_p2.md` (after Task 10's move; else `docs/sf/STATIC_ANALYZERS_p2.md`)

- [ ] **Step 0: Confirm the Task 0.5 upstream cause.** Read the D4 report entries; compare their per-analyzer causes with the D4 probe. If a cause is only a downstream symptom, STOP.
- [ ] **Step 1: Contract inventory** — for each analyzer (Lifetime/Provenance, NullPointer, DoubleFree, Signature): what it *should* do (design intent + what the diagnostics promise).
- [ ] **Step 2: Reality map** — what each actually does; every inert path with `file:line` (symbol-table provenance dead for locals/params; unseeded param null state; un-walked `return`/init expressions; DoubleFree alias-chain blindness; the comptime-dead-arm gap).
- [ ] **Step 3: Lie list** — every confident-but-wrong or vacuous diagnostic class with repro evidence (anchor: the 44 false `WARN_6002` on self-source; measure the current count — it may have shifted). Include "silently passes real defect" classes.
- [ ] **Step 4: Bar + must-work set** — the gap to a real-analyzer bar, and the concrete must-work list Task 9 implements. Fixture-driven test strategy (`tests/analyzers/**`) replaces hand-fed symbols.
- [ ] **Step 5: Commit** `docs(specs): static-analyzer audit — contracts, inert paths, lie list (Phase3.5 D4-pre)`.

### Task 9: D4-upgrade — split into 9a–9h, then D15 (9i–9k)

**Execution order:** 9a → 9b → 9c → 9d → 9e → 9h1 → 9h2 → 9i (interim D15) → 9j (D15 parity I) → 9k (option (d) value-switch fix) → 9g → 9f (final). The existing `f2c0e8bc` 9f commit is provisional; D4 is not closed until the final 9f re-run. Task 9l/9m are deferred under D16 and are not executed. Task 9k keeps `sw_is_stmt_expr`, fixes value-result switches, and leaves statement-mixed/assignment-void/anyerror/comptime-selector parity to D16.

**Source:** Task 8's audit (`docs/superpowers/specs/2026-10-29-phase35-analyzer-audit.md`) is the binding bar. Task 8 must be reviewed before 9a starts.

**Global constraints:** Only the plan; no unrelated fixes; no push. Full audit bar. No interprocedural/alias-through-deref expansion. No emission change: analyzers are post-sema, so emitted C/H must be byte-identical for corpus/stdlib/examples. Do not suppress a diagnostic to make a count move; fix the state/walk that causes it. Every sub-task has its own commit and scoped review.

#### Task 9a: Shared analyzer infrastructure and harness

**Files:**
- Modify: `sf/src/analyzer.zig` (AnalyzerContext fold field, mode gating, source spans), `sf/src/main.zig` (pass `ctx.comptime_folds` into `phase_StaticAnalyzers`), `sf/src/comptime_eval.zig` only if the fold accessor needs it, `sf/src/diagnostics.zig` only if source attribution needs it, `sf/src/tests/test_analyzer_bin.zig` (code-aware harness, manifest, `Symbol` file_id)
- Test: `tests/analyzers/**`; `tests/analyzers/d4_contract_probe.zig` registered

**Interfaces:**
- Consumes: audit §§1.5, 2.5, 3 L2/L11/L12, and must-work `DED-1`, `TEST-1`, `DX-1`.
- Produces: fold table available to analyzers; DED-2 switch-prong fold gating; null diagnostics emitted only by the null pass; diagnostics carry `source_file_id`/non-zero spans; code-aware fixture harness with exact code/count assertions; D4 probe registered. No analyzer behavior fixes beyond plumbing.

- [ ] **Step 0: Confirm the audit mapping.** Read Task 8 §§2.5/4.3 and confirm the harness/plumbing root is not a downstream symptom. If not, STOP.
- [ ] **Step 1: RED for duplicate/mode gating.** Use `np_cond.zig` (one `p.*`) and record the current 3 warnings across all passes vs 1 in the null pass alone. Expected post-fix: exactly one `WARN_6002`.
- [ ] **Step 2: Plumb the fold table and gate switch prongs.** Add `comptime_folds` to `AnalyzerContext`, pass it from `phase_StaticAnalyzers`, and expose the shared accessor used by sema/lowering. Do not add a parallel fold table. Gate `switch` prongs (DED-2), using the selector evaluator when the selector has no fold-table entry; dead prongs must not emit analyzer diagnostics, live prongs must.
- [ ] **Step 3: Gate `analyzeExpr` by analyzer mode.** Null diagnostics must not be emitted from lifetime/double-free passes; conditions still participate in each pass's own state. Re-measure the self-source 43/86 split.
- [ ] **Step 4: Code-aware test harness.** Replace aggregate-only `testFixture` assertions with `{code, count}`/`{code, file, line}` expectations; add a fixture manifest; set `Symbol` test `file_id`; register `d4_contract_probe.zig`.
- [ ] **Step 5: Source attribution (DX-1).** Carry `source_file_id` and a non-zero span for null/lifetime/double-free/leak diagnostics; render file/line/caret when present. Keep signature behavior unchanged.
- [ ] **Step 6: Verify.** Analyzer suites green; no emission change; self-source raw count equals single-pass count (no cross-mode duplication); report commands/outputs. Commit `refactor(analyzer): plumb folds, gate passes and attribute diagnostics (Phase3.5 D4a)`.

#### Task 9b: NullPointer

**Files:**
- Modify: `sf/src/analyzer.zig` (NullPointer paths only), `sf/src/tests/test_analyzer_bin.zig` (fixtures/expectations)
- Test: `tests/analyzers/**` NP fixtures

**Interfaces:**
- Consumes: Task 9a harness/fold/attribution.
- Produces: NP-1..NP-5: non-optional pointer params seeded `safe`; optional params conservative; `return`/`var` initializer/assignment RHS walked; exactly one diagnostic per defect; guard/capture refinement and true positives preserved.

- [ ] **Step 0: Confirm the audit NP cause; STOP if downstream-only.**
- [ ] **Step 1: RED** — `np_param_safe.zig` (0 `WARN_6002`), `np_return_null.zig`/`np_init_null.zig`/`np_assign_null.zig` (`ERR_2004`), `np_single_deref.zig` (exactly one warning); record current results.
- [ ] **Step 2: Implement** param seeding, return/init/RHS walks, and single-pass emission; preserve guard/capture refinement.
- [ ] **Step 3: Verify** NP-1..5, no new false positives, no emission change; commit `fix(analyzer): make null-pointer analysis real (Phase3.5 D4b)`.

#### Task 9c: DoubleFree

**Files:**
- Modify: `sf/src/analyzer.zig` (DoubleFree paths only), `sf/src/tests/test_analyzer_bin.zig`
- Test: `tests/analyzers/**` DF fixtures

**Interfaces:**
- Consumes: Task 9a harness/fold/attribution.
- Produces: DF-1..DF-4: alias state propagation; field/index/member free resolution; ownership transfer only at real ownership sites; no lossy `transferred`/`returned_val`/`unknown` → `freed`; leak/double-free semantics preserved.

- [ ] **Step 0: Confirm the audit DF cause; STOP if downstream-only.**
- [ ] **Step 1: RED** — `df_alias_chain.zig`, `df_field.zig`, `df_index.zig`, `df_owner_handle.zig`, `df_transferred_free.zig`; record current false/missing diagnostics.
- [ ] **Step 2: Implement** alias relation/state propagation, field/index resolution, precise ownership pass, and lossless state transitions.
- [ ] **Step 3: Verify** DF-1..4; before/after self-source and corpus warning/info volume recorded; no emission change; commit `fix(analyzer): make double-free ownership real (Phase3.5 D4c)`.

#### Task 9d: Lifetime / Provenance

**Files:**
- Modify: `sf/src/analyzer.zig` (Lifetime paths only), `sf/src/tests/test_analyzer_bin.zig`
- Test: `tests/analyzers/**` LIFE fixtures

**Interfaces:**
- Consumes: Task 9a harness/fold/attribution.
- Produces: LIFE-1/LIFE-2. Keep true positives/captures. Per the audit, delete the structurally dead symbol-table provenance arm for locals/params and test the real state-map path; do not build a new front-end scope map in this milestone. Document the no-interprocedural/no-alias-through-deref limits.

- [ ] **Step 0: Confirm the audit LIFE cause; STOP if downstream-only.**
- [ ] **Step 1: RED** — `lifetime_local.zig`, `lifetime_param.zig`, plus existing `capture_lifetime.zig`; record `ERR_2020`/`ERR_2021`/`WARN_6010` behavior.
- [ ] **Step 2: Remove the dead symbol-table path** and route local/param provenance through the real state map; keep the true positive `return &x`.
- [ ] **Step 3: Verify** LIFE-1/2, no new false positives, no emission change; commit `fix(analyzer): make lifetime provenance real (Phase3.5 D4d)`.

#### Task 9e: Signature and residue

**Files:**
- Modify: `sf/src/tests/test_analyzer_bin.zig`, `docs/sf/STATIC_ANALYZERS_p2.md` §5.3, `docs/tech_debt/static_analyzers.md`
- Test: `tests/analyzers/**` signature fixtures

**Interfaces:**
- Consumes: Task 9a harness; Task 8 audit §2.4/§2.5.
- Produces: SIG-1 regression by code; vacuous hand-fed-symbol tests retired or reduced to pure helper tests; docs residue cleaned. Signature analyzer logic unchanged.

- [ ] **Step 1: Assert the existing Signature surface by code** (`?Aggregate`, `E!Aggregate`, arbitrary-width ints) and the negative codes/counts.
- [ ] **Step 2: Retire/rewrite the hand-fed `Symbol` behavior tests; set `file_id` on remaining tests.**
- [ ] **Step 3: Clean `STATIC_ANALYZERS_p2.md` §5.3 and `tech_debt/static_analyzers.md`; leave `docs/design/static_analyzers.md` deferred with the zig0 archive.**
- [ ] **Step 4: Verify** suite green, no emission change; commit `test(analyzer): assert signature contracts and remove analyzer test residue (Phase3.5 D4e)`.

#### Task 9f: D4 final integration and closeout (after 9h/9g)

**Status:** provisional `f2c0e8bc` deleted D4 early; D4 remains open until this task is re-run after 9h/9g.

**Files:**
- Modify: `examples/torrent_example_defects.md` (delete D4), `docs/tech_debt/static_analyzers.md` if not already done
- Test: full analyzer suite; self-source measurement; corpus/stdlib/examples no-emission proof

**Interfaces:**
- Consumes: 9a–9e, 9h1, 9h2, 9i, 9j, 9k, 9g.
- Produces: D4 closed on the full audit bar; self-source `WARN_6002` class collapsed, not moved; raw count equals single-pass count; any residual individually justified; emitted C/H byte-identical.

- [ ] **Step 0: Do not treat D4 as closed yet.** Re-run this task only after 9h and 9g; if 9h finds a real null risk or examples/stdlib residuals remain unjustified, STOP and reopen D4. The provisional `f2c0e8bc` deletion must be revalidated, not assumed.
- [ ] **Step 1: Re-run the self-source measurement** (43 null-pass / 86 raw baseline) and the D4 probe; record exact commands/counts. Any residual must be justified per site.
- [ ] **Step 2: Verify no emission change** on corpus/stdlib/examples; analyzer suites green; no new false positives.
- [ ] **Step 3: Delete D4 from the defects doc; record the deferred `docs/design/static_analyzers.md` residue in the SDD report; commit `docs(analyzer): close D4 on the full audit bar (Phase3.5 D4f)`.**



#### Task 9f.1: Certify the 31 value-switch emission diffs

**Status:** MANDATORY after Task 9f and before Phase 3.5 closeout. No source changes.

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-31-diff-certification.md`
- Create: per-entry evidence under `repro/mi_matrix/known_excluded/d15_31_diff/` or `/tmp` with the exact commands recorded in the report
- No `sf/src`, no plan/spec/defects edits.

**Interfaces:**
- Consumes: Task 9k option (d), Task 9f’s 31-entry diff set (19 Task 9k shifts + 12 D15-recovered cases), the Zig 0.17.1/previous-Z98 evidence.
- Produces: one per-entry certification table with gcc build/run results; no claim of harmless C without it.

- [ ] **Step 0: Build the two compilers.** Pre-Task-9 base `3bf7602b…` (`d124055d`) and final `cac6716d…` (`ace04574`/current source), using the recorded seed/self-compile recipes. Record md5/sha256 and clean worktree state.
- [ ] **Step 1: Materialize the 31 entries.** Use the Task 9f comparison list. Separate 19 Task 9k value-switch shifts and 12 D15-recovered `*_err_switch`/`*_null_switch` cases.
- [ ] **Step 2: Dump and build each entry.** For every entry, dump C from both compilers with the canonical `--lib-dir`, then gcc `-m32 -std=c89` compile/link. Run the resulting binary where the entry has a runnable main; record rc and stdout. For compile-only entries, record gcc-only status.
- [ ] **Step 3: Compare.** For the 12 recovered cases, require behavior identical to pre-D15 Z98. For the 19 value switches, require the expected-type coercion semantics (and Zig oracle where runnable). Any gcc error, runtime difference, or unexplained output → STOP.
- [ ] **Step 4: Confirm boundaries.** No statement switch and no non-switch entry in the 31; D16 remains open. If a statement or non-switch entry appears, STOP.
- [ ] **Step 5: Commit the report/evidence.** No source changes, no plan/spec/defects edits. Report per-entry status and any STOP. Task 9f/Phase 3.5 is not closed until this passes.

#### Task 9g: Restore stale analyzer/semantic test binaries

**Files:**
- Modify: `sf/src/tests/test_semantic_bin.zig` (current `semanticAnalyzerInit` arity and required setup), `sf/src/tests/test_analyzer_integration_bin.zig` (stale `examples/hello/main.zig` path)
- Test: both binaries compile and run green

**Interfaces:**
- Consumes: Task 9a's `AnalyzerContext` fields; the current `semanticAnalyzerInit` signature.
- Produces: the two pre-existing red test binaries green. This is a harness repair, not analyzer behavior and not a compiler fix.

- [ ] **Step 1: Confirm the cause is test staleness.** `semanticAnalyzerInit` now takes 16 args (module/source ids, coercion/enum/tuple/error-code tables, interner, call/cp maps, module registry, suspending fns); the test still passes 8. The integration test reads `examples/hello/main.zig`; the file is `examples/z98/hello/main.zig`. If either failure is actually a compiler/analyzer defect, STOP and present.
- [ ] **Step 2: Repair the harnesses only** — update the init call/setup and the example path. Retarget or remove `testFnCallNotCallable`: callability is enforced at lowering with `error[3056]`, while the synthetic sema test asserts the wrong layer. Use the existing real fixtures `nonfn_local_call_reject_xmod` / `nonfn_member_call_reject_xmod` or a pipeline-level check; do not change `semantic_analyzer.zig` or compiler behavior to make the test pass.
- [ ] **Step 3: Verify** both binaries compile and run green; record output; commit `test: restore analyzer/semantic test binaries (Phase3.5 D4g)`.

#### Task 9h1: Null-state foundation

**Files:**
- Modify: `sf/src/analyzer.zig` (null-state walk/merge only), `sf/src/state_map.zig` only if the merge helper belongs there, `sf/src/tests/test_analyzer_bin.zig`, `tests/analyzers/**`

**Interfaces:**
- Consumes: Task 9a/9b harness, mode gating, exact expectations.
- Produces: one centralized null-state exit merge. Fall-through, guard-false, `break`, `continue`, and `switch` exits merge with `maybe` on disagreement; `ERR_2004` only when every path is `is_null`. No non-null classification, no suppression, no emission change.

- [ ] **Step 0: Confirm the state/merge root; STOP if it requires a broader analyzer rewrite.**
- [ ] **Step 1: Add fixtures** — `while_guard_body_ok`, `while_guard_exit_warn`, `while_break_maybe_warn`, `if_guard_exit_warn`, `switch_break_maybe_warn`; exact code/count.
- [ ] **Step 2: Implement** a single null-exit merge helper; remove the `99` sentinel from null merges; snapshot `break`/`continue` states; post-guard variables become `maybe`, never silent.
- [ ] **Step 3: Verify** all fixtures, D4 probe, analyzer suite, no emission change; commit `refactor(analyzer): centralize null-state exits (Phase3.5 D4h1)`.

#### Task 9h2: Type-driven nullability

**Files:**
- Modify: `sf/src/analyzer.zig` (NullPointer classification only), `sf/src/tests/test_analyzer_bin.zig`, `tests/analyzers/**`

**Interfaces:**
- Consumes: Task 9h1 exit merge; Task 9a/9b harness.
- Produces: one type-driven classifier. Non-optional `*T`, pointer field, pointer element, and non-optional call return are `safe`; optional `?*T` is `maybe`; address-of is `safe`; `@intToPtr` is `maybe` unless guarded/known non-zero; `@ptrCast`/`@alignCast` inherit source state; `try`/`catch unreachable` safe only for non-optional results; unknown/unresolved is `maybe`. No callee-name whitelist, no global suppression.

- [ ] **Step 0: Recheck the residual sites.** 7 self-source, 16 example, 17 stdlib. If any is a real null risk, STOP and present a code fix.
- [ ] **Step 1: Add fixtures** — `nonnull_ptrcast_ok`, `nonnull_type_field_element_ok`, `nonnull_call_result_ok`, `nonnull_inttoptr_guard_ok`, `optional_unknown_warn`, `optional_call_warn`; exact code/count.
- [ ] **Step 2: Implement** type-driven nullability; remove `npRegistryFieldClass` name fallback; make `np_decl_types` scope-aware or delete it in favor of resolved types. No callee-name whitelist.
- [ ] **Step 3: Recheck all sites**; target examples <=251 and stdlib <=7, or a per-site justified residual. If reaching that needs more special cases, STOP and present.
- [ ] **Step 4: Verify** D4 probe, analyzer suite, examples/stdlib/corpus, no emission change; commit `fix(analyzer): classify pointer nullability from types (Phase3.5 D4h2)`.

#### Task 9i: D15 — mixed value-switch prong type error (I/F)

**Status:** Interim fix landed at `280a3b12`. It rejects unannotated mixed prongs but also false-rejects 12 valid annotated optional/error-union switches; D15 is re-opened and final ownership moves to Tasks 9j/9k. See
`.superpowers/sdd/2026-10-29-phase35-defects-plan/task-d15-investigation-report.md`.

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (switch-expression unification only), `sf/src/tests/test_semantic_bin.zig`
- Test: `repro/mi_matrix/known_excluded/switch_value_mixed_type_repro/` (commit the repro + NOTES)

**Interfaces:**
- Consumes: the investigation report, `testSwitchExprMixed`, the D15 fixture, Task 9g's first observation.
- Produces: mixed/non-unifiable value-switch prongs are a clean level-0 type-mismatch reject; no first-prong type, no void acceptance, no lower/emitter change.

- [ ] **Step 0: Confirm the report's root cause** (`semanticAnalyzerResolveSwitchExpr` MIX branch `:5187-5202`, tail overwrite `:5256-5258`). If it does not match, STOP.
- [ ] **Step 1: Commit the real repro** under `known_excluded/`; update its NOTES to the expected reject contract.
- [ ] **Step 2: Implement** one level-0 type-mismatch diagnostic at the mismatching prong (or switch node with a prong span), deduped per switch; poison `unified` (chosen sentinel) so the tail cannot return the first-prong type; keep `continue`, valid coercions, mandatory-`else` `error[3068]`, import idiom, captures, enum/tagged-union behavior. Use `ERR_3000_TYPE_MISMATCH`; no new diagnostic code unless STOP.
- [ ] **Step 3: Strengthen `testSwitchExprMixed`** to assert the poison sentinel **and** exactly one level-0 mismatch diagnostic; add inferred/use/reverse-order source fixtures.
- [ ] **Step 4: Verify** direct/infer/use/reverse forms rc2 and 0 `.c` under `-ffast`/`-fsafe`; valid switches (same-type, numeric literal coercion, string slice, f32 narrowing, captures, enum/tagged-union, import idiom, no-`else` reject) unchanged; `test_semantic_bin` green; no emission change.
- [ ] **Step 5: Commit** `fix(sema): reject mixed value-switch prong types (Phase3.5 D15)` + report. This is the interim fix only; D15 stays open until 9j/9k. Task 9g may then resume, but 9f final waits for 9k.

#### Task 9j: D15 parity investigation — expected-type vs peer-type (I)

**Status:** MANDATORY before Task 9k. No source changes; stop for operator review after the report.

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-d15-parity-investigation.md`
- Create: `repro/mi_matrix/known_excluded/d15_parity/` probe sources + recorded outputs
- Read-only: `sf/src/semantic_analyzer.zig` (`semanticAnalyzerResolveSwitchExpr`, `semanticAnalyzerResolveIfExpr`, `topExpectedType`), `sf/src/type_registry.zig` (`typeRegistryIsAssignable`), the D15 fixture, the 12 corpus cases
- No `sf/src` edits, no plan/spec truth-up, no fixes.

**Interfaces:**
- Consumes: Task 9i interim fix `280a3b12`; the 12 false-rejected corpus cases; the semantic expected-type path already used by if-expressions.
- Produces: a committed parity report with the accept/reject matrix from **Zig 0.17.1**, Z98 pre-D15 base, and current HEAD; one recommended fix shape with exact sema insertion points; no code change.

- [ ] **Step 0: Obtain the oracle. First locate an existing Zig 0.17.1 binary. If absent, download the official Zig 0.17.1 linux-x86_64 archive into `/tmp/phase35-d15-i/zig-0.17.1`, verify `zig version` is `0.17.1`, and record the archive URL and sha256. Do not install it on PATH and do not substitute another Zig version. If the oracle cannot be obtained, STOP.**
- [ ] **Step 1: Freeze the matrix.** Cover expected types `i32`, `?i32`, `error{E}!i32`, `error{E}!?i32`, `??i32`, `?*T`, slice, `f32`, `anyerror!i32`; positions return, typed/untyped var/const, call argument, field/array initializer, nested switch; statement vs value switch; comptime-known and runtime selectors; captures; noreturn/undefined; the D15 mixed negatives; and the 12 corpus cases. Commit the probe sources and exact commands under `known_excluded/d15_parity/`.
- [ ] **Step 2: Run three-way.** Execute every probe under real Zig 0.17.1, the Z98 pre-D15 base (`git rev-parse 280a3b12^`; build in a throwaway worktree or use a matching `/tmp` binary), and current HEAD. Record rc, diagnostics, and emitted C presence. Do not infer a result not observed.
- [ ] **Step 3: Classify.** For each row: Zig accept/reject, pre-D15 Z98, current Z98, and the correct rule (`expected-type-first` vs `peer-resolution`). Call out every current divergence and every case where Zig and the spec/docs disagree. If a result is ambiguous or the matrix is incomplete, STOP.
- [ ] **Step 4: Compare fix shapes.** (a) expected-type-first before the MIX branch, mirroring `semanticAnalyzerResolveIfExpr`; (b) full result-location/expected-type push for every switch result position; (c) a shared sema type-resolution helper used by if/switch. State exact insertion points, expected effect on the 12 cases, the invalid-mixed cases, statement switches, and existing valid switches; state the blast radius and why it is not a symptom patch.
- [ ] **Step 5: Write and commit the report.** Include the three-way matrix, the 12-case evidence, the recommended shape, residual risks, and a STOP for operator review before Task 9k. Commit only the report/probes. Do not change source. Task 9k must not start until the operator approves this report.

#### Task 9k: D15 expected-type-aware fix

**Status:** Authorized option (d) by operator 2026-11-09. Tasks 9l/9m are deferred under D16 and are not executed. Scope is value-result switches only; `sw_is_stmt_expr` stays.

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (switch-expression unification only, following the approved 9j shape), `sf/src/tests/test_semantic_bin.zig`
- Test: `repro/mi_matrix/known_excluded/d15_parity/`, the 12 corpus cases, `switch_value_mixed_type_repro`, existing valid-switch fixtures
- Modify: `examples/torrent_example_defects.md` only after the fix is green.

**Interfaces:**
- Consumes: the approved Task 9j report; Task 9i interim fix; the existing `topExpectedType`/if-expression expected-type pattern; `typeRegistryIsAssignable`.
- Produces: value-result switches with a known expected type coerce each prong to that type (optional/error-union/null/noreturn included); no-expected-type switches use peer resolution; the 12 valid corpus cases and 35 expected-type cells accept; unannotated mixed value prongs still reject; statement switches keep `sw_is_stmt_expr` and their current behavior; no emitter/lower/async change.

**Scope contract (binding):**
- Expected-type-first only before the MIX branch for value-result switches; keep peer resolution for no-expected cases.
- Keep `sw_is_stmt_expr`; do not change statement-switch behavior. Mixed statement switches remain a D16 parity gap.
- On value-switch mismatch, latch `unified = TYPE_NORETURN` and the node type; a later prong must not reset it. One level-0 diagnostic, 0 `.c`.
- Keep `noreturn`/`undefined` neutral, captures, enum/tagged-union, import idiom, string-slice, f32 FX10, and missing-`else` behavior unchanged.
- Accept the 19 expected value-switch coercion emission shifts; the 12 recovered D15 cases add 12 more against the pre-Task-9 base, for 31 total value-switch diffs. No fixture migration. Task 9f.1 certifies the 31: 31/31 gcc compile, 29/31 direct run identical, 2/2 compile-only equal under the fixture `getp` stub, 12/12 recovered match pre-D15, no statement-switch C changed. Defer comptime-selector pruning, `anyerror`, assignment-void, and statement-mixed parity to D16.
- Do not add a shared if/switch helper or full result-location push. Do not copy the 9j snippet literally; it does not latch the poison.

- [ ] **Step 0: Confirm the approved 9j shape and option (d) scope. If the current code or report differs, STOP.**
- [ ] **Step 1: RED.** The 12 valid corpus cases must be rc0 (currently rc2); the D15 mixed value negatives must be rc2. Record exact commands/diagnostics.
- [ ] **Step 2: Implement expected-type-first for value-result switches** before the MIX branch; keep `sw_is_stmt_expr`; keep peer-resolution for no-expected cases; latch the poison; no second switch typing path.
- [ ] **Step 3: Verify.** The 12 cases accept and build; 35 expected-type cells accept; D15 mixed direct/infer/use/reverse still reject with one level-0 mismatch and 0 `.c`; statement switches unchanged; valid value-switch fixtures and the 19 expected emission shifts are reviewed; `test_semantic_bin` green; corpus has no new false rejects. Re-run analyzer/semantic suites.
- [ ] **Step 4: Commit** `fix(sema): apply expected-value-type rules to switch prongs (Phase3.5 D15)` + delete D15 from the defects doc + report. D16 remains open. Then Task 9g/9f may resume. No seed rotation here.

#### Task 9l: Assignment/expression `void` audit (I)

**Status:** DEFERRED under D16 (operator option (d), 2026-11-09). Historical audit remains evidence; not executed as a Phase 3.5 task.

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-assignment-void-investigation.md`
- Create: `repro/mi_matrix/known_excluded/d15_assignment_void/` probes + outputs
- Read-only: `sf/src/semantic_analyzer.zig` (`semanticAnalyzerResolveAssign`, `semanticAnalyzerResolveExpr`, `expr_stmt`, block result, `stmt_expr_node`, switch peer/expected paths), `sf/src/lower.zig` (`plain_assign`/`assign_*`, block/expression-statement lowering, if/while joins, switch result), `sf/src/c89_emit.zig` only as needed
- No `sf/src` edits, no Task 9m yet, no 9k change.

**Interfaces:**
- Consumes: Task 9j parity matrix; the 38 statement-switch regression set; the uncommitted 9k candidate is **not** a baseline and must not be used or modified.
- Produces: a committed audit answering whether assignment expressions can type as `void` without breaking lowering or valid code; exact sema/lowering consumers; an impact matrix; one recommended option; STOP for operator review.

- [ ] **Step 0: Use a clean HEAD baseline.** Build/read from HEAD; do not use the uncommitted `sf/src/semantic_analyzer.zig` candidate. Reuse the verified Zig 0.17.1 oracle if present; verify `zig version` and sha256; if absent, use the Task 9j download recipe. If the oracle is unavailable, STOP.
- [ ] **Step 1: Establish Zig 0.17.1 semantics.** Probe assignment as an expression; assignment-ending block result; `expr_stmt`; chained assignment; `if`/`while` conditions; `switch` statement prongs; `_ =`; `defer`; optional/error-union blocks. Record exact accept/reject and types.
- [ ] **Step 2: Sema impact inventory.** Map every consumer of assignment/`expr_stmt`/block result types: `ResolveAssign`, `ResolveExpr`, `expr_stmt`, block tail, `stmt_expr_node`, switch peer/expected, return/init/call sites. Identify what changes if assignment returns `void`.
- [ ] **Step 3: Lowering/temp impact inventory.** Map `plain_assign`/compound assignments, block result temps, expression-statement discard, if/while joins, switch result, `TEMP_NONE`, and resolved-type reads. Determine whether assignment can lower store-only with no value temp; identify any required lowering changes.
- [ ] **Step 4: Impact matrix.** Run/record the 38 statement-switch entries, the 12 D15 cases, valid switch fixtures, corpus/goldens, and diagnostics under the proposed semantics. Classify each as expected fix, regression, or new failure.
- [ ] **Step 5: Options and recommendation.** Compare (a) global assignment/block `void`; (b) expression-statement/block-only normalization; (c) switch-only normalization; (d) keep `sw_is_stmt_expr` and scope 9k to value switches; (e) revert `280a3b12` and document the D15 gap. State exact files, blast radius, and test plan.
- [ ] **Step 6: Write and commit the report.** Commit only the report/probes. Stop for operator review before any 9m code. If the audit is inconclusive, STOP.

#### Task 9m: Conditional assignment/expression `void` fix

**Status:** DEFERRED under D16 (operator option (d), 2026-11-09). Not executed; no assignment-void change.

**Files:**
- Modify: the files approved by Task 9l (expected: `sf/src/semantic_analyzer.zig`, possibly `sf/src/lower.zig`), tests/fixtures identified by the audit
- Test: the 9l probes, 38 statement-switch entries, 12 D15 cases, corpus/goldens

**Interfaces:**
- Consumes: the approved 9l report.
- Produces: assignment/expression typing that matches the approved 9l shape; no 38-entry regression; no 12-case regression; then Task 9k may remove `sw_is_stmt_expr`.

- [ ] **Step 0: Confirm the approved 9l shape and files. If the report is not approved or the current code differs, STOP.**
- [ ] **Step 1: RED.** Record the current assignment/block/statement-switch failures and the 38 entries in the exact contexts the audit identifies.
- [ ] **Step 2: Implement only the approved 9l shape.** No unrelated sema/lowering cleanup; no emitter change unless 9l proved it required and the operator approved.
- [ ] **Step 3: Verify.** 38 entries and 12 D15 cases behave as the approved matrix requires; lowering emits correct stores with no missing value temp; corpus/goldens/no-emission checks green; `test_semantic_bin` green.
- [ ] **Step 4: Commit** `fix(sema): type assignment expressions as void (Phase3.5 D15-9m)` + report. Do not start 9k until reviewed.

### Task 10: Doc consolidation

**Files:**
- Create dir: `sf/docs/initial_design/`
- Move (git mv) from `docs/sf/`: `Design_p2.md`, `AST_PARSER_p2.md`, `AST_LIR_Lowering_p2.md`, `LIR_C89_Emission_p2.md`, `TYPE_SYSTEM_p2.md`, `STATIC_ANALYZERS_p2.md`, `RUNTIME_PAL_p2.md`, `ERROR_HANDLING_p2.md`, `TEST_HARNESS_p2.md`, `Lexer_sf.md`, `Import_Symbol_reg.md`, `COMPLEMENT.md`, `z98_external.md`, `AI_TASKS_sf.md`
- Modify: cross-references in `docs/sf/AGENTS.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/INDEX.md` and any doc pointing at the moved paths
- Untouched: `docs/sf/{AGENTS.md,QUICK_REF.md,manuals/,std_lib/,Debugging.md,std_additions.txt,zig0_zig1_matriuska_bug.md}` (stay), `sf/docs/tech_docs/` (stays), `docs/reference/` + `docs/design/` zig0-era docs (stays as-is)

- [ ] **Step 1: Move** the 14 design-intent files into `sf/docs/initial_design/` (`git mv`, explicit paths).
- [ ] **Step 2: Add `sf/docs/INDEX.md`** (or extend tech_docs INDEX) stating the split: `tech_docs/` = observed implementation, `initial_design/` = design intent as first thought, and the zig0-era docs stay in `docs/reference/` + `docs/design/` for comparison until the future `zig0/` archive.
- [ ] **Step 3: Fix every cross-reference** that pointed at the old paths (grep for the moved filenames repo-wide; update `docs/sf/`, `sf/docs/`, `scripts/` comments only if they name paths).
- [ ] **Step 4: Verify** — no dangling references (grep pass); `git status` shows pure renames + reference edits; no file content changed except cross-refs and the new INDEX.
- [ ] **Step 5: Commit** `docs(sf): consolidate self-host docs — tech_docs (observed) + initial_design (intent) (Phase3.5)`.

### Task 11: Spec truth-up

**Files:**
- Modify: `docs/reference/Language_Spec_Z98.md` (only this spec; the other stale docs stay)

**Interfaces:**
- Consumes: Task 3's PAL routing (D8 semantics), Task 4's lazy import (D3 semantics), Task 5's conventions (D5/D10 syntax), Task 6's full `enum(u64)` range (D13), Task 7's async EU-payload rule (D14), Task 9's analyzer status (for the §5/§7 accuracy check).
- Produces: a spec that matches the compiler.

- [ ] **Step 1: Kill the lifting lie** — replace the `:435` "AST Lifting" bullet with the real mechanism (lowerer phase machines emit branches + result temporaries in LIR; no AST transformation pass exists).
- [ ] **Step 2: Barrel list** — verify against the current `sf/src/std.zig`; it has 17 re-exports today, not the old 12 → 14 claim.
- [ ] **Step 3: Missing facts** — `error[3077]` (limit 130), `--check` mode, the §5.1 conventions rules, the §5.3 lazy-import semantics, full `enum(u64)` discriminants (D13), the suspending-wrapper error-union payload rule (D14), and the `@getChar` raw-byte contract selected by the operator: returns `0..255`, `-1` at EOF/error, no CRT CRLF→LF or Ctrl-Z→EOF translation; identical on POSIX/Win32 and CRT/no-CRT.
- [ ] **Step 4: Builtins reconciliation** — §4 list vs the compiler's real registration (sema `BuiltinDesc` + lower + `comptime_eval`); resolve `@addr`/`@name`/`@enumFromInt`/`@typeName`/`@cInclude` claims.
- [ ] **Step 5: §5/§7 re-verification** — every limitation and "Not Yet Supported" item re-checked against the current compiler and mi/corpus; correct stale claims; verify every fixture path named in the spec exists.
- [ ] **Step 6: Commit** `docs(spec): language spec truth-up — real lowering, current features (Phase3.5)` + report.

### Task 11.5: Manual truth-up — captures, switch, examples, std

**Files:**
- Modify: `docs/sf/manuals/en/vol1-09-repetition.html`, `vol1-12-arrays.html`
- Modify: `docs/sf/manuals/en/vol2-06-enums.html` (signed enum backings), `vol2-07-unions.html`, `vol2-09-arrays-slices.html`, `vol2-10-control-flow.html`, `vol2-17-stdlib.html`
- Modify: `docs/sf/manuals/en/vol4-01-grammar.html`, `vol4-05-enums.html`, `vol4-08-arrays-slices.html`, `vol4-13-control-flow.html`, `vol4-18-stdlib.html`, `vol4-18-stdlib-io.html`, `vol4-18-stdlib-data.html`, `vol4-18-stdlib-codecs.html`, `vol4-18-stdlib-algorithms.html` (17-name re-export claim), `vol4-21-diagnostics.html`, `vol5-15-diagnostics.html`
- Modify example-listing pages found by the static audit: `docs/sf/manuals/en/vol5-00-index.html`, `vol5-22-contribute.html`, `vol1-15-whats-next.html`/`vol3-18-whats-next.html`
- Generated: `docs/sf/manuals/en/search-data.js` via `build.sh`; refresh tracked `docs/sf/manuals/dist/en/vol4-21-diagnostics.html` only if its source changes (the rest of `dist/` is gitignored)
- No `sf/src`, compiler, seed, or manual `src/` example changes unless a referenced example command is broken or missing

**Interfaces:**
- Consumes: Task 11's final `Language_Spec_Z98.md`, current compiler behavior, current `sf/src/std.zig` and `sf/src/std_*.zig`, and the current examples matrix (28/28; 32 dirs with 4 excluded).
- Produces: manuals that match the current spec and compiler; D16 remains open and is described as a parity boundary, not full Zig parity.

- [ ] **Step 1: Static claim audit — no test reruns.** Cross-reference each manual claim to existing corpus/fixture/golden evidence. Do **not** re-run unrelated examples or re-prove unchanged behavior. Verify only (a) claims changed by Task 11's spec truth-up, and (b) claims that say something is **unsupported** where an existing corpus test contradicts the claim. Record contradictions; leave unchanged, test-covered claims alone. Two contradictions found in the initial audit are in scope and must be corrected: `vol2-06-enums.html` (signed backings do exist) and `vol4-18-stdlib-algorithms.html` (17-name re-export list, not thirteen).
- [ ] **Step 2: For-captures.** Verify/document `|item|`, `|item,index|`, `|*item|`, `|*item,index|`, `|*_|`, explicit index ranges, addressability/const rules, and `error[3078]` against existing for-capture corpus tests. Make the named pages consistent; do not add syntax beyond the spec.
- [ ] **Step 3: Switch behavior.** Document value-result expected-type/prong coercion (D15 option d) and unchanged statement switches. Record mixed statement switches, assignment-void, comptime-selector pruning, and `anyerror` as **D16 open**, not full Zig parity. Update the diagnostics references.
- [ ] **Step 4: Std library.** Derive counts statically from `sf/src/std.zig` and `sf/src/std_*.zig`; current `vol2-17` says 14 re-exports / 32 by-path / 5 pal, while `std.zig` has 17 re-exports and the seed has 59 std files. Add `std_page`, `std_page_pal`, `std_gpa`, `std_pool`, `std_tls_io`, `std_hpack`, `std_http2`; update the tour/table/IO/data/codecs pages, and correct the `vol4-18-stdlib-algorithms.html` “thirteen-name” re-export claim to 17.
- [ ] **Step 5: Examples.** Update lists/names to the current examples — `z9git`, `z9torr`, `tls_demo`, `z9zstddecomp` — and note excluded dirs only where the page lists the matrix. If behavior is already covered by existing tests, do **not** re-scrutinize the example command claims; fix only broken or missing references found statically.
- [ ] **Step 6: Build and validate.** Run `bash docs/sf/manuals/check.sh` and `bash docs/sf/manuals/build.sh` (static HTML/link/asset checks); fix links, counts, search data, and the 1:1 figure list. Do not add example execution to this task.
- [ ] **Step 7: Commit** `docs(manual): refresh captures, switch, examples and std additions (Phase3.5)` + report.

### Task 12.1: Analyzer statement traversal — explicit work stack

**Files:**
- Modify: `sf/src/analyzer.zig` (replace recursive statement traversal with an explicit work stack; keep `analyzeExpr` recursive)
- Test: existing `scripts/compiler/gate_lower_depth.sh` cases 2/10/11/12; `test_analyzer_bin`, `test_semantic_bin`, `test_analyzer_integration_bin`; D4 probe; Task 9h/9h1/9h2 fixtures; corpus emission compare

**Interfaces:**
- Consumes: `visitStatement`/`walkBlock` (`sf/src/analyzer.zig:2272`, `:1904`), `executeDeferQueue` (`:1888`), `ctx.current_depth`, defer queue, `np_current_label`/`np_ctrl_*`, and the mode-specific `on_stmt` callbacks.
- Produces: one iterative `runStmtWalk` machine with explicit frames for block, if, while, for, switch, labeled block/loop, defer exit, and leaf callbacks. No C-stack growth per statement nesting; expression traversal remains recursive and depth-bounded. All diagnostics, state forks/merges, defer order, capture bindings, break/continue targeting, and leak checks stay byte-identical.

- [ ] **Step 0: Root-cause gate.** Reproduce `gate_lower_depth` cases 2/10/11/12 at `ulimit -s 1024`; confirm v145 passes and current hop1/hop2/hop3 fail with `rc=139`. Measure/record the recursive analyzer frames (e.g. emitted-C `-fstack-usage`) and identify the exact `visitStatement`/`walkBlock` recursion. If the failure is not in the analyzer statement walk, STOP and present.
- [ ] **Step 1: Pin the behavior baseline.** Record analyzer/semantic/integration suites, D4 probe, D15/D16 fixtures, self-source WARN counts, and a corpus emission compare on the current tree. Do not change Task 12 files or seed.
- [ ] **Step 2: Implement the explicit work stack.** Replace the recursive statement traversal with a `StmtWork`/frame loop. Preserve:
  - block child order, `current_depth`, defer-queue execution and `in_defer_exec`, leak checks;
  - `if` then/else fork, capture binding, `npMergeNullExits`/`stateMapMergeStates`, alias merge;
  - `while`/`for` body, zero-iteration exit, control frames, `np_current_label` save/restore;
  - `switch` decisive selector/prong states/merge;
  - labeled block/loop frames and `break`/`continue` targeting;
  - leaf `analyzeExpr` and `on_stmt` callbacks in the same order.
  Keep expression recursion intact; do not change lowering/emitter/sema or diagnostic text.
- [ ] **Step 3: Verify GREEN.** Cases 2/10/11/12 pass at 1 MB; cases 1/3/13 and all existing gate cases unchanged; analyzer/semantic/integration suites green; D4 probe and D15/D16 fixtures unchanged; self-source/example/stdlib WARN counts unchanged; 1278-entry corpus emission/rc compare unchanged; `git diff --check` clean. If any semantic difference appears, STOP — do not weaken a fixture.
- [ ] **Step 4: Commit** `refactor(analyzer): traverse statements with an explicit work stack (Phase3.5 D4 stack fix)` + report. No seed rotation, no Task 12 files.

### Task 12: Interim closeout — v146 (superseded by Task 12.3)

**Status:** executed as an interim closeout (`36e39cf3`); v146 is not the final seed because the final review found the module-scope unannotated-switch regression. Task 12.2-I/12.2-F repair it; Task 12.3 performs the final v147 closeout. The steps below remain the record of the interim run.

**Files:**
- Modify: `scripts/compiler/gate_lower_depth.sh` (the 8 pins), `docs/sf/QUICK_REF.md` (pin table + counts), `README.md` (seed/fixed-point facts), `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`, `examples/torrent_example_defects.md` (final open-only state)
- Test: the full battery (below)

**Interfaces:**
- Consumes: every prior task's landed state, including Task 12.1's explicit analyzer work stack.
- Produces: seed v145 → **v146** with a new fixed point (F_new moved by Tasks 3–7), re-anchored corpus counts/class md5, re-recorded markers, all gates green.

- [ ] **Step 1: Full battery on the current tree** (report-only at first): corpus live (record new count/class md5; expect growth from new fixtures; frozen-1124 md5 MUST still be `518eca1a...` with 0 movers), goldens, markers (record new value), examples 28/28, stdlib 376 + any new fixtures (record actual), crosscheck 10/10, all compiler gates (`gate_lower_depth`, `gate_builtin_names`, `gate_mutable_for`, `gate_debug_map`, `gate_crlf`, `gate_warn_clean`, `gate_reserved_names`, `check_emit_support` 9/9), manual `check.sh`/`build.sh`, tiers (`tier_dbg`, `tier_dbg_core`, `tier_gfx`, `tier_edit`, `tier_edit_gui`) — GUI tiers only if std_gfx touched (it is not expected to be).
- [ ] **Step 2: STOP-check** — if anything unexpected moved beyond the known emission shifts (D8/D3/D14, and D13 if its representation changes existing enum emission), STOP and present. Expected movers: 8 pins (all), corpus additions, marker counts, any goldens touching stdout ordering or async.
- [ ] **Step 3: Single re-baseline** — re-record the 8 pins in `gate_lower_depth.sh` + `QUICK_REF.md` (the authorized once-only move); re-anchor corpus counts/class md5 and markers in the docs.
- [ ] **Step 4: Seed rotation** — `scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/phase35_close` → closure (two-hop: hop1 == hop2 == the new fixed point); full battery values recorded; `scripts/seed/archive_seed.sh <bin> <gen> release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`; verify every CHANGELOG claim (the v121 false-status class must not repeat); lib/ counts (59 baseline; expected unchanged — no new std file); rebuild from the NEW archive reproduces the fixed point.
- [ ] **Step 5: Defects doc final state** — open-only; the fixed entries (D3, D4, D5, D7.3, D8, D10, D12, D13, D14) are gone; D15 is closed, D16 remains open by design, and any new findings land at the next free slot (D17+).
- [ ] **Step 6: Commit** `chore(seed): rotate v146 (Phase3.5 defect closure + docs)` + `docs(sdd)` final report. No push, no tag.

### Task 12.2-I: Expected-type sentinel investigation (no code)

**Files:**
- Create: `docs/superpowers/specs/2026-10-29-phase35-expected-type-investigation.md`
- Test: `repro/mi_matrix/known_excluded/expected_type_*` probes
- No `sf/src` changes

**Interfaces:**
- Consumes: the expected-type stack (`pushExpectedType`/`popExpectedType`/`topExpectedType`), all producer sites (module/local var decl, return, call args, struct/array init), all consumers (`if_expr`, `switch`, `@ptrFromInt`, struct init), the D15 matrix/corpus, and the final-review module-scope switch repro.
- Produces: a written contract for “no expected type” vs “unknown/undetermined type”, a complete producer/consumer audit, a probe matrix at v145 and v146, and a recommended fix with blast radius. No implementation.

- [ ] **Step 0: Reproduce.** `const X = switch (1) { 0 => 1, else => 7 };` at module scope: v145 rc0/builds; v146 rc2/`target: type`. Also probe the equivalent module-scope unannotated `if` and annotated forms.
- [ ] **Step 1: Inventory.** List every `pushExpectedType` call and every `topExpectedType` consumer. Classify each pushed value as a known type, no-expected (`0`/`TYPE_VOID`), or unknown/undetermined (`TYPE_UNDEFINED`), and record whether it is intentional.
- [ ] **Step 2: Probe matrix.** Module/local unannotated vs annotated `const`/`var` switch and `if`; call arguments; struct/array initializers; return; nested cases. Record v145/v146 behavior and the Zig 0.17.1 oracle where the D15 parity matrix already covers it.
- [ ] **Step 3: Evaluate sound options.** Compare (a) normalize the module var-decl producer to `0` (mirror the local rule), (b) enforce a `pushExpectedType`/`topExpectedType` invariant or helper with no-expected normalization, (c) replace the sentinel mix with an explicit expected-type enum/optional contract, and (d) a switch-only normalization (rejected as a patch). State which sites/consumers each touches and what behavior could change.
- [ ] **Step 4: Recommend and STOP.** Give the recommended design with exact files/lines, the test matrix, and the risks. Do not implement. Commit the report/probes with `test(repro): investigate expected-type sentinel contract (Phase3.5)`.

**Status:** completed `70dd67ee`; review rejected option (a) as unsound (conflates no-annotation with annotation-unresolved). Operator m1864 selected the explicit `ExpectedType` contract; Task 12.2-F implements it.

### Task 12.2-F: Explicit expected-type contract (operator-approved)

**Operator ruling (m1864):** implement an explicit expected-type contract. Reject option (a) (normalizing `TYPE_UNDEFINED` to `0`); it conflates “no annotation” with “annotation-unresolved” and false-accepts `const X: Nope = switch (...)`.

**Files:**
- Modify: `sf/src/semantic_analyzer.zig`
- Test: module/local unannotated and annotated `switch`/`if`; annotated-unresolved module types; call-arg-undetermined; struct/array/return; D15 matrix; analyzer/semantic suites; corpus

**Interfaces:**
- Consumes: the Task 12.2-I audit and the operator’s explicit-contract ruling.
- Produces: `ExpectedType` with kind `none` / `known(type_id)` / `undetermined`. `undetermined` means “annotation present but unresolved” and value consumers must reject it cleanly; it is never used as a `TypeId`. An unresolved call-argument parameter type is **none** (peer/no expectation), not `undetermined`. Module-scope unannotated switch/if accept like v145; annotated-unresolved types remain rejected; D15 known-type behavior unchanged.

- [ ] **Step 0: Confirm the approved design.** If the implementation would deviate from the explicit contract, STOP.
- [ ] **Step 1: Add fixtures.** Module-scope `const`/`var` unannotated switch and if; annotated controls; `const X: Nope = switch (...)` must reject; call-arg-unresolved (must be peer, not a false expected type); struct/array/return. Verify v146 RED and v145/GREEN expectations.
- [ ] **Step 2: Implement the explicit contract.** Replace the `u32` expected-type stack with `ExpectedType` (`kind`, `type_id`) or an equivalent parallel-kind representation. Add explicit push helpers for none/known/undetermined; replace all 15 producers. Module var: `child_0 == 0` -> none; annotation present + unresolved -> undetermined; resolved -> known. Local mirrors. Call args: unresolved/unknown param -> none; known -> known; no expectation -> none. Consumers (`if_expr`, `switch`, `@ptrFromInt`, struct init, raw reads) use kind: known only for coercion; none falls to peer/no expectation; undetermined rejects cleanly (never a sentinel type). Do not add switch-only normalization or change D15 semantics.
- [ ] **Step 3: Verify.** Module/local unannotated + annotated switch/if; `Nope` rejects; call-arg-unresolved peer behavior; struct/array/return; D15 12/12 + 35/35 + negatives; analyzer/semantic/integration suites; self-source/example/stdlib counts; 1278 corpus emission/rc; emitted C/H unchanged for existing valid code except the restored module forms. Any semantic difference: STOP.
- [ ] **Step 4: Commit** `fix(sema): unify expected-type contract (Phase3.5 expected-type fix)` + report. No seed rotation.

**Operator acceptance (m1886):** the module-scope unannotated `if` with string literals changing from pointer to slice is accepted as the intended contract correction. Record it in the Task 12.2-F report and the v147 CHANGELOG; do not special-case the old pointer behavior.

### Task 12.3: Final closeout — v147

**Files:**
- Same Task 12 file set, with final seed **v147** replacing v146 in `release/seed/`, `CHANGELOG.md`, `QUICK_REF.md`, and `README.md`
- Test: full battery (Task 12 Step 1), plus the Task 12.2-F module-scope fixtures

**Interfaces:**
- Consumes: Task 12.2-F and all prior tasks.
- Produces: final seed v147, final pins/markers/corpus anchors, defects doc with D16 only, and a clean final review.

- [ ] **Step 1: Full battery on the repaired tree.** Record actual values. Reuse Task 12's accepted waivers only where unchanged: frozen one-row D15 mover, `tier_dbg` crashinit, stale archived SEED_README template. If a new mover/gate failure appears, STOP.
- [ ] **Step 2: Re-baseline only if values moved.** Update the 8 pins/QUICK_REF, corpus/class md5, markers, and frozen display anchor as needed; do not edit `scripts/corpus/frozen_1124.txt`.
- [ ] **Step 3: Rotate v147.** Two-hop closure; archive/zip/manifest; lib 59; verify CHANGELOG claims and rebuild-from-archive; `gate_debug_map` against the new seed. CHANGELOG/QUICK_REF must record the accepted explicit expected-type contract and the module unannotated if-string pointer→slice correction.
- [ ] **Step 4: Defects doc final state.** D15 closed, D16 open, fixed entries gone, next slot D17.
- [ ] **Step 5: Commit** `chore(seed): rotate v147 (Phase3.5 final closeout)` + report. No push/tag.

---

**Execution note:** tasks run in the listed order (the operator fixed it: 0 (repro inventory + adjacent scan, test-only), 0.1 (D14 exact-shape retry, test-only), 0.2 (D14 frontend-vs-tail-ABI matrix, test-only), 0.5 (upstream root-cause investigation, no fixes), 1, 2, 3, 4, 5, 6 (D13), 7 (D14), 8 (D4-pre audit), 9a–9h2, 9i (interim D15), 9j (D15 parity I), 9k (option (d) value-switch fix), 9g, 9f (final), 9f.1 (31-diff certification), then docs, then 11.5 manuals, then closeout). Task 0 creates the repros and inventory; Tasks 0.1/0.2 resolve the D14 evidence; Task 0.5 maps the upstream causes; later tasks consume their results, verify the root cause, and must not recreate them or patch symptoms. Tasks 3, 4, and 7 are the emission shifts; Task 6 may shift enum emission and must be verified functionally. Their diffs are expected and recorded, not re-baselined. Tasks 8 and 9j are investigation-only. Tasks 9l/9m are deferred under D16. Task 10 must land before Task 11's spec work references `sf/docs/initial_design/` paths; Task 11.5 consumes Task 11 and must land before closeout. Task 12.1 is the authorized analyzer-stack repair inserted after 11.5; Task 12 was the interim v146 closeout. Task 12.2-I investigates the expected-type sentinel contract with no code; Task 12.2-F implements only the operator-approved design; Task 12.3 performs the final v147 closeout. Task 12.2-F must not start before the Task 12.2-I report is reviewed and approved.
