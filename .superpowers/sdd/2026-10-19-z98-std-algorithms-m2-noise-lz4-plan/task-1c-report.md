# M2 T1C report — z9play migrate + full battery + seed v104

Status: IN PROGRESS (incremental)
Scope (plan §Task 1C): rebuild from seed, full battery + all z9play tiers with
mover table, z9play artifact migration (measured movers only; `floor.zig`
untouched), `archive_seed.sh` interim count 33→34, seed v104 rotation, 3 commits.

Constraints honored: no push; `run.err` untouched; `floor.zig` NOT edited;
Task 1C only.

---

## 1. Rebuild from fixed source (Step 1)

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t1c_build
[seed] hop1 binary md5: a53510875bc07065c6d5e2dc01136029
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop3 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] three-hop closure OK (moving point): hop2 == hop3 == 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m2_t1c_build ===
```

- Compiler under test: `/tmp/m2_t1c_build/zig1_5_clean` (hop1, md5
  `a53510875bc07065c6d5e2dc01136029`) + sibling `lib/`.
- Fixed point (hop2==hop3): `21c957730d268f1e7883176fa5413b65` — byte-identical
  to the T1F recorded fixed point. Moving-point (three-hop) is expected and
  benign: the committed seed binary embeds pre-T1F `emit_support`, so hop1
  writes the old `zig_compat.h` into gen and only hop2 onward close. Convergence
  criterion hop2==hop3 holds.
- Fixed point UNCHANGED vs T1F — no `sf/src` movement since T1F; T1C is
  example/docs/seed-scope only (plus `archive_seed.sh` count text).

---
## 2. Full battery + z9play tiers (Step 2, incremental)

Compiler under test: `/tmp/m2_t1c_build/zig1_5_clean`. Old values = frozen
anchors / committed goldens (pre-T1B `b299b4b4…` era). Scratch: `/tmp/m2_t1c_batt/`.

### 2.1 Corpus classify — 0 movers

```
$ bash scripts/corpus/classify /tmp/m2_t1c_build/zig1_5_clean /tmp/m2_t1c_batt/corpus_new.txt
wrote /tmp/m2_t1c_batt/corpus_new.txt: 1143 dirs
$ grep -vE '<19 post-freeze fixture dirs> ' corpus_new.txt > corpus_frozen1124.txt
$ wc -l corpus_frozen1124.txt → 1124
$ md5sum corpus_frozen1124.txt → 518eca1a9b5d3e1cc5a48abce214abd8
$ awk '{print $2}' corpus_new.txt | sort | uniq -c
    116 FAIL
     58 GREEN
    969 OK
