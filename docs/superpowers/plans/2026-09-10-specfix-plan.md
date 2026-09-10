# SPECFIX — Spec Accuracy + Corpus Completeness + Emitter Minor Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/reference/Language_Spec_Z98.md` and `README.md` accurately describe the current self-hosted compiler, commit a canonical corpus-list generator that includes the 13 omitted fixtures, and clear the outstanding emitter/script minors (which moves the fixed point → N-hop + seed v8 → v9).

**Architecture:** Investigation-first. Task 1 audits the spec against the live compiler + census the corpus universe and STOP-presents; Tasks 2–3 are docs/tooling (spec rewrite, corpus generator); Task 4 changes `sf/src` (emitter minors) and therefore moves the fixed point; Task 5 is the documentation GATE + seed rotation. No new compiler features are added.

**Tech Stack:** Z98 self-hosted compiler (`sf/src`), C89 emitter, bash tooling, the committed seed model (`release/seed/`).

## Global Constraints

- **Z98-only.** No new host dependencies, no generics/`@typeInfo`/complex comptime. Edits via `edit`/`fastedit` only — never `sed`/python/bulk transforms.
- **Seed model is the only rebuild path** (zig0 RETIRED): `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`. Dump from the repo root with the RELATIVE entry `sf/src/main.zig`; `<out_dir>` fresh. Measurement compiler = N-hop-converged binary; canonical std installed at `<exe_dir>/lib`.
- **Flag-set rule (binding):** every `gcc -c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. Separate verification gate `-Wall -Wextra -O3 -fsyntax-only` (never the build command). Self-emission link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **`timeout 120` on EVERY binary execution** (the compiler can infinite-loop).
- **Gates:** golden 9/9 + matrix 21/21 run byte-identity; corpus `-s0` zero-asymmetric; 4-MD5 `gol 2cf07dea247f3bf5e2b22c9532e89dca` / `lisp f13bd982758c8433908c5b5a4e23ebb2` / `json f61bccfdc121d61844c875cf4d5cc4a8` / `mud 68eee54c948bb7c8a850f106e14a36ea` unchanged unless a task changes the stdout dump path (none should).
- **Baseline:** HEAD `8cb7c75b`, fixed point `31973114d5ac93102d7acbd548756363`, seed v8 archive `242a41f27044c7b9e377424702ebbf74`, documented corpus 428 = 412 OK/9 GREEN/7 FAIL, EXPECTED_FAIL v76.
- **Never stage** the pre-existing dirty/untracked set: `M docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `M mnemoria/log.bin`, `M mnemoria/manifest.json`, `?? .zig1_res.tmp`, `?? .zig1_side.tmp`, `?? examples/z98/json_parser_upgraded/`, `.superpowers/sdd/*` (gitignored).
- **Record process:** SDD; report `.superpowers/sdd/task-SPECFIX-report.md` (sections `## Task 1`..`## Task 5`); ledger `.superpowers/sdd/progress.md`; memory via `mnemoria --path .opencode/memory add --agent specfix-session --type <intent|discovery|decision|problem|solution|pattern|warning|success|refactor|bugfix|feature> --summary "<one-liner>" "<content>"`. Task briefs via the SDD skill's `scripts/task-brief PLAN N`; review packages via `scripts/review-package BASE HEAD`.
- **Operator rulings (binding):** Task 4 chmod = self-chmod line in the emitted `.sh`, NOT a PAL `chmod` primitive; `build_target.sh` link order = leave as-is + document; corpus work = generator + list only (no count re-baseline).

---

### Task 1 — Spec-vs-implementation audit + corpus-universe census (I, record-only)

**Files:**
- Read: `docs/reference/Language_Spec_Z98.md`, `README.md`, `docs/sf/QUICK_REF.md`, `sf/src/token.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/type_registry.zig`, `sf/src/parser.zig`, `sf/src/c89_emit.zig`, `sf/src/std*.zig`
- Write: `.superpowers/sdd/task-SPECFIX-report.md` (`## Task 1`), `.superpowers/sdd/progress.md`

**Interfaces:**
- Produces: the section-by-section stale/missing/wrong delta; the "Not yet supported" list; the exact corpus-universe rule (consumed by Task 3); the spec rewrite outline (consumed by Task 2).

