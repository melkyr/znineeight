# Z98 `print` formatting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the `print` formatting layer into a new standard-library module `std.fmt` (`sf/src/std_fmt.zig`) and bring `print` to full parity with official Zig 0.15.2 across the whole type/format surface.

**Architecture:** The compiler keeps format-string parsing, per-argument static-type dispatch, and validation (`lowerPrintFmt` + `getPrintFnName`); the formatting **bodies** move to `std_fmt.zig` in Z98. The compiler emits **mangled `std.fmt` calls** and **auto-imports** `std_fmt` whenever a `print` is lowered. `std.io.print` stays the user entry. Aggregates/tuples get **compiler-generated per-type printers** (Z98 has no generics); enum/error-set names use **compiler-emitted tables**. `{}` on a `[]const u8` is rejected (Zig-matching).

**Tech Stack:** Z98 (`sf/src`), the seed-built `zig1`, the canonical C runtime/PAL (`sf/src/include/*.c`, mirrored in `sf/src/emit_support.zig`), `gcc -m32 -std=c89`, the corpus/std-lib/manual gate scripts, git.

**Spec:** `docs/superpowers/specs/2026-09-22-z98-print-formatting-design.md`.
**Investigation of record:** `.superpowers/sdd/2026-09-22-z98-manual-volume-I-plan/task-7G-report.md` (the full per-case table; this plan argues from it).
**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-09-22-z98-comptime-int-parity-plan.md` (the trailing-issues plan; **this plan executes immediately after it completes**). Volume I (`docs/superpowers/plans/2026-09-22-z98-manual-volume-I-plan.md`) is complete, and its Task 7H is superseded by this plan. NEXT: create the Volume II plan.

## Global Constraints

- **Oracle:** official **Zig 0.15.2** (`/tmp/zig-x86_64-linux-0.15.2/zig`). Every Z98-vs-Zig claim is verified against it. **Never zig0.**
- **Option B:** implement the missing features for full parity — do not clean-reject a feature Zig accepts (except where §6 of the spec says so).
- **Mangled `std.fmt.*`:** emitted call sites are mangled Z98 `std.fmt` calls; the `std_print_*` C-ABI symbols are internal and retired from the call sites.
- **Auto-import:** the compiler imports `std_fmt` whenever a `print` is lowered; the user needs no new import.
- **Entry point:** `std.io.print` stays the user-facing entry; the compiler still special-cases a callee named `print`.
- **`{}` on `[]const u8` is rejected** (use `{s}` / `std.io.write`).
- **Runtime/PAL edits are made in lockstep** in both the canonical `.c` and the emitted copy in `sf/src/emit_support.zig`; `scripts/check_emit_support.sh` must stay 7/7.
- **Every task leaves a regression fixture** (`repro/mi_matrix/`, goldens from the FIXED compiler, deterministic 3×) **+ a standalone `repro/` program**, updates `repro/mi_matrix/EXPECTED_FAIL.md` and `scripts/stdlib/expected_dirs.txt`, runs the QUICK_REF gate battery, and rotates the seed iff the fixed point moves. STOP on unexpected movement.
- **Seed build:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/<task>/build` (repo root). **Seed rotate:** `bash scripts/seed/archive_seed.sh <zig1> <gen> release/seed/zig1-seed.tgz --update-changelog`. `timeout 120` on every binary. `fastedit` per `docs/sf/AGENTS.md` §X.7.
- **Tech docs** per AGENTS §1.1.1 (the `c89_emit.zig` doc, the runtime/PAL docs, `docs/reference/Language_Spec_Z98.md` §4's per-type table, `docs/sf/QUICK_REF.md`).

---

### Task 0 (M): Review the 7G investigation and freeze the decision table

**Files:** `.superpowers/sdd/2026-09-22-z98-manual-volume-I-plan/task-7G-report.md` (read); `.superpowers/sdd/2026-09-22-z98-print-formatting-plan/task-0-report.md` (write).

**Interfaces:**
- Consumes: `task-7G-report.md`.
- Produces: a reviewed, frozen per-case decision table this plan's tasks implement.

- [ ] **Step 1:** Run the task-review of `task-7G-report.md` (spec compliance + accuracy), as the 7G task never received its review.
- [ ] **Step 2:** Resolve any findings; correct the report in place.
- [ ] **Step 3:** Confirm every FIX/CLEAN-REJECT row against official Zig 0.15.2 (spot-check the STOP rows).
- [ ] **Step 4:** Write `task-0-report.md` (frozen table + any corrections). No `sf/src` edits, no commit.

---

### Task 1 (F): Create `std_fmt` and migrate the primitives

**Files:** Create `sf/src/std_fmt.zig`; modify `sf/src/std.zig` (re-export `fmt`); modify `sf/src/c89_emit.zig` (emit mangled `std.fmt` calls + auto-import); modify `sf/src/emit_support.zig` + `sf/src/include/zig_runtime.c` (retire the C definitions); `release/seed/` (rotation); docs.

**Interfaces:**
- Consumes: the frozen table (Task 0).
- Produces: `std.fmt` printers in Z98; the compiler emitting mangled `std.fmt` calls; the C `std_print_*` definitions retired.

- [ ] **Step 1:** Create `sf/src/std_fmt.zig` with the printer set (`printI32/U32/I64/U64`, `printF64`, `printBool`, `printChar`, `printStr`, `printHex*`) implemented in Z98 over `@stdoutWrite` / the PAL float helper. Re-export as `std.fmt` in `sf/src/std.zig`.
- [ ] **Step 2:** Change `getPrintFnName` to return the **`std.fmt` function name**; make the emitter emit a **mangled cross-module call** into `std_fmt`.
- [ ] **Step 3:** Auto-import `std_fmt` in the print-lowering path; retire the C `std_print_*` definitions (lockstep).
- [ ] **Step 4:** Rebuild; verify the f32/`{}`/`{d}`/`{x}`/`{c}`/`{s}` routes still work; leave the fixture + standalone repro; **re-baseline the 4-MD5 gates** (the dump now carries `std_fmt`).
- [ ] **Step 5:** Gate battery + seed rotation + docs + `EXPECTED_FAIL`/QUICK_REF.
- [ ] **Step 6:** Commit — `refactor(std): move the print primitives into std.fmt`.

---

### Task 2 (F): Dispatch and runtime format fixes (E1/E2/E3)

**Files:** `sf/src/c89_emit.zig` (`getPrintFnName`); `sf/src/std_fmt.zig` (signed `{x}`, integral float); the PAL float helper (`sf/src/include/zig_pal.c` + `sf/src/emit_support.zig`).

**Interfaces:**
- Consumes: Task 1's `std.fmt` seam.
- Produces: `usize`/arb-int/wide-enum routed by width/signedness; `{x}` on negative signed values prints signed decimal; integral floats print without `.0`.

- [ ] **Step 1:** Rewrite `getPrintFnName` into a width/signedness dispatcher (`typeRegistryIntWidthBits`/`IsSigned`; integer-like = ints + arb + `c_char` + `enum` + `integer_literal`).
- [ ] **Step 2:** `std.fmt` hex printers: signed decimal when `val < 0`.
- [ ] **Step 3:** `pal_f64_to_str`: omit `.`+fraction when the value is integral (`7.0`→`7`).
- [ ] **Step 4:** Fixtures (`usize` wide, arb size-8, small-int `{x}`, negative `{x}`, integral float) + re-capture the f32 golden (`7.0`→`7`); rebuild + verify.
- [ ] **Step 5:** Gate battery + seed rotation + docs.
- [ ] **Step 6:** Commit — `fix(std): route print by width/signedness and fix {x}/float formats`.

---

### Task 3 (F): Print-format validator and rejects

**Files:** `sf/src/lower.zig` (`lowerPrintFmt`); `sf/src/diagnostics.zig` (+`ERR_3063`); fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `error[3013]` (spec/type mismatch) and `error[3063]` (no printer / operator-ruled Q3 residual) at the argument span; rc=2 / 0 `.c`.

- [ ] **Step 1:** Track explicit-vs-`{}` specifiers; add the `printFmtCheck` validator implementing the spec §6 tables (and the `TEMP_NONE`/temp-range guard at the argument deref).
- [ ] **Step 2:** Add `ERR_3063_PRINT_TYPE_NOT_SUPPORTED = 3063` to `diagnostics.zig` *(operator ruling Q1, 2026-09-24: 3058 is live `ERR_3058_CONDITION_NOT_BOOL`)*.
- [ ] **Step 3:** Emit at the argument node's span, level 0; do not double-report an already-invalid specifier.
- [ ] **Step 4:** Reject fixtures (`error[3013]`: `{c}` non-u8, `{s}` non-string, `{x}`/`{d}` bool, float `{c}`/`{s}`, `u8 {s}`, non-u8 slice, `{}` on `[]const u8`; `error[3063]`: frozen-table no-printer kinds + the Q3 bounded residuals) + positive control; rebuild + verify.
- [ ] **Step 5:** Gate battery + seed rotation + docs (spec §4 table).
- [ ] **Step 6:** Commit — `fix(lower): validate print format/type combinations`.

---

### Task 4 (I/F): Aggregate and tuple printers

**Files:** `sf/src/lower.zig` / `sf/src/c89_emit.zig` (generate per-type printers); `sf/src/std_fmt.zig`; fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `{}` on struct/union/tagged-union/packed-union/tuple prints Zig's `. { .a = 1 }` / `.{ 1, 2, 3 }`.

- [ ] **Step 1 (I):** Investigate the generated-printer shape (naming, where emitted, recursion/depth, self-reference) against Zig 0.15.2; write the report.
- [ ] **Step 2 (F):** Implement the compiler-generated per-type printers calling `std.fmt` field printers.
- [ ] **Step 3:** Fixtures + goldens; rebuild + verify.
- [ ] **Step 4:** Gate battery + seed rotation + docs.
- [ ] **Step 5:** Commit — `feat(std): print aggregates and tuples`.

---

### Task 5 (I/F): Enum member names and error-set names

**Files:** `sf/src/lower.zig` / `sf/src/c89_emit.zig` (name tables); `sf/src/std_fmt.zig`; fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: enum `{}` prints `.member`; `error_set` `{}` prints `error.Name`.

- [ ] **Step 1 (I):** Investigate the name-table shape + the runtime lookup; verify Zig's exact output for enum `{}`/`{d}`/`{x}` and error-set `{}`; write the report.
- [ ] **Step 2 (F):** Implement the tables + `std.fmt` lookups.
- [ ] **Step 3:** Fixtures + goldens; rebuild + verify.
- [ ] **Step 4:** Gate battery + seed rotation + docs.
- [ ] **Step 5:** Commit — `feat(std): print enum and error-set names`.

---

### Task 6 (I/F): Pointer/fn-pointer `{}` and float `{x}`

**Files:** `sf/src/c89_emit.zig` (`getPrintFnName`); `sf/src/std_fmt.zig`; fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: pointer/fn-pointer `{}` prints `T@0x…` / `fn …@0x…`; float `{x}` prints a C89 hex-float.

- [ ] **Step 1 (I):** Verify Zig's exact pointer/fn-pointer and hex-float output; investigate the hex-float algorithm (C89, no `%a`); write the report.
- [ ] **Step 2 (F):** Implement `printPtr` / `printFnPtr` / `printFloatHex`.
- [ ] **Step 3:** Fixtures + goldens; rebuild + verify.
- [ ] **Step 4:** Gate battery + seed rotation + docs.
- [ ] **Step 5:** Commit — `feat(std): print pointers and hex floats`.

---

### Task 7 (F): Closeout

**Files:** docs; `release/seed/`; `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`; the manual if a transcript changed.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: a whole-set review + verification sweep and the final seed.

- [ ] **Step 1:** Whole-set review (every spec §4 row matches; no dead code; no divergence undocumented).
- [ ] **Step 2:** Full QUICK_REF gate battery; 4-MD5 re-baseline recorded; corpus join-diff explained; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK.
- [ ] **Step 3:** Update `docs/reference/Language_Spec_Z98.md` §4 (per-type table + `error[3063]`), the tech docs, QUICK_REF, EXPECTED_FAIL; re-capture any manual transcript that moved.
- [ ] **Step 4:** Rotate the seed; commit — `docs: close out the print-formatting program`.

---

## Amendment 1 (2026-09-25) — post-closeout B-class hardening round

**Context:** The final whole-branch review + fix wave (through `b50f547d`, seed v86) found a set of
latent defects that were under-labeled as Minor in the per-task reviews and left unfixed. The
operator has directed this amendment to resolve them as a new round of tasks. Explicitly excluded:
B1 (the dev-time `python3` rename) is a disclosed process breach with no artifact to fix, and B6
(the untyped-literal print route) was already fixed in the final-review fix wave.

**B-class items covered:** B2 `emitPtrValuePrint` silently emits nothing when `zigPrintNameAppend`
fails; B3 pointer/optional depth caps disagree (emitter bails at 8, validator allows 16 → valid
programs can compile rc=0 and then fail at gcc); B4 `array_items[pty.payload_idx].elem` indexed
without the range guard (potential OOB read); B5 forward-referenced tuple-global elements
(`var g = .{ b, 7 }; const b = Pair{...}`) still emit gcc-invalid C; B7 stale gate-reference docs
(`QUICK_REF.md:32` archived-binary md5 still `96c72391…`, `:52` "v85 archive", `:36` "29 std
`.zig`"), plus the parked doc items (Language_Spec literal-guarantee overstatement outside the
evaluable window; R11 latent-risk mechanism wording; `00_lexer_parser.md:161` false `[*c]T`
grammar claim; CHANGELOG blank lines); B8 auto-import over-approximation (`error[3048]` for an
unrelated identifier named `print` when a lib dir lacks `std_fmt.zig`).

**Sequencing:** executes after `b50f547d`. The plan's Global Constraints apply unchanged (oracle
Zig 0.15.2, `timeout 120`, seed build, fixtures + standalone repro, full gate battery, docs,
STOP on unexpected movement). Per R2-print the seed rotates only at this round's closeout (Task 12).

