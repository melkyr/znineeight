# Z98 Manual — Volume II (Learning Z98) — Design

> **Status:** Draft for operator review, 2026-09-25. Binding for the Volume II
> plan (`docs/superpowers/plans/2026-09-25-z98-manual-volume-II-plan.md`) once
> approved. Program-level spec: `2026-09-20-z98-manual-phase0-design.md`
> (binding; this document does not restate its HTML/CSS/JS/asset rules — it
> cites them). Blueprint: `docs/sf/manuals/manuals_blueprint.txt` Part 4.

**Goal:** Author all 21 chapters of Volume II (Learning Z98), English, into the
Phase 0 website under `docs/sf/manuals/`, each chapter carrying a runnable
example program (where the blueprint gives one), a "Common mistakes" list, and
cross-references to the Reference and HOWTO volumes — every example compiled
and run against the seed-built compiler, every claim verified.

**Audience:** someone who already programs in *some* language and needs to
learn Z98 specifically. Entry state: programs in some language. Exit state:
fluent in Z98 syntax and idioms (blueprint Part 1).

## §1 Scope

**In scope:**

- 21 English pages (chapters 0–20), flat in `docs/sf/manuals/en/`:
  - expand the two existing pages, `vol2-00-title.html` (chapter 0) and
    `vol2-12-error-unions.html` (chapter 12), to the full chapter shape;
  - create the other 19 pages.
- 16 new example programs in `docs/sf/manuals/src/vol2/` (chapter 12 reuses the
  existing `error_unions.z98`), plus any helper modules an example needs.
- Navigation wiring: sidebar entries, `rel` links, `toc.html`,
  `en/vol2-00-title.html`, `en/index.html`, `search.html`/`search-data.js`
  (generated), and figures.
- One Win9x screenshot placeholder per chapter that ships a runnable program,
  with its `todo-figures-list.html` row (Phase 0 §7).
- The read-only Task 0 capability inventory (see §8) and, if a defect is found
  while verifying a claim, operator-ruled scoped compiler I/F amendments (§7).

**Out of scope:** translations (`es/`, `zh-cn/`), `dist/` builds and
diskette/CD packaging, Volumes I/III/IV/V/VI content (link targets only),
site-wide redesign, generator programs, and any change to the Phase 0
infrastructure (template, CSS, `doc.js`, `check.py`) unless an operator ruling
requires one.

## §2 Chapter contracts

The blueprint (Part 4, lines 135–165) is the authoring authority. The table
below fixes the page filename, sample program, authoring order, and the
chapter's "Must cover" list for this volume. Where a blueprint item cannot be
verified against the current compiler (Task 0 inventory, §8), the chapter
task STOPs and the operator rules (§5, §7) — the page never documents a
behavior the compiler does not have.

### 2.1 Page and sample index

| # | Chapter | Page file | Sample | Task |
|---|---|---|---|---|
| 0 | Title and how to read this | `vol2-00-title.html` (expand) | — | 4 |
| 1 | The honest comparison | `vol2-01-honest-comparison.html` | — | 5 |
| 2 | The type system | `vol2-02-types.html` | `types2.z98` | 6 |
| 3 | Pointers | `vol2-03-pointers.html` | `pointers.z98` | 7 |
| 4 | Aggregates I: structs | `vol2-04-structs.html` | `shapes.z98` | 8 |
| 5 | Aggregates II: packed structs | `vol2-05-packed-structs.html` | `wire.z98` | 9 |
| 6 | Aggregates III: enums | `vol2-06-enums.html` | `color.z98` | 10 |
| 7 | Aggregates IV: unions | `vol2-07-unions.html` | `variant.z98` | 11 |
| 8 | Aggregates V: tuples | `vol2-08-tuples.html` | `pair.z98` | 12 |
| 9 | Arrays and slices | `vol2-09-arrays-slices.html` | `strings.z98` | 13 |
| 10 | Control flow, in full | `vol2-10-control-flow.html` | `control.z98` | 14 |
| 11 | `defer` and `errdefer` | `vol2-11-defer.html` | `defer.z98` | 15 |
| 12 | Error unions — the first big shift | `vol2-12-error-unions.html` (expand) | `error_unions.z98` (existing) | 1 |
| 13 | Optionals | `vol2-13-optionals.html` | `lookup.z98` | 16 |
| 14 | The arena — the second big shift | `vol2-14-arena.html` | `arena.z98` | 2 |
| 15 | Builtins, in full | `vol2-15-builtins.html` | `builtins.z98` | 3 |
| 16 | No methods, no generics, no `comptime` | `vol2-16-no-methods.html` | `shapes2.z98` | 17 |
| 17 | The standard library tour | `vol2-17-stdlib.html` | `stdio.z98` | 18 |
| 18 | `print` and the format string | `vol2-18-print.html` | `print.z98` | 19 |
| 19 | Idioms and best practices | `vol2-19-idioms.html` | — | 20 |
| 20 | What you've learned, what's next | `vol2-20-whats-next.html` | — | 21 |

