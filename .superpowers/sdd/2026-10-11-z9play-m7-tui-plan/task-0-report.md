# M7 Task 0 report — preflight (report-only)

**Status:** READY — no STOP condition. No source, plan, or script edits were made.
The working tree was only read; probe programs were built under `/tmp`.

**Base:** branch `zig1_improvements`, base `4285ea9c` (M7 ledger init).
**Seed:** v101 archive md5 `378f5ea01db25ec69f455fbce52bc947`; rebuilt binary/fixed
point `b299b4b435e624d0ddbd2edde681cbc3`.

---

## 1. Findings

### 1.1 API shape (confirmed compatible with the current compiler)

Expose this exact surface from `sf/src/std_file.zig` (there is **no** `std.fs`
namespace; `sf/src/std.zig:1-13` does not export `fs`, and `main.zig:59` already
path-imports `std_file`):

```zig
pub const DirEntry = struct { name: []const u8, is_dir: bool };

pub const Dir = struct {
    handle: *void,                 // DIR* / FindFirstFile HANDLE
    first_pending: bool,           // Win9x: first entry already in `data`
    data: pal.Win32FindDataA,      // Win9x WIN32_FIND_DATAA mirror; unused on Linux
    path: []const u8,              // arena-owned copy; Linux DT_UNKNOWN stat fallback
};

pub fn openDir(arena: *arena_mod.Arena, path: []const u8) FileError!Dir;
pub fn readDir(arena: *arena_mod.Arena, d: *Dir) FileError!?DirEntry;
pub fn closeDir(d: *Dir) void;
```

Semantics fixed by Amendment 1 (`docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md:125-131`):

- `DirEntry.name` is **caller-arena-owned**; `readDir` copies each name into the
  caller arena (`std_arena.alloc`; `sf/src/std_arena.zig:14-19`).
- `Dir` owns the OS handle plus the Win9x first-entry/pending state. The extra
  `path` field is required to implement the Amendment's Linux `d_type ==
  DT_UNKNOWN` `stat` fallback; it is an implementation field, not an API-shape
  change.
- `readDir` does **not** filter `.`/`..` (both APIs return them; the TUI
  synthesizes its `..` entry).
- `closeDir` closes the handle and returns nothing.
- Extend the module's single error set `FileError` (`sf/src/std_file.zig:31`)
  with `OpenDirFailed` and `ReadDirFailed` (R2: one error set per module), or
  reuse `OpenFailed`/`ReadFailed`; either is compatible. `OutOfMemory` already
  exists for the name copy and the `path` copy.

The streaming `readDir` form is chosen over the plan's optional one-shot
`readAll` alternative so the TUI can stop after filling its pane without
allocating an unbounded listing. Both are explicitly allowed by
`m7-plan:39`.

Compatibility was measured with seed v101 (not assumed): a probe defining this
exact `DirEntry`/`Dir` shape and a `!?DirEntry` reader dumped, compiled with the
binding `gcc -m32 -std=c89` set, linked, and ran rc=0. Evidence in §5.1.

### 1.2 Linux implementation plan (`opendir`/`readdir`/`closedir`)

**Include** (in `sf/src/std_file.zig`, next to the existing prelude includes):
`@cInclude("<dirent.h>");`. This is also safe under `-osw`: MinGW ships
`/usr/i686-w64-mingw32/include/dirent.h`, and the Linux body is pruned by
`@isWindows()` (probe §5.4).

**Externs** (in `sf/src/std_file_pal.zig`; C prototypes come from the
`<dirent.h>` included by `std_file.zig`, matching the existing
"emitter emits no extern prototypes" rule):

```zig
pub extern "c" fn opendir(path: [*]const u8) *void;
pub extern "c" fn readdir(d: *void) *void;   // `struct dirent *`, null at end
pub extern "c" fn closedir(d: *void) i32;
```

`stat` already exists at `sf/src/std_file_pal.zig:68` and is already included via
`<sys/stat.h>` (`sf/src/std_file.zig:28`); no new stat extern is needed.

**`struct dirent` mirror** (normal Z98 struct, natural C alignment; probed on the
pinned target with `gcc 12.2 -m32`, glibc 2.36):

```zig
pub const PosixDirent = struct {
    d_ino: u32,          // offset 0
    d_off: i32,          // offset 4
    d_reclen: u16,       // offset 8
    d_type: u8,          // offset 10
    d_name: [256]u8,     // offset 11; sizeof == 268
};
```

Probe output: `dirent size=268 ino=0 off=4 reclen=8 type=10 name=11`.
Also probed: `stat size=88 mode=16 size=44 mtime=64`.

**Algorithm:**

- `openDir`: NUL-terminate via the existing `cstr` (`std_file.zig:104-112`);
  `opendir`; null → `error.OpenDirFailed`; copy `path` into the caller arena
  (for the fallback) and store it in `Dir.path`.
- `readDir`: `readdir`; null → return `null`. Cast `*void` → `*PosixDirent`
  (`@ptrCast(*PosixDirent, raw)`, the same pattern as `std_net.zig:609-614`).
  Copy `d_name` bytes up to its NUL into `arena_mod.alloc`.
  `is_dir = (d_type == 4)` (`DT_DIR`). If `d_type == 0` (`DT_UNKNOWN`), build
  `Dir.path + "/" + name`, call the existing `pal.stat` into a
  `[STAT_BUF_BYTES]u8`, read `st_mode` at offset `16`, and test
  `(mode & 0xF000) == 0x4000` (`S_IFMT`/`S_IFDIR`). The fixture adds an
  explicit `DT_UNKNOWN` fallback assertion if the host returns it; otherwise the
  probe below (which exercised the same `stat`/offset path) is the evidence.
- `closeDir`: `closedir(handle)`, ignore the return (contract is `void`).

### 1.3 Win9x implementation plan (`FindFirstFileA`/`FindNextFileA`/`FindClose`)

Only KERNEL32, no CRT/msvcrt (Amendment 1; `-osw` is no-CRT by default).

**Includes:** no new header. `sf/src/std_file_pal.zig:15` already includes
`<std_os_prelude.h>`, whose `_WIN32` branch includes `<windows.h>`
(`sf/src/include/std_os_prelude.h:8-14`). `sf/src/std_file.zig:22` includes the
same prelude at the call site.

**Externs** (in `sf/src/std_file_pal.zig`; `extern "stdcall"` like the existing
Win32 file APIs at lines 21-34):

```zig
pub extern "stdcall" fn FindFirstFileA(
    lpFileName: [*]const u8, lpFindFileData: *Win32FindDataA) *void;
