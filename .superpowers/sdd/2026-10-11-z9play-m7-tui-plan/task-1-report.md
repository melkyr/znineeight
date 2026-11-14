# M7 Task 1 report — `std_file` directory iteration

**Status:** DONE. No STOP condition. No compiler edits; fixed point unchanged.
**Branch:** `zig1_improvements`
**Commit (a):** `e4c07f9a` — `feat(std_file): directory iteration (openDir/readDir/closeDir)`
**Base seed:** v101, archive md5 `378f5ea01db25ec69f455fbce52bc947`.
**Rebuilt binary/fixed point:** `b299b4b435e624d0ddbd2edde681cbc3` (unchanged).

---

## Implement

### API (`sf/src/std_file.zig`)

Added, per Task 1 / T0 §1.1:

```zig
pub const DirEntry = struct { name: []const u8, is_dir: bool };

pub const Dir = struct {
    handle: *void,
    first_pending: bool,
    data: pal.Win32FindDataA,
    path: []const u8,
};

pub fn openDir(arena: *arena_mod.Arena, path: []const u8) FileError!Dir;
pub fn readDir(arena: *arena_mod.Arena, d: *Dir) FileError!?DirEntry;
pub fn closeDir(d: *Dir) void;
```

- `FileError` extended with `OpenDirFailed, ReadDirFailed` (the latter reserved;
  current `readDir` failures are `OutOfMemory`).
- `DirEntry.name` is copied into the caller arena via `arena_mod.alloc`; names
  are not NUL-terminated. `Dir.path` is arena-owned.
- `readDir` streams in OS order and returns `null` at end-of-listing. It does
  not filter `.`/`..`.
- Added `@cInclude("<dirent.h>")` (unconditional; MinGW supplies it and the
  POSIX body is pruned under `@isWindows()`) and `STAT_MODE_OFFSET = 16`.

### Linux (`opendir`/`readdir`/`closedir`)

- `openDir`: `cstr` path, `opendir`; `null` → `OpenDirFailed`; arena-copies
  `path` into `Dir.path`.
- `readDir`: `readdir`; `null` → `null`; casts `*void` to `*pal.PosixDirent`;
  copies `d_name` up to NUL into the caller arena; `is_dir = d_type == DT_DIR
  (4)`. On `DT_UNKNOWN (0)` calls `posixIsDir`, which builds
  `path + "/" + name`, calls `pal.stat`, reads `st_mode` at offset 16, and tests
  `(mode & 0xF000) == 0x4000`.
- `closeDir`: `closedir`, return ignored.

### Win9x (`FindFirstFileA`/`FindNextFileA`/`FindClose`, KERNEL32 only)

- `openDir`: builds `path + "\\*"` in a stack `PATH_BUF`, trimming one trailing
  `/` or `\\`; requires room; `FindFirstFileA` into `Dir.data`; handle
  `INVALID_HANDLE_VALUE` → `OpenDirFailed`; sets `first_pending = true`.
- `readDir`: consumes the pending first entry, else `FindNextFileA`; `0` →
  `null`; copies `cFileName` up to NUL into the caller arena;
  `is_dir = (dwFileAttributes & 16) != 0`.
- `closeDir`: `FindClose`, return ignored.

### PAL (`sf/src/std_file_pal.zig`)

- `Win32FindDataA` (size 320, `cFileName@44`) + `extern "stdcall"`
  `FindFirstFileA`/`FindNextFileA`/`FindClose`, after the `pal_file_mtime`
  block.
- `PosixDirent` (size 268, `d_type@10`, `d_name@11`) + `extern "c"`
  `opendir`/`readdir`/`closedir`, after `fstat`.

### Whitelist

`scripts/win32_cross/check_win9x_imports.sh:26` — added `FindNextFileA` next to
`FindFirstFileA` in `KERNEL32_9X` (the only authorized script change).

---

## Fixture

`repro/mi_matrix/stdlib_dir_iter_xmod/` (`main.zig`, `expected.txt` =
`dir iter ok\n`, `expected.rc` = `0`).

- Uses fixture-only `extern "c" mkdir`/`rmdir` (with `<sys/stat.h>` and
  `<unistd.h>`) to create `t_dir_iter/`, `a.txt`, `b.ogg`, `sub/`,
  `sub/c.bin`; files are written through `std_file.writeAll`.
- Iterates with `openDir`/`readDir`/`closeDir`, asserts `.` and `..` were
  observed (not filtered), skips them, then sorts the three real entries
  (arena-backed `[][]const u8` plus a parallel bool array, insertion sort) and
  asserts exactly: `a.txt` false, `b.ogg` false, `sub` true.
- Cleans up files then `rmdir sub`, `t_dir_iter`; prints exactly
  `dir iter ok\n`; rc 0.
- Pinned in `scripts/stdlib/expected_dirs.txt:97`, in actual C-locale sorted
  position (after the `defer_*` entries, before `enum_init_expr`; the T0
  neighbour note was off).

