# Example Performance Program — Phase 0 Baselines

Evidence log for Task 0 of
`docs/superpowers/plans/2026-11-17-example-performance-program.md`.

- Measured: 2026-11-17
- Host: Linux x86_64 (Debian gcc 12.2.0, 16 logical CPUs); 32-bit gates use
  `gcc -m32 -std=c89`.
- Repo baseline: `4e91d9d1ddd3137edbbb5b93ee3e40efcbcb0859`
- Compiler under test: `release/seed/zig1-seed.tgz`
  (archive md5 `76c12fc49d4e584841233601bfbe658d`) rebuilt to
  `/tmp/perf_seed/zig1_5_clean` (md5 `a2fc81055dc1cb7a67099fe3934d22ee`).
- z9play/z9gb/z9torr use the Phase 0 recipe: `-fsafe` emit plus the emitted
  `build_target.sh linux` link (the linux link is `-m32 -std=c89 -O0`). The
  z9git `profile_small.sh` harness emits `-ffast`
  (`examples/z98/z9git/tests/profile_small.sh:171-174`), also linked by its
  emitted `build_target.sh linux`. These are not the optimized `tier_perf.sh`
  `-O2` numbers.

## Before/after metric table

Later tasks append their "after" value below; keep the measurement recipe
column identical so the comparison is apples-to-apples.

| Metric | Baseline (before) | After | Measurement recipe |
|---|---:|---:|---|
| z9play Vorbis decode rate (audio-s / wall-s) | **10.5** (2.000 s / 0.19 s median) | **10.5** (2.000 s / 0.19 s median) | `/tmp/perf_z9play/prog --wav examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/perf_z9play/ogg.1.wav` |
| z9play FLAC decode rate (audio-s / wall-s) | **15.4** (2.000 s / 0.13 s median) | **14.3** (2.000 s / 0.14 s median) | `/tmp/perf_z9play/prog --wav /tmp/perf_z9play/sine_stereo_44100.flac /tmp/perf_z9play/flac.1.wav` |
| z9gb headless fps (600 frames, min ROM) | **51.4** (600 / 11.68 s median) | **64.0** (600 / 9.37 s median) | `/tmp/perf_z9gb/prog --headless --turbo --no-audio --frames 600 --rom examples/z98/z9gb/testdata/synth/minimal.gb --fb-out /tmp/perf_z9gb/fb.1.bin` |
| z9torr idle CPU % | **99%** (10.00 s window; 9.87–9.88 s user; local tracker + local suspended seed, `rc=124`) | — | `env Z9TORR_SEED=12345 /usr/bin/time -v timeout 10 /tmp/perf_z9torr/prog examples/z98/z9torr/testdata/t2_single_25m.torrent` (full local-seed setup in §4) |
| z9git clone wall time, local mirror | **0.22 s** median (0.22 / 0.22 / 0.49) | — | `ZIG=/tmp/perf_seed/zig1_5_clean SRC=/tmp/perf_z9git_src RUNS=3 DEEP=0 sh examples/z98/z9git/tests/profile_small.sh` |
| z9git clone wall time, HTTPS | **1.70 s** median (1.67 / 1.70 / 1.74) | — | same `profile_small.sh` run, `app_https_*` rows |
| z9git pack SHA-1 / clone throughput | **1.237 MB in 1.70 s ≈ 0.73 MB/s** HTTPS; **1.237 MB in 0.22 s ≈ 5.6 MB/s** local | — | same harness; `pack_bytes=1237697`, `objects=328`, `verify_pack=ok` |
| z9edit frame cost, 5k-line file | **30 full-buffer scans + 26 `lineStartOf` scans/frame ≈ 8.9–11.7 M buffer-byte reads + 986 `gfxDrawText` calls/frame** (80x25, 40 B/line) | — | analytic count from `ui.zig:uiPaint` / `buffer.zig` (no Linux GUI target) |

## 1. Compiler under test

