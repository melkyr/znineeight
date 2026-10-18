# M6 Task T5.3 report — Win9x no-CRT runtime + portable 64-bit C + native build scripts + docs + seed rotation

**Status:** DONE_WITH_CONCERNS (all committed gates green; native MSVC/OpenWatcom
scripts and real Win98 behavior remain design-verified / hardware-pending per
Amendment 5).

**Base:** `f244c7c5` (`docs(sdd): T5.3b complete — ledger`). Bootstrap compiler
`/tmp/m6/zig1_5_clean`, md5 `983ff15c251ae37a1a6c7b7fe8b7212f`.

**Code commits:**
- `6731d058` `fix(win9x): no-CRT runtime + portable 64-bit C + emitted build scripts`
- `b1e70357` `docs(win9x): Windows support matrix + emitted script docs`

A `docs(sdd): T5.3 report` commit and the seed-rotation commit (CHANGELOG +
QUICK_REF + `release/seed/zig1-seed.tgz`) follow this report.

**Scope:** `sf/src` runtime/emitter/std changes; emitted build scripts; the
Windows support doc + tech-doc stamps; seed archive/rebuild plumbing; z9torr
tier existence check/README truth-up. `run.err` / `run.out` / `progress.md` were
left untouched. No push.

---

## 1. Investigate — design deltas found while implementing

The approved T5.3a/T5.3b design was implementable. Four implementation details
had to be pinned down while applying it:

1. **argv parser storage.** The design's static-storage requirement is met with
   two buffers: `g_cmdline[32768]` (raw `GetCommandLineA`) and
   `g_argbuf[32768]` (parsed, compacted args). Parsing in place is incorrect:
   once a quoted token shortens the output, the output pointer lags the input
   pointer and eventually overwrites the start of a later token (reproduced:
   `one two three` → `e o ree`). Two buffers keep the single-threaded,
   process-lifetime, 256-arg contract and the MSVCRT quote/backslash rules.
2. **Import-pointer asm must restore `.text`.** `zig_nocrt.c` emits
   `__imp____acrt_iob_func` / `__imp___time32` in `.data` with
   `__asm__(".section .data,\"w\"")`. Without a following
   `__asm__(".text")`, GCC leaves the assembler in `.data`, so the subsequent
   shim functions (and anything after them in that TU) are emitted as
   non-executable `.data`; z9play/z9torr crashed on `execute access to
   <data>`. Both asm blocks now restore `.text`.
3. **Seed plumbing must carry `zig_nocrt.c`.** The new support file is emitted
   for every target. `archive_seed.sh` now excludes it from `gen/`, stages it
   into `runtime/`, and includes it in the archive-C fixed-point rebuild;
   `build_from_seed.sh`'s reconstruct path stages it too. This keeps the seed
   layout rule (“gen = module emission only; runtime = emitted support”) true.
4. **Pins moved from intended T5.3 changes only.** Besides the 64-bit spelling
   layer, the `std_file`/`std_os`/`std_time` PAL rewiring changes emitted helper
   calls/temp numbering, so all 8 pins move. Runtime outputs stay byte-identical
   (§3.3/§3.7); no unrelated semantic change was found.

No plan step was found impossible; therefore no STOP-present.

---

## 2. Implement — per file

### 2.1 Portable 64-bit C spelling layer
- `sf/src/include/zig_compat.h`: MSVC and OpenWatcom `z64`/`zu64` =
  `__int64`/`unsigned __int64`; `Z98_I64_C`/`Z98_U64_C` (`i64`/`ui64` on
  MSVC/OWC, `LL`/`ULL` on GCC); `Z98_I64_MAX`, `Z98_I64_MIN`,
  `Z98_U64_MAX`; the fixed-width `i8..u64/usize` typedefs are now emitted for
  OpenWatcom too (removed the `!defined(__WATCOMC__)` exclusion).
- `sf/src/include/zig_runtime.h` / `.c`: every `long long` /
  `unsigned long long` / `LL`/`ULL` / `~0ULL` / 2^63-boundary literal uses
  `z64`/`zu64`/`Z98_*`; behavior unchanged on GCC.
