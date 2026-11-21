# P3-M2 Task 2 report — map reader + debugger core

**Status:** DONE_WITH_CONCERNS
**Branch:** `zig1_improvements`
**Code commit:** `91225298` `feat(z9dbg): map reader + debugger core (Phase2 P3-M2)`
**Docs commit:** this report
**Compiler used:** `/tmp/z98_m2/zig1_5_clean`, built from
`release/seed/zig1-seed.tgz`; closure
`hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6`.

---

## 1. What was implemented

### 1.1 `examples/z98/z9dbg/map_reader.zig`

- Validates and indexes the three Task-1 sidecars without trusting counts:
  - header magic (`Z98DBGsy` / `Z98DBGln` / `Z98DBGcn`), `version == 1`,
    `file_total_len == actual length`;
  - `.syms` record count, minimum-size bound, `kind ∈ {0,1}`, exact record
    walk to EOF;
  - `.lines` group walk, run-count/run bounds, exact EOF; groups counted on a
    first pass so group storage is exact (no worst-case over-allocation); every
    run validates `src_line != 0`, `out_count != 0`, no 32-bit end overflow,
    and strictly ascending `out_line_start`;
  - `.cnames` two-string records, exact EOF.
- Every truncated length/offset/count produces `MapError` (`Corrupt`,
  `UnsupportedVersion`, `OpenFailed`, `OutOfMemory`); no trap.
- Public API: `open`, `symbolAt`, `lineAt`, `lineRowsAt`, `reverseRowAt`,
  plus `symbolByIndex`, `functionByName`, `nextMappedLine`, `cnameFor`,
  `resolveFile`, `resolveOutFile`, and count accessors.
- File query matching: exact path > path suffix > basename (`break` contract).
- Records are offset-indexed and decoded on demand; strings are zero-copy
  slices into the arena-loaded files.

### 1.2 `examples/z98/z9dbg/dbg_core.zig`

- Breakpoint table + spec §7.4 snap rule:
  - whitespace-only line → `break: no executable code at line N`, no-op;
  - mapped line → breakpoint (`break: set at line N`; duplicate
    `break: already set at line N`);
  - other line → next mapped line (`break: moved to line M`) unless that line
    is at/after the next function declaration, then the no-executable-code
    message and no breakpoint.
- Stop display: `Stopped at <path>:<line>`, function name, ±2 nearby source
  lines (current line marked `>`).
- `dump variables` v1 snapshot writer: header, stop location/function, i386
  registers (or `unavailable` when the backend cannot provide them), current
  call-stack frame, all mapped globals (name + source + module stem).
- Entry stop = `main` symbol's first mapped line before the next function.
- No machine address is fabricated; breakpoints are stored in source
  coordinates only.

### 1.3 `examples/z98/z9dbg/backend.zig`

- Tiny vtable exactly as planned: launch, wait, read/write memory, get/set
  regs, single-step, continue, detach, terminate; i386 `Registers` and a
  backend-neutral `StopEvent`.
- `stubBackend()` returns `error.Unsupported` for every operation (M3 installs
  the Linux ptrace implementation without touching the upper layer).

### 1.4 `examples/z98/z9dbg/main.zig`

- Session/command loop: exact startup banner `Z98 debugger has started...`,
  prompt `(z9dbg) `, stop display, commands `break <file>:<line>`,
  `continue`, `step`, `backtrace`, `dump variables [path]`, `quit`; no `run`
  (unknown command).
- Map discovery next to the executable (`*.z98dbg.syms`), entry stop, default
  dump name `z98-dump-<n>.txt`, explicit dump paths, quit/detach path.
- `break` is rejected while running (`break: only valid while stopped`).
- Unknown command: `unknown command: <line>` (defined and tested).
- M2 continue/step report `z9dbg: no live backend (M2)` when the stub is
  present; M3 replaces that backend.

### 1.5 Tests / fixtures