---

## Gates (command → observed output)

### 1. Seed build / fixed point

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m7_t1_seed
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/m7_t1_seed ===
rc=0

$ md5sum /tmp/m7_t1_seed/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t1_seed/zig1_5_clean
```

Also verified the seed build copied the current sources into its `lib/`
(`diff -q sf/src/std_file.zig /tmp/m7_t1_seed/lib/std_file.zig` and the PAL
both silent), so the fixture gates exercised this Task 1 code, not stale seed
sources.

### 2. Targeted fixture

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m7_t1_seed/zig1_5_clean \
      repro/mi_matrix/stdlib_dir_iter_xmod
PASS repro/mi_matrix/stdlib_dir_iter_xmod
----------------------------------------
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
rc=0
```

### 3. Full stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m7_t1_seed/zig1_5_clean
...
run_fixtures: 286 PASS / 0 FAIL over 286 dirs
STDLIB GATE OK
rc=0
```

The pinned baseline was 285; this task adds one fixture, so the exact result is
286 passed / 0 failed.

### 4. Win9x `-osw` compile/link/import probe

Probe in `/tmp/m7_t1_winprobe/probe.zig` (copies of the changed `std_file.zig`,
`std_file_pal.zig`, `std_arena.zig`) calls `openDir(".")`, loops
`readDir`/`closeDir`. This is a compile/link/import-only probe: the run side
needs a Win9x filesystem, so it was not executed.

```
$ /tmp/m7_t1_seed/zig1_5_clean -osw -o /tmp/m7_t1_winprobe/out \
      /tmp/m7_t1_winprobe/probe.zig
rc=0

$ (cd /tmp/m7_t1_winprobe/out && sh build_target.sh mingw)
Built: prog.exe
rc=0

$ file /tmp/m7_t1_winprobe/out/prog.exe
PE32 executable (console) Intel 80386 (stripped to external PDB), for MS Windows, 7 sections

$ bash scripts/win32_cross/check_win9x_imports.sh \
      /tmp/m7_t1_winprobe/out/prog.exe 9x
DLL KERNEL32.DLL
IMPORT GATE PASS (9x): /tmp/m7_t1_winprobe/out/prog.exe
rc=0

$ i686-w64-mingw32-objdump -p prog.exe | grep 'DLL Name'
    DLL Name: KERNEL32.dll
```

The import table contains `FindClose`, `FindFirstFileA`, `FindNextFileA` and
only KERNEL32; no msvcrt/CRT dependency.

### 5. Touched files

```
$ git diff --stat (commit (a))
 repro/mi_matrix/stdlib_dir_iter_xmod/expected.rc  |   1 +
 repro/mi_matrix/stdlib_dir_iter_xmod/expected.txt |   1 +
 repro/mi_matrix/stdlib_dir_iter_xmod/main.zig     | 141 +++++++++++++++++++++
 scripts/stdlib/expected_dirs.txt                  |   1 +
 scripts/win32_cross/check_win9x_imports.sh        |   2 +-
 sf/src/std_file.zig                               | 147 +++++++++++++++++++-
 sf/src/std_file_pal.zig                           |  40 ++++++
 7 files changed, 331 insertions(+), 2 deletions(-)
```

All changes are in the authorized Task 1 touch set. `run.err` was left
untouched (still untracked); no other files were modified.

---

## Concerns

1. **Linux helper emission fix (within scope).** The first `-osw` link of the
   after-implementation probe failed with `undefined reference to stat`: a
   top-level helper (`posixIsDir`) was emitted even though its only caller is
   the pruned Linux `readDir` branch. Added an `if (@isWindows()) return false;
   else { ...stat... }` guard inside that helper, matching the existing
   `llseekHandle` pattern, so `-osw` emits no `stat` reference. This is an
   implementation detail, not a compiler defect; the Linux gate was re-run
   after the change (286/0) and the Win9x probe passes.
2. **`ReadDirFailed` is declared but unused.** Per T0 it is part of the module
   error set; streaming `readDir` reports `OutOfMemory` and treats
   `FindNextFileA == 0` as end-of-listing, as specified.
3. **DT_UNKNOWN fallback not forced under fixture.** The Linux fixture
   exercises `d_type`-based classification on the host filesystem; the
   `stat`/`st_mode` offset-16 path is implemented per T0 §1.2 and was proven by
   the T0 probe, not by a runtime DT_UNKNOWN directory in this gate.
4. **Win9x runtime not executed.** The Task 1 gate is compile/link/import-only;
   real Win98/Me hardware/filesystem verification remains operator-pending
   (as Amendment 1 states).
5. **`Dir.path` on Win9x** is assigned the caller slice but unused (the Win9x
   path has no `stat` fallback); the arena ownership guarantee applies to the
   Linux `DT_UNKNOWN` path.
6. No seed rotation performed (M7 closeout, v101 → v102, is a later task);
   the compiler fixed point is unchanged.