```

Full tree 1143 = 969 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH. Frozen-1124
class file **byte-identical** to anchor `518eca1a9b5d3e1cc5a48abce214abd8`
(950 OK / 58 GREEN / 116 FAIL). **0 class movers.** The 19 excluded dirs are the
9 designed D1/D2 fixtures + 10 post-freeze additions (T1B `lexer_float_rounding_xmod`,
M1 `stdlib_rand_*`×4/`stdlib_map_robinhood`/`stdlib_dir_iter`/`stdlib_cross_smoke`,
held-Task-1 `stdlib_noise_*`×2), all OK in the full tally.

### 2.2 Runtime goldens 5/5 — byte-identical

Build: `--dump-c89` + `gcc -m32 -std=c89 -I sf/src/include` + `zig_runtime.c zig_pal.c`
(all 4 dumps rc=0, all 4 gcc rc=0).

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 gold/gol > gol.out` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| gold/lisp` | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| json_parser | `cd examples/z98/json_parser && gold/json` | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| mud server | `bash demo/session.sh gold/mud …` | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

**5/5 MATCH, 0 movers.**

### 2.3 mi_matrix frozen 25 + oob — MATCH

Frozen-25 anchor set (non-`stdlib_*` ∧ non-empty `expected.txt` ∧ `expected.rc=0`,
minus the 10 post-freeze fixtures): `run_fixtures` → **25 PASS / 0 FAIL over 25 dirs**.

OOB trap `slice_index_field_store_oob_xmod` (`-fsafe`): DUMP_RC=0, BUILD_RC=0
(`build_target.sh linux`), RUN_RC=133 (Trace/breakpoint trap), stdout 0 B
(md5 `d41d8cd98f00b204e9800998ecf8427e`). **MATCH.**

New-fixture probe (not part of frozen-25): `lexer_float_rounding_xmod`,
`lexer_float_exponent_xmod`, `stdlib_noise_basic_xmod`, `stdlib_noise_cross_xmod`
→ **4 PASS / 0 FAIL**.

---
### 2.4 Examples 26/26 build + 26/26 run — 0 movers

Build: `-ffast -o <out>` + `build_target.sh linux`, CWD = example dir.
Run: timeout 25 (mud_server 8), stdin `/dev/null`, rogue* `q\n`,
lisp* `(+ 1 2)\n`, json* run from their own dir.

| example | rc | stdout md5 prefix | frozen table | move |
|---|---|---|---|---|
| days_in_month | 0 | `8c0d394c` | `8c0d394c` | no |
| fibonacci | 0 | `b53b3a3d` | `b53b3a3d` | no |
| func_ptr_return | 0 | `f6a54779` | `f6a54779` | no |
| game_of_life | 0 | `fcbf7e7c` | `fcbf7e7c` | no |
| heapsort | 0 | `8cf0a784` | `8cf0a784` | no |
| hello | 0 | `74630882` | `74630882` | no |
| json_parser | 0 | `8bda3d5a` | `8bda3d5a` | no |
| json_parser_upgraded | 0 | `8bda3d5a` | `8bda3d5a` | no |
| json_parser_workaround | 0 | `dc22fa47` | `dc22fa47` | no |
| lisp_interpreter | 0 | `b3d9f897` | `1c1f0a41`* | see note |
| lisp_interpreter_adv | 0 | `b3d9f897` | `1c1f0a41`* | see note |
| lisp_interpreter_curr | 0 | `b3d9f897` | `1c1f0a41`* | see note |
| lisp_interpreter_upgraded | 0 | `b3d9f897` | `1c1f0a41`* | see note |
| lzw | 0 | `c3c7765e` | `c3c7765e` | no |
| mandelbrot | 0 | `d5966775` | `d5966775` | no |
| mud_server | 124 | `9545fe1d` | `9545fe1d` | no |
| prime | 0 | `d095a94d` | `d095a94d` | no |
| quicksort | 0 | `45d2f0fb` | `45d2f0fb` | no |
| rogue_mud | 0 | `3fb6709e` | `3fb6709e` | no |
| rogue_mud_upgraded | 0 | `3fb6709e` | `3fb6709e` | no |
| sort_strings | 0 | `c6c047cb` | `c6c047cb` | no |
| tco_defer | 0 | `264ea6b1` | `264ea6b1` | no |
| tco_factorial | 0 | `3d70c50b` | `3d70c50b` | no |
| tco_return_try | 0 | `7421137a` | `7421137a` | no |
| z9play | 1 | `f35b7ef7` | `f35b7ef7` | no |
| z9torr | 1 | `f666af15` | `f666af15` | no |

*lisp note: closed — the frozen T5.3 table value `1c1f0a41…` is the
stdin-`/dev/null` feed. Re-run of the 4 built lisp binaries with `</dev/null`:
all 4 stdout md5 `1c1f0a41…` (byte-match frozen). The `(+ 1 2)\n` feed shown
in the table is the gate-program golden feed (`b3d9f897…`, §2.2, also MATCH).
Feed difference only — **0 compiler movers.** **26/26 build + 26/26 run.**

### 2.5 Stdlib — fixtures 294/0; std_noise crosscheck mover (T1D-owned)

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t1c_build/zig1_5_clean
run_fixtures: 294 PASS / 0 FAIL over 294 dirs
run_crosscheck: 2 PASS / 1 FAIL over 3 modules
failed: std_noise:Z98-NE-REF:grid
STDLIB GATE FAILED (run_crosscheck rc=1)
```

Mover measured old → new:

| item | old (`b299b4b4…` compiler) | new (`a5351087…`/fp `21c95773…`) | class |
|---|---|---|---|
| `std_noise` crosscheck grid (Z98 vs NE ref) | PASS (1 vectors) | FAIL (`Z98-NE-REF:grid`) | mover |

