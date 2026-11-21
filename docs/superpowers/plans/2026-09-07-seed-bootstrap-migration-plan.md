# Seed-Model Migration — Committed zig1 Bootstrap Seed + Self-Host Working Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the committed, rotating bootstrap-seed working model so zig1 can always be rebuilt from source with only `gcc` — independent of the frozen zig0 front end. Capture seed v0 (zig0-built reference `3707d33b` + its self-emission C at HEAD `1079d90a`), add the build/archive scripts, parametrize the self_compile scripts on a seed path, and update AGENTS.md / QUICK_REF.md / plan conventions with the seed model + bootstrap-staging constraint. Infra/docs only — zero `sf/src` change, all gates byte-identical.

**Architecture:** a committed, git-tracked rotating archive `release/seed/zig1-seed.tgz` (NOT the git-ignored `release/staging/`) containing the seed binary + its self-emission C89 (41 `.c` + 42 `.h`) + runtime/link sources + std `lib/` + a `SEED_README.txt` with the verbatim rebuild recipes. Rotation happens only at plan closeout; provenance is tracked in `release/seed/CHANGELOG.md` (one entry per rotation, newest first). zig0 stays in-tree and active (`build_release.sh` untouched). The bootstrap-staging constraint (new-feature compiler code must be written in constructs the current seed already understands; sf/src may only adopt new syntax after a new fixed point exists) becomes binding in AGENTS.md and every future plan's Global Constraints.

Design spec: `docs/superpowers/specs/2026-09-07-seed-bootstrap-migration-design.md` (operator-approved).

## Global Constraints

