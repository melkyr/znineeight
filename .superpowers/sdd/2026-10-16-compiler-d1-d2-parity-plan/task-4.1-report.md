# Task T4.1 report — F1 root-cause/fix + F4 fold-in (Amendment 3 (B))

Tree start: `a823ba78` (Amendment 3 plan commit on T4 tree). Authority:
`task-4.1-brief.md` (Amendment 3 (B) verbatim). Controller context
(`task-4.1-context.md`) verified/refuted per hypothesis below.

---

## Investigate (root-cause + evidence — written BEFORE the source fixes)

### 1. F1 flip reproduced (brief repro recipe)

Baseline compiler (current tree, no probe) — prebuilt gate build
`/tmp/d1d2_t4/zig1_5_clean` (same `sf/src` as HEAD; `a823ba78` is docs-only):

```
$ mkdir -p /tmp/f1_probe/base && cd /tmp/f1_probe/base
$ timeout 120 /tmp/d1d2_t4/zig1_5_clean -ffast -o /tmp/f1_probe/base \
    repro/mi_matrix/stdlib_crypto_modpow_xmod/main.zig
rc=0; 6 .c emitted (main/std_crypto/std_io/c_exit/zig_pal/zig_runtime); stderr empty
```

class OK (rc 0), matching `expected.rc`=`0`, `expected.txt`=`crypto modpow ok\n`.

Probe compiler: ONE extra early intern at the top of `parserInitCommon`
(`stringInternerIntern(interner, "f1probe")`), built via
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/f1_probe/probe1`
(36 s; hop2==hop3 `0b7583efe912d1562e287b9e1f2c3aeb`):

```
$ cd /tmp/f1_probe/probe1_out
$ timeout 120 /tmp/f1_probe/probe1/zig1_5_clean -ffast -o . \
    repro/mi_matrix/stdlib_crypto_modpow_xmod/main.zig
rc=2; stderr:
/tmp/f1_probe/probe1/lib/std_io.zig:64:2: error[3000]: unable to infer array size
// pal_file_* symbols are declared here directly (extern "c") because the
  ^
0 .c emitted
```

class OK→GREEN, error[3000] "unable to infer array size", rc 2 — the T4
measurement reproduced exactly (attribution `std_io.zig:64`, a comment line —
the span is being read in the wrong file's coordinates, see §3).

### 2. Minimal repro + trigger narrowing

Reduced (probe compiler) to `mn.zig` (scratch, 36 `[_]u8` fn-local vars +
`var out: [96]u8` + 2× `std.io.write` + `std_crypto` import + `ckBytes` with a
short body + `g_fail`): probe FAIL (`std_io.zig:25:0 error[3000] unable to
infer array size`), baseline PASS. A one-token body difference
(`ckBytes` with vs without `var i: usize = 0; while …`) flips it — i.e. ANY
change to the interned-name set before `main`'s body (another id shift) flips
it. `mv.zig` = `mn.zig` + the longer `ckBytes` body passes on the probe.
Control: `var v: [_]u8 = [_]u8{1}` (ANNOTATED) errors on BOTH compilers —
intended Zig parity (the context's guessed unguarded var-annotation path is a
RED herring for F1; `[_]` in a concrete-type position is a hard error by
design, type_resolver.zig:2158-2170). Unannotated `var v = [_]u8{1}` alone
never errors.

### 3. Instrumented trace (probe vs baseline)

Temporary `pal.measureMarkerWrite*` instruments (live under `--markers`) at:
`typeResolverIsInferredLenArray` (F1G), `resolveTypeExprFull`'s
`if (node.child_0 != 0)` tail entry (F1TAIL:node/k/c0[/name=]), the
`array_type` arm (F1AR), the error[3000] arm (F1ERR), `evalConstIntFull`'s
ident arm for `_` (F1ID), and the `typeResolverResolveNames` sub-pass
boundaries (F1P). Built with
`scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/f1_probe/probe3`
(+probe) and `/tmp/f1_probe/base_instr2` (no probe).

Probe (`mn.zig`), rc=2:

```
F1P:RNT                                   ← resolveNamedTypeExpressions starts
F1TAIL:node15235
F1TAIL:k31                                ← AstKind 31 = builtin_call (ast.zig:33)
F1TAIL:c085                               ← child_0 = 85
F1TAIL:name=@intCast                      ← child_0 is @intCast's NAME ID
F1TAIL:node85                             ← name id 85 CONSUMED AS A NODE INDEX
F1TAIL:k86                                ← AstKind 86 = array_type (ast.zig:88)
F1TAIL:c084
F1AR:node85                               ← array_type arm entered
F1AR:sz503 / F1AR:pay28 / F1AR:fid18
F1ID:nm39 / F1ID:node83                   ← `_` fold attempted; NO F1ID:LOCAL / F1ID:SYM (miss)
F1ERR:node85 / sz503 / fid18 / mod3 / k24 ← error[3000]; size kind 24 = ident_expr
```

Baseline (`mn.zig`), rc=0 — the SAME walk, shifted alias:

```
F1P:RNT
F1TAIL:node15235
F1TAIL:k31
F1TAIL:c084                               ← child_0 = 84 (name id minus 1)
F1TAIL:name=@intCast
                                          (no F1AR / no F1ERR — node 84 resolves harmlessly)
