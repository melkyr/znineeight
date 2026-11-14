# P3-M3 Task 3 report — Linux ptrace backend + DWARF lines

**Status:** DONE_WITH_CONCERNS
**Branch:** `zig1_improvements`
**Code commit:** `566f65ce` `feat(z9dbg): ptrace backend + DWARF lines (Phase2 P3-M3)`
**Docs commit:** this report
**Compiler used:** `/tmp/z98_m3/zig1_5_clean`, rebuilt from the committed
v119 seed with the final `sf/src` std payload:
`hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6` (unchanged; only
`std_os*.zig` changed, no compiler source).

---

## 1. What was implemented

### 1.1 `sf/src/std_os_pal.zig` — POSIX externs (std change)

Added the Linux process/debug bindings the backend needs, declared as
`extern "c"` in the PAL and called only through `@isWindows()`-guarded wrappers
in `std_os.zig` (Win32 Debug API remains M4):

`fork`, `execv`, `waitpid`, `ptrace` (four fixed i386 args), `getpid`,
`kill`, `open`, `dup2`, `close`, `__errno_location`.

No prelude/compiler change was needed: `<unistd.h>` already declares
fork/execv/getpid/close in the emitted `std_os_prelude.h`; waitpid/ptrace/
open/dup2 resolve through C89 implicit declarations under the binding
`-Wno-implicit-function-declaration`. `scripts/check_emit_support.sh` still
reports 8/8 byte-identical support files.

### 1.2 `sf/src/std_os.zig` — thin process surface (std change)

Thin wrappers (`fork`, `execv`, `waitpid`, `ptrace`, `getpid`, `kill`,
`errno`, `clearErrno`, `debuggeeStdinNull`, `ptraceNull`) plus the documented
`@isWindows()` pruning pattern used by `env`/`cwd`. `debuggeeStdinNull`
points the child's fd 0 at `/dev/null` so the debuggee cannot consume z9dbg's
command stream (stdout/stderr stay inherited).

### 1.3 `examples/z98/z9dbg/backend_linux.zig` — ptrace backend

- `PTRACE_TRACEME` fork/execv launch (argv built in a stack buffer,
  NUL-terminated; `/dev/null` stdin; exec failure exits 127), initial exec
  SIGTRAP consumed by `launch`.
- `waitpid` status decoding (`WIFEXITED/WEXITSTATUS/WIFSTOPPED/WSTOPSIG`).
- `PEEK/POKETEXT`, `POKE/POKEDATA` word helpers with errno-based
  `-1`/valid-word disambiguation; byte-level read/write memory over words
  (works at unaligned instruction addresses).
- i386 `user_regs_struct` (17×u32) GETREGS/SETREGS and the vtable's
  `Registers` translation.
- int3 plant/restore table (256 entries): hit restores the original byte,
  rewinds EIP, and disables the address; `restoreAll` returns every byte on
  `quit`; `installAllExcept` re-plants for resume/step; `removeBreak` drops
  the entry (single-step/loop instructions).
- `continue` skips re-inserting a breakpoint exactly at the current PC and
  CONTs (the upper layer performs the line step-over). `singleStep` sets the
  step flag so the wait path classifies the SIGTRAP as a single-step stop.
- `detach` restores bytes and `PTRACE_DETACH`es (debuggee lives);
  `terminate` is available for failure cleanup.
- All symbols are resolved in-process; nothing shells out to gdb.

### 1.4 `examples/z98/z9dbg/dwarf_lines.zig` — in-Z98 DWARF/ELF reader

- ELF32 little-endian section reader (section headers, `.debug_line`,
  `.symtab` + linked `.strtab`); wrong class/magic/version fails cleanly.
- DWARF 2/3/4 line-number program interpreter:
  - unit/header parse (v4 `maximum_operations_per_instruction` included),
    include-directory and file-name tables, opcode-length table;
  - standard/extended/special opcodes, ULEB/SLEB (overflow-guarded),
    `set_address`, `advance_pc/line`, `set_file`, `const_add_pc`,
    `fixed_advance_pc`, `end_sequence`, `define_file`;
  - rows sorted by address and binary-searched for reverse lookups.
  - DWARF 5 units are skipped by design (v1 out of scope); DWARF64
    (`0xffffffff` unit length) stops line parsing and degrades to function
    entries.