Command (from repo root):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/perf_seed
```

Key output:

```text
[seed] hop1 binary md5: a2fc81055dc1cb7a67099fe3934d22ee
[seed] hop2 binary md5: a2fc81055dc1cb7a67099fe3934d22ee
[seed] two-hop closure OK: hop1 == hop2 == a2fc81055dc1cb7a67099fe3934d22ee
=== [seed] Done: /tmp/perf_seed ===
```

Closure matches the recorded v151 fixed point; no source edits were needed.

## 2. z9play baseline

Build:

```bash
mkdir -p /tmp/perf_z9play
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9play examples/z98/z9play/main.zig
sh /tmp/perf_z9play/build_target.sh linux /tmp/perf_z9play/prog
```

Fixture: `examples/z98/z9play/testdata/sine_stereo_44100.ogg`
(2 ch, 44100 Hz, `duration_s=2.000`).

```bash
/usr/bin/time -v /tmp/perf_z9play/prog --wav \
  examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/perf_z9play/ogg.1.wav
```

Three runs (all `rc=0`, `wav: ended frames=88200 pos_ms=2000 monotonic=1`):

| Run | Wall | User | CPU % | Decode rate |
|---|---:|---:|---:|---:|
| 1 | 0.20 s | 0.18 s | 95% | 10.00x |
| 2 | 0.19 s | 0.18 s | 95% | 10.53x |
| 3 | 0.19 s | 0.18 s | 97% | 10.53x |

Output check: WAV payload vs the committed
`examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm` is within the
existing decode gate (`max_delta=1`, `rms_milli=36`, 352800/352800 bytes):

```bash
tail -c +45 /tmp/perf_z9play/ogg.1.wav > /tmp/perf_z9play/ogg.1.pcm
python3 - /tmp/perf_z9play/ogg.1.pcm \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm <<'PY'
import sys, struct, math
a = open(sys.argv[1], "rb").read()
b = open(sys.argv[2], "rb").read()
n = min(len(a), len(b)) // 2
A = struct.unpack("<%dh" % n, a[:2*n])
B = struct.unpack("<%dh" % n, b[:2*n])
md = max(abs(x - y) for x, y in zip(A, B))
ss = sum((x - y) ** 2 for x, y in zip(A, B))
print("max_delta=%d rms_milli=%d bytes=%d/%d"
      % (md, int(math.sqrt(ss / n) * 1000 + 0.5), len(a), len(b)))
PY
```

FLAC fixture: the committed tree has no `.flac`, so it was generated from the
committed raw PCM golden with the no-root `flac 1.4.2` binary. `get_flac_tools.sh`
only prints its private path and library path, so both are used explicitly:

```bash
TMP=/tmp/perf_flac sh examples/z98/z9play/tests/get_flac_tools.sh
FLAC=/tmp/perf_flac/sys/usr/bin/flac
FLAC_LD=/tmp/perf_flac/sys/etc:/tmp/perf_flac/sys/lib/x86_64-linux-gnu:/tmp/perf_flac/sys/lib64:/tmp/perf_flac/sys/usr/lib/x86_64-linux-gnu:/tmp/perf_flac/sys/usr/lib/x86_64-linux-gnu/gconv:
env LD_LIBRARY_PATH="$FLAC_LD" "$FLAC" -f --force-raw-format \
  --endian=little --sign=signed --channels=2 --bps=16 --sample-rate=44100 \
  -o /tmp/perf_z9play/sine_stereo_44100.flac \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
sha1sum /tmp/perf_z9play/sine_stereo_44100.flac
wc -c /tmp/perf_z9play/sine_stereo_44100.flac
```

Generated fixture: sha1 `14be24c914ff796daf478393931761d575d76fa5`,
size 74017 B, md5 `77f597f4a7ceeff707c133928e17c188`. Decode it back with the
same private binary and compare byte-for-byte:

```bash
env LD_LIBRARY_PATH="$FLAC_LD" "$FLAC" -f -d --force-raw-format \
  --endian=little --sign=signed \
  -o /tmp/perf_z9play/flac_golden.pcm \
  /tmp/perf_z9play/sine_stereo_44100.flac
