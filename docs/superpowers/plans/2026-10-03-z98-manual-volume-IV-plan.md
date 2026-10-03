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