Root cause (verified this session, not a T1C fix): `sf/src/std_noise.zig` carries
the held-Task-1 **workaround literals** `0.3660254037844389` /
`-0.16666666666666664` (lines 39–40 + comment) — chosen to compensate the OLD
broken `parseF64`. Under corrected rounding they now parse to different bits
than the compensating target, so `noise2d/3d` drifts from the C reference grid.
Proof probe: with a scratch copy of `std_noise.zig` restoring the canonical
literals `0.366025403784439` / `-0.16666666666666666`, the NEW compiler passes
`run_crosscheck std_noise` → `PASS std_noise (1 vectors)`. The old compiler
cannot compile `std_noise` at all without a lib copy (its v103 `lib/` predates
the module) — with `std_noise.zig`/`std_rand.zig` copied into its lib it passes
the grid, confirming the old→new direction.

This is exactly the defect Task 1D exists to close (restore canonical literals
+ re-baseline); Task 1C must NOT edit `std_noise.zig` (brief: z9play artifacts +
`archive_seed.sh` count only). Recorded as a **known pre-existing mover,
T1D-owned**; stdlib fixture goldens (`stdlib_noise_basic_xmod` PGM hash etc.)
still pass (294/0 — u8 quantization absorbs the 1–2 ULP constant drift, T1B
ruling). The seed v104 rotation below therefore archives a tree whose
`std_noise` crosscheck is expected-red until T1D — matches plan sequencing
(Task 1D: "rotate v105 with the canonical std_noise").

### 2.6 Pins 8/8 — 0 movers

`<compiler> <mode> --dump-c89 examples/z98/<entry>/main.zig | md5sum` from
repo root, `/tmp/m2_t1c_build/zig1_5_clean`:

| entry | mode | old (v103 QUICK_REF) | new | move |
|---|---|---|---|---|
| mud_server | `-fsafe` | `35ec8c8c1158e260c328212ac5fdc013` | `35ec8c8c1158e260c328212ac5fdc013` | no |
| mud_server | `-ffast` | `3203868ad4b435e8c1968fedf9284695` | `3203868ad4b435e8c1968fedf9284695` | no |
| game_of_life | `-fsafe` | `4a963f79e08c67329f4fff46530090e4` | `4a963f79e08c67329f4fff46530090e4` | no |
| game_of_life | `-ffast` | `03a18737b641a6a95c67aec71daed3f7` | `03a18737b641a6a95c67aec71daed3f7` | no |
| lisp_interpreter_curr | `-fsafe` | `4939b6e20eb4ee3d519fc3fd91e6e0d6` | `4939b6e20eb4ee3d519fc3fd91e6e0d6` | no |
| lisp_interpreter_curr | `-ffast` | `a2afe23d87d35eb741464423a382c0f8` | `a2afe23d87d35eb741464423a382c0f8` | no |
| json_parser | `-fsafe` | `95f82c77058e2f5647f9711a14448a79` | `95f82c77058e2f5647f9711a14448a79` | no |
| json_parser | `-ffast` | `96fdbc4c6e6e76209cc2b27a6b959482` | `96fdbc4c6e6e76209cc2b27a6b959482` | no |

**0/8 movers.** Expected: these four entries contain no decimal f64 literal
whose parse moved (their pin stability was the T1A inventory's prediction for
non-float sources). QUICK_REF 8-pin table stays as-is (heading re-stamped in
§3 only if needed — values unchanged).

### 2.7 Markers — 0 movers

```
$ /tmp/m2_t1c_build/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig \
    > mk_gol.c 2> mk_gol.bin
3437 mk_gol.bin   (lines)
38408 mk_gol.bin  (bytes)
```

Unchanged `3437 / 38408` vs the T5.3 anchor. **0 movers.**

---
### 2.8 z9play tiers (info, setup, cli, tui, audio, decode, flac, stream, win9x)

Compiler: `/tmp/m2_t1c_fp/zig1_5_clean` (= hop2 = fixed point
`21c957730d268f1e7883176fa5413b65`, sibling `lib/`). All tiers run with
`ZIG=… OUT=/tmp/m2_t1c_z9/<tier>`.

