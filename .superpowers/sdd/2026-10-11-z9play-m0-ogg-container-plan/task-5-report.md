# Task 5 Report — z9play M0 `--info` CLI + `tier_info` gate

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 5)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): z9play --info CLI + tier_info gate` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/cli.zig` (new) — M0 argument parsing:
  `--info <file>`, `--help`/`-h`, `--version`. `parseArgs` prints+exits 0 for
  help/version and prints usage+exits 1 on a malformed command line; on success
  returns `InfoArgs{ path }`.
- `examples/z98/z9play/main.zig` (new) — entry `main(argc, argv)` (z9torr idiom:
  `i32` / `[*][*]u8`, no slice params across emissions). Reads the file via
  `std_file.readAll`, reassembles packets (`ogg.reassemble`), parses the id
  header (`vorbis_info.parseId`) and comment header (`parseComment`), derives
  duration (`ogg.lastGranule` + `ogg.durationMs`), and prints a FIXED
  `key=value` block.
- `examples/z98/z9play/tests/tier_info.sh` (new, executable) — the M0 gate.
- `examples/z98/z9play/NOTES.md`, `examples/z98/z9play/README.md` (updated) —
  M0 complete; `--info` usage + output; build recipe; `--dump-c89` md5.

## Output format (decision)

`--info` stdout is **byte-identical to the committed golden**
`testdata/expected/<name>.meta` (same `key=value`, LF-terminated format):

```
channels=<n>
sample_rate=<rate>
duration_s=<sec>.<mmm>     (3 decimals, from durationMs)
TITLE=<raw bytes>          (only when present)
ARTIST=<raw bytes>         (only when present)
ALBUM=<raw bytes>          (only when present)
```

Rationale: the plan's Task 5 gate is "`--info` output fields vs
`testdata/expected/*.meta`", so matching the golden exactly makes the gate a
strict, non-vacuous byte comparison (`cmp`). The convention tags `TITLE`/
`ARTIST`/`ALBUM` are emitted in fixed order (uppercased keys from
`parseComment`); unset tags are omitted, matching the goldens. Non-ASCII values
are written as raw bytes (no sanitization), so `tagged_unicode.ogg` round-trips
its UTF-8. The `ENCODER`/vendor field is intentionally NOT printed (the goldens
do not carry it).

## Exit codes

`0` ok · `1` args · `2` open · `3` decoder (parse/format).

## Verification (all under `-fsafe`)

Seed: `/tmp/z9play_seed/zig1_5_clean`, fixed point
`bafbba9454cd2b134bdc3d50c65384e0` (v97); no rebuild needed.

- Build `main.zig`: `zig1_5_clean -fsafe` rc 0 (0 diagnostics);
  `build_target.sh` rc 0 → `prog`.
- `tests/tier_info.sh` → **20 passed, 0 failed → TIER_INFO PASS** (rc 0):
  - 5 fixtures (`sine_mono_44100`, `sine_stereo_44100`, `sine_stereo_48000`,
    `tagged_unicode`, `short`) each exit 0 AND `stdout == golden` (`cmp`).
  - args: `--help`/`--version` exit 0 (`--version` prints `z9play`); unknown
    flag / `--info` without file / no args exit 1.
  - non-vacuous open/decoder negatives: missing file exit **2**; non-OGG file,
    truncated file, and mutated `OggS` capture each exit **3**.
- Regression: `tests/ogg_test.zig` PASS
  (`pages=4 last_granule=88200 packets=91`); `tests/info_test.zig` PASS
  (`channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11`).
- `--dump-c89 examples/z98/z9play/main.zig | md5sum` =
  `ba86cbe8b2229667f4c8084a0b0e75da` — **stable 3×** (seed `zig1_5_clean`, v97).
- Corpus discovery: `scripts/corpus/list_corpus_dirs.sh` now lists
  `examples/z98/z9play/` (entry resolves to `main.zig`); the `examples/z98/`
  corpus count is **26** (was 25). No other example touched.
- Scope: `git show --name-only a2f97656` = the five z9play files only; no
  compiler/`sf/src` change, no seed rotation.

## Z98 conformance

- `examples/z98/z9play/**` only; no compiler change; no seed rotation.
- Free functions (no method syntax); no generics/`anytype`/`@Type`/`@cImport`.
- Strict `@intCast` everywhere (`@intCast(usize, argc)`,
  `@intCast(u64, id.channels)`, `@intCast(u8, v % 10) + '0'`).
- Every `switch` has `else` — no `switch` is used here.
- String literals via `var s: []const u8 = "...";` (e.g. `var l_ch: []const u8
  = "channels=";`); no raw literal passed to a `[]const u8` parameter.
- D1 (no union tags) / D2 (slices only of primitives or named types:
  `[]ogg.Packet`, `[]vi.Tag`, `[]const u8`) / D3/D4 (no suspensions; no
  module-global struct passed into a suspension).
- Arena is a module-global `[4 MiB]u8` (not on the 32-bit stack), as in the
  Task 1–4 unit harnesses.

## Notes / decisions

1. `main.zig` requires at least 2 reassembled packets (id + comment) before
   decoding; fewer → exit 3 (`missing Vorbis headers`). A valid `oggenc` file
   always yields ≥3 (id, comment, setup).
2. `--info` does not reject sample rates ∉ {44100, 48000}: the spec §7 risk 5
   rejection is a *playback* (decoder) concern for M5; M0 metadata is
   informative and all fixtures are 44100/48000. Flagged in case M5 expects the
   rejection earlier.
3. The `--info` block is the golden `.meta` format exactly; if a later
   milestone needs a different human line (e.g. `duration_ms`), it should add
   one rather than changing these lines, so `tier_info.sh` stays a byte gate.
4. `NOTES.md` records `working commit` as "this commit; short hash pinned at
   M0 closeout" — a commit cannot self-reference its own hash, and the plan
   originally reserved this field for M0 closeout.
5. The M0 dump md5 `ba86cbe8b2229667f4c8084a0b0e75da` is for `main.zig` **only**
   (the plan asks for `main.zig`). The dump includes `cli.zig`/`ogg.zig`/
   `vorbis_info.zig` transitively as imported modules — consistent with the
   z9torr convention for its single top-level `main.zig`.

## Concerns

- None blocking. Two low-risk items for the M0 closeout / M1 review:
  - Confirm the M5 CLI is content with this `--info` block (or extends it
    additively) and does not need `duration_ms` in M0 output.
  - Confirm the sample-rate rejection belongs in M1/M3/M5, not M0.
