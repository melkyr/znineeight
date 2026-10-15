# Task P9 report — Structural frame-save rule (WHAT/HOW split)

Branch `zig1_improvements`, BASE `fc04f4f5` (confirmed `git rev-parse HEAD` = `fc04f4f52c92ea3317fc47aeb5f2cd03e186e828`). Requirements: `task-P9-brief.md` (binding, incl. controller pre-check facts). Shape: Investigate (written before source edits) → Implement (one commit (a)) → full 8-item runtime battery → this report (commit (b)).

**Status: COMPLETE** — the structural frame-save rule lands as one compiler-moving commit (a) `c2772f6a` (WHAT decided at the async-construction authorities + carried on the frame layout; the emitter spells; D3/D4 root cause closed at the save SET — the global by-value round-trip is gone); full 8-item runtime battery green with **pins 0/8 (the required zero)** and **markers unchanged**; no STOP. The only C delta is the sanctioned "less save/reload traffic" class on the one battery program that carried a live-across alias (`z9torr`, −3,810 B + frame relayout; runtime frozen) plus the D3/D4 repro shapes (18×2 round-trip lines → 0).

## Investigate (written before source edits — 2026-10-15)

### 1. Census (re-derived by NAME at HEAD `fc04f4f5`; matches controller pre-check)

**The frame-save round-trip (the save/restore machinery):**

1. **`saveAllFields`** (`sf/src/async_state_machine.zig:265-276`): walks `lay.fields` and `storeField`s EVERY `ASYNC_FIELD_PARAM`/`ASYNC_FIELD_LIVE` field **by value** into the frame (`:269-270`) plus the hidden child (`:273-275`). Callers: `emitAwait` step (9) (`:575`) and the explicit `@asyncSuspend` (`kk == 1`) yield path (`:1200`).
2. **`reloadAllFields`** (`sf/src/async_state_machine.zig:278-293`): walks `lay.fields`, `loadField`s and `assign`s EVERY PARAM/LIVE field back to `fld.temp_id + b.base` (`:282-284`) plus the child (`:287-290`). Callers: `emitAwait` step (10) (`:584`) and the `@asyncSuspend` resume path (`:1210`).
3. **The carried set**: `asyncLayoutFrame` (`sf/src/async_frame_layout.zig:522-670`) computes the live-across-suspension set (`instIsSuspendPoint` + `hasDefBefore`/`hasReadAfter`, `:585-604`) and adds the carried fields: `ASYNC_FIELD_PARAM` in param order (`:615-617`) and `ASYNC_FIELD_LIVE` in temp-id order (`:618-624`, controller-cited `:615-621`). `ASYNC_FIELD_*` kinds `:43-50`. The layout is published pre-transform (`asyncLayoutPublish`, `main.zig` phase A) and is the ONLY carrier the generators read.

**The undeclared-temp class (D3/D4 root cause):**

- `lowerGlobalRef` (`sf/src/lower.zig:4256-4269`), the module-alias `lowerLValueAddr` arm (`sf/src/lower.zig:2523-2546`, `load_global` `:2542`) and the mid-alias const-ref arm (`:4432`) emit `load_global{name_id, module_id, result}`. The result temp is a **module-global alias**: the `.load_global` emit arm (`sf/src/c89_emit.zig:6468-6472`) registers `temp_global_map` and emits NO statement; `resolveTempName` (`sf/src/c89_emit.zig:5664-5682`) spells the mangled global name for the temp at every reference. The emitter NEVER declares such a temp: the decl loop suppresses it via `d4_nodecl` (`dceMarkLoadGlobalAliases`, `sf/src/c89_emit.zig:7939-7956` → skip at `:2967`) and via `written_flag == 3` for large module-var array aliases (`:2637-2646` → skip at `:2964`).
- When a `load_global` alias is live across a suspension (the loop-carried `&g` shape — D3's `&g_reader` in the read loop, D4's same), `asyncLayoutFrame` hoists it as `ASYNC_FIELD_LIVE` → `saveAllFields` emits `*frame_slot = <global name>` at every yield and `reloadAllFields` emits `<global name> = *frame_slot` at every resume — the **global by-value round-trip**: the global's value is copied into the frame and (stale-copy) written BACK INTO THE GLOBAL on resume. Pre-F3 the save named the raw undeclared `zT_N` (`gcc: 'zT_NNN' undeclared`); F3 (`06a7a793`) closed the SPIT site by pre-walking `temp_global_map` in `emitFunctionBody` (`sf/src/c89_emit.zig:8133-8150`) so the save/restore spells the global name. The round-trip traffic (and the stale write-back) remained — that is P9's target.

