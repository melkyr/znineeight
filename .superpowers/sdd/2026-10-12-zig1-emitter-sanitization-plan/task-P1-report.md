# P1 report — Identifier authority (execution order 2/10)

Implementer: P1 implementer, 2026-10-12. Branch `zig1_improvements`, BASE `fd63c77a` (P5 report HEAD). Spec: `docs/superpowers/specs/2026-10-12-zig1-emitter-sanitization-design.md` §1/§3 cat 1/§4 row/§5 P1. Brief: `task-P1-brief.md`. Comparison anchors: `progress.md` `## Task 0` (frozen battery) + `task-0-report.md` §1 / Appendix A / §2.1. P5-validated fixed point before P1: `e81d9266955caaad6873fb728d7f494e`. Seed NOT rotated (controller resolution 3).

## Investigate

(Written before any source edit, per the brief. Census + precise edit plan as approved by the controller.)

### 0. Drift check vs plan cites (re-derived before editing)

P5 added 1 import line near `c89_emit.zig:28` (net +1 above ~4300) and deleted 63 lines at `:4394` (-9), `:4709` (-19), `:4892` (-35). Every brief cite re-derived by function name at HEAD `fd63c77a`:

| brief cite | entity (truth) | brief line | current line | drift |
|---|---|---|---|---|
| `:93` | `NameMangler` struct | 93 | 94 | +1 (P5 import) |
| `:657` | `nameManglerMangle` collision loop | 657 | 658 | +1 |
| `:2091` | struct-field raw decl `emitStructType` | 2091 | 2092 | +1 |
| `:468/:513/:524/:558` | `resolveFieldAccess` raw/else arms | 468/513/524/558 | 469/514/525/559 | +1 each |
| `:577/:594` | `mangleC89Keyword` / `cUnionMemberName` | 577/594 | 578/595 | +1 |
| `:2431` | `mangleLocalName` | 2431 | 2432 | +1 |
| `:3195` | `mangleTempName` | 3195 | 3196 | +1 |
| `:897/:931/:940` | `syntheticTypeName`/`sliceElementName`/`getCTypeName` | 897/931/940 | 898/932/941 | +1 |
| `:2795` | `moduleQualifiedName` | 2795 | 2796 | +1 |
| `:5530` | `typeIdName` | 5530 | **5468** | **-62** (+1 import, -9@4394, -19@4709, -35@4892) |

Task 0 fix-round-1 "brief cites exact, no drift" held at `f96e1206`; P5 shifted them (drift fully accounted for above). No plan-text divergence. `sf/src/name_mangler.zig` (stub) and the emitter-internal `NameMangler` are untouched by P5, as the brief states.

### 1. Census — every emitted-C-identifier mint in the 10 kinds