```

Baseline fixture run (`/tmp/f1_probe/base_instr2`, rc=0):
`F1TAIL:node15484 / k31 / c093 / name=@intCast` — alias node 93, harmless.

Span forensics: `F1AR:sz503` is offset 503 of the ENTRY file (`mn.zig` =
`var v4_r = [_]u8{ 0x00, 0x18 };`'s `_`; fixture offset 1382 = line 41
`var v4_b = [_]u8{…}`'s `_`) while `F1ERR:fid18` = std_io's file id (module 3
being walked) — the diagnostic prints `<std_io.zig>:<entry-file offset>` =
the observed `std_io.zig:64` / `std_io.zig:25` misattributions. NO F1G marker
precedes the error: the node was reached WITHOUT the inferred-array guard,
i.e. through the unguarded tail recursion, not through an aggregate
annotation.

### 4. Root cause (F1) — name id consumed as AST node index

`resolveTypeExprFull`'s generic tail (type_resolver.zig, `if (node.child_0 !=
0)` fall-through after the ident/field_access/error_set/error_union/fn_type
arms) recursively resolves `node.child_0` as a TYPE-EXPRESSION NODE for every
node kind that reaches it. That is wrong for `AstKind.builtin_call`, whose
`child_0` is the builtin's interned NAME ID — documented twice in
`sf/src/ast.zig`:

- ast.zig:386: `builtin_call → builtin name ID (child_0); payload = extra-children index`
- ast.zig:976 (`nodeChildIsNode`): `AstKind.builtin_call => return slot != 0, // child_0 = builtin name id`
  with the standing note: *"a dropped type edge is inert; a name id walked as a
  node index is fatal."*

`nodeChildIsNode` is the codebase's declared single source of truth for this
exact hazard and is consulted by `visitPreOrder`, `analyzer.zig:571-573`,
`async_analysis.zig` — but NOT by `resolveTypeExprFull`'s tail. The chain:

1. `resolveNamedTypeExpressions` (type_resolver.zig:2355) resolves every
   module-level var init that `varDeclInitNeedsNameCache` accepts (which
   includes `builtin_call`), e.g. std_io's
   `const INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF);`.
2. `resolveTypeExprFull(builtin_call_node)` falls into the tail and recurses
   `resolveTypeExprFull(child_0)` — i.e. "resolves" the AST node sitting at
   index = the `@intCast` NAME ID.
3. Interner ids are assigned in INSERTION ORDER
   (`string_interner.zig`: `new_idx = self.entries_len`, returned by
   `stringInternerIntern`) — so the aliased node is a function of id ASSIGNMENT
   ORDER. One extra intern before source lexing shifts every later id by +1
   (T4 measured; re-measured here: `@intCast` id 84 → 85).
