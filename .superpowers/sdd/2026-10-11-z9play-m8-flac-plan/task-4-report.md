# M8 Task 4 report — docs (FLAC)

**Status:** COMPLETE.

**Commit (a):** `808355d38ec869b28b818b406ec76f81c1def29d` — `docs(z9play): M8 FLAC`
(`examples/z98/z9play/NOTES.md` + `examples/z98/z9play/README.md` only).

**Commit (b):** `docs(sdd): M8 T4 report` — this report only (staged with
`git add -f`).

**Seed:** v102 `/tmp/z9play_seed/zig1_5_clean`
(`b299b4b435e624d0ddbd2edde681cbc3`); archive `release/seed/zig1-seed.tgz`
md5 `702f34d87b7e6bf401dd206d2517dbee` (unchanged).

## Docs changes

Docs-only; no source, std, compiler, seed, or fixture change.

- `NOTES.md` (`808355d3`):
  - top status paragraph now records M8 (FLAC through `main.zig`/`ui.zig`,
    Vorbis-only request modes, `tier_flac.sh` 59/0 twice, seed v102,
    D1/D2 FIXED / D3/D4/D5 OPEN, Win9x hardware operator-pending, and that
    M8 Task 5 owns any feature-complete statement);
  - the MD5 field now records the **M8 current** Linux-default pins while
    preserving the historical M6 `-osw` and previous Linux values;
  - new M8 milestone section (line ~975) records the decoder/selector work,
    FLAC capabilities/limits, `tier_flac.sh` evidence, current dump md5s, Win9x
    gate, defect status, and the M8 chain (`07d92393` T2 → `903ea2ab` T3).
  - M0–M7 sections are preserved; changes are additive except the top status
    and MD5 field.
- `README.md` (`808355d3`):
  - intro now says OGG Vorbis + FLAC;
  - new M8 status paragraph (support, limits, tier result, Win9x, seed, defects,
    no feature-complete claim);
  - new M8 file list, `### FLAC (M8)` build/run section, and `tier_flac.sh` in
    the gate list;
  - Notes section now lists the M8 current `main.zig`/`ui.zig` dump md5s and
    marks the M7 `ui.zig` pin superseded as current.
  - historical M0–M7 text is preserved.

Documented truth matches the T2/T3 reports and the context: `.flac` playback
through `--wav` + interactive CLI (`main.zig`) and TUI (`ui.zig`), mixed
`.ogg`/`.flac` directories, `--info`/`--dump-setup`/`--pcm` Vorbis-only (FLAC
exit 3), lossless exact PCM + 3× deterministic tier, 59/0 twice, win9x
PE32/import gate, and no hardware/full-feature-completion claim.

## Truth checks

### Diff scope

```
$ git show --stat --oneline 808355d3
808355d3 docs(z9play): M8 FLAC
 examples/z98/z9play/NOTES.md  | 57 ++++++++++++++++++++++++++++++--
 examples/z98/z9play/README.md | 77 ++++++++++++++++++++++++++++++++++++++-----
 2 files changed, 123 insertions(+), 11 deletions(-)
```

Only `NOTES.md` + `README.md`. `run.err` remains untracked/untouched; no
`progress.md` change was made.

### Seed values

```
$ md5sum /tmp/z9play_seed/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/z9play_seed/zig1_5_clean
$ md5sum release/seed/zig1-seed.tgz
702f34d87b7e6bf401dd206d2517dbee  release/seed/zig1-seed.tgz
```

### `--dump-c89` current values (measured, not copied)

```
$ timeout 300 /tmp/z9play_seed/zig1_5_clean --dump-c89 examples/z98/z9play/main.zig | md5sum
e56af7916edd199e796f3ef11d5e49c4  -
$ timeout 300 /tmp/z9play_seed/zig1_5_clean --dump-c89 examples/z98/z9play/ui.zig | md5sum
22676fd997471df1c4c3a3f04397121d  -
```

Both match the M8 values documented.

### Vorbis-only request modes reject FLAC

