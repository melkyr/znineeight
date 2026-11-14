# Task C report — Closeout (plan `### Task C: Closeout`)

Plan: `docs/superpowers/plans/2026-10-12-zig1-emitter-sanitization-plan.md:101-113`.
Brief: `.superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/task-C-brief.md`.

All increments complete. This report is the final closeout: full runtime battery on
the FINAL compiler, D1–D8 defect ledger root-cause mapping, QUICK_REF re-baseline,
seed rotation v97 → v98, commits.

**Compiler under test:** seed-built `/tmp/taskC/seed/zig1_5_clean` from the
committed v97 seed (`release/seed/zig1-seed.tgz`, md5
`7a2630c7ef37de664dd3a4da310c94cd`), built via
`bash scripts/seed/build_from_seed.sh`. No `sf/src` edit was made by this task
(docs + seed artifact only).

---

## Step 1 — Full runtime battery on the final compiler

### 1. Seed two-hop closure

```
$ FIXED_POINT_MD5=f18b69ece1917bf970a036b276e5e403 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/taskC/seed
[seed] hop2 binary md5: f18b69ece1917bf970a036b276e5e403
[seed] two-hop closure OK: hop1 == hop2 == f18b69ece1917bf970a036b276e5e403
[seed] recorded fixed point OK: f18b69ece1917bf970a036b276e5e403
=== [seed] Done: /tmp/taskC/seed ===
```

**hop1 == hop2 == `f18b69ece1917bf970a036b276e5e403`** — matches the P7 expected
final fixed point. **GATE PASS.**

### 2. Corpus classify — class file byte-identical, 0 movers

```
$ bash scripts/corpus/classify /tmp/taskC/seed/zig1_5_clean /tmp/taskC/corpus_C.txt
wrote /tmp/taskC/corpus_C.txt: 1124 dirs
$ md5sum /tmp/taskC/corpus_C.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/taskC/corpus_C.txt
$ awk '{print $2}' /tmp/taskC/corpus_C.txt | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
```

Byte-identical to the frozen anchor `518eca1a9b5d3e1cc5a48abce214abd8`
(1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH). **0 movers.**

### 3. Runtime goldens 5/5 — byte-identical PRE↔POST

Build recipe (QUICK_REF "Compile + RUN", default `-fsafe`):
`<zig1> --dump-c89 <ENTRY> > <n>.c` then
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include <n>.c
sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o <n>`.
All 4 dumps rc=0; all 4 gcc rc=0 (0 `error:`).

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 /tmp/taskC/gold/gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 gold/lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| json_parser | `cd examples/z98/json_parser && timeout 60 gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh gold/mud mud_srv.out mud_cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

**5/5 byte-identical** to the QUICK_REF gate-program goldens.

