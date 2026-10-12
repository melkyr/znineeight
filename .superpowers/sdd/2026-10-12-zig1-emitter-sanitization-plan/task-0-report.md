# Task 0 report — Preflight: baseline, inventory, P1–P10 execution ORDER

**Status:** DONE_WITH_CONCERNS
**Date:** 2026-10-12
**Branch:** `zig1_improvements` @ `f96e1206280938d3a35ed98e6a7318e2439931e6`
**Scope honored:** READ-ONLY for `sf/src` — zero compiler-source changes in this task. No seed rotation. No fixes of anything found (observations only).

---

## 0. Environment

| Item | Value |
|---|---|
| HEAD | `f96e1206280938d3a35ed98e6a7318e2439931e6` (`git rev-parse HEAD`) |
| Branch | `zig1_improvements` |
| Base seed | v97 `release/seed/zig1-seed.tgz` (archive md5 `7a2630c7ef37de664dd3a4da310c94cd`) |
| Seed-built compiler | `/tmp/task0_work/seed/zig1_5_clean`, md5 `bafbba9454cd2b134bdc3d50c65384e0` |
| Compiler `lib/` | 32 std `.zig` copied from current `sf/src` (note: `std_math.zig` post-dates v97 — see §1.6) |

---

## 1. Step 1 — frozen runtime baseline (every command + observed value)

### 1.1 Seed rebuild + self-emission closure

Command:
```bash
cd /workspace/znineeight
FIXED_POINT_MD5=bafbba9454cd2b134bdc3d50c65384e0 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/task0_work/seed
```
Observed output (key lines of `/tmp/task0_work/seed_build.log`):
```
[seed] hop1 binary md5: bafbba9454cd2b134bdc3d50c65384e0
[seed] hop2 binary md5: bafbba9454cd2b134bdc3d50c65384e0
[seed] two-hop closure OK: hop1 == hop2 == bafbba9454cd2b134bdc3d50c65384e0
[seed] recorded fixed point OK: bafbba9454cd2b134bdc3d50c65384e0
=== [seed] Done: /tmp/task0_work/seed ===
```
Extra check: `md5sum /tmp/task0_work/seed/zig1_5_clean` -> `bafbba9454cd2b134bdc3d50c65384e0`; `ls /tmp/task0_work/seed/lib | wc -l` -> `32`.
**Result: hop1 == hop2 == expected fixed point `bafbba9454cd2b134bdc3d50c65384e0` — MATCH.**

### 1.2 Corpus classify (tally + per-dir class list)

Command:
```bash
cd /workspace/znineeight
bash scripts/corpus/classify /tmp/task0_work/seed/zig1_5_clean /tmp/task0_work/corpus_baseline.txt
```
Observed output (tail of the run):
```
wrote /tmp/task0_work/corpus_baseline.txt: 1124 dirs
```
Tally command: `awk '{print $2}' /tmp/task0_work/corpus_baseline.txt | sort | uniq -c`
Observed:
```
    950 OK
    116 FAIL
     58 GREEN
```
(no `ICE`, no `CRASH`, no `NOENTRY`; `grep -vE ' (OK|GREEN|FAIL|ICE|CRASH|NOENTRY)$'` -> empty)

| class | observed | D6 closeout reference | delta |
|---|---|---|---|
| dirs | 1124 | 1122 | +2 |
| OK | 950 | 948 | +2 |
| GREEN | 58 | 58 | 0 |
| FAIL | 116 | 116 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

**+2 explained (evidence):** the corpus universe (`scripts/corpus/list_corpus_dirs.sh`) includes `repro/mi_matrix/*/`, `repro/*/`, `examples/z98/*/`, `stdlib_test/*/`. After the D6 closeout (`875b9a9e`) two dirs were added and both classify `OK`:
- `examples/z98/z9play` (z9play M0 example work) — classify line `examples/z98/z9play OK` (Appendix A).
- `repro/mi_matrix/stdlib_math_f64_xmod` (z9play M2 std_math band, commits `4d6fb5dd`/`b5ca08d2`) — classify line `repro/mi_matrix/stdlib_math_f64_xmod OK` (Appendix A).

**FAIL/ICE/CRASH unchanged — the baseline anchor condition ("no new FAIL/ICE/CRASH") holds.** The full per-dir class list (the comparison anchor for every later increment) is Appendix A — verified byte-exact against the classify output (`diff` empty; both sides md5 `518eca1a9b5d3e1cc5a48abce214abd8`, 1124 lines — command + output in Fix round 1 F6).

### 1.3 Runtime goldens (4 programs / 5 md5s) — RE-MEASURED

Build command (QUICK_REF "Compile + RUN" recipe, default `-fsafe`; per-program):
```bash
/tmp/task0_work/seed/zig1_5_clean --dump-c89 <ENTRY> > /tmp/task0_work/gold/<n>.c 2> <n>.dumperr
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/task0_work/gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
    -o /tmp/task0_work/gold/<n>
```
All 4 builds: `dump rc=0`, `gcc rc=0` (0 `error:`) — gol/lisp/json/mud.

