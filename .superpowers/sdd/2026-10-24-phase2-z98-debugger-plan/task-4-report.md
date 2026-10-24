# P3-M4 Task 4 report — Win98 backend + COFF + DWARF-in-PE + docs + v120 closeout

**Status:** DONE_WITH_CONCERNS
**Branch:** `zig1_improvements`
**BASE:** `1ef863eb` (Amendment A1; recorded before the first commit)
**Code commit:** `7cd7e26f` `feat(z9dbg): Win98 backend + COFF/DWARF-in-PE (Phase2 P3-M4)`
**Docs commit:** `5981b560` `docs(manuals|std_lib): debug map + z9dbg truth-up`
**Seed commit:** `eba1afee` `chore(seed): rotate v120 (Phase2 P3)`
**Report commit:** this file

**Final compiler used for gates:** `/tmp/m4_seed_v120/zig1_5_clean` (rebuilt
from the rotated `release/seed/zig1-seed.tgz`; two-hop closure
`hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6`).

---

## 1. Step 1 — RED evidence

Baseline before any M4 edit (`/tmp/z98_m3/zig1_5_clean`, current std payload):

```text
tier_dbg.sh       35 passed, 0 failed   TIER_DBG PASS
tier_dbg_core.sh  23 passed, 0 failed   TIER_DBG_CORE PASS
```

Wine Debug-API feasibility (temporary C probe in `/tmp/m4wine`, not committed):
`CreateProcessA(DEBUG_ONLY_THIS_PROCESS)` + `WaitForDebugEvent` delivered
`CREATE_PROCESS`, `LOAD_DLL`, the loader `EXCEPTION_BREAKPOINT`, and the
debuggee's own planted `int3` under `wine-8.0`; subsequent probes confirmed
TF single-step exceptions and context read/write. Wine can drive the debugger.

Pre-implementation Win98 build failed exactly as decision 3 predicts:

```text
$ /tmp/z98_m3/zig1_5_clean -osw -o /tmp/m4_red_win examples/z98/z9dbg/main.zig
$ sh /tmp/m4_red_win/build_target.sh mingw /tmp/m4_red_win/z9dbg.exe
/usr/bin/i686-w64-mingw32-ld: main_...o:(.text+0xeb4): undefined reference to `fflush'
collect2: error: ld returned 1 exit status
```

Pre-implementation new tests failed to build (readers absent):

```text
error[3048]: could not resolve imported file '../coff_lines.zig'
error[3048]: could not resolve imported file '../pe_debug.zig'
```

Before the whitelist edit, the freshly built z9dbg.exe failed the 9x gate with
exactly the eight names the amendment adds:

```text
FAIL ContinueDebugEvent not in 9x KERNEL32 whitelist
FAIL CreateProcessA not in 9x KERNEL32 whitelist
FAIL FlushInstructionCache not in 9x KERNEL32 whitelist
FAIL GetThreadContext not in 9x KERNEL32 whitelist
FAIL ReadProcessMemory not in 9x KERNEL32 whitelist
FAIL SetThreadContext not in 9x KERNEL32 whitelist
FAIL WaitForDebugEvent not in 9x KERNEL32 whitelist
FAIL WriteProcessMemory not in 9x KERNEL32 whitelist
IMPORT GATE FAILED (9x)
```

## 2. Step 2 — implementation

### 2.1 Backend / vtable

- `backend.zig`: added `imageBase_fn: fn (*void) u32`; stub returns 0.
- `backend_linux.zig`: same vtable field, returns 0 (ELF path unchanged).
- `backend_select.zig`: Windows arm now returns `backend_win98.win98Backend()`.
- `backend_win98.zig` (new):
  - `CreateProcessA(DEBUG_ONLY_THIS_PROCESS)` with raw 68-byte STARTUPINFOA /
    16-byte PROCESS_INFORMATION buffers; launch consumes `CREATE_PROCESS`
    **without continuing it** so `imageBase_fn` is valid before entry
    breakpoints are planted.
  - 50 ms `WaitForDebugEvent` pump; `LOAD_DLL`/`CREATE_THREAD`/`EXIT_THREAD`/
    `OUTPUT_DEBUG_STRING`/`RIP`/`UNLOAD_DLL` continued internally.
  - loader's initial breakpoint skipped when no planted reach exists at EIP-1.
  - planted int3: restore original byte, rewind EIP, leave the event pending;
    `continue` re-arms all except the current PC and issues
    `ContinueDebugEvent(DBG_CONTINUE 0x00010002)`.
  - raw 716-byte CONTEXT_i386; documented offsets
    (EIP 184, EFlags 192, EAX 176 …).
  - single-step sets EFlags bit 0x100; the single-step exception clears it.
  - Read/WriteProcessMemory + FlushInstructionCache after every code write.
  - `detach`/`terminate` = restore bytes + `TerminateProcess` (Win9x
    terminate-on-quit); `imageBase_fn` returns `lpBaseOfImage`.

### 2.2 std_os / std_os_pal

- `std_os_pal.zig`: ten `extern "stdcall"` debug bindings (CreateProcessA,
  WaitForDebugEvent, ContinueDebugEvent, Get/SetThreadContext,
  Read/WriteProcessMemory, FlushInstructionCache, TerminateProcess,
  CloseHandle).
- `std_os.zig`: thin `@isWindows()`-guarded wrappers; Linux returns failure
  without referencing the stdcall symbols. No prelude/compiler change.

### 2.3 Debug-info readers

- `dwarf_lines.zig`:
  - `DebugInfo` gained `image_base` (0 for ELF) so PE bias is explicit.
  - `openSections(arena, data, line_data, image_base)` interprets a raw
    `.debug_line` section; `injectFuncs` adds container functions and fills
    missing PE/COFF function sizes from the next symbol (needed for `ret-1`
    frame lookup); `buildInfo` takes COFF rows/files/functions.
  - `normalizePath` (`\`→`/`, drive/`./` strip, trailing CR, Windows case
    fold) applied to DWARF file names and file matching.
  - ELF `open` still parses section headers/`.symtab` exactly as before.
- `coff_lines.zig` (new): IMAGE_COFF_SYMBOLS_HEADER at the debug blob;
  `LvaToFirstSymbol`/`LvaToFirstLinenumber` treated as blob-relative; 18-byte
  SYMENT + string table; FILE (103) aux format 4 names the current file;
  STATIC section-def aux `nlnno` slices the line table; `Linenumber == 0`
  headers skipped; line Type is the code RVA; function VA =
  `ImageBase + section.VirtualAddress + Value`; one leading `_` stripped.
  `openBytes` is the pure synthetic/real-image entry.
- `pe_debug.zig` (new): DOS/PE headers, PE32-only, section table (including
  `/nnn` long names via the COFF string table), debug-directory Type 1
  fallback to `coff_lines`, `.debug_line` → `dwarf.openSections`, COFF symtab
  → functions, VA = `ImageBase + section.VirtualAddress + Value`, one leading
  `_` stripped. No PDB/CodeView.
- `map_reader.zig`: file comparison now uses `dwarf.normalizePath` (needed for
  Windows case/separator matching of generated-C names).

### 2.4 main.zig

- ELF/PE magic dispatch (`openDebug`) keeps the no-debug fallback: a PE
  without a line table still gets COFF/symtab functions and `has_line = false`.
- PE runtime bias = `imageBase_fn() - image_base`; PE failure warns and leaves
  bias unknown. ELF keeps `setLoadBase`/`/proc/<pid>/maps`.
- `flushOut()` is compile-time guarded: `if (!@isWindows()) { fflush(...) }`.
- Error text now covers both formats: `cannot read the debuggee ELF or PE image`.

### 2.5 Import gate

`scripts/win32_cross/check_win9x_imports.sh` 9x KERNEL32 whitelist adds exactly
the eight approved names; no msvcrt, no DebugActiveProcessStop.

## 3. Step 3 — gates (final compiler)

```text
tier_dbg_core.sh   26 passed, 0 failed   TIER_DBG_CORE PASS
tier_dbg.sh run 1  38 passed, 0 failed   TIER_DBG PASS
tier_dbg.sh run 2  38 passed, 0 failed   TIER_DBG PASS
```

`tier_dbg.sh` retains all 35 M3 Linux cases and adds three Win98/Wine cases:
`Win98 import gate (9x)`, `Win98 break+backtrace session`,
`Win98 step+backtrace session` (each session runs twice; outputs are compared
against the existing `live_break.txt` / `live_step.txt` goldens). The structural
COFF test and the real mingw `-g -gdwarf-2` PE fixture live in
`tier_dbg_core.sh` and run on Linux (no Wine).

Std gates on `/tmp/m4_seed_v120/zig1_5_clean`:

```text
verify_stdlib: 336 PASS / 0 FAIL;  crosscheck 10 PASS / 0 FAIL; STDLIB GATE OK
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
```

Seed closeout:

```text
# before rotation (v119 seed -> current sf/src)
hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6

# archive_seed.sh
seed binary md5 / fixed point  11de43a053bdde3be3ddc61caac31df6
self-emission C                48 .c + 49 .h (10,844,907 bytes)
lib manifest                   47 std files; md5 7ef5c6b66a2975b51847515fe91fff41
archive md5                    ba69e96d17c5554d19f01224ca3d7274