- `.symtab` STT_FUNC entries (`st_value/st_size/name`, defined symbols only)
  give function-entry addresses and frame-range lookup for backtrace.
- PIE/ET_DYN load bias read from `/proc/<pid>/maps` (path basename match,
  `start - offset`); ET_EXEC bias is 0.
- Public API: `open`, `setLoadBase`, `addrForLine`, `rowForAddr`,
  `rowFileName`, `funcAddr`, `funcByAddr`, `basename`.

### 1.5 `map_reader.zig` / `dbg_core.zig`

- `lineSpansAt` exposes the full emitted-line run (`out_start`, `out_count`)
  so a breakpoint is planted at every machine address mapped to a source line
  (spec §14); `lineRowsAt` keeps its M2 one-row-per-run behavior.
- `reverseNearestAt` maps a C line to the nearest preceding `.lines` run
  (needed for call/prologue lines that have no exact run).
- `srcNameForCname` is the reverse `.cnames` lookup used by frame unwinding.
- `dbg_core.nextFunctionLine` is now public; `breakTableForceAdd` records a
  line reached by the DWARF-level snap.
- M2 review minor (a) fixed: `stepInto` canonicalizes the resolved
  `src_file` through `map_reader.resolveFile` before comparing, so absolute/
  relative spellings of the same map line do not look like a new line.
- Corrupt `.lines` run payloads are not relied upon.

### 1.6 `main.zig` — live session

- `z9dbg <exe> [args…]` now launches, loads the debuggee's ELF/DWARF, sets
  the PIE bias, installs the entry breakpoint, and stops before the first
  command. `Z9DBG_STUB=1` retains the M2 scripted stub session for the
  map-core gate (`tier_dbg_core.sh`).
- Entry address: the first mapped line's machine address when it has one;
  otherwise the entry function's `.symtab` address (avoids snapping forward
  past an early program exit on the hello/mud/lisp shapes).
- `break`: map-level snap from M2, then DWARF-level snap to the nearest
  mapped line with an address (stops at the next function boundary); plants
  int3 at every address of every emitted-line span; exact M2 strings preserved
  (`break: moved to line N`, `break: no executable code at line N`, etc.).
- No `.debug_line`: resolves the containing map function through `.symtab`
  and prints exactly `break: no debug info`, then sets a function-entry
  breakpoint (source display uses the function declaration line).
- `continue`/`dump variables`: on a breakpoint hit, restores all bytes,
  single-steps across every remaining address of the *same* source line
  (multi-address lines would otherwise self-trap), reinserts everything except
  the current PC, CONTs, and displays the resolved stop. `dump` writes the
  snapshot then auto-resumes (spec §14) to exit/next stop.
- `step`: restores breakpoints, uses the M2 `stepInto` loop with a live
  DWARF resolver, then re-plants all except the new PC.
- `backtrace`: frame-pointer unwind (`[ebp]` prev, `[ebp+4]` ret), maps the
  callers through `.symtab` + reverse `.cnames`; stops at libc frames.
  Current frame prints the stop line; caller frames print the function's map
  declaration line.
- `quit`: restores every planted byte, then `PTRACE_DETACH` (debuggee lives).
- `Z9DBG_TIMING=1` writes `z9dbg: entry latency N ms` and
  `z9dbg: breakpoint latency N ms` to stderr for measurement.

### 1.7 `tests/tier_dbg.sh` (new) + fixtures

Scripted, 2×-compared sessions on a no-stdout fixture
`tests/fixtures/live/main.zig`, plus the required test set:

- break at a known line + exact stop display + backtrace names;
- empty-line reject and declaration-line `break: moved to line N`;
- `step` advances to the next mapped line;
- `dump variables` snapshot content + auto-resume to completion;
- `quit` restores *all* bytes (the un-hit line's int3 would kill the detached
  debuggee) and the debuggee writes its completion marker;