**Sample-name deviation (recorded):** chapter 12 keeps the existing
`error_unions.z98`; the blueprint's `divide.z98` name is dropped (Phase 0 §9
already shipped the sample under the existing name). All other samples use the
blueprint Part 4 names.

### 2.2 Must cover

Each chapter task reads its entry here verbatim and verifies every claim
against `docs/reference/Language_Spec_Z98.md` and the compiler source.

- **0 — Title and how to read this.** Volume II assumes you program; if you
  do not, read Volume I first. Entry/exit states; how the volume is built
  (chapter shape, callouts, `src/vol2/` examples, the seed compiler recipe);
  reading paths (blueprint Part 1). No sample.
- **1 — The honest comparison.** Z98 vs C89 vs C++98 vs modern Zig vs modern
  C: what each gives you. What Z98 gives you that C89 does not (error unions,
  coroutines, arena, comptime-introspection builtins) and what it does not
  (generics, templates, classes, exceptions, threads). The framing: Z98 is a
  *higher-level C89*, not a *smaller modern Zig*. The comparison statements
  about other languages are era framing, marked as such; every Z98 claim is
  spec-verified. At least one honesty callout. No sample.
- **2 — The type system.** Primitives; arbitrary widths `u1`..`u64`;
  `isize`/`usize`; `bool`, `void`, `noreturn`, `c_char`. The width rule
  (`@sizeOf` = carrier, `@bitSizeOf` = declared width). No implicit coercions
  between `i32` and `usize`. Sample `types2.z98`.
- **3 — Pointers.** `*T`, `*const T`, `*volatile T`, `[*]T`, `**T`; `&`, `.*`;
  `ptr[i]` only on many-item pointers; `ptr.field` auto-deref; `const` is
  frontend-only; `volatile` is preserved; the pointer builtins (exact Z98
  names verified in Task 0: `@ptrCast`, `@intFromPtr`/`@ptrFromInt`,
  `@bitCast`, `@volatileCast`). Sample `pointers.z98`.
- **4 — Aggregates I: structs.** `struct`, field order and layout, `@offsetOf`,
  `@sizeOf`, `@alignOf`; nested structs. Sample `shapes.z98`.
- **5 — Aggregates II: packed structs.** `packed struct`, LSB-first packing,
  the 31-bit field cap, `@bitOffsetOf`, `@bitSizeOf`; when you actually want
  this (hardware registers, wire formats). Sample `wire.z98`.
- **6 — Aggregates III: enums.** `enum`, `enum(uN)`, `@intToEnum`/
  `@enumToInt` (exact names verified in Task 0), enum ranges in `switch`.
  Sample `color.z98`.
- **7 — Aggregates IV: unions.** Bare unions, packed unions, tagged unions,
  naked tags, anonymous struct payloads; when each is right. Sample
  `variant.z98`.
- **8 — Aggregates V: tuples.** `struct { T1, T2 }`, `.{a, b}`, `t.0`, `t.1`;
  why they exist (print, grouped returns) and why you should not use them for
  anything else. Sample `pair.z98`.
- **9 — Arrays and slices.** `[N]T`, `[]T`, `[]const T`, `.ptr`, `.len`,
  slicing `arr[a..b]`, `arr[a..]`, the coercion rules, const propagation.
  Sample `strings.z98`.
