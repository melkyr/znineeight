# Z98 Manual — Volume IV (Reference) Design Spec

**Status:** Draft
**Program:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (binding for every volume)
**Blueprint:** `docs/sf/manuals/manuals_blueprint.txt` Part 6, Volume IV (lines 205–235)
**Plan:** `docs/superpowers/plans/2026-10-03-z98-manual-volume-IV-plan.md`
**Sequence:** PREVIOUS = Volume III (Working in the Era, complete, seed v89→v90 after Amendment A1); NEXT = the Volume V (HOWTO) plan.

## §1 Goal and audience

Volume IV is the **Reference**: a direct port of `docs/reference/Language_Spec_Z98.md`
into the Phase 0 website, restructured for **lookup** rather than linear reading.
It is not a tutorial — Volume II teaches, Volume III frames the era; Volume IV is
where a reader lands from a search or a cross-reference and needs the exact rule,
the exact signature, or the exact diagnostic.

- **Audience:** a reader who already knows Z98 (Volumes I–III) and wants one page
  per topic, precise and complete.
- **Source of record:** the current compiler (`sf/src/**`), checked against
  `docs/reference/Language_Spec_Z98.md`. The Language Spec is the *starting* text,
  but it has known stale/contradictory spots; the Reference documents **measured**
  behavior (Phase 0 §3).
- **25 pages**, per the blueprint table; three already exist (`vol4-00-title`,
  `vol4-15-builtins`, `vol4-24-html-style`) and are audited/updated, not authored
  from scratch.

## §2 Page index

| # | Task | File | Content | Source | Notes |
|---|---|---|---|---|---|
| 00 | T25 | `vol4-00-title.html` | How to use the Reference | blueprint 211 | exists → update |
| 01 | T6 | `vol4-01-grammar.html` | Full grammar, EBNF-style | `sf/src/parser.zig` + spec §1 | mechanical |
| 02 | T7 | `vol4-02-types.html` | Spec §1.1–§1.7, one page | spec §1 | |
| 03 | T8 | `vol4-03-pointers.html` | §1.2 | spec §1.2 | |
| 04 | T9 | `vol4-04-structs.html` | structs + packed structs | spec §1.3 | |
| 05 | T10 | `vol4-05-enums.html` | enums | spec §1.3 | |
| 06 | T11 | `vol4-06-unions.html` | unions, all three forms | spec §1.3 | |
| 07 | T12 | `vol4-07-tuples.html` | tuples | spec §1.3 | |
| 08 | T13 | `vol4-08-arrays-slices.html` | §1.4 | spec §1.4 | |
| 09 | T14 | `vol4-09-errors.html` | §1.5 | spec §1.5 | |
| 10 | T15 | `vol4-10-optionals.html` | §1.6 | spec §1.6 | |
| 11 | T16 | `vol4-11-aliases.html` | §1.7 | spec §1.7 | |
| 12 | T17 | `vol4-12-statements.html` | §3.1 | spec §3.1 | |
| 13 | T18 | `vol4-13-control-flow.html` | §3.2 | spec §3.2 | |
| 14 | T19 | `vol4-14-error-expressions.html` | §3.3 | spec §3.3 | |
| 15 | T23 | `vol4-15-builtins.html` | §4, alphabetical | spec §4 | exists → audit/update |
| 16 | T20 | `vol4-16-async.html` | §4.1 in full, the frame ABI | spec §4.1 + `sf/src/std_async.zig` | |
| 17 | T21 | `vol4-17-memory.html` | §2, the arena | spec §2 | |
| 18 | T5 | `vol4-18-stdlib.html` | `std.*` signatures | `sf/src/std_*.zig` + `sf/src/std.zig` | **one page, one full section per module** (operator: each module gets the room it deserves) |
| 19 | T3 | `vol4-19-pal.html` | `pal.*` signatures | `sf/src/include/zig_pal.*` | mechanical |
| 20 | T4 | `vol4-20-markers.html` | the marker table | `--markers` + `sf/src/**` | mechanical |
| 21 | T1 | `vol4-21-diagnostics.html` | the diagnostic codes, alphabetical | `sf/src/diagnostics.zig` | **printed ordinal** (`error[N]`) + `ERR_*` name; mechanical |
| 22 | T2 | `vol4-22-cli.html` | `zig1` flags | `sf/src/main.zig` | mechanical |
| 23 | T22 | `vol4-23-limits.html` | §5 and §7 verbatim, the honest list | spec §5/§7 | |
| 24 | T24 | `vol4-24-html-style.html` | Part 7 rules as a page | phase0 §6 + blueprint Part 7 | exists → audit/update |

