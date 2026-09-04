# Win32 Cross-Compile Pre-Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cross-compile zig1-emitted C89 (the in-scope example programs AND the compiler itself) to win32 PE with `i686-w64-mingw32-gcc` and run under 32-bit `wine`, proving byte-parity behavior vs the linux goldens — the operator's pre-trigger go/no-go for the win9x VM pass.

**Architecture:** Pure test/report plan — ZERO source edits (`sf/src`, `sf/src/include/*`, `examples/*`, gate programs, goldens all untouched). A committed harness (`scripts/win32_cross/`) performs: dump C89 with the reference compiler → cross-compile with mingw → run under a win32 wine prefix → compare stdout to linux goldens. Failures are classified (environment / toolchain / gap) and reported, never silently fixed. One `ZIG_NO_CRT` smoke and the compiler self-host cross-compile are included per operator ruling.

**Tech Stack:** `i686-w64-mingw32-gcc` (12-win32), `wine` 8.0 (`WINEARCH=win32` prefix), reference compiler `/tmp/fx_subfolder/zig1` (md5 `7c08d2d5`, std lib at `/tmp/fx_subfolder/lib`), existing harness/goldens (`scripts/closeout/`, `/tmp/fx_fix/{golden_ref,matrix_ref}`, `examples/z98/*_upgraded/demo/`).

Design spec: `docs/superpowers/specs/2026-09-04-win32-cross-pre-test-design.md` (operator-approved).

## Global Constraints

- **NO source edits anywhere** — not `sf/src`, `sf/src/include/*`, `examples/*`, gate programs, or any committed golden. Only new files under `scripts/win32_cross/` and the report are committed. Fixes are out of scope by operator ruling; breakage is reported as a gap.
- Only plan-authorized actions; STOP-present on any confusion/divergence; commits only per-task with the brief's exact message; stage ONLY intended files; pre-existing dirty/untracked set (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `examples/z98/json_parser_upgraded/`) never staged.
- All builds/dumps use fresh dirs (`rm -rf` + `mkdir -p`) and `timeout`-guard every run. Net runs: localhost only, never `pkill`; kill only PIDs started; verify no listener left after.
- Wine: use a dedicated 32-bit prefix (e.g. `/tmp/wine32` with `WINEARCH=win32`), set per-command (`WINEPREFIX=... WINEARCH=win32 wine prog.exe`), never mutate the operator's wine config.
- Goldens are the linux-verified ones already committed/recorded (mud boot line; rogue net `server.out` `aa40a52e`; canonical `96654b39`/`3fb6709e`/`b3c5b0e1`; demos `7361d248`/`aa40a52e`/`834459d0`). Byte-parity is measured against those. The lisp demo `(address)` line stays masked per AMENDMENT-4 convention.

**AMENDMENT 1 (operator ruling, 2026-09-04):** the parity criterion for CRT-path programs (`std_io` `fwrite`/`putchar` → msvcrt win32 **text mode** translates `\n`→`\r\n`, reproduced under wine and on any real win32/win9x) is **LF-normalized byte parity** — `cross_parity.sh` strips `\r` before the compare when `PARITY_STRIP_CR=1` is set; the raw wine stdout (`stdout.txt`) is preserved as evidence. PAL `WriteFile`-path programs (e.g. `game_of_life`) keep strict byte parity. CRLF output is expected real-platform behavior, NOT a defect and never fixed.
- Reports accumulate in `.superpowers/sdd/task-WIN32-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory`, agent `win32cross-session`.
- Per-task report contract: status, cross-compile/link/run rc evidence, byte-parity result (md5), wine prefix/proc evidence, gaps classified (environment/toolchain/gap), concerns.

---

### Task 0: Toolchain recipe + smoke (no commits yet)

**Files:**
- Scratch only (fresh dirs under `/tmp/`).
- Record: `.superpowers/sdd/task-WIN32-report.md` header.

**Interfaces:**
- Produces: the authoritative win32 cross compile/link/run recipe (flags, include path, per-program link set, wine prefix invocation) reused by Tasks 1-4.