cmp /tmp/perf_z9play/flac_golden.pcm \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
sha1sum /tmp/perf_z9play/flac_golden.pcm \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
```

Both decode to `0e31277ffee2bd62a707fc9732e9eb7281da58df`; `cmp` is silent
(byte-identical).

| Run | Wall | User | CPU % | Decode rate |
|---|---:|---:|---:|---:|
| 1 | 0.13 s | 0.12 s | 96% | 15.38x |
| 2 | 0.13 s | 0.12 s | 96% | 15.38x |
| 3 | 0.13 s | 0.12 s | 96% | 15.38x |

Output check: FLAC WAV payload is byte-exact vs the golden PCM:

```bash
tail -c +45 /tmp/perf_z9play/flac.1.wav > /tmp/perf_z9play/flac.1.pcm
cmp /tmp/perf_z9play/flac.1.pcm \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
sha1sum /tmp/perf_z9play/flac.1.pcm \
  examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
```

Both sha1s are `0e31277ffee2bd62a707fc9732e9eb7281da58df`; `cmp` is silent.

Rerun command for later tasks:

```bash
/usr/bin/time -v /tmp/perf_z9play/prog --wav <fixture> /tmp/perf_z9play/out.wav
```

Derive `decode-rate = fixture_duration_s / elapsed_wall_s`.

## 3. z9gb baseline

Build:

```bash
mkdir -p /tmp/perf_z9gb
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9gb examples/z98/z9gb/main.zig
sh /tmp/perf_z9gb/build_target.sh linux /tmp/perf_z9gb/prog
```

ROM: `examples/z98/z9gb/testdata/synth/minimal.gb`
(32768 B, sha256 `6e110337c4e336d0a4740d987fb3a3020c7a06b441536b575850f66889b04dc6`).
This committed synthetic ROM is the controller-specified deterministic test
fixture; it needs no external ROM download, and its hash is recorded here so
the same bytes are reused.

```bash
/usr/bin/time -v /tmp/perf_z9gb/prog --headless --turbo --no-audio \
  --frames 600 --rom examples/z98/z9gb/testdata/synth/minimal.gb \
  --fb-out /tmp/perf_z9gb/fb.1.bin
```

| Run | Wall | User | CPU % | fps (600 / wall) |
|---|---:|---:|---:|---:|
| 1 | 11.80 s | 11.66 s | 98% | 50.85 |
| 2 | 11.68 s | 11.67 s | 99% | 51.37 |
| 3 | 11.61 s | 11.60 s | 99% | 51.68 |

Each run produced a 92160-byte framebuffer with the same sha256
(`2b8eb9b578d14f956ac179bcefe26788075fe7041c1401c05ae283e109d2bfa9`).

Rerun command for later tasks: same command; `fps = 600 / elapsed_wall_s`.

Note: `tier_perf.sh` builds its own `-O2` variant and is a different number; the
Phase 0 before/after series uses the `-fsafe -O0` command above.

## 4. z9torr idle CPU baseline

Idle setup: a local `mock_tracker` advertises two loopback peers: a
`mock_blackhole_peer` (accepts TCP, never speaks) and a `mock_mse_peer` (a real
local seeder for the t2 payload). After 2 s the seeder process is suspended with
`SIGSTOP`; its TCP connection and coroutine stay live, so the client runs the
full 10 s window with `peers=2`, `0KB/s`, and no progress.

Make the local seed payload with the same `mawk` recipe as
`tests/mkfixture.sh` (its SHA-1 must equal the committed t2 golden):

```bash
awk -v seed=2 -v size=26214400 \
  'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' \
  > /tmp/perf_z9torr/t2.payload
