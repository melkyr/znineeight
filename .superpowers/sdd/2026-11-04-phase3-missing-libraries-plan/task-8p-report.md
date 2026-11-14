# Task 8p report: z9git performance/RAM profile on a ~1 MB real repo

Status: **DONE** (measure-only; no fixes, no T8b/sf/seed changes).

Base: `1442f8ad` (T8b core kept: `59a9133c`, `d08d07ab`, `5334c762`,
`1442f8ad`; seed v138).  The measurement used a detached worktree at
`1442f8ad` so the pre-existing uncommitted T8b-remaining changes in the main
worktree were neither measured nor touched.

Commits: one docs/test commit containing this report and
`examples/z98/z9git/tests/profile_small.sh` (see `git log -1`).

## Build / environment

| item | value |
|---|---|
| seed | `release/seed/zig1-seed.tgz` v138, md5 `9aef8a6a00bafd3f8f08db96c5ff889b` |
| compiler | `/tmp/t8p_build/zig1_5_clean`, md5 `cf68f192900e7f6618c11e1712b74b3a` |
| two-hop closure | `cf68f192…` == hop1 == hop2 |
| app emit | `zig1_5_clean -ffast -o <dir> examples/z98/z9git/main.zig` |
| app link | emitted `build_target.sh linux` (gcc 12.2.0, `-m32 -O0`) |
| profile builds | same emitted C, gcc wrapper adds `-g` (callgrind) / `-g -pg` (gprof) |
| host | Linux x86_64, 16 CPUs, 31 GB RAM; git 2.39.5; valgrind 3.19.0; gprof 2.40 |
| not installed | `strace`, `perf` |

The emitted `build_target.sh` is `-O0`; the numbers below are `-O0` C from the
`-ffast` compiler mode.  `-fsafe` was not run first: the brief says profile
`-ffast` when it is considerably slower than the local tool, and memcheck was
clean (below), so there was no OOB/UB reason to switch.

## Step 1: repo selection

Selected a real, non-archived, ~1 MB repository:

| field | value |
|---|---|
| repo | `jwiegley/git-from-the-bottom-up` |
| URL | `https://github.com/jwiegley/git-from-the-bottom-up.git` |
| GitHub API size | **1203 KB** (`https://api.github.com/repos/jwiegley/git-from-the-bottom-up`) |
| default branch / HEAD | `master` / `02d22a0124dcf74319e4041ea09746c0f2c929a8` |
| archive (curl) | `https://codeload.github.com/jwiegley/git-from-the-bottom-up/tar.gz/refs/heads/master`, 776,086 bytes |
| system pack | 1,237,697 bytes, idx 10,256 bytes, **328** objects |
| app HTTPS pack | 1,254,600 bytes, idx 11,768 bytes, **382** objects (see ref over-fetch below) |
| worktree | 43 tracked files, no symlinks/gitlinks |

System HTTPS clone, app HTTPS clone, system local clone, and app local clone all
produce the same HEAD.  `git verify-pack` accepts both the system and app idx
files.

## Step 2: system baseline

`/usr/bin/time -v`; network rx is `/proc/net/dev` non-loopback bytes before and
after (container-wide, so treat as ± small background traffic).  Three timed
runs for clone; medians shown.  The medians were post-processed from the
harness's raw `numbers.tsv`; the script records each timed run and does not
compute medians itself.

| operation | wall | max RSS | network rx | notes |
|---|---:|---:|---:|---|
| `git clone` local (from mirror) | 0.01 s | 5.8 MB | 0 | |
| `git clone` HTTPS | 0.99 s | 17.4 MB | 1,266,441–1,267,903 B | 328-object pack |
| `git ls-remote` HTTPS | 0.39 s | 17.1 MB | 7,948–8,002 B | 37 advertised refs |
| `git ls-remote` local | 0.00 s | 4.0 MB | 0 | |
| `curl` archive | 0.62–0.79 s | 12.9–13.1 MB | 802,057–802,440 B | `size_download=776,086` |

The local mirror is 2.6 MB on disk (`git count-objects -vH`: 1.19 MiB pack,
328 in-pack objects).

## Step 3: app (`-ffast`) results

