# Phase 2 Project 3 — Source-Level Z98 Debugger — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opt-in `--debug`/`-d` compiler sidecar map (Z98 ↔ generated source + optional C names) plus an out-of-process terminal debugger (`z9dbg`) with source-line breakpoints, working on Linux (ptrace) and Win98 (Win32 Debug API).

**Architecture:** Side-table span capture at lowering (never `LirInst`, never `lir_stream` record format), streamed map writer at emission keyed by the existing `(inst_bb, inst_ii)` hook and a `BufferedWriter` line counter; three map files (`.syms`/`.lines`/`.cnames`) next to the primary output. The debugger reads the map lazily, resolves machine addresses through the **C compiler's** debug info (DWARF 2/3/4 on Linux; embedded COFF `/Z7`-style on Win98 — no PDB parser in v1), and drives the debuggee through one contained backend interface (ptrace / Win32 Debug API).

**Tech Stack:** Z98 (compiler: `sf/src`; debugger: `examples/z98/z9dbg/`); existing `name_mangler`, `source_manager`, `std.os` (extended with debug bindings), `std_arena`, `std_file`; C compiler debug info read at debug time only.

**Spec:** `docs/superpowers/specs/2026-10-24-phase2-z98-debugger-design.md` (binding; §7 contracts, §14 settlements)

## Global Constraints

- Z98 subset; no new compiler features; **`LirInst` stays 32 B** — map state lives in parallel side tables + a parallel spill file (do NOT edit `lir_stream` record format / `expected_len`).
- Map machinery is **off by default**: no `-d` ⇒ no map files, no map allocation (gate at `lower.zig:574`), and default compilation output byte-identical to today (corpus frozen subset, goldens, 8 pins, markers, examples all stable).
- Compiler streams the map (≤ O(one function) RAM); debugger lazy-loads (bounded resident); both are gates.
- Debuggee builds use `-g -O0 -fno-omit-frame-pointer -m32`; Linux reader accepts DWARF 2/3/4 (CI pins `-gdwarf-2`); Win98 reader consumes **embedded COFF** (`MSVC /Z7` or OpenWatcom `-d2`) — **no PDB** in v1 (operator ruling (a)).
- Exact UX strings and breakpoint semantics are spec §7.4 (session `z9dbg <exe> [args…]`, `Z98 debugger has started...`, `Stopped at <path>:<line>`, `break: moved to line M`, `break: no executable code at line N`, snap rule, `step` = step-into, `quit` split Linux-detach/Win98-terminate, `dump variables` writes snapshot then resumes).
- Compiler banner `Z98 Compiler 2026 (map: on|off)` on stderr, suppressed by `--quiet`.
- Machine addresses are never invented: the map alone gives source ↔ generated source only; without C debug info the debugger reports `break: no debug info` and degrades to function-entry breakpoints from the symbol table.
- Gates per task (hybrid): after compiler changes run the standing battery (corpus frozen-1124 subset md5 `518eca1a9b5d3e1cc5a48abce214abd8` 0 movers, goldens 5/5, 8 pins old→new recorded, markers recorded, examples 26/26); after `std_os` changes run full `verify_stdlib.sh` + crosscheck; debugger tasks run `tier_dbg.sh` 2× deterministic + `-osw` build/import gate where applicable. Seed rotates at closeout (compiler source changed → new fixed point `F_new`, hop2==hop3). No push; `run.err` untouched; commits `feat(<file>): … (Phase2 P3-Mn)` / `example(z9dbg): …` / `test(tier): …` / `docs(std_lib|manuals): …` / `chore(seed): rotate (Phase2 P3)` / `docs(sdd): …`.
- STOP-present on any contract change or ambiguity (`I found the intention is X, but this is impossible given Y`).

## Review Focus