sha1sum /tmp/perf_z9torr/t2.payload
cat examples/z98/z9torr/testdata/expected/t2_single_25m.sha1
```

Both are `00fcf3e712b1271e12542032a2797248590673d3`. Build the client and the
three existing helper tools with the binding seed recipe:

```bash
mkdir -p /tmp/perf_z9torr
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9torr examples/z98/z9torr/main.zig
sh /tmp/perf_z9torr/build_target.sh linux /tmp/perf_z9torr/prog

mkdir -p /tmp/perf_z9torr/mock_tr /tmp/perf_z9torr/mock_bh /tmp/perf_z9torr/mock_mse
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9torr/mock_tr examples/z98/z9torr/tools/mock_tracker.zig
sh /tmp/perf_z9torr/mock_tr/build_target.sh linux /tmp/perf_z9torr/mock_tr/prog
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9torr/mock_bh examples/z98/z9torr/tools/mock_blackhole_peer.zig
sh /tmp/perf_z9torr/mock_bh/build_target.sh linux /tmp/perf_z9torr/mock_bh/prog
/tmp/perf_seed/zig1_5_clean -fsafe -o /tmp/perf_z9torr/mock_mse examples/z98/z9torr/tools/mock_mse_peer.zig
sh /tmp/perf_z9torr/mock_mse/build_target.sh linux /tmp/perf_z9torr/mock_mse/prog
```

Reset ports, then run one 10 s sample (the `kill -STOP` must target the
`mock_mse_peer` process, not a `timeout` wrapper):

```bash
pkill -f 'mock_tr/prog|mock_bh/prog|mock_mse/prog|perf_z9torr/prog' || true
cd /tmp/perf_z9torr
rm -rf idle_run && mkdir idle_run
./mock_tr/prog --port 6969 --peers 127.0.0.1:6991,127.0.0.1:6970 > idle.tr.log 2>&1 & TR=$!
./mock_bh/prog --port 6991 > idle.bh.log 2>&1 & BH=$!
./mock_mse/prog --port 6970 --file /tmp/perf_z9torr/t2.payload \
  --piece-length 262144 --info-hash 7e01c65cc1c75f4e82f023782927a1eb6d9239f5 \
  > idle.pe.log 2>&1 & PE=$!
sleep 1
( cd idle_run && env Z9TORR_SEED=12345 /usr/bin/time -v timeout 10 ../prog \
    /workspace/znineeight/examples/z98/z9torr/testdata/t2_single_25m.torrent \
    > ../idle.out 2> ../idle.time ) & CL=$!