| operation | wall | max RSS | network rx | notes |
|---|---:|---:|---:|---|
| app clone local, `--arena-mb 32` | **0.28 s** (0.28–0.55) | **5.6 MB** | 0 | 43 files checked out |
| app clone local, `--arena-mb 16` | 0.26 s | 5.5–5.6 MB | 0 | |
| app clone HTTPS, `--arena-mb 32` | **3.14 s** (3.13–3.66) | **8.7 MB** | 1.27–1.29 MB | 382-object pack |
| app clone HTTPS, `--arena-mb 16` | 3.34–3.70 s | 8.9–9.1 MB | 1.27 MB | |
| app `-h` / exit paths | unchanged | — | — | not profiled |

Against system git, HTTPS is ~3.2× slower wall (3.14 s vs 0.99 s) while using
about half the RSS.  Local clone is ~28× slower in wall (0.28 s vs 0.01 s) but
still sub-second.  The same repo was used for system and app in every row.

**Ref over-fetch:** the app requests every advertised ref, including
`refs/pull/*` (37 advertised refs, 36 installed), so it downloads 382 objects /
1,254,600 B.  `git clone` fetches heads/tags only: 328 objects / 1,237,697 B.
That is +54 objects (+16%) and ~17 KB of pack/network for this repo.  The extra
objects explain most of the app-vs-system network difference.

### Per-phase wall (temporary instrumentation, removed)

Timers used `std_time.highRes()` and `@stderrWrite`; no logic changed and the
instrumentation exists only in the `/tmp` worktree.

Local clone (`--arena-mb 32`, two runs):

| phase | wall |
|---|---:|
| copy packs | 8 ms |
| copy refs/HEAD/meta | 12 ms |
| store open (idx load + pack SHA-1) | 80–88 ms |
| resolve HEAD/tree | 0 ms |
| checkout (materialize tree) | 234–259 ms |
| **total** | **335–366 ms** |

HTTPS clone (`--arena-mb 32`, two runs):

| phase | wall |
|---|---:|
| TCP+TLS for ref discovery | 210–229 ms |
| ref discovery GET | 110–140 ms |
| TCP+TLS for upload-pack POST | 208–215 ms |
| pack download (incl. 1.27 MB body) | **2015–2072 ms** |
| trailer verify + idx synthesis | 366–561 ms |
| install refs | 0.11–0.30 s |
| checkout | 313–552 ms |
| **total** | **3.34–4.03 s** |

The HTTPS split is dominated by the pack download, but callgrind shows most of
that is CPU in AES-GCM/GHASH, not network wait: the body is only ~1.27 MB.

## Step 4: RAM drivers

Arena-used samples at phase boundaries (`Arena.used`, bytes):

| phase | local | HTTPS |
|---|---:|---:|
| after TLS/refs | — | 114–119 KB |
| after second TLS | — | 125 KB |
| after copy packs / pack download | 132 KB | 1,175 KB |
| after meta / idx synthesis | 395 KB | 2,224 KB |
| after store open | 1,455 KB | — |
| after resolve | 1,457 KB | — |
| after checkout | 4,006 KB | 5,843 KB |

Drivers:

- **1 MiB `std_http` stream buffer** (`STREAM_BUF_BYTES`,
  `sf/src/std_http.zig:487,771`) — explains the HTTPS pack-download arena jump
  to ~1.17 MB.
- **1 MiB pack window** (`WINDOW_SIZE`, `pack.zig:385,432`) — allocated by
  `packOpen`/`packOpenRaw`; explains the ~1 MB jump at store-open / idx
  synthesis.
- **External idx scratch/cache** — 16 MiB scratch + 8 MiB base cache at the
  32 MiB arena (`pack.zig:1311-1322`), allocated via `mmap` outside the arena.
  They are reserved but mostly untouched on this 1.2 MB pack, so peak RSS stays
  ~8.7 MB rather than 32 MiB.
- **Checkout retention** — object store cache/per-object reads grow the arena by
  ~2.55 MB local and ~3.62 MB HTTPS.  At 328–382 objects this is small; the
  T8b O(objects) concern is not stress-tested by this repo.
- Peak RSS is **5.6 MB local / 8.7 MB HTTPS** at `--arena-mb 32`, and 5.5 MB /
  8.9–9.1 MB at `--arena-mb 16`; the 16 MiB minimum is not a limiter here.