# after rotation (v120 archive -> current sf/src)
hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6
```

`lib/` standard-library count is unchanged at **47**. No corpus/goldens/pins/
markers/examples battery was run (operator gating amendment; M1 was the
compiler-source task). `git diff --check` is clean before the commits.

Docs completed: `QUICK_REF.md` (`-d` + debuggee/z9dbg recipe and v120 seed
block), new `sf/docs/std_lib/{z9dbg,debug_map}.md`, tech docs 08/09/10/13
(map cost, CLI routing, D8 stdout split, Win32 Debug API/9x imports), and the
three manuals now describe the opt-in sidecar instead of denying it.
`lin_bin/instructions.txt` (untracked/gitignored) gained the MSVC 6
`/DEBUGTYPE:COFF` and OpenWatcom `-d2` recipes plus the transcript request.

## 4. Commits

| Commit | Message |
|---|---|
| `7cd7e26f` | `feat(z9dbg): Win98 backend + COFF/DWARF-in-PE (Phase2 P3-M4)` |
| `5981b560` | `docs(manuals|std_lib): debug map + z9dbg truth-up` |
| `eba1afee` | `chore(seed): rotate v120 (Phase2 P3)` |
| (this report) | `docs(sdd): P3-M4 closeout report` |

## 5. Concerns / deferred items

1. **Real toolchains remain operator-run.** The COFF reader is validated by a
   structural §15.1 fixture (spec §15.4 explicitly allows this) and the
   DWARF-in-PE reader by real mingw output. No real MSVC 6 or OpenWatcom
   artifact was available here; recipes + transcript request are in
   `lin_bin/instructions.txt`. Real Win98 hardware is also operator-owned.
2. **Wine is not Win98.** The import gate is the loadability gate; the Wine
   session proves the API sequencing, not 9x kernel behavior.
3. **Win98 `quit` terminates the debuggee** (documented). There is no detach/
   reattach path and no `DebugActiveProcessStop` import.
4. **PE/COFF function sizes are derived** from the next symbol when the symbol
   table carries no aux size. This is sufficient for frame return addresses
   (`ret-1`); the last function keeps exact-match only.
5. **DWARF 5/64 and PDB/CodeView remain out of v1**; they degrade to
   `break: no debug info` + function-entry breakpoints, as documented.
6. **Full compiler battery (corpus/goldens/pins/markers/examples) was not
   re-run** per the operator gating amendment. The v120 fixed-point rotation
   and std gates are green.
7. **Process:** no sed/perl/python source edits and no subagents. The only
   `sed` uses are the pre-existing test-time expected-output rendering in the
   tier scripts; no untracked P4 docs, `run.err`, or `.opencode/memory` files
   were touched.

---

## Fix round 1 — v120 provenance HEAD correction

**Finding (Important).** The first v120 rotation was produced from the working
tree while `HEAD` was still `1ef863eb`, then committed as `eba1afee`. Both
`release/seed/CHANGELOG.md` and the archive's `zig1-seed/SEED_README.txt`
therefore said `HEAD 1ef863eb`, but the archived `lib/std_os.zig` was already
the M4 version (md5 `c62dda9e00c126d58f55496d792823c7`), which does not exist at
`1ef863eb`. `scripts/seed/archive_seed.sh` defines the pinned HEAD as the
committed source state the archive was built from, so the stamp must name a
commit that contains the M4 source.

**Reproduction (non-destructive clone; workspace untouched):**

```sh
git clone /workspace/znineeight /tmp/m4_prov
git -C /tmp/m4_prov checkout 5981b560
cd /tmp/m4_prov
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m4_prov_build
# hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6
bash scripts/seed/archive_seed.sh /tmp/m4_prov_build/zig1_5_clean \
     /tmp/m4_prov_build/gen release/seed/zig1-seed.tgz --update-changelog