Task numbers follow the **authoring order** (§8): big mechanical pages first.

## §3 Reference style (binding)

- **Lookup, not narrative.** Each page opens with a one-line definition, then
  tables/lists of the exact rules, signatures, and codes. No story.
- **Exactness over prose.** Signatures, fields, codes, and messages are quoted
  verbatim from source; a value nobody can reproduce is not shipped (Phase 0 §3).
- **Neutral register.** Volume IV makes no honesty arguments (Volume II/III own the
  framing). It states rules and, where a rule has a boundary, states the boundary.
- **Snippets are short and verified.** A snippet illustrates one rule. Before
  authoring a new snippet, **reuse** an existing `sf/src/tests/*`, `repro/mi_matrix/`
  program, or a Vol I–III `src/vol*/` sample that already demonstrates the rule
  (operator ruling); only compile a new snippet when nothing reusable exists.
- **No samples, no figures.** Reference pages ship no `src/vol4/` runnable programs
  and no Win9x screenshot figures. Every snippet is compiled/run during the task to
  verify its claim, but the snippet is a code block, not a chapter sample.

## §4 Page shape and site conventions

Identical to Volume III's chapter contract (`docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md` §4), with the differences below:

- **Sidebar:** all 25 Volume IV entries on every shipped `vol4-*` page (shipped =
  link, unshipped = `<i>(planned)</i>`); the current page bold (Vol II/III pattern).
- **`rel` chain:** nearest shipped in each direction; the last shipped page's `next`
  is `vol5-00-title.html` when it exists, else `toc.html`; Task 26 restores the
  continuous chain.
- **Cross-references:** may link Volume II chapters (all shipped), Volume III
  chapters (all shipped), the shipped Volume IV pages, and `docs/reference/*.md`
  targets that exist; planned volumes are prose `(planned)` with no link.
- **HTML/CSS/JS/assets/forbidden:** Phase 0 §6, unchanged (HTML 3.2/4.0
  intersection, no `<div>`/`<thead>`/`<tbody>`, ISO-8859-1, CSS1 external only,
  `doc.js` ≤ 2048 B, GIF only).
- **No "Common mistakes" / honesty callouts** on Reference pages (those are Volume
  II/III devices); a page may end with a short "See also" list of existing pages.

## §5 Accuracy and verification

- **Port means re-verify.** Every claim is checked against the current compiler and
  source, not copied from the Language Spec unexamined. Known stale spots to resolve
  during the port (Task 0 confirms the current list): the spec's §5-vs-Type-Coercions
  tension; anything the Volume III closeout already corrected (Winsock 1.1, `Socket = i32`,
  `name_mangling.md` measured form); `anytype` (rejected in signatures since Amendment
  A1; `docs/reference/Language_Spec_Z98.md:111` updated).
- **Diagnostics page (T1):** the printed number is the enum **ordinal**, not the
  `ERR_####` name — e.g. `ERR_2012_ANYTYPE_NOT_SUPPORTED` prints `error[16]`. The
  page lists every member of `sf/src/diagnostics.zig` alphabetically by name, with
  its printed `error[N]`/`warning[N]`/`info[N]` and the exact default message.
- **CLI page (T2):** flags, arguments, and defaults from `sf/src/main.zig`; the
  seed-build recipe and `-o`/`--dump-c89` behavior from `docs/sf/QUICK_REF.md`.
- **stdlib/PAL pages (T5/T3):** a section per module; signatures and error sets
  verbatim from `sf/src/std_*.zig`; the re-export set from `sf/src/std.zig`.
- **Markers page (T4):** every marker actually emitted by `--markers`, keyed to the
  phase that emits it.
- **Compiler-defect policy:** identical to Volume III §5 — STOP on a real defect,
  report the minimal repro, take an operator ruling; fixes enter as scoped I/F
  amendments only.
