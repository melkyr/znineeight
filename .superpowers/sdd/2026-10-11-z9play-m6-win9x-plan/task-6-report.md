# M6 Task 6 report — M7 amendment review

**Status:** BLOCKED — M7 requires an amendment before it can execute.

**Base:** `4989835b` (`docs(sdd): T5.6 complete — ledger`).

**Scope:** judgment/report only. No source or plan edits; no push; `run.err`,
`run.out`, and `progress.md` were left untouched. Evidence is from the
working tree at the base commit plus the committed M6 reports.

---

## Verdict

**I found the intention is for M7 to run unchanged on seed v98 and add
directory iteration with edits limited to `std_file`, but this is
impossible/incomplete given the current seed v101, the 9x no-CRT/closed-world
import gate (which does not allow `FindNextFileA`), and the archive `lib/`
payload rotation requirement.**

The `Console` contract itself is complete on both platforms; there is no
missing console op. The blocking gaps are M7-plan staleness and the missing
Win9x directory-iteration gate/authorization, not the vtable.

The exact proposed amendment text is in §4. **STOP-present** pending operator
approval.

---

## 1. Console vtable coverage on Linux and Win9x

**Result: complete. All 9 contract operations exist on both platforms and are
already assembled by `main.zig`.** No missing operation or incompatible
signature.

Contract: `examples/z98/z9play/platform/console.zig:37-44` defines `Key`
(`none`/`char`/`sigint`/arrows/`enter`/`esc`);
`platform/console.zig:49-59` defines the 9-op `Console` vtable
(`clear`, `setCursor`, `writeStr`, `readKey`, `enterRaw`, `leaveRaw`, `width`,
`height`, `cursorShow`).

| op | Linux backend | Win9x backend |
|---|---|---|
| `enterRaw` | `console_linux.zig:145` | `console_win9x.zig:126` |
| `leaveRaw` | `console_linux.zig:167` | `console_win9x.zig:153` |
| `readKey` | `console_linux.zig:198` | `console_win9x.zig:166` |
| `writeStr` | `console_linux.zig:269` | `console_win9x.zig:206` |
| `clear` | `console_linux.zig:275` | `console_win9x.zig:216` |
| `setCursor` | `console_linux.zig:305` | `console_win9x.zig:236` |
| `cursorShow` | `console_linux.zig:323` | `console_win9x.zig:244` |
| `width` | `console_linux.zig:336` | `console_win9x.zig:259` |
| `height` | `console_linux.zig:346` | `console_win9x.zig:270` |

Selection/assembly is present in `examples/z98/z9play/main.zig:68-70`
(imports), `main.zig:696-729` (both vtable literals under `@isWindows()` with an
explicit `else`), and `main.zig:896` (explicit `leaveRaw` before the final
exit).

Semantics relevant to the TUI:

- **Non-echoed, non-blocking keys** are implemented on both sides. Linux
  clears `ECHO`/`ECHONL`/`ICANON` and uses `VMIN=0`/`VTIME=0`
  (`console_linux.zig:103-108,155-159,177-181`); Win9x clears
  `ENABLE_LINE_INPUT`/`ENABLE_ECHO_INPUT` and uses
  `GetNumberOfConsoleInputEvents` before `ReadConsoleInputA`
  (`console_win9x.zig:71-74,141,169-178`). Arrow/Enter/Esc/Ctrl-C mapping is
  present on both (`console_linux.zig:198-263`,
  `console_win9x.zig:183-197`).
- **Cursor addressing/clear/size/cursor visibility** are implemented on both
  (table above). Linux uses ANSI; Win9x uses
  `FillConsoleOutputCharacterA`/`SetConsoleCursorPosition`/
  `GetConsoleScreenBufferInfo`/`GetConsoleCursorInfo`.
- **One semantic caveat:** Win9x `width`/`height` return the screen-buffer
  size (`dwSize.X/Y`), not the visible window (`srWindow`)
  (`console_win9x.zig:42-45,257-276`). A Win9x console whose buffer is larger
  than its visible window can therefore make a TUI that trusts `width`/`height`
  draw outside the visible 80×25 window. M7 should pin the blueprint's 80×25
  layout or clamp to the visible window; this is a TUI assumption issue, not a
  missing vtable op. (The M6 T2 report already recorded the same concern:
  `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-2-report.md:189-191`.)
