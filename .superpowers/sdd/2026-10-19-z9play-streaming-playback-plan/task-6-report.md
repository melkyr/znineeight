# M9 Task 6 report — large-file gate, `lin_bin` rebuild, docs

**Status:** PASS. `tier_stream.sh` 19/0; all prior tiers green; the operator's
8,205,755-byte track plays in the rebuilt TUI; docs updated. No source,
compiler, `sf/**`, standard library, or seed change.

## Environment / seed

- Branch: `zig1_improvements`
- Seed compiler: `/tmp/m7_t5_seed2/zig1_5_clean`
- `md5sum /tmp/m7_t5_seed2/zig1_5_clean`:
  `b299b4b435e624d0ddbd2edde681cbc3` (v102 fixed point, unchanged)
- Host: Linux x86_64; `gcc -m32`; Python 3.11; `script(1)` available.

## Commits

- `72ca8efa` — `example(z9play): streaming playback tier + large-file gate`
  - `examples/z98/z9play/tests/make_large_ogg.py` (new, mode 100755)
  - `examples/z98/z9play/tests/tier_stream.sh` (new, mode 100755)
- `b7c548b9` — `docs(z9play): streaming playback`
  - `examples/z98/z9play/NOTES.md`, `examples/z98/z9play/README.md`
- This report — `docs(sdd): M9 T6 report`

`lin_bin/` and the operator `.ogg` remain untracked. `run.err`/`run.out` and
`progress.md` were not touched.

## Deliverable 1 — `tests/make_large_ogg.py`

Deterministic generator; Python standard library only (no third-party OGG
library). It parses the committed 2.0 s `testdata/sine_stereo_44100.ogg`, walks
segment laces to prove the audio starts on a packet boundary, emits the header
pages once, repeats the audio page block, and rebuilds every page with:

- globally monotonic sequence numbers,
- the fixture's single serial,
- granule positions advanced by one fixture duration per block,
- EOS only on the final emitted page, and
- recomputed OGG CRC-32 (`0x04c11db7`, init/xorout 0, not reflected).

It then re-parses its own output and verifies serial/sequence/EOS/final
granule/CRCs before writing. `--size` accepts bytes or K/M/G (KiB/MiB/GiB)
suffixes; default is `64M`. `--quiet` suppresses statistics.

Exact command/output:

```text
$ python3 examples/z98/z9play/tests/make_large_ogg.py \
    examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/large.ogg --size 64M
size=67109323
pages=19800
blocks=9899
channels=2
sample_rate=44100
duration_s=19798.000

$ python3 examples/z98/z9play/tests/make_large_ogg.py \
    examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/large2.ogg --size 64M --quiet
$ cmp /tmp/large.ogg /tmp/large2.ogg && echo deterministic_ok
deterministic_ok
```

The gate repeats the byte comparison at 64 MiB, so determinism is exercised at
the real size, not only on a small sample.

## Deliverable 2 — `tests/tier_stream.sh`

The tier builds `main.zig` and `ui.zig` with `-fsafe` + emitted
`build_target.sh linux`, then runs:

1. large-OGG generation (twice, byte-identical) and size ≥ 64 MiB;
2. `--info` on the large file under `ulimit -v 65536` KiB (64 MiB);
3. a same-limit allocation probe for the exact generated file size;
4. `--pcm` exact pin on `sine_stereo_44100.ogg`;
5. optional `Z9PLAY_LARGE_OGG` real-track `--info`;
6. existing tiers `tier_info`/`tier_setup`/`tier_cli`/`tier_tui`/
   `tier_audio`/`tier_flac`.

Exact gate command/output (run 2; `tee /tmp/tier_stream_run2.log`):