**Decl-loop skip cascade = "declared vs alias" classes** (`sf/src/c89_emit.zig:2958-2967`; each class checked against the save set):

| class | encoding | in the save set today? | P9 treatment |
|---|---|---|---|
| params | `temp_id < params.len` (declared in the signature) | yes | KEEP (declared) |
| nest-inlined | `nest_inl == 1` | **structurally impossible** — a nest candidate needs `rc == 1` (`lir_opt_pass.zig` candidate rule (d) `:978-983`); a saved temp has the save `store`'s value read + its real read(s) → `rc ≥ 2` | none needed (argument §3) |
| large module-var array alias | `written_flag == 3` | yes (alias class) | EXCLUDE |
| dead | `d4_dead == 1` | **structurally impossible** — the save `store` value is counted by `dceMarkAllReads` (`:7970+`, `.store` arm) → `read_count ≥ 1` | none needed |
| named local | `d4_local == 1` (declared via the `decl_local` preamble walk) | yes | KEEP (declared) |
| `load_global` alias | `d4_nodecl == 1` | **THE D3/D4 class** | EXCLUDE |
| `TYPE_VOID` (`eff_type == 1`, no decl line) | — | not reachable as a saved value today (a void by-value slot would already be invalid C); enumerated as a residual, zero known sites | out of scope (no unrelated fixes) |

So "save/restore only declared temps" reduces at this HEAD to EXACTLY the alias-class exclusion; the other undeclared classes are structurally unreachable from the save set (§3 arguments).

**`nest_inl` machinery (the cited `c89_emit.zig:3827-3828` guard, drifted):** the suppression-path guards now sit at the decl loop (`sf/src/c89_emit.zig:2961-2962`), `emitValueExpr` (`:3364-3377`) and the body def walk (`:8287-8289`). `emitNestCompute` (`:3319-3351`) fills `nest_inl` per temp from `lirOptNestCandidate`/`lirOptNestDepthOf`/`lirOptNestConsLoc` (optimizer-recorded tables, `sf/src/lir_opt_pass.zig:108-165`, filled by `computeNestMetadata` `:934-1075`) plus `nestConsumerWired` (`:3217-3316`) and `nestShapeOk` (`:3170-3216`). See §3 for the ruling argument (spelling with carried inputs; no change).

**Census experiment (pre-edit, baseline compiler `/tmp/p9_base/zig1_5_clean` = two-hop of HEAD, `31b73acf…`):** the alias round-trip's emitted shape is `*zT_p = zG_g;` (save) / `zG_g = zT_v;` (reload). Dump census of the 8-pin programs (`-fsafe` + `-ffast`): **0 save-of-alias and 0 frame-reload-to-alias in all 4 pin programs in both modes** (the few `zG_x = zT_y` hits are ordinary module-init/global stores, not frame reloads) → **pins 0/8 expected**. `examples/z98/z9torr` (`-ffast`) DOES carry the round-trip: 9× `*zT_834… = zG_02BA9009_SCAN_MAX;` + 9× `zG_02BA9009_SCAN_MAX = zT_…;` (the `const SCAN_MAX` alias live across the scan-loop suspensions in `peerRun`) → the example's C **shrinks** (and its frame relayouts, see §4); runtime must stay frozen (`f666af15cf2625b3`).

### 2. Edit plan (precise; executed bottom-to-top per file, `edit`/`fastedit` only)

The WHAT decision executes at the async-construction authorities; the set is CARRIED on the frame layout (the `ASYNC_FIELD_PARAM`/`ASYNC_FIELD_LIVE` list is the save set); the emitter already SPELLs the save/restore from the carried set (the LIR `store`/`load`/`assign` insts built from the layout) — it never computes the set.

