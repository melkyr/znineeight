# Task 0 Report — z9play M0 Preflight (fixtures + vorbis-tools acquisition + baseline)

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md`
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `test(z9play): fixtures + vorbis-tools acquisition (M0)` (single commit; hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/tests/get_vorbis_tools.sh` — no-root vorbis-tools acquisition.
- `examples/z98/z9play/tests/mkfixtures.sh` — deterministic fixture + golden generator.
- `examples/z98/z9play/testdata/*.ogg` + `testdata/expected/*.meta` — 5 fixtures, 5 goldens.
- `examples/z98/z9play/README.md`, `examples/z98/z9play/NOTES.md` — skeletons (M0 in progress).

## 1. Acquisition helper

`tests/get_vorbis_tools.sh` mirrors `examples/z98/z9torr/tests/get_aria2.sh`:
private writable apt state/cache under `$TMP`, `apt-get update` +
`apt-get install --download-only --no-install-recommends -y vorbis-tools`,
`dpkg-deb -x` of every `.deb` into `$TMP/sys`, then prints:

```
oggenc: <path>
ogginfo: <path>
LD_LIBRARY_PATH: <colon-separated dirs>
oggenc_version: oggenc from vorbis-tools 1.4.2
```

Gate met: `oggenc --version` runs (`oggenc from vorbis-tools 1.4.2`, rc 0) with
the printed `LD_LIBRARY_PATH`. `ogginfo` has no `--version`, so the helper gates
it with `ogginfo -h` (prints usage, rc 0) instead. Downloaded transitive deps
include `libvorbis0a`/`libvorbisenc2`/`libvorbisfile3`/`libogg0`. Network was
available (deb.debian.org, bookworm/main).

## 2. Fixture generator + determinism

`tests/mkfixtures.sh` builds deterministic PCM in `python3`
(`math.sin`, no random) → WAV → `oggenc` (auto-invokes `get_vorbis_tools.sh` if
the tools are not on `OGGENC`). Fixtures (all 44100/48000 per spec §1):

| fixture | ch | rate | dur | freq | serial | bytes |
|:--|:--|:--|:--|:--|:--|:--|
| `sine_mono_44100.ogg` | 1 | 44100 | 1.0 s | 440 | 1001 | 5223 |
| `sine_stereo_44100.ogg` | 2 | 44100 | 2.0 s | 440/660 | 1002 | 10781 |
| `sine_stereo_48000.ogg` | 2 | 48000 | 1.0 s | 440/660 | 1003 | 8224 |
| `tagged_unicode.ogg` | 2 | 44100 | 1.0 s | 440/660 | 1004 | 7619 |
| `short.ogg` | 1 | 44100 | 0.3 s | 440 | 1005 | 4141 |

**Serial fix (the key determinism problem).** `oggenc` assigns a random Ogg
bitstream serial per run, so two encodes of identical PCM differed at byte 15
(char 15, the serial field). `oggenc` supports `-s`/`--serial`, so each fixture
pins a fixed serial (1001–1005). With that, **two consecutive `mkfixtures.sh`
runs produced all 5 `.ogg` + all 5 `.meta` files byte-identical** (`cmp` clean;
verified again after the final script edits). No STOP was needed: determinism is
fully achieved.

### Golden format (`.meta`)

Fixed, one `key=value` per line, LF, no comments; tag lines only when present,
always in `TITLE, ARTIST, ALBUM` order:

```
channels=<decimal>
sample_rate=<decimal>
duration_s=<seconds, 3 decimals>
TITLE=<raw UTF-8 value>
ARTIST=<raw UTF-8 value>
ALBUM=<raw UTF-8 value>
```

`channels`/`sample_rate`/`duration_s` are parsed from `ogginfo`
(`Channels:`, `Rate:`, `Playback length: <m>m:<s>s`). Documented in both
`mkfixtures.sh` and `NOTES.md`.