- `-g`-less build: exact `break: no debug info` + function-entry stop;
- source-line breakpoint latency;
- `hello`, `mud_server`, `lisp_interpreter_curr`, `z9torr` entry stops,
  latency, and RSS under `ulimit -v 32768`.

The live fixture uses one `addTwo` call path and a second call after the
breakpoint; the dump case breaks in `middle` so auto-resume reaches completion
(the second `addTwo` call would otherwise legitimately re-hit a line-12
breakpoint).

---

## 2. RED evidence (tests written first)

Command (before the backend/DWARF implementation existed; M2 stub binary):

```bash
ZIG=/tmp/z98_m2/zig1_5_clean OUT=/tmp/z9dbg_tier_red \
  bash examples/z98/z9dbg/tests/tier_dbg.sh
```

Result: rc=1, **8 passed / 26 failed**. Representative failures:

```
FAIL - live_break run 1 output
FAIL - live_break run 1 debuggee did not complete (int3 not restored?)
FAIL - live_step run 1 output
FAIL - live_dump run 1 snapshot content
FAIL - live_restore run 1 output
FAIL - live_nodbg run 1 output
FAIL - hello latency (got 'none')
FAIL - mud latency (got 'none')
FAIL - lisp latency (got 'none')
FAIL - z9torr latency (got 'none')
...
== tier_dbg summary: 8 passed, 26 failed ==
TIER_DBG FAIL
```

The 8 passes were the M2-only entry-stop/RSS checks (the map display and the
stub process existed); every live-behaviour assertion was red.

---

## 3. GREEN evidence

### 3.1 Final tier, 2× (rebuilt compiler)

```bash
ZIG=/tmp/z98_m3/zig1_5_clean OUT=/tmp/z9dbg_tier_run3 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # rc=0
ZIG=/tmp/z98_m3/zig1_5_clean OUT=/tmp/z9dbg_tier_run4 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # rc=0
```

Both runs:

```
== tier_dbg summary: 22 passed, 0 failed ==
TIER_DBG PASS
```

Every compared session is also run 2× inside the tier (stdout and dump bytes
compared). Across the two whole-gate runs, the logs are identical after
normalizing the inherently variable RSS/latency numbers:

```bash
sed -E 's/RSS [0-9]+KB/RSS <N>KB/; s/latency [0-9]+ms/latency <N>ms/' ...
md5sum /tmp/tier_dbg_run3.norm /tmp/tier_dbg_run4.norm
8d17ad8c92541bd6878707a96b210259  /tmp/tier_dbg_run3.norm
8d17ad8c92541bd6878707a96b210259  /tmp/tier_dbg_run4.norm
```

### 3.2 M2 map-core gate still green

```bash
ZIG=/tmp/z98_m3/zig1_5_clean OUT=/tmp/z9dbg_core_final \
  bash examples/z98/z9dbg/tests/tier_dbg_core.sh
== tier_dbg_core summary: 23 passed, 0 failed ==
TIER_DBG_CORE PASS
```

The standalone-binary section runs with `Z9DBG_STUB=1` (the binary now
launches a real process by default; the M2 expectations are for the scripted
stub session).

### 3.3 Extra DWARF-version check

The binding build pins `-gdwarf-2` (this gcc emits DWARF **3** headers even
with that flag). The live break/backtrace session was also manually run
against a `-gdwarf-4` build:

```
DWARF Version:               4
Stopped at .../live/main.zig:22
(z9dbg) break: set at line 12
(z9dbg) Stopped at .../live/main.zig:12
(z9dbg) #0 addTwo at .../live/main.zig:12
#1 middle at .../live/main.zig:16
#2 main at .../live/main.zig:21
```

DWARF 5 remains deliberately unsupported (spec §7.6).

---

## 4. Latency / RSS

Measured by `tier_dbg.sh` under `ulimit -v 32768`; latency is the debugger's
own stop-to-display measurement (ms resolution, so sub-ms reads as 0).

| Program | Latency run3 | RSS run3 | Latency run4 | RSS run4 |
|---|---|---|---|---|
| source-line break (`live` line 12) | 0 ms | — | 0 ms | — |
| hello | 0 ms | 1,884 KB | 1 ms | 1,488 KB |
| mud_server | 1 ms | 1,868 KB | 0 ms | 2,284 KB |
| lisp_interpreter_curr | 1 ms | 2,540 KB | 0 ms | 2,060 KB |
| z9torr (stress) | 0 ms | 8,180 KB | 0 ms | 8,064 KB |