4. Measured: id 84 (baseline) aliases an innocent node — rc 0. id 85 (probe)
   aliases `mn.zig`/the fixture's `[_]u8` `array_type` node (span 503 /
   1382) — the `array_type` arm runs, the `_` size fails to fold
   (`evalConstIntFull` ident arm: no local-const / no symbol hit — F1ID trace),
   the size text check reads `_`, and the hard error[3000] "unable to infer
   array size" fires (type_resolver.zig error arm), attributed to the module
   currently being walked (std_io).

This is the brief's "id-consuming subsystem" candidate: the interner id is
consumed as an AST node index. It explains every measured fact: ANY extra
early intern flips the fixture (the alias moves by 1 and lands on a landmine
`[_]` node — the fixture/main has 36 of them); dummy `Parser` fields do not
flip it (no id values change); the flip is deterministic per id assignment
(mn vs mv = intern-set difference = another shift); the message is the `_`
one (the aliased node is a real `[_]` array_type whose size text is `_`);
the attribution is a file that contains no `[_]` (env.source_file_id of the
walked module).

### 5. Controller hypotheses — verified or refuted (task-4-context.md)

| hypothesis | verdict | evidence |
|---|---|---|
| H1 `evalConstU32Full` folds `_` today via local_consts/symbols keyed by name_id; shift breaks the hit | REFUTED as the flip channel | F1ID trace: in the FAILING run the `_` fold MISSES (no F1ID:LOCAL / F1ID:SYM); in the baseline run the array node is never reached at all (no F1AR). The fold is name_id-equality (shift-invariant); the flip is upstream — the array node is only reached because a name id was read as a node index. |
| H2 `astStoreIdentifier` stale/garbage flips the `_` text check | REFUTED | The error arm's text check READS CORRECTLY (`_` → 3000 message, F1ERR:k24 = ident_expr); `typeResolverIsInferredLenArray` is never called on the node (no F1G) — the unguarded tail path bypasses it. Both checks use identical reads; no divergence observed. |
| H3 attribution mystery (`std_io.zig` has no `[_]`) | CONFIRMED (explained) | env.source_file_id = the walked module's file (std_io, fid 18 / module 3) while the aliased node's span belongs to the entry file (offset 503/1382 = its `[_]` `_`). The diagnostic renders file=std_io + foreign offset. |
| H4 name_id numeric consumers / hash-map iteration order / id-as-index | CONFIRMED — the exact consumer found | name-id-as-node-index in `resolveTypeExprFull`'s tail (the maps themselves are exact-compare sound — `u32ToU32Map`/`u64ToU32Map` Get/Put verified). Sibling same-mechanism site found: `resolveStmtTypesRec`'s generic tail (front_resolution.zig:212-215) walks `child_0`/`child_1` for all kinds except `builtin_call` (ad-hoc exclusion) — so `swt_prong.child_1` (capture name id) and statement-form container `child_0` (name id) are still walked as node indices there. |
| H5 `nameCacheGet` bare-key aliasing | REFUTED | nameCache keys are exact u64 (`u64ToU32MapGet`, key equality); the observed channel never involves the name cache (the alias happens in the tail walk before any cache lookup). |
| H6 `resolveTypeExprFull` ident arm order across modules | not the channel | The failing node is `array_type`, never an ident arm lookup. |
| F1-error-path map (`type_resolver.zig:2121-2179`) | VERIFIED | `evalConstU32Full` → 0xFFFFFFFF sentinel → `sz_is_inferred` text check → error[3000] at the documented lines; reached only via the unguarded tail. |
| Guard coverage asymmetry (var_decl annotation path unguarded) | REAL but NOT F1 | `var v: [_]u8 = …` errors on BOTH compilers (Zig-parity reject). F1's failing nodes are UNANNOTATED `[_]` array_init annotations aliased by the tail walk (no guard on that path by construction). |
| T4 bisect "dummy fields PASS / +1 intern FAIL" | consistent | No code reads interner ids as node indices through `Parser` fields; only the id VALUES matter. |

### 6. F4 investigation (fn-param flat `child_buf` protocol)