```text
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean sh examples/z98/z9play/tests/tier_stream.sh
== seed ==
compiler: /tmp/m7_t5_seed2/zig1_5_clean
md5:      b299b4b435e624d0ddbd2edde681cbc3
ok   - seed v102 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3
== building z9play main.zig and ui.zig (binding recipe, -fsafe) ==
ok   - main.zig -fsafe compile + emitted build_target.sh linux
ok   - ui.zig -fsafe compile + emitted build_target.sh linux
== deterministic large OGG from the committed 2 s fixture ==
ok   - make_large_ogg.py generated /tmp/z9play_tier_stream/large.ogg
ok   - make_large_ogg.py is deterministic (two runs byte-identical)
ok   - large OGG size 67109323 >= 67108864 bytes (64 MiB)
ok   - generator stats: 2ch 44100Hz duration=19798.000s blocks=9899
== --info on the large OGG under ulimit -v 65536 KiB (64 MiB) ==
ok   - large --info exit 0 under ulimit -v 65536
ok   - large --info matches expected channels/sample_rate/duration exactly
ok   - full-file allocation of 67109323 bytes fails under the same ulimit
== --pcm exact regression pin (pre-streaming WAV) ==
ok   - --pcm sine_stereo_44100 exit 0
ok   - --pcm canonical WAV size 352844
ok   - --pcm byte-exact pin (md5=e7f24870ec03b924be1b8e55a1962fb3)
== optional operator track (Z9PLAY_LARGE_OGG) ==
skip - Z9PLAY_LARGE_OGG not set (operator track not checked)
== existing tiers (green baselines) ==
info: == tier_info summary: 20 passed, 0 failed == (rc=0)
ok   - info 20/0
setup: == tier_setup summary: 21 passed, 0 failed == (rc=0)
ok   - setup 21/0
cli: == tier_cli summary: 23 passed, 0 failed == (rc=0)
ok   - cli 23/0
tui: == tier_tui summary: 40 passed, 0 failed == (rc=0)
ok   - tui 40/0
audio: == tier_audio summary: 27 passed, 0 failed == (rc=0)
ok   - audio 27/0
flac: == tier_flac summary: 59 passed, 0 failed == (rc=0)
ok   - flac 59/0

== tier_stream summary: 19 passed, 0 failed ==
TIER_STREAM PASS
```

Large `--info` output:

```text
channels=2
sample_rate=44100
duration_s=19798.000
```

### Memory limit rationale (reproducible)

`VM_KB=65536` (64 MiB). The 32-bit `main.zig` binary has ~42 MiB of static
`.bss` arenas (4 MiB stream/read arena + 16 MiB decoder + 8 MiB PCM scratch +
8 MiB WAV scratch + 2 MiB player + 2 MiB loop buffer) and runs under this limit.
Its streaming path additionally allocates only bounded buffers: 64 KiB
`BufferedFile` + 65,536-byte page + 1 MiB packet + a 256 KiB temporary tail
scan. A full-file buffer is 67,109,323 bytes (64 MiB + 459 B), which cannot be
allocated on top of that under the same limit. The tier proves this with a
Python probe that allocates exactly the generated file size and touches every
4 KiB page:

```text
full-file allocation of 67109323 bytes fails under the same ulimit
```

The probe is required to print `alloc-failed`; a probe crash or a successful
allocation fails the tier.

## Deliverable 3 — `lin_bin/z9play-console` rebuild + operator track

Rebuild (seed v102):

```text
$ /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o /tmp/t6_linbin \
    examples/z98/z9play/ui.zig
$ sh /tmp/t6_linbin/build_target.sh linux /tmp/t6_linbin/z9play-console
$ cp /tmp/t6_linbin/z9play-console lin_bin/z9play-console
$ md5sum lin_bin/z9play-console /tmp/z9play_tier_stream/ui/prog
af1cef634dd7b885363bff2ec3582aff  lin_bin/z9play-console
af1cef634dd7b885363bff2ec3582aff  /tmp/z9play_tier_stream/ui/prog
```

The rebuilt binary is byte-identical to the `ui.zig` binary built by
`tier_stream.sh` from the final tree.

`--info` on the operator track under the same 64 MiB limit:

```text
$ ( ulimit -v 65536; /tmp/z9play_tier_stream/main/prog --info \
    'lin_bin/01. 霜月はるか — ユメノハテニ.ogg' )
channels=2
sample_rate=44100
duration_s=334.000
TITLE=ユメノハテニ
ARTIST=霜月はるか
ALBUM=ユメノハテニ
rc=0
```