### 4. mi_matrix 25 + oob

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/taskC/seed/zig1_5_clean $(cat /tmp/opencode_p6pre/mi25.list)
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```

Trap (`-fsafe`) `repro/mi_matrix/slice_index_field_store_oob_xmod`: dump rc=0,
build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5
`d41d8cd98f00b204e9800998ecf8427e`), `expected.rc=133`, `expected.txt` 0 B.
**MATCH.**

### 5. examples/z98/*/ — 26/26 build + 26/26 run

CWD = example dir; `timeout 25` except `mud_server` 8; stdin `/dev/null` except
`rogue*` fed `q\n`. All 26 dumps rc=0 / builds rc=0; `.c` counts match task-0
§1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38). All 26 run rc
and stdout md5 IDENTICAL to the §1.4 table (days_in_month `8c0d394c…`, fibonacci
`b53b3a3d…`, func_ptr_return `f6a54779…`, game_of_life `fcbf7e7c…`, heapsort
`8cf0a784…`, hello `74630882…`, json×2 `8bda3d5a…`, json_parser_workaround
`dc22fa47…`, lisp×4 `1c1f0a41…`, lzw `c3c7765e…`, mandelbrot `d5966775…`,
mud_server rc=124 `9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`, rogue×2
`3fb6709e…`, sort_strings `c6c047cb…`, tco_defer `264ea6b1…`, tco_factorial
`3d70c50b…`, tco_return_try `7421137a…`, z9play rc=1 `2016494d…`, z9torr rc=1
`f666af15…`). **26/26 build + 26/26 run correct.**

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/taskC/seed/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

**285/0.** GATE PASS.

### 7. The 8 `--dump-c89` pins — RE-MEASURED (old → new)

Command per row (from repo root; deterministic, rc=0):
`<compiler> <mode> --dump-c89 examples/z98/<entry>/main.zig | md5sum`.

| entry | mode | old (QUICK_REF, stale) | new (final, v98) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `ad09343f1c0b9765716b2bd0857be0e2` | `bbc02913a10af9b0b5ed0f292f4e3407` | MOVE |
| mud_server | `-ffast` | `4cb0991679fd89993438aea1686e7e47` | `fa346108ed00d03a037c2f9331d3bdf8` | MOVE |
| game_of_life | `-fsafe` | `6a9518e77f68cabbf86a356afebe2157` | `93c5e3fdc5b80b2f3db020d995abbe3f` | MOVE |
| game_of_life | `-ffast` | `12a230e214f6407c9a1bb6faaf2d4ca8` | `01a4e2265b33c97a8ca6ff3dfa551231` | MOVE |
| lisp_interpreter_curr | `-fsafe` | `e7a8e48da407e8a7a87282ea35d886f9` | `6da05d070acd414674b1b1ec947baa5c` | MOVE |
| lisp_interpreter_curr | `-ffast` | `e5b74f4f5326ee65ec2afe61d629affc` | `e3970e33ac09c8dfaa316d2d69bf61ec` | MOVE |
| json_parser | `-fsafe` | `6eb0c0f8699bba517ac43ad2b28f85a9` | `af3823fae0b29fa4d4ca58932538d631` | MOVE |
| json_parser | `-ffast` | `5daac4a3cd2133fb00da3efda5b877df` | `24e0e812e7dffa5a43750135405ffe3f` | MOVE |

**Pins old→new: 8/8 moved.** The old table was stale since before the plan: at
Task 0 the mismatch was root-caused (C1) to `sf/src/std_math.zig` growth (z9play
M2 `4d6fb5dd`/`b5ca08d2`, 54 → 402 lines) post-dating it; swapping the v97-era
`std_math.zig` back reproduces all 8 old values byte-exactly (Task-0 report §1.6).
Runtime goldens are byte-identical PRE↔POST (§3), so this is an emitted-C
re-baseline only. These new values are the re-baselined QUICK_REF table.

### 8. `--markers` telemetry

```
$ /tmp/taskC/seed/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig \
    > /tmp/taskC/mk_gol.c 2>/tmp/taskC/mk_gol.bin
