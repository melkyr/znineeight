# Z98 Manual — Volume V (HOWTO) Design

**Status:** Implemented (2026-10-05; Task 25 closeout — whole-set review, all 24 pages shipped, gates green, seed **not** rotated)

**Blueprint:** `docs/sf/manuals/manuals_blueprint.txt` Part 6 (lines 237–266)
**Program spec:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (binding for every volume)
**Prior volume (register/mechanics):** `docs/superpowers/specs/2026-10-03-z98-manual-volume-IV-design.md`
**Plan (to be written):** `docs/superpowers/plans/2026-10-05-z98-manual-volume-V-plan.md`

## 1. Purpose and audience

Volume V is the **task-oriented** companion to the Volume IV Reference: a set of
short, step-by-step **HOWTO guides** that take a reader who already has Volume
II fluency and show them how to *get a concrete job done* with Z98 — build the
compiler, build a program, target an OS, use the arena, model errors, drive a
coroutine, read the diagnostics, port an existing file, package for a diskette,
and contribute.

The Reference answers "what is X"; Volume V answers "how do I do X". Each guide
is a numbered procedure with exact commands and a **Verify it worked** step, and
it links back to the Reference for the underlying rules. It is not a tutorial:
it assumes the reader can read Z98 and points at Volume II/IV rather than
re-teaching the language.

## 2. Guide index (24 pages)

All guides are English HTML under `docs/sf/manuals/en/`. The index page
`vol5-00-index.html` lists every guide A–Z and grouped by theme.

| Page file | Guide | Task |
|---|---|---|
| `vol5-00-index.html` | Index — A–Z, grouped by theme | 1 |
| `vol5-01-build-compiler.html` | Rebuild `zig1` from seed | 2 |
| `vol5-02-build-single.html` | One `.z98` to an executable | 3 |
| `vol5-03-build-multi.html` | Multiple modules | 4 |
| `vol5-06-arena.html` | Correct arena use, dual-arena | 5 |
| `vol5-07-errors.html` | Model and propagate errors | 6 |
| `vol5-08-coroutines.html` | Write and drive a coroutine | 7 |
| `vol5-09-files.html` | Read, write, exists | 8 |
| `vol5-11-c-interop.html` | `extern fn`, `@cInclude` | 9 |
| `vol5-12-c89-interop.html` | Link Z98 output against C89 libraries | 10 |
| `vol5-16-port-from-c.html` | Translate a C file, idiom by idiom | 11 |
| `vol5-17-port-from-cpp.html` | Translate a C++98 file, honestly | 12 |
| `vol5-18-port-from-python.html` | For readers from a modern dynamic language | 13 |
| `vol5-04-target-win9x.html` | Win9x `.exe` | 14 |
| `vol5-05-target-linux.html` | Linux ELF | 15 |
| `vol5-10-sockets.html` | WinSock under Z98 | 16 |
| `vol5-13-debugger.html` | gdb on the generated C | 17 |
| `vol5-14-markers.html` | `--markers`, `pal.markerWrite*` | 18 |
| `vol5-15-diagnostics.html` | Reading the `error[N]` codes | 19 |
| `vol5-19-pack-for-diskette.html` | Build the floppy distribution | 20 |
| `vol5-20-build-multilingual.html` | Produce one language's manual | 21 |
| `vol5-21-static-site.html` | The doc generator itself | 22 |
| `vol5-22-contribute.html` | Repo layout, patches | 23 |
| `vol5-23-report-bug.html` | What to include, how to reduce | 24 |

The task numbers encode the **foundational-first authoring order** (§8): build
and run first, then language practices, then interop/porting, then targets, then
tooling, then distribution/meta.

## 3. Guide shape and tone

Each guide page:

1. **h1** title and a one-line goal ("This guide builds a single-file Z98
   program into a native executable.").
2. **Prerequisites** — the compiler/seed, an OS target, and any prior guide.
3. **Numbered steps** — each step has the exact command(s) and a one-line
   explanation. Commands must be reproducible verbatim on the host or, for a
   Win9x step, through the committed `scripts/win32_cross/` harness.
4. **Verify it worked** — the real captured output (reused measured transcript),
   so the reader can compare.
5. **Common mistakes** — only where the guide ships code; the concrete reject or
   wrong output and the fix.
6. **Where to go next** — the adjacent guide and the Volume IV Reference pages
   that carry the rules.

Tone is neutral and task-focused. Volume II/III own the honesty framing; a guide
states a limitation only when a step depends on it, with its workaround.

## 4. Sources of record and the reuse-first rule (binding)

The how-to corpus already exists: `repro/mi_matrix/**` fixtures with their
goldens, `examples/z98/**`, shipped `docs/sf/manuals/src/vol1/**`,
`.../src/vol2/**`, `.../src/vol3/**`, and the repo scripts. Volume V **reuses**
that material rather than re-creating it:

- Every guide step is mapped in Task 0 to an existing fixture, example, script,
  or shipped sample. The guide cites the existing artifact and its measured
  output.
- **New code is created only when Task 0 finds nothing reuseable.** New samples,
  if any, live under `docs/sf/manuals/src/vol5/`.
- **No re-testing of existing green artifacts** unless the step is suspicious or
  contradicts the recorded result. Reuse their already-measured transcripts.
- No arbitrary "slop" examples: a guide never introduces a program purely to have
  a program when an existing fixture demonstrates the same thing.

## 5. Blueprint-vs-reality corrections

The manual documents the current compiler and the real toolchain. Where the
blueprint is stale, the guide states the measured reality (the same pattern as
Volumes III/IV):

- **`vol5-13-debugger`** — `.z98dbg` does not exist; the guide is **gdb on the
  generated C** only (blueprint column corrected in the spec index).
- **`vol5-21-static-site`** — the real pipeline is `check.sh` for the gate and
  `/tmp/z98_build_tmp.sh` for the search index; `build.sh`/`serve.sh` are not
  runnable on this host (the `rm -rf dist` hang), which the guide states.
- **`vol5-20-build-multilingual`** — describes producing one language's manual
  from the existing page template; translations (`es/`, `zh-cn/`) are out of
  scope and marked `(planned)`.
- **`vol5-19-pack-for-diskette`** — a documented tar/zip diskette-image recipe
  (`dist/` stays gitignored; no image is committed).
- **`vol5-22-contribute` / `vol5-23-report-bug`** — repo layout and the
  reproduce/minimise workflow as actually present.

Any further blueprint-vs-reality gaps Task 0 finds are corrected inline in the
guide or recorded as an open item.

## 6. Compiler amendments (scoped exception)

A guide that cannot be written truthfully because of a real compiler defect
triggers a **STOP**: report the minimal reproduction; do not fix `sf/src`, do not
document around it, do not re-scope the guide. The operator rules; the fix enters
the plan as a scoped **I/F amendment** (Task Na read-only + Task Nb fix with a
`repro/mi_matrix/` fixture, a standalone `repro/` program, the QUICK_REF gate
battery verbatim, tech-doc updates, a two-hop closure with the moved fixed point
recorded, and a commit). Only amendment tasks may touch `sf/src`, `scripts/`,
`repro/`, or `release/seed/`.

**Seed rotation is closeout-only:** the seed is rotated once at the closeout task
iff an amendment moved the fixed point.

## 7. Verification

- Every command and transcript a guide ships is reproduced from the seed-built
  compiler **or** reused from an existing measured artifact (reuse-first rule,
  §4). Win9x commands are verified through the committed `scripts/win32_cross/`
  harness (mingw cross-compile + 32-bit wine + LF-normalized parity); the emitted
  OpenWatcom `build_owc.bat`/`wcc386` path is emitted-only on this host.
- `bash docs/sf/manuals/check.sh` is green after each task.
- The search index is regenerated with `/tmp/z98_build_tmp.sh` and must
  byte-match `en/search-data.js`.
- `docs/sf/manuals/build.sh` is **never run** and `dist/` is never touched.

## 8. Task sequence

| Task | Guide(s) |
|---|---|
| 0 | Read-only **coverage inventory** (not a re-test): map each guide's steps to existing fixtures/examples/scripts; classify reuse / net-new / park; predict compiler I/F pairs |
| 1 | Index |
| 2–4 | Build and run: rebuild compiler, build single, build multi |
| 5–8 | Language practices: arena, errors, coroutines, files |
| 9–13 | Interop and porting: c-interop, c89-interop, port-from-c, port-from-cpp, port-from-python |
| 14–16 | Targets: Win9x, Linux, sockets |
| 17–19 | Tooling: debugger, markers, diagnostics |
| 20–24 | Distribution and meta: diskette, multilingual, static site, contribute, report-bug |
| 25 | Whole-set closeout: gates, nav continuity, no stale `(planned)`, figure audit, spec status, seed rotation iff moved, final commit |

Each guide task ends with a website-only commit
`docs(manual): add Volume V guide NN — <title>`; only amendment tasks may touch
the compiler.

## 9. Task 0 open items

- For each guide, the exact existing artifacts that satisfy its steps, and any
  genuinely uncovered step that needs new material.
- The precise `examples/z98`, `repro/mi_matrix`, `src/vol1-3`, and script
  inventory per guide (the "what is left" question).
- Any remaining blueprint-vs-reality gap beyond §5.
- Predicted compiler I/F pairs (highest risk first).
- Figure numbering baseline (Volume IV used 1–38; Win9x screenshots for
  `vol5-04`/`vol5-10`/`vol5-19` would start at 39) — confirmed at Task 0.

## 10. Scope exclusions

Translations (`es/`, `zh-cn/`), committed `dist/` artifacts, Volume IV/VI
authoring, and any re-authoring of shipped Volumes I–IV.

## 11. Index

This spec and its plan are registered in the program spec §12. Volume V is the
penultimate volume; Volume VI (Internals) remains planned.

## 12. Conventions

- Website-only files under `docs/sf/manuals/**` except this spec and the plan.
- HTML 4.0 Transitional in the HTML 3.2/4.0 intersection; no `<div>`, no HTML5
  structural tags; ISO-8859-1; CSS1 external only; one `doc.js` ≤ 2048 bytes.
- Navigation: a 25-row sidebar on every `vol5-*` page (index + 23 guides),
  `rel`/footer nearest-shipped; the final page's `next` is `toc.html` until
  Volume VI exists.
- Cross-references link only existing files; planned targets are prose
  `(planned)`.
- Edits via `edit`/`fastedit`; every binary under `timeout 120`.

## §13 Closeout (Task 25, 2026-10-05)

Volume V is complete: all **24 pages** (`vol5-00-index.html` plus guides 01–23)
shipped and verified. Task 25 re-verified the whole set against the unmoved
compiler fixed point and swept navigation, figures, and gates.

- **Sidebar/index (binding operator ruling: 24 entries).** Every `vol5-*` page
  carries a **24-entry** sidebar (the index plus the 23 guides); on a guide page
  the current row is bold text and the other 23 are links, on the index page all
  24 are links. The plan's Task 25 step-2 text ("25 rows") and spec §12
  ("25-row sidebar … index + 23 guides") are a known arithmetic defect — 1 index
  + 23 guides is **24**, and the operator ruled 24. No 25th row exists or was
  created. `toc.html` and `vol5-00-index.html` link every shipped guide.
- **Navigation continuity.** The `rel` chain is continuous
  `toc.html → vol5-00-index → vol5-01 → … → vol5-23 → toc.html`, and the
  prev/contents/next footers match. No stale `(planned)` remains for any Volume V
  guide: the cross-volume references in Volumes II/III and the site
  `index.html`/`readme.html`/`search.html` volume lists (which still called the
  HOWTO planned) were repointed at the shipped pages; the only `(planned)` left
  under Volume V prose names translations (`es/`, `zh-cn/`) and the Volume VI
  Internals volume, both genuinely unshipped.
- **Figures.** Figures **39** (`vol5-04`), **40** (`vol5-10`), and **41**
  (`vol5-19`) are the three Win9x screenshot placeholders, 1:1 with the
  `todo-figures-list.html` rows; `check.py` figure check green.
- **Gates.** `bash docs/sf/manuals/check.sh` green (112 HTML pages); the search
  index regenerated by `/tmp/z98_build_tmp.sh` byte-matches `en/search-data.js`
  (`md5 6cb6e27a6948a63f512f76019bc9abd3`) across two runs (idempotent). The
  fixture batteries backing the guides re-ran on the seed-built compiler:
  `scripts/closeout/verify_upgraded.sh` CLOSEOUT OK (A–C all PASS, stdlib
  **266/266**), `scripts/check_emit_support.sh` 7/7 byte-identical. `build.sh`,
  `serve.sh`, and `dist/` were never touched.
- **Seed NOT rotated (no amendment).** Volume V contained **no operator-ruled
  I/F compiler amendment** — no commit after the first Volume V page touched
  `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**`. The self-emission
  fixed point is therefore unmoved at `0b8c3e4ac0b1fc49c0bdf8caf9d39945` (seed
  **v91**, archive md5 `39669954c928df59263e5d03cbaacd1d`); the rebuilt
  `/tmp/manual_seed/zig1_5_clean` hashes to that fixed point and the two-hop
  closure gate passes. Per the closeout-only rotation rule, step 6 is a **no-op**:
  the seed was **not** rotated (`archive_seed.sh` not run; `release/seed/**`
  unchanged); v91 remains current.