- `sf/src/c89_emit.zig`: carrier typedefs (`typedef z64`/`zu64`); int-literal
  writers wrap only the >2^32-1/64-bit branches (`Z98_U64_C`, `Z98_I64_C`;
  negative forms stay `-Z98_I64_C(...)`); saturation bounds are
  `Z98_I64_MAX`/`Z98_I64_MIN`/`Z98_U64_C(9223372036854775808)`/`Z98_U64_MAX`;
  enum value tables, float-hex masks, cast/wrap/flag strings and
  `writeWidth*String` use the same tokens. 32-bit literal branches are
  preserved (`""`/`u`), so 32-bit arithmetic widths do not change.
- `sf/src/emit_support.zig`: byte mirror of the same `zig_compat.h`.
- `sf/src/include/std_time_prelude.h` (+ mirror): POSIX monotonic helper mapped
  to `z64`/`Z98_I64_C` for uniformity (Windows still excludes it).

### 2.2 No-CRT runtime
- `sf/src/include/zig_nocrt.c` (new, emitted): mingw `__acrt_iob_func` +
  `__imp____acrt_iob_func` asm; MSVC `FILE _iob[3]`; OWC `__w_FILE __iob[3]`;
  `fwrite`, `getchar`/`getc`/`fgetc`/`_filbuf`, `putchar`/`putc`/`fputc`/
  `_flsbuf`; `getenv`; `_time32`/`time` + `__imp___time32` asm; `.text`
  restored after both asm blocks; empty-TU dummy off Windows/no-CRT.
- `sf/src/c_exit.c` (+ mirror): `atexit` LIFO registry (32, re-entry guard) and
  `exit` → `ExitProcess` under `_WIN32 && ZIG_NO_CRT`; `c_exit` unchanged.
- `sf/src/include/zig_pal.c` (+ mirror):
  - `pal_file_size` / `pal_file_seek64` / `pal_file_mtime`: default Win95
    `GetFileSize` / `SetFilePointer` / `FindFirstFileA`; `#ifdef ZIG_WIN_NT`
    uses `GetFileSizeEx` / `SetFilePointerEx` / `GetFileAttributesExA`.
    `INVALID_*` disambiguated with `SetLastError`.
  - `pal_getenv` (static 32768-byte buffer), `pal_wallclock_unix`
    (`GetSystemTimeAsFileTime`, 1601→Unix).
  - `mainCRTStartup` (`__stdcall` MSVC, `__cdecl` otherwise), `__main`, and
    the `GetCommandLineA` parser calling `exit(main(argc, argv))`.
- `sf/src/include/zig_runtime.c` (+ mirror): no-CRT `strlen`, overlap-safe
  `memcpy`, `strncmp`.
- `sf/src/include/std_os_prelude.h`, `std_time_prelude.h` (both sides): Windows
  `pal_file_*`/`pal_getenv`/`pal_wallclock_unix` prototypes.
- `sf/src/std_file.zig` / `std_file_pal.zig`: XP+ stdcall externs replaced by
  cdecl `pal_file_*`; `seekHandle`/`sizeHandle`/`mtime` rewired; unused Windows
  FILETIME constants removed (POSIX constants kept).
- `sf/src/std_os.zig` / `std_os_pal.zig`: Windows → `pal_getenv`, POSIX
  `getenv` kept.
- `sf/src/std_time.zig` / `std_time_pal.zig`: Windows →
  `pal_wallclock_unix`, POSIX `time` kept.

### 2.3 Emitted build scripts
- `sf/src/c89_emit.zig` `emitBuildTargetSh`: 9x default is
  `-DZIG_NO_CRT` + `-nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32
  -lwinmm` (+`-lwsock32` when net); `nt` is `-DZIG_WIN_NT` + normal CRT +
  `-lwinmm` (+`-lwsock32`); `zig_nocrt.c` is compiled/linked in both profiles.
  Header states the redistribution guarantee and “design-verified; hardware
  verification pending”.
- Four MSVC/OWC script emitters: `build_target_nocrt.bat`,
  `build_target_crt.bat`, `build_owc_nocrt.bat`, `build_owc_crt.bat`.
  - command.com-safe: `%1` only, no `%~`/`%*`/`%~dp0`, no parenthesized
    `if/else`, no `setlocal`, no `^` continuation;
  - linker command via response files (`link @z98_link.rsp` /
    `wlink @z98_link.lnk`), one short `echo` line per module/option;
  - `_nocrt`: `/NODEFAULTLIB` / `option nodefaultlibs`, custom entry,
    `libcmt.lib` / `clib3r` helper members;
  - `_crt`: no `/NODEFAULTLIB`, no custom entry, no helper lib, `/MT` or
    default static CLIB;
  - both profiles carry `ZIG_WIN_NT` in an nt dump; 9x has no profile define.
