# Task 4 report — Milestone 1 closeout (full std battery + seed v136)

**Status:** COMPLETE. Seed rotated to v136, fixed point unchanged, docs truth-up landed.

**Repo/HEAD at start:** `/workspace/znineeight`, branch `zig1_improvements`, HEAD `315939a2`.

## 1. Build closure from the v135 seed

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t4_base
```

- hop1 `cf68f192900e7f6618c11e1712b74b3a`
- hop2 `cf68f192900e7f6618c11e1712b74b3a`
- two-hop closure OK: hop1 == hop2 == `cf68f192…` (expected; no STOP).

Built compiler + runtime lib: `/tmp/p3_t4_base/zig1_5_clean` (52-file `lib/`).

## 2. Full std battery

```
bash scripts/stdlib/verify_stdlib.sh /tmp/p3_t4_base/zig1_5_clean
```

- `run_fixtures: 356 PASS / 0 FAIL over 356 dirs`
- `run_crosscheck: 10 PASS / 0 FAIL over 10 modules`
- `STDLIB GATE OK`
- `scripts/stdlib/expected_dirs.txt`: **356** non-comment entries (361 lines
  including the 5-line header).

## 3. Anchor gates

- `scripts/compiler/gate_lower_depth.sh /tmp/p3_t4_base/zig1_5_clean`:
  `LOWER_DEPTH GATE OK`; case 5 pins 8/8 unmoved (`mud`, `gol`, `lisp`, `json`
  pairs). md5-comparison sub-cases (6/8/9/10-12) SKIP without
  `GATE_BASELINE_ZIG1`, as permitted; no baseline env was set.
- `scripts/check_emit_support.sh /tmp/p3_t4_base/zig1_5_clean`:
  `OK: 8/8 support files byte-identical to canonical`.
- Frozen-1124 subset: **1124 lines**, md5
  `518eca1a9b5d3e1cc5a48abce214abd8`, tally `950 OK / 58 GREEN / 116 FAIL /
  0 ICE / 0 CRASH`, **0 movers**. The repo classifier
  (`scripts/corpus/classify`) only accepts the live universe list, so a
  temporary helper (`/tmp/frozen_classify.sh`) replaying the same classifier
  logic over `scripts/corpus/frozen_1124.txt` was used to honour the "do not run
  the full live corpus" constraint. Output was `LC_ALL=C sort`-normalised before
  md5. No repo file was transformed.
- `git diff --check`: clean (rc 0).

The full live corpus was **not** run (Task 9 owns it).

## 4. Seed v136 rotation

```
bash scripts/seed/archive_seed.sh /tmp/p3_t4_base/zig1_5_clean /tmp/p3_t4_base/gen \
  release/seed/zig1-seed.tgz --update-changelog \
  --win9x-zip release/seed/zig1_seed_w9.zip
```

Artifacts (verified):

| field | value |
|---|---|
| archive md5 | `d0f1d191689ad996bedcade688de1f2b` |
| zip md5 | `8fc02b8123ab04fac77ab8932ac60beb` |
| archived binary md5 / fixed point | `cf68f192900e7f6618c11e1712b74b3a` (unchanged) |
| gcc-of-archive-C fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| `gen/` | 48 `.c` + 49 `.h`, 12,473,249 bytes |
| `lib/` | 52 std `.zig` (`std.zig` + 51 `std_*.zig`, adds `std_deflate.zig`) |
| manifest md5 | `1906480f9b15dcd4e152cf8c247f2e61` (changed because a std file was added) |
| Win9x `win/` | 52 `.c` + 51 `.h` |

Extra checks: extracted `lib/` contains 52 `.zig`; recomputed
`manifest.md5` is self-consistent with the archive and lists `std_deflate.zig`
(`a19add64fab3f298bb4b5407e6d26e19`). Zip contains `zig1-seed-w9/{README.txt,
lib/, win/}` with 52 `.zig` and the manifest.

Rebuild from the **new** archive:

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t4_new
```

- hop1 == hop2 == `cf68f192900e7f6618c11e1712b74b3a` — closure confirmed.

## 5. CHANGELOG v136 entry

`archive_seed.sh` produced the factual provenance table but omitted the
Milestone-1 narrative/battery details. The entry was augmented (via `edit`) to
state, accurately:

- `std_zstd` RFC 8878 dictionaries via `zstdDecompressDict` (full RFC 8878;
  `zstdDecompress` unchanged and still rejects dict frames).
- New `std_deflate` inflater (`inflateRaw` / `inflateZlib`, mandatory `used`).
- `std_http` POST + streaming sink (`httpPostOver`, `httpPostStreamOver`,
  `ResponseSink`, `post`).
- Battery **356 PASS / 0 FAIL** over 356 fixtures + crosscheck **10/10**.
- `lib/` **52** std `.zig`; fixed point unchanged.

No unmeasured claim was added.

## 6. Docs truth-up

- `docs/sf/QUICK_REF.md` — seed block now v136 (archive/zip/fixed-point/lib/
  manifest hashes), module counts 51→52, new API paragraph for
  `zstdDecompressDict`, `inflateRaw`/`inflateZlib` (`used`), and
  `httpPostOver`/`httpPostStreamOver`/`ResponseSink`/`post`; seed inventory and
  install command include `std_deflate.zig`; ladder label now v136 (same fixed
  point). Live-corpus numbers are explicitly left to Task 9 with the v135
  baseline named.
