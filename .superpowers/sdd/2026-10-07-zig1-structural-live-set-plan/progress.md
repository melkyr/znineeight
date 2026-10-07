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
- [x] Task 0 baseline adoption
- [x] Task 1 interner investigate
- [x] Task 2 interner fix (+STOP-GATE)
- [ ] Task 3 type-registry investigate
- [x] Task 4 type-registry fix (+STOP-GATE)
- [ ] Task 5 comptime investigate
- [ ] Task 6 comptime fix
- [ ] Task 7 closeout + seed v93


Task 0: complete (commit c8b87daa, baseline adopted verbatim; no sf/src change, no measurement).
Task 1: complete (commit 5ea9b91d, interner analysis; review clean after 1 fix round — gap corrected to 1,040K).
Task 2: complete (R1 u16 bucket slots + wide fallback/migration, R2 drop InternEntry.hash; dump-MD5 8/8 delta 0, corpus 923/58/116, stdlib 266/0, examples 24/24, goldens 4/4, markers byte-identical; RSS median 17,096K (-332K) -> STOP-GATE NOT met, proceed to Task 3).
Task 2: complete (commits 5ea9b91d..25809d0b, review clean; new fixed point 9cdcc97bb8dc0a0b94e29b9e981e5376; dump-MD5 8/8 delta 0; corpus 923/58/116; stdlib 266/0; examples 24/24; markers identical; RSS median ~17.08-17.10 MB ~-282..-332K; pool -491K). STOP-GATE NOT met (17,096K > 16,384K) -> proceed to Task 3.
Task 2: minor (deferred): sf/src/string_interner.zig migration allocates count=buckets_len but does not update buckets_capacity (safe under cap==len invariant; latent).
Task 2: minor (deferred): sf/docs/tech_docs/00_shared_infra.md still documents buckets_items:[*]u32 and deleted ensureCapacityBuckets/appendBucket -> update at Task 7 closeout.
Task 2: minor (deferred): R1 wide fallback unexercised by any fixture (correct by static reasoning only).
Task 3: complete (commit 3b600121, type-registry analysis; review clean after 1 fix round). Top: R1 right-size registry arrays/caches ~380-400K (Med, hint data-dependent); R2 Type[] 32->16B ~105K (Med, ~22 external write sites); R3 cache narrowing ~70K. Package ~0.4-0.47MB < 0.712MB gap.
Task 3: minor (deferred): report §"~15 external write sites" is 22; "alignment/size" overstates (size stays u32); §1.4 ~213KB vs R1 right-size ~164KB inconsistency.
Task 4: complete (R1 hint-seeded pre-size via typeRegistryInitSized + arrayReserve/InitCap; R2 Type 32->16B, drop is_signed, name_id/payload_idx u16, alignment/module_id u8, c_name_id->U32ToU32Map side memo, documented u16/u8 ceiling guard; external casts in symbol_registrator/type_resolver/c89_emit/lower/tests). New fixed point/binary md5 078ed10fc3477c0cfd07140b2dfb4ece; dump-MD5 8/8 delta 0; corpus 923/58/116/0/0; stdlib 266/0; examples 24/24; goldens 4/4; markers byte-identical in-session (48788 lines, diff 0); track-memory type_db 346K->249K. RSS 5-pair median base 17,096K / new 16,880K (-216K). STOP-GATE NOT met (16,880K > 16,384K) -> proceed to Task 5.
Task 4: minor (deferred): R1's measured carve/RSS prize (~90K carve, ~150-220K RSS) is below the Task-3 ~380-400K projection; segment-doubling accounting in GrowableSandGrow makes per-array abandoned generations less separable than §1.5 assumed.
Task 4: minor (deferred): test binaries fix only narrow casts; not built/run (battery is corpus/stdlib/examples/goldens).