- `build_target.bat` / `build_owc.bat` remain profile-correct aliases
  (`call ..._nocrt.bat %1` for 9x, `..._crt.bat` for nt).
- `scripts/check_emit_support.sh`: adds `zig_nocrt.c`; now 8/8.
- `scripts/win32_cross/cross_nocrt.sh`: no scratch shim; links the emitted
  `zig_nocrt.o`/`c_exit.o` and all emitted objects.
- `scripts/win32_cross/check_win9x_imports.sh` (new): closed-world PE32
  per-DLL/per-import gate; `9x` rejects msvcrt and the three XP+/NT4 APIs;
  `nt` allows the 9x set plus those three and the 28 msvcrt names.

### 2.4 Seed plumbing, docs, examples
- `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`: carry
  `zig_nocrt.c` in `runtime/` and the archive-C fixed-point rebuild.
- `sf/docs/tech_docs/13_windows_support.md` (new) + INDEX row: profile ×
  toolchain × CRT matrix, redistribution policy, `_iob` per-toolchain
  rationale, env lifetime, response-file/command.com design, verification
  status.
- `sf/docs/tech_docs/07`, `08`, `11`: T5.3 stamps.
- `examples/z98/z9torr/tests/tier4_wine.sh`: checks all four new scripts plus
  the aliases; `examples/z98/z9torr/demo/win9x_README.txt`: no-CRT default /
  no msvcrt / hardware-pending wording.

---

## 3. Runtime battery (commands + observed output)

All gates were run sequentially. Unless noted, the compiler is the fresh
seed rebuild `/tmp/t53/zig1_5_clean`; the final post-rotation compiler
`/tmp/t53_seedcheck/zig1_5_clean` was used to re-confirm corpus/stdlib and
produces the same pin table.

### 3.1 Seed closure
Before rotation (moving point, fresh build from the old v98 seed):
```text
[seed] hop2 binary md5: 1ef248e0c9782cfe646de73634dae4d8
[seed] hop3 binary md5: 1ef248e0c9782cfe646de73634dae4d8
[seed] three-hop closure OK (moving point): hop2 == hop3
```
After rotation (new v99 seed):
```text
[seed] hop1 binary md5: 1ef248e0c9782cfe646de73634dae4d8
[seed] hop2 binary md5: 1ef248e0c9782cfe646de73634dae4d8
[seed] two-hop closure OK: hop1 == hop2
```

### 3.2 Corpus
```text
$ bash scripts/corpus/classify /tmp/t53/zig1_5_clean /tmp/t53_corpus.txt
wrote /tmp/t53_corpus.txt: 1133 dirs
$ grep -vE '<the 9 designed D1/D2 fixtures>' /tmp/t53_corpus.txt \
    > /tmp/t53_corpus_frozen1124.txt
$ wc -l /tmp/t53_corpus_frozen1124.txt
1124
$ md5sum /tmp/t53_corpus_frozen1124.txt
518eca1a9b5d3e1cc5a48abce214abd8
$ awk '{print $2}' /tmp/t53_corpus_frozen1124.txt | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
```
`1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`, 0 movers vs
`518eca1a…`; the 9 designed D1/D2 fixture lines are all `OK`. Re-run with
`/tmp/t53_seedcheck/zig1_5_clean`: same 1133 tree, same frozen md5/tally.

### 3.3 Goldens 5/5 (`-ffast`, CWD = example dir)
```text
gol (100 gens)          rc=0  fcbf7e7cead5082f0a8caadd5a8f0ff9  MATCH
lisp `(+ 1 2)`          rc=0  b3d9f8974da24ddbf9d389f3d7d97322  MATCH
json_parser             rc=0  8bda3d5a1ec07d14a301bc343df32bf8  MATCH
mud server              rc=0  66c8f0abb926cca7baf9a0d1692ab318  MATCH
mud client (same run)         93147d0f0bbd983a9d844fea8b7a6fa7  MATCH
```
**5/5 MATCH.**