1. **`sf/src/async_frame_layout.zig` (carried set home + "remove the global by-value round-trip"):** new `pub fn asyncTempIsGlobalAlias(lir_fn, temp) bool` — the alias-class predicate, a pure read of the lowering-recorded `load_global` defs (the fact `lower.zig` writes at `lowerGlobalRef`/the module-alias arms; the `load_global` inst IS the carried record — **no new `lir.zig` field is needed**, named explicitly per the brief). `asyncLayoutFrame`'s `ASYNC_FIELD_LIVE` add (`:618-624`) skips alias temps: a global alias has no private storage (the module global IS its storage), so it gets **no by-value frame slot** and the round-trip is gone at the carrier. The carried set = the save set = only declared temps.
2. **`sf/src/async_state_machine.zig` (WHAT — "save/restore only declared temps"):** `saveAllFields` (`:269-270`) and `reloadAllFields` (`:282-284`) skip fields whose temp is a global alias (`async_frame_layout.asyncTempIsGlobalAlias(b.orig, fld.temp_id)`). This is the save/restore SET decision at the generators — the binding clause 1 enforced where the save/restore insts are built (clause 2's slot removal is the layout's half; either filter alone closes D3/D4, both are kept as the rule at the set's carrier and its consumer).
3. **`sf/src/c89_emit.zig`:** no functional change — the emitter's save/restore spelling is already "from the carried set" (LIR spelling) and the F3 `temp_global_map` alias spelling must keep working (invariant). One short comment at `dceMarkLoadGlobalAliases` records the interlock (the alias class is `load_global`-derived; the async save set never contains these).
4. **`sf/src/lower.zig`:** no code change — the alias fact is already recorded at the `load_global` construction sites (`lowerGlobalRef:4268`, `lowerLValueAddr:2542`, `:4432`); the save-set decision CONSUMES that fact at the async-construction sites above. No new LIR record field (the `load_global` inst carries the class; a redundant `TempDecl` flag would add copier surface (`remapInst`/hoisted-copy precedent `82ff0743`) for zero information).
5. **Tech docs** `[updated: 2026-10-12 — P9 …]` stamps: `12_async_coroutines.md` (§3 live-row rule + the F3/D3/D4 section gains the P9 root-cause paragraph), `08_c89_emission.md` (the declared-vs-alias spelling note + nest guard ruling), `07_lir_lowering.md` (the `load_global` alias fact row), `INDEX.md` (`asyncTempIsGlobalAlias` + updated rows).

### 3. Invariants — preservation map + the `nest_inl` ruling argument

| invariant | how preserved |
|---|---|
| `__Z98Step_<f>` signature/frame convention (`async_state_machine.zig:5-13`) | untouched |
| child/parent-result fields (`saveAllFields` `:271-273`, `reloadAllFields` `:283-286`) | untouched (saved/restored as today) |
| `remapInst` copier-only (ruling 1a) | untouched — no new LIR record field (see §2.4) |
| temp-id base remapping (`b.base`) | untouched (the alias predicate tests the ORIGINAL `fld.temp_id` against `b.orig`, exactly as the save/restore spell the remapped id) |
| `temp_global_map` alias behavior (F3 must keep working) | untouched — `c89_emit.zig:8133-8150` pre-walk + `resolveTempName` spelling stay; D3/D4 repro link-clean is battery-gated |
| `nest_inl` inline rendering byte-shape (pins prove it) | untouched — no nest code changes |
| P10 `lowerIndexElemAddr`/checked-path work | untouched (`lower.zig` not edited) |
| authoritative `frame_sizes` vs layout (`precise <= frame_sizes`) | untouched — dropping LIVE fields only shrinks `precise`; the layout still pads up to `frame_sizes` (`async_frame_layout.zig:658-670`) |
| callee-arg install reads callee PARAM offsets (`async_state_machine.zig:541-547`) | untouched (params never excluded) |

**The `nest_inl` suppression-path guard is legitimate C-shape spelling with carried inputs (the brief's "say so with the argument"):** every input that decides membership is carried/recorded before the guards run, and no guard decides the save set:

- **The save set** is carried on the frame layout (post-P9 = only declared temps). The guards never consult or alter it. The interlock is structural: a saved temp has `rc ≥ 2` (the save `store`'s value read plus its real read), so it can never be a nest candidate (`lir_opt_pass.zig` rule (d) requires `wc == 1 and rc == 1`), and never dead (`dceMarkAllReads` counts the save's read). The suppression path can therefore never suppress a save-set member — the D3/D4 failure class (a save naming an undeclared temp) is closed at the set's construction, not by the guard.
- **The inline set** (`nest_inl`) membership is a conjunction of recorded facts + C-shape predicates over them: `lirOptNestCandidate`/`lirOptNestDepthOf`/`lirOptNestConsLoc` are the optimizer's decisions, recorded in the opt tables (`lir_opt_pass.zig:2130-2134` publication; the pass runs per function before decl/body emission in `emitFunctionSet` `c89_emit.zig:2166-2171`); `nestConsumerWired`/`nestShapeOk` read the recorded def/consumer insts at the recorded locators and the recorded `TempDecl`/registry types and answer only "can this def be spelled as ONE inline C rvalue" — the C-shape admissibility question (sat ops, width-wrap, optional-null, aggregate results cannot be one rvalue). They re-derive no semantic fact owned elsewhere (P6 moved those out). The guard sites (`:2961-2962`, `:3374`, `:8287-8289`) only READ `nest_inl` and skip — spelling.
- Residual placement note (not a decision): `lirOptRun` is invoked from `emitFunctionSet` (pre-existing since T4a) — the OPTIMIZER decides there and records; the emitter consumes. P9 does not move the opt (out of the touch set and out of the plan text); the ruling question was whether the EMITTER decides set membership from uncarried inputs — it does not.

No corner of the plan text required an improvisation; no new emit-time deciding helper is introduced → no STOP.

### 4. Behavior-delta analysis (predicted)

- The 4 pin programs (mud/gol/lisp/json, both modes) have ZERO alias round-trips (§1 census) → **pins 0/8 expected**, corpus class file byte-identical expected.
- `z9torr` (example battery) drops the 9× `SCAN_MAX` save + 9× reload pairs and relayouts `peerRun`'s frame (the alias slot at offset 572 and its neighbours shift) → its emitted C changes (shrink + relayout); the example's .c file COUNT is unchanged; runtime stdout md5 must stay `f666af15cf2625b3` (the round-trip of a constant global is value-preserving; removing it cannot change values).
- D3/D4 repro shapes (z9torr patched to the defect-doc form: module-global `MsgReader` + `&g_reader`): the save/restore no longer names or copies the global at all — must link clean (F3 preserved or improved: the save block no longer references the alias in any spelling).
- Any runtime OUTPUT change on an in-bounds program = STOP-present (none expected: the removed traffic copies a value whose authoritative home is the global itself; post-resume reads of the alias spell the global name both before and after this change).

## Implement (commit (a) `c2772f6a` — the §2 edit plan, executed)

One compiler-moving commit `(a) refactor(async_state_machine): P9 — structural frame-save rule: save/restore only declared temps, drop the global by-value round-trip (D3/D4 root)` (`fc04f4f5..c2772f6a`; 7 files, +60/−6 — `sf/src/async_frame_layout.zig` +27, `sf/src/async_state_machine.zig` +8, `sf/src/c89_emit.zig` +4 (comment), `sf/docs/tech_docs/{07_lir_lowering,08_c89_emission,12_async_coroutines,INDEX}.md`). `sf/src/lower.zig` and `sf/src/lir.zig` UNTOUCHED (named explicitly per the brief: **no `lir.zig` semantic record field is needed** — the `load_global` inst is the lowering-recorded alias fact; see §2.4). Committed state (line refs at `c2772f6a`):

- **NEW `asyncTempIsGlobalAlias(lir_fn, temp) → bool`** (`async_frame_layout.zig:522-544`): the alias-class predicate — a pure walk of the LIR's `load_global` defs. One definition, consumed at both decision sites.
- **`asyncLayoutFrame` `ASYNC_FIELD_LIVE` add** (`async_frame_layout.zig:641-650`): skips alias temps ("remove the global by-value round-trip" — no by-value frame slot; the global is the alias's storage). The carried `ASYNC_FIELD_PARAM`/`ASYNC_FIELD_LIVE` list IS the save set = only declared temps.
- **`saveAllFields`/`reloadAllFields`** (`async_state_machine.zig:265-280`/`:282-299`): the save/restore generators skip alias fields ("save/restore only declared temps" — the SET decision at the generators). Both walks otherwise verbatim (child field untouched). NOTE (deliberate, see Concerns C3): after the layout filter the generator filter is unreachable for the current layouts — kept as the structural enforcement of clause 1 at the save/restore construction site (each of the two sites owns one clause of the binding sentence; either alone closes D3/D4).
- **`dceMarkLoadGlobalAliases`** (`c89_emit.zig:7939-7942`): comment only — the emitter's undeclared-alias class is `load_global`-derived and now never enters the save set; F3's `temp_global_map` pre-walk (`:8137-8157`) + `resolveTempName` spelling untouched (invariant).
- **Tech docs** `[updated: 2026-10-12 — P9 …]` stamps: `12_async_coroutines.md` (H1 stamp, §3 LIVE row note, the §8 F3 entry gains the P9 root-cause paragraph), `08_c89_emission.md` (H1 stamp incl. the `nest_inl` ruling), `07_lir_lowering.md` (H1 stamp + the `load_global` row notes the alias fact), `INDEX.md` (H1 stamp + the `asyncTempIsGlobalAlias` row).

No behavior question required an improvisation; no new emit-time helper of any kind → no STOP.

## Runtime battery (8 items; compiler `/tmp/p9_build/zig1_5_clean`, two-hop build of the committed tree)

### 1. Seed two-hop

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p9_build` → `[seed] hop1 binary md5: 3c0376fc62002297029f6ecc278a259c` / `[seed] hop2 binary md5: 3c0376fc62002297029f6ecc278a259c` / `[seed] two-hop closure OK: hop1 == hop2 == 3c0376fc62002297029f6ecc278a259c`. **hop1==hop2**; fixed point `31b73acfb486375722d56a5dcc1e6a0c` (P10 record) → **`3c0376fc62002297029f6ecc278a259c`** (moved as expected — `sf/src` moved; recorded; seed NOT rotated — Task C).

### 2. Corpus classify (class FILE vs frozen `518eca1a…`)

`bash scripts/corpus/classify /tmp/p9_build/zig1_5_clean /tmp/p9_run/corpus.txt` → `wrote /tmp/p9_run/corpus.txt: 1124 dirs`; `md5sum` = `518eca1a9b5d3e1cc5a48abce214abd8` = frozen `518eca1a…` (**byte-identical, 0 movers**); tally `1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH` (unchanged).

### 3. Goldens 5/5

dump+gcc (recipe task-0 §1.3) all rc=0 (0 `error:`). gol `timeout 120 ./gol` = `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `printf '(+ 1 2)\n' | timeout 60 ./lisp` = `b3d9f8974da24ddbf9d389f3d7d97322`; json (CWD `examples/z98/json_parser`) = `8bda3d5a1ec07d14a301bc343df32bf8`; mud session (`examples/z98/mud_server/demo/session.sh`) rc=0, server `66c8f0abb926cca7baf9a0d1692ab318`, client `93147d0f0bbd983a9d844fea8b7a6fa7`; both mud files `cmp`-IDENTICAL to `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt`. **5/5 = frozen.**

### 4. mi_matrix 25 + oob

SET DEFINITION (progress.md, load-bearing) enumerated → the 25 dirs (`array_of_struct_literal_xmod` `catch_discard_struct_xmod` `const_assign_ok_xmod` `empty_named_struct_field_xmod` `empty_named_struct_xmod` `enum_subbyte_backing_xmod` `f64_literal_precision_xmod` `field_store_continue_nested_xmod` `field_store_continue_xmod` `fn_ptr_signature_ok_xmod` `for_range_end_len_xmod` `len_array_field_xmod` `lexer_float_exponent_xmod` `lit64_decimal_xmod` `nested_loop_label_xmod` `optional_void_present_xmod` `packed_nested_whole_depth_ok_xmod` `packed_nested_wholeliteral_xmod` `packed_union_struct_wholemember_xmod` `shadow_ok_xmod` `sig_known_type_ok_xmod` `slice_index_field_store_xmod` `tagged_payload_whole_reassign_xmod` `tagged_tag_member_shadow_xmod` `tagged_tag_sugar_xmod`). `bash scripts/stdlib/run_fixtures.sh /tmp/p9_build/zig1_5_clean <25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**. Trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`), `expected.rc=133`. **MATCH.**

### 5. examples 26/26 build + 26/26 run

Build (`-ffast -o`, output dirs pre-created, `build_target.sh linux`): 26/26 dump=0 / `.c` counts identical to task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* fed `q\n`): 26/26 rc + stdout md5_16 IDENTICAL to §1.4 — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, **z9torr rc=1 `f666af15cf2625b3`** (frozen despite the C shrink — O2).

### 6. stdlib

`bash scripts/stdlib/verify_stdlib.sh /tmp/p9_build/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK`.

### 7. The 8 `--dump-c89` pins (old → new; sequential from repo root)

| entry | mode | old (P10 record) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `bbc02913a10af9b0b5ed0f292f4e3407` | `bbc02913a10af9b0b5ed0f292f4e3407` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `93c5e3fdc5b80b2f3db020d995abbe3f` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `6da05d070acd414674b1b1ec947baa5c` | `6da05d070acd414674b1b1ec947baa5c` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `af3823fae0b29fa4d4ca58932538d631` | `af3823fae0b29fa4d4ca58932538d631` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — byte-identical, the REQUIRED zero** (the brief's "same save/restore set" ideal holds on the whole pin corpus: §1's pre-edit census found no live-across alias in any pin program, and the battery confirms it).

### 8. Markers telemetry

`/tmp/p9_build/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,437 lines / 38,384 B** = record **3,437 / 38,384** (unchanged; telemetry, per the P2/P10 precedent).

### D3/D4 reproducers (brief: must still link clean — F3 preserved or improved)

In-example shapes from `examples/torrent_example_defects.md` (applied to a `/tmp` copy of `examples/z98/z9torr` — repo tree untouched): D3 = module-global `var g_reader: std_stream.MsgReader` field-initialised + `&g_reader` at both `wire.readMessageAsync*` loop sites; D4 = `g_reader = std_stream.initMsgReader(&peer.sock, peer.read_buf[0..]);` (the by-value struct-return into the global) + the same `&g_reader` sites.

| shape | compiler | `*zT = zG_` save lines | `g_reader = zT_` reload lines | dump | link (`build_target.sh linux`) |
|---|---|---|---|---|---|
| D3 | baseline `fc04f4f5` (F3) | 18 | 18 | 0 | **rc=0, 0 `error:`** |
| D3 | P9 `c2772f6a` | **0** | **0** | 0 | **rc=0, 0 `error:`** |
| D4 | baseline `fc04f4f5` (F3) | 18 | — | 0 | **rc=0, 0 `error:`** |
| D4 | P9 `c2772f6a` | **0** | — | 0 | **rc=0, 0 `error:`** |

F3's alias spelling is preserved (the `g_reader` references render `zG_1DDBC924_g_reader` in both), and the save/restore no longer names or copies the global at all — "preserved or improved" ✓. (Note: the D3 patch must also retarget the `readMessageAsyncEnc` site — the defect doc's older patch predates the dual call sites.)

## Observations

- The WHAT/HOW split is delivered as ruled: the save/restore SET is decided at the async-construction authorities (`async_state_machine.zig` generators + the `async_frame_layout.zig` carried-set build — the async/lowering stage, `phase_LIRLowering`), carried on the frame layout (the `ASYNC_FIELD_PARAM`/`ASYNC_FIELD_LIVE` list IS the save set), and the emitter spells the save/restore from the carried set (unchanged LIR spelling; no emit-time set computation exists or is introduced).
- **O1 (the required zero realized):** pins 0/8, corpus class file byte-identical (0 movers), markers unchanged — the "ideally ZERO / same save/restore set" ideal holds on the entire frozen battery; the alias class simply does not occur in the pin programs' save sets.
- **O2 (the sanctioned shrink class, recorded + explained + runtime-frozen):** `z9torr` is the one battery program that carried a live-across alias (`const SCAN_MAX` from `mse.zig`, loop-carried across the `peerRun` scan-loop suspensions in 9 step copies). Its C goes 2,684,130 → 2,680,320 B (**−3,810 B**): the 9× `*zT_834… = zG_02BA9009_SCAN_MAX;` saves + 9× `zG_02BA9009_SCAN_MAX = zT_…;` reloads are gone (the round-trip removal) and `peerRun`'s frame relayouts (the alias slot at offset 572 and its neighbours shift — "a save-set change that perturbs frames is fine if recorded"). Runtime proof of benignity: examples 26/26 frozen incl. `z9torr rc=1 f666af15cf2625b3` (§5), goldens/stdlib/mi frozen. This is exactly the brief's anticipated delta class ("async C may shrink if the round-trip is genuinely reduced — recorded old→new + explained + runtime-frozen", spec §7.3 / ruling `dff38830` precedent). The removed traffic was also semantically wrong in general (the reload wrote the stale frame copy BACK INTO the global at every resume); for a `const` global it was value-preserving waste — both readings justify the removal.
- **O3 (`nest_inl` ruling, restated):** the suppression-path guards are C-shape spelling over carried inputs (§3 argument) — no emit-time decision of the save/inline set remains at the guard sites; no `nest*` code changed (pins prove the inline rendering is untouched).
- In-bounds runtime values unchanged everywhere → no STOP (the STOP trigger — any runtime OUTPUT change — did not fire).
- Deferred minors: none taken. The `async_frame_layout` temp-id-order instability (P10 deferred minor) stays deferred (the P9 slot drop is a save-set change, not a redesign of the order rule).
- Harness notes: 4 examples (`func_ptr_return`/`mandelbrot`/`quicksort`/`sort_strings`) use `<name>.zig` entries (not `main.zig`); `-o` needs pre-created output dirs; pins/markers run sequentially from one CWD (spill-file race).

## Concerns

- C1: fixed point moved (expected): `31b73acfb486375722d56a5dcc1e6a0c` → `3c0376fc62002297029f6ecc278a259c`; seed NOT rotated (Task C closeout).
- C2: `lower.zig`/`lir.zig` are NOT edited (§2.4): the plan text attributes the decision to `async_state_machine.zig`/`lower.zig`; the decision's only lowering-side input is the alias class, and that fact is already carried on the LIR by the `load_global` inst itself (written at `lowerGlobalRef:4268` / `lowerLValueAddr:2542` / `:4432`). A reified `TempDecl` flag would be information-free duplication with mandatory copier surface (`remapInst`/hoisted-copy precedent `82ff0743`). If the controller wants the fact reified on `TempDecl` anyway, it is a small follow-up (field + 3 fill sites + 2 `async_state_machine.zig` TempDecl copiers, ruling 1a); nothing in the observable behavior would change (pins are already 0/8).
- C3: the `saveAllFields`/`reloadAllFields` alias filter is defense-in-depth (with the layout filter in place it cannot fire on current layouts). It is kept because the binding text has two clauses and the generators are the literal "the set of temps to save/restore is decided in async_state_machine.zig" site ("save/restore only declared temps"), while the layout filter owns "remove the global by-value round-trip" (no by-value slot). Reviewer may prefer a single filter; either alone is complete for D3/D4.
- C4: residual declared-ness class enumerated in §1 (the decl loop's `eff_type == TYPE_VOID` no-decl line) — a void-typed temp in a by-value save slot would already be invalid C today; zero known sites (a void value cannot be read across a suspension by the live scan); not excluded (no unrelated fixes). Named for the Task-C ledger.
- C5: the D3 defect-doc patch text predates `peer.zig`'s dual `readMessageAsyncEnc`/`readMessageAsync` loop sites; the repro adapts it (both sites retargeted) — the in-example shape is faithful.