All latencies < 100 ms; all z9dbg RSS values < 32 MB (max observed 8.2 MB,
z9torr with the largest debug ELF/map). `Z9DBG_TIMING=1` is opt-in; no timing
output appears in normal sessions.

---

## 5. std gate (std_os touched)

```bash
bash scripts/stdlib/verify_stdlib.sh /tmp/z98_m3/zig1_5_clean
run_fixtures: 336 PASS / 0 FAIL over 336 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK

bash scripts/stdlib/run_crosscheck.sh /tmp/z98_m3/zig1_5_clean
run_crosscheck: 10 PASS / 0 FAIL over 10 modules

bash scripts/check_emit_support.sh /tmp/z98_m3/zig1_5_clean
OK: 8/8 support files byte-identical to canonical
```

Seed rebuild closure: `hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6`.
No compiler module was modified; no corpus/goldens/pins battery was required
per the approved hybrid gating.

---

## 6. Files

Code commit `566f65ce`:

- `sf/src/std_os.zig`, `sf/src/std_os_pal.zig` (std process/debug surface)
- `examples/z98/z9dbg/backend_linux.zig` (new)
- `examples/z98/z9dbg/dwarf_lines.zig` (new)
- `examples/z98/z9dbg/backend.zig` (`live` flag; stub unchanged)
- `examples/z98/z9dbg/dbg_core.zig` (path canonicalization, public helper,
  DWARF-snap table entry)
- `examples/z98/z9dbg/map_reader.zig` (`lineSpansAt`,
  `reverseNearestAt`, `srcNameForCname`)
- `examples/z98/z9dbg/main.zig` (launch, entry, break/continue/step/
  backtrace/dump/quit, timing, `Z9DBG_STUB`)
- `examples/z98/z9dbg/tests/tier_dbg.sh` (new, mode 100755)
- `examples/z98/z9dbg/tests/tier_dbg_core.sh` (`Z9DBG_STUB=1` for the
  two standalone-binary sessions)
- `examples/z98/z9dbg/tests/session_live_{break,step,dump,restore,nodbg}.in`
- `examples/z98/z9dbg/tests/expected/live_{break,step,dump,restore,nodbg}.txt`
- `examples/z98/z9dbg/tests/fixtures/live/main.zig`

Docs commit: this report.

---

## 7. Self-review

- No compiler source changed; `LirInst`/`lir_stream`/map writer untouched.
- Readers are in-process Z98 inside z9dbg; no gdb, no helper binary, no
  process spawn at debug time except the debuggee itself.
- Break addresses: map source line -> every emitted-line span -> DWARF row
  addresses; no machine address is invented.
- `quit` restore is proven behaviourally: the restore session leaves an
  un-hit line-13 int3 planted if restoration is wrong, and the detached
  debuggee then dies instead of writing its completion marker.
- No-debug build: `.debug_line` absent -> `.symtab` function entry + exact
  `break: no debug info`.
- M2 exact UX strings are unchanged for the stub/mock harness; the M2 gate
  passes 23/23.
- `git diff --check` clean; `run.err` untouched.
- PROCESS DEVIATION (disclosed): two `handleDump(...)` call sites in
  `main.zig` were updated with one `sed` substitution (a two-expression,
  single-file edit) instead of `edit`/`fastedit`. No perl/python/awk was
  used and no bulk transform was performed, but this is still outside the
  edit-only instruction. Everything else was edited with `edit`/`write`.

---

## 8. Concerns / deferred

1. **FPO builds:** backtrace is frame-pointer only (`-fno-omit-frame-pointer`);
   optimized/omit-frame-pointer builds produce unreliable frames (spec §14).
2. **DWARF 5 / DWARF64:** unsupported by design. This gcc reports DWARF 3
   even with `-gdwarf-2`; DWARF 4 was additionally verified manually.
