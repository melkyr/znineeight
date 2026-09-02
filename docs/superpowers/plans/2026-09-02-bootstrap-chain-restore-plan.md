# Bootstrap Chain Restore (zig0 → zig1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the `zig0 → zig1` bootstrap chain (broken at `a1bfa260`, last green `2206177e`) by rewriting the offending constructs into zig0-compatible form, with a documented fallback (separate plan) if recovery proves impossible.

**Architecture:** A README boundary note; then a read-only **I-BOOT** investigation that builds a minimal-repro harness over the offending construct shapes, classifies each failing site as root vs cascade, and pins the zig0-compatible idiom; then gated **F-BOOT** fix tasks executed on HEAD (ast.zig value-pool slice root first, spill_store roots second), each gated by `build_release.sh` green + the full battery on the zig0-built zig1.

**Tech Stack:** Zig (sf/src), C++ bootstrap (src/bootstrap), bash, gcc -m32, stale `build/zig0` front-end as the type-check oracle.

## Global Constraints

- **Boundary (operator-ruled):** last-good `2206177e` (sf/src = F-TABLE `40d72e04`), first-bad `a1bfa260` (F-SIDE: disk-back AST value pools). 5 source commits after the break: `a1bfa260`, `eb8730c8` (F-FMT), `89c310a7` (F-SBackend), `16d28337` (F-MM), `cc5c37c1` (F-S); GATE `ff5e3633` + 2 `.bak` commits are docs/artifacts.
- **The offending construct (bisect-pinned root):** `ast.zig` value-pool cache slice — `p.cache_buf[ @intCast(usize,v)*VALUE_POOL_BLOCK_BYTES .. @intCast(usize,v)*VALUE_POOL_BLOCK_BYTES + VALUE_POOL_BLOCK_BYTES ]` (ast.zig:581 at HEAD / :592 at a1bfa260) — a slice of a `[*]u8` struct field with a computed (non-literal) start. zig0: `type mismatch`. Good accepted pattern: `nraw[0..N]` (ast.zig:782/784, literal-`0` start).
- **F-BOOT rewrites are source-only and behavior-preserving:** the 4 MD5 gates must NOT move (gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `4591fef0` — no re-baseline). The reference zig1 (`/tmp/fx_subfolder/zig1`, md5 `0c09fe1a`) is the oracle; `build_release.sh` green = acceptance.
- **zig0 oracle:** the stale `build/zig0` (08-27) is a VALID type-check oracle — `src/bootstrap/type_checker.cpp` unchanged since 2026-05-11, so a fresh g++ rebuild has an identical type checker. Invocation: `build/zig0 --header-priority-include -o <precreated-dir>/zig1.c <input>.zig` (the `-o` dirname receives the emitted `.c`; MUST pre-exist). `timeout 300` on front-end runs.
- **build_release.sh:** `timeout 900 bash sf/scripts/build_release.sh` from repo root (gate `=== [release] Done ===`); WIPES `/tmp/fx_subfolder` → after each run reinstall `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`. This is the FIRST exercise since 08-27.
- **Self-compile gate:** `timeout 900 bash scripts/self_compile/build_zig1_5.sh` → 42 `.c` / 0 `error[` / 0 PANIC (spill_store module added; 41→42).
- **Z98 dialect** for any `.zig` written; `edit`/`fastedit` only; never touch `sf/build/out_release/`; never touch the committed `.bak` files (`build/zig1_5_clean.bak` etc.).
- **Ledger:** append one line per completed task to `.superpowers/sdd/progress.md`. **Reports:** `.superpowers/sdd/task-BOOTSTRAP-report.md` (gitignored; WARNING `task-1-report.md` is TRACKED — never reuse). Mnemoria agent `bootstraprestore-session`.
- **Pre-existing dirty files never staged:** `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`, `.zig1_*.tmp`.
- Design doc: `docs/superpowers/specs/2026-09-02-bootstrap-chain-restore-design.md`.

---

### Task 0: README bootstrap-chain boundary note (docs)

**Files:**
- Modify: `README.md` (new section near the build/self-host docs)
- Commit: `docs: record bootstrap-chain boundary (zig0 last green at 2206177e, broken at a1bfa260)`

**Interfaces:**
- Consumes: the bisect finding (last-good `2206177e`, first-bad `a1bfa260`).
- Produces: a durable, operator-audited record of the bootstrap boundary + drift risk; the anchor for the fallback's merge decision.

- [ ] **Step 1: Locate the build/self-host section in README.md**

Read README.md and find the section describing `build_release.sh` / self-hosting. Note the exact heading + line numbers.

- [ ] **Step 2: Add the boundary note**