- **10 — Control flow, in full.** `if`, `if` expressions, optional capture
  `if (x) |v|`, `while` with continue-expression, `while (opt) |v|`, `for`
  with index capture, `switch` with inclusive and exclusive ranges, the
  mandatory `else` prong, labeled loops, labeled blocks (value-less only).
  Sample `control.z98`.
- **11 — `defer` and `errdefer`.** LIFO ordering, runs on all paths,
  `break`/`continue`/`return` forbidden inside, the difference between the
  two. Sample `defer.z98`.
- **12 — Error unions — the first big shift.** `error{Foo, Bar}`, `!T`, `E!T`,
  `try`, `catch |err|`, `errdefer`, `error.Tag`; why this replaces `-1`
  returns; why `orelse` is rejected (it is for optionals); why `anyerror` does
  not exist; the "you will reach for `errno` and `goto cleanup`; here is the
  Z98 way" paragraph. Expand the existing page to the full chapter shape (add
  "Common mistakes", "Where to go next", figure rows; keep and re-verify the
  example and every diagnostic quoted). Sample `error_unions.z98` (existing).
- **13 — Optionals.** `?T`, `null`, `orelse`, `if (opt) |v|`,
  `while (opt) |v|`; why `?*T` has the same struct representation; the "you
  will reach for a sentinel pointer; here is the Z98 way" paragraph. Sample
  `lookup.z98`.
- **14 — The arena — the second big shift.** Why there is no `malloc` and no
  `free`; `std.arena.init`, `std.arena.alloc`, `std.arena.reset` (exact API
  verified in Task 0); `ArenaError![*]u8` and why you use `try`/`catch`, never
  `orelse`; the dual-arena pattern; the "you will reach for `malloc`; here is
  the Z98 way" paragraph. This is the chapter C programmers get wrong most
  often. Sample `arena.z98`.
- **15 — Builtins, in full.** Every builtin from §4 of the Language Spec,
  grouped: cast/conversion, introspection, runtime, C varargs, async,
  declarations, print; one example each; the rule that unknown builtins are
  `error[3000]`. The engine of the sample is the Task 0 inventory list; if
  "one example each" cannot fit the chapter length, the inventory proposes the
  grouping and the operator rules. Sample `builtins.z98`.
- **16 — No methods, no generics, no `comptime`.** What that means in
  practice; manual vtables (`struct { fn(*void) void, *void }`); the
  init-function pattern; why `comptime` is replaced by the specific builtins.
  Sample `shapes2.z98`.
- **17 — The standard library tour.** `std.io`, `std.str`, `std.mem`,
  `std.math`, `std.debug`, `std.arena`, `std.net`, `std.async` — one page
  each, not exhaustive, pointing to the Reference. The Task 0 inventory maps
  each module name to what actually ships in `sf/src/std_*.zig`; missing or
  renamed modules are corrected in the chapter (or dropped with an operator
  ruling). Sample `stdio.z98`.
- **18 — `print` and the format string.** The one variadic form; `{}`, `{d}`,
  `{x}`, `{c}`, `{s}`; tuple-literal arguments; `error[3013]` for unknown
  specifiers; the type rules the print-formatting plan fixed (what `{}` does
  and does not accept) as the current compiler implements them. Sample
  `print.z98`.
- **19 — Idioms and best practices.** Arena ownership, init functions, manual
  vtables, dual arenas, runtime initialization, why `undefined` is not zero.
  No sample.
- **20 — What you've learned, what's next.** You can write Z98; Volume III is
  where you point it at 1998 hardware. Honesty callout. No sample.

## §3 Page shape and authoring conventions

Binding, in addition to the Phase 0 spec (§6 HTML/CSS/JS/assets, §7 figures,
§8 content verification, §11 conventions):

1. **Template.** Every page copies the `en/vol4-24-html-style.html` skeleton:
   doctype, charset, `rel="home|up|prev|next"`, language bar, three-column
   table, sidebar TOC, prev/contents/next footer, `doc.js`.