- [ ] **Step 1: Audit each spec section against the compiler.** For every section of `Language_Spec_Z98.md` (1 Types, 2 Memory/Arena, 3 Control Flow, 4 Builtins, 5 Known Limitations, 6 Idioms, plus the top-level Type Coercions), record: is it stale, missing, or wrong vs the current compiler? Ground each finding in a source anchor (file:line) or a shipped module. At minimum verify: introspection/pointer builtins (`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf`/`@intFromPtr`/`@ptrFromInt`/`@fieldParentPtr`/`@bitCast`/`@as`/`@cInclude`), `export fn`/`export var` + cross-module `pub var`, arbitrary-width `uN`/`iN`, `packed struct`/`packed union`/`enum(uN)`, switch case-range lowering, the target model (`-osl`/`-osw`/`--target`/`@isWindows()`), `std_net` extern bindings, and the 8 std modules (`std` io/arena/str/mem/math/debug/net) with the real `std.arena.init/alloc/reset` API.
- [ ] **Step 2: Enumerate designed-but-unimplemented features.** List features that exist only in design/plan docs (do NOT describe them as present): `c89-ahead` `static`/`do…while`/type-alias/`volatile` (confirm absent from `sf/src/token.zig`), `@errorName`, `extern struct`/`opaque`/`vector`, generics/`anytype`/`@Type`/`@typeInfo`. This becomes the "Not yet supported" section.
- [ ] **Step 3: Census the corpus universe.** Determine the exact rule the historical `-s0` sweeps used to count "repro top-level + `mi_matrix` + `examples/z98`" (inspect `docs/sf/QUICK_REF.md`'s baseline log and which dirs carry a compilable entry such as `main.zig`; identify container dirs excluded, e.g. `slice_matrix`, and any non-`main.zig` entries). Verify the resulting set **includes all 13** omitted fixtures: `catch_ret_err_{chain,direct,if,lzw_shape,multi,nested_fn,value_ctx}`, `catch_return_err_tco`, `orelse_ret_err`, `orelse_ret_err_void`, `store_dedup_{assign,const,valueblock}_xmod`. Record the rule precisely enough to implement in bash.
- [ ] **Step 4: Write the report section + ledger line**, then **STOP-present** the delta, the rewrite outline, the "Not yet supported" list, and the corpus-universe rule. No commits, no source edits.

**Acceptance:** report `## Task 1` present with a section-by-section delta (each grounded), the unimplemented list, the 13-fixture inclusion check, and the exact universe rule; `git status --porcelain` == the pre-existing dirty set only; no commits.

---

### Task 2 — In-place rewrite of the Z98 language spec (F)

**Files:**
- Modify: `docs/reference/Language_Spec_Z98.md`
- Write: `.superpowers/sdd/task-SPECFIX-report.md` (`## Task 2`)

**Interfaces:**
- Consumes: Task 1's delta + rewrite outline + "Not yet supported" list.

- [ ] **Step 1: Rewrite the spec in place** so every section reflects only implemented behavior, following Task 1's outline. Keep the existing document structure/style (tables, `###` subsections) and the disclaimer header. Correct the arena section to the shipped `std.arena.init/alloc/reset` API and the module set. Add the missing builtins/features. Add a short **"Not yet supported"** subsection (or section) with the Task-1 unimplemented list.
- [ ] **Step 2: Verify the rewrite against Task 1's delta** — no stale claim survives; no designed-only feature is presented as present; no placeholder/TODO text.
- [ ] **Step 3: Commit** (docs-only). Message: `docs: rewrite Z98 language spec to current self-hosted feature set (SPECFIX)`.

**Acceptance:** `docs/reference/Language_Spec_Z98.md` matches the Task-1 delta; commit contains only that file.

---

### Task 3 — Canonical corpus-list generator (F)

**Files:**
- Create: `scripts/corpus/list_corpus_dirs.sh`
- Write: `.superpowers/sdd/task-SPECFIX-report.md` (`## Task 3`)

**Interfaces:**
- Consumes: Task 1's exact corpus-universe rule.
- Produces: a script printing the sorted canonical dir list on stdout (one dir per line, repo-relative, trailing slash).

- [ ] **Step 1: Implement `scripts/corpus/list_corpus_dirs.sh`** (bash; no perl/python) encoding the Task-1 universe rule. It must be deterministic (sorted), run from the repo root, and print repo-relative dir paths.
- [ ] **Step 2: Verify.** Run it; confirm the output includes all 13 omitted fixtures and reconciles with the historical sweep accounting (Task 1's rule). Counts are **not** re-baselined — this is a list generator only. Make the script executable (`chmod +x`).
- [ ] **Step 3: Commit** (tooling). Message: `feat: canonical corpus-list generator (SPECFIX)`.

**Acceptance:** `scripts/corpus/list_corpus_dirs.sh` exists, is deterministic, includes the 13 fixtures; commit contains only that file.

---

### Task 4 — Emitter + script minors (F) *(moves the fixed point)*

**Files:**
- Modify: `sf/src/c89_emit.zig` (conditional `net_prelude.h`, `openSupportOutputFile` guard, `build_target.sh` self-chmod, link-order comment)
- Possibly modify: `sf/src/main.zig` (if `emitSupportFiles` needs the reachable set threaded in)
- Modify: `scripts/check_emit_support.sh` (hello/stdio probe expects five support files)
- Modify: `scripts/win32_cross/cross_build_run.sh`, `scripts/win32_cross/cross_nocrt.sh` (comment fixes), `scripts/closeout/run_upgraded.sh` (`timeout 30`→`120`)
- Write: `.superpowers/sdd/task-SPECFIX-report.md` (`## Task 4`)

**Interfaces:**
- Consumes: the existing `scriptNetEmitted`/`moduleHasNetPrelude` predicate (Task 5 of EMITEMIT) and the reachable-module set on the emitter.

- [ ] **Step 1 (emitter): conditionally emit `net_prelude.h`.** Gate the `net_prelude.h` write in `emitSupportFiles` on the reachable set (`std_net` reachable). `std_io`/other support files stay unconditional.
- [ ] **Step 2 (emitter): long-path guard.** In `openSupportOutputFile`, compute the combined path length and abort with a diagnostic if it would truncate the `[512]u8` buffer (mirror the module-file path's behavior).
- [ ] **Step 3 (emitter): self-chmod line.** In the emitted Linux `build_target.sh` (e.g. `emitBuildTargetSh`), add `chmod +x "$0" 2>/dev/null || true` immediately after the shebang. Operator ruling: self-chmod, no PAL `chmod` primitive.
- [ ] **Step 4 (emitter): document link order.** Add a short comment at the link-order site in `emitBuildTargetSh` recording that modules-then-runtime order is intentional (differs from the seed's alphabetical `*.o` order). No behavior change.
- [ ] **Step 5 (scripts): cleanups.** Fix the "trio"→actual wording in `cross_build_run.sh`/`cross_nocrt.sh` legacy comments; raise `run_upgraded.sh` `timeout 30`→`120`.
- [ ] **Step 6 (TDD/verify): gates + N-hop.**
  - Fresh N-hop from the committed seed v8: dump + rebuild, hop1/hop2, record the new fixed point.
  - Strict `-Wall -Wextra -O3 -fsyntax-only` clean; `check_emit_support.sh` green (updated for five support files).
  - stdio `-o` dump emits **no** `net_prelude.h`; a net program emits it; `-osw` stdio links without `-lwsock32`/`net_prelude.h`.
  - Hello via `sh build_target.sh` builds+runs; the `.sh` is executable after one `sh` run.
  - Golden 9/9 + matrix 21/21; corpus `-s0` zero-asymmetric; 4-MD5 unchanged.
- [ ] **Step 7: Commit** (feature/tooling). Messages: `fix: emit net_prelude.h only when std_net is reachable (SPECFIX)` and `chore: SPECFIX emitter/script minors`.

**Acceptance:** gates green on the new fixed point; conditional `net_prelude.h` verified both ways; `check_emit_support.sh` updated and passing; fixed point recorded; commits contain only intended files.

---

### Task 5 — README + docs GATE + seed rotation v8 → v9 (F)

**Files:**
- Modify: `README.md`, `docs/sf/QUICK_REF.md` (incl. the stale Multi-Module Build recipe + link-order note + newest bullet), `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md` (bump only if a class moved)
- Rotate: `release/seed/zig1-seed.tgz` via `scripts/seed/archive_seed.sh`
- Write: `.superpowers/sdd/task-SPECFIX-report.md` (`## Task 5`)

**Interfaces:**
- Consumes: the Task-4 fixed point and gate values.

- [ ] **Step 1: Refresh `README.md`** to the current self-hosted state: new fixed point + `.c`/`.h` counts, seed v8/v9 references, current 4-MD5 rows, current corpus counts, 8-file `lib/`, `--dump-c89` as a debug alias, and the EMITEMIT user workflow (`zig1 -o DIR prog.zig` → self-contained dir → `sh build_target.sh`). Correct the stale sample hashes and `EXPECTED_FAIL v70` references.
- [ ] **Step 2: Update `docs/sf/QUICK_REF.md`** — replace the stale Multi-Module Build recipe with the self-contained-dir workflow, add the link-order note, and add a newest-first SPECFIX bullet above the current top bullet.
- [ ] **Step 3: Docs GATE + rotation.** Rotate the seed v8 → v9 via `bash scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`; update `CHANGELOG.md` provenance; bump `EXPECTED_FAIL.md` only if a fixture class moved (record otherwise). Verify post-rotation `build_from_seed.sh` closure.
- [ ] **Step 4: Full battery** on the rotated seed / final compiler: golden 9/9, matrix 21/21, corpus `-s0`, 4-MD5, `check_emit_support.sh`, staged-input runtime spot checks.
- [ ] **Step 5: Commit** (docs GATE + seed). Message: `docs: GATE — spec accuracy + corpus generator + emitter minors (SPECFIX)`.

**Acceptance:** README/QUICK_REF/CHANGELOG consistent with the new fixed point; seed v9 archive md5 + internal `zig1` md5 recorded; post-rotation closure holds; EXPECTED_FAIL bump decision recorded; commit contains only the intended files.

---

## Self-Review

- **Spec coverage:** Task 1/2 cover the spec-accuracy goal; Task 3 the corpus-completeness goal; Task 4 the emitter/script minors; Task 5 the README + GATE + rotation. The operator's four rulings are encoded in Global Constraints and in Task 4 Steps 3/4.
- **Placeholder scan:** no TBD/TODO; the only deferred specifics are the Task-1 census outputs (the intentional I-first design).
- **Type consistency:** `emitSupportFiles` / `openSupportOutputFile` / `emitBuildTargetSh` / `scriptNetEmitted` are named as they exist in `sf/src/c89_emit.zig`; Task 4 consumes Task 1–3 outputs by name.