Insert a short section stating: the `zig0 → zig1` bootstrap chain was last verified green at commit `2206177e`; it broke at `a1bfa260` (F-SIDE: disk-back AST value pools) because the source drifted past zig0's type checker (`src/bootstrap/type_checker.cpp`, unchanged since 2026-05-11) while the tree was kept alive only via the self-host chain. Reference the restore plan. Keep it factual and terse.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: record bootstrap-chain boundary (zig0 last green at 2206177e, broken at a1bfa260)"
```

### Task I-BOOT: Minimal-repro investigation — root vs cascade + compatible idiom (read-only)

**Files:**
- (Read) `sf/src/ast.zig` (:581/:782-784 value-pool + S-AST slice patterns), `sf/src/spill_store.zig` (:183/:213), the 5 source commits' diffs (`a1bfa260`, `eb8730c8`, `89c310a7`, `16d28337`, `cc5c37c1`), `src/bootstrap/type_checker.cpp` (report sites :2545/:4721, re-eval loop :2486)
- (Create, /tmp only) minimal-repro snippets + zig0 runs under `/tmp/boot_diag/`
- Report: append `## I-BOOT` to `.superpowers/sdd/task-BOOTSTRAP-report.md`

**Interfaces:**
- Consumes: the bisect boundary + the pinned ast.zig:581 root; the stale `build/zig0` oracle.
- Produces: (a) per-construct-shape zig0 verdict (accepts/rejects), (b) the root-vs-cascade classification of every failing site, (c) the zig0-compatible idiom per root, (d) recoverable/impossible verdict for the operator.

- [ ] **Step 1: Confirm the oracle**

Run `timeout 300 build/zig0 --header-priority-include -o /tmp/boot_diag/anchor sf/src/main.zig` and confirm it reproduces the known failure set (ast.zig:581 type mismatch + cascades; spill_store:183/213). Record rc + the exact error list. (This is the stale-zig0 reproduction already done in the bisect — re-confirm at HEAD.)

- [ ] **Step 2: Build the minimal-repro harness**

Under `/tmp/boot_diag/`, create tiny self-contained `.zig` snippets (each with a `main` stub or top-level fn, minimal imports avoided — use bare definitions so zig0 parses them standalone) covering, in isolation:
- A: slice of `[*]u8` param with literal-`0` start (`f(buf: [*]u8) { g(buf[0..N]); }`) — the GOOD control.
- B: slice of `[*]u8` param with computed start (`buf[a..b]` where a/b are u32 locals).
- C: slice of a `[*]u8` STRUCT FIELD with computed start (`p.cache_buf[a..b]`) — the suspected root.
- D: slice of `[*]u8` struct field with literal-`0` start (`p.cache_buf[0..N]`).
- E: `var x = a + @intCast(u32, n);` (n usize) — the spill_store:183/213 shape.
- F: `var x: u32 = a + @intCast(u32, n);` (explicit annotation variant of E).
- G: `var x = a & b;`, `var x = a or b;`, `var x = if (c) a else b;` — the ast.zig:600/comptime_eval:55/c89_emit:1681 shapes.
Run each through `build/zig0` (front-end only) and record accept/reject + error text.

- [ ] **Step 3: Classify roots vs cascades**

Using Step-2 verdicts + the type_checker.cpp re-eval semantics, classify each failing site at HEAD as ROOT (zig0 rejects the construct in isolation) or CASCADE (construct is fine in isolation; fails only when a prior break leaves shared types undefined). Specifically adjudicate: ast.zig:581 (root?), ast.zig:589/590, spill_store:183/213, c89_emit:1681, comptime_eval:55, front_resolution:158.

- [ ] **Step 4: Determine the compatible idiom per root**

For each ROOT, verify a zig0-accepted rewrite in the harness (e.g. hoist to `var base = p.cache_buf + off; g(base[0..len])`; or explicit annotation `var x: u32 = …`; or `@ptrCast`). Confirm the S-AST `nraw[0..N]` idiom generalizes. Record the exact accepted snippet(s).

- [ ] **Step 5: Verdict + STOP-present**