- `tests/dbg_test.zig` — headless harness importing the production modules:
  map assertions, snap assertions, scripted sessions, running-state break
  rejection, dump formatting, corrupt-map error handling, and a mock backend
  used only to make `continue` succeed for the break-while-running case.
- `tests/tier_dbg_core.sh` — builds the harness and the real `z9dbg` binary
  with the binding recipe and runs every compared case 3× byte-identically.

---

## 2. RED evidence (tests written first)

Command:

```bash
ZIG=/tmp/z98_m2/zig1_5_clean \
  bash examples/z98/z9dbg/tests/tier_dbg_core.sh
```

Result (rc=1):

```
== building dbg_test (binding recipe, -fsafe) ==
FAIL: zig compile (see /tmp/z9dbg_core_tier/zig.log)
       Z98 Compiler 2026 (map: off)
       error[3048]: could not resolve imported file '../map_reader.zig'
       error[3048]: could not resolve imported file '../dbg_core.zig'
       error[3048]: could not resolve imported file '../main.zig'
       error[3048]: could not resolve imported file '../backend.zig'
       ...
SCRIPT_RC=1
```

---

## 3. GREEN evidence (final code)

Single run:

```bash
ZIG=/tmp/z98_m2/zig1_5_clean \
  bash examples/z98/z9dbg/tests/tier_dbg_core.sh
```

Result (rc=0):

```
== building dbg_test (binding recipe, -fsafe) ==
== map reader fixtures ==
ok   - map_hello 3x
ok   - map-hello assertions
ok   - map_fib 3x
ok   - map-fib assertions
== breakpoint classification / snap ==
ok   - snap_hello 3x
ok   - snap assertions
== scripted session (exact strings) ==
ok   - session 3x
== break is rejected while running ==
ok   - session-running 3x
== default dump names z98-dump-<n>.txt ==
ok   - session-default 3x
== dump writer with formatted registers ==
ok   - dump-regs 3x
== standalone z9dbg binary (map discovery + session) ==
ok   - z9dbg binary session 3x
== corrupt / truncated / missing maps fail cleanly ==
ok   - trunc clean error
ok   - magic clean error
ok   - version clean error
ok   - count clean error
ok   - total clean error
ok   - str clean error
ok   - linetrunc clean error
ok   - cnamemagic clean error
ok   - missing clean error

== tier_dbg_core summary: 20 passed, 0 failed ==
TIER_DBG_CORE PASS
SCRIPT_RC=0
```

3× whole-gate determinism:

```bash
for i in 1 2 3; do
  ZIG=/tmp/z98_m2/zig1_5_clean OUT=/tmp/z9dbg_tier_final_$i \
    bash examples/z98/z9dbg/tests/tier_dbg_core.sh \
    > /tmp/z9dbg_tier_final_$i.log 2>&1
done
md5sum /tmp/z9dbg_tier_final_*.log
```

```
58499e3943702937d71d08218ab5817e  /tmp/z9dbg_tier_final_1.log
58499e3943702937d71d08218ab5817e  /tmp/z9dbg_tier_final_2.log
58499e3943702937d71d08218ab5817e  /tmp/z9dbg_tier_final_3.log
```

The standalone `z9dbg` binary also passed a session under `ulimit -v 32768`
(rc=0, stdout byte-identical to the expected session), confirming the 32 MB
debugger envelope for the fixture workload.

---

## 4. Fixtures

Generated with the same seed-built compiler and committed:

```bash
/tmp/z98_m2/zig1_5_clean -q -d -o <tmp> \
  examples/z98/z9dbg/tests/fixtures/hello/main.zig
/tmp/z98_m2/zig1_5_clean -q -d -o <tmp> \
  examples/z98/z9dbg/tests/fixtures/fibonacci/main.zig
```

Regenerating both fixtures and `cmp`-ing all six map files against the
committed copies produced `FIXTURES_REPRODUCIBLE`.

| Fixture | source | `.syms` | `.lines` | `.cnames` |
|---|---|---|---|---|
| hello | `tests/fixtures/hello/main.zig` | 3 symbols | 1 group / 6 runs | 3 names |
| fibonacci | `tests/fixtures/fibonacci/main.zig` | 2 symbols | 1 group / 6 runs | 2 names |