| tier | result | movers observed |
|---|---|---|
| `tier_info.sh` | **20/0 PASS** | none (meta goldens unchanged) |
| `tier_setup.sh` | **21/0 PASS** | none (setup goldens unchanged) |
| `tier_cli.sh` | **23/0 PASS** | dump-c89 main.zig records `47f1691c8d1f5041e4bd7208e50ed65d` |
| `tier_tui.sh` | 39/1 FAIL | 1. fixed-point md5 pin `b299b4b4…`→`21c95773…`; dump-c89 ui.zig `7395dad777efe7fb8417fc1e57d64235` |
| `tier_audio.sh` | **27/0 PASS** | none (M3 goldens tolerance + determinism) |
| `tier_decode.sh` | **25/0 PASS** | **exact PCM pin `e7f24870ec03b924be1b8e55a1962fb3` (352844 B) UNCHANGED** |
| `tier_flac.sh` | 57/2 FAIL | 1. fixed-point md5 pin; 2. nested `tier_tui` cascade; dump-c89 main/ui `47f1691c…`/`7395dad7…` stable 2× |
| `tier_stream.sh` | 17/3 FAIL | 1. fixed-point md5 pin; 2–3. nested tui/flac cascade; **`--pcm` byte-exact pin `e7f24870…` UNCHANGED** |
| `tier_win9x.sh` | **14/0 PASS** | none (9x PE/import + wine parity) |

Bonus (not in the 9-tier list, run for completeness): `tier_math.sh` 8/0 PASS,
`tier_console.sh` 11/0 PASS.

**Mover table (old → new):**

| artifact | old | new | class |
|---|---|---|---|
| z9play `main.zig` Linux `--dump-c89` | `23f9b5ec0f8e69fe48e9b5598719ced7` | `47f1691c8d1f5041e4bd7208e50ed65d` | mover (floor table literals re-parse) |
| z9play `ui.zig` Linux `--dump-c89` | `76d0fc83121892118089b10c6b66bb41` | `7395dad777efe7fb8417fc1e57d64235` | mover |
| z9play `main.zig` `-osw --dump-c89` | `6cd349b5fae0b6a703d27424ddfb70f2` | `92b9ae90148e037f8e3a0ead6ef30538` | mover |
| z9play `ui.zig` `-osw --dump-c89` | `294e3fde8819e638556d07cddc385301` | `cbe3cfa6bb70d1b0b2161a37a4fdf400` | mover |
| tier fixed-point compiler md5 pin (tui/flac/stream) | `b299b4b435e624d0ddbd2edde681cbc3` | `21c957730d268f1e7883176fa5413b65` | mover |
| exact PCM pin `--pcm` WAV md5 (`tier_decode`/`tier_stream`) | `e7f24870ec03b924be1b8e55a1962fb3` | `e7f24870ec03b924be1b8e55a1962fb3` | **non-mover** |
| `testdata/expected/*.pcm` goldens (5 fixtures, tolerance-compared) | pass | pass | **non-mover** |
| `*.meta` / `*.setup` goldens | pass | pass | **non-mover** |

Mechanism: `floor.zig`'s 256-entry `floor1_inverse_dB_table` carries decimal
f64 literals that re-parse (≤4 ULP) under corrected rounding — their emitted C
literal text changes, so every `--dump-c89` of a program importing `floor.zig`
moves. Runtime PCM is byte-identical because ≤4 ULP (≈9e-16 relative) never
crosses an s16 rounding boundary in these fixtures (measured: exact pin
unchanged). Dump pins re-measured with hop1 == hop2 (byte-identical dumps
confirmed). The9 fixed-point pin FAILs are a stale-pin class (compiler binary
md5 moved with the lexer fix), not decode drift.

---
## 3. z9play migration (Step 3)