Verdict: **recoverable** (all roots have a trivial zig0-compatible idiom, low rewrite surface) or **impossible** (a root has no compatible form — would require fixing zig0's type checker itself). Append `## I-BOOT` to the report with the harness results + classification + idiom + verdict, and STOP-present to the operator. NO `sf/src` edits, NO commit. If **impossible**, the operator's fallback (ultra-gate + merge-to-main second plan) is triggered — do NOT improvise it here.

### Task F-BOOT-1: Rewrite the ast.zig value-pool slice root (F, gated on I-BOOT = recoverable)

**Files:**
- Modify: `sf/src/ast.zig` (the value-pool cache-slot read, ~:581, and any sibling slice-of-field patterns in the same era)
- Commit: `fix: zig0-compatible value-pool slice (hoist computed base)`

**Interfaces:**
- Consumes: I-BOOT's confirmed idiom for the ast.zig:581 root.
- Produces: a HEAD tree whose ast.zig zig0-type-checks; the cascade sites are expected to clear with it.

- [ ] **Step 1: Golden baseline capture**

Record the current gate battery on the reference zig1 (`/tmp/fx_subfolder/zig1`): 4 MD5 (`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 <entry> | md5sum`, repo-root CWD; entries gol `examples/z98/game_of_life/main.zig`, lisp `examples/z98/lisp_interpreter_curr/main.zig`, json `examples/z98/json_parser/main.zig`, mud `examples/z98/mud_server/main.zig`) + golden 9/9 run outputs + `--track-memory` baseline. (The reference is zig1_5_clean-derived; byte-identity must not move.)

- [ ] **Step 2: Apply the compatible idiom**

Rewrite the ast.zig:581 value-pool cache-slot slice (and every sibling `cache_buf[computed .. computed]` / `head_buf[computed .. computed]` shape introduced by a1bfa260/F-SIDE) into the I-BOOT-confirmed zig0-accepted form (hypothesis: `var base = p.cache_buf + <computed>; spillReadAt(..., base[0..<len>])`). Behavior must be identical — same bytes read into the same slots.

- [ ] **Step 3: Verify zig0 front-end accepts the tree**

Run `timeout 300 build/zig0 --header-priority-include -o /tmp/boot_f1 sf/src/main.zig` → expect **rc=0, 0 real errors** (all cascades cleared). If other roots remain, STOP and report (they belong to F-BOOT-2 or are new I-BOOT findings).

- [ ] **Step 4: End-to-end gate — build_release.sh + full battery**

Run `timeout 900 bash sf/scripts/build_release.sh` (repo root) → gate `=== [release] Done ===`; reinstall std lib. Then on the **zig0-built** `/tmp/fx_subfolder/zig1`: 4 MD5 must equal the baselines byte-for-byte; golden 9/9; self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh` → 42 `.c` / 0 err / 0 PANIC; reference 0-warning.

- [ ] **Step 5: Commit**

```bash
git add sf/src/ast.zig
git commit -m "fix: zig0-compatible value-pool slice (hoist computed base)"
```

### Task F-BOOT-2: Rewrite spill_store roots if independent (F, gated on I-BOOT classification)

**Files:**
- Modify: `sf/src/spill_store.zig` (and any sibling introduced by `89c310a7`) if I-BOOT found independent roots there
- Commit: `fix: zig0-compatible spill_store expressions`

**Interfaces:**
- Consumes: I-BOOT's verdict on spill_store.zig:183/213 (root vs cascade) + its confirmed idiom.
- Produces: a HEAD tree fully zig0-type-checking; the F-BOOT-1-first order means this runs only if spill_store roots remain after F-BOOT-1.

- [ ] **Step 1: Re-run the zig0 front-end after F-BOOT-1**

`timeout 300 build/zig0 --header-priority-include -o /tmp/boot_f2 sf/src/main.zig`. If 0 errors — SKIP this task (spill_store was a cascade; record and go to F-BOOT-3). If spill_store.zig:183/213 errors remain, apply the I-BOOT-confirmed idiom (e.g. explicit annotation / restructured expression) to each.

- [ ] **Step 2: End-to-end gate + commit**

Same as F-BOOT-1 Steps 3-4 (build_release.sh green + full battery on the zig0-built zig1), then:
```bash
git add sf/src/spill_store.zig
git commit -m "fix: zig0-compatible spill_store expressions"
```

### Task F-BOOT-3: Full bootstrap restoration gate (F, terminal)

**Files:**
- Report only (no expected source change) unless a residual root surfaces
- Commit (if the operator directs a reconciliation doc): `docs: bootstrap chain restored (zig0->zig1 green at HEAD)`

**Interfaces:**
- Consumes: F-BOOT-1 (+F-BOOT-2) rewrites.
- Produces: proof the bootstrap chain is restored and the zig0-built zig1 is behaviorally identical to the reference.

- [ ] **Step 1: Clean build_release.sh from a pristine tree**

Verify the working tree has only pre-existing dirty files, then `timeout 900 bash sf/scripts/build_release.sh` → `=== [release] Done ===`; reinstall std lib. Confirm `/tmp/fx_subfolder/zig1` runs and reports a sane `--help`.

- [ ] **Step 2: Full battery on the zig0-built zig1**

4 MD5 byte-identical (gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `4591fef0`); golden 9/9 run outputs; corpus sweep (404 dirs, 0-asymmetric vs the recorded buckets); self-compile 42 `.c` / 0 err / 0 PANIC; reference 0-warning.

- [ ] **Step 3: Ledger + report + STOP**

Append the ledger line(s) for Tasks 0..F-BOOT-3 and `## F-BOOT-3` (proof table) to the report. STOP-present to the operator: bootstrap chain restored; the `.bak` files may be retired once the operator confirms. Do NOT run the fallback unless I-BOOT ruled it impossible (it would be a separate plan).

---

## Fallback (triggered only if I-BOOT = impossible — separate plan, NOT executed here)

If I-BOOT concludes the bootstrap chain cannot be preserved (a root construct has no zig0-compatible form without fixing zig0's type checker), the operator directed: (1) ultra-gate zig1 AND zig1_5 against mi_matrix + corpus + the full battery so their real capability is proven; (2) README note "bootstrap chain ends at `2206177e`"; (3) prepare a SECOND plan to merge `zig1_start → main` — we are then in unknown territory (w98 emission never tested). That fallback is out of scope for this plan and becomes its own spec+plan.