**fn (kind 0 `F_`)** — `nameManglerMangle(...,0,mod)` at `:2559` (sig), `:2594` (fwd-decl), `:3069` (`emitMainWrapper`), `:3171` (`__module_init`), `:5406` (`stdFmtSourceSymbol`), `:8034` (`call_direct`), `:8168`, `:8707`. **Hard boundary (verified)**: `is_extern==1` paths override with the raw source name (`:2559-2560`, `:2595-2596`, `:8036`) — extern/PAL/runtime symbols keep exact C names. Mint-then-override pattern preserved verbatim (the mint's collision-map registration is part of the frozen emission state; the emitted extern bytes remain exact).

**global (kind 1 `G_`)** — `nameManglerMangleGlobal:739` (extra minter entry point, Task 0 §2.1) at `:2864`, `:2889`, `:7378`, `:7384`, `:9071`.

**type (kind 2 `T_`)** — `getCTypeName` (`:956/:963/:980/:988/:1095 EU_/:1145 FP_/:1163 ES_/:1166/:1169`), `syntheticTypeName:921`, `sliceElementName:937`, decls `:1955/:1975 TU_/:2062/:2109/:2307/:2334/:2343/:2352`, `:4305/:7783`.

**local** — `mangleLocalName:2432` (escape-only, no collision), calls `:2543` (params), `:3641`, `:6582` (`resolveTempName`), `:7112/:7115/:7175/:7196/:7282/:7312/:7419/:7477` (`emitInst`), `:9116/:9178` (`emitFunctionBody`).

**temp** — `mangleTempName:3196` (`zT_<id>`), calls `:3781/:3890/:3938/:6588`.

**union-member** — `cUnionMemberName:595` (escape, **no collision check** = D1 concern 2), calls `:321` (`emitFieldAssign`), `:436` (`emitVariantFieldPayload`), `:478/:525/:559` (`resolveFieldAccess`), `:2043` (TU decl), `:2134` (union decl), `:6307` (printer TU access).

**struct-field (RAW — the D1 latent class)** — `:2092` (decl) + access `:469` (addr-of struct), `:514` (ptr->struct), `:525`-else (ptr->packed_union), `:559`-else (value struct/packed), `:321`-else (`emitFieldAssign`), **plus `:6221` (`emitAggPrinterDef` `v.<fname>`) — a sibling the plan list missed**. All routed.

**synthetic-type** — `syntheticTypeName:898` (pure 3-part rule; callers `:998/:1010/:1065/:1074/:2155/:2385`), `sliceElementName:932`, and the ad-hoc builders inside `getCTypeName:941`: `EU_` `:1078-1096`, `FP_` `:1098-1146`, `ES_` `:1148-1165`, plus the `TU_` builder `:1963-1975`. **P1/P3 seam (disclosed):** composition of type-structure -> name-material is P3's `typeCName` residue ("P3 later closes the full typeCName residue"); P1 owns the mint tail (every final identifier is produced by `name_mangler.zig`).

**module** — `moduleQualifiedName:2796` (base+fnv1a+hex stem; callers `:2954` includes, `:9276` build scripts, `main.zig:1458` output filenames). Registry lookup stays in the emitter; the pure stem rule moves.

**printer** — `typeIdName:5468` (prefix+decimal; callers `:5487/:5500/:5699-5726`) + `aggPackedScratchName:5559` (`zT_pkf<idx>` — sibling, same rule) + `stdFmtSourceSymbol:5403` (kind-0 mint). All routed.

**Not mints (census'd, unchanged):** `#define` composites (`zTU_*_*`, `ERROR_*`, enum macros — prefixed, keyword-safe by construction), include/ctype guards, fixed ABI designators (`tag`/`payload`/`_dummy`/`_0`/`.ptr`/`.len`/`._N`), `zT_main_result` literal in `emitMainWrapper`, C `main` entry, extern names (hard boundary).

**Dead-stub delete set (verified current lines):** `main.zig:10-11` (stub import + type alias), `:104` field, `:206` no-arg init, `:333` write; `main_dump.zig:10-11`, `:60` field; `strip_main.zig:2-3`, `:6-7` discard; `name_mangler.zig:1-7` (stub body). Task 0's lowercase `name_mangler` grep missed the `:11` `NameMangler` alias lines — deleted same-class (stated here, in the delete list).

### 2. Authority design (approved)

`sf/src/name_mangler.zig` becomes the sole minter. Moved verbatim (so `sf/src/tests/test_name_mangle_bin.zig` keeps passing via `c89_mod.*` — kind 3 included): `NameMangler`, `writeHex`, `isTempOrBuiltin`, `isC89Keyword`, `mangleC89Keyword`, `nameManglerPopulateKeywords`, `nameManglerInit`, `nameManglerMangle` (incl. the kind-`L` branch), `nameManglerMangleGlobal`, `syntheticTypeName`, `mangleTempName`, `typeIdName`, `moduleQualifiedName`'s stem rule. New per-kind mints (raw rule = keyword escape `z_` + **per-scope** collision `_N` on the candidate):

- `nameManglerMintLocal(mangler, name_id, scope)` / `nameManglerMintField` / `nameManglerMintMember` — shared raw rule; scope = fn scope for locals, owning **tid** for fields/members. Escape-collision (`int` vs `z_int` in one scope) resolved deterministically (first-mint keeps the candidate, later mints get `_N`).
- `nameManglerFnScope(mangler, fn_name_id, fn_module_id) u32` — deterministic fn scope key (interned `module_id + "_" + name_id` pair; the key value is only a map-partition token — the minted strings depend on the grouping, not the key value). Threading: new `emitter.current_fn_scope` set wherever `current_fn` is set (`:3214`, `:9055`); `emitParamList` gains a scope param (callers `:2581/:2603` pass `nameManglerFnScope` of the fn).
- `nameManglerMintTemp` / `nameManglerMintSyntheticType` / `nameManglerMintIndexName` / `nameManglerMintModuleStem` — moved pure rules (byte-identical strings).

**Determinism argument:** hash-mangled collision state = existing `nameManglerMangle` order (call order unchanged by the move). Raw-kind occupancy is per-scope; within a scope mint order is a pure function of the program (params then `decl_local`s per fn — `emitFunctionSet` order; fields in declaration order before any access — type emission precedes body emission). Same input -> same names in every compilation -> self-emission `hop1==hop2` preserved. **Self-emission byte-identity proof:** sf/src has exactly one keyword local (`lir_opt_pass.zig:1873` `signed` — escaped identically), zero keyword fields/members (grep over `sf/src`), zero `z_<keyword>` pairs (no escape-collisions); all other rules move verbatim -> names unchanged; only the module split (bigger `name_mangler.zig` .c, smaller `c89_emit.zig` .c) moves the fixed point (P5-class).

**D1 semantics:** struct/packed fields now escape (`int`->`z_int`) + collision-checked — the latent class F1 missed. Prior F1 behavior for union tags preserved exactly (`z_int`). No corpus program has a keyword-named struct field (grep over repro/stdlib_test/examples/sf/src) -> predicted **no FAIL->OK class mover**; if one appears, STOP-present per the brief.

**P1/P3 seam (disclosed):** `EU_`/`ES_`/`FP_`/`TU_` name-material **composition** stays in the emitter (P3 moves the whole derivation to `type_registry.typeCName`); every one of those names is finalized through `nameManglerMangle` (the authority) — no identifier of the listed categories is produced outside `name_mangler.zig` after P1. `sliceElementName`/`getCTypeName`/`moduleQualifiedName` remain emitter-side derivations calling the authority.

**Compat surface (disclosed, within touch set):** `c89_emit.zig` keeps 4 thin `pub` forwarding exports (`NameMangler` const alias + `nameManglerInit`/`nameManglerMangle`/`nameManglerMangleGlobal` wrappers) so `main.zig:1197-1199` and `sf/src/tests/test_name_mangle_bin.zig` (outside the touch set) keep compiling. No minting logic copied — single implementation in `name_mangler.zig`.

### 3. Precise edit plan (touch set confirmed — nothing outside)

1. **`sf/src/name_mangler.zig`** — replace the 7-line stub with the authority (moved block + new raw mints + 3 new `U64ToU32Map` pairs for local/field/member cache+taken).
2. **`sf/src/c89_emit.zig`** — delete the moved defs + `cUnionMemberName`/`mangleLocalName`/`aggPackedScratchName`; rewire all mint call sites to `nm_mod.*`; new `const nm_mod = @import("name_mangler.zig");`; thin `pub` compat exports as above.
3. **`sf/src/main.zig`** — delete `:10-11`, `:104`, `:206`, `:333` only.
4. **`sf/src/main_dump.zig`** — delete `:10-11`, `:60`.
5. **`sf/src/strip_main.zig`** — delete `:2-3`, `:6-7`.
6. **Tech docs** (`[updated: 2026-10-12]` on changed sections): `08_c89_emission.md`, `09_pipeline_orchestration.md`, `INDEX.md`.

Edits via `edit`/`fastedit` only (X.7: re-read region immediately before each edit; bottom-to-top per file; insert = replace anchor line with new content + original anchor line). Z98 §1.3 constructs only; bootstrap-staging §9.4 (moved code is already seed-compilable; new code reuses existing map/itoa/intern patterns).

### 4. Observations (report-only, NOT fixed)

1. `EU_`/`ES_` synthetic names use **reversed** decimal digits (payload 123 -> `EU_321`) — quirky but stable/deterministic.
2. `nameManglerMangle` keyword short-circuit returns `z_<name>` for keyword fn/global/type names before hash-mangling — kinds collapse to one name for keyword identifiers; the collision map suffixes (`_N`) keep them distinct.
3. The 31-char C89 significance limit is enforced only in `nameManglerMangle`; raw-kind names (locals/fields/members) are unbounded (pre-existing).
4. Packed-union member-access arms (`:525/:559/:321` else branches) emit `v.<name>`/`->name` against the opaque `unsigned char _[N]` C model — dead-or-broken path (uniform routing applied; no behavior change for non-keyword names).
5. Macro names (`zTU_*_*`, `ERROR_*`, enum member macros) embed RAW member names — keyword-safe (prefixed) but not routed; a member `int` gives macro `..._int` while the member is `z_int` (cosmetic namespace split).
6. `nameManglerMangle` kind 3 (`L`) is exercised only by the test binary; the emitter's locals use `nameManglerMintLocal` (the authority's raw rule).
7. Frontend rejects local shadowing (`error[3057]`, doc 09) — per-fn raw-name uniqueness holds, which the per-scope collision design relies on for fields too (duplicate field names are a semantic error).

## Implement

### What was changed (diff vs the §3 edit plan)

**`sf/src/name_mangler.zig`** (7-line stub → the minting authority, +430 lines): moved verbatim `NameMangler` struct, `writeHex`, `isTempOrBuiltin`, `isC89Keyword`, `mangleC89Keyword`, `nameManglerPopulateKeywords`, `nameManglerInit`, `nameManglerMangle` (incl. the kind-`L` branch), `nameManglerMangleGlobal`, `syntheticTypeName` (→ `nameManglerMintSyntheticType`), `mangleTempName` (→ `nameManglerMintTemp`), `typeIdName` (→ `nameManglerMintIndexName`), `moduleQualifiedName`'s stem rule (→ `nameManglerMintModuleStem`). New: `nameManglerMintRaw` (shared raw rule), `nameManglerMintLocal`/`MintField`/`MintMember`, `nameManglerFnScope`; `NameMangler` gains 3 `U64ToU32Map` pairs (`raw_cache_*`/`raw_taken_*` for local/field/member).

**`sf/src/c89_emit.zig`** (-509/+36 net): deleted the moved defs + `cUnionMemberName` + `mangleLocalName` + `aggPackedScratchName`; added `const nm_mod = @import("name_mangler.zig")` and 4 thin `pub` forwarders (`NameMangler` alias, `nameManglerInit`, `nameManglerMangle`, `nameManglerMangleGlobal`); every mint call site rewired to `nm_mod.*` (90 references). Rewires by category:

| category | sites rewired |
|---|---|
| struct-field (D1 fix) | decl `emitStructType` (was raw `:2092`), `resolveFieldAccess` addr-of-struct `:469`, ptr→struct `:514`, value-named `:559` (struct arm), `emitFieldAssign` `:321` (struct arm), `emitAggPrinterDef` `v.<f>` access (was raw `:6221`) |
| union-member | `emitTaggedUnionType` decl, `emitUnionType` decl, `emitVariantFieldPayload` (now takes the TU type id, derives the payload index internally), `resolveFieldAccess` `:478`/`:525`/`:559` (union/packed arms), `emitFieldAssign` `:321` (union/packed arm), printer TU access `:6307` |
| local | `emitParamList` (gains `fn_scope` param; callers pass `nameManglerFnScope`), `emitHoistedDecls` dbg, `resolveTempName`, `emitInst` `.assign`/`.assign_field`/`.assign_index`/`.load_local`/`.store_local`/`.load_field`/`.store_field`, `emitFunctionBody` decl + unused-param writes; new `C89Emitter.current_fn_scope` field set alongside `current_fn` |
| temp | `resolveTempName` fallback, hoisted-decl loops (3 sites) |
| synthetic-type | `getCTypeName` arr/tup/slice/opt branches, `emitArrayType`, `emitOptionalType` (`MintSyntheticType`); `getCTypeName`'s `EU_`/`ES_`/`FP_`/`TU_` composites + `sliceElementName` keep their P3 derivation composition and route every mint tail through `nm_mod.nameManglerMangle` |
| module | `moduleQualifiedName` body → `nameManglerMintModuleStem` (registry lookup stays; callers incl. `main.zig:1458` unchanged) |
| printer | `namePrinterName`/`aggPrinterName`/error-table names (`MintIndexName`), packed scratch names `zT_pkf<idx>` (3 sites), `stdFmtSourceSymbol` kind-0 mint |
| fn/global/type | all `nameManglerMangle`/`nameManglerMangleGlobal` call sites → `nm_mod.*` (34 sites); extern mint-then-override pattern preserved byte-for-byte (hard boundary) |

**`sf/src/main.zig`** — deleted `:10-11` (stub import + `NameMangler` alias), `:104` (field), `:206` (no-arg stub init), `:333` (write). Task 0's lowercase grep listed only `:10`; the `:11` `NameMangler` alias is the same stub class, deleted and disclosed here.

**`sf/src/main_dump.zig`** — deleted `:10-11`, `:60` (stub field; `CompilerContext` was never constructed in its `main`).

**`sf/src/strip_main.zig`** — deleted `:2-3` imports + `:6-7` discard; file is now `pal` + `main` + `stderr_write("zig1\n")`.

**Tech docs** (`[updated: 2026-10-12]` on changed sections): `08_c89_emission.md` (header P1 entry; §1.3 rewritten — authority home, extended field table, per-kind mint API table, determinism argument, Temp/Local subsections rewritten; §3 rewritten from "Minimal Counter" to the authority description; current-state fn-table rows re-pointed), `09_pipeline_orchestration.md` (header P1 entry; CompilerContext 34→33 / main_dump 6→5 field rows; setup step 7 tombstoned; `phase_C89Emission` mangler-init note; `strip_main.zig` section rewritten), `INDEX.md` (function-index rows for every moved/renamed symbol re-pointed; `NameMangler` struct row re-homed; new mint-API row added).

### Deviations from plan text (none semantic)

1. `main.zig:11` / `main_dump.zig:11` (the `NameMangler` stub TYPE aliases) deleted in addition to the Task 0-listed `:10` import lines — same stub class, disclosed in Investigate §1.
2. `emitVariantFieldPayload` signature takes the tagged-union **type id** (was the `tu` payload index) so the member mint's scope key is the owning type — the only call site (`resolveFieldAccess` TU payload arm) passes `base_ty`.
3. Printer display labels keep the RAW source name while the access designators use the minted name (existing F1 pattern extended to struct fields) — required for runtime-golden identity (`.{ .int = 7 }` prints `int`, accesses `z_int`).

### Semantic-preservation checks (run during/after the edit pass)

1. Grep over `c89_emit.zig` for every deleted identifier (`mangleLocalName`/`mangleTempName`/`cUnionMemberName`/`syntheticTypeName`/`aggPackedScratchName`/`typeIdName(`/`isC89Keyword`/`mangleC89Keyword`/`writeHex`/`isTempOrBuiltin`/`nameManglerPopulateKeywords`) → **zero hits**; un-prefixed `nameManglerMangle(`/`nameManglerMangleGlobal(` call sites → **zero hits** (all `nm_mod.*` or the 4 `pub fn` forwarder defs).
2. `tests/test_name_mangle_bin.zig` (outside the touch set; exercises `c89_mod.NameMangler`/`nameManglerInit`/`nameManglerMangle` incl. kind 3) built with the P1 compiler and run: `NameMangle tests passed.` — 14/14 ok (compat surface verified).
3. `main_dump.zig` + `strip_main.zig` dump-compile with the P1 compiler: `rc=0` both (stub deletes do not break the entries).
4. Self-emission names byte-identical by construction (pass-through raw rule for the only keyword local `lir_opt_pass.zig:1873` `signed`; zero keyword fields/members; zero `z_<keyword>` pairs in sf/src) — confirmed by pins 0/8 and `hop1==hop2` below.

### Tech docs (AGENTS.md 1.1.1 duty)

Done — see the change list above (`08_c89_emission.md`, `09_pipeline_orchestration.md`, `INDEX.md`; `[updated: 2026-10-12]` at the top of each changed section).

## Runtime battery

Full battery per the brief's "Runtime battery + comparison anchors" (all 8 items). Zig1 under test: `/tmp/p1_work/seed/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p1_work/seed` (fresh out dir; `release/seed/` untouched). Comparison anchors: `progress.md` `## Task 0` + `task-0-report.md` §1 / Appendix A. Repo CWD `/workspace/znineeight` for all commands.

### 1. Seed rebuild + self-emission two-hop closure

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p1_work/seed
```
Observed (tail):
```
[seed] hop1 binary md5: f8912bbd39083dba727b5f2c55072d6c
[seed] hop2 binary md5: f8912bbd39083dba727b5f2c55072d6c
[seed] two-hop closure OK: hop1 == hop2 == f8912bbd39083dba727b5f2c55072d6c
=== [seed] Done: /tmp/p1_work/seed ===
```
**Fixed point old→new: `e81d9266955caaad6873fb728d7f494e` → `f8912bbd39083dba727b5f2c55072d6c` — MOVED (expected/allowed: the compiler source changed — the module split moves the self-emission C; naming behavior on sf/src is byte-identical). hop1 == hop2 — MATCH.** No `FIXED_POINT_MD5` gate applied (the frozen point legitimately moved). Seed NOT rotated (controller resolution 3).

### 2. Corpus classify — per-dir runtime class vs Appendix A

```bash
bash scripts/corpus/classify /tmp/p1_work/seed/zig1_5_clean /tmp/p1_work/corpus_p1.txt
# -> wrote /tmp/p1_work/corpus_p1.txt: 1124 dirs
awk '/^## Appendix A/{f=1} f&&/^```$/{c++; next} c==1{print} c>=2{exit}' \
  .superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/task-0-report.md > /tmp/p1_work/appx_a.txt
md5sum /tmp/p1_work/appx_a.txt /tmp/p1_work/corpus_p1.txt
# -> 518eca1a9b5d3e1cc5a48abce214abd8  appx_a.txt
# -> 518eca1a9b5d3e1cc5a48abce214abd8  corpus_p1.txt
diff /tmp/p1_work/appx_a.txt /tmp/p1_work/corpus_p1.txt   # EMPTY
awk '{print $2}' /tmp/p1_work/corpus_p1.txt | sort | uniq -c
# -> 116 FAIL / 58 GREEN / 950 OK
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — per-dir list BYTE-IDENTICAL to Appendix A (md5 `518eca1a9b5d3e1cc5a48abce214abd8` both sides). No class mover (the D1-class struct-field fix flipped nothing — no corpus program has a keyword-named struct field). UNCHANGED.**

### 3. Runtime goldens (4 programs / 5 md5s)

Build (frozen recipe):
```bash
/tmp/p1_work/seed/zig1_5_clean --dump-c89 <ENTRY> > /tmp/p1_work/gold/<n>.c 2> <n>.dumperr   # rc=0 x4
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/p1_work/gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
    -o /tmp/p1_work/gold/<n>                                                                  # rc=0 x4
```

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| `game_of_life` (100 gens) | `timeout 120 /tmp/p1_work/gold/gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| `lisp_interpreter_curr` `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 /tmp/p1_work/gold/lisp > lisp.out` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| `json_parser` | `cd examples/z98/json_parser && timeout 60 /tmp/p1_work/gold/json > json.out` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| `mud_server` server | `bash examples/z98/mud_server/demo/session.sh /tmp/p1_work/gold/mud mud_srv.out mud_cli.out` (session rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| `mud_server` client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

**5/5 goldens byte-identical to the frozen md5s.**

### 4. `repro/mi_matrix` runtime anchor set (25 + oob)

```bash
bash scripts/stdlib/run_fixtures.sh /tmp/p1_work/seed/zig1_5_clean \
  repro/mi_matrix/array_of_struct_literal_xmod … repro/mi_matrix/tagged_tag_sugar_xmod
```
(the exact 25-dir command frozen in Task 0 F2). Observed tail + all 25 lines `PASS repro/mi_matrix/<name>`:
```
----------------------------------------
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
In-bounds D5 confirmer inside the set: `slice_index_field_store_xmod` = `PASS` (the `9/11/22/ok` golden). D-fix trap subset (separate `-fsafe` recipe):
```bash
/tmp/p1_work/seed/zig1_5_clean -fsafe -o /tmp/p1_work/anchor/oob repro/mi_matrix/slice_index_field_store_oob_xmod/main.zig   # rc=0
cd /tmp/p1_work/anchor/oob && sh build_target.sh linux ./prog   # rc=0
timeout 120 ./prog > run.out 2> run.err; echo "run rc=$?"   # -> run rc=133 (Trace/breakpoint trap)
wc -c < run.out                 # -> 0
md5sum < run.out                # -> d41d8cd98f00b204e9800998ecf8427e (= expected.txt)
```
D1 sibling print (display-name check for the struct-field/member mint): `union_keyword_tag_xmod` → `P=.{ .int = 7 }` / `3`, rc=0 — **identical to the frozen baseline** (the print label keeps the raw tag `int`; the C member is `z_int`).
**25/25 MATCH goldens + oob rc=133/empty MATCH.**

### 5. `examples/z98/*/` matrix — build AND run

Build (per dir; entry resolution `main.zig` → `<dirname>.zig` → first `*.zig`):
```bash
/tmp/p1_work/seed/zig1_5_clean -ffast -o /tmp/p1_work/matrix/<name> <entry>          # dump rc=0 x26
cd /tmp/p1_work/matrix/<name> && sh build_target.sh linux /tmp/p1_work/matrix/<name>/prog   # build rc=0 x26
```
All 26 `.c` counts match the §1.4 baseline (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). Run (`cd examples/z98/<name> && timeout 25 …`, mud 8s, rogue* fed `q\n`, else `/dev/null`):

| dir | rc | stdout md5 (16) | vs §1.4 baseline | verdict |
|---|---|---|---|---|
| days_in_month | 0 | `8c0d394cbc6e7f36` | same | correct |
| fibonacci | 0 | `b53b3a3d6ab90ce0` | same | correct |
| func_ptr_return | 0 | `f6a5477970a87a1c` | same | correct |
| game_of_life | 0 | `fcbf7e7cead5082f` | same | correct |
| heapsort | 0 | `8cf0a7844206319d` | same | correct |
| hello | 0 | `746308829575e17c` | same | correct |
| json_parser | 0 | `8bda3d5a1ec07d14` | same | correct |
| json_parser_upgraded | 0 | `8bda3d5a1ec07d14` | same | correct |
| json_parser_workaround | 0 | `dc22fa473650bd3d` | same | correct |
| lisp_interpreter | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_adv | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_curr | 0 | `1c1f0a417d5e9434` | same | correct |
| lisp_interpreter_upgraded | 0 | `1c1f0a417d5e9434` | same | correct |
| lzw | 0 | `c3c7765e6faf7b70` | same | correct |
| mandelbrot | 0 | `d596677501e36537` | same | correct |
| mud_server | 124 | `9545fe1d245293ef` | same | correct (documented timeout) |
| prime | 0 | `d095a94d20dcaf7a` | same | correct |
| quicksort | 0 | `45d2f0fb6fc40654` | same | correct |
| rogue_mud | 0 | `3fb6709e7bbd8964` | same | correct |
| rogue_mud_upgraded | 0 | `3fb6709e7bbd8964` | same | correct |
| sort_strings | 0 | `c6c047cbc13cdd4f` | same | correct |
| tco_defer | 0 | `264ea6b106a51dde` | same | correct |
| tco_factorial | 0 | `3d70c50b5a37d549` | same | correct |
| tco_return_try | 0 | `7421137aa2d104b4` | same | correct |
| z9play | 1 | `2016494de476fcb6` | same | correct (usage-on-no-args) |
| z9torr | 1 | `f666af15cf2625b3` | same | correct (usage-on-no-args) |

**26/26 build rc=0 + 26/26 run correct; every stdout md5 + rc identical to the frozen §1.4 table.**

### 6. Stdlib gate

```bash
bash scripts/stdlib/verify_stdlib.sh /tmp/p1_work/seed/zig1_5_clean
```
Observed (tail):
```
----------------------------------------
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
**STDLIB GATE OK — 285 PASS / 0 FAIL; no lost PASS vs baseline 285.**

### 7. The 8 `--dump-c89` pin md5s — old→new

```bash
/tmp/p1_work/seed/zig1_5_clean <mode> --dump-c89 <ENTRY> 2>/dev/null | md5sum
```

| entry | mode | old (P5-validated) | new (P1) | delta |
|---|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `-fsafe` | `498b90f191b544655a1b731ef480709d` | `498b90f191b544655a1b731ef480709d` | unchanged |
| `examples/z98/mud_server/main.zig` | `-ffast` | `50dbf5f02c1a5de920e158cab7f2f29b` | `50dbf5f02c1a5de920e158cab7f2f29b` | unchanged |
| `examples/z98/game_of_life/main.zig` | `-fsafe` | `52c5feb5f158e2af7b32a0509b43d4c6` | `52c5feb5f158e2af7b32a0509b43d4c6` | unchanged |
| `examples/z98/game_of_life/main.zig` | `-ffast` | `7271960fc6375ed1dee34b7abfb6325b` | `7271960fc6375ed1dee34b7abfb6325b` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-fsafe` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-ffast` | `ec82996028671a52a0a3d52ad307edf1` | `ec82996028671a52a0a3d52ad307edf1` | unchanged |
| `examples/z98/json_parser/main.zig` | `-fsafe` | `48eedfc0243431693f65518646ad280c` | `48eedfc0243431693f65518646ad280c` | unchanged |
| `examples/z98/json_parser/main.zig` | `-ffast` | `04124b2675e77020933cbfab20f883e1` | `04124b2675e77020933cbfab20f883e1` | unchanged |

**Pin delta count: 0/8** — user-program emitted C is byte-identical under the pass-through naming rules (the authority reproduces every prior name byte-for-byte for non-keyword, non-colliding names; the D1-class fix only changes names in programs that HAVE keyword fields/members — none in the pin set). Runtime proof = items 3–6. (The brief allowed movement; the byte-stable contract of the raw rule keeps these 8 fixed — only the compiler's SELF-emission moved, item 1.)

### 8. `--markers` telemetry

```bash
/tmp/p1_work/seed/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/p1_work/mk_gol.c 2>/tmp/p1_work/mk_gol.bin
grep -ac '^' /tmp/p1_work/mk_gol.bin    # -> 3436
wc -c < /tmp/p1_work/mk_gol.bin         # -> 38378
```
Prefix tally vs baseline: `INT:new` **1810 → 2005 (+195)**; `DC:k` 423, `FE:p` 240, `FWD:n=` 195, `P0:lc` 195, `RaD` 122, `MT` 86 — all UNCHANGED. The +195 `INT:new` lines are exactly the `nameManglerFnScope` scope-key interns (one per emitted function; `FWD:n=` count = 195 functions). **3,436 marker lines / 38,378 B (recorded, not gated) — delta fully explained; emitted-C bytes unaffected (pins 0/8).**

### Battery verdict summary

| gate | observed | vs frozen Task 0 anchor | verdict |
|---|---|---|---|
| seed two-hop closure | hop1 == hop2 == `f8912bbd39083dba727b5f2c55072d6c` | fixed point `e81d9266…` → `f8912bbd…` (moved, allowed, recorded) | MATCH |
| corpus classify | 1124 = 950/58/116/0/0; per-dir list byte-identical (md5 `518eca1a…`) | Appendix A | UNCHANGED (no mover) |
| runtime goldens | 5/5 md5s | frozen md5s | MATCH |
| mi_matrix anchors | 25/25 + oob rc=133/empty; D1 sibling `P=.{ .int = 7 }`/`3` | §1.8 set (25+oob) | MATCH |
| examples matrix | 26/26 build + 26/26 run | §1.4 (incl. rc=1 ×2, rc=124) | MATCH |
| stdlib gate | 285 PASS / 0 FAIL, STDLIB GATE OK | 285/0 | MATCH |
| 8 dump pins | old→new recorded above | recorded-not-gated | delta 0/8 |
| markers | 3,436 lines / 38,378 B (`INT:new` +195 = fnScope interns) | 3,241 / 36,038 | recorded; delta explained |

No gate failed; no observation diverges from the plan. Runtime behavior unchanged.

### Concerns

1. **Markers telemetry moved** (item 8): +195 `INT:new` lines from the `nameManglerFnScope` scope-key interns. Not a gate; emitted-C bytes unchanged. If markers become a gate later, the scope key could avoid interning (hash of `(module_id, name_id)`) at the cost of theoretical scope-key collisions.
2. **Compat surface** (disclosed design decision, within the touch set): `c89_emit.zig` keeps 4 thin `pub` forwarders so `main.zig:1197-1199` and `sf/src/tests/test_name_mangle_bin.zig` (outside the approved touch set) keep compiling unchanged. No minting logic is duplicated.
3. **P1/P3 seam** (disclosed): the `EU_`/`ES_`/`FP_`/`TU_` name-material COMPOSITIONS stay in `getCTypeName`/`emitTaggedUnionType` (P3 relocates the derivation to `type_registry.typeCName`); every one of those names is finalized through the authority's `nameManglerMangle` — no listed-category identifier is produced outside `name_mangler.zig`.
4. **Fixed point moved** `e81d9266…` → `f8912bbd39083dba727b5f2c55072d6c` (module split; expected per the brief). Seed not rotated per controller resolution; rotate at closeout (Task C).

