# Task 1 report — D1 identity: canonical synthetic composite types

Branch `zig1_improvements`. Scope: D1 identity half ONLY (spec `docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md` §2 bug 1 + Fix 1). Bug 2 (emit ordering) is T2; no emit-ordering changes made here.

## Investigate

Written before source edits (site census + planned change).

### Site census — synthetic-composite GetOrCreate sites (`sf/src/type_registry.zig`)

| fn | lines | key | cache today | layout at creation | verdict |
|---|---|---|---|---|---|
| `typeRegistryGetOrCreatePtr` / `PtrQ` | 739–760 | `(base<<2)\|q` (`ptr_cache`) | **unconditional** `MapPut` (:757) | fixed 4/4, `state=2` | model — canonical |
| `typeRegistryGetOrCreateManyPtrQ` | 763–780 | `(base<<2)\|q` (`many_ptr_cache`) | **unconditional** `MapPut` (:779) | fixed 4/4, `state=2` | canonical |
| `typeRegistryGetOrCreateSlice` | 783–811 | `(elem<<1)\|is_const` (`slice_cache`) | **unconditional** `MapPut` (:804) | always `state=2` (slice layout `{ptr,len}` is elem-independent) | canonical — audit pass |
| `typeRegistryGetOrCreateOptional` | 814–836 | `payload` (`optional_cache`) | **GUARDED** `MapPut` `if (opt_state == 2)` (:835) | size/align/state computed only if `payload.state == 2` | **BUG** — fix |
| `typeRegistryGetOrCreateErrorUnion` | 839–866 | `(payload<<32)\|error_set` (`eu_cache`) | **unconditional** `MapPut` (:865) — per T0 evidence the guard is NOT here | size/align/state computed only if `payload.state == 2` | cache OK; **pending-layout freeze** (T0 C5a) fixed by completion below |
| `typeRegistryGetOrCreateArray` | 869–912 | `(elem<<32)\|length` (`array_cache`) | **GUARDED** `MapPut` `if (elem_ty.state == 2)` (:911) | size/align/state computed only if `elem.state == 2` | **BUG** — fix |
| `typeRegistryGetOrCreateTuple` | 915–926 | **none** | no cache at all | `state=2`, size=0, align=1 at creation | audit — see tuple ruling below |
| `typeRegistryGetOrCreateFn` | 966–990 | name_id (`fnt_<ret>_<params…>` embeds component **ids**) | linear scan by name_id+module+conv | fixed 4/4 | identity follows component ids — unifies once composites unify |
| `typeRegistryGetOrCreateErrorSet` | 993+ | FNV over tag set (`es_cache`) | unconditional | `state=2` | canonical (content-keyed) |

Registry state-mutation note (T0): every `.state =` in `type_registry.zig` is a creation site; `layoutCompute`/`layoutEnsure` (`type_resolver.zig:278/433`) own resolution. `typeResolverResolve` (`:541`) resolves every type existing at pass time and sets `state=2` (cycles → void + `ERR_3005`).

### Bug mechanism (identity)

`typeRegistryGetOrCreateOptional`/`GetOrCreateArray` create the composite and append it, but **only cache it when the payload/elem is already laid out**. A composite created before its payload resolves is appended **uncached**; every later request mints a **second, distinct type id** (the laid-out one is cached). The same spelled type `?Key` then exists twice; `typeRegistryIsAssignable:1813`'s fn arm (`:1830-1849`) compares `fn_type.return_type` **ids** (and param ids) directly → `error[3000]` on `fn (*void) ?Key` coercion (fixture `fnptr_opt_aggregate_coerce_xmod`, defect D1 reproducer A). `typeRegistryGetOrCreateFn` keys on a name embedding those ids, so the fn types and their ptr types diverge too. Optional and Array are the only guarded caches (EU is unconditional — T0 C5a still notes a state-0 EU id can freeze a pending layout pre-resolution).

### What the fix changes

