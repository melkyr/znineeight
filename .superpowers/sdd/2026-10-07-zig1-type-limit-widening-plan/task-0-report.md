# Task 0 report — Baseline adoption

Plan: `docs/superpowers/plans/2026-10-07-zig1-type-limit-widening-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-type-limit-widening-design.md`
Date: 2026-10-07. Read-only: no `sf/src` edit, no rewiring, no measurement, no seed build.

## Step 1 — `sf/src` at structural-plan final state

- HEAD recorded: `32cc6dfb61fcc4b801df967b077dc6468348ef16`.
- Commits after `3fae3552`: only `32cc6dfb docs: add zig1 type-limit widening spec + plan` (docs only).
- `git diff --stat 3fae3552..HEAD -- sf/src` → **empty**.
- Result: `sf/src` is byte-identical to the structural-plan final state `3fae3552`. No divergence.

## Step 2 — Frozen baseline (adopted verbatim)

- Seed: **v93**.
- Fixed point: `639902d5146233091f6b2f98508ce3eb`.
- Archive md5: `e1955908f3aa58992592f9c021c36d42`.
- `-s0` self-compile pool: ≈ **11,965 K**.
- Peak RSS median: ≈ **16,150 K**.
- Battery: dump-MD5 **8/8**, corpus **923/58/116** (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH),
  stdlib **266/0**, examples **24/24**, goldens **gol / lisp / json / mud**.
- **Binding target: peak RSS median ≤ 16,384 K.**

## Step 3 — Expected cost and target check

- Change widens `Type` **16 B → 20 B** (+4 B/type): `name_id`/`payload_idx` u16→u32 (+2 B each),
  `module_id`/`alignment` u8→u16 absorbed by existing padding.
- Expected RSS cost **~10–16 KB** (~10 KB at current len 2,497; ~16 KB at pre-sized cap 4,096).
- ≈0.1 % of the 16 MB budget; structural-plan margin (~180–440 K) absorbs it.
- **Target ≤16,384 K must still hold** after the widening — verified in Task 1 / Task 2.

## Pre-existing state noted (not ours)

- `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/progress.md` — uncommitted append from
  the prior plan; left untouched.
- Untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`, `for_open.z98`,
  `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) — not ours; left untouched.

## Concerns

- None blocking. Baseline adopted as-is; the ~10–16 KB widening cost leaves headroom under the
  16,384 K target, contingent on Task 1 holding the structural-plan gains (interner switch +
  comptime `FoldVal` + right-sizing unchanged).