The fixtures intentionally cover: global-init row (hello line 1), two functions,
two `.lines` runs for one source line (hello 16, fib 2), comment-only lines,
blank lines, `}`, a declaration line, a struct field, and a closing line after
the last function.

Expected strings/goldens live in `tests/expected/` with a nested `.gitignore`
(`!*.txt`) because the repository root ignores `*.txt` as app output.

---

## 5. `std_os` decision + gates

`sf/src/std_os.zig` was **not touched**. No M2 core test needed a debug binding;
ptrace/waitpid/Win32 shapes belong to M3/M4. Therefore no
`verify_stdlib.sh` / `run_crosscheck.sh` run was required for this task.
No compiler source was changed, so no corpus/goldens/pins/markers/examples
battery was run (per the operator-approved hybrid gating).

`git diff --cached --check` was clean before the code commit; `run.err` was
untouched.

---

## 6. Files

Code commit `91225298`:

- `examples/z98/z9dbg/backend.zig`
- `examples/z98/z9dbg/dbg_core.zig`
- `examples/z98/z9dbg/main.zig`
- `examples/z98/z9dbg/map_reader.zig`
- `examples/z98/z9dbg/tests/dbg_test.zig`
- `examples/z98/z9dbg/tests/tier_dbg_core.sh` (mode 100755)
- `examples/z98/z9dbg/tests/session_hello.in`
- `examples/z98/z9dbg/tests/session_running.in`
- `examples/z98/z9dbg/tests/session_default.in`
- `examples/z98/z9dbg/tests/expected/.gitignore`
- `examples/z98/z9dbg/tests/expected/{map_hello,map_fib,snap_hello,session_hello,session_running,session_default,dump_hello,dump_regs_hello}.txt`
- `examples/z98/z9dbg/tests/fixtures/hello/{main.zig,main_BDA8D6C7.z98dbg.{syms,lines,cnames}}`
- `examples/z98/z9dbg/tests/fixtures/fibonacci/{main.zig,main_4DFBF9C3.z98dbg.{syms,lines,cnames}}`

Docs commit: this report.

---

## 7. Self-review

- Compiler/std/plan/spec untouched; only `examples/z98/z9dbg/` added.
- Reader validates all three headers/counts/lengths and every record boundary;
  corrupt syms/lines/cnames, truncated headers, bad version, bad counts,
  oversized str16, and missing files all produce clean errors.
- Snap rule matches §7.4 cases: whitespace reject, comment/`}`/field/no-row
  snap-forward, declaration snap, next-function boundary reject, no-EOF target
  reject; exact strings are golden-tested.
- Breakpoint duplicates are no-ops with a defined message; the running-state
  rejection is tested via a test backend whose `continue` succeeds.
- `dump variables` default naming (`z98-dump-1.txt`, `z98-dump-2.txt`) and
  explicit paths are both tested; snapshot content includes i386 register
  formatting and globals.
- Standalone binary path (argument handling → map discovery → session) is
  exercised, not just the imported `runSession` function.
- 3× determinism is byte-identical for every compared output.
- Process note: one mechanical replacement of `std.fmt.printU32(x)` with
  `std.io.printInt(@intCast(i32, x))` across three files was applied with
  `perl -pi` instead of `edit`/`fastedit`. It was a pure call-site swap (needed
  to avoid mixing buffered `std.io` output with unbuffered `std.fmt` output)
  and the full gate was re-run afterwards. No other bulk edit was used.

---

## 8. Concerns / deferred to M3/M4

1. **Map residency.** M2 loads the three sidecars into the caller arena (bounded
   by map size; the z9torr map is ~275 KB and parsed success was manually
   checked). Records/strings are decoded lazily from offsets, but this is not
   yet per-section streaming I/O. A future M3 refinement can section the files.