1. **`-d` off purity** — any leaked map write/marker/allocation in the default path breaks every golden; pin set must be byte-stable, and a no-`-d` build must create zero `*.z98dbg.*` files.
2. **Span fidelity** — DCE-skipped insts (no row), hoisted decls (row = owning statement), nest-inlining (row = outer call), async step/driver synthetic insts (approximate rows). Mutation tests must prove a wrong row is caught.
3. **Streaming memory** — self-compile with `-d` must not regress peak RSS measurably; side table spills per function and is released per function (`sandReset` discipline).
4. **Breakpoint snap** — whitespace-only reject vs comment/decl/`}` snap-forward; `int3` at every machine address of the snapped line; original bytes restored on `quit`; duplicate break on same line is a no-op with message.
5. **Address-layer separation** — z9dbg must fail cleanly when the debuggee lacks C debug info and must never present map rows as machine addresses.

---

### Task 1: M1 — `--debug`/`-d` map emission (compiler side)

**Files:**
- Create: `sf/src/debug_map.zig` (side-table entry type, spill writer/reader, three map-file writers)
- Modify: `sf/src/lower.zig` (capture `span_start` at `emitInst` `:574` into the side table when enabled; zero work when off)
- Modify: `sf/src/lir.zig` (side-table entry struct only — `LirInst` untouched)
- Modify: `sf/src/c89_emit.zig` (`BufferedWriter.line: u32` incremented on `\n` in Write/WriteByte/WriteIndent; `emitInst` hook `:8883-8895` emits line-map rows)
- Modify: `sf/src/main.zig` (`--debug`/`-d` parse, banner, map file open/close + header count patch, `--quiet` suppression)
- Test: `scripts/compiler/gate_debug_map.sh` (structural + determinism + no-`-d` purity gate)

**Interfaces:**
- Consumes: `Token/AstNode` spans via `_ctx_node_idx`; `sourceManagerGetLocation`; `nameManglerMangle` reverse cache.
- Produces (binding byte layout, little-endian; spec §7.1):
  - Header (all three files): magic 8 bytes (`Z98DBGsy` / `Z98DBGln` / `Z98DBGcn`) + `u32 version=1` + `u32 record_count` + `u32 file_total_len` (both patched at close).
  - `.syms` record: `u8 kind` (0=fn, 1=global), `u32 src_line`, `u16`-prefixed `src_name`, `u16`-prefixed `module_stem`, `u16`-prefixed `src_file`. Sorted by (src_file, src_line, name).
  - `.lines` group: `u16`-prefixed `src_file`, `u16`-prefixed `out_file`, `u32 run_count`, then runs `u32 src_line, u32 out_line_start, u32 out_count` (RLE: consecutive `out_line`s sharing `src_line`). Groups in emission order; runs sorted by `out_line_start`. `record_count` = total runs.
  - `.cnames` record: `u16`-prefixed `src_name`, `u16`-prefixed `mangled_name`. Sorted by `src_name`. Written whenever `-d` (C backend) even though consumers treat it as optional.
  - Map files land next to the primary output (`<stem>.z98dbg.*`, honoring `--output-dir`); `out_file` values are basenames.

- [ ] **Step 1:** Write `scripts/compiler/gate_debug_map.sh` first (RED): compile a committed `hello`-shaped probe with `-d`, assert the three files exist, `od`-check magics/version, assert symbol rows contain `main` with a plausible `src_line`, assert 3× runs are byte-identical, then compile without `-d` and assert zero map files and output `.c` set byte-identical to the no-`-d` output of the same binary before the change (captured baseline). Run — FAIL (no `debug_map.zig` / flag).
- [ ] **Step 2:** Implement `sf/src/debug_map.zig`: side-table record `(inst ordinal = (bb_idx, inst_idx), u32 span_start)`, per-function arrays keyed by `LirSlot.disk_offset`, spill/restore alongside (not inside) `lir_stream`, RLE on write. Implement the three writers exactly per the byte layout above.
- [ ] **Step 3:** Wire `lower.zig:574` capture behind the flag (span 0 = none; gate first, zero cost off) and `c89_emit.zig` `BufferedWriter.line` counter + `emitInst` hook; wire `main.zig` flag/banner/close-patch. Emitter DCE skips produce no rows; hoisted decls attribute to the owning statement; nest-inlined rows attribute to the outer call; async synthetic rows map to the suspending function's line (documented caveats, spec §7.3).
- [ ] **Step 4:** Run the gate — PASS. Then the standing battery (corpus frozen-1124 md5 `518eca1a…` 0 movers, goldens 5/5, 8 pins old→new recorded, markers recorded, examples 26/26 build+run) and the cost measurement: `hello`, `mud_server`, `lisp_interpreter_curr`, `z9torr`/`z9play` compiled with and without `-d`; record time + peak RSS deltas (expect ≈0) in the report.
- [ ] **Step 5:** Commit `feat(c89_emit): -d debug map emission (Phase2 P3-M1)` (one code commit; `debug_map.zig` rides with it) + `docs(sdd): P3-M1 report`.