pub extern "stdcall" fn FindNextFileA(
    hFindFile: *void, lpFindFileData: *Win32FindDataA) i32;
pub extern "stdcall" fn FindClose(hFindFile: *void) i32;
```

**`WIN32_FIND_DATAA` mirror** (probed with the i686 MinGW headers; normal Z98
struct, natural C alignment):

```zig
pub const Win32FindDataA = struct {
    dwFileAttributes: u32,        // offset 0
    ftCreationTime_low: u32,      // 4
    ftCreationTime_high: u32,     // 8
    ftLastAccessTime_low: u32,    // 12
    ftLastAccessTime_high: u32,   // 16
    ftLastWriteTime_low: u32,     // 20
    ftLastWriteTime_high: u32,    // 24
    nFileSizeHigh: u32,           // 28
    nFileSizeLow: u32,            // 32
    dwReserved0: u32,             // 36
    dwReserved1: u32,             // 40
    cFileName: [260]u8,           // 44
    cAlternateFileName: [14]u8,   // 304; sizeof == 320
};
```

Probe output:
`WIN32_FIND_DATAA size=320 attr=0 ctime=4 atime=12 wtime=20 sizehigh=28 sizelow=32 res0=36 res1=40 name=44 alt=304`;
`FILE_ATTRIBUTE_DIRECTORY=16 MAX_PATH=260`.

**Algorithm:**

- `openDir`: build a NUL-terminated pattern `path + "\\*"` in a stack
  `[PATH_BUF]u8` (avoid a duplicate separator if `path` ends in `/` or `\`;
  require `path.len + 2 < PATH_BUF`). `FindFirstFileA(pattern, &d.data)`;
  `@ptrToInt(h) == INVALID_HANDLE_VALUE_U` (existing constant,
  `std_file.zig:70`) → `error.OpenDirFailed`. Store the handle, set
  `first_pending = true` (the first entry is already in `d.data`), and do not
  need `path`.
- `readDir`: if `first_pending`, clear it and use `d.data`; otherwise call
  `FindNextFileA(handle, &d.data)`; return `null` when it returns 0 (the
  streaming end-of-listing contract). Copy `cFileName[0..NUL]` into the caller
  arena. `is_dir = (dwFileAttributes & 16) != 0`.
- `closeDir`: `FindClose(handle)`, ignore the return.
- Do not filter `.`/`..`; Win9x `FindFirstFileA("*")` returns them just as Linux
  `readdir` does.
- `FindNextFileA` returning 0 is treated as end-of-listing. The whitelist
  already contains `GetLastError` if T1 later wants to distinguish
  `ERROR_NO_MORE_FILES`; the plan does not require that distinction.

A standalone `-osw` probe built and linked this exact mirror/extern shape
through the emitted `build_target.sh mingw`; it produced a PE32 i386 exe whose
only DLL is KERNEL32. With the current whitelist the 9x gate fails **only**
because `FindNextFileA` is missing (evidence §5.3), which is exactly the
authorized Task 1 script edit.

### 1.4 Fixture + `expected_dirs.txt` + `verify_stdlib` plan

**New fixture:** `repro/mi_matrix/stdlib_dir_iter_xmod/` with `main.zig`,
`expected.txt` (`dir iter ok\n`), `expected.rc` (`0`).

Fixture shape (follows `stdlib_file_open_xmod`/`stdlib_file_remove_xmod`):

1. `@cInclude("<sys/stat.h>")` plus fixture-only
   `extern "c" fn mkdir(path: [*]const u8, mode: i32) i32;` and
   `extern "c" fn rmdir(path: [*]const u8) i32;`. `std_file` deliberately has
   no directory-creation API; fixture-only externs are the established
   convention (`stdlib_stdin_*` uses `extern "c"` open/dup2/close;
   `stdlib_debug_stress` uses `extern "c" fn remove`).
2. Create `t_dir_iter/`, `t_dir_iter/a.txt`, `t_dir_iter/b.ogg`,
   `t_dir_iter/sub/`, `t_dir_iter/sub/c.bin`; files via `f.writeAll`.
3. `openDir("t_dir_iter")`; loop `readDir`, skip `.` and `..`, collect
   `(name, is_dir)`. Sort by name (local insertion sort over parallel arrays,
   or `std_sort.sortStr` for names plus a lookup) and assert the exact sequence:
   `a.txt` false, `b.ogg` false, `sub` true.
4. Assert `.`/`..` were observed (not filtered) before skipping them.
5. `closeDir`; remove files; `rmdir` `sub` then `t_dir_iter` (the harness runs
   the program 3× in one scratch CWD, so cleanup is mandatory for determinism).
6. Print exactly `dir iter ok\n`; rc 0.

**Pin:** insert `repro/mi_matrix/stdlib_dir_iter_xmod` into
`scripts/stdlib/expected_dirs.txt` between the lexicographic neighbours
`stdlib_default_lib_lookup_xmod` (line 93) and `stdlib_defer_control_flow_xmod`
(line 94). Discovery is pinned set-equality (`run_fixtures.sh:126-160`); an
unpinned `stdlib_*` dir fails the gate (`run_fixtures.sh:137-149`).

**Gate commands** (seed-built compiler only):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m7_t1_seed
bash scripts/stdlib/run_fixtures.sh /tmp/m7_t1_seed/zig1_5_clean \
    repro/mi_matrix/stdlib_dir_iter_xmod
bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t1_seed/zig1_5_clean
md5sum /tmp/m7_t1_seed/zig1_5_clean
```