2. **Source reads.** `readSourceLine` re-reads the whole source file per
   lookup. This is fine for the fixture/probe workload but is wasteful and
   arena-hungry on large sources; M3 should cache source content and define the
   source-root policy (map paths are relative to the compile CWD).
3. **`dump variables` v1 scope.** Call stack is the current frame only; globals
   are all mapped globals (including std globals when a real map is used).
   Frame-pointer unwinding/filtering is M3.
4. **`continue`/`step` success path.** With the M2 stub they always report
   `z9dbg: no live backend (M2)`. M3 adds wait/resolve/show-stop after a
   successful resume.
5. **Map discovery** currently takes the matching `.z98dbg.syms` found in the
   executable's directory; multiple sidecars in one directory should become an
   error/selection rule in M3.
6. **Fixed caps:** breakpoint table 256, dump text buffer 64 KB, main arena
   4 MB. Adequate for the M2 fixture workload; revisit with the M3 test set.

---

# Fix round 1

**Status:** DONE
**Commit:** `99b2c1cf` `fix(z9dbg): optional cnames, lazy map sections, dump/step semantics (Phase2 P3-M2)`
**Docs commit:** this appended section.

## F1 — `.cnames` is optional (spec §7.2)

`map_reader.open` no longer requires `.cnames`:

- if the file is absent, `has_cnames = false`, `cnameCount()` returns 0 and
  `cnameFor()` returns null;
- if the file is present, its header and record walk are still validated at
  open (corrupt/truncated `.cnames` is still a clean `MapError`).

New tests:

- `map-nocnames` (harness) opens a syms+lines-only map and asserts symbol
  lookup, line lookup, entry stop, `cnameCount == 0`, and `cnameFor == null`;
- the standalone `z9dbg` binary is run in a second executable directory that
  contains syms+lines but no cnames, using the full `session_hello.in` scripted
  session; stdout/dump files match the normal session byte-for-byte.

```
ok   - map-nocnames 3x
ok   - z9dbg binary no-cnames session
```

## F2 — lazy/sectioned map loading (spec §5 / plan R4)

`map_reader` is now file-backed and sectioned:

- open reads only the 20-byte headers, validates the symbol/cname record
  boundaries by streaming (no content retained), and reads the `.lines` group
  headers. `.lines` run payloads are **not** read at open.
- A group's runs are read on demand (`readRun`, 12 bytes at a time);
  `reverseRowAt` binary-searches a group's runs instead of scanning.
- `.syms` and `.cnames` contents are loaded only on first symbol/cname query
  (`loadSyms` / `loadCnames`), then decoded zero-copy from their arena section.
- The whole `.lines` run stream (the large section) is never resident.
- Forward (`lineAt`, `lineRowsAt`, `nextMappedLine`) and reverse
  (`reverseRowAt`) behavior is preserved and covered by the existing fixtures.