### Task 2: M2 — map reader + debugger core

**Files:**
- Create: `examples/z98/z9dbg/main.zig` (session, command loop, prompt, exact UX strings)
- Create: `examples/z98/z9dbg/map_reader.zig` (lazy reader for the three files; forward + reverse line indices; basename/path-suffix `break` matching)
- Create: `examples/z98/z9dbg/dbg_core.zig` (breakpoint table + snap rule, source display `Stopped at <path>:<line>` + function + nearby lines, `dump variables` snapshot writer)
- Create: `examples/z98/z9dbg/backend.zig` (tiny vtable: launch, wait, read/write memory, get/set regs, single-step, continue, detach/terminate)
- Modify: `sf/src/std_os.zig` (debug bindings used later by backends; start with the shared shapes if needed by any core test)
- Test: `examples/z98/z9dbg/tests/` (map-reader fixtures + scripted-session harness skeleton)

**Interfaces:**
- Consumes: Task 1 map files; `std_arena`, `std_file`, `std_str`.
- Produces: `z9dbg` binary; map reader API (`open`, `symbolAt`, `lineAt`, `lineRowsAt`, `reverseRowAt`); snap rule exactly per spec §7.4; `dump variables [path]` default `z98-dump-<n>.txt` containing registers + call stack + globals (v1), then resume.