- `STD_README.MD` — v136 shipped-seed block, 52-file counts, L4/domain tables,
  `std_deflate` row, zstd dictionary and HTTP POST/stream descriptions, domain
  docs index entries for `deflate.md`/`http.md`; removed the stale
  "compression formats are out of scope" wording.
- `sf/docs/std_lib/zstd.md` — dictionary support added to overview/supported
  subset/offline workflow and a full `zstdDecompressDict` API entry (signature,
  parameters, returns, errors, example, gotchas).
- `sf/docs/std_lib/deflate.md` — new page per `_template.md`
  (`inflateRaw`, `inflateZlib`, boundaries, offline workflow).
- `sf/docs/std_lib/http.md` — new page per `_template.md`. No `std_http` page
  existed in `sf/docs/std_lib/`; the plan explicitly allows "update existing or
  create per `_template.md`", so it was created. Documents `Url`, `Header`,
  `Response`, `HttpError`, `parseUrl`, `percentEncode`, `parseResponse`,
  `HttpTransport`, `ResponseSink`, `httpGetOver`, `httpPostOver`,
  `httpPostStreamOver`, `get`, `post`.
- `docs/sf/manuals/en/vol2-17-stdlib.html` — `std_deflate` row; v136
  zstd-dictionary/deflate/http descriptions; counts recounted: 32 public
  by-path + 5 PAL (37 more `std_*.zig` than the 14 re-exports). The coverage
  sentence lists `std_deflate` separately (indexed with an in-page section) and
  enumerates the other eight public by-path modules outside the companion
  pages, explicitly marking `std_fft` as not yet documented.
- `docs/sf/manuals/en/vol4-18-stdlib.html` — `std_deflate` by-path row and v136
  description paragraph. Table/HTML nesting checked with a Python tag-balance
  pass (0 errors); `git diff --check` clean.

## 7. Commits

- `76b54a10` — `chore(seed): rotate v136 (std_deflate + zstd dicts + http post/stream)`
  (seed artifacts + docs truth-up; explicit paths only; no push).
- Follow-up `docs(sdd)` commit contains this report.

## Deviations / concerns

- The frozen-1124 check used a temporary wrapper with the canonical
  `scripts/corpus/classify` logic restricted to `frozen_1124.txt`, because the
  repo classifier hardcodes the live universe and the brief forbids running the
  full live corpus. Result matches the frozen anchor exactly.
- `sf/docs/std_lib/http.md` did not exist; created under the plan's
  "update existing or create" allowance rather than stopping.
- The live corpus is stale by design in docs (v135 baseline named), pending
  Task 9.
- `archive_seed.sh` records the packaging base HEAD (`315939a2`, pre-rotation)
  in the v136 CHANGELOG/SEED_README provenance, which is accurate for the source
  used to build the binary.

## Fix round 1

Docs-only follow-up at HEAD `7781ced6`; no seed/code changes.

1. **Broken manual link — fixed.** Both `vol2-17-stdlib.html` and
   `vol4-18-stdlib.html` no longer link outside the manual tree to
   `../../../sf/docs/std_lib/deflate.md`. Vol2 links to
   `vol4-18-stdlib.html#deflate`; vol4 links to its own new
   `<a name="deflate"></a>` section. The section summarizes the two signatures,
   `used`, `FDICT` rejection, Adler-32, and the two errors.
2. **Stale current count — fixed.** `QUICK_REF.md:317` now says
   `verify_stdlib` is **356/0 today**; the v123 `336/0`, M7/v103 `294/0`, and
   other older figures remain labelled historical.
3. **Coverage enumeration — fixed.** `vol2-17-stdlib.html` no longer lists
   redundant `std_deflate` among the eight domain-doc-only modules; it lists
   `std_ecc`, `std_asn1`, `std_x509`, `std_tls`, `std_wireguard`, `std_tcpip`,
   `std_cipher`, and `std_fft`, noting the first seven have domain docs and
   `std_fft` is not yet documented. The matching claim in this report was
   corrected above.
4. **Install list — fixed.** The canonical install command now includes
   `sf/src/std_fft.zig` and `sf/src/std_deflate.zig`; an extraction check counts
   **52** unique `.zig` paths (the full `std.zig` + 51 `std_*.zig` set).
5. **Measurement label — fixed.** The spill-ladder paragraph now says it is
   unchanged from v135 (same fixed point `cf68f192…`) and that the numbers were
   measured on the v135 seed on 2026-11-05, not re-measured for v136.
6. **Companion-page wording — fixed.** `vol4-18-stdlib.html` now says the
   by-path library is detailed on four companion pages **plus a fifth
   `Deflate / zlib` area row with its own section on this page**.

Verification:

```
python3 docs/sf/manuals/check.py
check.py: OK - 116 HTML pages, links, rel, lang, forbidden list, figures, no-CSS baseline
```

- `git diff --check`: clean.
- Greps: `356/0` current; install command 52 unique files; no
  `../../../sf/docs/std_lib` links remain in the touched manuals; enumerated
  coverage list matches the sentence.
- No seed rotation, no battery re-run (docs-only). Checker did not require any
  pipeline change.
