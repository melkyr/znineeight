# SDD ledger — plan: docs/superpowers/plans/2026-10-12-zig1-emitter-sanitization-plan.md

Session: agent Zni-005, 2026-10-12. Branch `zig1_improvements`, BASE `f96e1206280938d3a35ed98e6a7318e2439931e6`. Binding spec: `docs/superpowers/specs/2026-10-12-zig1-emitter-sanitization-design.md`. Base seed v97 (`bafbba9454cd2b134bdc3d50c65384e0`).

## Authority (operator, binding — 2026-10-12)
- Plan is the sole authority. If the plan says A, do A. If any better X/Y surfaces, or any issue/confusion/unforeseen divergence arises: STOP and present. No corner cuts, no unrelated fixes, nothing outside the plan.
- Source edits only via `edit`/`fastedit` (AGENTS.md X.7: re-read region before every edit; bottom-to-top for multi-edits; INSERT = replace anchor line with [new content + original anchor line]).
- Compression during this build session is FORBIDDEN (overrides system compression reminders).
- GIT HARD RULE: no push; no `git reset --hard/--keep`, `git checkout --`, `git restore`, `git clean`, `git stash drop/clear`, force-push, history rewrite. Only `git commit --amend` on own just-created commit.
- Reports/ledger under this workspace dir, committed via `git add -f`.
- Ruling: SDD skill's "rulings, not stalls" default is overridden by the operator's STOP-present rule — any real ambiguity stops the run and surfaces to the operator instead of a controller ruling. Cost if wrong: none (stricter than the skill).

## Preflight conflict scan (controller, before Task 1/P1)
Rows for every task pair sharing a file or interface, and per-task self-consistency:

| Pair / task | Shared surface | Produce → consume | Finding |
|---|---|---|---|
| P1 ↔ P3 | synthetic type-name minting (`c89_emit.zig:897/:931/:940`) | P1 routes emitter name sites through the minter; P3 makes `typeCName` the single derivation ("synthetic names minted here, once") | Overlap is real but ordered: P1 revives the minter, P3 relocates the derivation and closes D2 residue. Plan text itself sequences P1 then P3 ("Closes D2 residue"). No contradiction. |
| P1 ↔ P6 | struct field names | P1 = single C-identifier minter (incl. struct fields); P6 records "field ordinal/name" on LIR for the emitter to read | Interface reading: P6 carries the semantic/raw name; minting still goes through P1's authority (P1 "minting every emitted C identifier"). Consistent; if an implementer finds the plan demands otherwise → STOP-present. |
| P2 ↔ P3 | `type_registry.zig` | P2 adds `typeRefs`/`typeNeedsFullDef`; P3 adds `typeCName` | Distinct functions in one module. Compatible. |
| P2 ↔ P4 | emitter type-emission paths | P2 rebuilds typedef ordering (`tstTopologicalSort`/`tstEdgesWalk` from `typeRefs`); P4 removes `computeSharedSet`/`shouldSkipTypeEmission` | Adjacent regions of the same emission loop; order between them is fixed by Task 0 Step 3. No textual contradiction. |
| P2 ↔ P5 | `type_registry` predicates | P5 exposes canonical int-kind/scalar/pointer predicates; P2's `typeNeedsFullDef` may consume them | Compatible; Task 0 order decides whether P5 precedes P2. |
| P6 ↔ P10 | `sf/src/lower.zig` | P6 records field ordinal/name, temp types, etc. on LIR; P10 unifies checked address-taking + adds the `-fsafe` root-index check to the `lowerFieldStore` index arm | Same file, distinct mechanisms; P10 is declared the D5-residue closer while P6 removes emitter re-resolution. Independent. |
| P7 ↔ P8 | `sf/src/semantic_analyzer.zig` | P7 module-scope-first type-name resolution (roots D7); P8 builtin arity/descriptor table (roots D6) | Same file, disjoint subsystems. |
| P1 ↔ P2 | `c89_emit.zig` naming vs ordering | P1 names; P2 orders typedefs | Disjoint mechanisms. |

