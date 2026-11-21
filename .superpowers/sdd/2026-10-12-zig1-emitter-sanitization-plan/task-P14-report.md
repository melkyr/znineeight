# Task P14 report — Lookup-index hygiene (Amendment 7)

**Status: COMPLETE** — the three lookup classes land as ONE increment with **zero
LIR/emitter-spelling change**; the required identity proof holds: **pins 0/8** (byte-identical
old→new on all 8 gate dumps) and the full 8-item battery is green (corpus class file byte-identical
vs frozen Appendix A `518eca1a…`, goldens 5/5, mi_matrix 25+oob MATCH, examples 26/26 build +
26/26 run frozen, stdlib 285/0, hop1==hop2, markers 3437/38384 unchanged — the gol `--markers`
stream is byte-identical to the old compiler's). No STOP. Commits: (a) `refactor(c89_emit): P14 —
lookup-index hygiene (Amendment 7)` (4 src files + tech docs), (b) `docs(sdd): P14 report` (this
file).

Touch set held exactly: `sf/src/async_frame_layout.zig` + `sf/src/async_state_machine.zig` +
`sf/src/c89_emit.zig` + `sf/src/c89_plan.zig` + tech docs stamps
(`08_c89_emission.md`/`12_async_coroutines.md`/`INDEX.md`). `lower.zig`/`lir.zig` untouched.

---

## 1. Investigate

### 1.1 Site census (re-derived by function name at the pre-edit HEAD `7d1529c6…`; survey lines
drifted, names did not)

**Class A — `asyncTempIsGlobalAlias` full-LIR rescan per call.**
- Def (pre-edit `async_frame_layout.zig:530`): walks every block/inst of the fn per call looking
  for a `.load_global` with `result == temp` — O(blocks×insts) per query.
- Callers (pre-edit): `asyncLayoutFrame` `ASYNC_FIELD_LIVE` add skip (`:647`) — one query per live
  temp; `saveAllFields` (`async_state_machine.zig:273`) and `reloadAllFields` (`:290`) — one query
  per PARAM/LIVE field per yield/resume copy (the step copies multiply this).

**Class B — `hoisted_temps` linear scans (5 helpers, 45+ call sites).**
| helper | filter semantics | miss | call sites (pre-edit line, enclosing fn) |
|---|---|---|---|
| `getTempTypeByIndex` (`c89_emit.zig:692`) | raw first-match | `0xFFFFFFFF` | 11: `tempFnTypeId:1652`, `nestShapeOk:3175/:3182/:3202`, `nestEmitDefRvalue:3463`, `nestEmitBinExpr:3517/:3522`, `emitterTempIsPackedStructPtr:5894`, `emitFlagOp:6905/:7857`, `tempPayloadIsVoid:8608` |
| `hoistedTypeOfInFn` (`:706`) / `hoistedTypeOf` (`:715`) | first-match-SKIP-UNDEFINED (`type_id != TYPE_UNDEFINED`) | `0` | 3 direct (`emitFieldAssign:249/:328`, `dceTempIsArray:7930`) + wrapper `:716` + 14 via `hoistedTypeOf` (`nestEmitDefRvalue:3436`, `emitUnaryRvalue:3613`, `emitFlagOp:6223/:6293/:6380/:6420/:6517/:6533/:6576/:6714/:6803/:6808/:6848/:7066`) |
| `hoistedTypeId` (`:721`) | raw first-match | `0` | 3: `emitFlagOp:6469/:6474`, `emitFunctionBody:8150` |
| `getTempEffType` (`:4082`) | FAILFAST first-match — the FIRST match's `0xFFFFFFFF`/`TYPE_VOID` type fails to `0` with no later-decl fall-through | `0`/`(0,0)` | 11: `emitFieldAssign:369`, `nestScalarEffTid:3129`, `emitBinRvalueText:3555/:3556`, `emitFlagOp:6245/:6248/:6443/:6446/:6629/:6664/:6671` |
| `hoistedEffType` (`c89_plan.zig:208`) | FAILFAST first-match (plan-time mirror of `getTempEffType`) | `0` | 2: `spellPlanPlanFn` uac `:193/:194` |

Same search class (converted, see §2.2 note): `spellPlanPlanFn`'s inline carrier-fill
first-match `hoisted_temps` scan (pre-edit `:175-180`) — O(hoisted) per const inst.

Multi-decl which-wins: **all five helpers are FIRST-match** (the first `TempDecl` with the queried
temp_id wins; `hoistedTypeOfInFn` is first-match **among non-UNDEFINED decls**). This is the
identity requirement the maps must preserve (the in-tree models fill **LAST-match** —
`lir_opt_pass.lirOptRun`'s `t2p[td.temp_id] = hti` and `emitHoistedDecls`'s `tid_to_pos` — so the
P14 fills are explicitly first-wins).

**Class C — `fn_keys` linear scan.** `spellPlanUac` (`c89_plan.zig:256`) / `spellPlanCarrier`
(`:268`) scan `plan.fn_keys[0..fn_count)` per spell-time read (~8 call sites through
`planUacSideAt`/`planConstCarrierAt`); F is small but the scan runs per comparison-binary and per
const inst during body emission.

### 1.2 Map design (in-tree O(1) models mimicked: `factCarrierOfTemp`'s `d4_t2p`/`d4_fcar`,
`tempDeclTypeId`'s `t2p`/`ttype`)

- **Class B, `c89_emit.zig`:** `C89Emitter` gains `t2pos: [*]u32` / `t2pos_conc: [*]u32` /
  `t2pos_max: u32` (beside the `d4_*` tables). Built ONCE at the per-fn emission entry
  (`emitHoistedDecls`, in the same hoisted-temp walk that fills `tid_to_pos`; no marker traffic
  added — the `--markers` stream is byte-identical): `t2pos[temp_id]` = FIRST hoisted index with
  that `temp_id` (`0xFFFFFFFF` = miss), `t2pos_conc[temp_id]` = FIRST with that `temp_id` AND
  `type_id != TYPE_UNDEFINED`. Every helper becomes a bounds-checked map read +
  `hoisted_temps.items[pos].type_id`:
  - `getTempTypeByIndex` → `t2pos` (raw first-match, miss `0xFFFFFFFF`),
  - `hoistedTypeOfInFn`/`hoistedTypeOf` → `t2pos_conc` (skip-undefined, miss `0`),
  - `hoistedTypeId` → `t2pos` (raw first-match, miss `0`),
  - `getTempEffType` → `t2pos` + the unchanged FAILFAST validity gate on the first match
    (`0xFFFFFFFF`/`TYPE_VOID` → `0`; else fill `out_type`/`out_signed` exactly as before).
  The filter is never re-derived: the map replaces only the SEARCH. Out-of-domain ids
  (`temp_id >= t2pos_max`) return each helper's miss value — equivalent to the scan miss for every
  input (every hoisted temp id is `< t2pos_max` by construction of `max_temp`).
- **Class B, `c89_plan.zig`:** the per-fn `t2pos` (same first-match fill) is built at
  `spellPlanPlanFn` start; `hoistedEffType` reads it with its FAILFAST filter verbatim, and the
  carrier-fill inline scan reads it (a found `0xFFFFFFFF` type id still classifies as absent —
  verbatim).
- **Class C:** `C89SpellPlan` gains `fn_key_index: hash_mod.U32ToU32Map` (fn_key → fn index),
  initialized in `spellPlanInit` (side-table style beside `fn_keys`/`fn_maps`/`uac_maps`), filled
  in `spellPlanPlanFn` **first-wins** (only put when absent — under a duplicate `fn_key` the
  retired scan returned the FIRST matching index; first-wins preserves that for every input).
  `spellPlanUac`/`spellPlanCarrier` read the map; miss semantics unchanged (fn miss → `null` =
  uac no-cast / carrier historical fallback; inst miss → `null` as before).

### 1.3 Class A exclusion proof (the deletion authorization condition)

The dual generator filters (`saveAllFields`/`reloadAllFields`) were authorized for deletion only
under a proven exclusion: no alias temp is ever a param id. **Proof:**

1. `lower.zig` `lowerFn` mints the function's **param** temps first: the param loop
   (`lower.zig:9332-9337`) calls `nextTemp` for each param (a fresh lowerer starts
   `temp_counter = 0`, `lower.zig:483`), so param `temp_id`s are exactly `0 .. params_count-1`;
   afterwards `temp_counter` is reset to `proto.params_count` (`lower.zig:9356`).
2. Every `load_global` result is minted by `nextTemp` **in the body** — `lowerGlobalRef`
   (`lower.zig:4267-4268`), the module-alias `lowerLValueAddr` arm (`:2540-2542`), the mid-alias
   const-ref arm (`:4431-4432`) — so every `load_global` result is `>= params_count`.
3. Therefore no `load_global` result equals any `LirParam.temp_id` in the same function:
   `asyncTempIsGlobalAlias(orig, param_temp_id)` is always false. Module-init fns have no params
   (`lowerModuleInit` appends no `LirParam`) — vacuous. `asyncLayoutFrame` runs only on
   lower-produced fns (`main.zig:925`).
4. The generator filter's scope is PARAM+LIVE; LIVE fields already exclude aliases at the layout
   (`asyncLayoutFrame`'s LIVE-add skip). With (3) the generator filter cannot fire on either kind
   → its deletion is behavior-preserving. This is exactly the P9 review C3 "defense-in-depth is
   unreachable" condition, now proven at the temp-allocator level.

Set-domain note: every `load_global` result also has a `TempDecl` (`nextTemp` appends one at
`lower.zig:801-804`), so `lg.result < max_temp` always — the carried alias set (sized `max_temp`)
covers the predicate's whole domain (same result per temp as the retired full-LIR rescan).

---

## 2. Implement

Edit policy held: `edit`/`fastedit` only, region re-read before each edit, bottom-to-top per file,
INSERT = anchor→new+original, no scripted source transforms.

1. **`sf/src/async_frame_layout.zig` (Class A):**
   - `AsyncFrameLayout` (`:69`) gains `alias_flags: [*]u8` / `alias_len: u32` (the carried per-fn
     set).
   - `asyncTempIsGlobalAlias` (`:539`) is now a pure **set read** of the carried set (same
     predicate result per temp; P9 semantics unchanged).
   - `asyncLayoutFrame` builds the set with **one** LIR pass (`:639-657`, beside the existing
     live-scan; no markers) and the LIVE-add skip (`:665`) reads it; the return (`:711`) carries
     it on the layout.
2. **`sf/src/async_state_machine.zig` (Class A):** the dual `saveAllFields` (`:270-275`) /
   `reloadAllFields` (`:288-293`) alias filters are DELETED (exclusion proven §1.3); both walks
   otherwise verbatim (child field untouched).
3. **`sf/src/c89_emit.zig` (Class B):** `t2pos`/`t2pos_conc`/`t2pos_max` on `C89Emitter`
   (`:546-548`, init `:633-635`); maps built in `emitHoistedDecls` (`:2367-2418`); the five
   helpers (`getTempTypeByIndex:702`, `hoistedTypeOfInFn:716`, `hoistedTypeOf:723`,
   `hoistedTypeId:731`, `getTempEffType:4109`) are map reads with their own filters verbatim.
   `hoistedTypeOfInFn` takes `*C89Emitter` (was `*LirFunction`); its call sites thread the
   emitter (`emitFieldAssign` uses `emitter2` — `emitter.current_fn` at the single call site
   `:6275`; `dceTempIsArray`/`dceBaseEscapes`/`dceMarkAllReads` gain/swap the emitter param —
   same lookups, same DCE results).
4. **`sf/src/c89_plan.zig` (Class B+C):** `fn_key_index` on `C89SpellPlan` (`:42`, init `:114`);
   per-fn `t2pos` built at `spellPlanPlanFn` start (`:146-166`); `hoistedEffType` (`:245`) is a
   map read with the FAILFAST filter verbatim; the carrier-fill inline scan (`:201-214`) reads the
   same map (verbatim which-wins); `spellPlanUac:292` / `spellPlanCarrier:304` read `fn_key_index`
   (first-wins fill `:141-145`).
5. **Tech docs:** `[updated: 2026-10-15 — P14 …]` stamps on the changed sections —
   `08_c89_emission.md` (header + `t2pos` field row + `plan` field row + `getTempTypeByIndex`
   helper row + arena row), `12_async_coroutines.md` (header + §8 P14 paragraph with the exclusion
   proof), `INDEX.md` (header + rows `asyncTempIsGlobalAlias`/`getTempTypeByIndex`/
   `spellPlan{Init,PlanFn,Uac,Carrier}`).

Decision-vs-spelling unchanged (lookup rewrites only — no new decisions, no spelling change);
`lower.zig`/`lir.zig` untouched; determinism held (dense first-match arrays + a hash map keyed by
the existing `fn_keys` domain; no iteration-order-dependent output — proven by the byte-identical
pins/corpus).

---

## 3. Runtime battery

Compiler under test: `/tmp/p14_work/new/zig1_5_clean` (seed two-hop of the P14 tree). OLD
comparison compiler: `/tmp/p8f1_build/zig1_5_clean` (md5 `7d1529c68562d5b2b2e3548129f08856` =
the pre-P14 recorded fixed point; its 8 pins reproduce the P8 record exactly — the `old` column
below).

### 1. Seed rebuild + two-hop closure

```
$ cd /workspace/znineeight
$ FIXED_POINT_MD5=7d1529c68562d5b2b2e3548129f08856 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p14_work/new
[seed] hop2 binary md5: 7b6273ffeb8959232a552c105d891fcd
[seed] two-hop closure OK: hop1 == hop2 == 7b6273ffeb8959232a552c105d891fcd
error: fixed-point mismatch: got '7b6273ffeb8959232a552c105d891fcd', want '7d1529c68562d5b2b2e3548129f08856'
```

**hop1==hop2 proven**; fixed point old `7d1529c68562d5b2b2e3548129f08856` → new
**`7b6273ffeb8959232a552c105d891fcd`** (expected to move — the compiler's source moved; the
`FIXED_POINT_MD5` mismatch is the recorded delta; seed NOT rotated — closeout-only).

### 2. Corpus classify vs frozen Appendix A

```
$ bash scripts/corpus/classify /tmp/p14_work/new/zig1_5_clean /tmp/p14_work/corpus_p14.txt
wrote /tmp/p14_work/corpus_p14.txt: 1124 dirs
$ md5sum /tmp/p14_work/corpus_p14.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p14_work/corpus_p14.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ awk '{print $2}' … | sort | uniq -c  →  116 FAIL / 58 GREEN / 950 OK
```

**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical class file, 0 movers.**

### 3. Runtime goldens (5/5)

Dump `-fsafe` + gcc (`-m32 -std=c89 … -I sf/src/include zig_runtime.c zig_pal.c`): all 4 dump
rc=0 / gcc rc=0 / 0 `error:` (line counts 13987/19343/15672/14937 — the post-P10 `-fsafe`-guard
shape; the dumps are byte-identical to the old compiler's by the pins below).

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 gold/gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| gold/lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| json | `cd examples/z98/json_parser && gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| mud srv | `bash examples/z98/mud_server/demo/session.sh gold/mud mud_srv.out mud_cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| mud cli | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

Both mud files also `cmp`-equal the committed `demo/canonical_expected.txt` /
`demo/canonical_client_expected.txt` (`cmp srv IDENTICAL` / `cmp cli IDENTICAL`). **5/5
byte-identical.**

### 4. mi_matrix anchors 25 + oob

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/p14_work/new/zig1_5_clean $(cat /tmp/opencode_p6pre/mi25.list)
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```

Trap (`-fsafe`) `slice_index_field_store_oob_xmod`: dump rc=0, `sh build_target.sh linux` build
rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e`
= empty `expected.txt`), `expected.rc=133`. **MATCH.**

### 5. examples/z98/*/ matrix (26/26 build + 26/26 run)

Build (`-ffast -o <dir>`, `build_target.sh linux`): **26/26 dump=0 / build=0**; `.c` counts
identical to task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). Run
(CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* fed `q\n`):
**26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** — days_in_month `8c0d394cbc6e7f36`,
fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`,
heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`,
json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`,
mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`,
quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`,
tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`,
z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`. **26/26 frozen.**

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/p14_work/new/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

### 7. The 8 `--dump-c89` pins (old → new; sequential from repo root)

Command per row: `<compiler> <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

| entry | mode | old (`/tmp/p8f1_build` = `7d1529c6…`) | new (`7b6273ff…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `bbc02913a10af9b0b5ed0f292f4e3407` | `bbc02913a10af9b0b5ed0f292f4e3407` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `93c5e3fdc5b80b2f3db020d995abbe3f` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `6da05d070acd414674b1b1ec947baa5c` | `6da05d070acd414674b1b1ec947baa5c` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `af3823fae0b29fa4d4ca58932538d631` | `af3823fae0b29fa4d4ca58932538d631` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical, the REQUIRED identity proof.** The old column also
reproduces the P8 record (the current live table) exactly.

### 8. `--markers` telemetry

```
$ /tmp/p14_work/new/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol_new.c 2> mk_gol_new.bin
dump rc=0; 3,437 marker lines / 38,384 B
$ cmp /tmp/p14/mk_gol_old.bin /tmp/p14/mk_gol_new.bin  →  IDENTICAL
```

Unchanged **3437/38384** and the stream is byte-identical to the old compiler's (the map build
adds no marker traffic).