Expected: targeted PASS, then `STDLIB GATE OK`; md5 must remain
`b299b4b435e624d0ddbd2edde681cbc3`. `run_fixtures.sh` emits `-ffast`, compiles
every emitted `.c` with the binding flag set, links `build_target.sh linux`,
and runs 3× from a fresh scratch CWD, diffing stdout/rc
(`run_fixtures.sh:22-29,165-265`).

### 1.5 M6 console contract confirmation — 9/9 on both platforms

Confirmed against `console.zig:49-59` and the M6 Task 6 review
(`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-6-report.md:30-85`).
All nine ops exist on both backends:

| op | Linux | Win9x |
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

Assembly/selection is `main.zig:68-70` (imports) and `main.zig:696-729`
(both vtable literals under `@isWindows()`, explicit `else`); `leaveRaw` is
called on the normal exit at `main.zig:896` and in `playFail`
(`main.zig:165-166`).

Measured on seed v101:

- Linux: `tier_console.sh` → **11 passed, 0 failed / TIER_CONSOLE PASS**
  (raw mode, all key/escape cases, real `100x30` pty size, all output ops).
- Win9x under Wine: `tier_win9x.sh` → **14 passed, 0 failed, 0 skipped /
  TIER_WIN9X PASS**, including the no-CRT PE32/import gate and the console
  probe `entered=1,raw_changed=1,restored=1`.