## Profiling: top functions and std/app split

Callgrind totals: **1.77 G** instructions (local) and **41.1 G** (HTTPS).
HTTPS is ~32,000 instructions per downloaded byte, almost all in the constant-
time GHASH implementation.

### Callgrind self-cost, local clone

| function | module | self |
|---|---|---:|
| `sha1Block` | std_crypto | 29.53% |
| `rotl32` | std_crypto | 22.64% |
| `mask` | std_crypto | 14.15% |
| `readAt` | pack (app) | 5.98% |
| `sha1Update` | std_crypto | 5.43% |
| `bFill` | std_deflate | 4.72% |
| `decodeBlock` | std_deflate | 2.88% |
| `adler32` | std_deflate | 2.62% |
| `decodeSym` | std_deflate | 2.62% |
| `buildHuff` | std_deflate | 1.32% |

Inclusive: `materializeTree` 91.7%, `sha1Update` 73.5%, `storeOpen` 41.3%
(`packOpen` streams SHA-1 over the whole pack), `readEntry`/`decompressEntry`
22.5%.

### Callgrind self-cost, HTTPS clone

| function | module | self |
|---|---|---:|
| `ghashMulX` | std_cipher | 50.70% |
| `ghashMulX4` | std_cipher | 20.18% |
| `ghashMulH` | std_cipher | 8.09% |
| `sha1Block` | std_crypto | 3.76% |
| `rotl32` | std_crypto | 2.88% |
| `i31Montymul` | std_ecc | 2.57% |
| `mask` | std_crypto | 1.82% |
| `sha1Update` | std_crypto | 0.99% |
| `crc32Update` | std_crypto | 0.95% |
| `readAt` | pack (app) | 0.77% |

Inclusive: TLS path 84.3%, `httpPostStreamOver` 83.1%, AES-GCM open 80.2%,
`ghashUpdate` 79.2%, `idxSynthesize` 8.1%, SHA-1 9.6%, ECC 2.6%.

### std-lib vs app split (callgrind self)

| bucket | local | HTTPS |
|---|---:|---:|
| std_cipher (AES-GCM) | 0% | **80.27%** |
| std_crypto (SHA-1/CRC) | **71.75%** | 10.44% |
| std_ecc (P-256/P-384 ECDSA verify) | 0% | 3.65% |
| std_deflate | 18.66% | 2.30% |
| std_tls | 0% | 0.48% |
| std_http | 0% | 0.11% |
| std_file | 0.77% | 0.08% |
| **app modules** (pack/httpgit/repo/objects/delta) | **6.23%** | **2.18%** |
| unknown (gcc/libc/PLT) | 2.59% | 0.49% |

The application code is a small fraction of both profiles; std-lib crypto/TLS
and deflate dominate.  The HTTPS `std_ecc` cost is certificate-chain ECDSA
verification (the callgrind call counts show two P-256 and two P-384 verifies);
the TLS key exchange is x25519 and is ~0.1% of instructions.

### gprof corroboration (`-g -pg` build)

These numbers come from the `-g -pg` variant built by the gcc wrapper, not from
the timed `-ffast` binary.

- Local: `sha1Block` 27.3%, `mask` / `rotl32` / `sha1Update` 18.2% each;
  37,294 `sha1Block` calls, 8.35 M each of `rotl32`/`mask`; `decodeSym`
  594,304 calls.
- HTTPS: `ghashMulX` 43.8% (10.17 M calls), `ghashMulX4` 19.3% (2.54 M),
  `ghashMulH` 7.7% (79,486), `sha1Block` 6.4% (110,229), ECC `i31Montymul`
  3.0%.  gprof user CPU was 2.33 s, ~1.65 s of it GHASH.

### Valgrind / other tools

`valgrind --tool=memcheck --error-exitcode=99 --leak-check=summary` on local and
HTTPS clones: **0 errors from 0 contexts** both.  `strace` and `perf` are not
installed; callgrind + gprof + valgrind were used instead.  The harness also
runs `strace -c` / `perf stat` automatically when those tools are present.

## Data-backed T8b fix list (no fixes made)