- [ ] **Step 1: Capture the linux link set per program from QUICK_REF.** Read `docs/sf/QUICK_REF.md` sections that define the build/link recipe per program (esp. the mud_server modern-vs-legacy `net_runtime.c` rule at QUICK_REF lines ~32, 451-456, 653-655, 714, 767 and the multi-module recipe). Record, per in-scope program (gol, lisp_curr, json_parser, mud_server, lisp_interpreter_upgraded, rogue_mud_upgraded, rogue net variant, net client), the exact set of `.c` files linked on linux (zig_runtime.c / zig_pal.c / net_runtime.c presence) and the include flags. If any rule is ambiguous, STOP-present.

- [ ] **Step 2: Initialize the win32 wine prefix.** `export WINEPREFIX=/tmp/wine32 WINEARCH=win32; wineboot -i` (first run initializes; may print fixme noise). Verify `wine --version` and that `$WINEPREFIX/drive_c` exists. Timeout-guard.

- [ ] **Step 3: Toolchain smoke.** Write a trivial C89 program under `/tmp/win32_smoke/` (`int main(void){ printf? }` — NO, the runtime never uses printf; use a plain `write`-style via nothing: keep it to `int main(void){ return 0; }` plus a stderr byte) — compile: `i686-w64-mingw32-gcc -std=c89 -m32 -Wall -o /tmp/win32_smoke/smoke.exe /tmp/win32_smoke/smoke.c`; run: `timeout 20 env WINEPREFIX=/tmp/wine32 WINEARCH=win32 wine /tmp/win32_smoke/smoke.exe`; expect rc=0. Then compile the ACTUAL minimal runtime path: a tiny C that `#include "zig_compat.h"` + links `sf/src/include/zig_pal.c` and calls `pal_print_stdout("hi\n",3)` + `pal_get_default_lib_path`, and verify it runs under wine and prints `hi`. Record any flags needed for a clean 32-bit mingw link.

- [ ] **Step 4: Capture the recipe + smoke evidence.** Record: exact cross `gcc` flags (`-std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include`; add `-mconsole` if needed), link extras (e.g. `-lwsock32` for net programs that need it, msvcrt is default), wine invocation, stdout CRLF-vs-`\n` behavior observed on the smoke (was the output byte-exact `hi`? any `\r`?). Record `file smoke.exe` (must say PE32). Report section + ledger note. NO commit in this task.

---

### Task 1: Gate-program cross matrix (stdio/math/text)

**Files:**
- Create: `scripts/win32_cross/cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]`
- Create: `scripts/win32_cross/cross_parity.sh <entry> <feed> <expected_stdout> <workdir>` (wraps build+run+`cmp`)

**Interfaces:**
- Consumes: Task 0 recipe.
- Produces: per-program parity evidence for gol / lisp_curr / json_parser (and mud boot path deferred to Task 2).

- [ ] **Step 1: Write `cross_build_run.sh`.** Dump C89 into a fresh dir (`(cd /workspace/znineeight && <zig1> --dump-c89 --output-dir <W> <entry>)`, expect 0 `error[`, 0 PANIC, `RUNRC=0`), then `i686-w64-mingw32-gcc` each emitted `.c` → `.o` (flags from Task 0), link `.o` + the Task-0 link set + any extra libs → `<exe_out>.exe`. Echo `XRUNRC`. Fresh dirs; every sub-run `timeout`-guarded.

- [ ] **Step 2: Write `cross_parity.sh`.** Run the `.exe` under the wine prefix with a feed on stdin, capture stdout to a file; `cmp` against `<expected_stdout>` (the committed/recorded linux golden); echo `PARITY=OK|DIFF`; on DIFF print `diff` output. Handle the lisp `(address)`-mask rule where the caller passes a mask flag.

- [ ] **Step 3: Run the matrix for `game_of_life`** (bounded-run feed as recorded in the matrix refs), `lisp_interpreter_curr` (recorded basic feed), `json_parser` (run from its own dir with its `test.json` as recorded; note any CWD requirement for json_parser input files). For each: cross-compile rc=0, wine run rc recorded, stdout byte-parity vs the `/tmp/fx_fix/matrix_ref` / `golden_ref` linux outputs (or the recorded goldens). 3× run determinism for one program.

