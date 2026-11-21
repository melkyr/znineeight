# Production preservation validation — `-fsafe` source fixes + `-ffast` seed gate

Date: 2026-10-25. Repo: `/workspace/znineeight`, branch `zig1_improvements`.
Base: `c13de0bc`. No seed rotation; `release/seed/*` untouched.

## Status

**PASS.** The 7-file source fix is committed; the committed v120 seed rebuild closes at the new
fixed point; the full `-ffast` production battery passes with 0 corpus movers and 0 pin movers.

| Item | Result |
|---|---|
| copy exact | `diff -rq sf/src /tmp/inv/src_fsafe` empty; diff body == `/tmp/inv/logs/src_fsafe.diff` |
| fix commit | `5dbd24448fdb0f12b73f0bf9ec8faa79502ca470` |
| hop1 / hop2 / `F_new` | `dcfc9e70e475a8a08c0487dafd2e6b45` / same / same |
| previous fixed point | `11de43a053bdde3be3ddc61caac31df6` |
| corpus frozen-1124 | 950 OK / 58 GREEN / 116 FAIL, **0 movers** |
| goldens | **5/5** exact |
| dump-MD5 pins | **8/8** unchanged (both modes) |
| markers | 3252 lines / 37293 B |
| examples | **26/26** |
| `verify_stdlib` | **336 PASS / 0 FAIL**, `STDLIB GATE OK` |
| crosscheck | **10 PASS / 0 FAIL** |

## 1. Copy verification

Operator-authorized copy-over of the 7 files:

```bash
cd /workspace/znineeight
for f in c89_emit.zig comptime_eval.zig lexer.zig lir_opt_pass.zig \
         semantic_analyzer.zig type_registry.zig type_resolver.zig; do
  cp /tmp/inv/src_fsafe/$f sf/src/$f
done
diff -rq sf/src /tmp/inv/src_fsafe          # empty, rc=0
git diff --check                            # clean
```

The `git diff` hunk bodies are identical to `/tmp/inv/logs/src_fsafe.diff`; only the hunk-header
trailing function context differs (GNU `diff` omitted it). 17 hunks cover the 15 intended sites
(12 intentional wraps + 3 real defects):

```text
 sf/src/c89_emit.zig          | 8 ++++----
 sf/src/comptime_eval.zig     | 6 +++---
 sf/src/lexer.zig             | 9 ++++-----
 sf/src/lir_opt_pass.zig      | 6 +++---
 sf/src/semantic_analyzer.zig | 2 +-
 sf/src/type_registry.zig     | 2 +-
 sf/src/type_resolver.zig     | 4 ++++
 7 files changed, 20 insertions(+), 17 deletions(-)
```

Committed only those 7 files:

```text
5dbd24448fdb0f12b73f0bf9ec8faa79502ca470
fix(src): make the compiler -fsafe-clean (12 wraps + 3 real defects)
```

`release/seed/*` (stale uncommitted v121), `run.err`, and the untracked P4 docs were not staged.

## 2. Build from the committed v120 seed

```bash
cd /workspace/znineeight
git show c13de0bc:release/seed/zig1-seed.tgz > /tmp/v120_seed.tgz   # md5 18c21ebfc18f3014f0ccab2f10f38688
bash scripts/seed/build_from_seed.sh /tmp/v120_seed.tgz /tmp/fixed_v121_build
```

Key output (full log `/tmp/fixed_v121_build.log`):

```text
[seed] hop1 binary md5: dcfc9e70e475a8a08c0487dafd2e6b45
[seed] hop2 binary md5: dcfc9e70e475a8a08c0487dafd2e6b45
[seed] two-hop closure OK: hop1 == hop2 == dcfc9e70e475a8a08c0487dafd2e6b45
=== [seed] Done: /tmp/fixed_v121_build ===
```

`F_new` moved from `11de43a053bdde3be3ddc61caac31df6` (v120) to
**`dcfc9e70e475a8a08c0487dafd2e6b45`**. Closure is hop1 == hop2. Compiler under test:
`/tmp/fixed_v121_build/zig1_5_clean`.

## 3. Full `-ffast` production battery

### Corpus (frozen-1124)

```bash
cd /workspace/znineeight
bash scripts/corpus/classify /tmp/fixed_v121_build/zig1_5_clean /tmp/prod_corpus.txt
# wrote /tmp/prod_corpus.txt: 1188 dirs
```

Frozen-1124 restriction and comparison against the v120 seed baseline
(`/tmp/inv/logs/seed_corpus.txt`, `/tmp/corpus_frozen.txt`):

```bash
awk 'NR==FNR{k[$1]=1;next} ($1 in k)' /tmp/corpus_frozen.txt /tmp/inv/logs/seed_corpus.txt | sort > /tmp/seed_frozen1124.txt
awk 'NR==FNR{k[$1]=1;next} ($1 in k)' /tmp/corpus_frozen.txt /tmp/prod_corpus.txt | sort > /tmp/prod_frozen1124.txt
diff /tmp/seed_frozen1124.txt /tmp/prod_frozen1124.txt   # empty
```

- Frozen-1124: **950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH**, **0 movers**.
- All 1188 current dirs are also byte-identical to the v120 baseline
  (1014 OK / 58 GREEN / 116 FAIL).

### Runtime goldens (5/5)

Built from the canonical examples recipe (`-ffast -o <dir>` + `build_target.sh linux`):