1. **HTTPS CPU: AES-GCM GHASH.** 80.3% of HTTPS instructions, ~1.65 s of the
   ~2.33 s measured CPU.  `ghashMulX`/`X4`/`H` are the top three self-cost
   functions.  A PCLMUL/table GHASH or an optimized AES-GCM path is the largest
   HTTPS win; a release `-O2` emitted build would also help because the current
   script is `-O0`.
2. **Checkout is O(objects).** `materializeTree` is 91.7% inclusive locally;
   SHA-1 verification is 73.5% inclusive and `readTyped`/`storeReadTyped` 57.8%.
   Checkout takes 234–259 ms local / 313–552 ms HTTPS and grows the arena by
   2.55/3.62 MB.  Supports the T8b per-file checkout scratch, streaming
   `storeReadTo`, and cache invalidation.
3. **`storeOpen` hashes the whole pack and loads the whole idx.** `packOpen`
   is 41.0% inclusive locally, 80–88 ms, and the arena goes from 132 KB to
   1.46 MB.  At 1 MB this is tolerable; at git/git scale it is O(pack)+O(idx).
   Supports the bounded idx reader and a lazy/skipped whole-pack hash decision.
4. **1 MiB fixed arena buffers.** `std_http` stream buffer + pack window are
   each 1 MiB.  They fit the 16 MiB minimum here but are fixed costs; smaller
   or adaptive buffers are a straightforward RAM reduction.
5. **Ref over-fetch.** The app wants every advertised ref including
   `refs/pull/*` (382 vs 328 objects, +16%), while system `git clone` fetches
   heads/tags only.  Filtering wants to heads/tags (or HEAD) matches the
   baseline and reduces pack size/network slightly.
6. **Large-repo items remain unexercised at 1 MB.** Large-object allocation,
   symlink/gitlink materialization, Content-Length disk preflight, thin-pack
   handling, and the git/git-scale O(idx)/O(objects) failures cannot be
   reproduced with this repo.  The 1 MB profile confirms the fixed buffers,
   idx/checkout retention, and SHA-1/GHASH costs that underlie those items, but
   the remaining T8b work is still needed for the large cases.

## Harness

`examples/z98/z9git/tests/profile_small.sh` reproduces the measurement
categories and records the listed repo facts:

- records the source path, HEAD, and requires a clean `SRC` tree before
  measuring;
- records the GitHub API size, clones a system HTTPS mirror, runs system local
  and HTTPS clones, `ls-remote`, and the curl archive with `/usr/bin/time -v`
  wall/RSS plus `/proc/net/dev` rx bytes;
- writes the HEAD, pack size, idx size, in-pack object count, and
  `git verify-pack` result for the mirror and app clones to `facts.tsv`;
- builds the app with `-ffast` through the emitted `build_target.sh` and runs
  local/HTTPS clones at 32 MiB and 16 MiB (`RUNS` repetitions);
- builds `-g` / `-g -pg` variants by prepending a gcc wrapper on `PATH` (the
  emitted script and sources are untouched), then runs callgrind, gprof, and
  memcheck, plus `strace -c` / `perf stat` when installed; memcheck failures
  are propagated (nonzero exit) after the `ERROR SUMMARY` capture;
- env: `ZIG`, `OUT`, `SRC`, `URL`, `NET` (0 reuses a mirror), `RUNS`,
  `ARENA_MB`, `DEEP`.

The temporary per-phase timers and arena prints were used only in the `/tmp`
measurement worktree and are **not** committed; this commit is the harness and
this report only.

## Concerns / limitations

- The main worktree already contained uncommitted T8b-remaining changes in
  `examples/z98/z9git/{httpgit,objects,pack,repo}.zig` and `tests/tier_git.sh`.
  They were not touched and not measured; all numbers are from `1442f8ad`.
- Network variance is visible: one later full-harness app HTTPS run took 6.4 s
  versus the 3.13–3.66 s three-run set; system HTTPS was 0.96–1.07 s.  Ratios
  are indicative, not a benchmark of the network.
- `/proc/net/dev` counters are container-wide and include small background
  traffic; pack/idx sizes are exact.
- The emitted C is `-O0`; no `-O2` measurement was taken (it was outside the
  brief and would change the performance, though not the logic).
- No `-fsafe` run was needed: `-ffast` was profiled per the brief and memcheck
  reported 0 errors.  If a conservative timing number is wanted later, a
  `-fsafe` build can be added to the same harness.