---

### Task 8 (I/F): Pointer-name emission hardening — silent drop + depth caps (B2, B3)

**Files:** `sf/src/c89_emit.zig` (`emitPtrValuePrint`, `emitPointeeDep`); `sf/src/lower.zig` (validator depth); fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: no silent emission drop on a name-append failure; one documented pointer-chain depth cap enforced consistently by the validator and the emitter (either a clean `error[3063]` beyond the cap or correct emission at 16), with an oracle-checked fixture.

- [ ] **Step 1 (I):** Reproduce both defects (`emitPtrValuePrint` silent no-op at `c89_emit.zig:6376`; a >8-deep pointer/optional chain accepted by the validator at `lower.zig:1111` then emitted with an unknown type). Decide the cap policy against Zig 0.15.2's behavior; write the report.
- [ ] **Step 2 (F):** Make the name-append failure non-silent (defensive fallback that cannot emit broken C, or a hard internal failure — per the investigation); align the validator/emitter caps.
- [ ] **Step 3:** Fixture + standalone repro for the >8-deep chain (accept-if-fixed or clean-reject per the decision, Zig-twin-cross-checked); rebuild + verify.
- [ ] **Step 4:** Gate battery (4-MD5 expected UNCHANGED); docs; seed NOT rotated (Task 12).
- [ ] **Step 5:** Commit — `fix(print): harden pointer emission and align the depth caps`.

