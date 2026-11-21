# Task 2 report — D1 emit: composite typedef ordering

Branch `zig1_improvements`. Scope: D1's **emit/ordering half** ONLY (spec `docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md` §2 Bug 2 + Fix 2). T1's identity cache (`type_registry.zig` Optional/Array/`typesEquivRec`) is untouched. T3 (D2/comptime-if) untouched. `examples/torrent_example_defects.md` left dirty (T6 owns it).

## Investigate

Channel pinned with dump evidence **before** any source edit. Pin compiler: `/tmp/d1d2_t1/zig1_5_clean` (behaviorally identical to the pre-edit tree — T1 fix-round 1 was comment/doc-only).

### Pin — the Opt typedef is PRESENT but LATE (ordering, not missing emission)

`/tmp/d1d2_t1/zig1_5_clean -ffast --dump-c89 --output-dir <pre-created dir> repro/mi_matrix/fnptr_opt_aggregate_emit_xmod/main.zig` → rc 0, 6 `.c`. `zig_special_types.h` (816 lines):

| line | text | fact |
|---|---|---|
| `:52-69` | `struct zT_CD1AC90C_Key { … }` | Key's FULL def (tagged union payload) |
| `:663` | `typedef zT_ADE98789_Opt_37 (*zT_36EA955F_FP_zT_ADE98789_Opt_)(void*);` | fp typedef **names** `zT_ADE98789_Opt_37` |
| `:770` | `typedef struct { zT_CD1AC90C_Key value; int has_value; } zT_ADE98789_Opt_37;` | the Opt typedef **exists, 107 lines later** |

Coerce fixture, same pin (rc 0, 6 `.c`): fp at `:637` `typedef zT_B1EBCC6C_Opt_23 (*zT_5D2AA370_FP_zT_B1EBCC6C_Opt_)(void*);`, Opt def at `:742-745` — byte-for-byte the T1 probe (637/744) and the spec §2 Bug 2 symptom. Pre-fix gcc then fails `zig_special_types.h:663: expected declaration specifiers or '...' before '*' token` + `unknown type name 'zT_…_FP_zT_…_Opt_'` (NOTES).

**Same-file differential (decisive):** `:490` `typedef zT_39E21528_Opt_63 (*zT_C411D575_FP_zT_39E21528_Opt_)(void*, zT_39E21528_Opt_63);` is correctly ordered **after** its `Opt_63` def (`:96-97`, pointer-payload optional). Identical dispatch, identical relation; the only structural difference is the Opt payload kind (`void*` vs `?Key` aggregate).

### Suspect disposition (brief's two channels)

- **(b) per-kind emit dispatch omits optional/error_union/slice — REFUTED.** `emitTypeDefinition` (`sf/src/c89_emit.zig:1435-1437` in the pre-edit tree) dispatches `slice_type→emitSliceType`, `optional_type→emitOptionalType`, `error_union_type→emitErrorUnionType`; the typedef is literally present in the dump (`:770` / `:742-745`). (The T2-context line "no optional/error_union/slice case visible" at `:1440-1453` is stale — those cases exist.)
- **(a) `typeHasForwardDecl` suppresses the fn-return edge — REFUTED.** `typeHasForwardDecl` (`sf/src/type_registry.zig:1351`) returns true only for exactly-named non-packed `struct`/`union`/`tagged_union`; an `optional_type` falls through to `return false`, so `typeRefEdgeTarget`'s name_pos=1 path keeps the fn→opt edge (`typeNeedsFullDef(optional)=true`, `:1377`). `typeRefsWalk`'s fn arm (`:1504`) already notes `return_type`/params at name_pos=1. The P2 sort order is honest.

### True channel — the 2a/2b sub-pass split overrides `typedef_order` across groups

`emitTypePasses` (`sf/src/c89_emit.zig`) emits Sub-pass 2a (pointer-only) **completely before** Sub-pass 2b (value-embedding), each in carried `typedef_order`. `classifyTypeEmissionGroups` (`sf/src/type_resolver.zig:640-890`) has **no `fn_type` arm and no `slice_type` arm** → both classify `pointer_only` (2a). `?Key` hits `requiresFullDef(tagged_union)=true` (`:627`) → value-embedding (2b). So the fp typedef emits in 2a **before** the Opt in 2b no matter what the sort says. Within-group order holds (the `Opt_63`/`FP` differential above) — exactly the present-but-late shape. Neither `emitTypeDeps` (no fn/slice arm) nor `emitDepMember`'s fn arm / `emitPointeeDep`'s fn arm pulls the fn typedef's return/param spelling deps first. Same channel family covers slice-elem spellings (`Elem*`) and by-value spellings of any 2a type naming a 2b composite.