### Root cause corrected (fix round 1): encode-time locale, not ogginfo display

The original report misdiagnosed this as ogginfo/vorbiscomment *display*
sanitization. The real root cause is **encode-time locale**: the first
`mkfixtures.sh` exported `LC_ALL=C` globally, which leaked into the `oggenc`
calls. `oggenc` converts non-ASCII tag arguments through the locale, so under
`C` it substituted each non-ASCII byte with `#` **when writing the file**.
`tagged_unicode.ogg` therefore stored literal `#` bytes (`title=Caf## d##j## vu`,
`artist=Na##ve ######`, `ALBUM=##n##cod##`; zero `C3 A9` tag bytes), while the
golden held the UTF-8 literals — mutually inconsistent.

Fix: `oggenc` now runs under a UTF-8 locale (auto-detected
`C.UTF-8`/`C.utf8`/`en_US.UTF-8`/`en_US.utf8`; STOP if none), and `LC_ALL=C` is
scoped to only the byte/numeric parsing helpers. The golden tag values are now
read back from the **actual comment packet stored in the `.ogg`** (a small
Python OGG packet-reassembler in `extract_tags`), not from shell literals and
not from `ogginfo`. A self-check asserts the stored bytes round-trip to the
requested values and that the non-ASCII bytes appear verbatim in the file.
Forcing `UTF8_LC=C` makes the script fail with the `##` round-trip mismatch,
proving the guard. See "Fix round 1" below.

## 3. Baseline