sleep 2
kill -STOP "$PE"
wait "$CL"; RC=$?
kill -CONT "$PE" 2>/dev/null; kill "$TR" "$BH" "$PE" 2>/dev/null
echo "client_rc=$RC"
grep -E 'Elapsed|User time|System time|Percent of CPU|Maximum resident' idle.time
tail -1 idle.out
```

Three runs (each killed by the 10 s `timeout`, hence `rc=124`):

| Run | Wall | User | Sys | CPU % | Result |
|---|---:|---:|---:|---:|---|
| 1 | 10.00 s | 9.87 s | 0.12 s | 99% | rc=124, `0.0% ... 0KB/s peers=2` |
| 2 | 10.00 s | 9.87 s | 0.12 s | 99% | rc=124, `0.0% ... 0KB/s peers=2` |
| 3 | 10.00 s | 9.88 s | 0.11 s | 99% | rc=124, `0.0% ... 0KB/s peers=2` |

This is the full 10 s idle busy-wait baseline Task 9 must drive well below 100%.
Cleanup/port check after a run:

```bash
pkill -f 'mock_tr/prog|mock_bh/prog|mock_mse/prog|perf_z9torr/prog' || true
for p in 6969 6970 6991; do
  (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && echo "busy $p"
done
```

Secondary context measurement (real local MSE seeder, not the idle metric):
the same t2 torrent served by `tools/mock_mse_peer.zig` without `SIGSTOP`
completed 26214400 B in 16.00 s wall at 71% CPU (~1.64 MB/s, exit 0, payload
sha1 matched the golden). This is a throughput observation, not the idle
baseline.

## 5. z9git throughput baseline

Harness (existing, unmodified):

```bash
ZIG=/tmp/perf_seed/zig1_5_clean OUT=/tmp/perf_z9git \
SRC=/tmp/perf_z9git_src RUNS=3 DEEP=0 \
sh examples/z98/z9git/tests/profile_small.sh
```

`SRC` must be a clean git tree; a throwaway `/tmp/perf_z9git_src` repo was used
because the working tree contains the untracked plan:

```bash
rm -rf /tmp/perf_z9git_src
mkdir -p /tmp/perf_z9git_src
git -C /tmp/perf_z9git_src init -q
git -C /tmp/perf_z9git_src config user.email perf@example.invalid
git -C /tmp/perf_z9git_src config user.name perf
printf 'z9git perf baseline source marker\n' > /tmp/perf_z9git_src/README
git -C /tmp/perf_z9git_src add README
git -C /tmp/perf_z9git_src commit -qm 'perf baseline source marker'
git -C /tmp/perf_z9git_src status --porcelain
```

`profile_small.sh` emits the app with `-ffast`
(`examples/z98/z9git/tests/profile_small.sh:171-174`) and links via its emitted
`build_target.sh linux`. `DEEP=0` skips the callgrind/gprof/memcheck section;
the timed clone/hash rows are unchanged.

Remote: `https://github.com/jwiegley/git-from-the-bottom-up.git`
(mirror HEAD `02d22a0124dcf74319e4041ea09746c0f2c929a8`).

| Row | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| `sys_https_clone` | 5.35 s | — | — | 5.35 s |
| `sys_local_clone` | 0.01 s | — | — | 0.01 s |
| `app_local` (32 MB arena) | 0.22 s | 0.22 s | 0.49 s | **0.22 s** |
| `app_local16` (16 MB arena) | 0.22 s | 0.22 s | 0.47 s | 0.22 s |
| `app_https` (32 MB arena) | 1.67 s | 1.70 s | 1.74 s | **1.70 s** |
| `app_https16` (16 MB arena) | 1.67 s | 6.82 s | 4.07 s | 4.07 s |

Clone facts for both `app_local_1` and `app_https_1`:
`pack_bytes=1237697`, `idx_bytes=10256`, `objects=328`, `verify_pack=ok`,
same HEAD as the mirror. The HTTPS rows vary with the network; the local-mirror
row is the stable comparison point. Wall time includes the pack SHA-1
verification done by z9git.

Artifacts: `/tmp/perf_z9git/{numbers.tsv,facts.tsv,logs/,times/}`.

## 6. z9edit frame-cost estimate (analytic; no Linux GUI target)

z9edit is Win32/GUI-only, so no host timing is claimed. The count is from the
current sources:

- `ui.zig:uiPaint` (`ui.zig:840`) repaints the whole visible window every call.
- `main.zig:loop` (`main.zig:422-456`) calls `paintFrame` every iteration and
  `sleepMs(16)` unconditionally, so an idle editor still repaints at ~62.5 Hz.
- Per visible row, `uiPaint` calls `buffer.bufLineRange` (`buffer.zig:423`),
  which calls `lineCountOf` (full-buffer scan, `buffer.zig:150`) **and**
  `lineStartOf` (scan from the buffer start, `buffer.zig:165`).
- `uiPaint` also calls `bufLineCount` twice (`ui.zig:860` for the gutter,
  `ui.zig:894` for the render bound), and `clampScroll` (`ui.zig:245`) calls it
  once more. Each `bufLineCount` is another full-buffer `lineCountOf` scan.
- `caretLineCol` → `bufLineColOf` (`buffer.zig:456`) scans from the buffer start
  to the caret each frame.
- `paintCursor` (`ui.zig:786`) and `paintStatus` (`ui.zig:802`) each call
  `lineText` → another `bufLineRange`. `paintStatus` also calls
  `match.matchUnbalanced` (`match.zig:79`), a full-buffer scan, every frame.
- `paintTokens` (`ui.zig:724-770`) issues one `gfx.gfxDrawText` per visible
  character (a tab expands to one call per space cell), plus one per gutter row.

Reference case: default 80x25 window, 5,000 lines at 40 bytes/line
(B = 5,000 × 41 = 205,000 bytes including newlines), scroll not dirty so
`syncLex` does no replay.

| Per-frame work | Count |
|---|---:|
| Visible content rows | 24 |
| `bufLineRange` calls (24 rows + cursor + status) | **26** |
| `lineCountOf` full scans from those 26 calls | 26 × 205,000 = 5,330,000 B |
| `lineStartOf` scans (mid-file vs bottom scroll) | 26 × ~102,500 to 26 × ~204,500 ≈ 2.67 M–5.32 M B |
| `bufLineCount` ×2 (gutter + render bound) | 2 × 205,000 = 410,000 B |
| `clampScroll` → `bufLineCount` ×1 | 205,000 B |
| `matchUnbalanced` full scan | 205,000 B |
| `caretLineCol` → `bufLineColOf` | ~102,500 B (mid) to ~204,500 B (bottom) |
| Total buffer-byte reads per frame | **≈ 8.9 M (mid-file) to 11.7 M (bottom)** |
| Character draw calls (`gfxDrawText`) | 24 × 40 + 24 gutter + 1 cursor + 1 status = **986** |
| Plus non-text ops | 1 `gfxClear`, 1 `gfxFillRect` (status row) |

Canonical arithmetic: `T = 26·B + 26·L̄ + 4·B + P = 30·B + 26·L̄ + P`,
where `B` is the file size, `L̄` is the mean line-start offset of the 26
painted/cursor/status lines, and `P` is the caret byte offset. Mid-file:
`30×205,000 + 26×102,500 + 102,500 ≈ 8.9 M`. Bottom:
`30×205,000 + 26×204,500 + 204,500 ≈ 11.7 M`.

General forms:

- `bufLineRange` calls/frame = `content_rows + 2` = `(rows - 1) + 2`.
- Character draws/frame = `content_rows × min(line_len, cols - gutter) +
  content_rows + 2`; with 75-column lines the same 80x25 window is
  `24 × 75 + 26 = 1,826` draw calls.
- At the 62.5 Hz paint loop the reference case is ~0.56–0.73 G buffer-byte
  reads/s and ~62 k `gfxDrawText` calls/s, even when nothing changed.
- A scroll/jump also runs `syncLex` (`ui.zig:685`) line by line; each skipped
  line goes through `lineText` → `bufLineRange`. Jumping to line ~4,976 adds
  roughly 1.0–1.5 G buffer-byte reads for that one frame.

GUI timing remains operator-side (Wine smoke later); this estimate is the
before/after work-count metric for Tasks 7-8.

## 7. Caveats / notes

- No Z98 source was modified; no compiler pins were touched.
- The Linux link is `-O0`; z9gb `tier_perf.sh`'s `-O2` fps is deliberately not
  mixed into this series.
- z9torr's idle CPU sample is the full 10.00 s window: the local seeder is
  `SIGSTOP`ped after 2 s while its connection/coroutine stay live, and the
  client spins at 99% CPU with `0KB/s` until `timeout` kills it (`rc=124`).
- The FLAC fixture is generated on demand from the committed PCM golden with
  the private `flac` binary and its `LD_LIBRARY_PATH` (`sha1
  14be24c914ff796daf478393931761d575d76fa5`, 74017 B); the source tree has no
  committed `.flac`.
- z9git HTTPS numbers include network variance; the local-mirror row is the
  stable before/after comparison.
- All compiler/example builds and dumps were run sequentially from the repo
  root (`.zig1_*.tmp` collision rule).