---

## 4. Observations

- **O1 (identity):** pins 0/8 + corpus 0 movers + goldens/mi/examples/stdlib/marker-stream frozen —
  the "lookup-only, zero spelling change" contract holds on the whole frozen battery. The maps are
  pure search replacements: each helper's filter semantics and multi-decl first-match which-wins
  are preserved exactly (§1.1 table).
- **O2 (in-tree models differ on which-wins — disclosed):** the mimicked O(1) models
  (`d4_t2p`/`lir_opt_pass.t2p`) fill **LAST-match** (`t2p[id] = hti` unconditional). All five P14
  helpers are FIRST-match, so the new fills are first-wins (`if (t2pos[id] == 0xFFFFFFFF)`); a
  last-match fill would have moved multi-decl results. Multi-decl temp ids do not occur on the
  current producers (lower/async mint one `TempDecl` per `nextTemp`), so the pin identity is
  doubly safe — but the fill order is now correct regardless.
- **O3 (Class B scope note):** `spellPlanPlanFn`'s inline carrier-fill `hoisted_temps` scan is not
  one of the named five helpers but is the same first-match search class with identical results
  (a found `0xFFFFFFFF` type id classifies as absent, verbatim); it was converted to the same
  `t2pos` read (search-only). If the operator wants it reverted to a literal scan it is a 6-line
  revert with zero behavior change.
