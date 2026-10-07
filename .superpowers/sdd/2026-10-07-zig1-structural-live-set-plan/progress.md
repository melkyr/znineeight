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
- [x] Task 3 type-registry investigate
- [x] Task 4 type-registry fix (+STOP-GATE)
- [x] Task 5 comptime investigate
- [x] Task 6 comptime fix
- [x] Task 7 closeout + seed v93


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
Task 4: complete (commits 3b600121..da376da0, review clean; new fixed point 078ed10fc3477c0cfd07140b2dfb4ece; dump-MD5 8/8; corpus 923/58/116; stdlib 266/0; examples 24/24; markers identical; type_db 346K->249K; pool 14362->14064K; RSS median 16,880K (-216K)). STOP-GATE NOT met (16,880K > 16,384K) -> proceed to Task 5.
Task 4: minor (deferred): payload_idx u16 cast has NO ceiling guard (unchecked @intCast under -ffast; silent truncation if >65,535 payload entries; unreachable on all gates) - consider one-line guard or explicit waiver at Task 7.
Task 4: minor (deferred): computed alignment writers unguarded (>255 truncation; implausible); report says test_sym_reg_bin "9 sites" but 8.
Task 4: deferred action: run sf/scripts/build_test.sh at Task 7 to cover the two edited test binaries (test_semantic_bin.zig, test_sym_reg_bin.zig), outside the battery.
Task 5: complete (commit 45ecd226, comptime analysis; review clean after 1 fix round). Top: R1 element 48->16B (small-int inline + rare wide-int side pool) ~0.25-0.38 MiB touched; R2 pre-size vals+slots ~0.9 MiB carve. High-water verdict: GENUINE lever (module reset only at main.zig:407; post-reset lir_read/emission reuse seg_free_head, no carve row).
Task 5: minor (deferred): headline ">64-bit via << or overflowing *" omits `~` of a near-max u64 operand (<=65 bits, 3 limbs); non-material (closure has zero `const ~`).
Task 5: minor (deferred): R2 mechanism geometric sum 393,168B vs correct 785,664B (pre-existing, unchanged).
Task 6: complete (R1 FoldVal 16B tag {small,kind,neg,wide} + index-addressed wide_ints[*]ComptimeInt for len>2; R2 source-hint pre-size via comptimeFoldTableInitSized + u32ToU32MapInitCap, doubling kept as soft floor; main.zig:199 fold_hint=source.len/9 -> cap 16,384). New fixed point/binary md5 44b8e7fff5a115743ab5c62adb849555; dump-MD5 8/8 delta 0; corpus 923/58/116/0/0; stdlib 266/0; examples 24/24; goldens 4/4; markers byte-identical in-session (48851 lines, diff 0); track-memory pool 14074K->11965K. RSS 8-pair median base 16,904K / new 16,174K (-730K). STOP-GATE MET (16,174K <= 16,384K) -> Task 7 closeout.
Task 6: wide-path verified with /tmp fixtures (1<<70, u64max*3, 20-value wide_ints growth): old vs new identical error[3000]/emitted .c; small neg/zero/bool/float round-trip fixtures byte-identical.
Task 6: minor (deferred): stop-gate margin ~210K (1/8 new samples 16,432K); pool drop -2109K exceeds ~1.8MB fold carve, not independently isolated (no instrumentation).
Task 6: complete (commits 45ecd226..d69f10e7, review clean; new fixed point 44b8e7fff5a115743ab5c62adb849555; FoldVal 16B + wide side pool + pre-size; dump-MD5 8/8; corpus 923/58/116; stdlib 266/0; examples 24/24; markers identical; pool 14074K->11965K; wide path exercised (gdb 20 encodes/20 decodes, pool 0->16->32); RSS median 16,174K (impl) / 15,938K (rev)). STOP-GATE MET (<=16,384K) -> STOP fixes, go to Task 7 closeout.
Task 6: minor (deferred): report lists c.zig (u64max*3) as wide path but it compiles rc0 via paren_expr; wide path genuinely proven by h.zig + d/e/f/g (gdb) instead.
Task 6: minor (deferred): _pad never initialized (stored, never read/compared); foldCapFromHint can spin on >2.4GB source (unreachable).
Task 7: complete (re-verify at HEAD d69f10e7: fresh seed rebuild /tmp/struct_seed7 -> hop1==hop2==44b8e7fff5a115743ab5c62adb849555; dump-MD5 8/8; corpus 1097=923/58/116/0/0; stdlib 266/0; examples 24/24; goldens gol/lisp/json/mud all pinned; markers byte-identical in-session 48851/48851 diff 0; self-compile rc0 48c/48h; final RSS 5-run median 16,152K <= 16,384K; pool 11,965K/type_db 249K). Fixed points recorded c8b87daa/25809d0b/da376da0/d69f10e7 with zero dump-MD5 delta at every fix.
Task 7: docs updated (QUICK_REF seed v93 + self-compile figures; tech_docs 00_shared_infra §2 interner; 03_type_resolution Type 16B; INDEX Table A Type; 04_comptime_eval FoldVal storage).
Task 7: seed rotated v92->v93 (archive md5 3cacdd44df75c0ce96abfd51af93f928 -> 84d295ae04e20c4b722ed219bd9a74f1; CHANGELOG v93 HEAD d69f10e7 fixed point 44b8e7ff...; gen 45c+46h 9803909B).
Task 7: minor (deferred): two Task-4-edited test binaries (test_semantic_bin.zig, test_sym_reg_bin.zig) NOT runtime-verified — build_test.sh 0/9 (zig0 retired) and a direct seed-compiler build both fail on pre-existing semanticAnalyzerInit 8-arg vs 17-arg drift (error[3061]), not on the narrowed Type columns.
Task 7: deferred structures recorded (AST window/value-pool representation, hash-map single interleaved array, one-use retention: classify work arrays + symbol registry).