- **Environment deviation (binding):** `docs/sf/manuals/build.sh` HANGS at
  `rm -rf dist`; **never run `build.sh`/`serve.sh` and never touch `dist`**. Gate
  with `bash docs/sf/manuals/check.sh`; regenerate the search index with
  `/tmp/z98_build_tmp.sh` and require a byte-match to `en/search-data.js`.

## §6 Compiler amendments (scoped exception)

Same shape as Volumes II/III: an amendment is appended to the plan by **operator
ruling** as an I/F pair (read-only investigation; fix with `repro/mi_matrix/`
fixture + standalone repro + the QUICK_REF gate battery + two-hop closure recorded).
Only amendment tasks may touch `sf/src/**`, `scripts/**`, `repro/**`, or
`release/seed/**`. **Seed rotation is closeout-only** (Task 26) — the seed is
rotated once at Volume IV closeout iff an amendment moved the fixed point.

## §7 Verification

Per page task:

1. Port the topic from its source section; **reuse** existing tests/fixtures/samples
   for snippets where possible; compile/run any new snippet on the seed compiler.
2. Cross-check every signature/code/flag against `sf/src/**` (and
   `docs/reference/Language_Spec_Z98.md` where it is the authority).
3. `bash docs/sf/manuals/check.sh` passes; regenerate the search index with
   `/tmp/z98_build_tmp.sh` and confirm a byte-match.
4. Commit: `docs(manual): add Volume IV page NN — <title>` (new) or
   `docs(manual): update Volume IV page NN — <title>` (existing).

Task 26 (closeout) re-runs every snippet/claim on the seed, restores the continuous
navigation chain, confirms the 25-page toc/sidebars, audits that no sample/figure
was added, runs `check.sh` + the index idempotence check, sets this spec's status to
implemented, rotates the seed iff an amendment moved the fixed point, and commits
the whole-set review.

**Compiler under test:** seed **v90** (rotated 2026-10-03 at the Amendment A1 closeout):

```bash
FIXED_POINT_MD5=f78bebc448e267b32419afdb13afb386 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

## §8 Task sequence

| Task | Content |
|---|---|
| 0 | Read-only **delta/claim inventory**: build the port map (spec section → page); the diagnostics ordinal table; the CLI flag list; the stdlib/PAL signature inventory; the marker table; the **reuse inventory** (existing tests/`mi_matrix`/`src/vol*` material per page); the stale-spot list; figure/sample confirmation (none); predicted compiler I/F pairs. |
| 1–6 | Big mechanical pages: diagnostics, CLI, PAL, markers, stdlib (expanded per module), grammar. |
| 7–16 | Type/aggregate pages: types, pointers, structs, enums, unions, tuples, arrays-slices, errors, optionals, aliases. |
| 17–22 | Statement/error/async/memory/limits: statements, control-flow, error-expressions, async, memory, limits. |
| 23–25 | Existing-page audit/update: builtins, html-style, title. |
| 26 | Whole-set closeout: snippet re-run, nav chain, toc/sidebars, no-sample/no-figure audit, spec status, seed rotation iff moved, final commit. |

## §9 Open items for Task 0

- The exact diagnostics count and printed ordinals (`sf/src/diagnostics.zig`), and
  whether to print `ERR_*` names in parentheses (operator ruling: yes).
- The full `std.*` re-export set and each module's public surface + error sets.
- The `pal.*` surface (`sf/src/include/zig_pal.*` / `pal.zig`) and which functions
  the reference should document (the user-facing PAL subset vs every symbol).
- Every `--markers` marker actually emitted and its phase.
- The CLI flag set and defaults from `sf/src/main.zig`.
- The grammar: whether to port the spec's EBNF or transcribe `sf/src/parser.zig`
  rules (Task 0 proposes; parser is authoritative).
- The per-page reuse inventory (which existing fixture/test/sample supplies each
  snippet), so no new snippet is authored where a verified one exists.

## §10 Plan index

This spec is implemented by `docs/superpowers/plans/2026-10-03-z98-manual-volume-IV-plan.md`
(one plan, Task 0 + 25 page tasks + Task 26 closeout). Program index update:
`docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` §12 gains the
Volume III-complete/seed-v90 and Volume IV spec/plan entries.