```

The clone's archive was then copied into the workspace and only the v120
CHANGELOG entry was replaced (v119 and older untouched; the resulting
CHANGELOG is byte-identical to the clone's).

**Corrected provenance evidence:**

```text
SEED_README.txt: Pinned HEAD: 5981b560
lib/std_os.zig md5: c62dda9e00c126d58f55496d792823c7
lib std files: 47
lib manifest md5: 7ef5c6b66a2975b51847515fe91fff41
seed binary md5: 11de43a053bdde3be3ddc61caac31df6
fixed point: 11de43a053bdde3be3ddc61caac31df6
archive md5: 18c21ebfc18f3014f0ccab2f10f38688
```

The reproduced fixed point is unchanged (`11de43a...`, re-measured from the
v119 seed at `5981b560`); the archive md5 changes because `SEED_README.txt`
carries the corrected HEAD stamp.

**Scope disclosure — `map_reader.zig`.** The feat commit `7cd7e26f` also edits
`examples/z98/z9dbg/map_reader.zig`, which is not explicitly enumerated in the
Task-4 file list. The edit is limited to `fileScore`: it routes map `src_file`
and query comparisons through `dwarf.normalizePath` so spec §15.3's
`\`→`/`, drive/`./` stripping, and Windows case folding apply to map matching
too. Controller ruling: accepted, no revert.

**Verification for this fix round:** `git diff --check` is clean; the already
built `z9dbg.exe` still passes
`scripts/win32_cross/check_win9x_imports.sh <exe> 9x`; the full tiers were not
re-run because only the seed stamp/archive changed, not code.

---

## Fix round 2 — COFF reader correctness (review Critical 1-2, Important 3-4)

**Commit:** `9519eece` `fix(z9dbg): COFF line RVA, string table, function
classification (Phase2 P3-M4)`

### Critical 1 — line-record RVA double-counted section VA

**Finding.** `coff_lines.parseBlob` computed line rows as
`image_base + section.VirtualAddress + line.VirtualAddress`. §15.1 defines a
line record's `VirtualAddress`/`Type` as the **code RVA** when
`Linenumber != 0`, so the section VA must not be added again. Real MSVC rows
would be 0x1000+ too high (breakpoints at wrong addresses). The synthetic
fixture hid it because its line records were section-relative and the section
VA was 0x1000.

**Fix.** Row VA is now `image_base +% va` (`coff_lines.zig`). The fixture's
line records now store code RVAs `0x1010/0x1014/0x1018` while the expected
final VAs remain `0x401010/0x401014/0x401018`, so re-adding the section VA
would fail the test.

### Critical 2 — COFF debug-blob string table never parsed

**Finding.** `parseBlob` left `pe.strtab/str_size = 0`, so long symbol names
(first dword zero, second dword a string-table offset) resolved to `""` and
were dropped. Z98 C names (`zF_<hash>_<name>`) are long, so the MSVC path had
no function names.

**Fix.** After the symbol records (`sym_end = sym_start + nsym*18`), the reader
reads the u32 string-table size when four bytes are available, validates
`str_size >= 4` and `sym_end + str_size <= end`, and sets
`pe.strtab = sym_end`, `pe.str_size = str_size`; an absent/truncated table
stays 0/0. Line-table placement is not required to be before or after the
string table; both are independently bounded. The fixture now adds a separate
string table at the end of the symbol records and an EXTERNAL long-named symbol
(`_zF_LONGNAME_hello`, offset 4); the test asserts the name resolves and
`funcAddr("zF_LONGNAME_hello") == 0x401080`.

### Important 3 — function classification too broad

**Finding.** Both readers treated any STATIC+section+naux symbol as a section
definition (misreading static functions with aux), treated any STATIC+naux==0
symbol as a function (turning static data Type 0 into functions), and could
misread `.bf/.ef/.lf`.

**Fix (both `coff_lines.zig` and `pe_debug.zig`):**

- section definition: `cls == STATIC && typ == 0 && snum > 0 && naux >= 1`;
- function: `(cls == EXTERNAL || cls == STATIC) && (typ & 0x20) != 0 && snum > 0`;
- `TotalSize` only from a format-1 aux on an EXTERNAL function
  (`cls == EXTERNAL && typ & 0x20 && naux >= 1`); otherwise the next-symbol
  size derivation remains;
- storage class FUNCTION (101) is excluded (it matches neither constant).

The structural COFF fixture now adds a STATIC function with an aux (`_sfunc`)
and STATIC Type-0 data with no aux (`_sdata`): exact function count is 3
(`hello`, `sfunc`, `zF_LONGNAME_hello`) and `funcAddr("sdata") == null`.
The real mingw PE fixture asserts the equivalent shape from its symbol table:
`g_atexit_fns` (STATIC Type 0, no aux) is excluded and `zig_ovf_sext` (STATIC
function with aux) is included.

### Important 4 — stale v120 archive md5 in QUICK_REF

`docs/sf/QUICK_REF.md` now records the corrected archive md5
`18c21ebfc18f3014f0ccab2f10f38688` (matches
`release/seed/CHANGELOG.md` and the committed archive).

### Test evidence

```text
tier_dbg_core.sh   26 passed, 0 failed   TIER_DBG_CORE PASS  (new COFF assertions green)
tier_dbg.sh run 1  38 passed, 0 failed   TIER_DBG PASS
tier_dbg.sh run 2  38 passed, 0 failed   TIER_DBG PASS
check_win9x_imports.sh <z9dbg.exe> 9x   IMPORT GATE PASS (9x)
git diff --check                        clean
```

The regenerated Win98 `z9dbg.exe` also passes the 9x import gate. The deferred
review minors (5-10) were intentionally left untouched.

### Residual concerns

- The COFF fixture remains structural (spec §15.4 permits this); real MSVC 6
  output is still operator-run via `lin_bin/instructions.txt`.
- The real-PE static-data/static-function assertions name symbols from the
  current emitted runtime (`g_atexit_fns`, `zig_ovf_sext`); a future rename in
  the runtime would require updating those two test names.