`parserParseFnDecl`'s param list uses the flat protocol `self.child_buf_len =
0` (parser.zig entry), append params at `[0..]`, copy out, `child_buf_len =
0` again — the same shared-`child_buf` reset class as the C2 site deleted in
`d568880c`. Measured clobber (baseline compiler `/tmp/d1d2_t4/zig1_5_clean`):

```
f4e.zig: fn body with 75 var stmts, no nested fn          → rc=0, 4 .c
f4f.zig: 66 var stmts + `fn nested(a: u32) u32 {…}` stmt 67 → rc=2,
   error[3020] "internal error: unhandled node kind in type resolution"
   attributed at `var x9` (stmt 9 — LONG BEFORE the nested fn)
```

i.e. entering `parserParseFnDecl` with a `child_buf` list in progress (the
`parserParseBlock` >64-stmt overflow flush puts the block's stmt list in
`child_buf`) zeroes the list; the block's payload is then read back as
garbage. Note the T4 F4 wording "when a fn-type appears inside one" did not
match a literal trigger I could construct — `parserParseFnType` uses its own
`parserPushU32` buffer and never touches `child_buf` (verified by reading
parser.zig:1341-1383; call-arg/tuple shapes with fn-types compile clean,
`f4b.zig` rc=0). The defect as specified is the param-list flat protocol
clobbering an enclosing list; the measured trigger is a fn DECL inside a
block stmt list that has overflowed into `child_buf`. Fixed as specified
("fix like C2 was fixed" = the shared buffer must not be reset; the standard
saved/append/listEnd protocol every list user follows must hold).

---

## Fix (F1 root + F4)

Source edits AFTER the Investigate section above (temp debug instruments from
the investigation were removed before the canonical build; final delta = 3
files, see `git diff a823ba78`).

### F1 root — never consume a name-id slot as a node index

`sf/src/type_resolver.zig` — `resolveTypeExprFull`'s generic tail now gates
the `child_0` recursion on `ast_mod.nodeChildIsNode(node.kind, 0)` (the
codebase's declared single source of truth for this hazard). `builtin_call`
never reaches the recursion, so its name id can no longer alias an arbitrary
node — compilation for this mechanism is now ID-ORDER-INDEPENDENT.

`sf/src/front_resolution.zig` — same mechanism, sibling walk:
`resolveStmtTypesRec`'s generic tail replaced its ad-hoc
`node.kind != AstKind.builtin_call` exclusion with `nodeChildIsNode` checks on
slots 0/1 (the old exclusion left `swt_prong.child_1` (capture name id) and
statement-form container `child_0` (name id) being consumed as node indices —
the identical id-order-dependent class).

Root-fix evidence (fixed tree `/tmp/d1d2_t41` + probe tree
`/tmp/f1_probe/fix_probe` = fix + `stringInternerIntern(interner, "f1probe")`
at `parserInitCommon`):

```
unfixed + probe: fixture rc=2 error[3000] unable to infer array size   (FAIL)
fixed   + probe: fixture rc=0, 6 .c, stderr empty                       (PASS)
fixed   + probe: mn.zig rc=0 (minimal repro; FAILed on unfixed+probe)   (PASS)
fixed   clean  : fixture rc=0                                           (PASS)
```

i.e. the +1 id shift that flipped the fixture now changes nothing.

### F4 — `parserParseFnDecl` param-list flat `child_buf` protocol

`sf/src/parser.zig` — the param list no longer resets the shared `child_buf`:
entry `self.child_buf_len = 0` → `var saved_params = self.child_buf_len`;
params append at `[saved_params..]`; the copy-out slice/count use
`saved_params` bounds and restore `child_buf_len = saved_params`; the exit
reset and the stale-check bound likewise. This is the C2 fix's principle
applied to a list that appends ("the saved/append/listEnd protocol every list
user follows is already correct without the reset" — d568880c comment): the
clobber lines are gone; the enclosing list is preserved.

Evidence (baseline `/tmp/d1d2_t4` vs fixed `/tmp/d1d2_t41`, scratch `g1.zig` =
66 `var` stmts + `fn nested(a: u32) u32 { return a; }` as stmt 67 +
`var s: u32 = x1;`):

```
baseline g1: rc=2  error[20] identifier 'x1' is not declared or imported
                + warning[3000] init type void   (block stmt list clobbered)
