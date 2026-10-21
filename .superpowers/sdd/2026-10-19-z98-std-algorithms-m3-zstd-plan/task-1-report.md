# M3 Task 1 report — std_zstd

Status: COMPLETE

Base commit: `9f7828c6` (branch `zig1_improvements`).
Feature commit: `c9af1fa8` `feat(std_zstd): RFC 8878 subset decoder (M3)`.

Final gate summary: `STDLIB GATE OK` (299 fixtures PASS / 0 FAIL; crosscheck
5 PASS / 0 FAIL, including `std_zstd` 30 vectors).

## Tool acquisition

`scripts/stdlib/get_zstd_tools.sh` (new, no-root private apt state, M8 pattern).

Command:

```
TMP=/tmp/zstd sh scripts/stdlib/get_zstd_tools.sh
```

Observed (stdout):

```
zstd: /tmp/zstd/sys/usr/bin/zstd
LD_LIBRARY_PATH: /tmp/zstd/sys/etc:/tmp/zstd/sys/lib/x86_64-linux-gnu:/tmp/zstd/sys/lib64:/tmp/zstd/sys/usr/lib/x86_64-linux-gnu:/tmp/zstd/sys/usr/lib/x86_64-linux-gnu/gconv:/tmp/zstd/sys/usr/share/gdb/auto-load/usr/lib/x86_64-linux-gnu:
zstd_version: *** Zstandard CLI (64-bit) v1.5.4, by Yann Collet ***
```

Acquisition works; a runnable CLI is available without root. The script accepts
the actual version banner (`Zstandard`) as well as lowercase `zstd`.

## Vectors (frozen host-zstd agreement)

29 corpus vectors + `empty` = 30 `.in`/`.expected` pairs under
`scripts/stdlib/vectors/std_zstd/`. Generated through the acquired CLI from
stdin so the frame header carries an explicit window descriptor for every
requested `--zstd=wlog=10..21` (small inputs otherwise become single-segment).
Every `.expected` was produced by `zstd -d` and `cmp`-verified byte-equal to the
original source. Corpus covers text / binary / incompressible, levels `-1` and
`-19`, source blocks 1 KB and 64 KB (window 10 forces 1 KB blocks; window 21
leaves one 64 KB block), and window logs 10-21. All frames carry XXH64 content
checksums; the decoder validates them.

Representative header verification (parser saw standard magic
`28 b5 2f fd`, explicit wlog, checksum flag set, payload fully consumed):

```
text_w10_l1.in   wlog 10  blocks 64  max block content 188
text_w21_l1.in   wlog 21  blocks 1   max block content 1796
binary_w10_l1.in wlog 10  blocks 64  max block content 738
random_w21_l1.in wlog 21  blocks 1   max block content 65536
```

## Implementation

`sf/src/std_zstd.zig` (L4, imports nothing):

- frame magic/header (single-segment + explicit window descriptor, optional FCS,
  dict-id rejected), skippable frames, concatenated frames;
- window-log cap checked from the header before any decode (`WindowTooBig`);
- raw / RLE / compressed blocks, all literal modes (raw/RLE/compressed/treeless,
  1- and 4-stream), custom and predefined FSE, repeat modes, repeat offsets,
  overlap-safe match copies, XXH64 content-checksum validation;
- literals are decoded on demand from the bitstreams (no literal scratch
  buffer); FSE/Huffman tables are function-local; no heap and no allocation
  beyond caller `dst`.

Two implementation defects found by the corpus and fixed during T1:

1. Reverse-bit addressing must account for the partial last byte
   (`last_bit`), not `k / 8`; the first version misread every FSE/Huffman
   stream whose final byte was not full.
2. Huffman symbol ordering must use cumulative *symbol counts* (weight 0
   symbols included) for the `symbols` array, while table-entry offsets
   exclude weight 0. Using entry offsets for both scrambled any FSE-compressed
   Huffman tree that contains weight-0 symbols.

Also relaxed the sequence end check to zstd's semantics: the final FSE state
update may read a bounded amount of zero padding before the stream start; the
decoder accepts `total <= consumed <= total + 64` instead of requiring exact
equality. Extras and all other reads remain strict.

## Tests so far

Build:

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m3_t1_build
```

Seed closure stayed `21c957730d268f1e7883176fa5413b65`.

Targeted fixtures:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m3_t1_build/zig1_5_clean \
  repro/mi_matrix/stdlib_zstd_basic_xmod repro/mi_matrix/stdlib_zstd_cross_xmod
```

Observed:

```
PASS repro/mi_matrix/stdlib_zstd_basic_xmod
PASS repro/mi_matrix/stdlib_zstd_cross_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

Targeted crosscheck:

```
bash scripts/stdlib/run_crosscheck.sh /tmp/m3_t1_build/zig1_5_clean std_zstd
```

Observed:

```
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

`run_crosscheck.sh` now discovers the union of `ref/` and `vectors/` modules and,
for a ref-less module (no `ref/<module>/ref.c`), builds no reference and requires
Z98 exit 0 and Z98 stdout == committed `.expected`.

## Full battery

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m3_t1_build/zig1_5_clean
```

Observed tail:

```
PASS repro/mi_matrix/stdlib_zstd_basic_xmod
PASS repro/mi_matrix/stdlib_zstd_cross_xmod
...
run_fixtures: 299 PASS / 0 FAIL over 299 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 5 PASS / 0 FAIL over 5 modules
STDLIB GATE OK
```

## Import resolvability

`scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` now copy
`std_zstd.zig` into the seed `lib/`. The produced compiler contains it:

```
-rw-r--r-- ... /tmp/m3_t1_build/lib/std_zstd.zig
78571d92335b609e9176608a493f4630  /tmp/m3_t1_build/lib/std_zstd.zig
78571d92335b609e9176608a493f4630  sf/src/std_zstd.zig
```

Both new fixtures `@import("std_zstd.zig")`; their successful emit + gcc + run
under the seed-built compiler is the resolvability proof.

## Stack discipline

No function-local array over 4 KB: `FseTable.entries` is `[512]` of 4-byte
entries (2 KB), `huf_symbols` / `huf_nbits` are `[2048]u8` (2 KB each), and the
remaining locals are `[256]`/`[12]`/`[4]` tables. The entropy tables live in the
single stack `Decoder` and the per-Huffman-tree `FseTable`; there is no heap and
no allocation beyond caller `dst`.

## Files

- new: `sf/src/std_zstd.zig`, `scripts/stdlib/get_zstd_tools.sh`,
  `scripts/stdlib/vectors/std_zstd/*`, both `stdlib_zstd_*_xmod` fixtures,
  `repro/mi_matrix/stdlib_zstd_basic_xmod/vectors_data.zig` (generated frozen
  1 KB vectors, so the basic fixture is self-contained under the harness's
  scratch CWD);
- modified: `scripts/stdlib/expected_dirs.txt`, both seed copy lists,
  `scripts/stdlib/run_crosscheck.sh`.