3. **Entry-stop fallback:** if the first mapped line has no machine address,
   the entry stop uses the entry function's `.symtab` address rather than
   snapping forward. Snapping forward can pass an early program exit
   (`mud_server`/`lisp` shapes) and never trap; the fallback is the honest
   "first executable point" choice.
4. **Multi-address lines:** continuing from a line breakpoint single-steps
   across all remaining addresses of that source line (max 64 instructions)
   before reinserting. This avoids self-trapping but can skip a same-line
   re-entry inside that window.
5. **Backtrace caller lines:** frames ≥ 1 print the function's map declaration
   line (function name is exact); call-site line recovery would need
   instruction decoding, out of v1 scope. Unwinding stops at libc (no map
   symbol).
6. **Latency resolution:** `ticksMs` is millisecond-resolution, so sub-ms hits
   read as 0 ms. The end-to-end tier still bounds the whole session.
7. **Debuggee streams:** stdin is `/dev/null` (debugger owns fd 0); stdout and
   stderr are inherited. A debuggee that needs interactive stdin is not
   supported in this scripted v1.
8. **Map discovery** still takes the last `*.z98dbg.syms` in the executable's
   directory; multiple sidecars in one directory remain ambiguous (M2 note).
9. **PIE bias** is read from `/proc/<pid>/maps` by basename; a renamed/symlinked
   executable path could fail to match and leave bias 0 (ET_EXEC is unaffected).
10. **Implicit C prototypes:** waitpid/ptrace/open/dup2 rely on the binding
    build's `-Wno-implicit-function-declaration` instead of extending the
    canonical `std_os_prelude.h` (which would require touching the compiler's
    `emit_support.zig`; forbidden here). M4 can fold the Linux/Win32 prelude
    prototypes in when the Win32 backend lands.
11. **Memory model:** the debuggee ELF is read whole into the z9dbg arena
    (16 MB cap), not section-lazy; test-set RSS stayed ≤ 8.2 MB, but a
    self-host-sized debug ELF should be re-measured in M4.

---

# Fix round 1

**Status:** DONE_WITH_CONCERNS
**Code commit:** `91b47abd` `fix(z9dbg): vtable isolation, caps, breakpoint
re-arm, span clamp, honesty minors (Phase2 P3-M3)`
**Docs commit:** this appended section.
**Compiler:** `/tmp/z98_m3r2` rebuilt from the v119 seed with the final std
payload; `hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6`. `sf/src/std_os.zig`
changed this round (debuggee-stdio helper), so the std gates were re-run;
`std_os_pal.zig` and all compiler modules are unchanged.

## R1.1 Findings

### F1 — §8.3 test-set sessions

`tier_dbg.sh` now builds and runs a full scripted session on each required
test-set program, with exact byte goldens compared twice:

| Program | Session | Commands exercised |
|---|---|---|
| hello | `session_set_hello.in` | break, continue, backtrace, dump, quit |
| mud_server | `session_set_mud.in` | break (x2), continue, step, backtrace, dump, quit |
| lisp_interpreter_curr | `session_set_lisp.in` | break, continue, step, backtrace, dump, quit |
| z9play (`--info short.ogg`) | `session_set_z9play.in` | break, continue, step, backtrace, dump, quit |

The child's stdout/stderr are redirected to `/dev/null` for these sessions via
the new `Z9DBG_CHILD_OUT` test-support env (see concerns), so the goldens are
only debugger output. Detached test-set debuggees are killed with
`pkill -9 -x prog`; no `pkill -f` pattern can match the harness shell.
Snapshot content is asserted for each session (stop line + function).

### F2 — vtable isolation

`backend.zig` vtable additions: `plant_fn`, `removeBreak_fn`, `restoreAll_fn`,
`installAllExcept_fn`, `pid_fn`; `stubBackend()` implements them
(Unsupported/no-op/-1) and `backend_linux` installs the real functions.
`main.zig` no longer imports `backend_linux`; backend construction goes through
the new `backend_select.zig` (compile-time `@isWindows()` guard; M4 edits that
module only). `grep backend_linux main.zig` is empty.

### F3 — same-line step-over re-arm