- Seed built: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
  /tmp/z9play_seed` → **two-hop closure OK: hop1 == hop2 ==
  `bafbba9454cd2b134bdc3d50c65384e0`** (matches the expected fixed point; seed
  v97). rc 0.
- Corpus discovery: `scripts/corpus/list_corpus_dirs.sh` enumerates every
  immediate subdir of `examples/z98/` but emits a dir only with a resolvable
  entry. `examples/z98/z9play/` has no `.zig` yet → **not listed now**; with a
  throwaway `main.zig` stub it was emitted as `examples/z98/z9play/`, and the
  stub was removed immediately. Task 5 adds `main.zig`, satisfying discovery.

## 4. Commit

Single commit `test(z9play): fixtures + vorbis-tools acquisition (M0)`:
`examples/z98/z9play/{tests/*.sh,testdata/*.ogg,testdata/expected/*.meta,
README.md,NOTES.md}` plus this report. No push.

Report ignore nuance (corrected in fix round 1): `.superpowers/sdd/.gitignore`
contains `*`, so an **untracked** file there (e.g. this freshly written report)
*is* ignored and needed `git add -f` to stage. Once committed it is tracked, and
`git check-ignore` then reports it as **not** ignored (tracked paths are never
"ignored"), which is the state observed after the commit. So the `git add -f`
was necessary at creation time; the "is ignored" phrasing is accurate only for
the untracked state. Fixtures/goldens are not gitignored (only `*.txt` is), so
no `-f` was needed for them.

## Test summary

- `get_vorbis_tools.sh`: exit 0; prints oggenc/ogginfo + `LD_LIBRARY_PATH`;
  `oggenc --version` → `oggenc from vorbis-tools 1.4.2`.
- `mkfixtures.sh`: exit 0; 5 `.ogg` + 5 `.meta`; two runs byte-identical
  (10/10 `cmp` clean), including after final edits.
- Baseline seed: fixed point `bafbba9454cd2b134bdc3d50c65384e0` (expected).

## Concerns / notes for reviewer

1. ~~`ogginfo`/`vorbiscomment` sanitize non-ASCII tags to `#`~~ **Resolved
   (fix round 1).** The `#` bytes came from the encode-time `LC_ALL=C` leak into
   `oggenc`, not from ogginfo display. `tagged_unicode.ogg` now stores real UTF-8
   tag bytes, and the `.meta` is parsed from those stored bytes. Task 5's
   `tier_info.sh` should compare the Unicode tag bytes against the `.meta`
   (raw), which is what the `.meta` now holds.
2. WAV PCM uses `python3 math.sin`; cross-machine float reproducibility is not
   guaranteed, but the committed `.ogg` bytes are the source of truth (same
   "committed-bytes-are-truth" contract z9torr uses). Same-machine re-runs are
   byte-identical.
3. Fixture durations are exact (1.0/2.0/1.0/1.0/0.3 s) so Task 4's
   granule-derived `durationMs` should match the `duration_s` goldens exactly.
4. `duration_s` is stored to 3 decimals (ogginfo's ms resolution); if Task 5
   compares in integer ms, multiply by 1000 (exact for these fixtures).

## Fix round 1

Addressed the review: one HIGH (mutually inconsistent `tagged_unicode.ogg` /
`.meta`) and all LOWs.

**HIGH — encode-time locale corruption (fixed).** `mkfixtures.sh` had
`export LC_ALL=C` globally; this leaked into `oggenc`, which substitutes each
non-ASCII tag byte with `#` under a non-UTF-8 locale, so `tagged_unicode.ogg`
stored `#` bytes while the golden held UTF-8 — a correct parser would return
`##` and fail. Changes:

- Removed the global `export LC_ALL=C`. `oggenc` now runs under a UTF-8 locale
  auto-detected from `C.UTF-8`/`C.utf8`/`en_US.UTF-8`/`en_US.utf8`
  (`UTF8_LC`, overridable); the script STOPs if none is available.
- Added `extract_tags`, a small Python OGG packet-reassembler that reads the
  Vorbis comment packet straight from the `.ogg` bytes; the golden tag values
  are now derived from the **actual stored bytes**, not from shell literals and
  not from `ogginfo` (whose output is locale-dependent). `channels` /
  `sample_rate` / `duration_s` still come from `ogginfo`, with `LC_ALL=C` scoped
  to those parsing helpers only.
- Added a self-check: the stored tag bytes must round-trip to the requested
  values, and the non-ASCII TITLE must appear verbatim in the file.
  Verified by forcing `UTF8_LC=C` in a throwaway tree: the script exits 1 with
  `tag round-trip FAILED ... got: TITLE=Caf## d##j## vu` — the guard catches the
  exact regression.
- **Regenerated all fixtures.** Verified `tagged_unicode.ogg` now contains the
  raw UTF-8 bytes (`od -c`: `title=Caf 303 251 ...`), and
  `expected/tagged_unicode.meta` matches (its content is unchanged in git — the
  golden was already the right string; only the `.ogg` was wrong).
- Determinism re-confirmed: two `mkfixtures.sh` runs → all 5 `.ogg` + 5 `.meta`
  byte-identical (10/10 `cmp`). `oggenc --version` still runs
  (`oggenc from vorbis-tools 1.4.2`).

**LOWs (folded in).**
- Report misdiagnosis of `#` as ogginfo *display* sanitization → corrected to
  the encode-time locale root cause (above; also corrected `NOTES.md`).
- Report `.superpowers/sdd/` gitignore claim → corrected: `.superpowers/sdd/
  .gitignore` is `*`, so an untracked report is ignored (`git add -f` was
  needed); once committed, `git check-ignore` reports it as not ignored.
- `mkfixtures.sh` `set -u` override path → `LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"`
  before export; verified `env -u LD_LIBRARY_PATH OGGENC=... sh mkfixtures.sh`
  fails with a typed message, not "unbound variable".
- `get_vorbis_tools.sh` `DIST=bookworm` → added a comment that the distro pin is
  informational and the committed `.ogg` bytes are the source of truth.

**Files changed in fix round 1:** `tests/mkfixtures.sh`, `tests/get_vorbis_tools.sh`,
`testdata/tagged_unicode.ogg`, `NOTES.md` (the other fixtures and all 5 `.meta`
are byte-identical to the original commit). This report. Commit amended
(same subject). No push.