dump rc=0; 3,437 marker lines / 38,384 B
```

Unchanged **3437 / 38384**; `cmp` IDENTICAL to the P7 compiler's marker stream.

### Battery summary

| item | result |
|---|---|
| seed two-hop | hop1 == hop2 == `f18b69ece1917bf970a036b276e5e403` — PASS |
| corpus classify | `518eca1a9b5d3e1cc5a48abce214abd8`, 1124 = 950/58/116/0/0 — 0 movers |
| runtime goldens | 5/5 byte-identical |
| mi_matrix | 25 PASS / 0 FAIL + oob rc=133/empty — MATCH |
| examples | 26/26 build + 26/26 run correct |
| stdlib | 285 PASS / 0 FAIL / STDLIB GATE OK |
| pins | 8/8 re-measured (old→new) |
| markers | 3437 lines / 38384 B (identical to P7) |

---

## Step 2 — Defect ledger (`examples/torrent_example_defects.md`)

Each of D1–D8 marked **FIXED AT ROOT CAUSE** with mechanism + milestone commit;
prior site-fix history retained (`Prior site fix …`). Diff summary
(`git diff --numstat`): **82 insertions / 29 deletions**.

| defect | root-cause increment | commits | mechanism |
|---|---|---|---|
| D1 (C keyword union tag) | P1 identifier authority | `4056b26f`/`185bcc13` + `9c867fef`/`8ba4b418` | `name_mangler.zig` single minter (MintLocal/Field/Member keyword-escape + per-scope collision) at decl AND every access |
| D2 (synthetic slice typedef alias) | P3 canonical `typeCName` | `e526859b`/`b33ae234` | one `typeCName`/`typeSliceElementName` derivation; emitter pure consumer |
| D3 + D4 (frame-save undeclared temp) | P9 structural frame-save rule | `c2772f6a`/`097a5949` | save/restore set decided at async construction (`asyncTempIsGlobalAlias`; alias temps get no `ASYNC_FIELD_LIVE` slot); emitter spells |
| D5 (slice-index aggregate lvalue store lost) | P10 lvalue unification | `b7cba183`/`b6875640` + `5b6b8e1a` | one checked `lowerIndexElemAddr` path + `lowerFieldStore` root-index check |
| D6 (`@ptrFromInt` type-arg miscompile) | P8 builtin arity/descriptor table | `649fe398` + `c4838a29` | central `BuiltinDesc` consulted before the ladder for all 37 builtins; whole wrong-arity accept class closed |
| D7 (unqualified type cross-module) | P7 module-scope-first (Amd 8 widened) | `dcd0c9db` | lexical module context threaded into comptime type-arg fold + in-set order fixes |
| D8 (fnptr-typedef-returning-error-union order) | P2 single type-dependency relation | `1029221f`/`36c6a00a` + `40a8a36e`/`f29070b4` | one `typeRefs`/`typeNeedsFullDef` relation derives both graphs incl. `fn_type` |

Prior site fixes kept noted: F1 `69e82cd8` (D1), F2 `e21dd31b` (D2), F3
`06a7a793` (D3+D4), F5 `ae156d26` (D5), `875b9a9e` (D6, seed v97). D7 and D8
were DOCUMENTED/OPEN → now FIXED.

Parked example workarounds (`z9play` `Mode`→`VorbisMode`; the D8 example-side
workaround) stay as committed per plan §"Out of scope" — examples need not change.

### Residual class items (added to the ledger)

- P7 module-less shapes fallback-first (dead shapes).
- P8 `error[19]` rendering of `ERR_3000_TYPE_MISMATCH` (diagnostics enum lacks
  `=3000`, pre-existing, deliberately preserved) + `@cVaArg` dead resolve guard.
- P8 `@intCast` 1-arg identity-typing narrowing residual (EXPECTED_FAIL Task 7,
  documented divergence).
- P10/P9 `async_frame_layout` not stable under `-fsafe` instrumentation growth
  (temp-id-order live-temp layout).
- P4 O7 named tuples get no typedef in the multi-file path.
- P14 O3 carrier-fill scan conversion (operator ratify-or-revert pending).

---

## Step 3 — Seed rotation v97 → v98

Gen dir = final compiler's self-emission:
```
$ timeout 120 /tmp/taskC/seed/zig1_5_clean -ffast --dump-c89 \
    --output-dir /tmp/taskC/gen_final sf/src/main.zig     # rc=0
$ bash scripts/seed/archive_seed.sh /tmp/taskC/seed/zig1_5_clean \
    /tmp/taskC/gen_final release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): f18b69ece1917bf970a036b276e5e403