`resumeAndShow` tracks `stepped_addr` (the instruction actually executed) and
finishes with `installAllExcept_fn(stepped_addr)`, so the current PC is re-armed
when it was not the stepped instruction; only a self-loop address is left
disabled (and `continue_fn` skips only that current PC). New fixture
`tests/fixtures/loopline/main.zig` puts the whole `while` loop on one source
line and the tier asserts four consecutive hits (`loopline breakpoint re-arm
(4 hits)`), which would run free under the old code.

### F4 — `lineSpansAt` clamp

`lineSpansAt` now takes an `overflow: *bool`, stores at most `out.len` spans,
returns the stored count, and sets overflow. `resolveAddrsForLine` uses a
1024-span buffer (`MAX_SPANS`) and prints
`z9dbg: source line maps to more than the span cap; breakpoint may be
incomplete` on overflow. The core harness adds a 1-entry-buffer clamp assertion
on the two-run hello line 16 (`lineSpansAt clamp count` + overflow).

### F5 — raised caps

- `MAX_ADDRS` (per source line): **4096** (observed worst map: 215 emitted C
  lines for one Z9 source line; each C line contributes a few addresses).
- `MAX_BREAKS` (backend machine table) and `g_bp` (upper layer):
  **65536** (supports 256 source lines x 256 addresses, or 16 huge lines at
  the per-line cap).
- `MAX_SPANS`: **1024** emitted-line runs per source line (observed max 215).

Memory: `g_bp` is 1 MiB BSS, the backend table 512 KiB BSS, and the 16 MiB
arena still dominates; `size` reports BSS 18,350,276 B (~17.5 MiB virtual,
all under the 32 MB `ulimit`), while measured z9dbg RSS is 1.5–8.3 MB.
No warning-only truncation path was added; the caps are the bound.

## R1.2 Folded minors

1. **Caller frames** print the map declaration line with a ` (decl)` suffix;
   current-frame output is unchanged. Goldens updated.
2. **Entry-stop honesty:** `liveEntryStop` verifies the stop reason and EIP.
   Pre-entry exit prints `z9dbg: debuggee exited before entry stop`; a signal
   prints `z9dbg: debuggee stopped by signal N before entry breakpoint`;
   anything else prints `z9dbg: unexpected stop before entry breakpoint`.
   Fixtures `earlyexit` (exit 7 in module init) and `crashinit` (null deref in
   module init, SIGSEGV 11) cover both.
3. **Backend-unavailable text:** real backend failures now print
   `z9dbg: backend operation failed`; the exact M2 stub string is retained only
   for the headless stub path.
4. **`dump variables` call stack:** `dbg_core.writeDumpFrames` writes the
   collected current + caller frames; the M2 `writeDump` wrapper still passes an
   empty slice and is byte-identical. Live dump snapshots now include
   `#1 ... (decl)`.
6. **DWARF:** `DW_LNE_define_file` entries now increment the unit's
   `file_count`, so later `set_file` indices resolve. `DebugInfo` carries
   `unsupported_version`; when line info is unusable and a DWARF 5/DWARF64 unit
   was seen, stderr gets
   `z9dbg: debug info present but unsupported DWARF version (only 2/3/4);
   using function-entry breakpoints` while `break: no debug info` degradation
   is unchanged. The tier builds a `-gdwarf-5` fixture and asserts both.
9. **Latency:** high-resolution monotonic `nowUs()` (std.time.highRes) is used;
   entry timing is printed after the entry stop display, and breakpoint timing
   after the stop display. Output is `... latency N us`.
   Measured: source-line break 337–358 us; entries 204–1114 us (< 100 ms).
11. **Map discovery + PIE bias:** discovery prefers a sidecar whose stem matches
    the executable stem, accepts a single candidate, and reports
    `z9dbg: ambiguous debug map: N .z98dbg.syms candidates next to the
    executable` otherwise. `setLoadBase` returns failure for an unresolvable
    ET_DYN bias and main warns
    `z9dbg: cannot resolve PIE load bias; breakpoint addresses may be wrong`.
    Tier covers stem preference, two-candidate ambiguity, and a symlinked exe.