### 3.4 mi_matrix frozen 25 + oob
```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/t53/zig1_5_clean $(cat /tmp/t53_mi25_frozen.list)
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
OOB (`slice_index_field_store_oob_xmod`, `-fsafe`):
```text
DUMP_RC=0  BUILD_RC=0  RUN_RC=133  STDOUT_BYTES=0
```
**25 PASS + oob rc 133/empty — MATCH.**

### 3.5 Examples 26/26 build + 26/26 run
Build (`-ffast -o`, entry `main.zig` or `<dir>.zig`, `build_target.sh linux`):
```text
BUILD_TALLY ok=26 fail=0
```
Run (CWD = example dir; timeout 15, mud 8; rogue `q\n`; stdin `/dev/null`):
```text
days_in_month 8c0d394c  fibonacci b53b3a3d  func_ptr_return f6a54779
game_of_life fcbf7e7c  heapsort 8cf0a784  hello 74630882
json_parser 8bda3d5a  json_parser_upgraded 8bda3d5a  json_parser_workaround dc22fa47
lisp_interpreter* 1c1f0a41 (x4)  lzw c3c7765e  mandelbrot d5966775
mud_server rc=124 9545fe1d  prime d095a94d  quicksort 45d2f0fb
rogue_mud* 3fb6709e (x2)  sort_strings c6c047cb
tco_defer 264ea6b1  tco_factorial 3d70c50b  tco_return_try 7421137a
z9play rc=1 f35b7ef7  z9torr rc=1 f666af15
RUN_TALLY ok=26 fail=0
```
All md5 prefixes match the frozen prior-milestone table.

### 3.6 Stdlib
```text
$ bash scripts/stdlib/verify_stdlib.sh /tmp/t53/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
Re-run with `/tmp/t53_seedcheck/zig1_5_clean`: identical 285/0.

### 3.7 Pins 8/8 (old → new; `--dump-c89` from repo root)
| Entry | Mode | Old (v98) | New (v99) |
|---|---|---|---|
| mud_server | `-fsafe` | `bbc02913a10af9b0b5ed0f292f4e3407` | `35ec8c8c1158e260c328212ac5fdc013` |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `3203868ad4b435e8c1968fedf9284695` |
| game_of_life | `-fsafe` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `4a963f79e08c67329f4fff46530090e4` |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `03a18737b641a6a95c67aec71daed3f7` |
| lisp_interpreter_curr | `-fsafe` | `6da05d070acd414674b1b1ec947baa5c` | `4939b6e20eb4ee3d519fc3fd91e6e0d6` |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `a2afe23d87d35eb741464423a382c0f8` |
| json_parser | `-fsafe` | `af3823fae0b29fa4d4ca58932538d631` | `95f82c77058e2f5647f9711a14448a79` |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `96fdbc4c6e6e76209cc2b27a6b959482` |

All 8 moved. Diff inspection (`/tmp/m6` vs new compiler, hello) shows the
expected 64-bit spelling substitutions, plus the intended std PAL rewiring
(`std_os.env` / `std_file` / `std_time` helper calls and temp numbering);
runtime goldens are unchanged. Re-measured with the fixed-point compiler
`1ef248e0…`: identical values.

### 3.8 Markers
```text
$ /tmp/t53/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig \
    > /tmp/t53_markers.c 2> /tmp/t53_markers.bin
3437 /tmp/t53_markers.bin
38408 /tmp/t53_markers.bin
```
Pre-change anchor was `3436 / 38371`; the +1 line / +37 bytes are the intended
std PAL/emitter support emission.

### 3.9 `check_emit_support.sh`
```text
$ bash scripts/check_emit_support.sh /tmp/t53/zig1_5_clean
[check] OK: 8/8 support files byte-identical to canonical (6 core + 2 conditional preludes)
```
Also re-passed with `/tmp/t53_seedcheck/zig1_5_clean`.