**Win9x size caveat (relevant to Task 3):** `width`/`height` return
`dwSize.X/Y` (screen **buffer**), not `srWindow` (visible window)
(`console_win9x.zig:43-45,257-276`). Task 3 must pin/clamp the layout to the
80×25 visible window and must not assume the reported size is the visible
rectangle.

### 1.6 TUI invocation path — choose the separate `ui.zig` root

**Decision: separate root `examples/z98/z9play/ui.zig` with `pub fn main(argc,
argv)`, not a `--tui` flag.** This is the plan-consistent path:

- The plan's File Structure lists only `ui.zig` for the TUI and does not list
  `main.zig`/`cli.zig` edits (`m7-plan:27,48-51`).
- The Architecture says the TUI (`ui.zig`) owns the layout and event loop
  (`m7-plan:7`).
- The blueprint explicitly allows "a separate binary (or a `--tui` flag ...
  either works)" (`examples/z9play.txt:240`); the plan is the only authority and
  chooses the file layout that implies a separate root.
- Separate roots are already the norm (`tests/*.zig` are built directly with
  their own `pub fn main`), and the seed compiles arbitrary entry files
  (evidence: tier builds).

Exact build commands (Linux):

```bash
mkdir -p /tmp/z9play_tui
timeout 120 /tmp/m7_t1_seed/zig1_5_clean -fsafe -o /tmp/z9play_tui \
    examples/z98/z9play/ui.zig
sh /tmp/z9play_tui/build_target.sh linux /tmp/z9play_tui/z9play-tui
```

Exact build commands (Win9x default `-osw`, 9x no-CRT):

```bash
mkdir -p /tmp/z9play_tui_win
timeout 120 /tmp/m7_t1_seed/zig1_5_clean -osw -o /tmp/z9play_tui_win \
    examples/z98/z9play/ui.zig
cd /tmp/z9play_tui_win && sh build_target.sh mingw
bash scripts/win32_cross/check_win9x_imports.sh /tmp/z9play_tui_win/prog.exe 9x
```

`ui.zig` can `@import("std_file")`, `player.zig`, and `platform/console*.zig`
exactly as `main.zig` does (`main.zig:58-71`). No `main.zig` or `cli.zig` change
is required.

---

## 2. Exact T1 edit regions (file:line)

`sf/src/std_file.zig`:

1. `:22-24` — add `@cInclude("<dirent.h>");` after the existing stdio include
   (unconditional; MinGW provides the header, and the Linux body is pruned).
2. `:31` — extend `FileError` with `OpenDirFailed, ReadDirFailed` (or reuse
   `OpenFailed`/`ReadFailed`; see §1.1).
3. `:38-46` — after `File`, add `DirEntry` and `Dir` (fields per §1.1); keep
   `PATH_BUF` at `:46`.
4. `:70` — reuse `INVALID_HANDLE_VALUE_U` for `FindFirstFileA`.
5. `:92-93` — add `const STAT_MODE_OFFSET: usize = 16;` beside the existing
   stat probe constants.
6. `:252-254` — insert internal dir helpers (Linux `PosixDirent`, `DT_DIR = 4`,
   `DT_UNKNOWN = 0`, `S_IFMT = 0xF000`, `S_IFDIR = 0x4000`, name-length/copy,
   stat fallback) immediately before the
   `// --- blueprint §3 L3 public surface` comment.
7. `:389` — append the public `openDir`/`readDir`/`closeDir` implementation at
   EOF (after `writeAll`).