12. **Missing `.cnames`:** backtrace prints
    `backtrace limited: no .cnames` instead of silently stopping after `#0`.
    Tier runs a syms+lines-only copy and asserts the notice.
- **WIFSIGNALED:** `waitRaw` decodes signalled termination into the new
  `STOP_SIGNALED_EXIT` (`exit_code = 128 + signo`, `alive = false`,
  `exited = true`), and the session prints
  `z9dbg: debuggee terminated by signal N`; no "signal 0"/stale state.
- **No-debug false success:** if function-entry resolution fails, the break
  table entry is removed and the session prints
  `break: cannot resolve function entry for line <requested line>`; the
  no-debug golden exercises this twice (`break main.zig:8`).
- **FPO warning:** `collectFrames` flags `prev == 0`, `prev <= ebp`,
  unreadable frame memory, a return address outside every STT_FUNC range, or a
  missing non-wrapper map symbol, and backtrace prints
  `backtrace: frame chain unreliable; build with -fno-omit-frame-pointer`.
  Normal chains stop silently at the emitted C `main` wrapper. Tier builds an
  `-O2 -fomit-frame-pointer` fixture and asserts the warning.

## R1.3 Verification

```bash
ZIG=/tmp/z98_m3r2/zig1_5_clean OUT=/tmp/z9dbg_fix_run1 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # 35 passed, 0 failed
ZIG=/tmp/z98_m3r2/zig1_5_clean OUT=/tmp/z9dbg_fix_run2 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # 35 passed, 0 failed
```

Normalized whole-gate logs (RSS/latency values masked) are byte-identical:
`20db94a8157a30b1d8fd0ae0f980e564` both runs. Each reported session is also
run twice and compared internally.

```bash
ZIG=/tmp/z98_m3r2/zig1_5_clean \
  bash examples/z98/z9dbg/tests/tier_dbg_core.sh
== tier_dbg_core summary: 23 passed, 0 failed ==

bash scripts/stdlib/verify_stdlib.sh /tmp/z98_m3r2/zig1_5_clean
run_fixtures: 336 PASS / 0 FAIL over 336 dirs
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
STDLIB GATE OK

bash scripts/check_emit_support.sh /tmp/z98_m3r2/zig1_5_clean
OK: 8/8 support files byte-identical to canonical
```

Latency / RSS (two runs; latency measured through the stop display):

| Program | Lat run1 | RSS run1 | Lat run2 | RSS run2 |
|---|---|---|---|---|
| source-line break (`live`:12) | 358 us | — | 337 us | — |
| hello | 204 us | 1,536 KB | 204 us | 1,900 KB |
| mud_server | 425 us | 2,112 KB | 392 us | 2,284 KB |
| lisp_interpreter_curr | 499 us | 2,308 KB | 444 us | 2,540 KB |
| z9torr (stress) | 1,114 us | 8,060 KB | 1,028 us | 8,260 KB |

All < 100 ms and < 32 MB; max RSS 8.3 MB. `git diff --check` clean before the
commit. No sed/perl/python/awk was used this round.

## R1.4 Files (fix round)

- `backend.zig`, `backend_linux.zig`, `backend_select.zig` (new), `main.zig`
  (vtable ops, select, caps, F3, honesty paths, timing, flush, map/PIE)
- `dbg_core.zig` (dump frames), `dwarf_lines.zig` (define_file, unsupported
  notice, bias status), `map_reader.zig` (span clamp)
- `sf/src/std_os.zig` (debuggee stdio + `Z9DBG_CHILD_OUT`, WIFSIGNALED support
  is backend-side)
- `tests/tier_dbg.sh`, `tests/tier_dbg_core.sh` unchanged this round (core
  harness gained the span-clamp assertion in `tests/dbg_test.zig`)
- `tests/session_set_{hello,mud,lisp,z9play}.in`,
  `tests/session_loopline.in`, `tests/session_live_nodbg.in`,
  `tests/expected/set_{hello,mud,lisp,z9play}.txt`, `loopline.txt`,
  updated `live_{break,step,nodbg}.txt` and `map_hello.txt`
- fixtures `loopline`, `earlyexit`, `crashinit`

## R1.5 Concerns / deferred