- zig0 stays in-tree and ACTIVE for current compiler cycles: `sf/scripts/build_release.sh` is NOT modified by this plan (its g++→zig0→gen-0→gcc path remains the reference builder). No removal of `src/bootstrap`, `README_zig0_bootstrap.md`, `docs/Building.md`, or zig0 oracle references.
- Seed = committed under `release/seed/` (git-tracked). `release/staging/` remains git-ignored and is untouched. Rotating canonical file `release/seed/zig1-seed.tgz`; prior seeds recoverable in git history.
- Seed binary = the zig0-built reference (`3707d33b` at capture); packed C = its self-emission set (41 `.c` + 42 `.h`). Rotation tracking = `release/seed/CHANGELOG.md` (NOT the release-versioned root `CHANGELOG.md`).
- Gates stay byte-identical UNLESS a change legitimately alters them (existing operator-ruled re-baseline rule — no new policy). This infra/docs migration MUST be byte-neutral: 4-MD5 (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`), golden 9/9, matrix 21/21, corpus 433-dir `-s0`, self-compile fixed point `24da89b9d6398ff24f4baecfe2e23f77` (two-hop, 41 `.c`, 0 `error[`, 0 PANIC).
- Reference compiler: `/tmp/fx_subfolder/zig1` md5 `3707d33bd1d3779c4a98aab9d5be1841` (zig0-built at HEAD `1079d90a`, valid since sf/src unchanged). Canonical std lib must be reinstalled at `/tmp/fx_subfolder/lib` after any `build_release.sh`.
- Pre-existing dirty/untracked set (2026-08-26 plan doc, `mnemoria/*`, `.zig1_res.tmp`, `.zig1_side.tmp`, `examples/z98/json_parser_upgraded/`) never staged. Scratch in `/tmp` and `.superpowers/sdd/` only.
- Fastedit/edit per docs/sf/AGENTS.md X.7 (re-read region before every edit; absolute lines; edit bottom-to-top). No python/sed/bulk transforms; no `git checkout` to erase.
- Report: `.superpowers/sdd/task-SEEDMIG-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory`, agent `seedmig-session`.
- Per-task evidence contract: status, commits, per-gate md5/evidence, rebuild-recipe verification output, concerns. STOP-present on any divergence/ambiguity/plan-vs-evidence mismatch.
- Subagent-driven execution with the SDD skill (fresh implementer per task, independent reviewer, fix loops, ledger lines).

---

### Task 1: Record-only baseline + recipe census (no commit)

**Files:**
- Record only: `.superpowers/sdd/task-SEEDMIG-report.md` header + Task 1 section.

**Interfaces:**
- Produces: (a) verified baseline (HEAD `1079d90a`, reference `3707d33b`, 4-MD5 gates, fixed point `24da89b9`, EXPECTED_FAIL version, git status); (b) the authoritative rebuild-recipe set (verbatim commands for self-emission dump → gcc `-m32` → zig1_5, and the gcc-of-self-emission-C rebuild) that Task 2/3 implementers consume and Task 4 records in SEED_README.txt; (c) the exact `release/seed/` archive inventory (which headers link sources `gen/` needs, confirmed by compiling a fresh self-emission dump).

- [ ] **Step 1: Baseline.** `git rev-parse --short HEAD` (expect `1079d90a`); `md5sum /tmp/fx_subfolder/zig1` (expect `3707d33b…`; if it differs, STOP-present — do not proceed on a stale compiler); `ls /tmp/fx_subfolder/lib` (expect the 4 std `.zig`); re-run the 4-MD5 gate (repo-root CWD `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/{game_of_life,lisp_interpreter_curr,json_parser,mud_server}/main.zig | md5sum`) → record against the constraint values; confirm the fixed point `24da89b9…` via a fresh two-hop dump round-trip; record `git status --short` (pre-existing dirty set only).

- [ ] **Step 2: Authoritative recipe census.** From a FRESH dir, run the canonical self-emission build: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir <fresh>/gen sf/src/main.zig` (from repo root), `cd <fresh>/gen`, `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <repo>/sf/src/include -c *.c`, then `gcc -m32 -O0 *.o <repo>/sf/src/include/zig_runtime.c <repo>/sf/src/include/zig_pal.c <repo>/sf/src/c_exit.c -o <fresh>/zig1_5_clean`. Record rc (expect 0), `.c`/`.h` file counts (expect 41 `.c` + 42 `.h` + `zig_special_types.h`), and the produced binary md5 (expect fixed point `24da89b9…`). Record the exact gcc include/link command line verbatim.

- [ ] **Step 3: Archive inventory.** Confirm which headers the emitted `gen/*.c` pull in via `#include` (grep) so the archive's `runtime/` dir is exactly sufficient: expect `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h` (and `net_prelude.h` only if the dump is target-`-osw` or includes it — verify; the linux dump should not need it). Cross-check `c_exit.c` presence at `sf/src/c_exit.c`. Record the minimal file set + sizes.

- [ ] **Step 4: Rebuild-from-C verification (fallback recipe).** In another fresh dir, copy the self-emission `gen/` output + the runtime/link files and compile the C WITHOUT touching the repo include path (self-contained `-I <dir>/runtime`): `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <dir>/runtime -c *.c` + link `zig_runtime.c` + `zig_pal.c` + `c_exit.c` → binary. Record md5 (expect the fixed point — reproduces `24da89b9…`, NOT `3707d33b`). Smoke a hello-class program. This proves the archive is gcc-only self-sufficient. **AMENDMENT (operator 2026-09-07):** the gcc `-c` command MUST carry the full canonical build flag set (`-Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration`) — the fixed point `24da89b9…` reproduces ONLY with `-Wall` in the set (without it a deterministic but cosmetic-label-numbering-different binary `0696756c…` results; instruction-identical, verified 2026-09-07). This matches the warning-clean target of the W2 series (memory-refactor plan AMENDMENT 5): emission is warning-clean at `-Wall -Wextra -O3`; the 3 `-Wno-*` are the structural carve-outs. The `-Wall -Wextra -O3 -fsyntax-only` warning-clean check is a SEPARATE verification gate, not the build command.

- [ ] **Step 5: Report + ledger.** Write baseline + recipes + inventory into the report; ledger line. No commit, no source edits.

---

### Task 2: Capture and commit seed v0 (archive + CHANGELOG)

**Files:**
- Add: `release/seed/zig1-seed.tgz` (packed archive), `release/seed/CHANGELOG.md`, `release/seed/SEED_README.txt` (packed inside the tgz at `zig1-seed/SEED_README.txt`).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 recipes + inventory.
- Produces: the committed seed v0 and its provenance changelog, verified gcc-only rebuildable.

- [ ] **Step 1: Assemble staging tree.** In `/tmp`, build `zig1-seed/` per the spec layout: `zig1` (copy of `/tmp/fx_subfolder/zig1`, the `3707d33b` binary), `gen/` (the Task-1 self-emission C: 41 `.c` + 42 `.h` + `zig_special_types.h`), `c_exit.c`, `runtime/` (the minimal include/link set from Task-1 Step 3), `lib/` (the 4 std `.zig`), `SEED_README.txt` (Task-1 recipes verbatim + provenance + the binary-vs-fixed-point note: gcc of the C reproduces the self-emission fixed point `24da89b9…`, while the archived binary is the zig0-built reference `3707d33b…` — both are the same compiler state at HEAD `1079d90a`).

- [ ] **Step 2: Verify the assembled tree in isolation.** Copy `/tmp/zig1-seed` to a fresh dir, and (a) rebuild from the binary: `./zig1-seed/zig1 --dump-c89 … sf/src/main.zig` → gcc → two-hop closure == fixed point; (b) rebuild from the C only (self-contained `-I zig1-seed/runtime`, per Task-1 Step 4) → fixed-point binary; (c) run a hello-class program with the rebuilt compiler (std from `zig1-seed/lib/`). All rc=0. Record md5s.

- [ ] **Step 3: Pack + write CHANGELOG.** `tar -czf release/seed/zig1-seed.tgz -C /tmp zig1-seed`. Write `release/seed/CHANGELOG.md`: header + the seed-v0 entry (newest-first): `## 2026-09-07 — seed v0 (HEAD 1079d90a)`, fields: seed binary md5 `3707d33bd1d3779c4a98aab9d5be1841`, self-emission C 41 `.c` + 42 `.h`, fixed point `24da89b9d6398ff24f4baecfe2e23f77`, archive md5, rotation basis (zig0-built reference; infra migration). Note: root `CHANGELOG.md` (release-versioned) is NOT touched.

- [ ] **Step 4: Commit.**
```bash
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "feat: seed-model migration — commit zig1 seed v0 archive + changelog (SEEDMIG)"
```

- [ ] **Step 5: Report.** Archive layout proof (tar -tzf), isolated-rebuild evidence (md5s + runs), CHANGELOG content, concerns. Ledger line.

---

### Task 3: Seed build/archive scripts + self_compile parametrization

**Files:**
- Add: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`.
- Modify: `scripts/self_compile/build_zig1_5.sh`, `scripts/self_compile/build_next_gen.sh` (parametrize the compiler path; defaults unchanged so existing behavior is preserved).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1/2 recipes.
- Produces: reusable tooling so future plans build from a seed and rotate the archive at closeout.

- [ ] **Step 1: `scripts/seed/build_from_seed.sh <seed> <out_dir>`.** Usage: unpack/extract the seed (accepts the tgz or an unpacked `zig1-seed/` dir), use the seed `zig1` binary to dump the CURRENT `sf/src/main.zig` → gcc `-m32` → `<out_dir>/zig1_5_clean` (per Task-1 Step-2 command set verbatim; std copied into `<out_dir>/lib/`). Verify two-hop fixed-point closure. If the binary is missing, fall back to rebuilding the seed from its own C (`-I <seed>/runtime`, per Task-1 Step 4) first. Echo a `=== [seed] Done: <out_dir> ===` gate line. Also accept a `--reconstruct-only` mode for the gcc-of-C path.

- [ ] **Step 2: `scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> <out_tgz>`.** Assemble a fresh `zig1-seed/` tree from the given binary + self-emission `gen/` (re-deriving `runtime/`, `c_exit.c`, `lib/` from the repo per the Task-1 inventory), write `SEED_README.txt`, pack `<out_tgz>`, and append a `CHANGELOG.md` entry (date, HEAD sha, binary md5, C count, fixed-point md5, archive md5). Idempotent; used at every future plan closeout to rotate the seed.

- [ ] **Step 3: Parametrize `build_zig1_5.sh` / `build_next_gen.sh`.** Replace the hardcoded `/tmp/fx_subfolder/zig1` with a `$COMPILER` argument/environment defaulting to `/tmp/fx_subfolder/zig1` (build_zig1_5.sh) so behavior at default is byte-unchanged. `build_next_gen.sh` already takes `<compiler>` as arg — verify + document. No output-format change to either script's emitted files.

- [ ] **Step 4: Smoke.** Run `build_from_seed.sh` against `/tmp/zig1-seed` → binary md5 == fixed point `24da89b9…`; run `archive_seed.sh` into a /tmp out → repacks byte-sensibly (compare `tar -tzf` to the Task-2 archive; deterministic given the same inputs). Run `build_zig1_5.sh` at default → unchanged md5.

- [ ] **Step 5: Commit.**
```bash
git add scripts/seed/ scripts/self_compile/build_zig1_5.sh scripts/self_compile/build_next_gen.sh
git commit -m "feat: seed-model migration — build_from_seed/archive_seed scripts + self_compile seed parametrization (SEEDMIG)"
```

- [ ] **Step 6: Report.** Script content summary, smoke evidence (md5s), concerns. Ledger line.

---

### Task 4: Docs — AGENTS.md, QUICK_REF.md, plan conventions

**Files:**
- Modify: `docs/sf/AGENTS.md`, `docs/sf/QUICK_REF.md`.
- Record: report + ledger.

**Interfaces:**
- Consumes: the model + recipes from Tasks 1-3 and the spec.
- Produces: the durable working-model documentation future plans and subagents follow.

- [ ] **Step 1: AGENTS.md.** Update: §0 header context line and §0.1 table (`Bootstrap Compiler` row) to state zig1 is rebuilt from a committed seed or zig0 while zig0 still compiles sf/src; §1.2 Dev Env; §2.2 Build & Test Cycle (add the seed-build path as the forward path, zig0 as the current-cycle path); §2.3 Differential Testing oracle note (zig0 remains the differential oracle ONLY while it can compile the source; the seed/fixed-point self-emission becomes the oracle for newer-construct programs); §9.2 Build Scripts table (add `scripts/seed/build_from_seed.sh` + `archive_seed.sh` rows). Add a new §X subsection (or extend §9): **the seed model + bootstrap-staging constraint** — (1) every plan begins from the committed seed; (2) new-feature compiler code must be written in constructs the current seed already understands; (3) sf/src may adopt new syntax only after a new fixed point exists; (4) rotation at plan closeout via `archive_seed.sh` + `CHANGELOG.md` entry; (5) the seed lives at `release/seed/` (tracked), never `/tmp`. Keep edits additive and verbatim-preserving.

- [ ] **Step 2: QUICK_REF.md.** Add a **"Seed model"** section near the build cheat-sheet: seed location + what it contains, the two rebuild recipes (from seed binary; from seed C only), the rotation protocol (closeout-only, `archive_seed.sh`, `CHANGELOG.md`), and the pointer to `release/seed/SEED_README.txt`. Add ONE newest-first baseline bullet (2026-09-07, HEAD `1079d90a`, seed v0 committed, all gates byte-identical, fixed point unchanged `24da89b9…`) inserted directly above the Post-INTWIDTH bullet.

- [ ] **Step 3: Plan-convention pointer.** Ensure AGENTS.md's plan-writing/global-constraints guidance tells future plans to include the standard seed line: "Reference compiler rebuilt per the seed model (release/seed/); rotate the seed at closeout via scripts/seed/archive_seed.sh". Do NOT edit already-committed plans/specs.

- [ ] **Step 4: Gates.** Re-run the 4-MD5 gate + confirm golden 9/9 + self-compile fixed point hold (doc-only edits MUST be byte-neutral). Rebuild the reference only if needed for measurement hygiene; record md5.

- [ ] **Step 5: Commit.**
```bash
git add docs/sf/AGENTS.md docs/sf/QUICK_REF.md
git commit -m "docs: seed-model migration — AGENTS/QUICK_REF seed model + rotation + bootstrap-staging constraint (SEEDMIG)"
```

- [ ] **Step 6: Report.** Diff summary, verbatim-preservation evidence, gate md5s, concerns. Ledger line.

---

### Task 5: Full battery + STOP-present closeout

**Files:**
- Record only.

- [ ] **Step 1: Battery.** golden 9/9 rc0 byte-identical; matrix 21/21; corpus sweep (must match the pre-plan state — zero movement expected); 4-MD5 byte-identical (gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `846106ac`); self-compile fixed point `24da89b9…` (two-hop, 41 `.c`, 0 `error[`, 0 PANIC).

- [ ] **Step 2: Seed self-sufficiency proof.** From a pristine `/tmp` unpack of the committed `release/seed/zig1-seed.tgz`: (a) rebuild via seed binary → fixed point; (b) rebuild via seed C only → fixed point; (c) run a hello-class + one gate program with the C-rebuilt compiler (std from the archive `lib/`). All rc=0, md5s recorded.

- [ ] **Step 3: STOP-present.** Propose plan close + the rotation cadence going forward (each future fixed-point-moving plan runs `archive_seed.sh` at its docs closeout). No commit, no docs touched beyond what Tasks 2-4 already committed.

---

## Plan Self-Review

1. **Spec coverage:** seed v0 capture + commit (T2), scripts + parametrization (T3), AGENTS/QUICK_REF + plan-convention updates (T4), full battery + self-sufficiency proof + STOP (T5); spec layout/recipes/CHANGELOG/rotation implemented (T2/T3/T4); success criteria 1-4 → T2/T3/T4, 5 → T1/T5; out-of-scope (zig0 removal, 0.20.0 re-staging, sf/src changes, src_sh) untouched.
2. **Placeholder scan:** no TBD; all md5s/file counts are the measured HEAD `1079d90a` values; recipes are resolved by the record-only Task-1 census (execution follows it).
3. **Type/name consistency:** seed dir `release/seed/`; canonical archive `zig1-seed.tgz`; provenance `release/seed/CHANGELOG.md` (distinct from root `CHANGELOG.md`); scripts `scripts/seed/build_from_seed.sh` + `archive_seed.sh`; report file `task-SEEDMIG-report.md`; memory agent `seedmig-session`.