Using the T2-built binary at `/tmp/z9play_t2_main/prog`:

```
$ /tmp/z9play_t2_main/prog --info /tmp/z9play_t2_fixture/sine_stereo_44100.flac
z9play: not an OGG Vorbis stream
--info rc=3
$ /tmp/z9play_t2_main/prog --dump-setup /tmp/z9play_t2_fixture/sine_stereo_44100.flac
z9play: not an OGG Vorbis stream
--dump-setup rc=3
$ /tmp/z9play_t2_main/prog --pcm /tmp/z9play_t2_fixture/sine_stereo_44100.flac /tmp/z9play_t2_main/reject.wav
z9play: not an OGG Vorbis stream
--pcm rc=3
```

### Stale seed grep

Command:

```
$ grep -n "v98" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
```

Observed hits: `NOTES.md:9` (historical MD5 note), `:34` (M5 base seed),
`:691`, `:693`, `:738`, `:751`, `:785`, `:816`, `:888`, and `README.md:70`,
`:86`. All are in preserved M5/M5b/M6/M7 historical text. No M8 current claim
uses v98; the M8 text and top status say seed v102.

### Defect-status grep

Command:

```
$ grep -n "D1–D8 are all FIXED\|D1-D8 are all FIXED" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
```

Observed hits:

```
NOTES.md:34:  ... the pre-reset M0–M5 defects D1–D8 are all FIXED ...
NOTES.md:692: ... compiler defects D1–D8 are all FIXED in seed v98 (M5 history) ...
README.md:130: ... the old M0–M5 D1–D8 are all FIXED and in history ...
```

All are explicitly historical/contextualized. The current statements are
**D1/D2 FIXED; D3/D4/D5 OPEN** (top status, M8 section, README M8).

### False hardware-completion grep

Command:

```
$ grep -niE "hardware (verification|verified)[^.]*\b(complete|passed|done)\b" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
```

Observed output: none. Both docs state Win98/Me hardware verification is
design-verified / **operator-pending**.

### Old dump md5 in M8 region

Command:

```
$ awk '/### M8 /{f=1} f' examples/z98/z9play/NOTES.md | grep -nE "ad9ccfd|e7bc57a2|4c9f760"
```

Observed hits are only the explicit superseded-current note:

```
40:  (`ad9ccfd34aa2ba26c38abbcf48eedeb0`) and the historical M7 `ui.zig` value
41:  (`e7bc57a2a38a72cb83f51a1ce7497239`) are superseded as current pins by these
```

They are not presented as current. The current values are `e56af791...` /
`22676fd9...`.

### Tier evidence

`tests/tier_flac.sh` exists (mode 100755) and its T3 report records both runs:

```
== tier_flac summary: 59 passed, 0 failed ==
TIER_FLAC PASS
```

Run 1 and run 2 logs were byte-identical (98 lines each) and cover: `main.zig`/
`ui.zig` `-fsafe` builds; no-root `get_flac_tools.sh` (flac 1.4.2); three
regenerated `.flac` fixtures; byte-exact `--wav` payloads vs `flac -d`; 3× raw-
PCM SHA-1 determinism; mixed `.ogg`/`.flac` TUI pty session (18/18); OGG tiers
23/0, 40/0, 27/0; Win9x PE32/import gate; stable 2× dump md5s. Not rerun in T4
(docs-only); the docs cite the T3 report.

## Concerns

- `--info`, `--dump-setup`, and `--pcm` remain Vorbis-only and reject FLAC with
  exit 3; FLAC tags are not parsed; frame CRC-16 is not verified (header CRC-8
  is). These limits are now documented.
- The 59/0 result is taken from the T3 report; T4 did not rerun the tier
  (docs-only, and the tier regenerates fixtures via apt/no-root tooling).
- Win9x remains emission/build/import-gated only; real Win98/Me hardware
  verification is operator-pending and is not claimed.
- Current docs intentionally do not claim "feature-complete"; the M8 Task 5
  handoff owns that statement.