1. **Test-set dump stops:** on heavily mapped test-set code a `dump` auto-resume
   may stop at another machine address of the same/next source line instead of
   exiting (e.g. hello line 3, z9play line 435). This is the planted-every-
   address contract, not a debugger wedge; the exact goldens capture the
   resulting stops. The live-fixture dump case still proves completion.
2. **`Z9DBG_CHILD_OUT` is a test-support env**, not a user command: it redirects
   the debuggee's stdout/stderr (the tier uses `/dev/null`). It keeps the
   goldens deterministic and prevents post-quit child output from racing the
   comparison.
3. **Backtrace caller lines** are still function declaration lines, now marked
   `(decl)`; call-site recovery is deferred.
4. **Libc boundary:** a normal chain stops at the emitted C `main` wrapper; a
   return address that is inside executable text but outside every STT_FUNC
   range (or unreadable/zero/backward frame pointers) is treated as unreliable
   and warned, per the review.
5. **PIE bias** is matched by exe basename in `/proc/<pid>/maps`; a renamed or
   symlinked exe warns and degrades rather than silently using 0.
6. **Map stem preference** cannot match the compiler's root-module stem in
   general; a single sidecar is accepted, multiple non-matching sidecars are
   reported as ambiguous.
7. **Prior concerns still apply:** FPO builds are unsupported (now warned),
   DWARF 5/64 degrade with a notice, multi-address step-over is capped at 64
   instructions, the debuggee ELF is read whole into the arena, and
   waitpid/ptrace/open/dup2 rely on implicit C prototypes.

---

# Fix round 2

**Status:** DONE
**Code commit:** `a61b7ec1` `fix(z9dbg): hello test-set session exercises step
(Phase2 P3-M3)`
**Docs commit:** this appended section.

## R2.1 F1 completion — hello step

`session_set_hello.in` now starts with `step`, so the hello test-set session
actually exercises step-into as the tier label claims:

```
step
break greetings.zig:3
continue
backtrace
dump variables @SNAP@
quit
```

The step advances from the entry stop at `main.zig:3` into
`greetings.zig:3` (a different mapped line); the subsequent break/continue
re-hits that line, backtrace lists `sayHello` + `main (decl)`, and the dump
auto-resumes to completion (`z9dbg: debuggee exited`). The tier label
`hello break/continue/step/dump session` is now truthful; the other three
test-set sessions are unchanged.

`tests/expected/set_hello.txt` now contains the step stop display before the
breakpoint hit and the post-dump completion message instead of the old
post-dump stop.

## R2.2 Report correction (Minor)

The fix-round-1 section (R1.4) said
"`tests/tier_dbg.sh` ... unchanged this round". That sentence was wrong: the
fix-round-1 diff changed `tier_dbg.sh` substantially to add the F1 test-set
sessions, honesty checks, and the 2× harness. This fix-round-2 section records
the correction rather than rewriting the earlier text.

## R2.3 Verification

```bash
ZIG=/tmp/z98_m3r2/zig1_5_clean OUT=/tmp/z9dbg_fix2_run1 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # 35 passed, 0 failed
ZIG=/tmp/z98_m3r2/zig1_5_clean OUT=/tmp/z9dbg_fix2_run2 \
  bash examples/z98/z9dbg/tests/tier_dbg.sh    # 35 passed, 0 failed
```

Normalized whole-gate logs are byte-identical:
`20db94a8157a30b1d8fd0ae0f980e564` both runs. `tier_dbg_core.sh` remains
23 passed / 0 failed. `git diff --check` clean before the commit.

No `sf/src/std_os*.zig` or compiler-source change was made this round, so the
std gates were not re-run; the fixed point remains
`11de43a053bdde3be3ddc61caac31df6`.

## R2.4 Files

- `examples/z98/z9dbg/tests/session_set_hello.in`
- `examples/z98/z9dbg/tests/expected/set_hello.txt`
- this report

## R2.5 Concerns

No new concerns. The hello step lands on `greetings.zig:3` and the dump runs
to completion in this session; the test-support `Z9DBG_CHILD_OUT=/dev/null`
behaviour and the fix-round-1 concerns are unchanged.