- [ ] **Step 4: Record results.** Verdict table (program × cross rc / wine rc / parity md5 / class). Any failure: reproduce once, classify (environment/toolchain/gap), capture evidence, do NOT fix.

- [ ] **Step 5: Commit the harness.**

```bash
git add scripts/win32_cross/cross_build_run.sh scripts/win32_cross/cross_parity.sh
git commit -m "test: win32 cross-build/run + parity harness (cross_build_run.sh, cross_parity.sh)"
```

- [ ] **Step 6: Report.** Table + evidence + concerns. Ledger line.

---

### Task 2: Net/win-socket programs under wine

**Files:**
- Create: `scripts/win32_cross/cross_net.sh` (mud_server + rogue net variant server/client runner)

**Interfaces:**
- Consumes: Task 1 harness + Task 0 net link rule.
- Produces: winsock-under-wine evidence for `mud_server` and the rogue net demo.

- [ ] **Step 1: Cross-build `mud_server`** (examples/z98/mud_server) per the Task-0 authoritative link set (modern F6-migrated path: socket builtins inline — confirm whether net_runtime.c is required by QUICK_REF for THIS tree; if required, link it with `-lwsock32`). Cross-compile rc=0; run the server under wine (localhost:4000; ensure 4000 free first per the operator port discipline); connect with the linux-built net client precedent (or the committed `demo/net_demo_client.zig` cross-built) and send a movement command; capture server stdout; compare to the linux mud boot/behavior golden (`MUD server listening on port 4000` + response line). Kill only the PIDs you started; verify no listener remains (wine + host).

- [ ] **Step 2: Cross-build the rogue net demo.** `rogue_mud_upgraded/demo/net_main.zig` (server, MULTIPLAYER=true) + `demo/net_demo_client.zig` (client, port 4000). Run both under wine per the AMENDMENT-6 procedure (server `< /dev/null` under `timeout -k 2 12`, `LD_PRELOAD` flush shim is LINUX-ONLY — under wine the server must be run such that its stdout is captured AFTER flushing: wine console writes via the pal `WriteFile` path which is unbuffered at the OS level once the program exits/terminates? — determine the correct capture method for wine; if the fully-buffered `fwrite`-style path loses output under wine timeout-kill, run the client, then let the server exit via a graceful path or capture after `wine` exits and note the mechanism in the report). Compare captured server stdout to `demo/net_demo_expected.txt` (aa40a52e) with the `(address)`-free net block (byte-compare whole file; the net info block has no address line). 

- [ ] **Step 3: Record winsock results.** Both programs: cross rc / wine run / parity / class. Any winsock-specific difference (WSAStartup init timing, select behavior, SOCKET vs int casts) documented with evidence. Do NOT fix.

- [ ] **Step 4: Report + ledger.** Verdicts, evidence, gaps classified. No harness commit needed unless a new runner file was required (commit only that file with an exact message if so, else none).

---

### Task 3: `_upgraded` showcase programs under wine

**Files:**
- None new (reuse Task 1 harness).

**Interfaces:**
- Consumes: Tasks 1-2 harness + the committed `_upgraded` demo assets/goldens.
- Produces: feature-rich showcase parity under wine (proves the new builtins/export/net constructs run on win32).

- [ ] **Step 1: `lisp_interpreter_upgraded`:** canonical feed → byte-parity `96654b39`; demo feed → parity with the AMENDMENT-4 mask (all lines byte-equal except the `(address)` integer line, which must be a positive integer); export symbol presence check in the PE (e.g. `i686-w64-mingw32-nm` on the `.exe` or the linked objects shows `alloc_value` by source name — confirm the exact tool/flags; if nm is unavailable, record how symbols were verified or mark as environment-gap).

- [ ] **Step 2: `rogue_mud_upgraded`:** canonical q feed → `3fb6709e`; canonical move feed → `b3c5b0e1`; local `i` demo feed → `7361d248`; export gates via PE symbol check (`saveDungeon`/`loadDungeon` source-named, no mangled-only).