**Ruling (brief file list vs binding rule):** the brief names
`tests/tier_decode.sh`/`tests/tier_stream.sh` as the exact-pin files but the
binding constraint is "update ONLY measured movers". The measured tier movers
also include the **fixed-point compiler md5 pins** in `tests/tier_tui.sh`,
`tests/tier_flac.sh`, `tests/tier_stream.sh` (all three assert
`b299b4b4…` and fail against the T1B/T1F compiler). Those were updated too —
cost if wrong: three pin lines in example tests. `tests/tier_decode.sh` needed
NO edit (exact PCM pin measured a non-mover).

Edits (all measured):

1. **`tests/tier_tui.sh`, `tests/tier_flac.sh`, `tests/tier_stream.sh`** —
   fixed-point md5 pin `b299b4b435e624d0ddbd2edde681cbc3` →
   `21c957730d268f1e7883176fa5413b65`; seed labels `v101`/`v102` → `v104`;
   comment parentheticals updated. PCM/exact pins in `tier_stream.sh`
   (`e7f24870ec03b924be1b8e55a1962fb3`, 352844 B) left untouched — non-movers.
2. **`examples/z98/z9play/README.md`** (Notes pin block) — current pins
   re-stamped to T1C values; M9 values preserved as superseded history:
   - Linux default: `main.zig` `23f9b5ec…`→`47f1691c8d1f5041e4bd7208e50ed65d`,
     `ui.zig` `76d0fc83…`→`7395dad777efe7fb8417fc1e57d64235`
   - `-osw`: `main.zig` `6cd349b5…`→`92b9ae90148e037f8e3a0ead6ef30538`,
     `ui.zig` `294e3fde…`→`cbe3cfa6bb70d1b0b2161a37a4fdf400`
3. **`examples/z98/z9play/NOTES.md`** — `MD5 (--dump-c89)` current block and
   the `--dump-c89` recipe block re-stamped to the same T1C values; M9-era
   values retained as superseded history. The exact-PCM pin line
   (`e7f24870…`, 352,844) untouched — non-mover.
4. **NOT edited (verified non-movers):** `floor.zig` (binding constraint — the
   table is already spec decimal text), `testdata/expected/*.pcm`,
   `*.meta`/`*.setup` goldens, `tests/tier_decode.sh` exact pin,
   `tests/tier_stream.sh` PCM pin.

All four dump pins re-measured stable 2× and byte-identical between hop1 and
hop2 dumps (§2.8) — pin values are compiler-behavior, not build-path artifacts.

## 4. Interim seed count (Step 4)

`scripts/seed/archive_seed.sh` (std_noise was already in the copy list — the
copy loop carries 34 entries):

- module comment lib-list: `std_rand.zig}` → `std_rand.zig, std_noise.zig}`
- `SEED_README.txt` text: "the 33 std .zig" → "the 34 std .zig" (+ enumeration
  gains `std_noise.zig`)
- manifest prose: "(33 std files" → "(34 std files"
- CHANGELOG template: "(33 std files; md5 …)" → "(34 std files; …)"
- `std install` prose: "lib/ with the 33 std .zig" → "34 std .zig"

`bash -n scripts/seed/archive_seed.sh` OK; no remaining `33` count sites.
Task 3 later takes the count to 35 (`std_lz4`) per plan.

---
### 3.1 Post-migration tier re-verification

Re-ran the three previously-failing tiers with `ZIG=/tmp/m2_t1c_fp/zig1_5_clean`
(hop2 = fixed point `21c95773…`):

```
tier_tui:    40 passed, 0 failed — TIER_TUI PASS   (seed pin: "seed v104 compiler md5 is the fixed point 21c95773…")
tier_flac:   59 passed, 0 failed — TIER_FLAC PASS  (nested tui 40/0, audio 27/0)
tier_stream: 20 passed, 0 failed — TIER_STREAM PASS (nested info 20/0, setup 21/0, cli 23/0, tui 40/0, audio 27/0, flac 59/0;
             --pcm byte-exact pin e7f24870… ok; 64 MiB ulimit gate ok)
```

All 9 z9play tiers green after migration. No `floor.zig` edit (verified
untouched in `git status`).

---
## 5. Seed rotation v103 → v104 (Step 5)

Example-migration commit `8bb1361d` first (rotation captures it as HEAD, per
M1-T4 precedent), then:

