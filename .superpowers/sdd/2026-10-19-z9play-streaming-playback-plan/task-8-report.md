# M9 Task 8 report — Win9x build instructions in z9play/z9torr READMEs

**Status:** PASS. Docs-only; no gate rerun. No push.

**Branch:** `zig1_improvements`

## Commits

| Purpose | Commit | Message |
|---|---|---|
| z9play README | `75b650b6` | `docs(z9play): Windows 9x build instructions` |
| z9torr README | `05c70a31` | `docs(z9torr): Windows 9x build instructions` |
| This report | (see `git log`) | `docs(sdd): M9 T8 report` |

## Files changed

- `examples/z98/z9play/README.md` — replaced the `### Windows 9x (M6)` build
  recipe with the current seed v102 procedure: seed rebuild, archive md5
  `702f34d87b7e6bf401dd206d2517dbee`, fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`, `-fsafe -osw`, separate CLI
  (`main.zig` → `z9play.exe`) and TUI (`ui.zig` → `z9play-console.exe`) output
  dirs, `check_win9x_imports.sh ... 9x` (PE32 / KERNEL32+WINMM / no msvcrt),
  copy EXE + `.ogg`/`.flac` to Win98 and run from an MS-DOS Prompt. Kept the
  `demo/win9x_README.txt`, native `*_nocrt.bat` / `*_crt.bat`, `-osw nt`, and
  hardware-pending pointers.
- `examples/z98/z9torr/README.md` — added `## Building for Windows 9x (seed
  v102)` before the historical M6/M5 sections: seed rebuild + md5s, `-fsafe
  -osw` client build (`main.zig` → `z9torr.exe`), import check (PE32 /
  KERNEL32+WSOCK32 / no msvcrt), optional `mock_tracker`/`mock_peer` builds, and
  pointers to `demo/win9x_README.txt`, native scripts, `-osw nt`, and the
  hardware-pending caveat.

Only these two READMEs were edited; no source, tests, demo, plans, seed, or
`progress.md` changes.

## Verification

```text
$ git diff --check
(clean)

$ git diff --stat
 examples/z98/z9play/README.md | 48 +++++++++++++++++++++++++++++++-----------
 examples/z98/z9torr/README.md | 49 +++++++++++++++++++++++++++++++++++++++++++
 2 files changed, 85 insertions(+), 12 deletions(-)
```

Both recipes use seed v102 (`b299b4b435e624d0ddbd2edde681cbc3`) and
`-fsafe -osw`. Commits were made separately per README. `lin_bin/`, `run.err`,
and `progress.md` were not touched.

## Concerns

- Hardware verification remains operator-pending; the READMEs explicitly do not
  claim a real Win98/Me run.
- `run.err` remains untracked (pre-existing; not touched, not committed).