- [ ] **Step 3: Determinism.** 3× run one demo feed; byte-stable (minus any platform-documented variance). Record wine `file`/`objdump -p` header evidence that outputs are PE32 console images.

- [ ] **Step 4: Report + ledger.** Verdict table + gaps. No new file commit unless a runner tweak was needed (commit with exact message if so).

---

### Task 4: NO_CRT smoke + compiler self-host cross

**Files:**
- Create: `scripts/win32_cross/cross_nocrt.sh` (builds one program with `-DZIG_NO_CRT`)
- Create: `scripts/win32_cross/cross_compiler.sh` (dumps `sf/src/main.zig`, mingw-cross-compiles, runs the win32 zig1 under wine)

**Interfaces:**
- Consumes: Task 0 recipe.
- Produces: no-CRT proof + win32-compiler proof; either may report gaps.

- [ ] **Step 1: NO_CRT smoke.** Take one non-net program (e.g. `game_of_life` or a small stdio one). Cross-compile with `-DZIG_NO_CRT`, verify the pal `mainCRTStartup` entry is used (link entry symbol; mingw needs the entry set — confirm whether `-e mainCRTStartup` or the pal's exported `mainCRTStartup` is picked up; record the working link flags). Run under wine; byte-parity vs the linux golden. Record evidence that the binary does not depend on msvcrt (e.g. `objdump -p` import table has only kernel32).

- [ ] **Step 2: Compiler self-host cross.** Dump the compiler: `(cd /workspace/znineeight && <zig1> --dump-c89 --output-dir <W> sf/src/main.zig)` (expect 0 `error[`, 0 PANIC). Cross-compile ALL emitted `.c` + the Task-0 link set (compiler needs no net) with `i686-w64-mingw32-gcc` → `zig1.exe`. Record compile/link result. If it links, run under wine: `timeout 60 env WINEPREFIX=/tmp/wine32 wine <W>/zig1.exe --dump-c89 examples/z98/hello/main.zig` into a fresh dir (zig1 needs its `lib/` — copy `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into a wine-visible `lib/` next to `zig1.exe`, or pass the install path; use the same lib-relative rule the compiler uses) and verify the win32 compiler emits the same C89 as the linux reference (compare emitted `.c` md5). Report PASS or a classified gap.

- [ ] **Step 3: Report + ledger.** NO_CRT result, self-host cross result, evidence, gaps. Commit the two runner scripts if created (exact messages), else no commit.

---

### Task 5: Aggregate report + STOP-present

**Files:**
- Record only: `.superpowers/sdd/task-WIN32-report.md` (final verdict section).

**Interfaces:**
- Consumes: Tasks 0-4 evidence.

- [ ] **Step 1: Build the aggregate verdict table** (rows: gol, lisp_curr, json_parser, mud_server, lisp_interpreter_upgraded, rogue_mud_upgraded, rogue net demo, NO_CRT smoke, compiler self-host × columns: dump rc / mingw rc / link rc / wine run rc / byte-parity / class) and the gaps list (each classified environment/toolchain/gap, with evidence path).

- [ ] **Step 2: Record the win9x-readiness recommendation** (what the wine pass proves, what remains for the VM: console interactivity, no-CRT on real win9x, file CWD semantics, etc.). Do NOT touch EXPECTED_FAIL.md / QUICK_REF.md (deferred).

- [ ] **Step 3: STOP-present to the operator** with the full verdict table, gaps, and recommendation. No further action until the operator directs.

---

## Plan Self-Review

1. **Spec coverage:** operator rulings 1-4 all map to tasks (scope → T1-T3, no-edits → Global Constraints + every task, NO_CRT + self-host → T4, report-only → T5). Success criteria map to tasks 0-4; verdict/gaps → T5.
2. **Placeholder scan:** no TBDs; recipe specifics (exact per-program link sets, entry-symbol flags for NO_CRT, PE symbol-check tool) are deliberately captured as Task-0/4 determinations because they cannot be known a priori without execution — each step names exactly what to record/decide and to STOP if ambiguous.
3. **Type/name consistency:** script names prefixed `cross_`; report file `task-WIN32-report.md`; goldens referenced by their committed md5s.