TUI pty probe (80x25 UI in a 100x30 pty, cwd `lin_bin`, `j` to select the only
`.ogg`, Enter, wait for `State: Playing` and >1 MiB written to the hermetic WAV
sink, then `q`):

```text
rc=0
now=1
playing=1
cannot_open=0
oom=0
not_ogg=0
wav_bytes=1082668
Now: b'Now: 01. \xe9\x9c\x9c\xe6\x9c\x88... (ユメノハテニ)'
State: b'State: Playing'
```

The old failure text `cannot open track` does not appear. The WAV sink grew to
1,082,668 bytes before quitting, proving actual decode/playback rather than an
idle state.

`lin_bin/instructions.txt` was updated (untracked, as required) to document
streaming/bounded memory, arbitrary practical track size, and the existing
32-bit build/runtime note.

## Deliverable 4 — docs

`NOTES.md`:

- top status now records M9 (streaming, bounded buffers, large-file gate);
- current `--dump-c89` pins:
  - Linux: `main.zig` `23f9b5ec0f8e69fe48e9b5598719ced7`,
    `ui.zig` `76d0fc83121892118089b10c6b66bb41`;
  - `-osw`: `main.zig` `6cd349b5fae0b6a703d27424ddfb70f2`,
    `ui.zig` `294e3fde8819e638556d07cddc385301`;
  - M8-era pins marked superseded;
- full M9 section: stream/OGG/FLAC APIs, no whole-track buffer, streamed
  `--pcm`, large-file gate, operator-track result, D3/D4/D5 OPEN, Win9x
  hardware operator-pending.

`README.md`:

- M9 status paragraph and file list;
- streaming build/gate section with the exact `ulimit -v 65536` command;
- `--pcm` wording updated to incremental streaming;
- current pins in Notes; seed v102 unchanged, D3/D4/D5 OPEN, Win9x pending.

Both dump pins were measured sequentially (parallel runs collide on the
compiler's `.zig1_*.tmp` spill files in the repo root) and are stable 2×.

## Verification summary

| Gate | Result |
|---|---|
| `tier_stream.sh` | **19 passed, 0 failed** |
| `tier_info` | 20/0 |
| `tier_setup` | 21/0 |
| `tier_cli` | 23/0 |
| `tier_tui` | 40/0 |
| `tier_audio` | 27/0 |
| `tier_flac` | 59/0 |
| Large OGG | 67,109,323 bytes, 19,800 pages, deterministic |
| Large `--info` under 64 MiB | exit 0, exact rate/channels/duration |
| Same-size allocation under 64 MiB | fails (`alloc-failed`) |
| `--pcm` exact pin | md5 `e7f24870ec03b924be1b8e55a1962fb3` |
| Operator `--info` under 64 MiB | exit 0, 334.000 s |
| Operator TUI | `Now:` + `State: Playing`, 1,082,668 WAV bytes, no `cannot open track` |
| Seed | v102 fixed point `b299b4b435e624d0ddbd2edde681cbc3` unchanged |

## Concerns / notes

- The optional `Z9PLAY_LARGE_OGG` branch was implemented and manually exercised
  through the same `--info` command/limit; the recorded automated gate run left
  the env var unset (it printed `skip`). It never copies the operator file.
- `tier_flac.sh` re-runs `tier_tui.sh`; when given a deep scratch `OUT`, the
  TUI's fixed 43-column path pane truncates the path and fails its
  `dir-pane-shows-current-path` check. `tier_stream.sh` therefore runs the
  nested tiers from a short scratch root (`${TMPDIR:-/tmp}/z9s_tiers`). This is
  a test-harness path-length sensitivity, not a player regression; the direct
  `tier_tui` run is 40/0 at the default short scratch path.
- Generating + self-verifying a 64 MiB OGG takes ~10 s per run in Python; the
  gate does it twice (determinism). Pure-Python CRC/table code keeps this
  dependency-free.
- D3/D4/D5 remain OPEN; real Win98/Me hardware verification remains
  operator-pending. No compiler/seed rotation and no `sf/**` change.
