# SDD ledger — plan: docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md

Started: 2026-10-07. Operator resumed build session (m0541); compression FORBIDDEN this session.
Branch `zig1_improvements`, NO push. Edit with `edit`/`fastedit` only.

Base at start: HEAD `9465e31fa580959605438c2ca8cdb90c68bebf0b`.
Preflight: `git diff --stat 2d713a9a..HEAD -- sf/src` empty -> `sf/src` byte-identical to post-L3 state.
Seed v92 (archive md5 `3cacdd44df75c0ce96abfd51af93f928`).

## Preflight conflict scan (plan vs spec)
- Plan Task 0 reuses the prior live-set Task 0 report (no re-measure, no rewiring) — matches spec "Baseline adoption". OK.
- Task numbering in PLAN (0..7) differs from SPEC "Task shape" prose (which calls the Investigate/Fix pairs "Tasks 1–3", meaning 3 work packages). The PLAN is the operative enumeration: packages = Tasks 1–2 (interner), 3–4 (type registry), 5–6 (comptime), 7 closeout. Ruling: follow the PLAN's per-task numbering; packages are the spec's three structures in order. No user-visible ambiguity.
- Stop-gate placement: plan says after every Fix (Task 2, 4, 6); if peak RSS <= 16 MB STOP. Consistent.
- No task/task file-contention: packages touch disjoint files (string_interner.zig; type_registry.zig; comptime_eval.zig). OK.
- Scan result: clean. Proceed.

## Todos
- [ ] Task 0 baseline adoption
- [ ] Task 1 interner investigate
- [ ] Task 2 interner fix (+STOP-GATE)
- [ ] Task 3 type-registry investigate
- [ ] Task 4 type-registry fix (+STOP-GATE)
- [ ] Task 5 comptime investigate
- [ ] Task 6 comptime fix
- [ ] Task 7 closeout + seed v93

