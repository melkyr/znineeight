# I task — why does a Windows-hosted zig1.exe fail?

**Repo:** /workspace/znineeight, branch `zig1_improvements`.
**Mode:** investigation only. No production fixes. Temporary probes/binaries allowed.
**Seed artifacts:** `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`,
`release/seed/CHANGELOG.md` are currently uncommitted (v121). Do not commit or modify them.

## Fixed decisions
- No operator MSVC/OpenWatcom probe. MSVC/OW will be a prediction, not a confirmation.
- Keep the v121 artifacts uncommitted.
- Include the Linux `gen/` C built with MinGW CRT as a differential.
- Local only (MinGW + Wine).
- First test: compile already-valid emitted C programs with MinGW here, run under Wine.

## Evidence so far
- Linux compiler works.
- MinGW CRT `zig1.exe` from the CRT-only zip builds and prints usage, but fails on `hello`:
  - 9x `-fsafe` C: trap in `cnameDedupKey` (bad `cname` slice length).
  - `-ffast` C: `std_debug.zig:64` — `tag.len` “no field len” on `tag: []const u8`.
  - `-osw nt` MinGW: `int3` under Wine.
  - 8 MB stack: no change.
- z9dbg works under MinGW/Wine, so basic slices/vtables are fine.
- The compiler uses `@sizeOf`/`@offsetOf` heavily; layout conformance is the main hypothesis.

## Phase 1 — baseline (must run first)
Use `/tmp/seed_v121/zig1_5_clean` (Linux seed compiler; `lib/` beside it).

Emit valid programs with `-osw`:
```
/tmp/seed_v121/zig1_5_clean -osw -o /tmp/inv/hello examples/z98/hello/main.zig
/tmp/seed_v121/zig1_5_clean -osw -o /tmp/inv/lisp  examples/z98/lisp_interpreter_curr/main.zig
```
Build with MinGW and run under Wine:
```
cd /tmp/inv/hello && sh build_target.sh mingw && wine hello.exe
cd /tmp/inv/lisp  && sh build_target.sh mingw && printf '(+ 1 2)\n' | wine lisp.exe
```
Expected: hello prints its greeting; lisp prints `3`. Capture exact stdout/stderr/rc.
If lisp is awkward, use another already-valid program (e.g. `docs/sf/manuals/src/vol3/echo.z98`) and record.
**If Phase 1 fails, STOP and report; do not proceed to Phase 2.**

## Phase 2 — compiler C differential
2a. Windows-target compiler C: extract `release/seed/zig1_seed_w9.zip` to `/tmp/inv/w9`;
from `zig1-seed-w9/win` build with MinGW CRT:
```
i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_WIN32 -I . -c *.c
i686-w64-mingw32-gcc -m32 *.o -o ../zig1.exe -lkernel32 -lwinmm -lwsock32
```
`lib/` is at the zip root. Run `wine zig1.exe` (usage), then compile `hello` with `-osw`
(relative paths, output dir exists) and capture the first failure.

2b. Linux-target compiler C: copy only `*.c/*.h` from `/tmp/seed_v121/gen` to `/tmp/inv/genwin`;
build the same way with `-DZIG_WIN32` and MinGW CRT; copy `/tmp/seed_v121/lib` beside the exe;
run usage and compile `hello`. If `write`/stdio symbols are missing, record the link error
(this differential is still informative); do not add production shims.

Interpretation:
- 2a fails, 2b works → `-osw` compiler emission/profile is the problem.
- both fail → the compiler’s own C/ABI under MinGW is the problem.
- both work → the zip’s script/profile is the problem.

## Phase 3 — layout conformance (next agent)
Static audit + Z98 probe + C probe; compare `@sizeOf`/`@offsetOf` vs `sizeof`/`offsetof`
under Linux gcc and MinGW. Any mismatch names the type/field.

## Phase 4 — binary diagnosis (next agent)
`-g -O0` build, Wine/gdb/winedbg, break `pal_trap`/`cnameDedupKey`, capture the bad slice,
caller, C line; `WINEDEBUG=+seh`; find the first corruption.

## Phase 5 — differential flags (next agent)
`-mms-bitfields` vs `-mno-ms-bitfields`, `-malign-double`, `-O0/-O2`, `-fno-strict-aliasing`,
`-fwrapv`, `-DZIG_WIN32` vs `-DZIG_WIN_NT`, `-fsafe` vs `-ffast`.
Each: usage, `hello`, no-std, `std_debug`-only.

## Phase 6 — minimal reproducers (next agent)
`std_debug`-only, slice-param `.len`, no-std, `@sizeOf`/`@offsetOf` probe.

## Phase 7 — verdict (next agent)
Root cause; MinGW-specific vs common; MSVC/OW prediction (unconfirmed); fix scope; seed
decision (do not commit the zip until the verdict).

## Report contract
- This agent (phases 1-2) writes `/workspace/znineeight/.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/phase12-report.md`
  with exact commands, output, rc, versions, md5s, and the Phase 1/2 conclusions.
- Return only: status, key results, report path.
- No production edits, no commits, no seed changes, no subagents, no destructive git.
- If a phase cannot run, STOP and report the exact blocker.