```bash
timeout 120 /tmp/prod_ex/game_of_life/prog </dev/null > /tmp/prod_gold/gol.out 2>/tmp/prod_gold/gol.err
printf '(+ 1 2)\nexit\n' | timeout 30 /tmp/prod_ex/lisp_interpreter_curr/prog > /tmp/prod_gold/lisp_basic.out
timeout 30 /tmp/prod_ex/lisp_interpreter_curr/prog \
  < examples/z98/lisp_interpreter_upgraded/demo/canonical_feed.txt > /tmp/prod_gold/lisp_canon.out
( cd examples/z98/json_parser && timeout 30 /tmp/prod_ex/json_parser/prog </dev/null > /tmp/prod_gold/json.out )
timeout 30 bash examples/z98/mud_server/demo/session.sh \
  /tmp/prod_ex/mud_server/prog /tmp/prod_gold/mud_server.out /tmp/prod_gold/mud_client.out
```

| Golden | Measured md5 | Expected |
|---|---|---|
| game_of_life (100 gen) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` (83490 B) | same |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | same |
| lisp canonical 12-line | `96654b3910a54d8bb7ec3ddfc0f26c6a` | `canonical_expected.txt` same |
| json_parser | `8bda3d5a1ec07d14a301bc343df32bf8` | same |
| mud server / client | `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` | committed goldens same |

**5/5 exact** (mud server/client pair counted as one).

### Dump-MD5 pins (8/8, no mover)

Command from the repo root, for each `<mode>` in `-fsafe -ffast` and each entry:

```bash
/tmp/fixed_v121_build/zig1_5_clean <mode> --dump-c89 examples/z98/<name>/main.zig | md5sum
```

Baseline was re-run with the v120 seed compiler `/tmp/seed_v121/zig1_5_clean`
(md5 `11de43a053bdde3be3ddc61caac31df6`). All 8 values are identical:

| Entry | `-fsafe` md5 | `-ffast` md5 |
|---|---|---|
| mud_server | `bab44607cce6323e98bce50989eae4b2` | `0436db2738291f82a39e376ec7d88596` |
| game_of_life | `738c7ca45b305f91578c76a396e6950b` | `222fab7c86c27e4421fbe045245959e8` |
| lisp_interpreter_curr | `7facfa7c06c5c9870a07bf5c6fd6de68` | `de8f1afdee58ec1be1af5011f31a3c4d` |
| json_parser | `452e8875a5ddcf298d1b4eeb2a113137` | `f4f19376c197083db782d1b023bba368` |

**8/8, 0 movers.**

### Markers

```bash
mkdir -p /tmp/prod_markers
/tmp/fixed_v121_build/zig1_5_clean --markers --dump-c89 --output-dir /tmp/prod_markers \
  examples/z98/mud_server/main.zig >/tmp/prod_markers/stdout.txt 2>/tmp/prod_markers/markers.txt
```

rc=0; marker stream **3252 lines / 37293 B** (matches the accepted temp evidence).

### Examples (26/26)

`-ffast -o <dir>` + `build_target.sh linux` over `examples/z98/*/` (excluding `demo/` and
`z9dbg/`, 26 entries):

```text
OK days_in_month  OK fibonacci  OK func_ptr_return  OK game_of_life  OK heapsort  OK hello
OK json_parser  OK json_parser_upgraded  OK json_parser_workaround  OK lisp_interpreter
OK lisp_interpreter_adv  OK lisp_interpreter_curr  OK lisp_interpreter_upgraded  OK lzw
OK mandelbrot  OK mud_server  OK prime  OK quicksort  OK rogue_mud  OK rogue_mud_upgraded
OK sort_strings  OK tco_defer  OK tco_factorial  OK tco_return_try  OK z9play  OK z9torr
matrix entries=26 failures=0
```

### Stdlib + crosscheck

```bash
bash scripts/stdlib/verify_stdlib.sh /tmp/fixed_v121_build/zig1_5_clean
bash scripts/stdlib/run_crosscheck.sh /tmp/fixed_v121_build/zig1_5_clean
```

```text
run_fixtures: 336 PASS / 0 FAIL over 336 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK
```

Logs: `/tmp/prod_stdlib.log`, `/tmp/prod_crosscheck.log`.

## 4. Accepted `-fsafe` evidence

The committed `sf/src` is byte-identical to `/tmp/inv/src_fsafe` (`diff -rq` empty, exact diff
body match), so the prior agent's full `-fsafe` battery in `report.md` §Phase E is accepted
without a duplicate run: corpus 0 movers, stdlib 336/0, crosscheck 10/10, goldens 5/5, pins 8/8,
examples 26/26, `verify_upgraded.sh` `CLOSEOUT OK`. No `-fsafe` smoke was needed because the byte
check was exact.

## 5. Remaining MinGW `std_async` result (not fixed here)

A fully `-fsafe`-clean source still produces the same MinGW-CRT-built compiler failure:
`hello` is rejected at `std_async.zig:259` (`t.state`, then `:262`/`:263`, then
`std_debug.zig:64`), with **no trap**, on both `-osw` and `-osl`, under `-fsafe`, `-ffast`, and
`-mms-bitfields` (report §Phase C/D). It is not a masked overflow and remains a separate
Windows toolchain/layout/ABI or Win32-PAL/registry investigation. No source change for it is
included here.

## Artifacts

- build: `/tmp/fixed_v121_build/`, log `/tmp/fixed_v121_build.log`
- corpus: `/tmp/prod_corpus.txt`, `/tmp/prod_corpus.log`, frozen diffs under `/tmp/*frozen1124.txt`
- pins: `/tmp/prod_pins.txt`
- goldens: `/tmp/prod_gold/`
- examples: `/tmp/prod_ex/`, `/tmp/prod_examples.log`
- markers: `/tmp/prod_markers/`
- stdlib/crosscheck: `/tmp/prod_stdlib.log`, `/tmp/prod_crosscheck.log`