- Win9x output/cursor calls are console-handle operations; with redirected
  stdout they fail harmlessly (`console_win9x.zig:46-49`). The TUI is
  console-oriented, so this is acceptable.

No amendment is required for the `Console` vtable shape itself.

---

## 2. M7 directory-iteration shape/API against current `std`

**Result: the proposed API shape is still workable and does not need a
rewrite, but M7 is incomplete as written: it misses a required gate
authorization and several ownership/semantics decisions.**

M7's proposed surface (`docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md:39`):

```zig
pub const DirEntry = struct { name: []const u8, is_dir: bool };
pub fn openDir(arena, path: []const u8) !Dir;
pub fn readDir(arena, d: *Dir) !?DirEntry;
pub fn closeDir(d: *Dir) void;
```

Findings:

- **The optional/error shape is compatible with the current compiler.** D1 is
  fixed at root cause (`examples/torrent_example_defects.md:15-17`), and M7's
  `!?DirEntry` is a normal error-union/optional return, not the M5b
  function-pointer-return shape. The `Key.none` example workaround remains
  retained, but it does not constrain this API.
- **`std.fs` is conceptual, not a current namespace.** `sf/src/std.zig:1-13`
  exports only the core 13 modules and does not export `fs`; file I/O is the
  path-imported `std_file` (`sf/src/std_file.zig:1-31`, imported in
  `main.zig:59` as `@import("std_file")`). M7 already names the actual files
  correctly (`m7 plan:23,38`), but docs/task titles should say `std_file`, not
  imply a new `std.fs` namespace.
- **`std_file` has no directory API today.** Its public surface is
  `open`/`read`/`write`/`seek`/`size`/`flush`/`exists`/`mtime`/`remove`/
  `rename`/`readAll`/`writeAll` (`sf/src/std_file.zig:256-378`); no
  `openDir`/`readDir`/`closeDir`/`DirEntry` exists in `sf/src`.
- **The Windows implementation needs a `WIN32_FIND_DATAA` mirror or a PAL
  helper.** The authorized prelude already supplies `<windows.h>` on `_WIN32`
  and `<unistd.h>` elsewhere (`sf/src/include/std_os_prelude.h:8-16`;
  included by `sf/src/std_file.zig:22` and
  `sf/src/std_file_pal.zig:15`). The Win9x API calls themselves
  (`FindFirstFileA`/`FindNextFileA`/`FindClose`) are KERNEL32/Win9x-safe, so
  the no-CRT profile is compatible. `std_file_pal.zig:21-36` currently has
  no `FindFirstFileA`/`FindNextFileA`/`FindClose` externs; Task 1 adds them.
  Linux needs `@cInclude("<dirent.h>")` and a `struct dirent` mirror/field
  probe (the same opaque-layout pattern as `std_file.zig:82-93`), because
  Z98 cannot use the C type directly.
- **HARD BLOCKER — the closed-world 9x import gate does not allow
  `FindNextFileA`.** The 9x KERNEL32 whitelist lists `FindFirstFileA` and
  `FindClose` but **not** `FindNextFileA`
  (`scripts/win32_cross/check_win9x_imports.sh:26`), and the gate fails any
  unknown import on the 9x profile (`check_win9x_imports.sh:74`). M7's
  `readDir` necessarily imports `FindNextFileA` on Win9x. M7's touch set
  allows only `sf/src/std_file.zig` (+`std_file_pal.zig`), fixture, and
  `expected_dirs.txt` (`m7 plan:17`), so it does **not** authorize the
  required whitelist edit. Without an amendment, a Win9x TUI/dir-iteration
  build cannot pass the 9x import gate.
- **API ownership must be stated.** `readDir(arena, d)` should copy the entry
  name into the caller arena; `Dir` must hold the OS handle plus Win9x's
  first-entry/pending state; `closeDir` closes the handle. The plan currently
  does not say whether `.`/`..` are returned (Linux `readdir` does, Win32
  `FindFirstFile` commonly does not), nor what `is_dir` does when Linux
  `d_type == DT_UNKNOWN`. These are implementation-contract gaps, not reasons
  to change the API shape.

The intended one-shot `readAll` alternative in `m7 plan:39` is also viable for
small directories, but streaming `readDir` is fine if the ownership points
above are fixed.

---

## 3. Is M7 stale against the current milestone state?