fixed    g1: rc=2  only error[3020] at the nested fn (pre-existing nested-fn
                sema gap — semantic_analyzer.zig:5587; span field = node_idx,
                so its "line" is bogus); x1 resolves clean
```

## Runtime battery

8 items; gate compiler `/tmp/d1d2_t41/zig1_5_clean` (seed-built from the fixed
tree; hop2 == hop3 == `9110b933c26306ccbf491767febb35be`). Sequential runs.

| # | item | command | observed | verdict |
|---|---|---|---|---|
| 1 | corpus | `bash scripts/corpus/classify /tmp/d1d2_t41/zig1_5_clean /tmp/d1d2_t41work/corpus_t41.txt` | 1133 dirs; frozen 1124 subset (9 designed lines removed) md5 **`518eca1a9b5d3e1cc5a48abce214abd8`**; tally 959 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH; designed 9/9 OK | frozen **byte-identical, 0 movers**; no designed flips this round |
| 2 | goldens 5/5 | `zig1_5_clean -ffast --dump-c89 <ENTRY>` + gcc trio + runs | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud srv `66c8f0abb926cca7baf9a0d1692ab318` / cli `93147d0f0bbd983a9d844fea8b7a6fa7` | **5/5 MATCH** |
| 3 | mi_matrix frozen-25 + oob | `bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_t41/zig1_5_clean <25 frozen dirs>`; oob `-fsafe` recipe | `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`; oob trap: dump rc 0, build rc 0, run **rc 133** (Trace/breakpoint trap), stdout 0 B `d41d8cd98f00b204e9800998ecf8427e` | **MATCH** |
| 4 | examples | per-dir `zig1_5_clean -ffast -o <out> <entry>` + `build_target.sh linux` + run (CWD=dir, timeout 25, mud 8, stdin /dev/null, rogue `q\n`) | **26/26 build, 26/26 run**; all stdout md5 prefixes == T0/T3 table (`8c0d394c`,`b53b3a3d`,`f6a54779`,`fcbf7e7c`,`8cf0a784`,`74630882`,`8bda3d5a`×2,`dc22fa47`,`1c1f0a41`×4,`c3c7765e`,`d5966775`,mud rc124 `9545fe1d`,`d095a94d`,`45d2f0fb`,`3fb6709e`×2,`c6c047cb`,`264ea6b1`,`3d70c50b`,`7421137a`,z9play rc1 `f35b7ef7`,z9torr rc1 `f666af15`) | **MATCH** |
| 5 | stdlib | `bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_t41/zig1_5_clean` | `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK` | **285/0 MATCH** |
| 6 | seed two-hop | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t41` | `three-hop closure OK (moving point): hop2 == hop3 == 9110b933c26306ccbf491767febb35be` | fixed point old `20bd1a526abaf837190a53ae9f1b2f1a` → **new `9110b933…`** (verdict (a) moving-point semantics) |
| 7 | 8 pins | `zig1_5_clean <mode> --dump-c89 <ENTRY> \| md5sum` | gol `-fsafe` `93c5e3fdc5b80b2f3db020d995abbe3f` / `-ffast` `01a4e2265b33c97a8ca6ff3dfa551231`; lisp `6da05d070acd414674b1b1ec947baa5c` / `e3970e33ac09c8dfaa316d2d69bf61ec`; json `af3823fae0b29fa4d4ca58932538d631` / `24e0e812e7dffa5a43750135405ffe3f` — all unchanged; **mud moved**: `-fsafe` `bbc02913a10af9b0b5ed0f292f4e3407`→`48f188df6b5f09cb1614c532ae7e825a`, `-ffast` `fa346108ed00d03a037c2f9331d3bdf8`→`243369f4a942ad27f75b3c391581bd29` | **6/8 unchanged; 2/8 moved** (operator-approved class; delta characterized below) |
| 8 | markers | `zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig` | `marker_lines=3436 bytes=38371` | **unchanged** vs 3436/38371 baseline |