```
$ bash scripts/seed/archive_seed.sh /tmp/m2_t1c_build/hop2/zig1_hop2 \
    /tmp/m2_t1c_build/hop2 release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 21c957730d268f1e7883176fa5413b65
[archive] wrote release/seed/zig1-seed.tgz (archive md5 cfe7fe31edd16a526d549201dfbd7c2b)
## 2026-10-20 — seed v104 (HEAD 8bb1361d)
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (34 std files; md5 `3e8b6f6628973414425c1df63f8c4455`) |
| archive md5 | `cfe7fe31edd16a526d549201dfbd7c2b` |
[archive] prepended entry to release/seed/CHANGELOG.md
```

Inputs: hop2 binary (`zig1_hop2`, the fixed-point binary) + its self-emission
`hop2/` gen dir (hop2 gen ≡ hop3 gen byte-identical — verified, so the archived
gen is the fixed-point binary's true self-emission).

- Archive md5: `cfe7fe31edd16a526d549201dfbd7c2b`
- Archived binary md5 (= fixed point): `21c957730d268f1e7883176fa5413b65`
- `gen/` 46 `.c` + 47 `.h` (10,307,965 bytes)
- `lib/manifest.md5`: 34 lines (std_noise included; interim count 34 — Task 3
  takes it to 35 with `std_lz4`), manifest md5 `3e8b6f6628973414425c1df63f8c4455`
- CHANGELOG entry prepended (`2026-10-20 — seed v104`, HEAD `8bb1361d`).

Rotation verification:

```
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/zig1 | md5sum
21c957730d268f1e7883176fa5413b65
$ tar -xOf … zig1-seed/lib/manifest.md5 | wc -l → 34
$ tar -tzf … | grep -c 'lib/.*\.zig$' → 34
$ FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t1c_check
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
[seed] recorded fixed point OK: 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m2_t1c_check ===
```

**Notable:** closure is TWO-hop again after rotation (vs the T1F-era three-hop
moving point). Expected: v104's archived binary embeds the post-T1F
`emit_support`, so hop1's gen carries the new `zig_compat.h` and hop1 == hop2
directly. The moving-point branch is dormant until another `emit_support`-byte
change. Fixed point UNCHANGED from T1F (`21c95773…`) — T1C moved no compiler
bytes.

---
## 6. Commits (Step 6)

1. `8bb1361d` `example(z9play): migrate to correctly rounded f64 literals`
   — `examples/z98/z9play/{README.md,NOTES.md,tests/tier_{tui,flac,stream}.sh}`
   + `docs/sf/QUICK_REF.md` (T1C z9play pin re-measure note).
2. `de9258ba` `chore(seed): rotate v104 (lexer f64)`
   — `scripts/seed/archive_seed.sh` (count 33→34), `release/seed/zig1-seed.tgz`,
   `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md` (current-seed block +
   rotation history).
3. (this commit) `docs(sdd): M2 T1C report` — report + ledger.

## 7. Complete mover table (every measured old → new)

| # | artifact | old | new | disposition |
|---|---|---|---|---|
| 1 | corpus frozen-1124 class file | `518eca1a…` | `518eca1a…` | non-mover |
| 2 | gol golden | `fcbf7e7c…` | `fcbf7e7c…` | non-mover |
| 3 | lisp `(+ 1 2)` golden | `b3d9f897…` | `b3d9f897…` | non-mover |
| 4 | json_parser golden | `8bda3d5a…` | `8bda3d5a…` | non-mover |
| 5 | mud server golden | `66c8f0ab…` | `66c8f0ab…` | non-mover |
| 6 | mud client golden | `93147d0f…` | `93147d0f…` | non-mover |
| 7 | mi_matrix frozen 25 | 25/0 | 25/0 | non-mover |
| 8 | oob trap rc | 133/empty | 133/empty | non-mover |
| 9 | examples 26 run md5s | (table §2.4) | identical | non-mover |
| 10 | stdlib run_fixtures | 292/0 (v103) | 294/0 | non-mover (+2 noise fixtures) |
| 11 | std_noise crosscheck grid | PASS | **FAIL `Z98-NE-REF:grid`** | **mover — T1D-owned** (workaround literals; §2.5) |
| 12 | 8 dump pins (4 entries × 2 modes) | (QUICK_REF v103) | identical | non-mover |
| 13 | markers gol | 3437 / 38408 | 3437 / 38408 | non-mover |
| 14 | z9play `main.zig` Linux dump | `23f9b5ec…` | `47f1691c8d1f5041e4bd7208e50ed65d` | **mover — migrated** |
| 15 | z9play `ui.zig` Linux dump | `76d0fc83…` | `7395dad777efe7fb8417fc1e57d64235` | **mover — migrated** |
| 16 | z9play `main.zig` `-osw` dump | `6cd349b5…` | `92b9ae90148e037f8e3a0ead6ef30538` | **mover — migrated** |
| 17 | z9play `ui.zig` `-osw` dump | `294e3fde…` | `cbe3cfa6bb70d1b0b2161a37a4fdf400` | **mover — migrated** |
| 18 | tier fixed-point compiler pin (tui/flac/stream) | `b299b4b4…` | `21c957730d268f1e7883176fa5413b65` | **mover — migrated** |
| 19 | exact `--pcm` WAV pin | `e7f24870…` (352844 B) | `e7f24870…` (352844 B) | non-mover |
| 20 | `testdata/expected/*.pcm` goldens | pass | pass | non-mover |
| 21 | `*.meta` / `*.setup` goldens | pass | pass | non-mover |
| 22 | compiler fixed point | `b299b4b4…` (v103 era) → T1F `21c95773…` | `21c95773…` | unchanged by T1C (moved in T1B/T1F) |
| 23 | archive md5 | `c4d1e7a6…` (v103) | `cfe7fe31edd16a526d549201dfbd7c2b` (v104) | rotation |
| 24 | lib manifest | 33 files / `74771fa9…` | 34 files / `3e8b6f6628973414425c1df63f8c4455` | rotation + count truth-up |

## 8. Concerns

1. **`std_noise` crosscheck red until T1D (by design).** v104 archives the
   tree with the held-Task-1 workaround literals in `sf/src/std_noise.zig`;
   `run_crosscheck std_noise` fails the Z98-vs-ref grid under corrected
   rounding (§2.5, root-caused and probe-verified). T1D restores the canonical
   literals and rotates v105. Nothing else in the battery depends on it
   (`verify_stdlib` fixtures 294/0, PGM golden stable under u8 quantization).
2. **Tier fixed-point pins expect the FIXED-POINT binary.** `tier_tui/flac/stream`
   assert `md5(zig1_5_clean) == 21c95773…`. That holds for post-rotation
   `build_from_seed.sh` output (hop1 == hop2 == fixed point) and for a direct
   hop2 binary. The pre-rotation T1C build's `zig1_5_clean` is hop1
   (`a5351087…`, moving-point artifact) and would fail the pin — use
   `<out>/hop2/zig1_hop2` or the rotated archive. Recorded in the tiers'
   comments ("rebuild from the committed archive").
3. **Windows native/hardware verification remains operator-pending** (inherited
   Amendment 5 boundary; `tier_win9x` proves PE/import + wine parity only).
4. **`Z98_NAN` still has no end-to-end runtime pin** (inherited T1F note 3 —
   NaN unreachable from a Z98 literal; out of T1C scope).

## 9. Checklist

- [x] Step 1: rebuild `/tmp/m2_t1c_build` (hop1 `a5351087…`; fixed point `21c95773…`, unchanged vs T1F)
- [x] Step 2: full battery (corpus 0 movers; goldens 5/5; mi25+oob; examples 26/26; stdlib 294/0 + std_noise mover recorded; 8 pins 0 movers; markers 0 movers) + all 9 z9play tiers measured; every mover old→new recorded (§7)
- [x] Step 3: z9play migrated (measured movers only; `floor.zig` untouched; goldens non-movers untouched); tiers re-verified green
- [x] Step 4: `archive_seed.sh` count 33→34 (+ comment/list prose)
- [x] Step 5: seed v104 rotated + verified (two-hop closure, manifest 34)
- [x] Step 6: three commits (`8bb1361d`, `de9258ba`, this)
