# Z98 Manual — Volume IV (Reference) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the Z98 Language Specification into 25 lookup-oriented Reference pages under `docs/sf/manuals/en/vol4-*.html`, re-verified against the current compiler/source, with reused verified snippets instead of runnable chapter samples — every page gated by `check.sh` and the search-index byte-match.

**Architecture:** One plan: a read-only inventory (Task 0), 25 page tasks in a **big-mechanical-pages-first** order, and a whole-set closeout (Task 26). Each page task ports its topic from the spec/source, verifies every claim on the seed compiler, reuses existing tests/fixtures/samples for snippets, writes the page from the shipped `vol4-24-html-style.html` skeleton, wires navigation, gates, and commits. Website-only **except** operator-ruled scoped compiler I/F amendments.

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, 1998-era vanilla JavaScript (`doc.js`), GIF assets, Python 3 (`check.py`), the seed-built `zig1` + `gcc -m32`, the committed `scripts/win32_cross/` harness (`i686-w64-mingw32-gcc` + 32-bit `wine`) only if a page makes a Win claim, git.

**Spec:** `docs/superpowers/specs/2026-10-03-z98-manual-volume-IV-design.md` (binding for this plan). Program-level spec: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md`. Blueprint: `docs/sf/manuals/manuals_blueprint.txt` Part 6 (lines 205–235). Prior-volume register/style: `docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md`.

**Sequence:** PREVIOUS = `docs/superpowers/plans/2026-09-30-z98-manual-volume-III-plan.md` (Volume III, COMPLETE; seed rotated v89 → v90 at the Amendment A1 closeout). NEXT = the Volume V (HOWTO) plan.

**Compiler amendments:** an amendment is appended to this plan only by **operator ruling**, as an I/F pair — Task Na (I) read-only investigation; Task Nb (F) fix with a `repro/mi_matrix/` fixture + a standalone `repro/` program + the QUICK_REF gate battery verbatim (STOP on unexpected movement) + tech-doc updates + a two-hop closure verification with the moved fixed point recorded + a commit. Amendment tasks are the ONLY tasks permitted to touch `sf/src`, `scripts/`, `repro/`, or `release/seed/`. **Seed rotation is closeout-only:** the seed is rotated once at Task 26 iff an amendment moved the fixed point.

## Global Constraints

- **Website only, with scoped exceptions (spec §6).** Do NOT edit `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**` — EXCEPT tasks inserted by an operator-ruled amendment. Every other task leaves the compiler fixed point and the seed untouched.
- **STOP on a real compiler defect** found while verifying a claim — report the minimal reproduction; do not fix `sf/src`, do not document around it, do not re-scope the page (phase0 §9/§11). Compiler correctness takes priority.
- **All content files under `docs/sf/manuals/`** except this plan and its spec.
- **Reference style, not tutorial (spec §3).** Lookup-oriented: one-line definition, then exact tables/lists. **No runnable chapter samples, no Win9x screenshot figures.** Snippets are short verified illustrative code blocks; **reuse** existing `sf/src/tests/*`, `repro/mi_matrix/`, or `src/vol*/` material wherever it demonstrates the rule — only author a new snippet when nothing reusable exists.
- **Exactness (phase0 §3).** Every signature, field, flag, code, and message is quoted verbatim from source/compiler; a value that cannot be reproduced is fixed or dropped.
- **Neutral register.** No honesty arguments/callouts (Volume II/III own the framing); a page may end with a short "See also" list of existing pages.
- **HTML restrictions (phase0 §6.1).** HTML 4.0 Transitional in the HTML 3.2/4.0 intersection. No HTML5 structural tags; no `<div>` (layout via `<table>`); ISO-8859-1 meta; every page carries `<link rel="home|up|prev|next">`, a sidebar TOC (all 25 Volume IV entries), a language bar, and a prev/contents/next footer.
- **CSS/JS/asset/forbidden (phase0 §6.2–§6.5).** CSS1 external only (`z98.css`/`z98-print.css`); no inline `<style>`; one `doc.js` ≤ 2048 bytes, four functions; GIF only; the checker's forbidden list.
- **Navigation, non-contiguous shipping (spec §4).** Sidebar lists all 25 entries (shipped = link, unshipped = `<i>(planned)</i>`); `rel`/footer point at the nearest shipped page; Task 26 restores the continuous chain.
- **Cross-references (spec §4).** Only existing files may be `<a>`-linked (all Volume II/III chapters, the shipped Volume IV pages, existing `docs/reference/*.md` targets); planned volumes are prose `(planned)`.
- **English only.** The language bar carries English plus the "not yet available" plain-text entries, as the existing pages do.
- **Environment deviation (binding).** `docs/sf/manuals/build.sh` HANGS at `rm -rf docs/sf/manuals/dist`. **Never run `build.sh` or `serve.sh`; never touch `dist`.** Gate with `bash docs/sf/manuals/check.sh`; regenerate the search index with `/tmp/z98_build_tmp.sh` (writes only `/tmp/z98_search-data.regen.js` + `/tmp/z98_dist_tmp`) and require a byte-match to `en/search-data.js` (copy over only if it differs, and report).
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Seed model (binding).** Reference compiler rebuilt per `release/seed/`, seed **v90** (archive md5 `430f4f9ce415852b4ca5b1bb01261189`; archived binary = fixed point `f78bebc448e267b32419afdb13afb386`). Rotated only by Task 26, only if an amendment moved the fixed point.

## Compiler under test

```bash
FIXED_POINT_MD5=f78bebc448e267b32419afdb13afb386 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Every binary runs under `timeout 120`. Compile/run a snippet:

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out <file>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

For a Win claim only (rare in a Reference): use the committed `scripts/win32_cross/` harness (mingw cross-compile + 32-bit `wine` run + LF-normalized parity), never emission alone; the emitted OpenWatcom `build_owc.bat`/`wcc386` path is emitted-only on this host.

### How each page task works (shared steps)

Each page task repeats this shape; its own block lists Files/Consumes/Must-cover:

1. **Read** the source of record for the topic (`docs/reference/Language_Spec_Z98.md` section **and** the authoritative `sf/src/**`), plus the shipped `vol4-24-html-style.html` skeleton and one existing Reference page for markup.
2. **Verify** every claim on the seed compiler; for each snippet **reuse** an existing verified program from the Task-0 reuse inventory (or compile a new minimal one only when none fits).
3. **Write** `docs/sf/manuals/en/<file>.html` — lookup structure, exact tables, verified snippets, no sample/figure.
4. **Cross-check** links (only existing targets) and the sidebar/`rel`/language-bar/footer.
5. **Wire** the page: make its own sidebar row a link (unbolded link on siblings), add it to `en/toc.html` and `en/vol4-00-title.html` if that page lists pages, and re-point the nearest shipped neighbours' `rel`/footer.
6. **Gate**: `bash docs/sf/manuals/check.sh` green; regenerate the index with `/tmp/z98_build_tmp.sh` and confirm byte-match.
7. **Commit**: `docs(manual): add Volume IV page NN — <title>` (or `update` for T23–T25).

---

### Task 0: Delta/claim inventory (read-only)

**Files:**
- Read-only: `docs/reference/Language_Spec_Z98.md`, `sf/src/**` (diagnostics, main, std modules, pal, parser, markers), `docs/sf/QUICK_REF.md`, the shipped `en/vol4-*.html`, `en/toc.html`, `sf/src/tests/**`, `repro/mi_matrix/**`, `docs/sf/manuals/src/vol*/**`.
- Create (untracked): `.superpowers/sdd/2026-10-03-z98-manual-volume-IV-plan/task-0-report.md`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the spec's page index (§2), reference style (§3), verification rules (§5), and open items (§9).
- Produces: the **port map** (each page → spec section + authoritative source file/line ranges); the **diagnostics table** (every `sf/src/diagnostics.zig` member: `ERR_*` name, printed ordinal, level, exact message); the **CLI flag list**; the **stdlib module surface** (public symbols + error sets per module, and the `sf/src/std.zig` re-export set); the **PAL surface**; the **marker table**; the **grammar source decision** (spec EBNF vs `parser.zig`); the **reuse inventory** (per page: which existing test/fixture/sample/`src/vol*` program supplies each snippet); the **stale-spot list**; confirmation that no page needs a sample/figure; and the predicted compiler I/F pairs.

**Don't-list.** Do not re-measure the language surface already verified in Volumes I–III; cite those reports as inherited-verified. This task inventories sources and reusable snippets, not new behavior.

- [ ] **Step 1: Build the compiler** per "Compiler under test" and record its md5.
- [ ] **Step 2: Build the port map + reuse inventory.** For each of the 25 pages, record the spec section, the authoritative `sf/src` file(s), and the concrete reusable snippet source(s) (test/fixture/sample) — or "new snippet needed: <why>".
- [ ] **Step 3: Build the mechanical tables.** Diagnostics (name/ordinal/level/message), CLI flags, stdlib/PAL signatures + error sets, markers, and the `std.zig` re-export set.
- [ ] **Step 4: Resolve the stale-spot list** and record the exact corrected wording each affected page must use.
- [ ] **Step 5: Confirm** there are no samples/figures and that Task-26's closeout checklist matches the plan.
- [ ] **Step 6: Write the report** (`task-0-report.md`) and return a summary. No commit.

---

### Task 1: Page 21 — Diagnostics
**Files:** Create `docs/sf/manuals/en/vol4-21-diagnostics.html`; modify `en/toc.html`, `en/vol4-00-title.html` (if it lists pages), `en/vol4-15-builtins.html`, `en/vol4-24-html-style.html`, `en/search-data.js`.
**Consumes:** Task 0 diagnostics table. **Must cover:** every `sf/src/diagnostics.zig` member, alphabetical by `ERR_*`/`WARN_*`/`INFO_*` name, with the **printed ordinal** (`error[N]`, `warning[N]`, `info[N]`) and the exact default message; a short note that the printed N is the enum ordinal, not the name's number (e.g. `ERR_2012_ANYTYPE_NOT_SUPPORTED` → `error[16]`); snippet reuse per Task 0. **Commit:** `docs(manual): add Volume IV page 21 — diagnostics`.

### Task 2: Page 22 — CLI
**Files:** Create `docs/sf/manuals/en/vol4-22-cli.html`; wire as above.
**Consumes:** Task 0 CLI list. **Must cover:** every `zig1` flag/argument and default from `sf/src/main.zig`; the seed-build recipe pointer; `-o`/`--dump-c89`/`--markers`/`--track-memory`/`-mm*`/`-s*`/`-osw`/`-osl`/`-fsafe`/`-ffast` as they actually exist. **Commit:** `docs(manual): add Volume IV page 22 — the zig1 command line`.

### Task 3: Page 19 — PAL
**Files:** Create `docs/sf/manuals/en/vol4-19-pal.html`; wire as above.
**Consumes:** Task 0 PAL surface. **Must cover:** the user-facing `pal.*` signatures (file/stdout/stderr/memory/trap/console as applicable), quoted verbatim; note the PAL is an internal contract, not part of the language. **Commit:** `docs(manual): add Volume IV page 19 — the platform layer`.

### Task 4: Page 20 — Markers
**Files:** Create `docs/sf/manuals/en/vol4-20-markers.html`; wire as above.
**Consumes:** Task 0 marker table + `--markers` output. **Must cover:** every marker actually emitted, keyed to the phase/component that emits it, with a short meaning and the flag that enables it. **Commit:** `docs(manual): add Volume IV page 20 — pipeline markers`.

### Task 5: Page 18 — Standard library
**Files:** Create `docs/sf/manuals/en/vol4-18-stdlib.html`; wire as above.
**Consumes:** Task 0 stdlib surface. **Must cover:** one **full section per re-exported module** (each module gets the room its surface deserves — signatures, error sets, and notes verbatim from source); the `sf/src/std.zig` re-export set; the concrete-only nature (no generics) where relevant; snippet reuse. **Commit:** `docs(manual): add Volume IV page 18 — the standard library`.

### Task 6: Page 01 — Grammar
**Files:** Create `docs/sf/manuals/en/vol4-01-grammar.html`; wire as above.
**Consumes:** Task 0 grammar decision. **Must cover:** the full grammar, EBNF-style, transcribed from the authoritative parser (`sf/src/parser.zig`) — productions, precedence, and the constructs Z98 rejects. **Commit:** `docs(manual): add Volume IV page 01 — grammar`.

### Task 7: Page 02 — Types
**Files:** Create `docs/sf/manuals/en/vol4-02-types.html`; wire as above.
**Consumes:** spec §1.1–§1.7 + `sf/src/type_registry.zig`. **Must cover:** primitives, widths/signedness, `usize`/`isize`, arbitrary-width ints, `bool`/`void`/`noreturn`/`c_char`, the coercion table (linking the dedicated rows on later pages), and the type-kind list. **Commit:** `docs(manual): add Volume IV page 02 — types`.

### Task 8: Page 03 — Pointers
**Must cover:** spec §1.2 — `*T`, `*const T`, `*volatile T`, `[*]T`, `**T`, single-pointer indexing rules, slices-adjacent pointer forms, and the pointer builtins (cross-ref the builtins page). **Commit:** `docs(manual): add Volume IV page 03 — pointers`.

### Task 9: Page 04 — Structs
**Must cover:** spec §1.3 structs and packed structs — layout/align-8 model reference, field access, literal rules, packed bit rules, `@offsetOf` forms and rejects. **Commit:** `docs(manual): add Volume IV page 04 — structs`.

### Task 10: Page 05 — Enums
**Must cover:** spec §1.3 enums — backing types, ranges, `.member`, `@enumToInt`/`@intToEnum`, switch rules. **Commit:** `docs(manual): add Volume IV page 05 — enums`.

### Task 11: Page 06 — Unions
**Must cover:** spec §1.3 unions — bare, packed, tagged; tag access rules (Amendment FX16 sugar); payload rules; printing behavior. **Commit:** `docs(manual): add Volume IV page 06 — unions`.

### Task 12: Page 07 — Tuples
**Must cover:** spec §1.3 tuples — type syntax, `.N`/`._N`/`t[N]`, destructuring, limits. **Commit:** `docs(manual): add Volume IV page 07 — tuples`.

### Task 13: Page 08 — Arrays and slices
**Must cover:** spec §1.4 — fixed arrays, slices, `.len`/`.ptr`, indexing/bounds, string literals, the const rules. **Commit:** `docs(manual): add Volume IV page 08 — arrays and slices`.

### Task 14: Page 09 — Errors
**Must cover:** spec §1.5 — error sets, error unions, `error.Name`, `try`/`catch`, `errdefer`, the enclosing-return rules (FX12), and `anyerror` status (Amendment A1). **Commit:** `docs(manual): add Volume IV page 09 — errors`.

### Task 15: Page 10 — Optionals
**Must cover:** spec §1.6 — `?T`, `if`/`while` capture, `orelse`, `.?`, representation, traps. **Commit:** `docs(manual): add Volume IV page 10 — optionals`.

### Task 16: Page 11 — Aliases
**Must cover:** spec §1.7 — `const T = ...` aliases, where they are allowed, and the current limits. **Commit:** `docs(manual): add Volume IV page 11 — type aliases`.

### Task 17: Page 12 — Statements
**Must cover:** spec §3.1 — declaration/assignment/expression statements, `defer`/`errdefer`, blocks, and the statement-level rules. **Commit:** `docs(manual): add Volume IV page 12 — statements`.

### Task 18: Page 13 — Control flow
**Must cover:** spec §3.2 — `if`/`while`/`for`/`switch`/labels/`break`/`continue`, the mandatory-`else` switch rule, and capture rules. **Commit:** `docs(manual): add Volume IV page 13 — control flow`.

### Task 19: Page 14 — Error expressions
**Must cover:** spec §3.3 — `try`, `catch`, `orelse`, `if (opt) |v|`, `if (eu) |v| else |e|`, and the related diagnostics. **Commit:** `docs(manual): add Volume IV page 14 — error and optional expressions`.

### Task 20: Page 16 — Async / coroutines
**Must cover:** spec §4.1 + `sf/src/std_async.zig` — the four `@async*` builtins, the frame/step ABI (sizes/offsets measured in Vol III Task 0), `std.async` (`Context`/`Task`/`Scheduler`/`tick`/`awaitTask`/`waitFor`/`suspendUntil`), and the two-context rule. **Commit:** `docs(manual): add Volume IV page 16 — async and coroutines`.

### Task 21: Page 17 — Memory
**Must cover:** spec §2 — the arena API, init/reset patterns, dual-arena, tiers/`-mm*`, and the 16 MB budget pointer. **Commit:** `docs(manual): add Volume IV page 17 — memory and the arena`.

### Task 22: Page 23 — Limits
**Must cover:** spec §5 and §7 verbatim as the honest list — known limitations/workarounds and "not yet supported" (permanently dropped / designed-not-implemented). **Commit:** `docs(manual): add Volume IV page 23 — limitations`.

### Task 23: Page 15 — Builtins (audit/update)
**Files:** Modify `docs/sf/manuals/en/vol4-15-builtins.html`; wire as needed.
**Must cover:** audit the shipped page against the current `sf/src` §4 builtin set; correct any stale entries; keep the alphabetical structure; reference style consistent with the new pages. **Commit:** `docs(manual): update Volume IV page 15 — builtins`.

### Task 24: Page 24 — HTML style (audit/update)
**Files:** Modify `docs/sf/manuals/en/vol4-24-html-style.html`; wire as needed.
**Must cover:** audit against phase0 §6 + blueprint Part 7; ensure the rules match the current checker (`check.py`). **Commit:** `docs(manual): update Volume IV page 24 — HTML style`.

### Task 25: Page 00 — Title / how to use (audit/update)
**Files:** Modify `docs/sf/manuals/en/vol4-00-title.html`; wire as needed.
**Must cover:** how to use the Reference (lookup, page map, cross-volume pointers); flip the toc/sidebar rows for shipped pages; keep the shipped-page list accurate. **Commit:** `docs(manual): update Volume IV page 00 — how to use the Reference`.

### Task 26: Whole-set closeout
- [ ] **Step 1: Re-run every snippet/claim** in the 25 pages on the rebuilt seed; confirm each quoted value/message reproduces.
- [ ] **Step 2: Navigation and completeness** — continuous `rel` chain `toc → vol4-00 → … → vol4-23 → next`; all 25 sidebars list 25 rows; `en/toc.html` links every shipped page; no shipped page carries a stale `(planned)` for a shipped page.
- [ ] **Step 3: No sample / no figure audit** — confirm no `src/vol4/` program was added and no `todo-figures-list.html` row was added by Volume IV (1:1 unchanged).
- [ ] **Step 4: Gates** — `check.sh` green; `/tmp/z98_build_tmp.sh` byte-match idempotent.
- [ ] **Step 5: Spec status** — set `2026-10-03-z98-manual-volume-IV-design.md` to implemented + a closeout section.
- [ ] **Step 6: Seed rotation iff moved** — if any amendment moved the fixed point, rotate once via `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog` and record the new value in `docs/sf/QUICK_REF.md` "Current seed".
- [ ] **Step 7: Final commit** — `docs(manual): Volume IV closeout — whole-set review and verification sweep`.

## Self-Review

- **Spec coverage:** every spec §2 row maps to a task (00–24 → T25/T6–T25 as numbered); §3 style, §4 shape, §5 accuracy, §6 amendments, §7 verification each have plan constraints; §9 items are Task 0's deliverable.
- **Placeholder scan:** Task 0 fills the mechanical tables; no task says "TBD" — T1–T22 name their exact source and must-cover list.
- **Type consistency:** page filenames, task numbers, and commit-message convention match the spec index; `rel`/sidebar rules match Volume III's shipped pattern.
- **Ordering:** big mechanical pages (diagnostics, CLI, PAL, markers, stdlib, grammar) are Tasks 1–6 per the operator ruling; narrative/type pages follow; shipped pages are audited last but before closeout.

---

## Amendment A2 — enum sub-byte backing + empty named-struct layout (operator-ruled m1470)

**Origin:** found while authoring Volume IV page 04 (`structs`) and page 05 (`enums`). Operator ruling m1470: D1 = option 2, D2 = option 2 if small scoped; **one I/F pair covers both**.

**D1 — sub-byte enum backing interaction (seed v90, `f78bebc448e267b32419afdb13afb386`).** Reproduced:
- `const Small = enum(u3) { A, B, C };` alone → rc 0.
- `const Wide = enum(u5) { X = 0, Y = 31 };` alone → rc 0.
- **Both together** → rc 2, `error[3000]: enum tag value does not fit the enum backing width (must fit 2^N - 1); no silent truncation` at the `u3` enum. Zig 0.15.2 accepts both.

**D2 — empty named-struct layout.** `const E = struct {};` compiles rc 0 but reports a bogus layout `12/4/96` (the layout pass never ran; contradicts the min-1 rule at `type_resolver.zig:304`).

### Task A2-I: read-only investigation (both defects)
- [ ] Reproduce both with minimal programs (record exact rc/stdout/stderr).
- [ ] Root-cause each in `sf/src/**`; establish correct semantics (oracle = Zig 0.15.2 for validity).
- [ ] Specify the minimal fix per defect and the blast radius (self-emission, corpus, stdlib, 4-MD5).
- [ ] Specify the fixtures: `repro/mi_matrix/enum_subbyte_backing_xmod/` and `repro/mi_matrix/empty_named_struct_xmod/`, plus standalone `repro/` programs.
- [ ] Report `task-A2-I-report.md`; no `sf/src` edits; no commit.

### Task A2-F: implement both fixes
- [ ] Implement the two minimal fixes; add the fixtures + standalones.
- [ ] Run the QUICK_REF gate battery verbatim (self-compile two-hop closure, example matrix, 4-MD5 emitted-C, stdlib runtime gate, corpus `-s0`, `check_emit_support.sh`, `verify_upgraded.sh`); **STOP on unexpected movement**.
- [ ] Update tech docs per `docs/sf/AGENTS.md` §1.1.1 + `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`; verify the two-hop closure and record the moved fixed point.
- [ ] Commit the fix(es) (`fix(...)` messages); then a docs commit updating `docs/sf/manuals/en/vol4-05-enums.html` (sub-byte boundary note) and `docs/sf/manuals/en/vol4-04-structs.html` (empty-struct note) to the fixed behavior.
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence:** A2 runs after Task 10's page commit `e8a85200` and before Task 11. **Task 10's review/closure is ON HOLD until A2-F lands** (its boundary note changes).

---

## Amendment A3 — `[_]T` as a declaration type must clean-reject (operator-ruled m1500)

**Origin:** found while authoring Volume IV page 08 (`arrays and slices`); Task-13 review Medium. Operator ruling m1500(1): open the scoped I/F — **parity is required; a gcc failure is not a Z98 failure this early** (Z98 must reject or handle it itself). Operator m1500(2)(3): also fix the Vol II stale warning claim and the page-01/page-08 `[_]T` wording inconsistency.

**Defect.** `var x: [_]i32 = .{1,2,3};` (and any `[_]T` used where a concrete type is required) compiles rc 0 but the emitted C fails (`'x' undeclared`). `[_]T` is the inferred-length form valid only in the array-literal/initializer position (`const a = [_]T{...}` / `var a = [_]T{...}`); as a declaration type Zig rejects it. Parity = a clean Z98 reject (confirm the exact Zig 0.15.2 behavior in A3-I).

### Task A3-I: read-only investigation
- [ ] Reproduce (`var x: [_]i32 = …`, struct field, param, return, cast target) and record exact rc/stderr.
- [ ] Confirm the Zig 0.15.2 oracle behavior for each shape.
- [ ] Root-cause in `sf/src/**` (why the frontend accepts it and the inference path emits invalid C).
- [ ] Specify the minimal fix: reject `[_]T` outside the allowed literal/initializer positions with a clean level-0 diagnostic (reuse `error[2000]` or an existing code; no new code unless ruled).
- [ ] Blast radius (self-emission, corpus, stdlib, 4-MD5); fixtures `repro/mi_matrix/array_inferred_len_decl_reject_xmod` + standalone; verification plan.
- [ ] Report `task-A3-I-report.md`; no `sf/src` edits; no commit.

### Task A3-F: implement
- [ ] Implement the minimal clean reject; add the fixture + standalone; run the QUICK_REF gate battery verbatim (**STOP on unexpected movement**); update tech docs + QUICK_REF + EXPECTED_FAIL; record the moved fixed point; commit the fix.
- [ ] Docs commit: fix `docs/sf/manuals/en/vol4-08-arrays-slices.html` and `docs/sf/manuals/en/vol4-01-grammar.html` to the fixed `[_]T` rule; fix the stale `*const u8 = "literal"` warning claim in `docs/sf/manuals/en/vol2-09-arrays-slices.html` (Vol II, docs-only).
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence:** A3 runs after Task 13 (commit `2b0ee60c`) and before Task 14.

---

## Amendment A4 — `?void` present value must be preserved (operator-ruled m1523)

**Origin:** found while probing Volume IV page 10 (`optionals`); Task-15 review. Operator ruling m1523: option 1 — scoped I/F.

**Defect (controller-verified, seed-side fp `2794fe04e0828c95dd5c2c6fecdea362`).** In a `?void`-returning function, `return;` yields the **absent** value:
```zig
fn done(flag: bool) ?void { if (flag) { return; } return null; }
// if (done(true)) |_| print("present") else print("absent")   →  Z98 prints "absent"
```
Zig 0.15.2 prints `present`. Silent wrong value. Page 10 makes no `?void` runtime claim, so this is a compiler defect, not a page defect.

### Task A4-I: read-only investigation
- [ ] Reproduce all `?void` shapes: `return;` in a `?void` fn; `return {}`/`return undefined` if legal; `var x: ?void = {}`/`= null`; `if (x) |_|`/`x == null`/`x != null`; assigning `?void` results; passing `?void`.
- [ ] Confirm the Zig 0.15.2 oracle behavior for each shape.
- [ ] Root-cause in `sf/src/**` (how `return;` / the void payload interacts with the optional `has_value` model at sema/lowering/emission).
- [ ] Specify the minimal fix; blast radius (self-emission, corpus, stdlib, 4-MD5); fixtures `repro/mi_matrix/optional_void_present_xmod` + standalone; verification plan.
- [ ] Report `task-A4-I-report.md`; no `sf/src` edits; no commit.

### Task A4-F: implement
- [ ] Implement the minimal fix; add fixture + standalone; run the QUICK_REF gate battery verbatim (**STOP on unexpected movement**); update tech docs + QUICK_REF + EXPECTED_FAIL; record the moved fixed point; commit the fix.
- [ ] Docs commit: if page 10 said anything about `?void` shape that changes, correct it; otherwise no manual change.
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence:** A4 runs after Task 15 (commit `efacc0c4`) and before Task 16.

## Amendment A5 — type/alias value position must clean-reject (operator-ruled m1544)

**Origin:** found while probing Volume IV page 11 (`aliases`); Task-16 review (F1). Operator ruling (m1538 option 1; m1544: reuse the existing diagnostic; include `const T = type` in the reject).

**Defect (reviewer-verified, base fp `c1746347cbcdbb39385f325be20b9b6b`).** A type/alias value in a **value position** at module scope compiles rc 0 and emits a poison read:
```zig
const A = i32;
var x = A;              // rc 0; emitted: int zT_1; zig_poison_fill(...); x = zT_1;
```
Zig 0.15.2 rejects (`variable of type 'type' must be const or comptime`). Local type values already clean-reject (`semantic_analyzer.zig:5811-5823`), so module-scope acceptance is inconsistent. The bare `const T = type;` shape is also in scope (m1544): it compiles rc 0 and `T` is unusable.

### Task A5-I: read-only investigation
- [ ] Reproduce all value-position shapes at module scope: `var x = A;` (alias), `var x = i32;` (builtin type), assignment `x = A;`, call arg `f(A)`, return `return A;`, and bare `const T = type;`. Confirm the local forms already reject.
- [ ] Confirm the Zig 0.15.2 oracle rejection for each.
- [ ] Root-cause in `sf/src/**`: why local type values clean-reject (`semantic_analyzer.zig:5811-5823`) but module scope is accepted; whether the module-scope var/const init path skips the type-value check.
- [ ] Specify the minimal fix — reuse the existing raw level-0 `error[3000]` and its existing source/target notes (no new diagnostic code); reject at module scope and for `const T = type`. Blast radius (`sf/src`, `examples/z98`, `docs/sf/manuals/src`, `repro`, retired `examples/zig0`); fixtures `repro/mi_matrix/alias_value_reject_xmod` + `repro/alias_value_reject.z98`; verification plan.
- [ ] Report `task-A5-I-report.md`; no `sf/src` edits; no commit.

### Task A5-F: implement
- [ ] Implement the minimal reject; add fixture + standalone; run the QUICK_REF gate battery verbatim (**STOP on unexpected movement**); update tech docs + QUICK_REF + EXPECTED_FAIL; record the moved fixed point; commit the fix.
- [ ] Reword `docs/sf/manuals/en/vol4-11-aliases.html`: F1 value-position row now documents the clean reject; F2 header ("every type form is a legal alias target") corrected; F3 authority naming (`const_alias_prepass.zig` unwired) corrected.
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence:** A5 runs after Task 16 (commit `5db52869`) and before Task 17.

## Amendment A6 — assignment must not be an expression (operator-ruled m1570)

**Origin:** found while probing Volume IV page 12 (`statements`); Task-17 review (F1). Operator ruling (m1570 option 1): make Z98 reject assignment-as-expression at the statement/initializer/return positions, matching Zig.

**Defect (reviewer-verified, base fp `821481e69df63fc0cf69176fdaaf9dd9`).** The compiler accepts an assignment where an expression is expected, in three positions:
```zig
a = b = 2;              // rc 0; a == b == 2
var b: i32 = a = 3;     // rc 0; a == 3, b == 3
return a = 3;           // rc 0
```
Zig 0.15.2 rejects each (`error: expected ';' after statement`). Conditions (`if (a = 3)`) and parenthesized init (`var b = (a = 3);`) already reject (Task 9B: `parser.zig:942-944`, `parser.zig:723-725`), but the expression-statement path (`parserParseExprStmt`, `sf/src/parser.zig:1560-1566`), the var-initializer path, and the return path still parse at `Prec.assignment`, and `getInfixInfo` (`sf/src/parser.zig:2218-2225`) makes `=` right-associative.

### Task A6-I: read-only investigation — DONE
- [x] DONE (report `task-A6-I-report.md`). Base fp `821481e6…` accepts `a = b = 2;`, `var b: i32 = a = 3;`, `return a = 3;` (rc 0); Zig 0.15.2 rejects all three. Root cause: the expression-statement path (`parserParseExprStmt`, `sf/src/parser.zig:1566`) parses at `Prec.assignment` (=1) and the var-init (`:1619`) and return (`:1990`) paths parse at `Prec.none` (both too low); conditions/parens already parse at `Prec.prec_orelse` (=2). A 3-site scratch patch (statement form parses the LHS at `Prec.prec_orelse` + consumes one assignment op; `:1619`/`:1990` -> `Prec.prec_orelse`) rejects all three with `error[2000]` and moves **0** of 1093 corpus + 45 manual + 88 `examples/zig0` programs. **The 3-site patch is NOT a complete reject**: `f(a = 3);`, `arr[a = 0]`, builtin args, struct field-inits, tuple/array-literal elements, if-expr branches, switch case items/prongs and for/range bounds still parse at a too-low precedence and must be swept for the full reject.
- [x] Rulings (m1582): **Decision 1 B — full sweep** (every expression position rejects assignment-as-expression); **Decision 2 i — the fixture is a green-guard** (`error[2000]` classifies FAIL, declared in `EXPECTED_FAIL.md`'s Green-guard set like `parsergap_strict_comma_xmod`/`parsergap_selfblok_xmod`); **Decision 3 — keep the Z98 wording** (`error[2000]: expected ';' but found token`), do not chase Zig's `expected ';' after statement`.

### Task A6-M: migration (find and perform migrations first)
- [ ] Inventory every expression position still parsing assignment at a too-low precedence (A6-I residual list: call arg `parser.zig:550`, index `:520/528`, builtin arg `:767`, struct field-init `:602`, tuple element `:887`, array-literal element `:920`, if-expr branches `:964/968`, switch items/prongs `:1026/1031/1035/1081`, for/range bounds `:1912/1925/1932`, field default `:2113`, body expressions `:1406/1820/1833/1889/1968`) and confirm each against a fresh grep; classify (must reject / legitimate statement form).
- [ ] Find and migrate any in-tree program relying on an accepted assignment-expression (corpus, `examples/z98`, `docs/sf/manuals/src/**`, `repro/**`, retired `examples/zig0/**`); perform the migrations where needed and record the census.
- [ ] Report `task-A6-M-report.md`; no `sf/src` edits; no commit.

### Task A6-F: implement the full reject (split per reject family if they differ)
- [ ] Implement the full sweep (all positions A6-M inventories) so assignment-as-expression clean-rejects with the Z98 wording; add the green-guard fixture `repro/mi_matrix/assignment_expr_reject_xmod` + standalone `repro/assignment_expr_reject.z98`; run the QUICK_REF gate battery verbatim (**STOP on unexpected movement**); update tech docs + QUICK_REF + EXPECTED_FAIL; record the moved fixed point; commit the fix. Split into separate F tasks (F1, F2, …) with their own fixtures/gates if the reject families diverge materially.
- [ ] Reword `docs/sf/manuals/en/vol4-12-statements.html`: the "assignment is not an expression" claim now holds; correct the `:107` right-associativity wording and the report F2/F3 notes.
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence (m1582 deferral):** A6 is deferred to the **end of the volume** so the manual writing continues first. Task A6-I is DONE; run **A6-M (migration)** then **A6-F (implement, split per reject family)** **after all page tasks (through Task 25) and before Task 26 closeout**. The manual pages (including Task 17's page 12) write the **assumed final behavior** (assignment is not an expression); the current compiler acceptance is a collected defect for the after-manual/before-next-volume work.

## Amendment A7 — `if` capture must not be visible in the `else` arm (operator-ruled m1596)

**Origin:** found while probing Volume IV page 13 (`control-flow`); Task-18 review F1. Operator ruling (m1596 option 1): make the capture scope local to the then-arm so an `else`-arm use rejects cleanly; **deferred to the end of the volume, after A6-F**, because it is an edge case (not self-hosting-blocking, not delivery-blocking).

**Defect (reviewer-verified, base fp `821481e69df63fc0cf69176fdaaf9dd9`).** An `if`/`while` capture stays in scope in the `else` arm; Z98 accepts the program (rc 0, no diagnostic) and the `else` arm reads uninitialized storage (varies per run):
```zig
if (opt) |v| { use(v); } else { use(v); }   // rc 0; else reads garbage
```
Zig 0.15.2 rejects (`use of undeclared identifier 'v'`) — the capture is scoped to the then-arm only. Page 13 documents the boundary (`vol4-13-control-flow.html:424`, `:883-884`) and ships a non-reproducible measured garbage value (Task-18 review F2).

### Task A7-I: read-only investigation
- [ ] Reproduce at fp `821481e6…` for `if` and `while` captures (then-arm payload, else-arm use); confirm the Zig rejection.
- [ ] Root-cause in `sf/src/semantic_analyzer.zig` / `sf/src/lower.zig`: where the capture local is registered and why it stays in scope for the else arm; specify the minimal fix (register the capture in a scope closed at the end of the then-arm so the else-arm use becomes `error[20] undeclared` like Zig, or a clean level-0 code).
- [ ] Blast radius (`sf/src`, corpus, `examples/z98`, `docs/sf/manuals/src/**`, `repro/**`, `examples/zig0/**`); fixtures `repro/mi_matrix/if_capture_else_reject_xmod` + standalone; verification plan (Zig oracle, corpus classify join-diff, 4-MD5, stdlib, example matrix, self-emission).
- [ ] Report `task-A7-I-report.md`; no `sf/src` edits; no commit.

### Task A7-M: migration (only if A7-I finds in-tree reliance)
- [ ] Find/migrate any program relying on an else-arm capture; record the census; report `task-A7-M-report.md`; no `sf/src` edits; no commit.

### Task A7-F: implement
- [ ] Implement the minimal capture-scope fix; add fixture + standalone; run the QUICK_REF gate battery verbatim (**STOP on unexpected movement**); update tech docs + QUICK_REF + EXPECTED_FAIL; record the moved fixed point; commit.
- [ ] Reword `docs/sf/manuals/en/vol4-13-control-flow.html`: the capture is scoped to the then-arm, an else-arm use now rejects, and drop the non-reproducible garbage value.
- [ ] Seed rotation stays closeout-only (Task 26).

**Sequence (m1596 deferral):** A7 follows A6 at the **end of the volume** — run **A7-I → (A7-M if needed) → A7-F after A6-F and before Task 26 closeout**. Page 13's capture-scope reword is assigned to A7-F; the current acceptance is a collected edge-case defect.