Pin delta characterization (mud_server only): 341 diff lines, all synthetic
composite typedef renames/reorders — `zT_…_Opt_68`→`zT_…_Opt_66`,
`Opt_80`→`Opt_78`, `EU_28`→`EU_08` etc. (the trailing number is the type
registry id). Mechanism: pre-fix, `resolveNamedTypeExpressions`'s
name-id-as-node-index walk resolved spurious types for the aliased nodes and
stamped them into the name cache; the F1 fix resolves builtin_call inits to
UNDEFINED and allocates no type, so later synthetic composite ids shift.
Behavior-preserving: mud goldens (`66c8f0ab…`/`93147d0f…`) and the example
run md5 (`9545fe1d…`) match on the new binary (item 3/4 above).

## Concerns

- **F4 scale vs the plan's "1-line" descriptor (disclosed).** The plan/brief
  call F4 a "1-line fix … fix like C2 was fixed". A bare deletion of the
  `child_buf_len = 0` clobber line is NOT sound at this site: unlike C2's
  `@import` arm (which appends nothing), the param list APPENDS to `child_buf`,
  so without the entry reset the copy-out slice `child_buf_items[0..len]`
  would include enclosing-list items and `param_count` would be wrong. The fix
  is the C2 principle (the standard saved/append/listEnd protocol, resets
  removed) implemented as a 5-line bounds conversion in `parserParseFnDecl`
  (entry save +2 bounds + restore + stale-check bound). Construct-local and
  revertable if a literal 1-line delta is required.
- **F4 trigger wording vs measured shape (disclosed).** The T4 F4 entry says
  the clobber fires "when a fn-type appears inside one [an enclosing list]".
  `parserParseFnType` uses its own `parserPushU32` buffer and never touches
  `child_buf` (fn-type-in-list shapes compile clean — `f4b.zig` rc=0). The
  measured trigger is a fn DECL inside a block whose stmt list overflowed into
  `child_buf` (`parserParseBlock`'s >64-stmt flush) — e.g. a nested `fn` as
  stmt 67. The fix covers the specified defect (the param-list flat protocol
  clobbering enclosing lists) in both readings.
- **Nested-fn-in-statement-position gap (pre-existing, NOT fixed).** A nested
  `fn` decl inside a block is a semantic_analyzer feature gap:
  `error[3020] internal error: unhandled node kind in type resolution`
  (semantic_analyzer.zig:5587; its diagnostic span field is `node_idx`, so the
  printed line/column is bogus), and the nested fn's name is not registered as
  a local. Out of T4.1 scope (F4 = the child_buf clobber only; no unrelated
  fixes). Recommend a later task.
- **Same-mechanism sibling fix scope (disclosed).** The F1 root fix is
  `resolveTypeExprFull`'s tail; the `resolveStmtTypesRec` tail hardening
  (`front_resolution.zig`) is the same defect class (name id consumed as node
  index — the brief's "id-consuming subsystem") at a sibling walk, replaced
  with the `nodeChildIsNode` source of truth. If the reviewer scopes F1 to the
  single measured channel, the front_resolution hunk is independently
  revertable. Frozen-1124 corpus is byte-clean either way (item 1).
- **Pin movers 2/8 (recorded, per "MAY move").** mud_server `--dump-c89`
  digests moved in both modes via synthetic type-id renaming (characterized
  above); 6/8 pins and all run-level goldens unchanged.
- **Error[3000] misattribution residual (disclosed).** When `resolveTypeExprFull`
  reports the array-size errors it stamps `env.source_file_id` (the module
  being walked) with the node's span from its own file — cross-file nodes get a
  wrong filename. Not exercised post-fix on the fixture (no error fires), and
  pre-fix it only ever fired ON the aliased garbage node; not fixed (would be
  an unrelated diagnostics change).