---

### Task 9 (I/F): Invariant guard + tuple-global forward refs (B4, B5)

**Files:** `sf/src/lower.zig` (payload-elem lookup); `sf/src/semantic_analyzer.zig` / `sf/src/front_resolution.zig` (tuple globals); fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: a guarded payload-elem lookup; forward-referenced tuple-global elements either resolved correctly (preferred) or clean-rejected, never gcc-invalid C.

- [ ] **Step 1 (I):** Reproduce the unguarded `array_items[pty.payload_idx].elem` read and the forward-ref tuple-global gcc failure (`incompatible types`); determine fix (multi-pass/re-resolve) vs clean reject; write the report.
- [ ] **Step 2 (F):** Add the `types_len`-style range guard; fix the tuple-global forward ref (prefer fix; keep direct/global tuple fixtures green).
- [ ] **Step 3:** Fixtures (guard probe + forward-ref tuple global) + oracle twin; rebuild + verify.
- [ ] **Step 4:** Gate battery (4-MD5 expected UNCHANGED); docs; seed NOT rotated (Task 12).
- [ ] **Step 5:** Commit — `fix(lower): guard the payload-elem lookup and fix tuple-global forward refs`.

---

### Task 10 (I/F): Auto-import precision (B8)

**Files:** `sf/src/main.zig`, `sf/src/c89_emit.zig`, `sf/src/lower.zig` (print lowering path); fixtures/repro.