`sf/src/std_file_pal.zig`:

8. `:38-40` — after `pal_file_mtime`, before the POSIX section, add
   `pub const Win32FindDataA` and the three `extern "stdcall"` Find* externs.
9. `:60-69` — after `access` (or at EOF after `fstat`), add
   `pub const PosixDirent` and the three `extern "c"`
   `opendir`/`readdir`/`closedir` externs. No stat change.

`scripts/win32_cross/check_win9x_imports.sh`:

10. `:26` — add `FindNextFileA` to the `KERNEL32_9X` list (next to
    `FindFirstFileA`). This is the only authorized script change.

Fixture / pin:

11. New `repro/mi_matrix/stdlib_dir_iter_xmod/{main.zig,expected.txt,expected.rc}`
    (§1.4).
12. `scripts/stdlib/expected_dirs.txt:93-94` — insert the new fixture path in
    sorted position.

Task 4 (not T1) additionally adds `examples/z98/z9play/tests/tier_tui.sh`.

---

## 3. Risks / STOP conditions

- **STOP** if the pinned Linux `struct dirent` layout differs from the probe
  (`size 268`, `d_type@10`, `d_name@11`) or `st_mode@16`; the probe is on the
  same i386/glibc target, so this is not expected.
- **STOP** if the Win32 find-data mirror differs from the MinGW/Win9x ABI
  (`size 320`, `cFileName@44`); the i686 MinGW header probe matches.
- **STOP** if `@cInclude("<dirent.h>")` breaks `-osw`; measured OK (MinGW ships
  the header). Do not replace it with a conditional `@import` hack (D3
  conditional-import lazy-load is OPEN).
- **STOP** if the compiler rejects `!?DirEntry` or the struct/cast shape; the
  probe already dumped, built, linked, and ran rc=0, so this is not expected.
- **STOP** if a new compiler-defect shape surfaces in `sf/src` (D3/D4/D5 are
  OPEN). The compiler must not be edited; present the defect and the minimal
  example-only workaround instead of improvising.
- **STOP** if the Win9x build imports anything besides KERNEL32 (`Find*`) —
  especially msvcrt — or if the only fix is an unauthorized whitelist entry.
  Amendment 1 authorizes only `FindNextFileA`.
- **STOP** if `FindNextFileA` appears anywhere other than the KERNEL32 9x list
  edit; no other script/tooling change is authorized.
- **STOP** if T1 needs `mkdir`/`rmdir` in `std_file`; the plan does not add
  directory creation. Keep those as fixture-only externs.
- **Task 3 STOP risk:** using Win9x `width`/`height` as the visible rectangle.
  The backend returns `dwSize`; pin/clamp to 80×25 or the TUI will draw off the
  visible window. A TUI that assumes `width`/`height` is visible is a defect,
  not a compiler issue.
