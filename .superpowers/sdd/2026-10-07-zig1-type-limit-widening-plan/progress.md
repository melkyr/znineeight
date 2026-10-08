# SDD ledger — plan: docs/superpowers/plans/2026-10-07-zig1-type-limit-widening-plan.md

Started: 2026-10-07. Operator resumed build session (m0623); compression FORBIDDEN this session.
Branch `zig1_improvements`, NO push. Edit with `edit`/`fastedit` only.

Base at start: HEAD `32cc6dfb61fcc4b801df967b077dc6468348ef16` (spec+plan commit).
Preflight: `git diff --stat 3fae3552..HEAD -- sf/src` empty -> `sf/src` byte-identical to the
structural-plan final state `3fae3552`.
Seed v93 (fixed point `639902d5146233091f6b2f98508ce3eb`, archive md5 `e1955908f3aa58992592f9c021c36d42`).
Note: `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/progress.md` has uncommitted
append lines from the prior plan's finish (not ours to touch here).

## Preflight conflict scan (plan vs spec)
- Task 1 touches `sf/src/type_registry.zig` + its writer call sites (`symbol_registrator.zig`,
  `type_resolver.zig`); Task 2 touches docs + `release/seed`. No file contention between tasks. OK.
- Plan vs spec: both say widen `module_id`+`alignment`->u16, `name_id`+`payload_idx`->u32; remove
  guards; keep interner + FoldVal; seed v93->v94. Consistent.
- Global Constraint says "Do not touch interner bucket / comptime FoldVal" — Task 1 scope is Type
  only. OK.
- Scan result: clean. Proceed.

## Todos
- [x] Task 0 baseline adoption (report: `task-0-report.md`; HEAD `32cc6dfb`, `sf/src` diff vs `3fae3552` empty; baseline v93 adopted)
- [x] Task 1 widen Type ceiling columns + battery + RSS
- [x] Task 2 closeout + limits note + seed v93->v94
- [ ] Final review + finish

Task 0: complete (commit f99f6d53, baseline adopted; sf/src byte-identical to 3fae3552; review skipped — docs-only adoption, no concerns).

Task 1: complete (report: `task-1-report.md`). `Type` widened to 20 B (`name_id`/`payload_idx` u32, `module_id`/`alignment` u16; two u16 columns moved after the u8 columns to reuse tail padding); guards `typeDbCeiling`/`typeNarrowU16`/`typeNarrowU8` removed and all call sites (type_registry + symbol_registrator + type_resolver + 2 test binaries) converted to plain assignment/`@intCast(u32|u16)`; tech doc `03_type_resolution.md` 16 B→20 B. NEW fixed point/binary md5 `296c48f676deec290387b57132e4e2bd` (hop1==hop2). Battery all green: dump-MD5 8/8 delta 0; corpus 1097 = 923/58/116/0/0; stdlib 266/0; examples 24/24; goldens gol/lisp/json/mud; markers byte-identical in-session 48819/48819 diff 0; self-compile rc0 0 error/0 PANIC 48c/48h. RSS pooled 10-run median baseline 16,030K / new 15,516K (delta ≈−514K; target ≤16,384K MET). Concern: delta sign opposite to the expected +10–16K (host/arena variance dominates); 20-B layout required reordering `module_id` after the u8 columns.
Task 1: complete (commits f99f6d53..78dd4593, review clean after 1 fix round; Type widened to 20B via field reorder (safe, nominal access only); ceiling guards removed; new fixed point 296c48f676deec290387b57132e4e2bd; dump-MD5 8/8; corpus 923/58/116; stdlib 266/0; examples 24/24; markers identical; RSS median 15,516-15,704K (<=16,384K, margin ~0.7-0.9MB)).
Task 1: accepted deviation: module_id/alignment reordered after the u8 columns to hit the plan's stated 20B (in-place widening would be 24B); reviewer confirmed safe.
Task 1: minor (deferred): test_sym_reg_bin/test_semantic_bin already fail at base on pre-existing error[3061] semanticAnalyzerInit arity drift (not gate-verified).

Task 2: complete (report: `task-2-report.md`, commit `docs: type-limit widening plan — closeout + seed v94`). Re-verify at HEAD 78dd4593: seed rebuild hop1==hop2==296c48f676deec290387b57132e4e2bd (gen==hop2 byte-identical); battery all green — dump-MD5 8/8 delta 0; corpus 1097 = 923/58/116/0/0; stdlib 266/0; examples 24/24; goldens gol/lisp/json/mud; markers in-session 48819/48819 diff 0; self-compile 48c/48h rc0. Final RSS median 15,448K (5 samples 15436/15824/15236/15448/15508; ≤16,384K, margin ≈936K). Limits note added to `docs/sf/QUICK_REF.md` (Type 20B: name_id/payload_idx u32, module_id/alignment u16 residual 65,535; earlier u16/u8 ceilings raised; interner auto-migrates u16→u32); seed block v93→v94; tech doc `03_type_resolution.md` confirmed 20B. Seed rotated v93→v94: archive md5 e1955908…→16ca54bd63320a4ec1d8e8aee3fe2c43, fixed point 296c48f6…, CHANGELOG HEAD 78dd4593. Concern: RSS median ~0.4–0.6MB below expected 15.5–15.7MB (host variance, inside target).