Run commands + observed (expected values from QUICK_REF "Gate-program runtime outputs"):

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| `game_of_life` (100 gens) | `timeout 120 /tmp/task0_work/gold/gol > gol.out` (run rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | **YES** |
| `lisp_interpreter_curr` `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 /tmp/task0_work/gold/lisp > lisp.out` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | **YES** |
| `json_parser` | `cd examples/z98/json_parser && timeout 60 /tmp/task0_work/gold/json > json.out` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | **YES** |
| `mud_server` server | `bash examples/z98/mud_server/demo/session.sh /tmp/task0_work/gold/mud mud_srv.out mud_cli.out` (session rc=0); `md5sum mud_srv.out` | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | **YES** |
| `mud_server` client | (same session) `md5sum mud_cli.out` | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | **YES** |

Both mud files also `cmp`-equal the committed `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt` — the `cmp` command outputs (`cmp server: IDENTICAL`, `cmp client: IDENTICAL`) are recorded in Fix round 1 F6.
**Result: 5/5 goldens byte-identical to QUICK_REF.**

### 1.4 `examples/z98/*/` matrix — build AND run (all dirs)

Build command (per dir; entry resolution = `main.zig` -> `<dirname>.zig` -> first `*.zig`, same as `list_corpus_dirs.sh`):
```bash
/tmp/task0_work/seed/zig1_5_clean -ffast -o /tmp/task0_work/matrix/<name> <entry>
cd /tmp/task0_work/matrix/<name> && sh build_target.sh linux /tmp/task0_work/matrix/<name>/prog
```
Observed build table (26/26 — `dump=0`, >=1 `.c`, `build=0`):

| dir | entry | dump rc | .c | build rc |
|---|---|---|---|---|
| days_in_month | main.zig | 0 | 7 | 0 |
| fibonacci | main.zig | 0 | 6 | 0 |
| func_ptr_return | func_ptr_return.zig | 0 | 6 | 0 |
| game_of_life | main.zig | 0 | 7 | 0 |
| heapsort | main.zig | 0 | 6 | 0 |
| hello | main.zig | 0 | 7 | 0 |
| json_parser | main.zig | 0 | 9 | 0 |
| json_parser_upgraded | main.zig | 0 | 9 | 0 |
| json_parser_workaround | main.zig | 0 | 9 | 0 |
| lisp_interpreter | main.zig | 0 | 14 | 0 |
| lisp_interpreter_adv | main.zig | 0 | 15 | 0 |
| lisp_interpreter_curr | main.zig | 0 | 15 | 0 |
| lisp_interpreter_upgraded | main.zig | 0 | 15 | 0 |
| lzw | main.zig | 0 | 8 | 0 |
| mandelbrot | mandelbrot.zig | 0 | 6 | 0 |
| mud_server | main.zig | 0 | 9 | 0 |
| prime | main.zig | 0 | 6 | 0 |
| quicksort | quicksort.zig | 0 | 6 | 0 |
| rogue_mud | main.zig | 0 | 21 | 0 |
| rogue_mud_upgraded | main.zig | 0 | 20 | 0 |
| sort_strings | sort_strings.zig | 0 | 6 | 0 |
| tco_defer | main.zig | 0 | 6 | 0 |
| tco_factorial | main.zig | 0 | 7 | 0 |
| tco_return_try | main.zig | 0 | 7 | 0 |
| z9play | main.zig | 0 | 25 | 0 |
| z9torr | main.zig | 0 | 38 | 0 |

Run command (per dir; CWD = the example dir; `timeout 25` except mud_server `timeout 8`; stdin `/dev/null` except rogue* fed `q\n`):
```bash
cd examples/z98/<name> && timeout <t> /tmp/task0_work/matrix/<name>/prog < <feed> > run.out 2> run.err
```
Observed run table (26/26 correct):

| dir | run rc | stdout md5 (16) | first output | verdict |
|---|---|---|---|---|
| days_in_month | 0 | 8c0d394cbc6e7f36 | `Days in month for year 2024:...` | correct (u8 `{}` quirk pre-existing) |
| fibonacci | 0 | b53b3a3d6ab90ce0 | `55` | correct |
| func_ptr_return | 0 | f6a5477970a87a1c | `10 + 5 = 15 / 10 - 5 = 5` | correct |
| game_of_life | 0 | fcbf7e7cead5082f | 100-gen glider grid | correct (= golden) |
| heapsort | 0 | 8cf0a7844206319d | `135671112131520` | correct |
| hello | 0 | 746308829575e17c | `Hello, world!` | correct |
| json_parser | 0 | 8bda3d5a1ec07d14 | JSON tree | correct (= golden) |
| json_parser_upgraded | 0 | 8bda3d5a1ec07d14 | JSON tree | correct |
| json_parser_workaround | 0 | dc22fa473650bd3d | `Parsed JSON successfully` + tree | correct |
| lisp_interpreter | 0 | 1c1f0a417d5e9434 | REPL `> ` (EOF exit) | correct |
| lisp_interpreter_adv | 0 | 1c1f0a417d5e9434 | REPL `> ` | correct |
| lisp_interpreter_curr | 0 | 1c1f0a417d5e9434 | REPL `> ` | correct |
| lisp_interpreter_upgraded | 0 | 1c1f0a417d5e9434 | REPL `> ` | correct |
| lzw | 0 | c3c7765e6faf7b70 | LZW demo prompt (EOF error msg) | correct (interactive demo) |
| mandelbrot | 0 | d596677501e36537 | 80x24 fractal | correct |
| mud_server | 124 | 9545fe1d245293ef | `MUD server listening on port 4000` | correct (documented timeout-gated server) |
| prime | 0 | d095a94d20dcaf7a | `2357` | correct |
| quicksort | 0 | 45d2f0fb6fc40654 | sorted asc/desc | correct |
| rogue_mud | 0 | 3fb6709e7bbd8964 | Rogue MUD boot (exits on `q`) | correct |
| rogue_mud_upgraded | 0 | 3fb6709e7bbd8964 | Rogue MUD boot | correct |
| sort_strings | 0 | c6c047cbc13cdd4f | `Sorted strings: apple banana cherry date` | correct |
| tco_defer | 0 | 264ea6b106a51dde | `countDown(10) = countDown(100000) = deep ok` | correct (bunched-order quirk pre-existing) |
| tco_factorial | 0 | 3d70c50b5a37d549 | `fact(10) = 3628800 / deep ok` | correct |
| tco_return_try | 0 | 7421137aa2d104b4 | `count(10) = 10 / count(100000) = 100000` | correct |
| z9play | 1 | 2016494de476fcb6 | `usage: z9play --info <file.ogg> ...` | correct CLI usage-on-no-args |
| z9torr | 1 | f666af15cf2625b3 | `usage: z9torr [--help] ...` | correct CLI usage-on-no-args |

**Result: 26/26 build + 26/26 run correctly** (the two rc=1 usage exits and the mud rc=124 timeout are the documented correct behaviors).

### 1.5 Stdlib gate

Command:
```bash
cd /workspace/znineeight
bash scripts/stdlib/verify_stdlib.sh /tmp/task0_work/seed/zig1_5_clean
```
Observed output (final lines):
```
----------------------------------------
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
(vs D6 closeout `284 PASS / 0 FAIL` — +1 = `stdlib_math_f64_xmod`, consistent with the z9play M2 band that also updated `scripts/stdlib/expected_dirs.txt` +1.)
**Result: STDLIB GATE OK, 285 PASS / 0 FAIL.**

### 1.6 The 8 `--dump-c89` pin md5s — observed vs QUICK_REF table

Command (QUICK_REF 8-pin recipe, from repo root):
```bash
/tmp/task0_work/seed/zig1_5_clean <mode> --dump-c89 <ENTRY> 2>/dev/null | md5sum
```
**Observed with the CURRENT compiler `lib/` (current `sf/src` std set) — this is the Task-0-frozen pin baseline:**

| entry | mode | OBSERVED (current lib/) | QUICK_REF table | match |
|---|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `-fsafe` | `498b90f191b544655a1b731ef480709d` | `ad09343f1c0b9765716b2bd0857be0e2` | NO |
| `examples/z98/mud_server/main.zig` | `-ffast` | `50dbf5f02c1a5de920e158cab7f2f29b` | `4cb0991679fd89993438aea1686e7e47` | NO |
| `examples/z98/game_of_life/main.zig` | `-fsafe` | `52c5feb5f158e2af7b32a0509b43d4c6` | `6a9518e77f68cabbf86a356afebe2157` | NO |
| `examples/z98/game_of_life/main.zig` | `-ffast` | `7271960fc6375ed1dee34b7abfb6325b` | `12a230e214f6407c9a1bb6faaf2d4ca8` | NO |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-fsafe` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | `e7a8e48da407e8a7a87282ea35d886f9` | NO |
| `examples/z98/lisp_interpreter_curr/main.zig` | `-ffast` | `ec82996028671a52a0a3d52ad307edf1` | `e5b74f4f5326ee65ec2afe61d629affc` | NO |
| `examples/z98/json_parser/main.zig` | `-fsafe` | `48eedfc0243431693f65518646ad280c` | `6eb0c0f8699bba517ac43ad2b28f85a9` | NO |
| `examples/z98/json_parser/main.zig` | `-ffast` | `04124b2675e77020933cbfab20f883e1` | `5daac4a3cd2133fb00da3efda5b877df` | NO |

**Root cause (evidence-complete, not a failed measurement):** the compiler binary is bit-identical to the D6 closeout compiler (`hop1 == hop2 == bafbba94...`, the md5 D6 recorded for `/tmp/d6_new/zig1_5_clean`), the recipe is identical, the dumps are deterministic (same md5 on repeat runs: gol `-fsafe` `52c5feb5...` twice), and the pins are install-path-independent (identical md5 from `/tmp/task0_work/seed`, `/tmp/task0_copy`, and `/tmp/d6_new` — the exact D6 measurement path). What changed since the table was measured is the **`lib/` std set**: z9play M2 commits `4d6fb5dd` (f64 sqrt) and `b5ca08d2` (f64 sin/cos) grew `sf/src/std_math.zig` 54 -> 402 lines. Proof:

```bash
# only std_math.zig differs between the v97 archive's lib/ and current sf/src
for f in /tmp/task0_work/seedarch/zig1-seed/lib/*.zig; do diff -q "$f" sf/src/$(basename $f) || echo DIFFERS; done
# -> DIFFERS: std_math.zig   (54 lines archive vs 402 lines current)

# re-dump with the D6-era std_math.zig swapped into lib/:
cp /tmp/task0_work/seedarch/zig1-seed/lib/std_math.zig /tmp/task0_pincheck/lib/std_math.zig
/tmp/task0_pincheck/zig1_5_clean -fsafe --dump-c89 examples/z98/mud_server/main.zig | md5sum
# -> ad09343f1c0b9765716b2bd0857be0e2   (= QUICK_REF table)
```
Reproduction with the D6-era `std_math.zig` is **8/8 exact** against the QUICK_REF table:

| entry | mode | observed with v97-era std_math | QUICK_REF table | match |
|---|---|---|---|---|
| mud_server | `-fsafe` | `ad09343f1c0b9765716b2bd0857be0e2` | `ad09343f1c0b9765716b2bd0857be0e2` | **YES** |
| mud_server | `-ffast` | `4cb0991679fd89993438aea1686e7e47` | `4cb0991679fd89993438aea1686e7e47` | **YES** |
| game_of_life | `-fsafe` | `6a9518e77f68cabbf86a356afebe2157` | `6a9518e77f68cabbf86a356afebe2157` | **YES** |
| game_of_life | `-ffast` | `12a230e214f6407c9a1bb6faaf2d4ca8` | `12a230e214f6407c9a1bb6faaf2d4ca8` | **YES** |
| lisp_interpreter_curr | `-fsafe` | `e7a8e48da407e8a7a87282ea35d886f9` | `e7a8e48da407e8a7a87282ea35d886f9` | **YES** |
| lisp_interpreter_curr | `-ffast` | `e5b74f4f5326ee65ec2afe61d629affc` | `e5b74f4f5326ee65ec2afe61d629affc` | **YES** |
| json_parser | `-fsafe` | `6eb0c0f8699bba517ac43ad2b28f85a9` | `6eb0c0f8699bba517ac43ad2b28f85a9` | **YES** |
| json_parser | `-ffast` | `5daac4a3cd2133fb00da3efda5b877df` | `5daac4a3cd2133fb00da3efda5b877df` | **YES** |

This is exactly the documented "absolute pin values are compiler-build dependent (each compiler build pairs a `lib/` std set)" variance — the current build pairs a *post-table* std set. Per the milestone gate the pins are **recorded, not held fixed**; the OBSERVED current-lib values above are the comparison anchor for P1–P10. See Concerns C1 (QUICK_REF table stale; re-baseline at Task C).

### 1.7 `--markers` telemetry (cheap capture)

Command:
```bash
/tmp/task0_work/seed/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/task0_work/mk_gol.c 2>/tmp/task0_work/mk_gol.bin
grep -ac '^' /tmp/task0_work/mk_gol.bin
grep -a '^' /tmp/task0_work/mk_gol.bin | sed 's/[-0-9 ].*//' | sort | uniq -c | sort -rn | head
```
Observed: dump rc=0; stderr **36,038 bytes / 3,241 marker lines**. Top prefixes:
```
1810 INT:new
 423 DC:k
 240 FE:p
 195 P
 195 FWD:n=
 122 RaD
  86 MT
  69 FE:
  26 arena
  17 X:
  17 IRP:p / 17 IRP:n / 17 IRP:m
   2 IRN:n
   2 IRE:x
```
(Extraction used `grep -a`, per QUICK_REF "Marker extraction — use `grep -a`, NOT `strings`".)

### 1.8 `repro/mi_matrix` runtime confirmers — FULL anchor set (broadened, fix round 1)

**Anchor-set definition (frozen; load-bearing for every later increment):** all `repro/mi_matrix/*/` dirs that (a) are NOT `stdlib_*` (those are owned by the stdlib gate, §1.5) and (b) ship committed goldens with **non-empty `expected.txt` AND `expected.rc == 0`** — enumerated count **25** (matches the review's count; enumeration command + output in Fix round 1 F1) — PLUS the D-fix-family trap fixture `slice_index_field_store_oob_xmod` (empty `expected.txt`, `expected.rc=133`, measured under `-fsafe`). Excluded and why: 37 reject-census dirs ship only `expected.rc` (e.g. `alias_value_reject_xmod`: `expected.rc` = `2` + `expected_error.txt`, no `expected.txt`) — compile-time rejects with no runtime stdout, owned by corpus classify (FAIL/GREEN buckets), not runtime anchors. The D-fix-family entries recorded in round 0 remain in the set as a subset (`slice_index_field_store_xmod`, `slice_index_field_store_oob_xmod`) plus the 3 sibling runtime prints (no goldens; NOTES contracts) kept as extra evidence.

**Run recipe for the 25** (the golden-owner harness shape, `scripts/stdlib/run_fixtures.sh`): `zig1 -ffast -o <tmp> <entry>` -> gcc every emitted `.c` (binding flag-set) -> `sh <tmp>/build_target.sh linux <tmp>/prog` -> run under `timeout 120` from a scratch CWD, 3x (byte-identical across runs asserted) -> `cmp` stdout vs `<dir>/expected.txt` + rc vs `<dir>/expected.rc`. Harness command + result: Fix round 1 F2 (`25 PASS / 0 FAIL`). Per-fixture observed values (single determinism-proven run; stdout md5 vs `expected.txt` md5):

| fixture (repro/mi_matrix/) | dump/build rc | run rc (exp) | stdout md5 == expected.txt md5 | verdict |
|---|---|---|---|---|
| array_of_struct_literal_xmod | 0/0 | 0 (0) | `72ff47472a8c39c1f47a27abaca42b72` | MATCH/MATCH |
| catch_discard_struct_xmod | 0/0 | 0 (0) | `9399dde1eebdfff4562fc66f948a3bba` | MATCH/MATCH |
| const_assign_ok_xmod | 0/0 | 0 (0) | `6da2ebec75aa1da53cee85b52b5daa65` | MATCH/MATCH |
| empty_named_struct_field_xmod | 0/0 | 0 (0) | `d9d64c38f109b3bd79447f975d88ddaf` | MATCH/MATCH |
| empty_named_struct_xmod | 0/0 | 0 (0) | `9c9989314cb32021d85ba5db5b9801cb` | MATCH/MATCH |
| enum_subbyte_backing_xmod | 0/0 | 0 (0) | `08180636d67745666fba65e927b299a7` | MATCH/MATCH |
| f64_literal_precision_xmod | 0/0 | 0 (0) | `bbd2bd05993b186e658e888c162ef1b4` | MATCH/MATCH |
| field_store_continue_nested_xmod | 0/0 | 0 (0) | `af474292ea3eef895aa1dbf839bc3307` | MATCH/MATCH |
| field_store_continue_xmod | 0/0 | 0 (0) | `e50f7dcda1bfc23cbead76b2d48df649` | MATCH/MATCH |
| fn_ptr_signature_ok_xmod | 0/0 | 0 (0) | `2737b49252e2a4c0fe4c342e92b13285` | MATCH/MATCH |
| for_range_end_len_xmod | 0/0 | 0 (0) | `79d2d702c618bbbaa19d3dc9ecfe6d6b` | MATCH/MATCH |
| len_array_field_xmod | 0/0 | 0 (0) | `ee04a6903155eaf4d9f46e3de760a3ae` | MATCH/MATCH |
| lexer_float_exponent_xmod | 0/0 | 0 (0) | `9e46db753b1c599fc16b35e94c64252a` | MATCH/MATCH |
| lit64_decimal_xmod | 0/0 | 0 (0) | `9b471756c72fee0e5c08ed63306a4360` | MATCH/MATCH |
| nested_loop_label_xmod | 0/0 | 0 (0) | `c6a1e09332ec123e058ddbae503faa5f` | MATCH/MATCH |
| optional_void_present_xmod | 0/0 | 0 (0) | `f45bd81312c3860e773b509fa1a5c388` | MATCH/MATCH |
| packed_nested_whole_depth_ok_xmod | 0/0 | 0 (0) | `4439a7a296ee24e78e402d0cd534fa27` | MATCH/MATCH |
| packed_nested_wholeliteral_xmod | 0/0 | 0 (0) | `4485cac0a23b786b166bce974601ec77` | MATCH/MATCH |
| packed_union_struct_wholemember_xmod | 0/0 | 0 (0) | `847cf70929d6844315b21cf24cf1c45b` | MATCH/MATCH |
| shadow_ok_xmod | 0/0 | 0 (0) | `806ad1987c43d13622bb850c4517ee37` | MATCH/MATCH |
| sig_known_type_ok_xmod | 0/0 | 0 (0) | `5c542c2d0a6c6c64aac8bdef9cef8171` | MATCH/MATCH |
| slice_index_field_store_xmod | 0/0 | 0 (0) | `c11ad986cc71be4250c4b4e3e4d801f5` | MATCH/MATCH (= `9/11/22/ok`) |
| tagged_payload_whole_reassign_xmod | 0/0 | 0 (0) | `82223e28b19e58787bff9ebfcd6a8782` | MATCH/MATCH |
| tagged_tag_member_shadow_xmod | 0/0 | 0 (0) | `417c1307bd4c2233f930b5064d2da0c4` | MATCH/MATCH |
| tagged_tag_sugar_xmod | 0/0 | 0 (0) | `74b907f8ee8dac8d6aa67b41c25239c2` | MATCH/MATCH |

**D-fix-family trap fixture (subset; `-fsafe` recipe `zig1 -fsafe -o <out> <entry>` + `build_target.sh linux` + `timeout 120` run):**

| fixture | observed run | observed stdout / rc | expected | match |
|---|---|---|---|---|
| `slice_index_field_store_oob_xmod` | rc=133 (SIGTRAP) | empty stdout (md5 `d41d8cd98f00b204e9800998ecf8427e`) | `expected.rc=133`, empty `expected.txt` (same md5) | **YES** |

**Sibling D-fix runtime prints (no committed goldens; NOTES contracts; extra evidence, not anchors):** `union_keyword_tag_xmod` rc=0 `P=.{ .int = 7 }`/`3`; `slice_of_slice_xmod` rc=0 `11`; `async_frame_structret_xmod` rc=0 `5` — all match their NOTES (round-0 measurements, unchanged).

### 1.9 Baseline freeze summary (the anchor)

| gate | frozen observed value |
|---|---|
| seed two-hop closure | hop1 == hop2 == `bafbba9454cd2b134bdc3d50c65384e0` |
| corpus classify | **1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** (per-dir list: Appendix A) |
| runtime goldens | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322`; json `8bda3d5a1ec07d14a301bc343df32bf8`; mud `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` |
| examples matrix | 26/26 build + 26/26 run correct (table §1.4) |
| stdlib gate | 285 PASS / 0 FAIL / STDLIB GATE OK |
| 8 dump pins (current lib/) | §1.6 first table (recorded; delta vs QUICK_REF root-caused 8/8) |
| markers telemetry | gol: 3,241 lines / 36,038 B (§1.7) |
| mi_matrix runtime anchors (§1.8 set) | **25/25 golden-bearing fixtures MATCH (stdout md5 + rc)** + oob trap fixture rc=133/empty MATCH (subset); sibling prints D1 `P=.{ .int = 7 }`/`3`, D2 `11`, D4 `5` |

---

## 2. Step 2 — emitter smell inventory (spec §3 categories 1–7 + survey extras)

Convention: `file:line` are **current** lines (re-derived 2026-10-12 at `f96e1206`; every cite re-verified by `grep -n` in Fix round 1 F4 — round-0 had three wrong cites, now corrected); "brief" cites are the plan/§3 numbers; drift is called out. Upstream owner per spec §4 target architecture.

### 2.1 Category 1 — No single naming authority (roots D1, D2) -> **P1**

| item | current site | duplicates / problem | upstream owner | risk / effort |
|---|---|---|---|---|
| `NameMangler` defined inside the emitter | `sf/src/c89_emit.zig:93` (brief 93 exact) | the minter is emitter-private | revived `sf/src/name_mangler.zig` | high blast (every emitted ident); byte-stable contract for non-colliding names |
| dead 7-line stub | `sf/src/name_mangler.zig:1-7` (brief "7-line stub" exact) | parallel type name, unused logic | delete after revival | trivial delete, verified dead (§2.8) |
| `ctx.name_mangler` write-only | write `sf/src/main.zig:333` (decl `:104`, init `:206`); also decl `sf/src/main_dump.zig:60`; stub imports `sf/src/strip_main.zig:2-3` + discard use `:6-7` (`var nm = nameManglerInit(); _ = nm;`) | stub type threaded through context / imported, never meaningfully read | delete stub usage — P1 delete set = `main.zig:10/:104/:206/:333`, `main_dump.zig:10/:60`, `strip_main.zig:2-3` + `:6-7` discard, `name_mangler.zig:1-7` | trivial (verified write-only/discard) |
| collision resolution only in `nameManglerMangle` | `c89_emit.zig:657` (brief 657 exact) | every other mint site skips collision handling | P1 authority | medium |
| struct field names emitted raw | decl `emitStructType` `c89_emit.zig:2091` (brief 2091 exact); access `resolveFieldAccess` `:468` (addr-of struct), `:513` (ptr->struct), `:558` (value-named struct arm) (brief 468/513/524/558 exact) | raw interner name; keyword/C-collision exposure (D1 class) | P1 authority (struct-field kind) | **runtime-risk**: keyword field names today = gcc reject; collision = silent alias |
| union-member escape without collision check | `mangleC89Keyword:577` (brief 577 exact), `cUnionMemberName:594` (brief 594 exact); applied `:524` (ptr->union), `:558` (value union), `emitUnionType:2105`, `emitTaggedUnionType:1950`, `emitVariantFieldPayload:419`, `emitAggPrinterDef:6202` | `z_` escape only; `int` vs `z_int` collide (F1 concern 2) | P1 authority | medium |
| locals minted ad-hoc | `mangleLocalName:2431` (brief 2431 exact) | separate minter, keyword map only | P1 | low |
| temps minted ad-hoc | `mangleTempName:3195` (brief 3195 exact — no drift) | separate minter (`zT_<id>`) | P1 | low |
| synthetic type names minted ad-hoc | `syntheticTypeName:897` (exact), `sliceElementName:931` (exact), `getCTypeName:940` (exact) | D2 class naming | P1 mints; P3 derives (plan sequences P1->P3) | medium |
| module symbols minted ad-hoc | `moduleQualifiedName:2795` (brief 2795 exact) | path-derived minter inline | P1 | low |
| printer symbols minted ad-hoc | `typeIdName:5530` (brief 5530 exact — no drift), consumed `getPrintFnName:5472`/`printFnSourceName:5429` | `prefix+decimal tid` inline naming rule | P1 (or P3's typeCName) | low |
| globals minted ad-hoc (extra) | `nameManglerMangleGlobal:738` | second global-naming path | P1 | low |

### 2.2 Category 2 — Two divergent type-dependency graphs (roots D8) -> **P2**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| resolver graph | `typeResolverBuildDependencyGraph` `sf/src/type_resolver.zig:629` (brief 629 exact); predicates `kindIsAggregateCore:593`, `fieldEmbedsByValue:599`, `requiresFullDef:604`, `layoutFieldNeedsEdge:609` | one of two graphs | `type_registry.typeRefs`/`typeNeedsFullDef` | high risk (typedef order -> gcc) |
| dead sorted accessor | `typeResolverGetSorted` `type_resolver.zig:889` (brief 889 exact) | DEAD (0 callers, §2.8) | delete (P2) | trivial |
| emitter ordering drivers | `c89NeedsEmitEdge:1324` (exact), `tstEdgesWalk:1363` (exact), `tstTopologicalSort:1484` (exact); consumers `emitTypeDefOnce:1571`, `emitPointeeDep:1603`, `emitDepMember:1656`, `emitTypeDeps:1669`, `emitNeededTupleAt:6589` | second graph, hand-rolled | derive from `typeRefs` (P2) | high (self-host hop closure gate) |
| predicate divergence (D8 core) | `c89NeedsEmitEdge` (emitter): includes `fn_type` (added z98-print Task 6, 2026-09-25), excludes `packed_union_type`; resolver predicates include `packed_union_type` (via `kindIsAggregateCore`) but exclude `fn_type` | **spec §3 drift:** "fn_type missing in both" is stale — now missing only on the resolver side; `packed_union` missing only on the emitter side (as stated) | one relation, P2 | medium |
| third dead predicate | `isValueDependency` `sf/src/type_registry.zig:980` (see §2.8) | DEAD (0 callers); a third divergent value-embed set | delete (P2) | trivial |

### 2.3 Category 3 — `getCTypeName` re-derives the synthetic type model -> **P3**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| synthetic C-name derivation in emitter | `getCTypeName` `c89_emit.zig:940` (brief 940 exact) | re-derives the synthetic model | `typeCName` in `type_registry`/`type_resolver` | medium (name bytes move; pins recorded; runtime-identical) |
| memo write-back into the registry | `typeRegistryCNameIdSet` call `c89_emit.zig:2428` (brief 2428 exact) | emitter mutates registry naming state | `typeCName` owns its memo | medium |
| self-duplicates | `emitArrayType:2145` (brief 2145 exact), `emitOptionalType:2373` (brief 2373 exact) | second C-name spellings for the same types | P3 dedup | low-medium |
| extra name derivations (extra) | `getUnsignedCTypeName:4692`, `ptrCTypeNameFromElem:4952` | two more C-name paths beside `getCTypeName` | fold into P3 | low |

### 2.4 Category 4 — Classification overlap -> **P4**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| resolver classification | `classifyTypeEmissionGroups` `sf/src/type_resolver.zig:662` (brief 662 exact) | the canonical pass (already exists) | resolver | — |
| emitter re-classification | `computeSharedSet` `c89_emit.zig:1702` (exact), `shouldSkipTypeEmission:1775` (exact) | second shared/skip decision | consume resolver result | medium (shared-set drift -> emission-set change -> gcc) |

### 2.5 Category 5 — Semantic predicate/promotion duplication -> **P5**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| emitter int-kind truth tables | `intKindIsSignedBase:9473`, `intKindIsUnsignedBase:9479`, `intKindWidthBytes:9487` (brief `:9473-9496` exact region) | duplicates registry predicates | `type_registry.zig:919-1049` (`typeRegistryIntWidthBits:919`, `typeRegistryIntIsSigned:931`, `typeRegistryIsNumeric:997`, `typeRegistryIsPointer:1046` — brief `:919-1049` exact) | low-medium (membership-preserving refactor; the "Task 2b3 D1-2" comment already froze caller sets) |
| emitter signedness/width dispatchers | `classifyIntSignedness:4712`, `intTypeNeedsWidthWrap:4722`, `intTypeByteWidth:4895` (brief `:4712-4929`, `:4895` exact) | per-caller "extras" (e.g. `c_char`/`integer_literal`/`undefined`/`null` -> signed in `classifyIntSignedness`) diverge from `typeRegistryIntIsSigned` | P5 must expose canonical predicates and keep per-caller membership verbatim | medium |
| C usual-arithmetic promotion re-done in emitter | `emitBinRvalueText:4385` (brief 4385 exact) | duplicates coercion common-type logic | `coercion.zig` promotion | medium (codegen-affecting) |

### 2.6 Category 6 — Re-deciding lowerer/analyzer decisions -> **P6**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| field re-resolution | `resolveFieldAccess` `c89_emit.zig:459` (brief 459 exact) | re-resolves what `semanticAnalyzerResolveFieldAccess` `sf/src/semantic_analyzer.zig:1562` (brief 1562 exact) already resolved | LIR field ordinal/name (`lower.zig`/`lir.zig`) | high (field-id mismatch = wrong member) |
| callee fn-type recovery | `findCalleeFnTypeId` `c89_emit.zig:2458` (brief 2458 exact) | linear scan over all types to recover a decision the lowerer had | LIR callee fn type id | medium |
| temp type re-derivation | `getTempTypeByIndex:1172`, `hoistedTypeOfInFn:1186`, `hoistedTypeOf:1195`, `hoistedTypeId:1201` (brief `:1172-1208` exact); `getTempEffType:4963`, `getTempTypeInfoResolve:4996`, `getTempTypeInfo:5011` (brief `:4963-5028` exact); ICE fallback `:5019` "temp type resolution failed" | re-derives temp result types | LIR temp result types | high (wrong temp type = wrong C) |
| saturation semantics in emitter | `emitSatBinary:5030`–~5400 (brief `:5030-5400` exact) | saturation op semantics belong to lowering | LIR saturation op / lowering helper | medium |

### 2.7 Category 7 — ICEs encoding semantic invariants + dead code -> **P9 (nest*) / P1+P2 deletions**

| item | current site | problem | upstream owner | risk / effort |
|---|---|---|---|---|
| `nest*` ICE family | `nestScalarEffTid:3978`, `nestEffCType:3995`, `nestDefTempId:4004`, `nestShapeOk:4018`, `nestConsumerWired:4065`, `nestEmitDefRvalue:4255`, `nestEmitBinExpr:4329`, `nestFail:4201`; ICE strings `:4228/:4235/:4240` ("T4b invariant broken") | ICEs encode invariants the lowerer should guarantee | structural frame-save rule (P9) + LIR guarantees (P6) | medium |
| `nest_inl` frame-decl suppression | `c89_emit.zig:3827-3828` (brief 3827-3828 exact); state `nest_ok/nest_max/nest_inl` decl `:779-781` | site-fix suppression of temps in the decl loop | P9 | medium-high (async runtime) |
| other semantic ICEs | `:5019` (temp type), `:7577` "store_field unresolved field", `:7707` "addr_of_field unresolved base field" | encode analyzer/lowerer invariants | P6/P10 territory | medium |
| dead code | `typeResolverGetSorted` (§2.2), `isValueDependency` (§2.2), `name_mangler.zig` stub + `ctx.name_mangler` (§2.1) | all three VERIFIED dead (§2.8) | delete in P1/P2 | trivial |

### 2.8 Dead-code claim verification (grep evidence — full outputs, fix round 1)

```
$ grep -rn "typeResolverGetSorted" sf/src/
sf/src/type_resolver.zig:889:pub fn typeResolverGetSorted(self: *TypeResolver) []u32 {
# -> definition only; ZERO call sites. DEAD.

$ grep -rn "isValueDependency" sf/src/
sf/src/type_registry.zig:980:pub fn isValueDependency(kind: TypeKind) bool {
# -> definition only; ZERO call sites. DEAD.

$ grep -rn "name_mangler" sf/src/          # FULL output (was abridged in round 0):
sf/src/strip_main.zig:2:const NameMangler = @import("name_mangler.zig").NameMangler;
sf/src/strip_main.zig:3:const nameManglerInit = @import("name_mangler.zig").nameManglerInit;
sf/src/main.zig:10:const nm_mod = @import("name_mangler.zig");
sf/src/main.zig:104:    name_mangler: *NameMangler,
sf/src/main.zig:206:     var name_mangler = nm_mod.nameManglerInit();
sf/src/main.zig:333:        .name_mangler = &name_mangler,
sf/src/main_dump.zig:10:const nm_mod = @import("name_mangler.zig");
sf/src/main_dump.zig:60:    name_mangler: *NameMangler,

$ grep -rn "NameMangler\|nameManglerInit" sf/src/name_mangler.zig
sf/src/name_mangler.zig:1:pub const NameMangler = struct {
sf/src/name_mangler.zig:5:pub fn nameManglerInit() NameMangler {
# (stub body :1-7; the pattern "name_mangler" matches import paths/field names only,
#  not the stub's own identifiers — hence this second grep for the stub file itself.)

$ sed -n '1,8p' sf/src/strip_main.zig
const pal = @import("pal.zig");
const NameMangler = @import("name_mangler.zig").NameMangler;
const nameManglerInit = @import("name_mangler.zig").nameManglerInit;

pub fn main() void {
    var nm = nameManglerInit();
    _ = nm;
```
Conclusions (unchanged by the full output): `typeResolverGetSorted` DEAD (0 callers); `isValueDependency` DEAD (0 callers); the stub `name_mangler.zig` is used ONLY by (a) `main.zig:10/:104/:206/:333` — `ctx.name_mangler` written at `:333`, NEVER read (write-only), (b) `main_dump.zig:10/:60` — field declared, never read, (c) `strip_main.zig:2-3` imports + `:6-7` `var nm = nameManglerInit(); _ = nm;` (explicit discard). All stub usage goes in P1's delete set (including `strip_main.zig:2-3` + the `:6-7` discard). The real minter is `c89_emit.zig:93`/`:643` (`c89_mod.nameManglerInit`, used `main.zig:1197-1199`).
Also confirmed **live** (not dead): `c89NeedsEmitEdge` drives emission — it is "divergent", to be REPLACED by `typeNeedsFullDef`-derived edges in P2, not deleted outright first.

### 2.9 Additional emitter-held responsibilities found in the survey (beyond §3)

1. **D3/D4 site-fix residue in the decl loop** — `d4_dead`/`d4_local`/`d4_nodecl` skip checks at `c89_emit.zig:3831-3833` (grep-verified; the skip cascade region is `:3824-3833`), and a leftover debug `markerWrite("OK\n")` at `:3820` in the hoisted-temp decl path. Belongs to P9's structural frame-save rule (the flags are the ad-hoc encoding of "declared vs alias temps"). Effort folded into P9.
2. **Extra C-name derivations** — `getUnsignedCTypeName:4692`, `ptrCTypeNameFromElem:4952` (listed §2.3): fold into P3's `typeCName`.
3. **Extra minter entry points** — `mangleTempName:3195`, `mangleLocalName:2431`, `nameManglerMangleGlobal:738` (listed §2.1): fold into P1.
4. **Marker/telemetry writes in hot emit paths** — `pal.measureMarkerWrite`/`markerWrite` scattered through emission (e.g. `emitStructType` `:2088-2090`, decl loop `:3816-3820`). No runtime effect; observation only — NOT in any P-scope (out of milestone scope; do not touch).
5. **`classifyIntSignedness` extras-membership divergence** (§2.5) — beyond the table duplication itself, the "which kinds count as signed" membership differs per caller; P5 must preserve exact membership (the existing "Task 2b3 D1-2" comment is the precedent).

---

## 3. Step 3 — execution ORDER of P1–P10 (governs all remaining tasks)

**The plan's bullet order is a catalog, not the execution order.** The order below is fixed by dependency + runtime-risk and supersedes the catalog order for execution. **No split/merge:** each increment stays one responsibility / one compiler-moving commit (P1 and P6 are the widest; their Investigate steps must confirm the full touch set, but neither may be split — a half-migrated naming authority or lowerer handoff is exactly the fragmentation this milestone removes).

| exec # | increment | one-line justification |
|---|---|---|
| 1 | **P5 Predicates + promotion centralized** | No inbound dependency; membership-preserving foundation; its canonical `type_registry`/`coercion` predicates are consumed by P2's `typeNeedsFullDef` and P3's int naming, so landing it first stops later moves from re-duplicating tables; smallest blast of the emitter moves -> validates the per-increment battery against the frozen baseline early. |
| 2 | **P1 Identifier authority** | Hard prerequisite of P3 (synthetic-name minting) and P6 (field/temp names through the authority — controller conflict-scan interface); roots D1/D2; the most-consumed foundation, so it lands before every name-routing move. |
| 3 | **P2 Type-reference relation + ordering** | Consumes P5's canonical predicates; adds the `type_registry` relation P3 sits beside; deletes the dead `typeResolverGetSorted`/`isValueDependency` and replaces the divergent `c89NeedsEmitEdge`; roots D8; must precede P3/P4 because both build on the settled type-reference relation and the reworked ordering machinery. |
| 4 | **P3 Canonical `typeCName`** | Hard-depends on P1 (synthetic names minted through the authority; plan text itself sequences P1 then P3); consumes P2's stabilized `type_registry` surface; closes D2 residue (write-back `:2428` removal + `emitArrayType`/`emitOptionalType` dedup). |
| 5 | **P4 Single classification pass** | Consumes the resolver classification over the typedef-ordering machinery P2 just rebuilt — the two rework adjacent regions of the same emission loop (controller conflict-scan), so classification simplification lands second, on settled ordering. |
| 6 | **P6 Lowerer carries decisions** | Hard-depends on P1 (names via the authority) and consumes P3's `typeCName` for the emitter-read types; removes the last emitter re-decisions (`resolveFieldAccess`/`findCalleeFnTypeId`/`getTemp*`/`emitSatBinary`); its LIR records (field ordinal/name, temp result types) are the substrate P9 ("declared temps") and P10 (checked field/index stores) consume. |
| 7 | **P10 Lvalue unification** | After P6 so the single checked address-taking path operates on LIR-carried field decisions instead of being re-touched by P6 afterwards (merge-risk minimization in `lower.zig`); closes the live D5-residue `-fsafe` root-index gap on `lowerFieldStore`; gated by the runtime confirmers frozen in §1.8 (`slice_index_field_store_xmod` `9/11/22/ok`, oob rc=133). |
| 8 | **P9 Structural frame-save rule** | After P6's temp-result typing on LIR (the "declared temps" source) and clear of P6's `lower.zig` churn; roots D3/D4; guards the `nest_inl` suppression path `c89_emit.zig:3827-3828` + replaces the `d4_*` skip flags (§2.9.1); async runtime confirmers (`async_frame_*`, §1.8 `async_frame_structret_xmod`) are in the frozen baseline. |
| 9 | **P8 Builtin arity/descriptor table** | Reject-only root-cause of D6 (the ~20 unchecked builtins); expect intentional corpus-class movers -> declared green-guards + arity reproducers; placed in the behavioral band after the mechanism moves so class movers cannot be confused with refactor fallout; additive table lands on `semantic_analyzer.zig` before P7 reworks the same file's resolution machinery. |
| 10 | **P7 Front-end module-scope-first name resolution** | Deepest behavioral change (binding changes accept/reject and which decl a name binds — root-cause of D7); lands last with the full battery battle-tested and its `Mode`-collision reproducer as the gate; second of the two `semantic_analyzer.zig` moves so the file's two mechanisms never interleave. |

**Execution sequence: P5, P1, P2, P3, P4, P6, P10, P9, P8, P7.**

**Risk-band summary:** 1–6 = behavior-preserving relocation/refactor band (pins may move, recorded old->new with runtime proof); 7–8 = runtime-semantics root-cause band (strong runtime confirmers exist in the frozen baseline); 9–10 = accept/reject behavioral band (declared class movers + new reproducers). Every increment runs the full §1 runtime battery; seed rotates at closeout (or early if the fixed point moves, recorded + `hop1==hop2`).

---

## 4. Concerns (short list)

- **C1 (pins):** QUICK_REF's 8-pin table is stale with respect to the current `lib/` std set — z9play M2 (`4d6fb5dd`/`b5ca08d2`) grew `sf/src/std_math.zig` 54->402 lines after the table was measured. Observed 8/8 differ; root cause proven 8/8 (swap D6-era `std_math.zig` -> table values reproduce exactly). The current-lib observed pins (§1.6) are the frozen anchor; QUICK_REF must be re-baselined at Task C closeout. Runtime goldens unaffected (5/5 byte-identical). No silent fixing performed.
- **C2 (corpus universe):** 1124 dirs vs D6's 1122 — `examples/z98/z9play` + `repro/mi_matrix/stdlib_math_f64_xmod` (both `OK`). FAIL/ICE/CRASH unchanged. Later increments compare against the Appendix A anchor, not against the D6 note. Stdlib gate likewise 285 (was 284).
- **C3 (spec §3.2 drift):** "fn_type missing in both" is stale — `c89NeedsEmitEdge` gained `fn_type` (2026-09-25); the resolver predicates still lack it. `packed_union` is missing only in the emitter edge predicate (as stated). P2's Investigate must key on the actual current split (§2.2), not the spec's sentence.
- **C4 (line cites — CORRECTED in fix round 1):** the round-0 report's `mangleTempName:3194`, `typeIdName:5529`, `intTypeNeedsWidthWrap:4723` cites were **wrong** (sed-window eyeball off-by-one) and the claimed "drift -1" was **false** — the brief's cites were exact (`fn mangleTempName` = `sf/src/c89_emit.zig:3195`, `fn typeIdName` = `:5530`) and there is **no line drift** in §3. Corrected here; all three corrected cites + every other §2 cite are grep-verified in Fix round 1 F4. `fn mangleTempName`/`fn typeIdName` are exact — no drift.
- **C5 (matrix CLI behavior):** `z9play`/`z9torr` exit rc=1 with usage text on no-args and `mud_server` is timeout-gated (rc=124) — documented correct behaviors, recorded so later increments do not treat them as regressions.
- **C6 (mi_matrix anchor set — broadened in fix round 1):** round 0 froze only the D-fix family (5 fixtures) and that narrowing was not raised as a concern — corrected. The runtime-battery line "repro/mi_matrix runtime reproducers" now freezes the FULL §1.8 set: the **25** non-stdlib golden-bearing fixtures (non-empty `expected.txt` + `expected.rc=0`) + `slice_index_field_store_oob_xmod` (trap subset). 25/25 MATCH + oob MATCH at baseline; no golden mismatch; set definition unambiguous (enumeration count = 25). Every later increment must keep this whole set green.

No BLOCKED items: every measurement landed with evidence; the one contradiction found (C1) was root-caused to a documented variance source with an 8/8 reproduction.

---

## Appendix A — frozen corpus class list (comparison anchor; 1124 dirs)

Produced by `bash scripts/corpus/classify /tmp/task0_work/seed/zig1_5_clean /tmp/task0_work/corpus_baseline.txt` at `f96e1206`. Format: `<repo-relative-dir> <CLASS>` (classifier = `scripts/corpus/classify`; classes OK/GREEN/FAIL/ICE/CRASH).

```
examples/z98/days_in_month OK
examples/z98/fibonacci OK
examples/z98/func_ptr_return OK
examples/z98/game_of_life OK
examples/z98/heapsort OK
examples/z98/hello OK
examples/z98/json_parser OK
examples/z98/json_parser_upgraded OK
examples/z98/json_parser_workaround OK
examples/z98/lisp_interpreter OK
examples/z98/lisp_interpreter_adv OK
examples/z98/lisp_interpreter_curr OK
examples/z98/lisp_interpreter_upgraded OK
examples/z98/lzw OK
examples/z98/mandelbrot OK
examples/z98/mud_server OK
examples/z98/prime OK
examples/z98/quicksort OK
examples/z98/rogue_mud OK
examples/z98/rogue_mud_upgraded OK
examples/z98/sort_strings OK
examples/z98/tco_defer OK
examples/z98/tco_factorial OK
examples/z98/tco_return_try OK
examples/z98/z9play OK
examples/z98/z9torr OK
repro/addr_of_deref OK
repro/anon_init_if_arm OK
repro/anon_init_var_decl OK
repro/bool_literal_lower OK
repro/capture_rename FAIL
repro/comptime_fold_typed_payload OK
repro/comptime_i64_big_negative OK
repro/comptime_i64_negative OK
repro/comptime_signed_divmod OK
repro/comptime_signed_negate OK
repro/deref_store_aggregate OK
repro/deref_store_compound OK
repro/deref_store_param_addr OK
repro/deref_store_scalar_addr OK
repro/diag_while_cap OK
repro/eu_optional_payload OK
repro/eu_void_payload OK
repro/field_load_slice_end OK
repro/field_store_ptr OK
repro/field_store_ptr_compound OK
repro/field_store_slice_len OK
repro/field_store_tagged OK
repro/for_capture_shadow OK
repro/for_in_array OK
repro/for_in_counter OK
repro/index_compound_store OK
repro/mi_eu_opt_null OK
repro/mi_matrix/a1_ptrarray_cchar_xmod OK
repro/mi_matrix/a1_ptrarray_strtod_xmod OK
repro/mi_matrix/a1_strlit_ptrarray_warn_xmod OK
repro/mi_matrix/alias_value_reject_xmod GREEN
repro/mi_matrix/analyzer_for_body_xmod FAIL
repro/mi_matrix/analyzer_labeled_reject_xmod FAIL
repro/mi_matrix/analyzer_switch_merge_reject_xmod FAIL
repro/mi_matrix/anon_errset_comparison OK
repro/mi_matrix/anon_init_orelse_rhs OK
repro/mi_matrix/anytype_reject_xmod FAIL
repro/mi_matrix/arena_multi_inst_xmod OK
repro/mi_matrix/arena_oom_green_xmod OK
repro/mi_matrix/array_inferred_len_decl_reject_xmod GREEN
repro/mi_matrix/array_manyptr_type OK
repro/mi_matrix/array_of_slices_literal_xmod FAIL
repro/mi_matrix/array_of_struct_literal_xmod OK
repro/mi_matrix/array_size_intcast_range_reject_xmod GREEN
repro/mi_matrix/array_size_negative_reject_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_builtin_reject_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_fwd_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_mutual_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_slice_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_tuple_xmod FAIL
repro/mi_matrix/array_size_struct_introspection_union_xmod FAIL
repro/mi_matrix/array_tagged_union_read OK
repro/mi_matrix/array_value_copy OK
repro/mi_matrix/assignment_expr_reject_xmod FAIL
repro/mi_matrix/ast_walk_capture_prong_xmod OK
repro/mi_matrix/ast_walk_error_set_xmod OK
repro/mi_matrix/ast_walk_for_index_xmod OK
repro/mi_matrix/ast_walk_subtree_break_xmod OK
repro/mi_matrix/async_await_multi_xmod OK
repro/mi_matrix/async_await_quick_xmod OK
repro/mi_matrix/async_await_ret_xmod OK
repro/mi_matrix/async_await_xmod OK
repro/mi_matrix/async_builtin_scope_xmod OK
repro/mi_matrix/async_callgraph_xmod OK
repro/mi_matrix/async_client_cells_xmod OK
repro/mi_matrix/async_defer_error_xmod FAIL
repro/mi_matrix/async_export_fn_void_xmod OK
repro/mi_matrix/async_export_fn_xmod OK
repro/mi_matrix/async_fnptr_error_xmod FAIL
repro/mi_matrix/async_frame_args_xmod OK
repro/mi_matrix/async_frame_branch_xmod OK
repro/mi_matrix/async_frame_isparam_order_xmod OK
repro/mi_matrix/async_frame_isparam_resume_xmod OK
repro/mi_matrix/async_frame_isparam_single_xmod OK
repro/mi_matrix/async_frame_isparam_xmod OK
repro/mi_matrix/async_frame_lifetime_xmod OK
repro/mi_matrix/async_frame_structret_xmod OK
repro/mi_matrix/async_frame_temps_xmod OK
repro/mi_matrix/async_frame_xmod OK
repro/mi_matrix/async_framesize_invalid_xmod FAIL
repro/mi_matrix/async_libctx_mix_xmod OK
repro/mi_matrix/async_live_local_across_suspend_xmod OK
repro/mi_matrix/async_pool_xmod OK
repro/mi_matrix/async_resume_arg_xmod OK
repro/mi_matrix/async_state_width_xmod OK
repro/mi_matrix/async_step_midmodule_xmod OK
repro/mi_matrix/async_step_nonlast_xmod OK
repro/mi_matrix/async_suspend_store_xmod OK
repro/mi_matrix/bare_enum_literal_xmod OK
repro/mi_matrix/bare_error_union_return OK
repro/mi_matrix/bareptr_to_slice_ctx_xmod GREEN
repro/mi_matrix/builtin_bitcast_xmod OK
repro/mi_matrix/builtin_bitoffsetof_xmod OK
repro/mi_matrix/builtin_bitsizeof_xmod OK
repro/mi_matrix/builtin_fieldparentptr_xmod OK
repro/mi_matrix/builtin_offsetof_xmod OK
repro/mi_matrix/builtin_ptr_roundtrip_xmod OK
repro/mi_matrix/call_arg_type_reject_xmod GREEN
repro/mi_matrix/call_arity_reject_xmod FAIL
repro/mi_matrix/callconv_cdecl_fnptr_xmod FAIL
repro/mi_matrix/callconv_default_cdecl_xmod OK
repro/mi_matrix/callconv_explicit_cdecl_xmod OK
repro/mi_matrix/callconv_fnptr_mismatch_green_xmod GREEN
repro/mi_matrix/callconv_mixed_fnptr_typedef_xmod OK
repro/mi_matrix/callconv_nonpub_stdcall_xmod FAIL
repro/mi_matrix/callconv_stdcall_decl_xmod OK
repro/mi_matrix/callconv_stdcall_fnptr_xmod FAIL
repro/mi_matrix/callconv_stdcall_variadic_green_xmod FAIL
repro/mi_matrix/callconv_unknown_green_xmod FAIL
repro/mi_matrix/capture_prong_str_literal_xmod OK
repro/mi_matrix/catch_block_implicit_expr OK
repro/mi_matrix/catch_block_value_producing OK
repro/mi_matrix/catch_discard_struct_xmod OK
repro/mi_matrix/catch_ret_err_chain OK
repro/mi_matrix/catch_ret_err_direct OK
repro/mi_matrix/catch_ret_err_if OK
repro/mi_matrix/catch_ret_err_lzw_shape OK
repro/mi_matrix/catch_ret_err_multi OK
repro/mi_matrix/catch_ret_err_nested_fn OK
repro/mi_matrix/catch_ret_err_value_ctx OK
repro/mi_matrix/catch_return_err_tco OK
repro/mi_matrix/cleandiag_unknown_builtin_xmod GREEN
repro/mi_matrix/cleandiag_unknown_type_xmod GREEN
repro/mi_matrix/client_task_arena_xmod OK
repro/mi_matrix/client_task_wiring_xmod OK
repro/mi_matrix/comptime_array_size_gap OK
repro/mi_matrix/comptime_binop_not_folded OK
repro/mi_matrix/comptime_cast64_range_reject_xmod GREEN
repro/mi_matrix/comptime_coerce_reject_xmod GREEN
repro/mi_matrix/comptime_compare_reject_xmod FAIL
repro/mi_matrix/comptime_const_chain OK
repro/mi_matrix/comptime_constfold_reject_xmod GREEN
repro/mi_matrix/comptime_float_compare_reject_xmod FAIL
repro/mi_matrix/comptime_intcast_range_reject_xmod GREEN
repro/mi_matrix/comptime_lower_ignores_fold OK
repro/mi_matrix/comptime_neg_int OK
repro/mi_matrix/comptime_u64_fold_overflow FAIL
repro/mi_matrix/cond_assign_reject_xmod FAIL
repro/mi_matrix/cond_nonbool_reject_xmod FAIL
repro/mi_matrix/console_builtin_test OK
repro/mi_matrix/const_assign_ok_xmod OK
repro/mi_matrix/const_assign_reject_xmod FAIL
repro/mi_matrix/const_decay_reject_xmod GREEN
repro/mi_matrix/const_discard_reject_xmod GREEN
repro/mi_matrix/const_field_decay_reject_xmod GREEN
repro/mi_matrix/const_size_arith_xmod OK
repro/mi_matrix/const_size_cycle_xmod FAIL
repro/mi_matrix/const_size_inline_ctrl_xmod OK
repro/mi_matrix/const_size_local_xmod OK
repro/mi_matrix/const_size_member_xmod OK
repro/mi_matrix/const_size_unfoldable_xmod FAIL
repro/mi_matrix/copied_tag_compare_reject_xmod FAIL
repro/mi_matrix/crossmod_pubvar_xmod OK
repro/mi_matrix/defer_control_flow_reject_xmod FAIL
repro/mi_matrix/diag_control_ok_xmod OK
repro/mi_matrix/diag_excerpt_line1_xmod FAIL
repro/mi_matrix/diag_excerpt_multifile_xmod OK
repro/mi_matrix/diag_excerpt_positions_xmod FAIL
repro/mi_matrix/diag_ignored_error_xmod FAIL
repro/mi_matrix/diag_missing_return_expr_ok_xmod OK
repro/mi_matrix/diag_missing_return_xmod FAIL
repro/mi_matrix/diag_uninit_var_xmod FAIL
repro/mi_matrix/dup_optptr_field_emit OK
repro/mi_matrix/dup_val_field_emit OK
repro/mi_matrix/ec_deep_nested_xmod OK
repro/mi_matrix/ec_packed_range_xmod OK
repro/mi_matrix/ec_xmod_crossmodule_xmod OK
repro/mi_matrix/emission_array_copy_xmod OK
repro/mi_matrix/emission_assign_xmod OK
repro/mi_matrix/emission_assoc_chain_xmod OK
repro/mi_matrix/emission_capture_control_xmod FAIL
repro/mi_matrix/emission_catch_labeled_xmod OK
repro/mi_matrix/emission_conflation_control_xmod OK
repro/mi_matrix/emission_enum_ext_xmod OK
repro/mi_matrix/emission_enum_switch_xmod OK
repro/mi_matrix/emission_global_alias_xmod OK
repro/mi_matrix/emission_labeled_ctrl_xmod OK
repro/mi_matrix/emission_local_dedup_cap_xmod OK
repro/mi_matrix/emission_lower_crash_xmod OK
repro/mi_matrix/emission_mangler_collision_xmod OK
repro/mi_matrix/emission_misc_xmod FAIL
repro/mi_matrix/emission_no_member_xmod OK
repro/mi_matrix/emission_opt10_assign_xmod FAIL
repro/mi_matrix/emission_opt_fptr_wrap_xmod OK
repro/mi_matrix/emission_orelse_block_xmod OK
repro/mi_matrix/emission_orelse_control_xmod OK
repro/mi_matrix/emission_orelse_labeled_xmod OK
repro/mi_matrix/emission_orelse_xmod OK
repro/mi_matrix/emission_pal_xmod FAIL
repro/mi_matrix/emission_request_member_xmod OK
repro/mi_matrix/emission_sibling_payload_catchcap_xmod FAIL
repro/mi_matrix/emission_sibling_payload_ifcap_xmod FAIL
repro/mi_matrix/emission_sibling_payload_nestedarm_xmod FAIL
repro/mi_matrix/emission_sibling_payload_scale_xmod FAIL
repro/mi_matrix/emission_sibling_payload_xmod OK
repro/mi_matrix/emission_temp_index_drift_xmod OK
repro/mi_matrix/emission_tu_switch_xmod OK
repro/mi_matrix/emission_type_storage_control_xmod OK
repro/mi_matrix/emission_type_storage_extern_struct_xmod OK
repro/mi_matrix/emission_type_storage_extern_threealias_xmod OK
repro/mi_matrix/emission_type_storage_extern_xmod OK
repro/mi_matrix/emission_void_call_control_xmod OK
repro/mi_matrix/emission_void_call_xmod OK
repro/mi_matrix/emission_void_temp_control_xmod OK
repro/mi_matrix/emission_void_temp_enum_xmod OK
repro/mi_matrix/emission_void_temp_multi_xmod OK
repro/mi_matrix/emission_void_temp_payload_xmod OK
repro/mi_matrix/emission_void_temp_scale_xmod OK
repro/mi_matrix/emission_void_temp_xmod FAIL
repro/mi_matrix/emission_zT_undeclared_xmod OK
repro/mi_matrix/empty_named_struct_field_xmod OK
repro/mi_matrix/empty_named_struct_xmod OK
repro/mi_matrix/enum_init_bitnot_reject_xmod FAIL
repro/mi_matrix/enum_init_builtin_reject_xmod FAIL
repro/mi_matrix/enum_init_cast64_range_reject_xmod FAIL
repro/mi_matrix/enum_init_cast_noninteger_reject_xmod FAIL
repro/mi_matrix/enum_init_cast_range_reject_xmod FAIL
repro/mi_matrix/enum_init_duplicate_xmod FAIL
repro/mi_matrix/enum_init_inline_duplicate_reject_xmod FAIL
repro/mi_matrix/enum_init_inline_nonconstant_reject_xmod FAIL
repro/mi_matrix/enum_init_local_duplicate_reject_xmod FAIL
repro/mi_matrix/enum_init_memberref_reject_xmod FAIL
repro/mi_matrix/enum_init_not_constant_xmod FAIL
repro/mi_matrix/enum_init_overflow_expr_xmod GREEN
repro/mi_matrix/enum_init_selfcycle_xmod FAIL
repro/mi_matrix/enum_literal_assign OK
repro/mi_matrix/enum_subbyte_backing_xmod OK
repro/mi_matrix/error_literal_return OK
repro/mi_matrix/error_set_unknown_member FAIL
repro/mi_matrix/error_union_capture_reject_xmod FAIL
repro/mi_matrix/errset_cross_set_compare OK
repro/mi_matrix/errunion_payload_callarg_xmod OK
repro/mi_matrix/errunion_payload_field_xmod OK
repro/mi_matrix/errunion_payload_str_xmod OK
repro/mi_matrix/errunion_payload_varinit_xmod OK
repro/mi_matrix/eu_assign_compat OK
repro/mi_matrix/eu_assign_from_payload OK
repro/mi_matrix/eu_assign_incompat_errorset GREEN
repro/mi_matrix/eu_assign_incompat_payload GREEN
repro/mi_matrix/eu_err_assign OK
repro/mi_matrix/eu_err_call_arg OK
repro/mi_matrix/eu_err_catch OK
repro/mi_matrix/eu_err_if_expr OK
repro/mi_matrix/eu_err_ret OK
repro/mi_matrix/eu_err_return OK
repro/mi_matrix/eu_err_switch OK
repro/mi_matrix/eu_err_var_decl OK
repro/mi_matrix/eu_optional_value OK
repro/mi_matrix/eu_payload_diff_reject_xmod GREEN
repro/mi_matrix/eu_val_assign OK
repro/mi_matrix/eu_val_call_arg OK
repro/mi_matrix/eu_val_catch OK
repro/mi_matrix/eu_val_if_expr OK
repro/mi_matrix/eu_val_return OK
repro/mi_matrix/eu_val_switch OK
repro/mi_matrix/eu_val_var_decl OK
repro/mi_matrix/eu_value_ret OK
repro/mi_matrix/eunum_err_assign OK
repro/mi_matrix/eunum_err_call_arg OK
repro/mi_matrix/eunum_err_catch OK
repro/mi_matrix/eunum_err_if_expr OK
repro/mi_matrix/eunum_err_return OK
repro/mi_matrix/eunum_err_switch OK
repro/mi_matrix/eunum_err_var_decl OK
repro/mi_matrix/eunum_val_assign OK
repro/mi_matrix/eunum_val_call_arg OK
repro/mi_matrix/eunum_val_catch OK
repro/mi_matrix/eunum_val_if_expr OK
repro/mi_matrix/eunum_val_return OK
repro/mi_matrix/eunum_val_switch OK
repro/mi_matrix/eunum_val_var_decl OK
repro/mi_matrix/euopt_err_assign OK
repro/mi_matrix/euopt_err_call_arg OK
repro/mi_matrix/euopt_err_catch OK
repro/mi_matrix/euopt_err_if_expr OK
repro/mi_matrix/euopt_err_return OK
repro/mi_matrix/euopt_err_switch OK
repro/mi_matrix/euopt_err_var_decl OK
repro/mi_matrix/euopt_val_assign OK
repro/mi_matrix/euopt_val_call_arg OK
repro/mi_matrix/euopt_val_catch OK
repro/mi_matrix/euopt_val_if_expr OK
repro/mi_matrix/euopt_val_return OK
repro/mi_matrix/euopt_val_switch OK
repro/mi_matrix/euopt_val_var_decl OK
repro/mi_matrix/euoptptr_err_assign OK
repro/mi_matrix/euoptptr_err_call_arg OK
repro/mi_matrix/euoptptr_err_catch OK
repro/mi_matrix/euoptptr_err_if_expr OK
repro/mi_matrix/euoptptr_err_return OK
repro/mi_matrix/euoptptr_err_switch OK
repro/mi_matrix/euoptptr_err_var_decl OK
repro/mi_matrix/euoptptr_val_assign OK
repro/mi_matrix/euoptptr_val_call_arg OK
repro/mi_matrix/euoptptr_val_catch OK
repro/mi_matrix/euoptptr_val_if_expr OK
repro/mi_matrix/euoptptr_val_orelse OK
repro/mi_matrix/euoptptr_val_return OK
repro/mi_matrix/euoptptr_val_switch OK
repro/mi_matrix/euoptptr_val_var_decl OK
repro/mi_matrix/euvoid_err_call_arg OK
repro/mi_matrix/euvoid_err_return OK
repro/mi_matrix/euvoid_err_var_decl OK
repro/mi_matrix/euvoid_val_catch GREEN
repro/mi_matrix/export_fn_xmod OK
repro/mi_matrix/export_var_xmod OK
repro/mi_matrix/extern_fn_eu_return OK
repro/mi_matrix/extern_fn_opt_return OK
repro/mi_matrix/extern_fn_opt_return_cross OK
repro/mi_matrix/extern_runtime_symbol_xmod OK
repro/mi_matrix/f32_narrow_reject_xmod GREEN
repro/mi_matrix/f64_literal_precision_xmod OK
repro/mi_matrix/field_access_optional GREEN
repro/mi_matrix/field_store_continue_nested_xmod OK
repro/mi_matrix/field_store_continue_xmod OK
repro/mi_matrix/field_store_drop OK
repro/mi_matrix/file_const_single OK
repro/mi_matrix/fn_ptr_local_bare OK
repro/mi_matrix/fn_ptr_signature_ok_xmod OK
repro/mi_matrix/fn_ptr_signature_reject_xmod GREEN
repro/mi_matrix/fn_ptr_struct_field OK
repro/mi_matrix/fn_varargs_body OK
repro/mi_matrix/fn_varargs_unsupported OK
repro/mi_matrix/for_index_range_reject_xmod GREEN
repro/mi_matrix/for_range_end_len_xmod OK
repro/mi_matrix/func_ptr_return_type OK
repro/mi_matrix/global_null_init_xmod OK
repro/mi_matrix/global_struct_array_store_xmod OK
repro/mi_matrix/ice_literal_overflow FAIL
repro/mi_matrix/if_capture_else_reject_xmod FAIL
repro/mi_matrix/if_expr_str_literal_xmod OK
repro/mi_matrix/if_expr_unreachable_xmod OK
repro/mi_matrix/if_noelse_reject_xmod FAIL
repro/mi_matrix/if_unannotated_str_xmod OK
repro/mi_matrix/if_unannotated_str_xmod_xmod OK
repro/mi_matrix/import_extern_c OK
repro/mi_matrix/index_oob_reject_xmod FAIL
repro/mi_matrix/inferred_errorset_fnptr OK
repro/mi_matrix/inferred_errorset_xmod OK
repro/mi_matrix/int_arbitrary_width_xmod OK
repro/mi_matrix/intcast_char_literal OK
repro/mi_matrix/intcast_range_check OK
repro/mi_matrix/intwidth_cast_xmod GREEN
repro/mi_matrix/intwidth_full_xmod OK
repro/mi_matrix/intwidth_introspect_xmod OK
repro/mi_matrix/intwidth_sign_extend_xmod OK
repro/mi_matrix/intwidth_wrap_xmod OK
repro/mi_matrix/io_builtin_test OK
repro/mi_matrix/labeled_stmt_unhandled OK
repro/mi_matrix/len_array_field_reject_xmod GREEN
repro/mi_matrix/len_array_field_xmod OK
repro/mi_matrix/lexer_float_exponent_xmod OK
repro/mi_matrix/lirrepro_global_reloc_call_xmod OK
repro/mi_matrix/lirrepro_global_reloc_store_xmod OK
repro/mi_matrix/lirrepro_global_reloc_xmod_xmod OK
repro/mi_matrix/lit64_decimal_xmod OK
repro/mi_matrix/load_global_array_copy OK
repro/mi_matrix/local_type_alias_compound_reject_xmod GREEN
repro/mi_matrix/local_type_alias_reject_xmod GREEN
repro/mi_matrix/local_type_fieldcap_reject_xmod GREEN
repro/mi_matrix/local_type_var_container_reject_xmod GREEN
repro/mi_matrix/lzw_builtin_call_crash OK
repro/mi_matrix/lzw_cross_module_error_set OK
repro/mi_matrix/lzw_error_set_member_comparison OK
repro/mi_matrix/lzw_error_set_typedef OK
repro/mi_matrix/lzw_eu_return_mismatch OK
repro/mi_matrix/lzw_local_var_undeclared OK
repro/mi_matrix/m4_array_to_slice_len_xmod OK
repro/mi_matrix/manyptr_len_range_reject_xmod GREEN
repro/mi_matrix/manyptr_len_reject_xmod GREEN
repro/mi_matrix/method_syntax_reject_xmod FAIL
repro/mi_matrix/mi_eu_err OK
repro/mi_matrix/mi_eu_opt_val OK
repro/mi_matrix/mod_silent_drop_xmod OK
repro/mi_matrix/module_as_value OK
repro/mi_matrix/module_const_fn_call OK
repro/mi_matrix/module_pub_var_int OK
repro/mi_matrix/module_pub_var_struct OK
repro/mi_matrix/module_value_addr_global_xmod OK
repro/mi_matrix/module_value_alias2alias_xmod OK
repro/mi_matrix/module_value_alias3_xmod OK
repro/mi_matrix/module_value_arraysize_xmod OK
repro/mi_matrix/module_value_direct1_xmod OK
repro/mi_matrix/module_value_enum_member_xmod OK
repro/mi_matrix/module_value_fncall_xmod OK
repro/mi_matrix/module_value_local_xmod OK
repro/mi_matrix/module_value_pos_xmod OK
repro/mi_matrix/module_value_positions_xmod OK
repro/mi_matrix/module_value_scalar_xmod OK
repro/mi_matrix/module_value_types_xmod OK
repro/mi_matrix/module_value_var_xmod OK
repro/mi_matrix/module_value_varstore_xmod OK
repro/mi_matrix/module_var_mutable OK
repro/mi_matrix/multiarray_field_store_xmod OK
repro/mi_matrix/multiarray_for_iter_3d_xmod OK
repro/mi_matrix/multiarray_for_iter_flat_control_xmod OK
repro/mi_matrix/multiarray_for_iter_scalar_control_xmod OK
repro/mi_matrix/multiarray_for_iter_value_xmod OK
repro/mi_matrix/multiarray_for_iter_xmod OK
repro/mi_matrix/multiarray_index_3d_xmod OK
repro/mi_matrix/multiarray_index_const_xmod OK
repro/mi_matrix/multiarray_index_flat_control_xmod OK
repro/mi_matrix/multiarray_index_local_xmod OK
repro/mi_matrix/multiarray_index_struct_control_xmod OK
repro/mi_matrix/multiarray_index_xmod OK
repro/mi_matrix/multiarray_literal_init_xmod OK
repro/mi_matrix/multiarray_row_store_xmod OK
repro/mi_matrix/nested_field_store_xmod OK
repro/mi_matrix/nested_field_store_xmod2 OK
repro/mi_matrix/nested_loop_label_xmod OK
repro/mi_matrix/nested_mod_deep_chain_reject_xmod FAIL
repro/mi_matrix/nested_mod_undef_member_reject_xmod FAIL
repro/mi_matrix/nested_switch_str_literal_xmod OK
repro/mi_matrix/net_bind_startup_xmod OK
repro/mi_matrix/net_builtin_test GREEN
repro/mi_matrix/nonagg_member_reject_xmod FAIL
repro/mi_matrix/nonfn_flat_member_call_reject_xmod FAIL
repro/mi_matrix/nonfn_local_call_reject_xmod FAIL
repro/mi_matrix/nonfn_member_call_args_reject_xmod FAIL
repro/mi_matrix/nonfn_member_call_reject_xmod FAIL
repro/mi_matrix/nonliteral_ptr_to_slice_xmod GREEN
repro/mi_matrix/noreturn_assign_rhs_xmod OK
repro/mi_matrix/noreturn_call_arg_xmod OK
repro/mi_matrix/noreturn_if_init_block_xmod OK
repro/mi_matrix/noreturn_if_init_xmod OK
repro/mi_matrix/noreturn_nested_xmod OK
repro/mi_matrix/noreturn_opt_ctx_xmod OK
repro/mi_matrix/noreturn_switch_init_xmod OK
repro/mi_matrix/null_opt_manyptr_arg_xmod OK
repro/mi_matrix/opt_extern_ptr_file OK
repro/mi_matrix/opt_fnptr_extern_xmod OK
repro/mi_matrix/opt_null_assign OK
repro/mi_matrix/opt_null_call_arg OK
repro/mi_matrix/opt_null_if_expr OK
repro/mi_matrix/opt_null_return OK
repro/mi_matrix/opt_null_switch OK
repro/mi_matrix/opt_null_var_decl OK
repro/mi_matrix/opt_payload_callarg_xmod OK
repro/mi_matrix/opt_payload_field_xmod OK
repro/mi_matrix/opt_payload_str_xmod OK
repro/mi_matrix/opt_payload_varinit_xmod OK
repro/mi_matrix/opt_slice_null OK
repro/mi_matrix/opt_slice_null_multi OK
repro/mi_matrix/opt_slice_null_return OK
repro/mi_matrix/opt_slice_null_xmod OK
repro/mi_matrix/opt_val_assign OK
repro/mi_matrix/opt_val_call_arg OK
repro/mi_matrix/opt_val_if_expr OK
repro/mi_matrix/opt_val_return OK
repro/mi_matrix/opt_val_switch OK
repro/mi_matrix/opt_val_var_decl OK
repro/mi_matrix/opt_value_decl OK
repro/mi_matrix/opt_void_extern_xmod OK
repro/mi_matrix/opteu_err_catch OK
repro/mi_matrix/opteu_err_if_expr OK
repro/mi_matrix/opteu_err_switch OK
repro/mi_matrix/opteu_null_assign OK
repro/mi_matrix/opteu_null_call_arg OK
repro/mi_matrix/opteu_null_if_expr OK
repro/mi_matrix/opteu_null_orelse OK
repro/mi_matrix/opteu_null_return OK
repro/mi_matrix/opteu_null_switch OK
repro/mi_matrix/opteu_null_var_decl OK
repro/mi_matrix/opteu_val_assign OK
repro/mi_matrix/opteu_val_call_arg OK
repro/mi_matrix/opteu_val_catch OK
repro/mi_matrix/opteu_val_orelse OK
repro/mi_matrix/opteu_val_return OK
repro/mi_matrix/opteu_val_switch OK
repro/mi_matrix/opteu_val_var_decl OK
repro/mi_matrix/optional_void_present_xmod OK
repro/mi_matrix/optnum_null_assign OK
repro/mi_matrix/optnum_null_call_arg OK
repro/mi_matrix/optnum_null_if_expr OK
repro/mi_matrix/optnum_null_orelse OK
repro/mi_matrix/optnum_null_return OK
repro/mi_matrix/optnum_null_switch OK
repro/mi_matrix/optnum_null_var_decl OK
repro/mi_matrix/optnum_val_assign OK
repro/mi_matrix/optnum_val_call_arg OK
repro/mi_matrix/optnum_val_if_expr OK
repro/mi_matrix/optnum_val_orelse OK
repro/mi_matrix/optnum_val_return OK
repro/mi_matrix/optnum_val_switch OK
repro/mi_matrix/optnum_val_var_decl OK
repro/mi_matrix/optopt_null_assign OK
repro/mi_matrix/optopt_null_call_arg OK
repro/mi_matrix/optopt_null_if_expr OK
repro/mi_matrix/optopt_null_orelse OK
repro/mi_matrix/optopt_null_return OK
repro/mi_matrix/optopt_null_switch OK
repro/mi_matrix/optopt_null_var_decl OK
repro/mi_matrix/optopt_val_assign OK
repro/mi_matrix/optopt_val_call_arg OK
repro/mi_matrix/optopt_val_if_expr OK
repro/mi_matrix/optopt_val_orelse OK
repro/mi_matrix/optopt_val_return OK
repro/mi_matrix/optopt_val_switch OK
repro/mi_matrix/optopt_val_var_decl OK
repro/mi_matrix/optptr_null_assign OK
repro/mi_matrix/optptr_null_call_arg OK
repro/mi_matrix/optptr_null_if_expr OK
repro/mi_matrix/optptr_null_orelse OK
repro/mi_matrix/optptr_null_return OK
repro/mi_matrix/optptr_null_switch OK
repro/mi_matrix/optptr_null_var_decl OK
repro/mi_matrix/optptr_val_assign OK
repro/mi_matrix/optptr_val_call_arg OK
repro/mi_matrix/optptr_val_if_expr OK
repro/mi_matrix/optptr_val_orelse OK
repro/mi_matrix/optptr_val_return OK
repro/mi_matrix/optptr_val_switch OK
repro/mi_matrix/optptr_val_var_decl OK
repro/mi_matrix/optstar_void_orelse OK
repro/mi_matrix/orelse_empty_block_reject_xmod FAIL
repro/mi_matrix/orelse_error_union_xmod FAIL
repro/mi_matrix/orelse_optional_control_xmod OK
repro/mi_matrix/orelse_requires_optional_xmod FAIL
repro/mi_matrix/orelse_ret_err OK
repro/mi_matrix/orelse_ret_err_void OK
repro/mi_matrix/orelse_void OK
repro/mi_matrix/packed_array_global_xmod OK
repro/mi_matrix/packed_byvalue_module_xmod OK
repro/mi_matrix/packed_enum_field_xmod OK
repro/mi_matrix/packed_l0_flags_xmod OK
repro/mi_matrix/packed_l1_mix_xmod OK
repro/mi_matrix/packed_l2_straddle_xmod OK
repro/mi_matrix/packed_l3_nested_xmod OK
repro/mi_matrix/packed_nested_whole_chain_reject_xmod GREEN
repro/mi_matrix/packed_nested_whole_depth_ok_xmod OK
repro/mi_matrix/packed_nested_whole_depth_reject_xmod GREEN
repro/mi_matrix/packed_nested_wholeliteral_xmod OK
repro/mi_matrix/packed_union_struct_member_xmod OK
repro/mi_matrix/packed_union_struct_wholemember_xmod OK
repro/mi_matrix/packed_union_xmod OK
repro/mi_matrix/parsergap_array_type_xmod OK
repro/mi_matrix/parsergap_discard_if_xmod OK
repro/mi_matrix/parsergap_many_ptr_xmod OK
repro/mi_matrix/parsergap_selfblok_xmod FAIL
repro/mi_matrix/parsergap_shadow_local_xmod FAIL
repro/mi_matrix/parsergap_slice_expr_xmod GREEN
repro/mi_matrix/parsergap_specifier_xmod OK
repro/mi_matrix/parsergap_strict_comma_xmod FAIL
repro/mi_matrix/parsergap_switch_comma_xmod OK
repro/mi_matrix/parsergap_trailing_comma_xmod OK
repro/mi_matrix/parsergap_value_if_xmod OK
repro/mi_matrix/parsergap_value_if_xmod_cross OK
repro/mi_matrix/parsergap_wrap_arith_xmod OK
repro/mi_matrix/parsergap_zeroarr_slice_xmod OK
repro/mi_matrix/pathnorm_dup_xmod OK
repro/mi_matrix/plat_stubs_missing_xmod OK
repro/mi_matrix/print_aggregate_noprinter_reject_xmod FAIL
repro/mi_matrix/print_fmt_noprinter_reject_xmod FAIL
repro/mi_matrix/print_fmt_ptrarray_guard_reject_xmod FAIL
repro/mi_matrix/print_fmt_type_reject_xmod FAIL
repro/mi_matrix/print_nontuple_container_reject_xmod FAIL
repro/mi_matrix/print_ptr_name_cap_reject_xmod FAIL
repro/mi_matrix/print_recursive_aggregate_reject_xmod FAIL
repro/mi_matrix/prune_globaltype_owner_xmod OK
repro/mi_matrix/ptr_scalar_to_manyptr_xmod GREEN
repro/mi_matrix/ptr_slice_reject_xmod GREEN
repro/mi_matrix/ptr_to_array_index_xmod GREEN
repro/mi_matrix/ptr_to_int_void_xmod OK
repro/mi_matrix/ptrcast_arity_xmod FAIL
repro/mi_matrix/ptrcast_slice_field_type OK
repro/mi_matrix/ptrcast_slice_field_void OK
repro/mi_matrix/ptrcast_slice_field_xmod OK
repro/mi_matrix/ptroint_arena_offset OK
repro/mi_matrix/pub_visibility_fold_reject_xmod FAIL
repro/mi_matrix/pub_visibility_reject_xmod FAIL
repro/mi_matrix/r_fallback_constalias OK
repro/mi_matrix/r_fallback_constalias_prepass OK
repro/mi_matrix/r_fallback_fnret OK
repro/mi_matrix/r_fallback_fnret_ctl OK
repro/mi_matrix/relational_enum_overaccept_xmod OK
repro/mi_matrix/safe_bounds_field_xmod OK
repro/mi_matrix/safe_bounds_inbounds_xmod OK
repro/mi_matrix/safe_bounds_read_xmod OK
repro/mi_matrix/safe_bounds_slice_xmod OK
repro/mi_matrix/safe_bounds_write_xmod OK
repro/mi_matrix/safe_cast_overflow_xmod OK
repro/mi_matrix/safe_compound_div_assign_xmod OK
repro/mi_matrix/safe_compound_mod_assign_xmod OK
repro/mi_matrix/safe_compound_shl_assign_xmod OK
repro/mi_matrix/safe_compound_shr_assign_xmod OK
repro/mi_matrix/safe_div_min_i64_neg1_xmod OK
repro/mi_matrix/safe_div_min_neg1_xmod OK
repro/mi_matrix/safe_div_zero_xmod OK
repro/mi_matrix/safe_divmod_control_xmod OK
repro/mi_matrix/safe_int_add_overflow_u_xmod OK
repro/mi_matrix/safe_int_add_overflow_xmod OK
repro/mi_matrix/safe_int_compound_add_loop_xmod OK
repro/mi_matrix/safe_int_compound_add_overflow_xmod OK
repro/mi_matrix/safe_int_lit_shl_count_xmod OK
repro/mi_matrix/safe_int_lit_shl_runtime_xmod OK
repro/mi_matrix/safe_int_lit_shl_value_xmod OK
repro/mi_matrix/safe_int_mixed_sign_xmod OK
repro/mi_matrix/safe_int_mul_overflow_u_xmod OK
repro/mi_matrix/safe_int_mul_overflow_xmod OK
repro/mi_matrix/safe_int_neg_overflow_xmod OK
repro/mi_matrix/safe_int_neg_unsigned_xmod OK
repro/mi_matrix/safe_int_shl_assign_overflow_xmod OK
repro/mi_matrix/safe_int_shl_overflow_u_xmod OK
repro/mi_matrix/safe_int_shl_overflow_xmod OK
repro/mi_matrix/safe_int_shortcircuit_xmod OK
repro/mi_matrix/safe_int_sub_overflow_u_xmod OK
repro/mi_matrix/safe_int_sub_overflow_xmod OK
repro/mi_matrix/safe_intcast_control_xmod OK
repro/mi_matrix/safe_intcast_i64_u64_xmod OK
repro/mi_matrix/safe_intcast_subword_xmod OK
repro/mi_matrix/safe_intcast_u64_i64_xmod OK
repro/mi_matrix/safe_intcast_widen_sign_xmod GREEN
repro/mi_matrix/safe_mod_min_i64_neg1_xmod OK
repro/mi_matrix/safe_mod_min_neg1_xmod OK
repro/mi_matrix/safe_null_unwrap_xmod OK
repro/mi_matrix/safe_ovf_control_xmod OK
repro/mi_matrix/safe_ovf_i64_add_xmod OK
repro/mi_matrix/safe_ovf_i64_neg_xmod OK
repro/mi_matrix/safe_ovf_i64_shl_xmod OK
repro/mi_matrix/safe_ovf_u64_mul_xmod OK
repro/mi_matrix/safe_ovr_mixsign_boundary_xmod OK
repro/mi_matrix/safe_shift_count_xmod OK
repro/mi_matrix/safe_undefined_agg_xmod OK
repro/mi_matrix/safe_undefined_direct_xmod OK
repro/mi_matrix/safe_undefined_poison_xmod OK
repro/mi_matrix/safe_unwrap_guard_xmod OK
repro/mi_matrix/sat_i64_mul OK
repro/mi_matrix/sat_signed_battery OK
repro/mi_matrix/self_embed_optional_cycle FAIL
repro/mi_matrix/shadow_ok_xmod OK
repro/mi_matrix/shadow_reject_xmod FAIL
repro/mi_matrix/shadow_related_span_xmod FAIL
repro/mi_matrix/sig_known_type_ok_xmod OK
repro/mi_matrix/sig_unknown_type_reject_xmod FAIL
repro/mi_matrix/sizeof_struct_union_xmod OK
repro/mi_matrix/slice_index_field_store_oob_xmod OK
repro/mi_matrix/slice_index_field_store_xmod OK
repro/mi_matrix/slice_of_array_xmod OK
repro/mi_matrix/slice_of_slice_xmod OK
repro/mi_matrix/slice_range_oob_reject_xmod FAIL
repro/mi_matrix/slice_runtime_end_xmod OK
repro/mi_matrix/std_import_bare_xmod OK
repro/mi_matrix/stdlib_analyzer_labeled_xmod OK
repro/mi_matrix/stdlib_analyzer_switch_merge_xmod OK
repro/mi_matrix/stdlib_arena_xmod OK
repro/mi_matrix/stdlib_array_size_builtin_xmod OK
repro/mi_matrix/stdlib_array_size_struct_introspection_xmod OK
repro/mi_matrix/stdlib_as_float_guard_xmod OK
repro/mi_matrix/stdlib_as_neg_operand_xmod OK
repro/mi_matrix/stdlib_async_addtask_restart_cancel_xmod OK
repro/mi_matrix/stdlib_async_addtask_reuse_xmod OK
repro/mi_matrix/stdlib_async_addtask_single_xmod OK
repro/mi_matrix/stdlib_async_await_nonctx_xmod OK
repro/mi_matrix/stdlib_async_await_xmod OK
repro/mi_matrix/stdlib_async_blocking_tick_two_xmod OK
repro/mi_matrix/stdlib_async_blocking_tick_xmod OK
repro/mi_matrix/stdlib_async_cancelall_xmod OK
repro/mi_matrix/stdlib_async_f64align_xmod OK
repro/mi_matrix/stdlib_async_handle_xmod OK
repro/mi_matrix/stdlib_async_headerexact_xmod OK
repro/mi_matrix/stdlib_async_oom_xmod OK
repro/mi_matrix/stdlib_async_pool_xmod OK
repro/mi_matrix/stdlib_async_removetask_noop_xmod OK
repro/mi_matrix/stdlib_async_removetask_xmod OK
repro/mi_matrix/stdlib_async_sched_xmod OK
repro/mi_matrix/stdlib_async_suspenduntil_false_xmod OK
repro/mi_matrix/stdlib_async_suspenduntil_stress_xmod OK
repro/mi_matrix/stdlib_async_suspenduntil_xmod OK
repro/mi_matrix/stdlib_async_waitfor_cancel_xmod OK
repro/mi_matrix/stdlib_async_waitfor_dep_xmod OK
repro/mi_matrix/stdlib_async_waitfor_helper_xmod OK
repro/mi_matrix/stdlib_async_waitfor_oom_xmod OK
repro/mi_matrix/stdlib_async_waitfor_settled_xmod OK
repro/mi_matrix/stdlib_async_waitfor_unregistered_xmod OK
repro/mi_matrix/stdlib_async_waitfor_xmod OK
repro/mi_matrix/stdlib_base64_decode_xmod OK
repro/mi_matrix/stdlib_base64_decodedlen_xmod OK
repro/mi_matrix/stdlib_base64_encode_xmod OK
repro/mi_matrix/stdlib_base64_encodedlen_xmod OK
repro/mi_matrix/stdlib_base64_invalid_xmod OK
repro/mi_matrix/stdlib_base64_oom_xmod OK
repro/mi_matrix/stdlib_base64_roundtrip_xmod OK
repro/mi_matrix/stdlib_base64_stress_xmod OK
repro/mi_matrix/stdlib_bencode_decode_xmod OK
repro/mi_matrix/stdlib_bencode_dictspan_xmod OK
repro/mi_matrix/stdlib_bencode_encode_xmod OK
repro/mi_matrix/stdlib_bencode_limits_xmod OK
repro/mi_matrix/stdlib_bencode_oom_xmod OK
repro/mi_matrix/stdlib_bits_extract_trap_xmod OK
repro/mi_matrix/stdlib_bits_insert_trap_xmod OK
repro/mi_matrix/stdlib_bits_stress_xmod OK
repro/mi_matrix/stdlib_bits_table_xmod OK
repro/mi_matrix/stdlib_bool_size_align_xmod OK
repro/mi_matrix/stdlib_buf_clear_xmod OK
repro/mi_matrix/stdlib_buf_endian_xmod OK
repro/mi_matrix/stdlib_buf_growth_xmod OK
repro/mi_matrix/stdlib_buf_oom_xmod OK
repro/mi_matrix/stdlib_buf_stress_xmod OK
repro/mi_matrix/stdlib_call_arity_types_ok_xmod OK
repro/mi_matrix/stdlib_capture_sibling_reuse_xmod OK
repro/mi_matrix/stdlib_comptime_bigint_arith_xmod OK
repro/mi_matrix/stdlib_comptime_cast64_range_xmod OK
repro/mi_matrix/stdlib_comptime_coerce_typed_slots_xmod OK
repro/mi_matrix/stdlib_comptime_compare_xmod OK
repro/mi_matrix/stdlib_comptime_constfold_exact_xmod OK
repro/mi_matrix/stdlib_comptime_float_compare_xmod OK
repro/mi_matrix/stdlib_comptime_floatcast_fold_xmod OK
repro/mi_matrix/stdlib_comptime_index_ok_xmod OK
repro/mi_matrix/stdlib_comptime_intcast_nonint_mask_xmod OK
repro/mi_matrix/stdlib_comptime_inttofloat_as_xmod OK
repro/mi_matrix/stdlib_comptime_noreturn_if_xmod OK
repro/mi_matrix/stdlib_comptime_true_if_xmod OK
repro/mi_matrix/stdlib_cond_ok_xmod OK
repro/mi_matrix/stdlib_const_decay_ok_xmod OK
repro/mi_matrix/stdlib_const_field_decay_ok_xmod OK
repro/mi_matrix/stdlib_crypto_crc32_xmod OK
repro/mi_matrix/stdlib_crypto_md5_xmod OK
repro/mi_matrix/stdlib_crypto_modpow_xmod OK
repro/mi_matrix/stdlib_crypto_rc4_xmod OK
repro/mi_matrix/stdlib_crypto_sha1_xmod OK
repro/mi_matrix/stdlib_crypto_sha256_xmod OK
repro/mi_matrix/stdlib_crypto_stress_xmod OK
repro/mi_matrix/stdlib_debug_backtrace_xmod OK
repro/mi_matrix/stdlib_debug_cleartrap_xmod OK
repro/mi_matrix/stdlib_debug_coredump_xmod OK
repro/mi_matrix/stdlib_debug_defaulttrap_xmod OK
repro/mi_matrix/stdlib_debug_stress_xmod OK
repro/mi_matrix/stdlib_debug_trap_xmod OK
repro/mi_matrix/stdlib_debug_xmod OK
repro/mi_matrix/stdlib_default_lib_lookup_xmod OK
repro/mi_matrix/stdlib_defer_control_flow_xmod OK
repro/mi_matrix/stdlib_defer_queue_reset_xmod OK
repro/mi_matrix/stdlib_defer_switch_block_xmod OK
repro/mi_matrix/stdlib_enum_init_expr_xmod OK
repro/mi_matrix/stdlib_errdefer_dyn_xmod OK
repro/mi_matrix/stdlib_errdefer_xmod OK
repro/mi_matrix/stdlib_errset_capture_qualified_xmod OK
repro/mi_matrix/stdlib_eu_samepayload_xmod OK
repro/mi_matrix/stdlib_f32_narrow_ok_xmod OK
repro/mi_matrix/stdlib_f32_print_xmod OK
repro/mi_matrix/stdlib_file_close_xmod OK
repro/mi_matrix/stdlib_file_exists_xmod OK
repro/mi_matrix/stdlib_file_flush_xmod OK
repro/mi_matrix/stdlib_file_mtime_xmod OK
repro/mi_matrix/stdlib_file_open_xmod OK
repro/mi_matrix/stdlib_file_openerr_xmod OK
repro/mi_matrix/stdlib_file_read_xmod OK
repro/mi_matrix/stdlib_file_readall_xmod OK
repro/mi_matrix/stdlib_file_remove_xmod OK
repro/mi_matrix/stdlib_file_rename_xmod OK
repro/mi_matrix/stdlib_file_seek64_xmod OK
repro/mi_matrix/stdlib_file_seek_xmod OK
repro/mi_matrix/stdlib_file_size_xmod OK
repro/mi_matrix/stdlib_file_stress_xmod OK
repro/mi_matrix/stdlib_file_write_xmod OK
repro/mi_matrix/stdlib_file_writeall_xmod OK
repro/mi_matrix/stdlib_fileio_xmod OK
repro/mi_matrix/stdlib_floatcast_xmod OK
repro/mi_matrix/stdlib_for_continue_xmod OK
repro/mi_matrix/stdlib_for_index_range_xmod OK
repro/mi_matrix/stdlib_heap_init_xmod OK
repro/mi_matrix/stdlib_heap_len_xmod OK
repro/mi_matrix/stdlib_heap_oom_xmod OK
repro/mi_matrix/stdlib_heap_peek_xmod OK
repro/mi_matrix/stdlib_heap_pop_xmod OK
repro/mi_matrix/stdlib_heap_push_xmod OK
repro/mi_matrix/stdlib_heap_stress_xmod OK
repro/mi_matrix/stdlib_heap_tie_xmod OK
repro/mi_matrix/stdlib_hex_decode_xmod OK
repro/mi_matrix/stdlib_hex_encodelower_xmod OK
repro/mi_matrix/stdlib_hex_encodeupper_xmod OK
repro/mi_matrix/stdlib_hex_oom_xmod OK
repro/mi_matrix/stdlib_hex_roundtrip_xmod OK
repro/mi_matrix/stdlib_hex_stress_xmod OK
repro/mi_matrix/stdlib_http_badurl_xmod OK
repro/mi_matrix/stdlib_http_parseresponse_chunked_reject_xmod OK
repro/mi_matrix/stdlib_http_parseresponse_xmod OK
repro/mi_matrix/stdlib_http_parseurl_xmod OK
repro/mi_matrix/stdlib_http_percentencode_xmod OK
repro/mi_matrix/stdlib_intcast_loop_capture_xmod OK
repro/mi_matrix/stdlib_intcast_range_xmod OK
repro/mi_matrix/stdlib_intcast_widen_sign_runtime_xmod OK
repro/mi_matrix/stdlib_layout_align8_xmod OK
repro/mi_matrix/stdlib_local_type_emission_xmod OK
repro/mi_matrix/stdlib_local_type_fieldcap_xmod OK
repro/mi_matrix/stdlib_map_determinism_xmod OK
repro/mi_matrix/stdlib_map_map32ptr_xmod OK
repro/mi_matrix/stdlib_map_map32x32_xmod OK
repro/mi_matrix/stdlib_map_mapstrptr_xmod OK
repro/mi_matrix/stdlib_map_oom_xmod OK
repro/mi_matrix/stdlib_map_stress_xmod OK
repro/mi_matrix/stdlib_math_f64_xmod OK
repro/mi_matrix/stdlib_math_xmod OK
repro/mi_matrix/stdlib_mem_xmod OK
repro/mi_matrix/stdlib_method_syntax_ok_xmod OK
repro/mi_matrix/stdlib_nested_mod_call_xmod OK
repro/mi_matrix/stdlib_net_connectto_xmod OK
repro/mi_matrix/stdlib_net_nonblocking_stress_xmod OK
repro/mi_matrix/stdlib_net_recvnonblocking_close_xmod OK
repro/mi_matrix/stdlib_net_recvnonblocking_wouldblock_xmod OK
repro/mi_matrix/stdlib_net_recvnonblocking_xmod OK
repro/mi_matrix/stdlib_net_resolve_xmod OK
repro/mi_matrix/stdlib_net_sendnonblocking_xmod OK
repro/mi_matrix/stdlib_net_setnonblocking_xmod OK
repro/mi_matrix/stdlib_net_shutdown_xmod OK
repro/mi_matrix/stdlib_net_soerror_xmod OK
repro/mi_matrix/stdlib_net_udp_bind_xmod OK
repro/mi_matrix/stdlib_net_udp_loopback_xmod OK
repro/mi_matrix/stdlib_net_udp_recvfrom_xmod OK
repro/mi_matrix/stdlib_net_udp_sendto_xmod OK
repro/mi_matrix/stdlib_net_udp_settimeout_xmod OK
repro/mi_matrix/stdlib_net_udp_stress_xmod OK
repro/mi_matrix/stdlib_net_udp_truncation_xmod OK
repro/mi_matrix/stdlib_net_udp_zero_len_xmod OK
repro/mi_matrix/stdlib_os_argc_xmod OK
repro/mi_matrix/stdlib_os_cwd_xmod OK
repro/mi_matrix/stdlib_os_env_xmod OK
repro/mi_matrix/stdlib_os_exit_xmod OK
repro/mi_matrix/stdlib_parse_ftoa_xmod OK
repro/mi_matrix/stdlib_parse_invalid_xmod OK
repro/mi_matrix/stdlib_parse_itoa64_xmod OK
repro/mi_matrix/stdlib_parse_itoa_xmod OK
repro/mi_matrix/stdlib_parse_parsefloat_xmod OK
repro/mi_matrix/stdlib_parse_parseint64_xmod OK
repro/mi_matrix/stdlib_parse_parseint_xmod OK
repro/mi_matrix/stdlib_parse_parseuint64_xmod OK
repro/mi_matrix/stdlib_parse_parseuint_xmod OK
repro/mi_matrix/stdlib_parse_stress_xmod OK
repro/mi_matrix/stdlib_parse_utoa64_xmod OK
repro/mi_matrix/stdlib_parse_utoa_xmod OK
repro/mi_matrix/stdlib_print_aggregate_xmod OK
repro/mi_matrix/stdlib_print_alias_chain_bwd_xmod OK
repro/mi_matrix/stdlib_print_alias_chain_fwd_xmod OK
repro/mi_matrix/stdlib_print_alias_chain_scalar_xmod OK
repro/mi_matrix/stdlib_print_alias_xmod OK
repro/mi_matrix/stdlib_print_autoimport_xmod OK
repro/mi_matrix/stdlib_print_dispatch_xmod OK
repro/mi_matrix/stdlib_print_enum_errset_xmod OK
repro/mi_matrix/stdlib_print_fmt_valid_xmod OK
repro/mi_matrix/stdlib_print_init_order_dep_xmod OK
repro/mi_matrix/stdlib_print_ptr_depth_ok_xmod OK
repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod OK
repro/mi_matrix/stdlib_print_tuple_fwd_ok_xmod OK
repro/mi_matrix/stdlib_print_tuple_var_ok_xmod OK
repro/mi_matrix/stdlib_print_unrelated_ident_xmod OK
repro/mi_matrix/stdlib_print_untyped_lit_xmod OK
repro/mi_matrix/stdlib_ptr_array_slice_ok_xmod OK
repro/mi_matrix/stdlib_ptrarray_for_ok_xmod OK
repro/mi_matrix/stdlib_ptrslice_ok_xmod OK
repro/mi_matrix/stdlib_pub_visibility_ok_xmod OK
repro/mi_matrix/stdlib_rle_decode_xmod OK
repro/mi_matrix/stdlib_rle_decodedlen_xmod OK
repro/mi_matrix/stdlib_rle_determinism_xmod OK
repro/mi_matrix/stdlib_rle_encode_xmod OK
repro/mi_matrix/stdlib_rle_encodedlen_xmod OK
repro/mi_matrix/stdlib_rle_oom_xmod OK
repro/mi_matrix/stdlib_rle_roundtrip_xmod OK
repro/mi_matrix/stdlib_rle_stress_xmod OK
repro/mi_matrix/stdlib_slice_to_many_ptr_xmod OK
repro/mi_matrix/stdlib_sort_binarysearchu32_xmod OK
repro/mi_matrix/stdlib_sort_introsort_xmod OK
repro/mi_matrix/stdlib_sort_sort_xmod OK
repro/mi_matrix/stdlib_sort_sorti32_xmod OK
repro/mi_matrix/stdlib_sort_sortstr_xmod OK
repro/mi_matrix/stdlib_sort_sortu32_xmod OK
repro/mi_matrix/stdlib_sort_stress_xmod OK
repro/mi_matrix/stdlib_std_fmt_seam_xmod OK
repro/mi_matrix/stdlib_stdin_crlf_boundary_xmod OK
repro/mi_matrix/stdlib_stdin_eof_notrailing_xmod OK
repro/mi_matrix/stdlib_stdin_multiline_xmod OK
repro/mi_matrix/stdlib_stdin_multiple_xmod OK
repro/mi_matrix/stdlib_stdin_overflow_xmod OK
repro/mi_matrix/stdlib_stdin_readall_xmod OK
repro/mi_matrix/stdlib_stdin_readerr_xmod OK
repro/mi_matrix/stdlib_stdin_readline_xmod OK
repro/mi_matrix/stdlib_stdin_stress_xmod OK
repro/mi_matrix/stdlib_str_count_xmod OK
repro/mi_matrix/stdlib_str_eqignorecase_xmod OK
repro/mi_matrix/stdlib_str_indexof_xmod OK
repro/mi_matrix/stdlib_str_join_xmod OK
repro/mi_matrix/stdlib_str_lastindexof_xmod OK
repro/mi_matrix/stdlib_str_oom_xmod OK
repro/mi_matrix/stdlib_str_repeat_xmod OK
repro/mi_matrix/stdlib_str_replace_xmod OK
repro/mi_matrix/stdlib_str_split_alias_xmod OK
repro/mi_matrix/stdlib_str_split_xmod OK
repro/mi_matrix/stdlib_str_splitlines_xmod OK
repro/mi_matrix/stdlib_str_stress_xmod OK
repro/mi_matrix/stdlib_str_trim_xmod OK
repro/mi_matrix/stdlib_str_trimleft_xmod OK
repro/mi_matrix/stdlib_str_trimright_xmod OK
repro/mi_matrix/stdlib_str_xmod OK
repro/mi_matrix/stdlib_stream_crlf_boundary_xmod OK
repro/mi_matrix/stdlib_stream_msgreader_oversize_xmod OK
repro/mi_matrix/stdlib_stream_msgreader_stress_xmod OK
repro/mi_matrix/stdlib_stream_msgreader_xmod OK
repro/mi_matrix/stdlib_stream_multiple_async_xmod OK
repro/mi_matrix/stdlib_stream_multiple_xmod OK
repro/mi_matrix/stdlib_stream_readline_empty_xmod OK
repro/mi_matrix/stdlib_stream_readline_noeof_xmod OK
repro/mi_matrix/stdlib_stream_readline_xmod OK
repro/mi_matrix/stdlib_stream_readlinesync_xmod OK
repro/mi_matrix/stdlib_stream_socketlinereader_stress_xmod OK
repro/mi_matrix/stdlib_stream_socketlinereader_xmod OK
repro/mi_matrix/stdlib_stream_stress_xmod OK
repro/mi_matrix/stdlib_switch_case_consts_xmod OK
repro/mi_matrix/stdlib_switch_enum_range_xmod OK
repro/mi_matrix/stdlib_time_monotonic_avail_xmod OK
repro/mi_matrix/stdlib_time_monotonic_xmod OK
repro/mi_matrix/stdlib_time_sleep_xmod OK
repro/mi_matrix/stdlib_try_return_type_ok_xmod OK
repro/mi_matrix/stdlib_tuple_model_ok_xmod OK
repro/mi_matrix/stdlib_union_layout_payload_xmod OK
repro/mi_matrix/stdlib_utf8_codepointlen_xmod OK
repro/mi_matrix/stdlib_utf8_countcodepoints_xmod OK
repro/mi_matrix/stdlib_utf8_decode_xmod OK
repro/mi_matrix/stdlib_utf8_encode_xmod OK
repro/mi_matrix/stdlib_utf8_invalid_xmod OK
repro/mi_matrix/stdlib_utf8_stress_xmod OK
repro/mi_matrix/stdlib_void_temp_stmt_xmod OK
repro/mi_matrix/store_dedup_assign_xmod OK
repro/mi_matrix/store_dedup_const_xmod OK
repro/mi_matrix/store_dedup_valueblock_xmod OK
repro/mi_matrix/strictzig_brace_if_xmod FAIL
repro/mi_matrix/strtod_endptr_wrongdecl_nonnull_xmod OK
repro/mi_matrix/struct_field_store_subscript OK
repro/mi_matrix/switch_case_qualifier_reject_xmod FAIL
repro/mi_matrix/switch_case_range_xmod OK
repro/mi_matrix/switch_char_expr OK
repro/mi_matrix/switch_char_labeled OK
repro/mi_matrix/switch_char_mixed_kinds OK
repro/mi_matrix/switch_char_multi OK
repro/mi_matrix/switch_char_nested OK
repro/mi_matrix/switch_char_nodefault FAIL
repro/mi_matrix/switch_char_single OK
repro/mi_matrix/switch_char_while OK
repro/mi_matrix/switch_char_xmod OK
repro/mi_matrix/switch_char_xmod_expr OK
repro/mi_matrix/switch_char_xmod_nodefault FAIL
repro/mi_matrix/switch_char_xmod_while OK
repro/mi_matrix/switch_expr_payload_capture_xmod OK
repro/mi_matrix/switch_expr_unreachable_xmod OK
repro/mi_matrix/switch_mixed_case_argtype OK
repro/mi_matrix/switch_on_error_anon OK
repro/mi_matrix/switch_on_error_named OK
repro/mi_matrix/switch_str_literal_prong_xmod OK
repro/mi_matrix/switch_str_literal_prong_xmod_xmod OK
repro/mi_matrix/switch_unannotated_diffstr_xmod OK
repro/mi_matrix/switch_unannotated_diffstr_xmod_xmod OK
repro/mi_matrix/switch_unannotated_direct_xmod OK
repro/mi_matrix/switch_unannotated_str_xmod OK
repro/mi_matrix/switch_unannotated_str_xmod_xmod OK
repro/mi_matrix/switch_without_else_reject_xmod FAIL
repro/mi_matrix/tagged_payload_store_reject_xmod GREEN
repro/mi_matrix/tagged_payload_whole_reassign_xmod OK
repro/mi_matrix/tagged_tag_member_shadow_xmod OK
repro/mi_matrix/tagged_tag_sugar_xmod OK
repro/mi_matrix/tagged_tag_switch_reject_xmod FAIL
repro/mi_matrix/tagged_union_cmp_xmod OK
repro/mi_matrix/tailcall_catch_same_eu OK
repro/mi_matrix/target_is_windows_xmod OK
repro/mi_matrix/taskptr_field_store_xmod OK
repro/mi_matrix/test_stub_0 OK
repro/mi_matrix/trap_arena_exhaustion_xmod OK
repro/mi_matrix/trap_orelse_unreachable_xmod OK
repro/mi_matrix/trap_panic_xmod OK
repro/mi_matrix/trap_unreachable_xmod OK
repro/mi_matrix/try_return_type_reject_xmod FAIL
repro/mi_matrix/tu_field_store_ptr OK
repro/mi_matrix/tu_ptrcast_copy OK
repro/mi_matrix/tu_uninit_data_void OK
repro/mi_matrix/tuple_elem_type_reject_xmod GREEN
repro/mi_matrix/tuple_fwd_global_reject_xmod FAIL
repro/mi_matrix/tuple_model_reject_xmod GREEN
repro/mi_matrix/typealias_agg_xmod OK
repro/mi_matrix/typealias_aint_xmod OK
repro/mi_matrix/typealias_arr_elem_mismatch_xmod GREEN
repro/mi_matrix/typealias_arr_len_mismatch_xmod GREEN
repro/mi_matrix/typealias_arr_xmod OK
repro/mi_matrix/typealias_chain_arr_xmod OK
repro/mi_matrix/typealias_eu_xmod OK
repro/mi_matrix/typealias_fn_xmod OK
repro/mi_matrix/typealias_forms_control_xmod OK
repro/mi_matrix/typealias_mptr_xmod OK
repro/mi_matrix/typealias_opt_xmod OK
repro/mi_matrix/typealias_prim_xmod OK
repro/mi_matrix/typealias_ptr_xmod OK
repro/mi_matrix/typealias_pub_aint_xmod OK
repro/mi_matrix/typealias_pub_arr_xmod OK
repro/mi_matrix/typealias_pub_mptr_xmod OK
repro/mi_matrix/typealias_pub_slice_xmod OK
repro/mi_matrix/typealias_slice_xmod OK
repro/mi_matrix/typeres_unhandled_node OK
repro/mi_matrix/unannotated_infer_samelength_xmod OK
repro/mi_matrix/unannotated_infer_stmtexpr_xmod OK
repro/mi_matrix/undef_arr_struct_literal OK
repro/mi_matrix/undef_ident_arg_reject_xmod FAIL
repro/mi_matrix/undef_ident_binop_reject_xmod FAIL
repro/mi_matrix/undef_ident_call_args_reject_xmod FAIL
repro/mi_matrix/undef_ident_call_of_call_reject_xmod FAIL
repro/mi_matrix/undef_ident_call_reject_xmod FAIL
repro/mi_matrix/undef_ident_cond_reject_xmod FAIL
repro/mi_matrix/undef_ident_discard_reject_xmod FAIL
repro/mi_matrix/undef_ident_fieldbase_reject_xmod FAIL
repro/mi_matrix/undef_ident_index_reject_xmod FAIL
repro/mi_matrix/undef_ident_paren_call_reject_xmod FAIL
repro/mi_matrix/undef_ident_return_reject_xmod FAIL
repro/mi_matrix/undef_ident_value_reject_xmod FAIL
repro/mi_matrix/undef_ident_xmod_reject_xmod FAIL
repro/mi_matrix/undefined_slice_array_xmod OK
repro/mi_matrix/union_emission_layout_xmod OK
repro/mi_matrix/union_keyword_tag_xmod OK
repro/mi_matrix/union_literal_nested_xmod OK
repro/mi_matrix/union_offset_reject_xmod FAIL
repro/mi_matrix/var_declared_void GREEN
repro/mi_matrix/voiddecl_boundary_xmod OK
repro/mi_matrix/voiddecl_boundary_xmod_err OK
repro/mi_matrix/voiddecl_chain_r2 OK
repro/mi_matrix/voiddecl_count_r3 OK
repro/mi_matrix/voiddecl_ifexpr_ctl_xmod OK
repro/mi_matrix/voiddecl_ifexpr_xmod OK
repro/mi_matrix/voiddecl_mimic_r6v2 OK
repro/mi_matrix/voiddecl_nested_r5 OK
repro/mi_matrix/voiddecl_payload_xmod OK
repro/mi_matrix/voiddecl_struct_xmod_r1 OK
repro/mi_matrix/voiddecl_switchexpr_xmod OK
repro/mi_matrix/voiddecl_tagprobe_xmod OK
repro/mi_matrix/voiddecl_u64cast_xmod OK
repro/mi_matrix/voiddecl_volume_r4 OK
repro/mi_matrix/voiddecl_xmodtype_xmod OK
repro/mi_matrix/volatile_add_accept_xmod OK
repro/mi_matrix/volatile_cast_accept_xmod OK
repro/mi_matrix/volatile_cast_nonvolatile_xmod GREEN
repro/mi_matrix/volatile_cast_wrong_base_xmod GREEN
repro/mi_matrix/volatile_drop_array_slice_xmod GREEN
repro/mi_matrix/volatile_drop_fnparam_xmod GREEN
repro/mi_matrix/volatile_drop_manyptr_xmod GREEN
repro/mi_matrix/volatile_drop_optional_xmod GREEN
repro/mi_matrix/volatile_drop_ptr_xmod GREEN
repro/mi_matrix/volatile_drop_slice_xmod GREEN
repro/mi_matrix/volatile_drop_void_xmod GREEN
repro/mi_matrix/volatile_fastpaths_xmod OK
repro/mi_matrix/volatile_mmio_xmod OK
repro/mi_matrix/volatile_ptrcast_drop_xmod GREEN
repro/mi_matrix/w3000_bool_or_xmod OK
repro/mi_matrix/w3000_enum_to_int_xmod GREEN
repro/mi_matrix/w3000_enumtoint_explicit_xmod OK
repro/mi_matrix/w3000_sliceptr_manyptr_xmod OK
repro/mi_matrix/w3000_undefined_manyptr_xmod OK
repro/mi_matrix/w3000fp_cvaarg_xmod OK
repro/mi_matrix/w3000fp_enumcmp_bool_xmod OK
repro/mi_matrix/w3000fp_errset_subset_xmod OK
repro/mi_matrix/w3000fp_if_errunion_xmod OK
repro/mi_matrix/w3000fp_if_optional_xmod OK
repro/mi_matrix/w3000fp_noreturn_if_xmod OK
repro/mi_matrix/w3000fp_noreturn_switch_xmod OK
repro/mi_matrix/w3000fp_tuple_array_xmod OK
repro/mi_matrix/width_wrap_signed_xmod OK
repro/mi_matrix/widthbits_union_intconst_xmod OK
repro/mi_matrix/wrap_signed_battery OK
repro/mi_matrix/xmod_amp_arena_union_store OK
repro/mi_matrix/xmod_field_store_index OK
repro/mi_matrix/xmod_global_field_access OK
repro/mi_matrix/xmod_pub_const_global OK
repro/mi_matrix/zT_missing_fwd_xmod OK
repro/mi_opt_null OK
repro/negative_intcast_ice OK
repro/nested_switch_return OK
repro/opt_null_decl OK
repro/optional_non_struct OK
repro/optional_null_vardecl_init OK
repro/optional_void OK
repro/paren_compound_store OK
repro/paren_deref_store OK
repro/ptrcast_manyptr OK
repro/sizeof_mul OK
repro/sizeof_mul_arg OK
repro/sizeof_ptr OK
repro/slice_array_end OK
repro/star_deref OK
repro/struct_init_slice_field OK
repro/switch_capture_name_reuse OK
repro/switch_prong_return OK
repro/tagged_field_path OK
repro/tagged_union_anon_return OK
repro/tagged_union_payload OK
repro/tagged_union_same_type OK
repro/tagged_union_slice_payload OK
repro/tu_void_prong OK
repro/while_cap_ptr OK
repro/zT_1_undeclared OK
stdlib_test/bits_buf_str_usage OK
stdlib_test/crypto_codec_usage OK
stdlib_test/file_stdin_usage OK
stdlib_test/file_stream_usage OK
stdlib_test/map_sort_heap_usage OK
stdlib_test/net_stream_usage OK
stdlib_test/os_time_usage OK
```

---

## Fix round 1 (2026-10-12) — mi_matrix anchor set + inventory cite corrections

All four findings addressed (Minors 5–6 deferred per instruction). No BLOCKED conditions: 25/25 fixture goldens MATCH at baseline and the set definition enumerates exactly 25. Touch set: this report + `progress.md` + their commit; ZERO `sf/src` change; seed untouched.

### F1 — Finding 1: anchor-set enumeration (command + observed)

```bash
cd /workspace/znineeight
for d in repro/mi_matrix/*/; do n=$(basename "$d"); case "$n" in stdlib_*) continue;; esac;
  if [ -f "$d/expected.txt" ] && [ -f "$d/expected.rc" ]; then
    et=$(wc -c < "$d/expected.txt"); er=$(tr -d '[:space:]' < "$d/expected.rc");
    echo "$n expected.txt_bytes=$et expected.rc=$er"; fi; done
```
Observed (26 dirs ship BOTH golden files; 25 match the set definition — non-empty `expected.txt` + `expected.rc=0`; the 26th is the oob trap fixture):

```
array_of_struct_literal_xmod expected.txt_bytes=27 expected.rc=0
catch_discard_struct_xmod expected.txt_bytes=24 expected.rc=0
const_assign_ok_xmod expected.txt_bytes=16 expected.rc=0
empty_named_struct_field_xmod expected.txt_bytes=6 expected.rc=0
empty_named_struct_xmod expected.txt_bytes=6 expected.rc=0
enum_subbyte_backing_xmod expected.txt_bytes=24 expected.rc=0
f64_literal_precision_xmod expected.txt_bytes=11 expected.rc=0
field_store_continue_nested_xmod expected.txt_bytes=31 expected.rc=0
field_store_continue_xmod expected.txt_bytes=24 expected.rc=0
fn_ptr_signature_ok_xmod expected.txt_bytes=3 expected.rc=0
for_range_end_len_xmod expected.txt_bytes=113 expected.rc=0
len_array_field_xmod expected.txt_bytes=69 expected.rc=0
lexer_float_exponent_xmod expected.txt_bytes=19 expected.rc=0
lit64_decimal_xmod expected.txt_bytes=9 expected.rc=0
nested_loop_label_xmod expected.txt_bytes=44 expected.rc=0
optional_void_present_xmod expected.txt_bytes=38 expected.rc=0
packed_nested_whole_depth_ok_xmod expected.txt_bytes=4 expected.rc=0
packed_nested_wholeliteral_xmod expected.txt_bytes=105 expected.rc=0
packed_union_struct_wholemember_xmod expected.txt_bytes=4 expected.rc=0
shadow_ok_xmod expected.txt_bytes=16 expected.rc=0
sig_known_type_ok_xmod expected.txt_bytes=22 expected.rc=0
slice_index_field_store_oob_xmod expected.txt_bytes=0 expected.rc=133   <- trap subset (excluded from the 25)
slice_index_field_store_xmod expected.txt_bytes=35 expected.rc=0
tagged_payload_whole_reassign_xmod expected.txt_bytes=14 expected.rc=0
tagged_tag_member_shadow_xmod expected.txt_bytes=16 expected.rc=0
tagged_tag_sugar_xmod expected.txt_bytes=31 expected.rc=0
```

Count under the definition (non-empty `expected.txt` + `expected.rc=0`, non-stdlib) = **25** = the review's count -> **set definition unambiguous, no STOP needed**. Also enumerated: 37 non-stdlib dirs ship ONLY `expected.rc` (no `expected.txt`) — reject-census fixtures (sample: `alias_value_reject_xmod` dir contents = `expected.rc` (`2`), `expected_error.txt`, `main.zig`) — compile-time rejects with no runtime stdout; excluded from the runtime-anchor set by the definition (they stay owned by corpus classify FAIL/GREEN).

### F2 — Finding 1: the 25 fixtures vs their committed goldens

Harness command (golden-owner recipe; 3x-identical + `cmp` stdout vs `expected.txt` + rc vs `expected.rc` per fixture):

```bash
bash scripts/stdlib/run_fixtures.sh /tmp/task0_work/seed/zig1_5_clean \
  repro/mi_matrix/array_of_struct_literal_xmod repro/mi_matrix/catch_discard_struct_xmod \
  repro/mi_matrix/const_assign_ok_xmod repro/mi_matrix/empty_named_struct_field_xmod \
  repro/mi_matrix/empty_named_struct_xmod repro/mi_matrix/enum_subbyte_backing_xmod \
  repro/mi_matrix/f64_literal_precision_xmod repro/mi_matrix/field_store_continue_nested_xmod \
  repro/mi_matrix/field_store_continue_xmod repro/mi_matrix/fn_ptr_signature_ok_xmod \
  repro/mi_matrix/for_range_end_len_xmod repro/mi_matrix/len_array_field_xmod \
  repro/mi_matrix/lexer_float_exponent_xmod repro/mi_matrix/lit64_decimal_xmod \
  repro/mi_matrix/nested_loop_label_xmod repro/mi_matrix/optional_void_present_xmod \
  repro/mi_matrix/packed_nested_whole_depth_ok_xmod repro/mi_matrix/packed_nested_wholeliteral_xmod \
  repro/mi_matrix/packed_union_struct_wholemember_xmod repro/mi_matrix/shadow_ok_xmod \
  repro/mi_matrix/sig_known_type_ok_xmod repro/mi_matrix/slice_index_field_store_xmod \
  repro/mi_matrix/tagged_payload_whole_reassign_xmod repro/mi_matrix/tagged_tag_member_shadow_xmod \
  repro/mi_matrix/tagged_tag_sugar_xmod
```
Observed tail: `run_fixtures: 25 PASS / 0 FAIL over 25 dirs` (each line `PASS repro/mi_matrix/<name>`).

Per-fixture values (independent single-run mirror of the harness recipe — `zig1 -ffast -o <tmp> <entry>` -> gcc -> `sh <tmp>/build_target.sh linux <tmp>/prog` -> `timeout 120` run; stdout md5 compared to `expected.txt` md5, rc to `expected.rc`) — the 25-row table is §1.8 above: every row `dump=0 build=0 run_rc=0(exp 0) rc=MATCH stdout=MATCH` with the listed md5. **No fixture mismatched its committed golden.**

### F3 — D-fix trap subset re-run (command + observed)

```bash
/tmp/task0_work/seed/zig1_5_clean -fsafe -o /tmp/task0_work/anchor/oob repro/mi_matrix/slice_index_field_store_oob_xmod/main.zig
cd /tmp/task0_work/anchor/oob && sh build_target.sh linux ./prog
timeout 120 ./prog > run.out 2> run.err; echo "run rc=$?"; wc -c < run.out; md5sum < run.out; md5sum < <(cat repro/mi_matrix/slice_index_field_store_oob_xmod/expected.txt)
```
Observed: `dump rc=0`, `build rc=0`, `run rc=133` (expected.rc=133), `stdout bytes=0` (expected.txt bytes=0), both md5 `d41d8cd98f00b204e9800998ecf8427e`. **MATCH.** (Sibling D-fix prints D1/D2/D4 unchanged from round 0 — §1.8.)

### F4 — Finding 2: cite re-verification (command + observed)

```bash
grep -n "fn mangleTempName" sf/src/c89_emit.zig
# 3195:fn mangleTempName(interner: *StringInterner, temp_id: u32) []const u8 {
grep -n "fn typeIdName" sf/src/c89_emit.zig
# 5530:fn typeIdName(emitter: *C89Emitter, prefix: []const u8, tid: u32) []const u8 {
grep -n "fn intTypeNeedsWidthWrap" sf/src/c89_emit.zig
# 4722:fn intTypeNeedsWidthWrap(reg: *TypeRegistry, tyid: u32) u8 {
```
**Truth:** `mangleTempName` = `:3195`, `typeIdName` = `:5530` — the **brief cites were exact, no drift**; the round-0 report cites (`:3194`, `:5529`) were wrong (sed-window eyeball off-by-one; `:3194`/`:5529` are the blank/comment lines above the defs) and the "drift -1" claims were false. `intTypeNeedsWidthWrap` = `:4722` (round-0 `:4723` wrong). All three corrected in §2.1/§2.5/§2.9.3; C4 rewritten.

Full re-verification of every remaining §2 cite (same `grep -n "fn <name>"` batch over `c89_emit.zig`, plus content greps for the interior cites) observed exact at every stated line:

```
419 emitVariantFieldPayload | 459 resolveFieldAccess | 577 mangleC89Keyword | 594 cUnionMemberName |
738 nameManglerMangleGlobal | 897 syntheticTypeName | 931 sliceElementName | 940 getCTypeName |
1172 getTempTypeByIndex | 1186 hoistedTypeOfInFn | 1195 hoistedTypeOf | 1201 hoistedTypeId |
1324 c89NeedsEmitEdge | 1363 tstEdgesWalk | 1484 tstTopologicalSort | 1571 emitTypeDefOnce |
1603 emitPointeeDep | 1656 emitDepMember | 1669 emitTypeDeps | 1702 computeSharedSet |
1775 shouldSkipTypeEmission | 1950 emitTaggedUnionType | 2058 emitStructType | 2105 emitUnionType |
2145 emitArrayType | 2373 emitOptionalType | 2431 mangleLocalName | 2458 findCalleeFnTypeId |
2795 moduleQualifiedName | 3978 nestScalarEffTid | 3995 nestEffCType | 4004 nestDefTempId |
4018 nestShapeOk | 4065 nestConsumerWired | 4201 nestFail | 4255 nestEmitDefRvalue |
4329 nestEmitBinExpr | 4385 emitBinRvalueText | 4692 getUnsignedCTypeName | 4712 classifyIntSignedness |
4895 intTypeByteWidth | 4952 ptrCTypeNameFromElem | 4963 getTempEffType | 4996 getTempTypeInfoResolve |
5011 getTempTypeInfo | 5030 emitSatBinary | 5429 printFnSourceName | 5472 getPrintFnName |
6202 emitAggPrinterDef | 6589 emitNeededTupleAt | 9473 intKindIsSignedBase | 9479 intKindIsUnsignedBase |
9487 intKindWidthBytes
```
Interior cites (content greps, observed): `:2091` `var fname = interner_mod.stringInternerGet(...)` (emitStructType) EXACT; `:468`/`:513`/`:524`/`:558` (resolveFieldAccess arms) EXACT; `:2428` `typeRegistryCNameIdSet` EXACT; `:3827` nest_inl guard EXACT; `:3820` `d4ok` marker EXACT; `:3831-3833` `d4_dead`/`d4_local`/`d4_nodecl` EXACT (round-0 "cascade `:3829-3833`" tightened to `:3831-3833` in §2.9.1); `:5019`/`:7577`/`:7707` ICE strings EXACT; `:2088` `measureMarkerWrite(fe_m)` EXACT; `:779-781` nest state decls EXACT. Cross-file cites (`type_resolver.zig:629/:889/:593/:599/:604/:609/:662`, `type_registry.zig:980/:919/:931/:997/:1046`, `semantic_analyzer.zig:1562`, `main.zig:104/:206/:333`, `main_dump.zig:60`, `name_mangler.zig:1-7`) unchanged from round-0 grep evidence (§2.8). **No other drift exists; the "re-derived" convention claim now holds with evidence.**

### F5 — Minor 3: full stub grep + delete-set row

Full `grep -rn "name_mangler" sf/src/` output + the stub-file grep + `strip_main.zig` body are now shown in §2.8 (the round-0 output was abridged — the stated pattern also matches `strip_main.zig:2-3`, `main.zig:10`, `main_dump.zig:10`, and the stub file's own identifiers need the second pattern). Conclusion unchanged; the §2.1 `ctx.name_mangler` row's delete set now includes `strip_main.zig:2-3` + the `:6-7` `var nm = nameManglerInit(); _ = nm;` discard.

### F6 — Minor 4: evidence for the round-0 verification claims

```bash
awk '/^## Appendix A/{f=1} f&&/^```$/{c++; next} c==1{print} c>=2{exit}' \
  .superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/task-0-report.md > /tmp/task0_work/appendix_check2.txt
diff /tmp/task0_work/appendix_check2.txt /tmp/task0_work/corpus_baseline.txt && echo "diff: EMPTY"
md5sum /tmp/task0_work/appendix_check2.txt /tmp/task0_work/corpus_baseline.txt
# diff: EMPTY
# 518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/appendix_check2.txt
# 518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
# wc -l -> 1124

cmp /tmp/task0_work/gold/mud_srv.out examples/z98/mud_server/demo/canonical_expected.txt && echo "cmp server: IDENTICAL"
cmp /tmp/task0_work/gold/mud_cli.out examples/z98/mud_server/demo/canonical_client_expected.txt && echo "cmp client: IDENTICAL"
# cmp server: IDENTICAL
# cmp client: IDENTICAL
```
Round-0 claims are now backed by shown command output (§1.2/§1.3 wording points here).

### Fix-round verdict

| finding | disposition |
|---|---|
| Important 1 (anchor set narrowed) | FIXED — §1.8 broadened to the full defined set (25 + oob); enumeration = 25 (unambiguous); 25/25 + oob MATCH goldens; set definition written into the ledger; Concerns C6 added |
| Important 2 (false drift + 3 wrong cites) | FIXED — `mangleTempName:3195`, `typeIdName:5530`, `intTypeNeedsWidthWrap:4722` corrected with grep evidence; C4 rewritten (brief cites were exact; no drift anywhere); all other cites re-verified exact; `:3829-3833` tightened to `:3831-3833` |
| Minor 3 (abridged grep + strip_main site) | FIXED — §2.8 full outputs (two patterns + file body); P1 delete-set row includes `strip_main.zig:2-3` + `:6-7` |
| Minor 4 (unshown verification) | FIXED — F6 shows `diff`/`md5sum` (Appendix A) + `cmp` (mud goldens); §1.2/§1.3 point at F6 |
