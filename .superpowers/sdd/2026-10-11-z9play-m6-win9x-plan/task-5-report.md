# M6 Task 5 report — manual Win98 procedure + docs

**Status:** COMPLETE. **Commit:** `8567488f` (`docs(z9play): manual Win98 procedure`).

Docs-only: no `.zig`/`.sh` edits. `git show --stat 8567488f` lists only
`examples/z98/z9play/NOTES.md`, `examples/z98/z9play/README.md`, and the new
`examples/z98/z9play/demo/win9x_README.txt` (3 files, +417/−21). The demo
`.txt` is matched by the repo-wide `*.txt` ignore rule (`.gitignore:52`), so it
was force-added (`git add -f`), matching the tracked z9torr precedent
(`examples/z98/z9torr/demo/win9x_README.txt`).

## Docs inventory

| File | What changed |
|:--|:--|
| `examples/z98/z9play/demo/win9x_README.txt` (new, 209 lines) | Manual Win98 procedure: cross-build, copy set, run/keys/status/exit codes, `Z9PLAY_WAV_OUT` test override, expected console behavior, Ctrl-C Option 3, raw-mode restore + abnormal-termination recovery, waveOut limits, troubleshooting. |
| `examples/z98/z9play/NOTES.md` | Status/working-commit/MD5 truth-up (lines 3/7/9); playback backend selection updated (lines 182–191); `--dump-c89` recipe updated (lines 203–216); new M6 milestone section appended at line 769 (Tasks 0–5, compiler note, defect status, chain). |
| `examples/z98/z9play/README.md` | M6 status paragraph (line 92), M6 files block (line 207), Windows 9x build/run subsection (line 316), playback backend selection (lines 309–311), and M6 md5 note (lines 364–372). |
| `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-5-report.md` | This report (not part of the docs commit; ledger artifact). |

## Coverage vs Task 5

- **Build or copy the `.exe`:** demo §1 (lines 13–56) gives the
  `build_from_seed.sh` step (current `sf/src`, output md5
  `2c48fa702393032c2b711a8d982bd388`, fixed point
  `b0e5f3b4e580f69eacdac7bd0e07dda1`) and the `cross_build_run.sh`
  `-osw … -lwinmm` invocation; it states the output is a PE32 i386 console
  executable and gives the prebuilt-copy alternative.
- **What to copy:** demo §2 (lines 58–70): `z9play.exe` + an `.ogg`, nothing
  else; statically self-contained apart from KERNEL32/msvcrt/WINMM.
- **How to run / expected behavior:** demo §§3–4 (lines 72–142): invocation,
  options, keys, startup metadata line, `\r` status line, `Stopped at mm:ss.`,
  exit codes, and Win32-console (non-ANSI) output behavior.
- **Raw-mode restore caveat:** demo §6 (lines 158–175): normal exits restore
  explicitly (`q`, Ctrl-C, end of track, error paths) plus the `atexit`
  backstop; abnormal termination (Ctrl-Break, console close, crash, reset) may
  leave the console raw; recovery = close the window and open a fresh MS-DOS
  Prompt (no `stty sane`; `mode con` is not an input-mode reset).
- **Ctrl-C Option 3:** demo §5 (lines 144–156): processed input off → Ctrl-C is
  `KEY_EVENT` `uChar == 0x03` → `.sigint`; clean quit, `Stopped at`, exit 0;
  Ctrl-Break remains default-terminate. Backed by
  `platform/console_win9x.zig:10-26,121-148,166-200` and
  `main.zig:828-830`.
- **waveOut best-effort limits:** demo §7 (lines 177–195): manual-only real
  device path, 16-bit 44100/48000, 1/2 channels, two 500 ms buffers/blocking
  write, exit 4 on unsupported/missing device. Backed by
  `platform/audio_win9x.zig:7-24,174-189`.