**Yes. M7's seed/defect note predates the M6 rotations and the no-CRT
truth-up.**

- **Seed:** M7 says base seed **v98**, fixed point
  `f18b69ece1917bf970a036b276e5e403` (`m7 plan:19`). The committed seed is
  **v101**, fixed point `b299b4b435e624d0ddbd2edde681cbc3`, archive md5
  `378f5ea01db25ec69f455fbce52bc947`
  (`docs/sf/QUICK_REF.md:27-30`; `release/seed/CHANGELOG.md:14-30`).
- **Defects:** M7 says "D1–D8 are all FIXED in seed v98"
  (`m7 plan:19`). Current status is D1 and D2 fixed at root cause
  (`examples/torrent_example_defects.md:15-17,115-117`), but D3 is OPEN/
  deferred (`:190-192`), D4 is OPEN (`:206-208`), and D5 is OPEN
  (`:232-234`). The file's own header also says the old D1–D8 numbering was
  reset (`:1-8`). M7's blanket claim is stale and should not be inherited.
- **Win9x no-CRT default:** M6 made `-osw` default to the 9x no-CRT profile
  (mingw `-DZIG_NO_CRT -nostdlib ... -lkernel32`, no msvcrt)
  (`task-5.4-report.md:26-33`; `task-5.5-report.md:72-80,155-161`). M7 does
  not mention the no-CRT build/import gate at all (`m7 plan:53-57`). Directory
  iteration on Win9x must stay KERNEL32-only and the M7 tier must run the 9x
  import gate.
- **Hardware verification pending:** M6 explicitly leaves native
  MSVC/OpenWatcom scripts and real Win98/Me hardware design-verified only
  (`task-5.5-report.md:179-184`; `task-5.4-report.md:51`; M6 plan Amendment
  5). M7 docs must not claim hardware verification.
- **Seed rotation:** M7 says "compiler fixed point unchanged"
  (`m7 plan:17`), which is true for the compiler self-emission because the
  compiler does not import std modules (`docs/sf/QUICK_REF.md:92-95`).
  However, the seed archive embeds the std `lib/` payload
  (`scripts/seed/archive_seed.sh:115-117`;
  `scripts/seed/build_from_seed.sh:146`), and the rotation protocol requires a
  rotation when the archive's `lib/` payload changes
  (`docs/sf/QUICK_REF.md:128-131`). M7 changes `std_file.zig`/`std_file_pal.zig`,
  so closeout must rotate v101 → v102 even though the fixed point is expected
  to remain `b299b4b435e624d0ddbd2edde681cbc3`. M7 currently has no such gate.
- **Win9x console is delivered:** M7's Task 2 only records the M5b Linux
  backend (`m7 plan:42-46`). M6 has already delivered the complete Win9x
  backend (`console_win9x.zig` all 9 ops; selected in `main.zig:698-712`).
  M7 should record that as an M6 handoff, not leave the impression only Linux
  exists.
- **Win9x TUI gate is missing:** M7's stated goal includes Win9x
  (`m7 plan:5`), but Task 4 only builds/pty-tests the Linux TUI
  (`m7 plan:53-57`). At minimum M7 should emit/build the TUI for `-osw`, check
  PE32/no-msvcrt/imports, and keep real-hardware claims pending.

---

## 4. Exact proposed M7 amendment text

Append the following amendment to
`docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md` (and apply the
superseding clause to its Global Constraints):