2. **Chapter shape.** h1 title; 8–14 pages of prose (blueprint Part 4); at
   least one complete, runnable code example (where the index gives a sample)
   with its real captured transcript in `<pre>`; a **"Common mistakes"**
   subsection wherever the chapter has code (the idiom the reader reaches for
   from C/C++/Python/modern Zig and the Z98 way); a **"Where to go next"**
   subsection with the cross-references; one honesty callout wherever the
   chapter touches a limit, a friction point, or an era alternative. Volume II
   does not require Volume I's "Check yourself".
3. **Cross-references.** `Where to go next` links the next shipped Volume II
   chapter and the relevant shipped Reference page(s). Only files that exist
   may be `<a>`-linked. Planned targets (most of Volume IV, all of Volume V)
   are named in prose with `(planned)` and no link, so `check.sh` stays green.
   The shipped Reference pages today are `vol4-00-title.html`,
   `vol4-15-builtins.html`, and `vol4-24-html-style.html`.
4. **Navigation, non-contiguous shipping (this volume's rule).** Chapters ship
   out of order (12, 14, 15 first). On every shipped Volume II page the
   sidebar lists all 21 chapters, shipped ones as links and unshipped ones as
   plain text marked `(planned)`. `rel="prev"`/`rel="next"` and the footer
   point at the **nearest shipped page** in that direction (or the title page
   / `toc.html` at an end). Task 22 re-points every page so the final chain is
   continuous by chapter number; the last chapter's `next` remains
   `vol4-00-title.html` (Volume III has no shipped page yet), as chapter 12
   does today.
5. **Figures.** Terminal transcripts are real runs rendered in `<pre>` (not
   figures). Win9x screenshots are placeholder boxes with a matching
   `todo-figures-list.html` row, 1:1, numbered from the next free global
   figure number (16 is the last used; the next free is 17 — Task 0 confirms).
   Every chapter that ships a runnable program gets one Win9x placeholder for
   the build-and-run claim; extra figures only where a claim needs one.
6. **Language bar.** English plus the "not yet available" plain-text entries,
   exactly as the existing pages carry it.
7. **`search-data.js`** is regenerated by `build.sh`, never hand-edited.
8. **Files.** All content goes under `docs/sf/manuals/`; the only files outside
   are this spec and the plan. `dist/` stays gitignored.

## §4 Accuracy and the compiler-defect policy

- The manual documents the **current** compiler only (Phase 0 §3). Every
  syntax, builtin, diagnostic, and `std` claim is cross-checked against
  `docs/reference/Language_Spec_Z98.md` and the compiler source; every example
  is compiled with the seed-built `zig1` and `gcc -m32` and actually run; a
  `-osw`/Win9x claim is run under `wine`. A claim that cannot be reproduced is
  fixed or dropped — never shipped.
- **STOP on a real compiler defect found while verifying a claim** (Phase 0
  §9/§11): report the minimal reproduction to the operator; do not fix
  `sf/src`, do not document around the defect, do not re-scope the chapter on
  your own. Compiler correctness takes priority over the manual.
- Once the operator rules, the fix enters the plan as a scoped compiler
  amendment (§6). Only amendment tasks may touch the compiler; every other
  task leaves the fixed point and the seed untouched.

## §5 Compiler amendments (scoped exception)

An amendment is appended to the plan by **operator ruling** and has the same
shape as Volume I's (phase0 §11 Amendments 1–17):

- **Task Na (I)** — read-only investigation: reproduce, root-cause, establish
  the correct semantics (oracle = official Zig 0.15.2 for validity questions,
  the Language Spec for Z98 semantics), specify the minimal fix, the blast
  radius, and the verification plan. No `sf/src` edits, no commit.
- **Task Nb (F)** — implement the fix; regression fixture under
  `repro/mi_matrix/<name>/` (`main.zig` + `expected.txt` + `expected.rc`,
  deterministic 3x) plus a standalone `repro/<name>.z98` program; run the
  QUICK_REF gate battery verbatim (self-compile two-hop closure, example
  matrix, 4-MD5 emitted-C gates, stdlib runtime gate, corpus `-s0` sweep,
  `check_emit_support.sh`, `verify_upgraded.sh`) and **STOP on unexpected
  movement**; update the tech docs per `docs/sf/AGENTS.md` §1.1.1 and
  `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`; verify the
  two-hop closure from the committed seed and record the moved fixed point;
  commit only the intended files. The dirty 4-MD5 re-baseline is allowed only
  with an explicit operator ruling and runtime-identity evidence.

**Seed rotation is closeout-only** (operator decision 2026-09-25, matching the
comptime-int/print-formatting R2 protocol): amendment F tasks verify the
closure and record the moved fixed point; the seed is rotated **once**, at
Volume II closeout (Task 22), via
`bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`,
iff the fixed point moved.

Only amendment tasks may edit `sf/src/**`, `scripts/**`, `repro/**`, or
`release/seed/**`, or run the compiler gate battery. Every other task leaves
the compiler fixed point and the seed untouched.

## §6 Verification

Per chapter (Phase 0 §8):

1. The example lives in `docs/sf/manuals/src/vol2/`, is compiled with the
   seed-built `zig1` and `gcc -m32`, and is actually run; the captured
   transcript matches the prose byte-for-byte.
2. Every syntax/builtin claim is cross-checked against
   `docs/reference/Language_Spec_Z98.md` and, where needed, the compiler
   source.
3. `-osw`/Win9x claims are emitted with `-osw` and run under `wine`.
4. `bash docs/sf/manuals/check.sh` passes (links, `rel`, language bar,
   charset, forbidden list, figure 1:1, no-CSS baseline) and
   `bash docs/sf/manuals/build.sh` succeeds.

Task 22 (closeout) re-runs every example in `src/vol2/`, verifies every
transcript, restores the continuous navigation chain, audits the figure list
1:1, runs `check.sh`/`build.sh` to idempotence, updates this spec's status to
implemented, rotates the seed iff an amendment moved the fixed point, and
commits the whole-set review.

**Compiler under test** (Phase 0 / `docs/sf/QUICK_REF.md`):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# result: /tmp/manual_seed/zig1_5_clean + /tmp/manual_seed/lib/
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol2/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

## §7 Task sequence

| Task | Content |
|---|---|
| 0 | Read-only capability inventory: map every chapter's "Must cover" claims against the seed-v88 compiler and `docs/reference/Language_Spec_Z98.md`; inventory the known residuals from the closed comptime-int and print-formatting plans; identify the exact Z98 names for builtins the blueprint spells with modern-Zig names; map the `std_*` modules the tour chapter describes; report the next free figure number (expected 17) and the predicted compiler I/F pairs. No source changes. |
| 1 | Chapter 12 expansion (first mental shift; the Phase 0 page is the archetype but not the full shape). |
| 2 | Chapter 14 (arena; second mental shift). |
| 3 | Chapter 15 (builtins; third first-batch chapter). |
| 4–21 | Sequential fill in numeric order, skipping the shipped ones: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 16, 17, 18, 19, 20. |
| 22 | Whole-set closeout: review, verification sweep, spec status, seed rotation, final commit. |

Amendments (I/F pairs) are inserted by operator ruling when a defect is found;
they may run between any two tasks without invalidating later chapter tasks,
which re-verify their own claims.

## §8 Open items for Task 0

- Builtin-name drift: the blueprint uses modern-Zig spellings
  (`@intFromPtr`, `@ptrFromInt`, `@intToEnum`, `@enumToInt`); Z98's real names
  are the Task 0 inventory's output.
- Module drift in chapter 17 (`std.str`, `std.mem`, `std.math`, `std.debug`,
  `std.arena`, `std.net`, `std.async`).
- Chapter 15 scope ("every builtin, one example each") against the 8–14-page
  chapter length.
- Chapter 14 API (`std.arena.*`) and the `ArenaError!` shape.
- Chapter 18 behavior after the print-formatting plan (which forms are
  accepted/rejected today).
- Whether any chapter claim is already a documented residual in
  `repro/mi_matrix/EXPECTED_FAIL.md` (the page must document only verified
  behavior; a residual that blocks a "Must cover" item becomes an amendment).

## §9 Plan index

This spec is implemented by
`docs/superpowers/plans/2026-09-25-z98-manual-volume-II-plan.md`. The
program-level plan index is `2026-09-20-z98-manual-phase0-design.md` §12.