- **M6 completion truth in NOTES/README:** status lines
  (`NOTES.md:3`, `README.md:92`), Win9x backends + `@isWindows()` selection
  (`NOTES.md:769-830`, `README.md:92-110`), tier 14/14 + what it gates
  (`NOTES.md:821-831`, `README.md:101-110`), md5 (`NOTES.md:9,840`,
  `README.md:364-372`), defect status (`NOTES.md:845-857`,
  `README.md:112-121`), compiler note (`NOTES.md:773-784`,
  `README.md:112-116`).
- **History preserved:** old M0–M5b dated sections were not rewritten; the
  README/NOTES edits only extend the cumulative status/history and the live
  usage/backend text.

## Defect-status check

Verified against `examples/torrent_example_defects.md`:

- Current **D1** (optional-of-aggregate fn-pointer return): **FIXED**, see
  `examples/torrent_example_defects.md:17` and the fix block at line 105.
- Current **D2** (`@isWindows()` dead-arm module leak): **FIXED**, see
  `examples/torrent_example_defects.md:117` and the fix block at line 184.
- Current **D3** (conditional-`@import` lazy-load gap): **OPEN/deferred**,
  `examples/torrent_example_defects.md:192`.
- Current **D4** (analyzer cluster): **OPEN**,
  `examples/torrent_example_defects.md:208`.
- Current **D5** (`extern fn` with a body silently dropped; no stdcall
  definitions): **OPEN**, with the M6 Amendment 1 Option 3 workaround,
  `examples/torrent_example_defects.md:234-248`.

The docs keep the 2026-10-16 numbering-reset disambiguation explicit: old
M0–M5 D1–D8 are FIXED in history; under the restarted numbering only D1/D2 are
FIXED, while D3/D4/D5 are OPEN. No “all D1–D8 fixed” claim is made about the
current ledger.

## Verification (commands + results)

Docs-only task; the full battery was **not required** (no code/tooling change).
I still re-ran the M6 gate to verify the claims recorded in the docs:

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/z9play_tier_win9x_t5 \
  sh examples/z98/z9play/tests/tier_win9x.sh
```

Result: `== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==`,
`TIER_WIN9X PASS`; `-osw --dump-c89` md5
`87856b43091e2bf5d992fc795d9764f2`; Wine parity `max_delta=1 rms_milli=36`;
console probe `entered=1,raw_changed=1,restored=1`; imports
`KERNEL32.dll msvcrt.dll WINMM.DLL`.

`md5sum /tmp/z9play_m6/zig1_5_clean` →
`2c48fa702393032c2b711a8d982bd388`. The fixed point
`b0e5f3b4e580f69eacdac7bd0e07dda1` is the recorded build result in
`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/progress.md:26`.

`git diff --check` is clean; the commit contains only docs.

## Concerns

1. **No real Win98 hardware run.** The real waveOut device path remains
   manual-only, as planned; Wine gates the WAV sink + console restore, not
   audible output. The demo says this explicitly.
2. **`--version` remains `(M5)`.** M4/M5 docs commits bumped the literal, but
   this task is binding docs-only (no `.zig` edits), so `cli.zig:85` is
   unchanged and `NOTES.md:7` says so. A future M6 closeout commit (or the M7
   seed work) should bump it if the project wants the user-facing version to
   track milestones.
3. **`*.txt` ignore trap.** `demo/win9x_README.txt` is ignored by
   `.gitignore:52`; it is tracked only because it was force-added. Future
   edits need `git add -f` (or an allow-list exception) to avoid silently
   missing it.
4. **Seed-v98 warning retained.** The docs now say the M6 compiler is rebuilt
   from current `sf/src` and that the old v98 binary still exhibits old D2;
   this is required truth, but it means the README’s Linux-tier recipe
   (`/tmp/z9play_seed`) and the M6 recipe (`/tmp/z9play_m6`) intentionally use
   different compiler builds.
5. **Untracked `run.err` left as instructed; `progress.md` is clean in this
   tree.** The report itself is left uncommitted for the ledger step.