### 3.10 No-CRT emit/link/Wine probes (mingw only)
```text
hello:  PE32; imports KERNEL32.dll;                 wine → "Hello, world!" rc=0
z9play: PE32; imports KERNEL32.dll WINMM.DLL;       IMPORT GATE PASS (9x);
        wine z9play.exe --help → usage, rc=0
z9torr: PE32; imports KERNEL32.dll WSOCK32.DLL;     IMPORT GATE PASS (9x);
        wine z9torr.exe --help → usage, rc=0
```
`-osw nt` hello: PE32, `KERNEL32.dll msvcrt.dll`, wine rc=0.
No msvcrt / `GetFileAttributesExA` / `GetFileSizeEx` / `SetFilePointerEx` in
any 9x image. Native MSVC/OWC scripts were not run (Amendment 5).

### 3.11 Script-content checks
- 9x `build_target.sh` carries `-DZIG_NO_CRT` and
  `-nostdlib -Wl,-e,_mainCRTStartup`; `nt` carries `-DZIG_WIN_NT` and the
  normal CRT link (`LDFLAGS="-m32"`, no `-nostdlib`).
- Four `.bat` scripts: no executed line >127 chars (REM lines excluded);
  response files used; `_nocrt` has `/entry:_mainCRTStartup@0` (MSVC) /
  `option start=_mainCRTStartup` (OWC), `/NODEFAULTLIB` / `option
  nodefaultlibs`, `libcmt.lib` / `clib3r`; `_crt` has none of those and keeps
  `/MT` / default static CLIB. `ZIG_WIN_NT` present in all four in an nt dump;
  absent in a 9x dump. Old names are aliases to the profile default.
- `--dump-c89` output still compiles with the normal GCC path: `-osl`/default
  Linux builds of all 26 examples succeeded (GPU/stdio examples included).

---

## 4. Seed rotation

```text
$ md5sum /tmp/t53/hop2/zig1_hop2
1ef248e0c9782cfe646de73634dae4d8
$ bash scripts/seed/archive_seed.sh /tmp/t53/hop2/zig1_hop2 /tmp/t53/hop2 \
    release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): 1ef248e0c9782cfe646de73634dae4d8
[archive] wrote release/seed/zig1-seed.tgz (archive md5 c51e8019d0a1a7088c714aa1ff39fa09)
```
CHANGELOG entry: seed **v99**, date 2026-10-18, HEAD `f244c7c5`, seed binary /
fixed point `1ef248e0c9782cfe646de73634dae4d8`, archive
`c51e8019d0a1a7088c714aa1ff39fa09`, `gen/` 46 `.c` + 47 `.h` (10,253,743
bytes). Post-rotation `build_from_seed.sh` verified `hop1 == hop2 ==
1ef248e0…`. `docs/sf/QUICK_REF.md` seed block + 8-pin table updated to the new
values.

---

## 5. Concerns

1. **Native toolchains remain hardware-pending.** MSVC 6 `/Za /Zl`, the
   `_mainCRTStartup@0` decoration, `libcmt.lib` helper selection, OpenWatcom
   `/sg`, `clib3r`, `option start`, and the native import tables are
   design-verified from vendor docs + emitted-C analysis only. No `cl`/`wcc386`
   was downloaded or run (Amendment 5). Real Win98/Me load/run, console, audio,
   and network behavior remain operator-owned.
2. **All 8 pins moved**, as expected for T5.3: 64-bit spelling layer plus the
   Win9x PAL rewiring. Runtime goldens are byte-identical; the new pin table is
   recorded in QUICK_REF under the fixed-point compiler `1ef248e0…`.
3. **argv parser implementation detail.** Two static 32 KiB buffers are used
   instead of in-place compaction; this preserves the design's contract but is
   an implementation detail not spelled out in T5.3a/b.
4. **Seed format now carries `zig_nocrt.c`** (`runtime/`, excluded from
   `gen/`). Both seed scripts were updated; the v99 archive rebuild reproduces
   the fixed point with the new file included.
5. **`_iob` omission remains mingw-scoped.** MSVC/OWC define their native
   stream arrays; if a future mingw header references `_iob` directly, the
   omission must be re-probed (documented in doc 13).
6. **Static-CRT alternates** are single-EXE/no-DLL by construction but are not
   claimed 9x-safe until `check_win9x_imports.sh ... 9x` passes on actual
   native artifacts.
7. **Environment slice lifetime** is narrowed to “until the next `env()` call”
   on Windows (static PAL buffer, single-threaded), per Amendment 3; documented.