**Interfaces:**
- Consumes: Tasks 1–7 (must preserve the Task 1 alias auto-import fix).
- Produces: `std_fmt` imported only when a `print` is actually lowered; an unrelated identifier named `print` no longer triggers `error[3048]` when the lib dir lacks `std_fmt.zig`.

- [ ] **Step 1 (I):** Characterize the over-approximation (`astStoreHasPrintRef` matches any ident/field named `print`); enumerate options (defer the import to the lowering site, lenient no-op when no print lowered, keep + document); report with a recommendation.
- [ ] **Step 2 (F):** Implement the minimal precision fix unless it breaks the alias path; if it does, clean-reject/document as a bounded residual instead.
- [ ] **Step 3:** Fixture: an unrelated identifier named `print` builds with and without `std_fmt` present; the alias fixture (`stdlib_print_alias_xmod`) still passes; rebuild + verify.
- [ ] **Step 4:** Gate battery (4-MD5 expected UNCHANGED); docs; seed NOT rotated (Task 12).
- [ ] **Step 5:** Commit — `fix(print): import std_fmt only when a print is lowered`.

---

### Task 11 (F): Gate-reference and parked-doc corrections (B7 + parked items)

**Files:** `docs/sf/QUICK_REF.md`; `docs/reference/Language_Spec_Z98.md`; `docs/superpowers/specs/2026-09-22-z98-print-formatting-design.md`; `repro/mi_matrix/EXPECTED_FAIL.md`; `sf/docs/tech_docs/{00_lexer_parser,10_c_runtime}.md`; `release/seed/CHANGELOG.md`.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: accurate gate-reference and residual statements; no source changes.