- [ ] **Step 1:** RED tests: map-reader fixtures against committed map files (parse header/counts, locate `main` rows, basename matching, corrupt/truncated → clean error); scripted-session skeleton asserting the exact strings (`Z98 debugger has started...`, `Stopped at <path>:<line>`, `break: moved to line M`, `break: no executable code at line N`, unknown-command message).
- [ ] **Step 2:** Implement `map_reader.zig` + `dbg_core.zig` + `main.zig` command loop (`break`, `continue`, `step`, `backtrace`, `dump variables`, `quit`; no `run` — `z9dbg <exe> [args…]` spawns and stops at the entry function's first mapped line). Snap rule: whitespace-only reject; comment/`}`/declaration/struct-field snap forward with warning; no target before next function ⇒ reject message. `step` = step-into to the next mapped Z98 line.
- [ ] **Step 3:** Run `examples/z98/z9dbg/tests/` map + string gates — PASS (3× deterministic where output is compared).
- [ ] **Step 4:** Commit `feat(z9dbg): map reader + debugger core (Phase2 P3-M2)` + `docs(sdd): P3-M2 report`.

### Task 3: M3 — Linux ptrace backend + session tests

**Files:**
- Create: `examples/z98/z9dbg/backend_linux.zig` (ptrace TRACEME/ATTACH, PEEK/POKETEXT, GETREGS/SETREGS, SINGLESTEP, CONT, waitpid; int3 plant/restore; never shells out to gdb)
- Create: `examples/z98/z9dbg/dwarf_lines.zig` (DWARF 2/3/4 `.debug_line` interpreter + ELF symtab reader, in Z98, inside z9dbg)
- Modify: `sf/src/std_os.zig` (ptrace/waitpid/etc. bindings)
- Test: `examples/z98/z9dbg/tests/tier_dbg.sh` (scripted sessions against the test set)

**Interfaces:**
- Consumes: `backend.zig` vtable; map reader; C debug info of the debuggee (`-gdwarf-2` CI pin).
- Produces: working `break`/`continue`/`step`/`backtrace`/`dump variables`/`quit` on Linux against `hello`, `mud_server`, `lisp_interpreter_curr` (final stress: `z9torr` or `z9play`); function-entry fallback when `.debug_line` absent (`break: no debug info` message, spec §7.6).

- [ ] **Step 1:** RED `tier_dbg.sh` cases: break at a known source line hits within 100 ms and prints the exact stop display; empty-line reject; declaration-line snap warning; `step` advances lines; `backtrace` lists function names; `dump variables` writes a snapshot file then resumes (debuggee continues to completion); `quit` restores original bytes and detaches (debuggee lives); no-debug-info build degrades to function-entry breakpoints with the exact message.
- [ ] **Step 2:** Implement `backend_linux.zig` + `std_os` bindings + `dwarf_lines.zig` (line program interpreter for DWARF 2/3/4; ELF symtab for function entries). Frame-pointer unwinding only (`-fno-omit-frame-pointer`); FPO documented as unreliable.
- [ ] **Step 3:** Run `tier_dbg.sh` 2× deterministic + full `verify_stdlib.sh` + crosscheck (std_os touched) — PASS. Record breakpoint latency and RSS on `hello`/`mud_server`/`lisp_interpreter_curr` + the chosen stress program.
- [ ] **Step 4:** Commit `feat(z9dbg): ptrace backend + DWARF lines (Phase2 P3-M3)` + `docs(sdd): P3-M3 report`.

### Task 4: M4 — Win98 backend + COFF reader + docs + closeout

**Files:**
- Create: `examples/z98/z9dbg/backend_win98.zig` (CreateProcess(DEBUG_ONLY_THIS_PROCESS), WaitForDebugEvent 50 ms timeout pump, ContinueDebugEvent, Get/SetThreadContext, Read/WriteProcessMemory, int3 + trap-flag single-step re-insert, terminate-on-quit)
- Create: `examples/z98/z9dbg/coff_lines.zig` (embedded COFF symbol + line-number records reader; **no PDB**)
- Modify: `sf/src/std_os.zig` (Win32 debug API bindings)
- Test: `examples/z98/z9dbg/tests/tier_dbg.sh` Win98 path (Wine where possible + `check_win9x_imports.sh 9x`); real hardware operator-owned
- Docs: `sf/docs/std_lib/` map + z9dbg page; truth-up `docs/sf/manuals/en/vol3-15-debugger-workflow.html`, `vol5-13-debugger.html`, `vol3-07-friction.html` (sidecar = opt-in compiler-dev tooling; no `#line`; default output unchanged); QUICK_REF `-d` recipe + debuggee flags; `examples/torrent_example_defects.md` if any new defects
- Rotate: `release/seed/` → **v120** (compiler source changed; new fixed point `F_new`, hop2==hop3, corpus/pins/goldens stable)

**Interfaces:**
- Consumes: Task 2 core + `backend.zig` vtable; embedded COFF from `/Z7` or Watcom `-d2` builds.
- Produces: Win98 parity of the M3 command set; Wine + import gates green; docs honest.

- [ ] **Step 1:** RED: Wine-driven session smoke (same assertions as M3 happy path where Wine allows) + `check_win9x_imports.sh 9x` on `z9dbg.exe` + a COFF-reader fixture against a committed `/Z7`-built object.
- [ ] **Step 2:** Implement `backend_win98.zig` + `std_os` Win32 debug bindings + `coff_lines.zig`; 50 ms `WaitForDebugEvent` timeout keeps the terminal pumping (Win98 has no `MsgWaitForMultipleObjects` for debug events).
- [ ] **Step 3:** Run gates: tier_dbg Linux 2× still green; Wine smoke + import gate; full standing battery (corpus/goldens/pins recorded/markers/examples/stdlib + crosscheck); seed rotate v119 → **v120** (archive + manifest; `lib/` std count unchanged at 47 — `std_os.zig` grows in place; `debug_map.zig` is compiler `gen/`, not `lib/`; record `F_new`, hop2==hop3); docs truth-up complete; `git diff --check` clean.
- [ ] **Step 4:** Commits `feat(z9dbg): Win98 backend + COFF lines (Phase2 P3-M4)` (or split code/docs), `docs(manuals): debug map + z9dbg truth-up`, `chore(seed): rotate (Phase2 P3)`, `docs(sdd): P4-M4 closeout report`.