```markdown
### Amendment 1 — M6 handoff truth-up: seed v101, no-CRT Win9x, dir-iteration
gate (operator ruling, 2026-10-18)

This amendment supersedes the "NOTE 2026-10-16" seed/defect clause in the
Global Constraints and adds the missing Win9x directory-iteration
authorization/gate. It does not change the TUI feature set or the Console
contract.

- **Base seed is v101**, not v98: `release/seed/zig1-seed.tgz` (archive md5
  `378f5ea01db25ec69f455fbce52bc947`), rebuilt binary/fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`. Rebuild with
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` for
  every M7 build/gate.
- **Defect status:** D1 and D2 are FIXED at root cause and are included in
  seed v101; the M5b `Key.none` and M6 example workarounds remain. Do not say
  "D1–D8 are all FIXED": `examples/torrent_example_defects.md` currently lists
  D3 (conditional `@import` lazy-load) OPEN/deferred, D4 (static-analyzer
  cluster) OPEN, and D5 (`extern fn` with a body) OPEN. If a new defect shape
  is hit, STOP-present, apply the minimal example-only workaround, and record
  it in `examples/torrent_example_defects.md`.
- **Win9x profile is 9x no-CRT by default:** `-osw` emits
  `-DZIG_NO_CRT -nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32` (plus
  `-lwinmm`/`-lwsock32` only when used). The Task 1 Win9x directory backend
  must use only KERNEL32 `FindFirstFileA`/`FindNextFileA`/`FindClose`; it must
  not introduce msvcrt or CRT dependencies. Native MSVC/OpenWatcom `.bat`
  scripts remain design-verified only; real Win98/Me hardware verification is
  operator-pending, and M7 docs must say "design-verified; hardware
  verification pending".
- **Task 1 touch-set addition:** add
  `scripts/win32_cross/check_win9x_imports.sh` to the M7 touch set and add
  `FindNextFileA` to its `KERNEL32_9X` list. The closed-world 9x import gate
  currently allows `FindFirstFileA`/`FindClose` but not `FindNextFileA`;
  without this, any z9play `-osw` build that calls `readDir` fails the gate.
  This is the only script change authorized by this amendment.
- **Seed rotation:** because Task 1 changes `sf/src/std_file.zig` /
  `std_file_pal.zig`, the archive `lib/` payload changes. At M7 closeout
  rotate seed **v101 → v102** per `docs/sf/QUICK_REF.md` (archive +
  `release/seed/CHANGELOG.md` + QUICK_REF seed/pins), even though the compiler
  self-emission fixed point is independent and expected to remain
  `b299b4b435e624d0ddbd2edde681cbc3`. The M7 gate must record the rotation.
- **M6 console handoff:** `platform/console_win9x.zig` is complete (all 9
  `Console` ops) and is selected by `@isWindows()` in `main.zig`; M7 Task 2 is
  confirmation only, and Task 3 may consume either backend. Reuse the M5/M6
  raw-mode discipline: call `leaveRaw` before every `std.os.exit` path; the
  Win9x backend's `atexit` restore is only a crash backstop.
- **Win9x TUI gate:** add to Task 4: emit/build the TUI for `-osw` (default 9x
  no-CRT), assert PE32, no msvcrt, and the `check_win9x_imports.sh <exe> 9x`
  gate. Keep the pty behavior assertions on Linux; Wine smoke is allowed but
  is not a substitute for the operator-pending Win98/Me hardware check.
- **TUI size semantics:** Win9x `width`/`height` return the screen-buffer size
  (`dwSize`), not the visible window (`srWindow`). M7 must pin the layout to
  the 80×25 visible window (or clamp to it) and must not assume the reported
  size is the visible rectangle.
- **Directory API clarifications (no shape change):** `DirEntry.name` is
  caller-arena-owned; `Dir` holds the OS handle plus the Win9x
  first-entry/pending state; `readDir` copies each name into the caller arena;
  `closeDir` closes the handle. Do not assume `readDir` filters `.`/`..`; the
  TUI synthesizes `..`. On Linux, `is_dir` must fall back to `stat` when
  `d_type == DT_UNKNOWN`. Use `std_file` naming in code/docs; there is no
  `std.fs` namespace in `sf/src/std.zig`.
```

---

## 5. Concerns / notes

1. **Console vtable: no amendment needed.** All 9 operations are present and
   wired on both platforms. The only semantic caveat is Win9x `width`/`height`
   reporting buffer size rather than visible-window size, addressed in the
   proposed amendment's TUI-size clause.
2. **Directory API: no rewrite needed.** The proposed `DirEntry`/
   `openDir`/`readDir`/`closeDir` shape is workable; the amendment adds the
   missing ownership, dot-entry, and `is_dir` decisions.
3. **The hard blocker is mechanical:** `FindNextFileA` is absent from the 9x
   KERNEL32 whitelist, and M7's touch set does not authorize the whitelist
   edit. This would fail the z9play Win9x import gate as soon as the TUI calls
   `readDir`.
4. **Seed rotation is required by the existing protocol**, not a compiler
   fixed-point move: `std_file` is part of the archive's `lib/` payload
   (`scripts/seed/archive_seed.sh:115-117`).
5. No source/plan files were changed by this review. `run.err` (untracked),
   `run.out`, and `progress.md` were left alone.