- **O4 (Class C `spellPlanGrow` not extended — disclosed):** `fn_key_index` is a plan-global
  `U32ToU32Map` (owns its growth; the recorded values are `fn_count` ordinals, stable across the
  `fn_keys`/`fn_maps`/`uac_maps` reallocation), so `spellPlanGrow` needs no extension — the
  `uac_maps`/`fn_maps` parallel-array precedent applies to per-fn arrays only. `spellPlanInit`
  carries the map init. Miss semantics unchanged (uac miss = no-cast posture; carrier miss = the
  historical fallback).
- **O5 (Class A API):** `asyncTempIsGlobalAlias` changed signature (set read of the carried
  `alias_flags`/`alias_len`) — the only remaining consumer is the `asyncLayoutFrame` LIVE-add
  skip; the generators no longer call it (filters deleted, exclusion proven §1.3). The predicate
  result per temp is unchanged (P9 semantics).
- **O6 (bound-guard note):** every map read bounds-checks `temp_id` against the map domain and
  returns the helper's miss value above it — identical to the scan miss for every input (all
  hoisted ids are in-domain by `max_temp`'s construction; body temps queried out of domain miss
  both ways).
- **O7 (harness):** pins/markers run sequentially (spill-file race if parallel zig1 runs share a
  CWD); example runs use CWD = example dir per the battery contract. Untracked `run.err` and the
  dirty plan-md delta were left alone; no push; seed NOT rotated (closeout-only).