[archive] wrote release/seed/zig1-seed.tgz (archive md5 74acfdadbb48fb658e59cf8da6ad678a)
[archive] prepended entry to release/seed/CHANGELOG.md
```

| field | v97 | v98 |
|---|---|---|
| archive md5 | `7a2630c7ef37de664dd3a4da310c94cd` | `74acfdadbb48fb658e59cf8da6ad678a` |
| archived binary md5 | `bafbba9454cd2b134bdc3d50c65384e0` | `f18b69ece1917bf970a036b276e5e403` |
| fixed point | `bafbba94…` | `f18b69ece1917bf970a036b276e5e403` |
| gen/ | 45 `.c` + 46 `.h` (9,821,325 B) | 46 `.c` + 47 `.h` (9,900,439 B) |
| HEAD | `875b9a9e` | `313372d3` |

The archived binary md5 equals the final fixed point. **Verified hop1 == hop2 from
the NEW committed seed:**
```
$ FIXED_POINT_MD5=f18b69ece1917bf970a036b276e5e403 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/taskC/seed98
[seed] two-hop closure OK: hop1 == hop2 == f18b69ece1917bf970a036b276e5e403
[seed] recorded fixed point OK: f18b69ece1917bf970a036b276e5e403
=== [seed] Done: /tmp/taskC/seed98 ===
```

`release/seed/CHANGELOG.md` prepended with the `2026-10-16 — seed v98 (HEAD
313372d3)` provenance entry (newest-first, after the preamble).

---

## Step 4 — QUICK_REF re-baseline (`docs/sf/QUICK_REF.md`)

Diff summary (`git diff --numstat`): **32 insertions / 21 deletions**.

- **§"Current seed":** `v97` → **`v98`** (rotated 2026-10-16 by the zig1 emitter
  sanitization closeout; seed v97 → v98, final compiler P7 `dcd0c9db`), archive
  md5 `74acfdadbb48fb658e59cf8da6ad678a`, archived binary md5 (= fixed point)
  `f18b69ece1917bf970a036b276e5e403`, gen/ 46 `.c` + 47 `.h` (9,900,439 bytes),
  `lib/` 32 std `.zig`.
- **8-pin table:** re-baselined to the Step-1 measured final values (all 8
  columns), header now `re-baselined 2026-10-16, zig1 emitter sanitization
  closeout, seed v98`, with the stale-table reason (C1: `std_math.zig` growth
  post-dating it) and the runtime-golden PRE↔POST proof.
- **Rotation history:** the seed enumerate paragraph and the milestone-closeout
  history section both carry the v97 → v98 entry, consistent with
  `release/seed/CHANGELOG.md`. The FX14-era "Current live `-ffast` pins" note was
  retitled "FX14-era" (superseded).

---

## Residual items list

- P7 module-less shapes fallback-first (dead shapes; no battery fixture).
- P8 `error[19]` rendering of `ERR_3000_TYPE_MISMATCH`; `@cVaArg` dead resolve guard.
- P8 `@intCast` 1-arg identity-typing narrowing residual (EXPECTED_FAIL Task 7).
- P10/P9 `async_frame_layout` instability under `-fsafe` instrumentation growth.
- P4 O7 named tuples get no typedef in the multi-file path.
- P14 O3 carrier-fill scan conversion (operator ratify-or-revert pending).
- Parked example workarounds (z9play `Mode`→`VorbisMode`; D8 example-side) stay;
  examples unchanged.

## Commits

1. `docs: zig1 emitter sanitization closeout + seed v98` —
   `examples/torrent_example_defects.md`, `docs/sf/QUICK_REF.md`,
   `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`.
2. `docs(sdd): Task C report` — this file (`git add -f` explicit path).

`progress.md` untouched (controller-owned). Untracked `run.err` left alone. No push.

## Concerns

None blocking. Battery fully green; fixed point matches `f18b69ec…`; seed v98
reproduces hop1==hop2; all anchors match. The only stale artifact was the pre-plan
QUICK_REF 8-pin table, now re-baselined (all 8 pins moved; runtime unchanged).