- Preserved historical M0–M7 text still contains the strings "v98" and
  "D1–D8 are all FIXED"; the truth greps above show they are historical and
  contextualized, not current claims.

## Fix round 1

**Commit (a):** `ee485934c47b3a0ad06cf4e545fb242bf67b8448` —
`docs(z9play): M8 T4 fix — pin truth-up` (`NOTES.md` + `README.md` only).

Fixed the stale/contradictory `-osw` pin in all three areas:

- `README.md` Notes: `ad9ccfd3...` is now explicitly historical M6/seed v101,
  **not a current pin**; `e56af791...` is the current `main.zig` Linux pin;
  `22676fd9...` supersedes only the M7 `ui.zig` Linux pin `e7bc57a2...`.
- `NOTES.md` top MD5 field: heading is now `MD5 (`--dump-c89`)`; the historical
  M6 `-osw` value is labelled **not current**; M8 did not re-pin `-osw` and the
  current measured value is recorded; Linux pins are distinguished.
- `NOTES.md` M6 `--dump-c89` region: the recipe is labelled **historical
  (seed v101)**, its value comment says **not current**, and the current seed
  v102 `-osw` value is stated above the code block.
- `NOTES.md` M8 dump bullet: `ad9...` is historical and not current; `22676...`
  supersedes only the M7 `ui.zig` Linux pin; `e56...` is the current `main.zig`
  Linux pin; the current `-osw` value `aa6878...` is recorded.
- Minor: added T1 `c4b53d84` to the M8 chain and changed README wording from
  "Linux gates are unchanged" to "The M8 FLAC gate and the existing Linux
  gates".

Measured current `-osw` value (seed v102):

```
$ timeout 300 /tmp/z9play_seed/zig1_5_clean -osw --dump-c89 examples/z98/z9play/main.zig | md5sum
aa68782328c001c1f72d03f8ab1282d7  -
```

Relevant greps:

```
$ grep -n "remains the Win9x target\|superseded as current pins by these\|Linux gates are unchanged" \
    examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
(no output)

$ grep -n "ad9ccfd" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
NOTES.md:3     ... M6 historical sentence, "-osw --dump-c89 ... on seed v101"
NOTES.md:9     ... "historical M6 ... **not current**"
NOTES.md:216   ... "(historical M6/seed-v101; not current)"
NOTES.md:868   ... M6 task-4 history
NOTES.md:890   ... M6 section (seed v101)
NOTES.md:1020  ... "historical M6/seed v101 and is **not a current pin**"
README.md:125  ... M6 section (seed v101)
README.md:517  ... "historical M6/seed v101, **not a current pin**"

$ grep -n "aa687823" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
NOTES.md:9     ... current measured -osw value
NOTES.md:210   ... M6-region note: current measured -osw value
NOTES.md:1023  ... M8 bullet: current measured -osw value
README.md:520  ... Notes: current measured -osw value

$ grep -n "e56af791\|22676fd9" examples/z98/z9play/NOTES.md examples/z98/z9play/README.md
NOTES.md:9     ... current main Linux pin / current ui Linux pin
NOTES.md:1017-1019 ... M8 bullet: current main pin; ui supersedes only M7 pin
README.md:513-515 ... Notes: current main pin; ui supersedes only M7 pin

$ grep -n "M8 chain so far" examples/z98/z9play/NOTES.md
1032:- M8 chain so far: `c4b53d84` (T1 decoder abstraction) → `07d92393` ...
```

Scope/whitespace:

```
$ git diff --stat HEAD~1 HEAD
 examples/z98/z9play/NOTES.md  | 27 +++++++++++++++++----------
 examples/z98/z9play/README.md | 19 ++++++++++---------
 2 files changed, 27 insertions(+), 19 deletions(-)
$ git diff --check HEAD~1 HEAD
(no output)
```

No stale pin is presented as current: every `ad9...` occurrence is either in
preserved M6/M7 history or explicitly labelled historical/not current.