Self-host map / memory evidence (reviewer's exact map sizes reproduced):

```bash
mkdir -p /tmp/z9dbg_self
/tmp/z98_m2/zig1_5_clean -q -d -o /tmp/z9dbg_self sf/src/main.zig
H=/tmp/z9dbg_core_tier/prog
bash -c 'ulimit -v 32768; /usr/bin/time -v \
  $H bench-full /tmp/z9dbg_self/main_9472B9CB'
```

```
syms 144,666 B   lines 1,101,257 B   cnames 102,445 B
2,089 symbols   48 groups / 91,565 runs   2,089 cnames

bench counts symbols=2089 groups=48 runs=91565 cnames=2089
Maximum resident set size (kbytes): 1476 / 1340 / 1568   (3 runs)
```

`bench-open` (headers + group headers only, no syms/cnames/run payloads):
`1244 / 1232 / 1380 KB`. The previous whole-load measurement was
**3,084 KB**; new peak is ~1.3–1.6 MB with all sections exercised. Most of
that remaining footprint is process/runtime + the 1 MB harness arena; the
91,565-run `.lines` stream is not retained.

## F3 — dump resume state

`handleDump` now returns whether the resume succeeded; `runSession` clears
`stopped` on a successful `dump variables` resume, so `break` is rejected
after a dump has resumed the debuggee. The `session-step` scripted test does:
`step` → `break` (accepted) → `dump variables` → `break` (rejected) →
`continue` → `break` (rejected).

```
ok   - session-step 3x
```

## F4 — `step` is step-into next mapped Z98 line

- `dbg_core.stepInto` loops over the backend vtable: `singleStep_fn` +
  `wait_fn`, resolving each stop through a caller-supplied `ResolveFn`.
  Unmapped C stops and stops on the same Z98 line are skipped; the loop
  returns on the first mapped line different from the current stop, or on
  exit/exhaustion.
- `main` calls this for `step`, updates the session stop, redraws the stop
  display, and keeps `stopped = true` (the old one-instruction path left the
  session looking "running").
- The harness mock backend scripts stops at lines 14 (same), 15 (unmapped),
  16 (mapped), proving the loop steps through unmapped C and lands on 16.
  M3 only needs to supply the DWARF-backed resolver + real backend.

## Verification (fix round)

```bash
for i in 1 2 3; do
  ZIG=/tmp/z98_m2/zig1_5_clean OUT=/tmp/z9dbg_fix1_$i \
    bash examples/z98/z9dbg/tests/tier_dbg_core.sh \
    > /tmp/z9dbg_fix1_$i.log 2>&1
  echo "run$i rc=$?"
done
md5sum /tmp/z9dbg_fix1_*.log
```

```
run1 rc=0
run2 rc=0
run3 rc=0
8912f662d547c11d110925caf6983089  /tmp/z9dbg_fix1_1.log
8912f662d547c11d110925caf6983089  /tmp/z9dbg_fix1_2.log
8912f662d547c11d110925caf6983089  /tmp/z9dbg_fix1_3.log
```

Gate summary: `23 passed, 0 failed` per run; `git diff --check` clean.
`std_os` and the compiler remain untouched; map format/Task 1 artifacts
unchanged.

## Files (fix commit `99b2c1cf`)

- `examples/z98/z9dbg/map_reader.zig` — file-backed sectioned reader,
  optional cnames, on-demand runs, lazy syms/cnames sections.
- `examples/z98/z9dbg/dbg_core.zig` — `stepInto` loop + `ResolveFn`; phantom
  line after a trailing newline no longer reported.
- `examples/z98/z9dbg/main.zig` — dump resume state, step loop/resolver,
  `runSession` resolver parameters.
- `examples/z98/z9dbg/backend.zig` — backend-neutral stop-reason constants.
- `examples/z98/z9dbg/tests/dbg_test.zig` — no-cnames, step-session, and
  bench-open/bench-full modes; mock step backend/resolver.
- `examples/z98/z9dbg/tests/tier_dbg_core.sh` — no-cnames, step/dump-state,
  standalone no-cnames checks.
- `examples/z98/z9dbg/tests/session_step.in` +
  `tests/expected/{session_step,dump_step,map_nocnames}.txt`.

## Fix-round concerns

1. `.lines` run payloads are no longer validated at open (that would read the
   whole run stream eagerly, defeating the lazy-run requirement). Truncated
   files, bad group headers/counts/strings, and bad magic/version still fail
   at open; a corrupted run field is bounds-checked on read and never traps,
   but is not reported as an open-time error. This is the deliberate trade for
   on-demand group runs.
2. `.syms`/`.cnames` are validated by streaming at open but loaded as whole
   sections on first use (144,666 B / 102,445 B on self-host). They are one
   section each in the current format; no per-record residency.
3. `stepInto`'s resolver is caller-supplied; M2 main passes a no-resolve
   callback (so the M2 stub still reports "no live backend"), and M3 wires the
   DWARF resolver. The loop itself is fully exercised by the mock test.
4. `dump variables` resume still updates only the stopped flag; M3 owns the
   real wait/stop path after resume.
5. Source reads still re-read the source file per lookup (unchanged from
   round 0); unrelated to the map residency fix.