- [ ] **Step 1:** Fix `QUICK_REF.md:32` archived-binary md5 (v85 `96c72391…` → v86 `5d3ca725…`), `:52` "v85 archive", `:36` "29 std `.zig`" → 30.
- [ ] **Step 2:** Correct Language_Spec §4's literal-guarantee claims to the evaluable window (`1<<256`/`1<<300`/bare `2^64` fallback paths), the R11 latent-risk mechanism wording (`visiting` guard terminates; mutual cycles are a gcc forward-declaration error), `00_lexer_parser.md:161`'s false `[*c]T` grammar claim, and the CHANGELOG blank lines.
- [ ] **Step 3:** Commit — `docs: correct the gate-reference and parked residual statements` (docs-only; no gate battery required, but record that 4-MD5 and the fixed point are untouched).

---

### Task 12 (F): Amendment closeout

**Files:** docs; `release/seed/`; `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: Tasks 8–11.
- Produces: a whole-round review + verification sweep and the final seed.

- [ ] **Step 1:** Whole-round review: every B item resolved or explicitly re-ruled; no new divergence undocumented.
- [ ] **Step 2:** Full QUICK_REF gate battery (closure, 4-MD5, corpus join-diff explanation, stdlib, matrix, `check_emit_support.sh` 7/7, `verify_upgraded.sh` CLOSEOUT OK, test binaries, self-emission).
- [ ] **Step 3:** Update `docs/reference/Language_Spec_Z98.md`, the tech docs, QUICK_REF, EXPECTED_FAIL for any behavior changed by this round.
- [ ] **Step 4:** Rotate the seed (v86 → v87, authorized at this closeout); commit — `docs: close out the print-formatting hardening round`.