## Implement

Task-6 `emitPointeeDep` site-patch pattern generalized, one wiring point (`sf/src/c89_emit.zig` only):

1. **`emitTypeDefOnce`** now runs **`emitDefDeps`** after the `seen`-mark and before writing the definition — every typedef's own spelling deps are re-ensured at its emission site.
2. **`emitDefDeps`** (new): the per-kind walk of everything the definition spells — fn return/params and slice elem at **name level** (via the existing `emitPointeeDep`; forward typedefs suffice for named aggregates), optional/EU payload, array/tuple elems, aggregate fields, tagged-union tag and enum backing at **by-value level** (via `emitDepRef`). Flagless fn types (which write no typedef) skip the walk.
3. **`emitDepRef`** (new): by-value completeness closure — pointer refs recurse their chain leaf name-level (`emitPointeeDep`), everything else pulls its own typedef through `emitTypeDefOnce` (recursively pulling that typedef's deps first — `?T`/`E!T` embed their payload by value, so a pulled composite brings its full-def closure).
4. **`kindWritesTypedef`** (new): the `emitTypeDefinition` dispatch set — scalar/void/ptr refs pull nothing (the gated form would wrap empty blocks).

Termination: `seen`-mark-before-recursion (each typedef pulled at most once per pass); ptr chains keep the existing depth cap 16. Battery-safety anchor: on a gcc-valid output every spelled typedef is already emitted before its referrer, so **every pull is a `seen` no-op** — verified empirically by 8/8 pins + markers byte/line-identical below.

- **Not changed:** `type_registry.zig` (the fn-return edge is honest; T1's cache stands), `type_resolver.zig` classification (see C1), analyzer, lowering.
- **Tech doc:** `docs/sf/LIR_C89_Emission_p2.md` §3.1 `[updated: 2026-10-16 …]` note (the changed subsystem's spec).

### Post-fix dump evidence (both designed flips)

| fixture | pre-fix | post-fix (`/tmp/d1d2_t2/zig1_5_clean`) |
|---|---|---|
| `fnptr_opt_aggregate_emit_xmod` | fp `:663` before Opt `:770`; gcc FAIL | Key `:62` → Opt_37 `:661-664` → fp `:667`; all 6 `.c` gcc-clean (binding flag-set) |
| `fnptr_opt_aggregate_coerce_xmod` | fp `:637` before Opt `:742-745`; gcc FAIL | Opt_23 `:635-638` → fp `:639-642`; all 6 `.c` gcc-clean |

`bash scripts/stdlib/run_fixtures.sh --capture … <both fixtures>` → `run_fixtures: 2 PASS / 0 FAIL`; goldens written: emit `expected.txt`=`fnptr emit ok\n`/`expected.rc`=`0`, coerce `expected.txt`=`coerce sigint ok\n`/`expected.rc`=`0` (3× deterministic inside the harness) — both exactly the fixtures' documented GREEN contracts (main.zig headers). Coerce `expected.rc` flipped `2`→`0` at capture (runtime golden supersedes the RED dump-rc census; `expected_error.txt` remains the committed RED record, pre-fix values in git history — C3).

## Runtime battery

Gate compiler `/tmp/d1d2_t2/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t2`. Sequential runs (spill-file race). Every claim = command + observed output.

### 1. Seed two-hop
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t2
→ [seed] hop2 binary md5: 6e6d1262e4a286486d2f478961fbd040
  [seed] two-hop closure OK: hop1 == hop2 == 6e6d1262e4a286486d2f478961fbd040
```
**MATCH** (closure held). Fixed point moved (expected — `sf/src` changed): `69cf0269933a8b943453fa7bce0e25cc` → **`6e6d1262e4a286486d2f478961fbd040`** (old→new recorded; seed rotation stays closeout-owned).

### 2. Corpus classify (post-T0 1130-line gate)
```
bash scripts/corpus/classify /tmp/d1d2_t2/zig1_5_clean /tmp/d1d2_t2work/corpus_t2.txt
→ wrote …: 1130 dirs
frozen 1124 subset (6 designed fixture lines removed): md5 518eca1a9b5d3e1cc5a48abce214abd8
  byte-identical to T0 anchor 518eca1a9b5d3e1cc5a48abce214abd8 (diff empty) → 0 movers
tally: 954 OK / 58 GREEN / 118 FAIL / 0 ICE / 0 CRASH (T1 was 952/58/120)
```
**Frozen 1124 class-identical, 0 movers.** Designed 6 lines — **exactly two movers, both designed NEW-fixture flips**:

| fixture | T1 | T2 | designed? |
|---|---|---|---|
| `fnptr_opt_aggregate_coerce_xmod` | FAIL | **OK** | **YES — T2 flip (FAIL→OK)** |
| `fnptr_opt_aggregate_emit_xmod` | FAIL | **OK** | **YES — T2 flip (FAIL→OK)** |
| `iswindows_deadarm_errunion_xmod` | FAIL | FAIL | unchanged (T3) |
| `iswindows_deadarm_prune_xmod` | OK | OK | unchanged (T3) |
| `conditional_import_if_xmod` | FAIL | FAIL | unchanged (T4) |
| `conditional_import_switch_xmod` | OK | OK | unchanged (T4) |

### 3. Goldens 5/5
Build (QUICK_REF recipe): `zig1_5_clean --dump-c89 <ENTRY> > g.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include g.c zig_runtime.c zig_pal.c -o g` — all 4: dump rc 0, gcc rc 0, 0 `error:`.

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` rc 0 | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | **YES** |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` rc 0 | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | **YES** |
| json | `cd examples/z98/json_parser && timeout 60 …/json` rc 0 | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | **YES** |
| mud server | `bash examples/z98/mud_server/demo/session.sh …` rc 0 | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | **YES** |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | **YES** |

**5/5 MATCH.**

### 4. mi_matrix frozen-25 + oob trap
```
bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_t2/zig1_5_clean <T0 §3.4 frozen 25 by name>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
**25/0 MATCH** (same explicit 25-name list as T1 §4). oob trap `slice_index_field_store_oob_xmod` (`-fsafe -o`, build_target): dump rc 0, 6 `.c`, build rc 0, run **rc 133** (Trace/breakpoint trap), stdout 0 B md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` (rc pin `133`). **MATCH.**

### 5. Examples 26/26 build + 26/26 run
Build per dir (`zig1_5_clean -ffast -o <out> <entry>` + `sh build_target.sh linux <out>/prog`, CWD out-dir): **26/26 OK** (dump rc 0, ≥1 `.c`, build rc 0). Run (CWD=**example dir**, `timeout 25`, mud `timeout 8`, stdin `/dev/null`, rogue* fed `q\n`): **26/26 correct** — every stdout md5 == T0 §3.5 table: days_in_month `8c0d394c…`, fibonacci `b53b3a3d…`, func_ptr_return `f6a54779…`, gol `fcbf7e7c…`, heapsort `8cf0a784…`, hello `74630882…`, json* `8bda3d5a…`×2 / `dc22fa47…`, lisp* `1c1f0a41…`×4, lzw `c3c7765e…`, mandelbrot `d5966775…`, mud rc 124 `9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`, rogue* `3fb6709e…`×2, sort_strings `c6c047cb…`, tco `264ea6b1…`/`3d70c50b…`/`7421137a…`, z9torr rc 1 `f666af15…`, z9play rc 1 `f35b7ef7d832cc4a…`. **26/26 MATCH.** (Method note: a first run-loop iteration forgot CWD=example-dir and produced divergent json md5s (`7c36adb3…`/`8c7b48aa…` — `test.json` not found from the repo root); re-run per the recorded recipe matched the table on all 26.)

### 6. Stdlib
```
bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_t2/zig1_5_clean
→ run_fixtures: 285 PASS / 0 FAIL over 285 dirs
  STDLIB GATE OK
```
**285/0 MATCH.**

### 7. The 8 `--dump-c89` pins (old→new)
`zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum` (repo root):

| entry | `-fsafe` old→new | `-ffast` old→new | delta |
|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` → same | `fa346108ed00d03a037c2f9331d3bdf8` → same | **0** |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` → same | `01a4e2265b33c97a8ca6ff3dfa551231` → same | **0** |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` → same | `e3970e33ac09c8dfaa316d2d69bf61ec` → same | **0** |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` → same | `24e0e812e7dffa5a43750135405ffe3f` → same | **0** |

**old→new: 8/8 UNCHANGED, pin delta count 0** — the no-op-on-valid-output property held exactly (these programs' emission needed no pulls). T1 C4 (in-place completion + structural fn_type comparison) also stayed corpus-unexercised for the pins.

### 8. Markers telemetry
```
zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin
→ marker_lines=3437 bytes=38384
top prefixes: 2005 INT / 423 DC / 310 FE (=241 FE:p + 69 FE:) / 195 P / 195 FWD / 122 RaD / 86 MT
```
**3437 lines / 38384 B — identical to T0/T1 baseline** (no marker drift; ET/CLS marker writes are compile-time-disabled `g_markers_debug=0`, same as at T0/T1).

### 9. Runtime goldens at the fixture flips
Captured (item 2 §Implement): emit + coerce `expected.txt`/`expected.rc`, GREEN contracts exact, `run_fixtures.sh --capture` 2 PASS (3× deterministic). No pre-existing corpus fixture moved (item 2).

### 10. Battery summary table

| gate | T0/T1 frozen | T2 observed | verdict |
|---|---|---|---|
| seed two-hop | `69cf0269933a8b943453fa7bce0e25cc` | hop1==hop2==`6e6d1262e4a286486d2f478961fbd040` | closure OK; fixed point moved (recorded) |
| corpus frozen 1124 | md5 `518eca1a9b5d3e1cc5a48abce214abd8` | byte-identical `518eca1a9b5d3e1cc5a48abce214abd8`, 0 movers | MATCH |
| designed 6 fixture lines | coerce FAIL, emit FAIL | coerce **OK**, emit **OK**, 4 others unchanged | 2 designed flips recorded |
| goldens | 5/5 | 5/5 identical | MATCH |
| mi_matrix 25 + oob | 25/0 + rc 133 | 25/0 + rc 133/empty `d41d8cd9…` | MATCH |
| examples | 26/26 + 26/26 | 26/26 build + 26/26 run correct | MATCH |
| stdlib | 285/0 | 285/0 STDLIB GATE OK | MATCH |
| 8 pins | == QUICK_REF table | 8/8 unchanged (delta 0) | MATCH |
| markers | 3437 lines / 38384 B | 3437 lines / 38384 B | MATCH |
| fixture runtime goldens | unreachable pre-fix | captured for both flipped fixtures | recorded |

## Concerns

- **C1 (classification soundness gap — masked, not fixed):** P4's `pointer_only` walk (`type_resolver.zig:640-890`) ignores `fn_type`/`slice_type` name-spelling refs (and the wp propagation covers only optional/EU field kinds), so the 2a/2b split remains unsound in general; the emit-site closure now compensates at every typedef site. A future cleanup should redefine `pointer_only` over the full name-ref relation (or merge 2a/2b and trust `typedef_order`) — that is a P4-classification change with output-reordering blast radius, out of T2 scope. Cost if wrong: none today (site-patch covers emission); a classification edit could re-move pins.
- **C2 (relation gap: carriers, latent):** `typeNeedsFullDef` omits `i64_type`/`u64_type`/`f64_type`, so the sort carries no edge for carrier-name spellings (`?i64`, fn-returning-carrier, enum backing) — tid-luck ordering pre-fix. The site-patch now pulls those spellings at emit sites (enum backing + optional payload included), so emission is covered; the `typeRefs`/resolver-graph gap itself is unchanged (T2 made no `type_registry` relation edits). Close with a relation audit if a repro appears.
- **C3 (coerce RED census superseded):** `run_fixtures.sh --capture` overwrote `fnptr_opt_aggregate_coerce_xmod/expected.rc` `2`→`0` (runtime golden now the fixture's gate), per the fixture NOTES' T2 capture ruling. `expected_error.txt` stays the committed RED diagnostic census; the pre-fix `expected.rc=2` remains in git history. If the controller wants the RED dump-rc census preserved as a live file, it needs a separate record (e.g. NOTES table row).
- **C4 (cyclic name-level fn typedefs):** `emitDefDeps` terminates via seen-mark-before-recursion + depth cap 16; a layout-impossible name cycle (`fn` typedefs spelling each other, or `struct { f: fn (*void) ?Self }` which C89 cannot express — Opt embeds S by value) would emit invalid C rather than hang (pre-existing class; the validator/depth-cap philosophy is unchanged).
- **C5 (shared-header placement):** on currently-broken shapes a pull may write a non-shared dep into the shared header early — C-valid (the `#ifndef` gates + per-module re-emit idempotent), placement-only. No byte change on valid programs (proven: 8/8 pins + markers identical).
- **C6 (design-spec wording drift, informational):** spec §2 Bug 2's suspect list ("`typeHasForwardDecl` suppressing the edge" vs "the per-kind emit dispatch omits optional/error_union/slice") does not include the actual channel (the pointer-only/value-embedding sub-pass split + missing fn/slice spelling deps at emit sites); both named suspects were refuted repro-driven (Investigate). Fix 2's normative contract ("every composite typedef … ordered before every spelling reference") is what was implemented. T6 may want a defect-record footnote; `examples/torrent_example_defects.md` not edited here (T6 owns it).