Per-task self-consistency: every increment gates on the §1 runtime battery (defined once in Global Constraints); P7 adds a `Mode`-collision reproducer, P8 adds arity reproducers — consistent with their text. Dead-code deletions mandated by the plan (`typeResolverGetSorted`, `name_mangler` stub usage, `isValueDependency`, divergent `c89NeedsEmitEdge`) are plan-required, not review defects. Task "Tasks P1–P10" executes in the order Task 0 Step 3 records (the plan's bullet order is a catalog, not the execution order). SDD's batch-same-shape shortcut does not apply: the plan mandates one responsibility per increment, one compiler-moving commit each — one dispatch per increment.

Scan verdict: no plan-contradicting-plan conflicts. Proceeding.

## Progress
Task 0: dispatched (implementer A0) — brief `task-0-brief.md`, report `task-0-report.md`.
Task 0: **DONE_WITH_CONCERNS** (implementer A0, 2026-10-12). Baseline frozen; inventory complete; P1–P10 execution order fixed below. Full evidence: `task-0-report.md`. No `sf/src` change; seed untouched.
Task 0 fix round 1: **DONE** (2026-10-12). Findings closed: (1) mi_matrix runtime-anchor set broadened to the full defined set 25+oob, 25/25 MATCH goldens; (2) cite corrections `mangleTempName:3195`/`typeIdName:5530`/`intTypeNeedsWidthWrap:4722` — brief cites exact, NO drift; (3) full stub grep + `strip_main.zig:2-3` delete-set row; (4) `diff`/`md5sum`/`cmp` evidence shown. Evidence: report `## Fix round 1`. No `sf/src` change; seed untouched.

## Task 0

**Frozen baseline** (command -> exact observed value; compiler `/tmp/task0_work/seed/zig1_5_clean` md5 `bafbba9454cd2b134bdc3d50c65384e0`):

| command | observed |
|---|---|
| `FIXED_POINT_MD5=bafbba9454cd2b134bdc3d50c65384e0 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/task0_work/seed` | `hop1 binary md5: bafbba9454cd2b134bdc3d50c65384e0` / `hop2 binary md5: bafbba9454cd2b134bdc3d50c65384e0` / `two-hop closure OK: hop1 == hop2` / `recorded fixed point OK` |
| `bash scripts/corpus/classify /tmp/task0_work/seed/zig1_5_clean /tmp/task0_work/corpus_baseline.txt` | `wrote …: 1124 dirs`; tally `950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH` (per-dir list = report Appendix A, verified byte-exact; +2 vs D6's 1122 = `examples/z98/z9play` + `repro/mi_matrix/stdlib_math_f64_xmod`, both OK; FAIL/ICE/CRASH unchanged) |
| `timeout 120 gold/gol` (100 gens) | stdout md5 `fcbf7e7cead5082f0a8caadd5a8f0ff9` = QUICK_REF |
| `printf '(+ 1 2)\n' \| gold/lisp` | stdout md5 `b3d9f8974da24ddbf9d389f3d7d97322` = QUICK_REF |
| `gold/json` (CWD `examples/z98/json_parser`) | stdout md5 `8bda3d5a1ec07d14a301bc343df32bf8` = QUICK_REF |
| `bash examples/z98/mud_server/demo/session.sh gold/mud srv.out cli.out` | server md5 `66c8f0abb926cca7baf9a0d1692ab318` / client md5 `93147d0f0bbd983a9d844fea8b7a6fa7` = QUICK_REF (session rc=0) |
| `zig1 -ffast -o <out> <entry>` + `sh <out>/build_target.sh linux` + run, all `examples/z98/*/` | **26/26 build rc=0; 26/26 run correct** (mud_server rc=124 timeout documented; z9play/z9torr rc=1 usage documented; table report §1.4) |
| `bash scripts/stdlib/verify_stdlib.sh /tmp/task0_work/seed/zig1_5_clean` | `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK` (was 284 at D6; +1 = stdlib_math_f64_xmod) |
| `<zig1> <mode> --dump-c89 <ENTRY> \| md5sum` (8 pins, current lib/) | mud `498b90f191b544655a1b731ef480709d`/`50dbf5f02c1a5de920e158cab7f2f29b`; gol `52c5feb5f158e2af7b32a0509b43d4c6`/`7271960fc6375ed1dee34b7abfb6325b`; lisp `e6f96b81f00e678eeaaa1ea7ed7c2359`/`ec82996028671a52a0a3d52ad307edf1`; json `48eedfc0243431693f65518646ad280c`/`04124b2675e77020933cbfab20f883e1`. **8/8 differ from the QUICK_REF table; root cause proven 8/8** (z9play-M2 `std_math.zig` 54->402 lines post-dates the table; swapping the v97-era `std_math.zig` into `lib/` reproduces the table exactly 8/8 — see report §1.6). Pins recorded, not gated. |
| `zig1 --markers --dump-c89 examples/z98/game_of_life/main.zig 2>mk; grep -ac '^' mk` | 3,241 marker lines / 36,038 B (top: INT:new 1810, DC:k 423, FE:p 240) |
| mi_matrix runtime anchors — **SET DEFINITION (load-bearing)** = all non-stdlib `repro/mi_matrix/*/` with committed goldens, non-empty `expected.txt` + `expected.rc=0` (**25 dirs**, enumerated) + D-fix trap subset `slice_index_field_store_oob_xmod` (empty `expected.txt`, `expected.rc=133`, `-fsafe`). Reject-census dirs with only `expected.rc` (37, no `expected.txt`) are NOT runtime anchors (corpus classify owns them). Run recipe = `scripts/stdlib/run_fixtures.sh` harness (`zig1 -ffast -o` + build_target.sh + 3x run vs golden). | **25/25 MATCH** (stdout md5 == expected.txt + rc==expected.rc each; e.g. `slice_index_field_store_xmod` `9/11/22/ok` md5 `c11ad986cc71be4250c4b4e3e4d801f5`) + oob rc=133/empty MATCH; sibling prints (NOT anchors) `union_keyword_tag_xmod` `P=.{ .int = 7 }`/`3`, `slice_of_slice_xmod` `11`, `async_frame_structret_xmod` `5` green. Full per-fixture table = report §1.8 / Fix round 1 |

**Inventory:** full smell inventory (spec §3 categories 1–7 + 5 survey extras) in `task-0-report.md` §2, with current `file:line` per item, upstream owner, risk/effort; dead-code claims VERIFIED (grep evidence report §2.8, full outputs incl. `strip_main.zig:2-3` stub imports + `:6-7` discard — all in P1's delete set): `typeResolverGetSorted` DEAD (def `type_resolver.zig:889`, 0 callers), `isValueDependency` DEAD (def `type_registry.zig:980`, 0 callers), `ctx.name_mangler` WRITE-ONLY (`main.zig:333` write, never read). **NO line drift in §3** (fix round 1: round-0's `3194`/`5529`/`4723` cites were wrong; truth = `mangleTempName:3195`, `typeIdName:5530`, `intTypeNeedsWidthWrap:4722`, grep-verified; brief cites exact). Spec §3.2 drift: `fn_type` now present in `c89NeedsEmitEdge`, missing only in resolver predicates; `packed_union` missing only in the emitter edge predicate.

**ORDERED P1–P10 (execution order — this governs Tasks P1–P10; the plan's bullet order is a catalog, NOT the order). No splits/merges.**

1. **P5 Predicates + promotion** — foundation; no inbound deps; membership-preserving; its canonical predicates are consumed by P2/P3; smallest blast -> validates the per-increment battery early.
2. **P1 Identifier authority** — hard prerequisite of P3 (synthetic names) and P6 (field/temp names via the authority); roots D1/D2; most-consumed foundation.
3. **P2 Type-reference relation + ordering** — consumes P5 predicates; deletes dead `typeResolverGetSorted`/`isValueDependency`, replaces divergent `c89NeedsEmitEdge`; roots D8; precedes P3/P4 (both build on the settled relation/ordering).
4. **P3 Canonical `typeCName`** — hard-depends on P1 (plan sequences P1->P3); on P2's stabilized `type_registry` surface; closes D2 residue (`:2428` write-back removal).
5. **P4 Single classification pass** — consumes resolver classification over the ordering machinery P2 just rebuilt (adjacent emission-loop regions; classification lands on settled ordering).
6. **P6 Lowerer carries decisions** — after P1 (names) + P3 (`typeCName`); removes emitter re-decisions; its LIR records are the substrate P9/P10 consume.
7. **P10 Lvalue unification** — after P6 (LIR field decisions exist; avoids re-touching `lower.zig` lvalue paths); closes live D5-residue `-fsafe` gap; gated by `slice_index_field_store_*` confirmers.
8. **P9 Structural frame-save rule** — after P6's temp typing (the "declared temps" source); roots D3/D4; guards `nest_inl:3827-3828`, replaces `d4_*` flags; async confirmers in baseline.
9. **P8 Builtin arity/descriptor table** — reject-only D6 root-cause; expected corpus-class movers (declared green-guards + arity reproducers) isolated in the behavioral band; additive table lands on `semantic_analyzer.zig` before P7.
10. **P7 Front-end module-scope-first name resolution** — deepest behavioral change (D7 root-cause); last with the battery battle-tested + `Mode`-collision reproducer; second `semantic_analyzer.zig` move (no interleaving with P8).

**Bands:** 1–6 behavior-preserving relocators (pins recorded old->new); 7–8 runtime root-causes (runtime confirmers frozen); 9–10 accept/reject behavioral (declared movers). Every increment runs the full runtime battery (§1 baseline = the anchor).

**Concerns:** C1 QUICK_REF 8-pin table stale vs current `lib/` (std_math post-D6; re-baseline at Task C); C2 corpus/stdlib counts +2/+1 (new fixtures, classes clean); C3 spec §3.2 `fn_type` sentence stale; C4 (CORRECTED fix round 1) round-0 cite errors `3194`/`5529`/`4723` fixed to `3195`/`5530`/`4722` — brief cites were exact, NO drift; C5 matrix CLI usage/timeout behaviors documented (z9play/z9torr rc=1, mud rc=124); C6 (fix round 1) mi_matrix anchor set broadened from the round-0 D-fix-only narrowing to the full defined set (25+oob) — 25/25 MATCH at baseline; later increments keep the WHOLE set green.
Task 0: fix round 1/5 (4 addressed, 0 open — mi_matrix 25-fixture anchor set + inventory cite corrections; commits f7c7865e..d743468b)
Task 0: deferred minor (fix-diff nit): task-0-report.md:1686-1688 F3 oob transcript block not literally executable as one unit (observed values self-consistent; rc=133 + empty-md5 match goldens)
Task 0: deferred minor (out-of-scope): task-0-report.md:336 §2.1 struct-field row parenthetical "(brief 468/513/524/558 exact)" on a row citing only :468/:513/:558 — cosmetic
Task 0: deferred minor: inventory "upstream owner" column sometimes names the owning increment rather than the upstream stage (review round-0 Minor 5)
Task 0: deferred minor: P5→P2 dependency justification overstated (P2 consumes kind/structure predicates, not P5's int-kind/scalar set) — order still coherent on risk grounds (review round-0 Minor 6)
Task 0: complete (commits f96e1206..d743468b, review clean)
Task P5: dispatched (2026-10-12) — brief `task-P5-brief.md`, report `task-P5-report.md`; exec order 1/10 (Predicates + promotion centralized)
Task P5: DONE (2026-10-12). 8 canonical `type_registry` predicates exposed + `coercion.coercionUsualArithPromote`; emitter truth tables (9 fns) deleted, 24 call sites rewired + promotion delegated; tech docs 03/05/08/INDEX updated. Full runtime battery green: corpus class UNCHANGED (per-dir list byte-identical to Appendix A, md5 518eca1a…), goldens 5/5, mi_matrix 25+oob MATCH, examples 26/26 build+run, stdlib 285/0 STDLIB GATE OK; hop1==hop2 with fixed point bafbba9454cd2b134bdc3d50c65384e0 -> e81d9266955caaad6873fb728d7f494e (moved, recorded old->new); 8 dump pins delta 0/8 (recorded old==new); markers UNCHANGED 3,241 lines / 36,038 B. Full evidence: `task-P5-report.md`. Seed NOT rotated.
Task P5: complete (commits `refactor(c89_emit): P5 — predicates + promotion centralized` + `docs(sdd): P5 report`)
