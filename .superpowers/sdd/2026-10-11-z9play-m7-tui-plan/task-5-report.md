# M7 Task 5 report — docs + seed rotation v101 → v102

**Status:** DONE — docs updated, seed rotated, all closeout gates pass.

**Branch:** `zig1_improvements`.
**Base HEAD at rotation:** `389e0030` (`docs(sdd): M7 T4 complete — ledger`).
**Commits:** `1c75ac9d` docs, `9b2c6f85` seed; this report commit follows.

The rotation ran before the docs/seed commits, so the script recorded the
truthful rotation-time HEAD `389e0030` in `release/seed/CHANGELOG.md`; the
entry was left exactly as generated.

---

## Docs changes

- `examples/z98/z9play/NOTES.md`
  - Status line appends M7 as complete (Tasks 0–5).
  - Build recipe moved to the current seed v102 (archive md5 + binary/fixed
    point) while preserving historical v101/M6 entries.
  - New TUI build/run and `--dump-c89` section (`ui.zig` separate root,
    pty/Win9x gate, terminal-restore/keys/layout).
  - New M7 milestone-log section: `std_file` API and semantics, TUI, tier,
    seed rotation, defect status, commit chain, and the separate Task 6.
  - Clarified that the old M0–M5 D1–D8 were the **pre-reset** numbering;
    current **D1/D2 FIXED, D3/D4/D5 OPEN**.
- `examples/z98/z9play/README.md`
  - M7 status paragraph, M7 Files list, TUI build/run recipe and gate,
    current seed v102 pins, TUI `--dump-c89` pin, Win9x PE32/import truth,
    and operator-pending hardware status.
  - Historical M0–M6 entries preserved.
- `docs/sf/QUICK_REF.md`
  - Current seed block is **v102**: archive
    `702f34d87b7e6bf401dd206d2517dbee`, archived binary/fixed point
    `b299b4b435e624d0ddbd2edde681cbc3`, `gen/` unchanged, `lib/` 32 std
    `.zig` including the M7 `std_file` iteration.
  - Rotation-history chain appends v102.
  - New concise `std_file` directory-iteration API section (`DirEntry{name,
    is_dir}`, `Dir`, open/read/close, caller-arena names, no `.`/`..`
    filtering, Linux `DT_UNKNOWN` `stat` fallback, Win9x
    `FindFirstFileA`/`FindNextFileA`/`FindClose`, no `std.fs` namespace).
  - 8-pin table header/note moved to v102 and a v102 re-measure paragraph
    added; historical notes retained.

No claim of Win98/Me hardware verification was added; the docs say
design-verified / operator-pending.

## Seed rotation (commands + observed results)

1. Rebuild from the committed v101 seed:

```bash
rm -rf /tmp/m7_t5_seed
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m7_t5_seed
md5sum /tmp/m7_t5_seed/zig1_5_clean
```

Observed:

```text
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/m7_t5_seed ===
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed/zig1_5_clean
```

2. Rotate with the seed-built binary and `gen/`:

```bash
bash scripts/seed/archive_seed.sh /tmp/m7_t5_seed/zig1_5_clean /tmp/m7_t5_seed/gen \
    release/seed/zig1-seed.tgz --update-changelog
```

Observed:

```text
[archive] gcc-only rebuild of archive C md5 (fixed point): b299b4b435e624d0ddbd2edde681cbc3
[archive] wrote release/seed/zig1-seed.tgz (archive md5 702f34d87b7e6bf401dd206d2517dbee)
## 2026-10-19 — seed v102 (HEAD 389e0030)
...
| archive md5 | `702f34d87b7e6bf401dd206d2517dbee` |
[archive] prepended entry to release/seed/CHANGELOG.md
```

Archive md5: **v101 `378f5ea01db25ec69f455fbce52bc947` → v102
`702f34d87b7e6bf401dd206d2517dbee`**.
Archived binary / fixed point: `b299b4b435e624d0ddbd2edde681cbc3` (unchanged).

3. Verify the rotated seed:

```bash
rm -rf /tmp/m7_t5_seed2
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m7_t5_seed2
md5sum release/seed/zig1-seed.tgz
md5sum /tmp/m7_t5_seed2/zig1_5_clean
```

Observed:

```text
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/m7_t5_seed2 ===
702f34d87b7e6bf401dd206d2517dbee  release/seed/zig1-seed.tgz
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
```

The archive `lib/` contains 32 std `.zig` files and the new
`openDir`/`readDir`/`closeDir` in `std_file.zig`.

## Gates

### stdlib dir fixture

```bash
bash scripts/stdlib/run_fixtures.sh /tmp/m7_t5_seed2/zig1_5_clean \
    repro/mi_matrix/stdlib_dir_iter_xmod
```

Observed:

```text
PASS repro/mi_matrix/stdlib_dir_iter_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

### stdlib gate

```bash
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t5_seed2/zig1_5_clean
```

Observed:

```text
run_fixtures: 286 PASS / 0 FAIL over 286 dirs
STDLIB GATE OK
```

### 8 dump pins (old → new)

Command (repo root, relative entry paths, `--dump-c89`, `md5sum`; stderr
suppressed so compiler warnings cannot interleave with the hash line):

```bash
for mode in -fsafe -ffast; do
  for e in examples/z98/mud_server/main.zig examples/z98/game_of_life/main.zig \
           examples/z98/lisp_interpreter_curr/main.zig examples/z98/json_parser/main.zig; do
    /tmp/m7_t5_seed2/zig1_5_clean "$mode" --dump-c89 "$e" 2>/dev/null | md5sum
  done
done
```

| Entry | Mode | v101 | v102 | Result |
|---|---|---|---|---|
| `mud_server` | `-fsafe` | `35ec8c8c1158e260c328212ac5fdc013` | `35ec8c8c1158e260c328212ac5fdc013` | unchanged |
| `game_of_life` | `-fsafe` | `4a963f79e08c67329f4fff46530090e4` | `4a963f79e08c67329f4fff46530090e4` | unchanged |
| `lisp_interpreter_curr` | `-fsafe` | `4939b6e20eb4ee3d519fc3fd91e6e0d6` | `4939b6e20eb4ee3d519fc3fd91e6e0d6` | unchanged |
| `json_parser` | `-fsafe` | `95f82c77058e2f5647f9711a14448a79` | `95f82c77058e2f5647f9711a14448a79` | unchanged |
| `mud_server` | `-ffast` | `3203868ad4b435e8c1968fedf9284695` | `3203868ad4b435e8c1968fedf9284695` | unchanged |
| `game_of_life` | `-ffast` | `03a18737b641a6a95c67aec71daed3f7` | `03a18737b641a6a95c67aec71daed3f7` | unchanged |
| `lisp_interpreter_curr` | `-ffast` | `a2afe23d87d35eb741464423a382c0f8` | `a2afe23d87d35eb741464423a382c0f8` | unchanged |
| `json_parser` | `-ffast` | `96fdbc4c6e6e76209cc2b27a6b959482` | `96fdbc4c6e6e76209cc2b27a6b959482` | unchanged |

**8/8 unchanged.** No pin moved, so no mover explanation is required.

### TUI gate on the rotated seed

```bash
ZIG=/tmp/m7_t5_seed2/zig1_5_clean bash examples/z98/z9play/tests/tier_tui.sh
```

Observed:

```text
driver: total=32 passed=32 failed=0
ok   - file: .../z9play-tui.exe: PE32 executable (console) Intel 80386 ...
imports: KERNEL32.DLL WINMM.DLL
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
--dump-c89 md5: e7bc57a2a38a72cb83f51a1ce7497239
ok   - --dump-c89 md5 recorded stable 2x: e7bc57a2a38a72cb83f51a1ce7497239
== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
```

TUI `--dump-c89` was also measured directly twice:
`e7bc57a2a38a72cb83f51a1ce7497239` both times.

### Battery scope

No corpus/goldens/examples battery was run: M7 Task 1 changes only the archive
`lib/` payload (`std_file`), not the compiler, and the 8-pin re-measure proves
the emitted C did not move. The std fixture + full stdlib gate and the TUI tier
were run on the rotated seed instead.

### Touch set

Docs commit `1c75ac9d`: `docs/sf/QUICK_REF.md`,
`examples/z98/z9play/NOTES.md`, `examples/z98/z9play/README.md`.
Seed commit `9b2c6f85`: `release/seed/zig1-seed.tgz`,
`release/seed/CHANGELOG.md`. No compiler/std/TUI behavior edits. `run.err`,
`run.out`, and dirty `progress.md` were left alone.

## Concerns

1. **Inherited WAV-sink lifetime (not an M7 regression).** `audio_wavfile.zig`
   has one global output path; switching tracks reopens/truncates
   `Z9PLAY_WAV_OUT`. The TUI tier plays one track before asserting payload
   completeness. Recorded by T3/T4.
2. **Debug-build decode speed.** The tier waits for the explicit `Ended` frame
   (240 s bound) rather than assuming real-time decode; this remains true for
   the rotated-seed run.
3. **Win98/Me hardware is not verified.** `-osw` proves PE32, KERNEL32+WINMM
   only, and no msvcrt; 80×25 conhost rendering/raw-mode behavior on real
   hardware remains design-verified / operator-pending.
4. **Defect status remains D1/D2 FIXED, D3/D4/D5 OPEN.** No new defect shape was
   encountered in T5.
5. **Task 6 (M8 amendment review) is separate.** The M7 plan carries no status
   field, so this closeout does not mark it done.
6. **CHANGELOG HEAD is capture-time.** It records `389e0030` because rotation
   ran before the docs commit; the entry was left truthful rather than
   hand-rewritten.
