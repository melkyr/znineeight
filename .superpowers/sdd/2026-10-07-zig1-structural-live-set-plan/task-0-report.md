# Task 0 — Baseline adoption (no work wasted)

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no measurement**, **no
rewiring**, and **no dump-MD5 re-baseline**.

## Step 1 — `sf/src` unchanged since L3

- `git diff --stat 2d713a9a..HEAD -- sf/src` → **empty**.
- The prior live-set spike (HEAD `9465e31f`, plus its ancestors) committed **docs only**; the working
  tree's `sf/src` is byte-identical to the post-L3 state `2d713a9a`.
- HEAD at adoption = `9465e31fa580959605438c2ca8cdb90c68bebf0b`.

## Step 2 — Adopted frozen baseline

Adopted verbatim from
`.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-0-report.md`:

- Seed **v92**; archive `release/seed/zig1-seed.tgz` md5 `3cacdd44df75c0ce96abfd51af93f928`.
- Archived v92 binary fixed point `d40e875a7ba3aa55d441af56006f6023`.
- Build gate: two-hop closure `hop1 == hop2 == **2293f756a8250351740cf6acde194d17**` (current-HEAD
  fixed point; no `FIXED_POINT_MD5` pin because `sf/src` carries post-v92 L3).
- `-s0` self-compile (CWD repo root, RELATIVE `sf/src/main.zig`):
  - `pool = 14,924 K`, `total = 2,967 K`, `perm=982K mod=1020K scr=965K type_db=346K`.
  - Peak **RSS median = 17,424 K** (samples 17,296 / 17,424 / 17,564 K), wall ≈0:04.1, 48 `.c`+48 `.h`.
- Per-arena carve (Σ `arena <name>: grew` `new`): module 5,382,144 · diag_read 4,655,313 ·
  perm 2,558,152 · import_scratch 1,385,155 · type_db 1,032,192 · scratch 223,519 · source 0 (B);
  Σ 15,236,475 vs pool 15,282,176 (residual 45,701).
- Frozen equivalence: dump-MD5 **8/8** (gol/lisp/json/mud × `-fsafe`/`-ffast`); corpus
  **1097 = 923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH**; `verify_stdlib` **266 PASS / 0 FAIL**;
  examples **24/24**; runtime goldens gol `fcbf7e7c…`, lisp `b3d9f897…`, json `8bda3d5a…`,
  mud server `66c8f0ab…` / client `93147d0f…`.

## Step 3 — Interim target + stop-gate

- Binding metric: peak **RSS** (`/usr/bin/time -v` Maximum RSS), median of ≥3 interleaved `-s0`
  self-compile runs. Carve ≠ touched RSS.
- Interim target: peak RSS **≤ 16 MB** (16,384 K).
- **Stop-gate after every Fix** (Task 2, Task 4, Task 6): if peak RSS ≤ 16 MB → STOP the plan and go
  to Task 7 closeout; otherwise proceed to the next work package.
- Task 1's Fix (Task 2, string interner) is the **first** stop-gate.

## Step 4 — Scope

- No measurement, no rewiring, no source edit. This report only adopts the frozen baseline above.
- Only this report is committed (`docs: structural live-set plan — Task 0 baseline`).

## Concerns (carried from the adopted baseline)

1. `-o <dir>` MUST pre-exist or the self-compile fails `rc=1` (`error: output directory does not
   exist`).
2. `source` arena carve = 0 at `-s0` (satisfied from `seg_free_head` reuse) — do not hunt it.
3. `mod=`/`scr=` are per-segment high-water peaks, not live footprints; `total=` is `perm+mod+scr`.
4. RSS is host-noisy (±~0.3 MB); `pool` is stable. Fix tasks must measure RSS median ≥3, interleaved.
5. Untracked root strays pre-exist and are not staged.
