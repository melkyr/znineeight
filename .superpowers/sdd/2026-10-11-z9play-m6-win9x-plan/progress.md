# SDD ledger — plan: docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md

**BASE:** `ade87e7f` (M5b console contract complete). **Seed v98** fixed point `f18b69ece1917bf970a036b276e5e403`. Branch `zig1_improvements`. **NO push.**
**Plan amended 2026-10-16** (`075e1bf1`): seed v98 / D1–D8 fixed; Win9x implements the **complete M5b `Console` contract** (9 ops); explicit leave before every exit; `Z9PLAY_WAV_OUT` precedence; exit codes 0–5.

## Pre-flight scan (task / interface table)

- **T1 → T3/T4:** `platform/audio_win9x.zig` (new; `waveOut` backend, implements the M4 `AudioOut` vtable). T1 sole writer; T3 (selection) + T4 consume.
- **T2 → T3/T4:** `platform/console_win9x.zig` (new; implements the M5b `platform/console.zig` contract — 9 ops + `Key`). T2 sole writer; T3/T4 consume.
- **T3:** `main.zig`/`cli.zig` — route audio + console via `@isWindows()` using the vtables; `Z9PLAY_WAV_OUT` precedence; preserve exit codes.
- **T4:** `tests/tier_win9x.sh` (new) — mingw build + Wine smoke. **T5:** `demo/win9x_README.txt` + `NOTES.md`/`README.md`.
- **T6:** reads the amended `2026-10-11-z9play-m7-tui-plan.md`.
- **Shared files:** `main.zig`/`cli.zig` written only by T3; no two tasks write the same file. `run.err` (untracked) left alone.
- **Plan-vs-reality:** M5b delivered the complete `Console` contract + Linux backend; M6's amended plan matches it (T6 review of M5b: "no amendment needed"). Clean.

**Rulings:** none required (scan clean).

## Task 0: complete (controller preflight, 2026-10-16)
- Toolchain present: `i686-w64-mingw32-gcc` (`/usr/bin`), `wine` (`/usr/bin`), `scripts/win32_cross/cross_build_run.sh`.
- Cross harness recipe: `cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [libs...]` → `zig1 -osw --dump-c89` (gate rc=0, 0 `error[`, 0 PANIC) → `i686-w64-mingw32-gcc -std=c89 -m32 …` compile+link (`-lwsock32` unconditional); prints `XRUNRC=<0|DUMPFAIL|GCCFAIL|LINKFAIL|NOC>`.
- M5b console contract confirmed (`platform/console.zig`: `Key = {none,char,sigint,up,down,left,right,enter,esc}`; 9 ops + `state`; `readKey_fn: fn (*void) Key`).
- M4 `AudioOut` vtable confirmed (`platform/audio.zig:38-44`: `open_fn`/`write_fn`/`close_fn`/`drain_fn` + `state`); backends expose free functions the caller assembles.
- Base seed v98 built: `/tmp/z9play_seed_v98/zig1_5_clean` (hop1==hop2 == `f18b69ece1917bf970a036b276e5e403`).

## Task 0 refresh: complete (controller, 2026-10-18)
- Compiler rebuilt from CURRENT `sf/src` (post-D1/D2 parity fixes) per T7 Advisory A1: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_m6` → `/tmp/z9play_m6/zig1_5_clean` md5 `2c48fa702393032c2b711a8d982bd388`, fixed point `b0e5f3b4e580f69eacdac7bd0e07dda1`, three-hop closure OK. The old `/tmp/z9play_seed_v98/zig1_5_clean` (`f18b69e…`) predates the fixes and still exhibits old D2 — NOT to be used.
- Old D2 (error-union ref in comptime-dead `@isWindows()` arm marks callee module reachable) is FIXED at root (T3 `58c4cb1c`/`3583668b` + T4 `a7828e5e`/`d568880c`). Task 1's blocker is gone.
- Task 1 WIP present and untouched: `examples/z98/z9play/platform/audio_win9x.zig` (281 lines) + `audio_win9x_pal.zig` (36 lines), uncommitted, cross-build clean per old report; `main.zig` reverted to base.
- BASE for M6 work: `0b15609c`. No push.
Task 1: complete (commit 866b260f, review Approved 0C/0I/3m). waveOut backend (281+36 lines) + AUDIO-ONLY @isWindows() wiring in main.zig (WAV precedence preserved; explicit else → OSS). Evidence: audio probe -osw XRUNRC=0 PE32 link OK (OSS absent), Linux tiers 20/21/27/23/11, -osw dump md5 d4c173851026b74d547998ad23c1db63 (2x). Full-program -osw GCCFAIL on unconditional console_linux = T2/T3 scope (pre-ruled; reviewer PASS). Minors: *void PAL sigs gcc warnings (typed mirrors later); ignored waveOut reset/unprepare/close rc + unbounded WHDR_DONE poll; deleted scratch probe weakens exact repro.
Task 2: complete (commits d86b3441 + fix round 85234e21..3922044c, re-review 2/2 ADDRESSED green). Win9x console backend, complete 9-op Console contract; Option 3 Ctrl-C per operator ruling + plan Amendment 1 (ded73c0c): enterRaw clears LINE|ECHO|PROCESSED; Ctrl-C = KEY_EVENT uChar 0x03 -> .sigint; SetConsoleCtrlHandler + cdecl cast REMOVED (Critical ABI defect fixed: cdecl through stdcall ptr = stack-cleanup mismatch); atexit restore backstop. D5 recorded (c685fbc0): defect = extern fn with body accepted rc=0 + silently dropped (link error far from cause); feature gap = no stdcall function definitions (minimal fix clean reject; full fix stdcall defs). Evidence: probe -osw XRUNRC=0 PE32, dump md5 81c052098c89218b96da2ea908f77310 (2x), layout vs mingw exact, tiers 11/23/20/21/27 green.