- **Task 3 risk:** if the operator insists on `z9play --tui`, T3 must edit
  `cli.zig`+`main.zig` (not in the plan's file list). The plan-consistent
  separate `ui.zig` root avoids that; choose it.
- **Task 4 risk:** real Win98/Me hardware verification is operator-pending; Wine
  is only a smoke test. Do not claim hardware verification.

---

## 4. Concerns

1. **Naming:** the plan/spec say `std.fs`, but the actual module is `std_file`
   (there is no `std.fs` namespace in `sf/src/std.zig`). Use `std_file` in code
   and docs, as Amendment 1 already requires.
2. **Sorting:** the OS does not sort listings. "Assert the listing sorted" means
   the fixture sorts after collection; the public API stays streaming/OS-order.
3. **Fixture setup:** `std_file` has no `mkdir`/`rmdir`, so the fixture uses
   fixture-only `extern "c"` bindings for those two POSIX calls. This does not
   expand the std API and follows existing fixture precedent.
4. **`Dir.path`:** the Linux `DT_UNKNOWN` fallback requires the original
   directory path, so `openDir` must arena-copy it into `Dir`. This is required
   by Amendment 1; it is not a public function-shape change.
5. **Win9x size semantics:** `dwSize` vs `srWindow` remains the main TUI
   assumption risk (see §1.5 and §3).
6. **Separate TUI binary:** the blueprint's `z9play --tui` phrasing is one of two
   allowed forms; the plan's file structure selects the separate `ui.zig` root.
   `tier_tui.sh` must build/invoke `ui.zig` accordingly.
7. No source/plan/script edits were made; the only untracked pre-existing file
   is `run.err`, left untouched.

---

## 5. Evidence (command → observed output)

### 5.1 API-shape / layout probe (seed v101)

Probe defined the exact `DirEntry`/`Dir` shape, the Linux dirent mirror, the
Win32 find-data mirror, a `!?DirEntry` reader, and `@sizeOf`/`@offsetOf`
assertions.

```
/tmp/t55_seedcheck/zig1_5_clean -fsafe -o /tmp/m7t0probe/out /tmp/m7t0probe/probe.zig
dump rc=0
cd /tmp/m7t0probe/out && <each emitted .c compiled with gcc -m32 -std=c89 ...>
build_target.sh linux → build rc=0
/tmp/m7t0probe/prog
run rc=0
```

### 5.2 Linux opendir/readdir/is_dir/stat probes

```
/tmp/t55_seedcheck/zig1_5_clean -fsafe -o /tmp/m7t0probe2/out /tmp/m7t0probe2/probe.zig
dump rc=0
build_target.sh linux → build rc=0
/tmp/m7t0probe2/prog
run rc=0
```

The probe listed `. .. a.txt b.ogg subdir` under a scratch directory, asserted
`subdir.d_type == 4`, and verified the `st_mode` offset-16 / `0x4000` fallback.
Host probes:

```
gcc -m32 -std=c89 ... /tmp/probe_stat_dirent.c && /tmp/probe_stat_dirent
stat size=88 mode=16 size=44 mtime=64
dirent size=268 ino=0 off=4 reclen=8 type=10 name=11
```

### 5.3 Win9x Find* probe and the whitelist gap

```
/tmp/t55_seedcheck/zig1_5_clean -osw -o /tmp/m7t0probe3/out /tmp/m7t0probe3/probe.zig
dump rc=0
cd /tmp/m7t0probe3/out && sh build_target.sh mingw
build rc=0
file /tmp/m7t0probe3/out/prog.exe
PE32 executable (console) Intel 80386 ...

bash scripts/win32_cross/check_win9x_imports.sh /tmp/m7t0probe3/out/prog.exe 9x
DLL KERNEL32.DLL
  FAIL FindNextFileA not in 9x KERNEL32 whitelist
IMPORT GATE FAILED (9x): /tmp/m7t0probe3/out/prog.exe
gate rc=1
```

`objdump -p` showed only KERNEL32 (`FindClose`, `FindFirstFileA`,
`FindNextFileA`) and the emitted recipe contains `-DZIG_NO_CRT -nostdlib
-lkernel32`. Adding `FindNextFileA` per Amendment 1 is the only missing piece.

### 5.4 `-osw` with `<dirent.h>` included

```
/tmp/t55_seedcheck/zig1_5_clean -osw -o /tmp/m7t0probe4/out /tmp/m7t0probe4/probe.zig
dump rc=0
cd /tmp/m7t0probe4/out && sh build_target.sh mingw
build rc=0
file /tmp/m7t0probe4/out/prog.exe
PE32 executable (console) Intel 80386 ...
```

### 5.5 M6 console gates on seed v101

```
ZIG=/tmp/t55_seedcheck/zig1_5_clean sh examples/z98/z9play/tests/tier_console.sh
...
== tier_console summary: 11 passed, 0 failed ==
TIER_CONSOLE PASS

ZIG=/tmp/t55_seedcheck/zig1_5_clean sh examples/z98/z9play/tests/tier_win9x.sh
...
ok   - imports are exactly KERNEL32 + WINMM (no msvcrt)
ok   - check_win9x_imports.sh 9x whitelist PASS
ok   - raw-mode restore asserted under Wine (entered=1,raw_changed=1,restored=1)
== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
TIER_WIN9X PASS
```

### 5.6 Seed/archive pins

```
md5sum release/seed/zig1-seed.tgz
378f5ea01db25ec69f455fbce52bc947  release/seed/zig1-seed.tgz

md5sum /tmp/t55_seedcheck/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/t55_seedcheck/zig1_5_clean
```