1. **Unconditional key-cache** in `typeRegistryGetOrCreateOptional` and `typeRegistryGetOrCreateArray` (model `typeRegistryGetOrCreatePtr:739`). EU unchanged (already unconditional).
2. **On-demand pending completion** ("or equivalent" of the brief's on-demand `layoutEnsure`): on every GetOrCreate cache-hit (and at creation), if the composite is still `state != 2` while its payload/elem is now `state == 2`, compute size/align/state **in place** using the exact creation-time math (same arithmetic as `layoutCompute`'s optional/EU/array branches; guarded by `payload.state == 2` so it never reads a pending payload and never freezes prematurely). Equivalence argument (why no extra `layoutEnsure` plumbing is needed):
   - **Pre-pass creation** (symbol_registrator / `resolveTypeExprFull` / front_resolution): the pending composite is in the registry before `typeResolverResolve` snapshots `types_len`, so the topological pass completes it via `layoutEnsure` (order-independent payload-chain walk). Same as pre-fix for the first id.
   - **Post-pass creation with payload ready** (`main.zig:587-591` resolves before sema `:747`/lower `:931`; every pre-pass type is `state=2` afterwards; `typeRegistryRegisterNamedType:1208` starts `state=0`): creation math completes it immediately (unchanged behavior).
   - **Post-pass creation with payload pending** (post-pass `registerContainerType` inline aggregates — `type_resolver.zig:1684`): pre-fix, a *later* request after the payload completed minted a fresh laid-out id (request-1 holders kept a broken id); post-fix the shared id completes **in place** at that later request, and `semantic_analyzer.zig:5949` `layoutEnsure` covers decl-typed sites. In-place completion is therefore ≥ pre-fix layout coverage everywhere, with one id. Residual gap (a pending composite never re-requested and never `layoutEnsure`d but whose size is read) did not have a correct id pre-fix either (no request ever saw a ready payload) — unchanged, recorded as concern C1.
   - Premature-layout hazard avoided: `layoutEnsure` at `resolveTypeExprFull` return sites would be unsafe (pre-pass registration order can leave `payload_idx=0` pointing at another type's payload; `layoutEnsure` would freeze a wrong size). Not done; the pass is the single layout moment pre-pass.
3. **Belt-and-braces structural `fn_type` comparison** (`typeRegistryIsAssignable:1830-1849`): `src_f.return_type == tgt_f.return_type` and the param-id loop become structural equivalence over the synthetic-composite family (new `typeRegistryTypesEquiv`: id fast-path; optional → payload equiv; error_union → payload equiv + error-set id (error sets are content-keyed canonical); array → elem equiv + length; slice → elem equiv + const-flag; tuple → element-list pairwise; fn_type → return + params + flags; everything else id equality — named aggregates stay distinct per Zig). Depth-capped. Widens acceptance only for structurally-identical synthetic composites with residual duplicate ids.
4. **Tuple/slice audit** (no tuple structural change — see ruling).
5. New unit tests in `sf/src/tests/test_sym_reg_bin.zig` (dedup + in-place completion), RED before the fix where the harness allows.

### Tuple / slice audit

- **Slice (`GetOrCreateSlice:783`)**: keyed `(elem<<1)|is_const`, `MapPut` unconditional, layout (`state=2`, size 8) independent of elem layout → **already canonical**. No change.
- **Tuple (`GetOrCreateTuple:915`)**: **no key-cache**; every call appends a fresh `state=2` id (literal-occurrence semantics). Not the D1 bug class: there is no layout-conditional caching (the bug class is "same composite, cache only when payload laid out"). Consumers never require tuple **identity**: `typeRegistryIsAssignable`'s tuple arm (`:1963-1985`) compares element lists structurally; tuple field access is ordinal (`typeRegistryTupleElem:930`); sema memoizes per literal-node (`semantic_analyzer.zig:6683-6705`, structural re-check on re-entry). Declared/spelled tuple types (`struct { T, U }`) go through `registerContainerType`'s name cache (`type_resolver.zig:1697`) and are already canonical per anon-name. A content-keyed cache over `xt` element lists would additionally conflate occurrence-keyed consumers (`ctx.tuple_index_table`, `needed_tuple_set` seeds) and move tuple typedef emission — a structural change without an identity defect. **Ruling: no tuple cache; recorded.** (Observation, orthogonal, not changed: `GetOrCreateTuple` creates `state=2` with size 0 while `layoutCompute` tuple math exists — literal tuples are print-arg/occurrence types; `registerContainerType` inline tuples are `state=0` and get real layouts from the pass.)

### Creation-after-resolve paths (lowering/semа `GetOrCreate*`) — verification census

| site | composite | payload | laid out at creation? |
|---|---|---|---|
| `lower.zig:4491` | array | `TYPE_U8` | yes (primitive) |
| `lower.zig:6410` | optional | ptr→void (via `GetOrCreatePtr`) | yes (ptrs canonical `state=2`) |
| `lower.zig:6952` | array | `TYPE_U8`/`TYPE_U32` (`:6947` char-literal fold) | yes (primitive) |
| `async_state_machine.zig:120/151` | optional | ptr→void | yes |
| `async_state_machine.zig:849-850` | array | `TYPE_U8` | yes |
| `semantic_analyzer.zig:3709` | optional | payload of expected type (any) | pre-pass types `state=2` post-pass; inline-aggregate payloads covered by in-place completion + `:5949` |
| `semantic_analyzer.zig:5044` | optional | ptr→void | yes |
| `semantic_analyzer.zig:6425` | array | slice-elem (any) | same as `:3709` |
| `semantic_analyzer.zig:6796-6797` | array | annotated/inferred elem (any) | same as `:3709` |
| `type_resolver.zig:2022` (EU) / `:2123` (opt) / `:2146` (array) via `resolveTypeExprFull` | all three | any type-expr child | pre-pass → pass completes; post-pass → creation math / in-place completion (see equivalence argument) |

Every lowering site that creates a composite **of a non-primitive** is the `resolveTypeExprFull` choke point or a sema site already covered above; no lowering site creates a composite over a pending payload without a later completion opportunity, and the pure-primitive sites need none.

### Planned edits (this task)

1. `type_registry.zig`: unconditional `MapPut` in Optional (`:835`) and Array (`:911`); add `optionalCompleteIfReady` / `errorUnionCompleteIfReady` / `arrayCompleteIfReady` (in-place completion, creation-time math) called from each GetOrCreate cache-hit path; add `typeRegistryTypesEquiv` and use it in the `fn_type` arm of `typeRegistryIsAssignable` (return + params).
2. `sf/src/tests/test_sym_reg_bin.zig`: dedup + completion tests (RED first where observable pre-fix).
3. No emit/lowering/analyzer changes. Goldens captured at fixture flip.

## Implement

All edits in `sf/src/type_registry.zig` (single file; no tech-doc change).

1. **`typeRegistryGetOrCreateOptional` (:814+)** — cache-hit path now runs `optionalCompleteIfReady` before return; the MapPut is unconditional (was `if (opt_state == 2)` at old `:835`), with a D1 comment. Model: `typeRegistryGetOrCreatePtr:739`.
2. **`typeRegistryGetOrCreateArray` (:940+)** — same two changes (`arrayCompleteIfReady` on hit; unconditional `MapPut`, was guard at old `:911`). Array marker telemetry (`O0e/O1H/O2N`) untouched.
3. **`typeRegistryGetOrCreateErrorUnion` (:909+)** — cache already unconditional (unchanged); cache-hit path now runs `errorUnionCompleteIfReady` (kills the T0 C5a pending-layout freeze residual).
4. **In-place completion helpers** `optionalCompleteIfReady` / `errorUnionCompleteIfReady` / `arrayCompleteIfReady` (inserted before `GetOrCreateOptional`, ~`:814-878`) — the on-demand layout guarantee (see Investigate equivalence argument). Guarded by `payload/elem.state == 2` (never reads a pending payload; `typeRegistryRegisterNamedType:1208` creates `state=0` so `state==2` ⇒ layout final); math is the creation-time math verbatim. Not `layoutEnsure` at `resolveTypeExprFull` sites — that would freeze premature layouts pre-pass (registration-order hazard, Investigate).
5. **`typeRegistryTypesEquiv` + `typesEquivRec`** (before `typeRegistryIsAssignable`, `:1887+`) — structural equivalence over the synthetic family (optional→payload, error_union→payload + error-set id, array→elem+length, slice→elem+const-flag, tuple→element list, fn_type→return+params+flags; everything else id equality; depth cap 16). The `fn_type` arm of `typeRegistryIsAssignable` (was `:1830-1849`) is now `if (typeRegistryTypesEquiv(self, source, tpp.base)) return true;` — belt-and-braces structural return+params comparison. (`FN_FLAG_STDCALL=2` + `is_variadic` bit 0 ⇒ `flags_packed` equality ≡ the old `& 1`/`& 2` checks.)
6. **Not changed (audit):** `GetOrCreateTuple` stays cache-free (R1 ruling); `GetOrCreateSlice` verified canonical; `GetOrCreateErrorSet`/Ptr/ManyPtr/Fn untouched; no emit (`c89_emit.zig`) / lowering / analyzer edits.

### Rulings

- **R1 (tuple audit, no cache):** tuple literal ids are per-occurrence anonymous types; consumers are structural (`isAssignable` tuple arm pairwise-elems, `typeRegistryTupleElem` by ordinal, sema per-node memo `semantic_analyzer.zig:6683-6705`); spelled tuple types are name-cache canonical (`type_resolver.zig:1697`). Tuple is NOT the D1 bug class (no layout-conditional caching exists there). A content cache would conflate occurrence-keyed consumers (`ctx.tuple_index_table`, `needed_tuple_set`) and move tuple typedef emission. Cost if wrong: re-run T1 battery after adding an `xt`-content cache.
- **R2 (late layout = in-place completion, not `layoutEnsure` plumbing):** see Investigate equivalence argument — coverage is ≥ pre-fix at every creation-after-resolve path (census table). Cost if wrong: add `layoutEnsure` at the `semantic_analyzer.zig:3709/6425/6796` + `type_resolver.zig:2022/2123/2146` sites (post-pass-guarded).
- **R3 (no unit tests added):** `sf/scripts/build_test.sh` is pre-existing broken (`0/9 (pre-existing)` per `docs/sf/QUICK_REF.md`; zig0 rejects current `ast.zig`) and `test_sym_reg_bin.zig` is stale vs `semanticAnalyzerInit`'s signature (dump with the gate compiler fails at `test_sym_reg_bin` call sites) — unit-level RED/GREEN is unverifiable without an unrelated test-suite fix. The fixture is the test: RED re-observed in-session on the gate compiler, GREEN on the fixed compiler. Cost if wrong: a latent registry regression covered only by the corpus battery.
- **R4 (designed-flip trajectory deviation — STOP-present):** `I found the intention is coerce GREEN→OK at T1, but this is impossible given` bug 2 (emit ordering) is T2-scoped (`fnptr_opt_aggregate_coerce_xmod` carries the same `fn (*void) ?Key` fp-typedef shape as `fnptr_opt_aggregate_emit_xmod`, so its emitted C cannot gcc-compile until T2): measured flip is **GREEN→FAIL** (frontend fixed; gcc blocked at `zig_special_types.h:637` fp-typedef before `:744` optional typedef). The fixture's NOTES/header "compiles and runs → class OK, goldens captured at T1" was authored across both bug halves. T1 keeps the identity half only (dispatch: "no emit-ordering changes (T2)"). Cost if wrong: if the operator intended T1 to include the ordering fix, T2 brief shrinks and this report's flip record needs one edit.

## Runtime battery

Gate compiler: `/tmp/d1d2_t1/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t1`. Every claim = command + observed output.

### 1. Seed two-hop
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t1
→ [seed] hop2 binary md5: 69cf0269933a8b943453fa7bce0e25cc
  [seed] two-hop closure OK: hop1 == hop2 == 69cf0269933a8b943453fa7bce0e25cc
```
**MATCH** (closure held at first convergence). Fixed point moved (expected — `sf/src` changed): `f18b69ece1917bf970a036b276e5e403` → **`69cf0269933a8b943453fa7bce0e25cc`** (old→new recorded; seed rotation is closeout-owned, NOT done here).

### 2. Corpus classify (post-T0 1130-line gate)
```
bash scripts/corpus/classify /tmp/d1d2_t1/zig1_5_clean /tmp/d1d2_t1work/corpus_t1.txt
→ wrote …: 1130 dirs
frozen 1124 subset (6 designed fixture lines removed): md5 518eca1a9b5d3e1cc5a48abce214abd8
  byte-identical to T0 anchor 518eca1a9b5d3e1cc5a48abce214abd8 (diff empty) → 0 movers
tally: 952 OK / 58 GREEN / 120 FAIL / 0 ICE / 0 CRASH (postfixture was 952/58/119)
```
**Frozen 1124 class-identical, 0 movers.** Designed 6 lines (the only mover is the T1 fixture):

| fixture | T0 post-landing | T1 | designed? |
|---|---|---|---|
| `fnptr_opt_aggregate_coerce_xmod` | GREEN | **FAIL** | **YES — T1 flip (R4: GREEN→FAIL, not the predicted GREEN→OK; frontend fixed, gcc blocked by T2's ordering bug)** |
| `fnptr_opt_aggregate_emit_xmod` | FAIL | FAIL | unchanged (T2) |
| `fnptr_opt_aggregate_errunion_xmod` | FAIL | FAIL | unchanged (T3) |
| `iswindows_deadarm_errunion_xmod` | FAIL | FAIL | unchanged (T3) |
| `iswindows_deadarm_prune_xmod` | OK | OK | unchanged (T3) |
| `conditional_import_if_xmod` | FAIL | FAIL | unchanged (T4) |
| `conditional_import_switch_xmod` | OK | OK | unchanged (T4) |

The 1130-line class file is `/tmp/d1d2_t1work/corpus_t1.txt`; the single diff line vs T0's `corpus_postfixture.txt` is the coerce fixture.

### 3. Goldens 5/5
Build: `zig1_5_clean --dump-c89 <ENTRY> > g.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include g.c zig_runtime.c zig_pal.c -o g` — all 4: dump rc 0, gcc rc 0, 0 `error:`.

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
bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_t1/zig1_5_clean <T0 §3.4 frozen 25 by name>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
**25/0 MATCH** (explicit list: `array_of_struct_literal_xmod`, `catch_discard_struct_xmod`, `const_assign_ok_xmod`, `empty_named_struct_field_xmod`, `empty_named_struct_xmod`, `enum_subbyte_backing_xmod`, `f64_literal_precision_xmod`, `field_store_continue_nested_xmod`, `field_store_continue_xmod`, `fn_ptr_signature_ok_xmod`, `for_range_end_len_xmod`, `len_array_field_xmod`, `lexer_float_exponent_xmod`, `lit64_decimal_xmod`, `nested_loop_label_xmod`, `optional_void_present_xmod`, `packed_nested_whole_depth_ok_xmod`, `packed_nested_wholeliteral_xmod`, `packed_union_struct_wholemember_xmod`, `shadow_ok_xmod`, `sig_known_type_ok_xmod`, `slice_index_field_store_xmod`, `tagged_payload_whole_reassign_xmod`, `tagged_tag_member_shadow_xmod`, `tagged_tag_sugar_xmod`).

oob trap `slice_index_field_store_oob_xmod` (`-fsafe -o`, build_target): dump rc 0, build rc 0, run **rc 133**, stdout 0 B md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` (rc pin `133`). **MATCH.**

### 5. Examples 26/26 build + 26/26 run
Build per dir (`zig1_5_clean -ffast -o <out> <entry>` + `sh build_target.sh linux <out>/prog`, CWD out-dir): **26/26 OK** (dump rc 0, ≥1 `.c`, build rc 0). Run (CWD=example dir, `timeout 25`, mud `timeout 8`, stdin `/dev/null`, rogue* fed `q\n`): **26/26 correct** — every stdout md5 == T0 §3.5 table: days_in_month `8c0d394c…`, fibonacci `b53b3a3d…`, func_ptr_return `f6a54779…`, gol `fcbf7e7c…`, heapsort `8cf0a784…`, hello `74630882…`, json* `8bda3d5a…`×2 / `dc22fa47…`, lisp* `1c1f0a41…`×4, lzw `c3c7765e…`, mandelbrot `d5966775…`, mud rc 124 `9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`, rogue* `3fb6709e…`×2, sort_strings `c6c047cb…`, tco `264ea6b1…`/`3d70c50b…`/`7421137a…`, z9torr rc 1 `f666af15…`, z9play rc 1 `f35b7ef7d832cc4a…` (C1 usage banner). **26/26 MATCH.**

### 6. Stdlib
```
bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_t1/zig1_5_clean
→ run_fixtures: 285 PASS / 0 FAIL over 285 dirs
  STDLIB GATE OK
```
**285/0 MATCH.**

### 7. The 8 `--dump-c89` pins (old→new)
`/tmp/d1d2_t1/zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum` (repo root):

| entry | `-fsafe` old→new | `-ffast` old→new | delta |
|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` → same | `fa346108ed00d03a037c2f9331d3bdf8` → same | **0** |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` → same | `01a4e2265b33c97a8ca6ff3dfa551231` → same | **0** |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` → same | `e3970e33ac09c8dfaa316d2d69bf61ec` → same | **0** |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` → same | `24e0e812e7dffa5a43750135405ffe3f` → same | **0** |

**old→new: 8/8 UNCHANGED, pin delta count 0** (operator pre-approval unused — these 4 entries never trip the pending-twin path, so type-id allocation is identical).

### 8. Markers telemetry
```
zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin
→ marker_lines=3437 bytes=38384
top prefixes: 2005 INT:new / 423 DC:k / 241 FE:p / 195 P / 195 FWD:n= / 122 RaD / 86 MT / 69 FE:
```
**3437 lines / 38384 B — identical to T0 baseline** (no marker drift).

### 9. Runtime golden at the fixture flip
**None reachable.** `fnptr_opt_aggregate_coerce_xmod` is dump-clean post-T1 (rc 0, 6 `.c`, 0 diagnostics — the identity fix's designed frontend flip) but its emitted C fails gcc on the T2-owned ordering gap (`zig_special_types.h:637` `typedef zT_B1EBCC6C_Opt_23 (*zT_5D2AA370_FP_…)(void*);` precedes the `:742-745` optional typedef; `run_fixtures.sh --capture` refuses at GCCFAIL). Per T0 R1 ("produce the goldens now **where the fixture becomes reachable**") and the dispatch ("Record a runtime golden for **any fixture that becomes reachable**"), reachability arrives at T2 — capture `expected.txt`=`coerce sigint ok\n` / `expected.rc`=`0` there. The pre-fix RED census (`expected.rc`=2 dump-rc + `expected_error.txt`) remains the committed RED record.

### 10. Battery summary table

| gate | T0 frozen | T1 observed | verdict |
|---|---|---|---|
| seed two-hop | `f18b69ece1917bf970a036b276e5e403` | hop1==hop2==`69cf0269933a8b943453fa7bce0e25cc` | closure OK; fixed point moved (recorded old→new) |
| corpus frozen 1124 | md5 `518eca1a9b5d3e1cc5a48abce214abd8` | byte-identical `518eca1a9b5d3e1cc5a48abce214abd8`, 0 movers | MATCH |
| designed 6 fixture lines | coerce GREEN | coerce **FAIL** (R4), 5 others unchanged | 1 designed flip recorded |
| goldens | 5/5 | 5/5 identical | MATCH |
| mi_matrix 25 + oob | 25/0 + rc 133 | 25/0 + rc 133/empty | MATCH |
| examples | 26/26 + 26/26 | 26/26 build + 26/26 run correct | MATCH |
| stdlib | 285/0 | 285/0 STDLIB GATE OK | MATCH |
| 8 pins | == QUICK_REF table | 8/8 unchanged (delta 0) | MATCH |
| markers | 3437 lines / 38384 B | 3437 lines / 38384 B | MATCH |
| fixture runtime golden | n/a pre-fix | not reachable (T2 gate) | recorded (R4) |

## Concerns

- **C1 (designed-flip trajectory, load-bearing — R4):** coerce flips **GREEN→FAIL** at T1, not the documented GREEN→OK: the identity fix makes the frontend accept (0 diagnostics, 6 `.c`) but the class is gcc-gated and the T2-owned emit-ordering gap blocks gcc (identical shape to `fnptr_opt_aggregate_emit_xmod`). T2's flip then becomes coerce FAIL→OK **and** emit FAIL→OK. If T0's §2.2 trajectory table is consumed by later gates, its "coerce GREEN→OK (T1)" row needs the T2-caveat (or T2 rewrites it at its own flip).
- **C2 (golden capture deferred):** per R4 — `run_fixtures.sh --capture` for `fnptr_opt_aggregate_coerce_xmod` must run at T2 (its header GREEN contract: stdout `coerce sigint ok\n`, rc 0, 3× deterministic). T0's "goldens captured at T1" sentence in the fixture header/NOTES is superseded by this.
- **C3 (unit-test channel dead):** `build_test.sh` 0/9 pre-existing (zig0 dialect drift on `ast.zig`) and `test_sym_reg_bin.zig` is stale vs `semanticAnalyzerInit` — no unit RED/GREEN possible without an unrelated suite repair (out of scope). Registry-level coverage rides on the 1130-dir corpus + battery. If the operator wants unit tests for the dedup/completion paths, a test-suite refresh is its own task.
- **C4 (in-place completion + structural fn_type comparison unexercised by corpus):** pins 8/8 + markers identical prove no emitted-code change for the 4 gate entries; the pending-twin re-request path (the completion helpers' trigger) and the structural fn arm are only exercised by the D1 fixture's frontend (which is now GREEN at dump). The helpers are inert-by-construction when nothing re-requests a pending composite. Watch T2's battery for unexpected pin movement from these paths.
- **C5 (residual late-layout gap, pre-existing):** a composite created post-pass over a still-pending payload, never re-requested and never `layoutEnsure`d (sema `:5949` covers decl types), keeps `state=0`/size 0 — pre-fix it had no correct id either (no request ever saw a ready payload). Unchanged by design (R2); close if a repro appears.
- **C6 (tuple observation, not changed):** `typeRegistryGetOrCreateTuple:915` creates `state=2` with size 0/align 1 while `layoutCompute` has real tuple math — literal tuples rely on emit-side typedefs; flagged for T2/emit work if tuple-of-aggregate stack layouts ever matter. Not identity-unsafe (R1), out of T1 scope.
- **C7 (fixed point moved; seed NOT rotated):** `f18b69ece1917bf970a036b276e5e403` → `69cf0269933a8b943453fa7bce0e25cc`. Seed rotation is a closeout action (per seed-bootstrap spec "Rotation only at plan closeout") — left to the milestone closeout across T2–T5; recorded here so T2's battery compares against `69cf0269…`.


