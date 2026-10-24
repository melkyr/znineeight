# Phase 2 Project 3 — Source-Level Z98 Debugger — Design

**Status:** approved for planning (operator, 2026-10-24).
**Blueprint:** `examples/projects_phase2.txt` §Project 3.
**Scope:** Project 3 only. Project 4 (Z98 Code Editor) is a separate later round.

---

## 1. Ground truth (verified in the tree)

- Source spans exist end-to-end to lowering: `token.zig:134-139` (`Token{span_start,span_len}`),
  `lexer.zig:269-276`, `ast.zig:123-126`; offset→line via `source_manager.zig:223-250`
  (permanent arena, survives to emission).
- The span is **lost at `lower.zig:574-579` `emitInst`** — `LirInst` has no span field and
  **32 B is a hard constraint**. The sanctioned fix is a parallel side table
  (`LirSideEntry` precedent, `lir.zig:227-247`), never `LirInst` growth.
- `main.zig:445` `sandReset(&ctx.alloc.module)` frees the AST before `phase_C89Emission`;
  spans must be captured **at lowering** into the side table.
- Mangled symbol names are already recoverable at emission (`name_mangler.zig:142-221`,
  reverse collision cache `:217`; `emitFunctionSignature` `c89_emit.zig:1887-1898` writes
  `/* orig */` comments) — zero pipeline change needed for the symbol map.
- Emitter line tracking is cheap: `BufferedWriter` (`c89_emit.zig:40-85`) gets a `line: u32`
  counter incremented on `\n` (~6 lines, zero alloc); one writer per output file
  (`main.zig:1611-1751`).
- The map key is already passed at the right hook: `emitInst(inst_bb, inst_ii)` in the body
  loop (`c89_emit.zig:8883-8895`).
- `dbg-mini.z98` (`docs/sf/manuals/src/vol3/`) is the out-of-process Win32 Debug-API
  precedent (CreateProcess/WaitForDebugEvent/GetThreadContext/ReadProcessMemory + int3).
- Manual honesty conflict: `docs/sf/manuals/en/vol3-15-debugger-workflow.html`,
  `vol5-13-debugger.html`, `vol3-07-friction.html` promise "no `.z98dbg` format" and
  "no `#line` directives". A sidecar map contradicts the letter of those pages; see §10.

---

## 2. Why

There is no way to map a running Z98 program back to Z98 source. Today the only tool is
`print`. The generated C is the debugging surface and the only symbol naming is the
`/* orig */` comment. A source-level map (Z98 line ↔ generated line ↔ symbol) plus a small
out-of-process debugger closes that gap for Win98 first and Linux for testing.

---

## 3. Goals

1. **G1 — Compiler-emitted map.** Opt-in `--debug`/`-d` flag emits a compact streamed
   sidecar map. Default (no flag) compilation output is **byte-identical** to today's
   output (corpus/pins/goldens stable); the compiler fixed point moves (compiler source
   changes) and the seed rotates at closeout, per the 1C-F precedent.
2. **G2 — Two-link chain.** Map gives Z98 ↔ generated-source (this project). Machine
   addresses come from the C compiler's own debug info (`gcc -g` DWARF / MSVC `/Z7` or
   Watcom `-d2` embedded COFF) or the post-link symbol table — **not** reinvented here.
3. **G3 — Out-of-process debugger** with a terminal UI, same command set on Win98 and
   Linux. Linux backend = `ptrace` + the map (never a gdb wrapper).
4. **G4 — Source-line breakpoints** with honest empty/declaration-line handling.
5. **G5 — `dump variables` v1** = registers + call stack + globals snapshot to a file,
   then resume. No typed locals in v1.
6. **G6 — Mangled C names are a separate optional file** so a future asm/other backend or
   an older debugger can use the source-level map alone.

## 4. Non-goals

- No typed/local-variable pretty printing in v1 (measure first).
- No expression watchpoints, no data breakpoints, no conditional breakpoints.
- No gdb/lldb wrapper on Linux; no GUI; no editor integration (Project 4 later).
- No `#line` directives in emitted C; no change to default emitted bytes.
- No DWARF/COFF *producer* — we consume the C compiler's debug info, never emit it.

## 5. Constraints

- Z98 subset; no new language features; no compiler-pipeline refactor beyond the map
  side-table + line counter + hooks already named in §1.
- `LirInst` stays 32 B. Map data lives in parallel side tables + spill files.
- Map machinery is **off by default**; zero cost and zero output difference without `-d`.
- Compiler must stream the map; never retain it in RAM (self-compile is 110–130 K insts).
- Debugger must lazy-load the map (per-file/per-function sections), bounded resident.
- Test set: `hello`, `mud_server`, `lisp_interpreter_curr`, then `z9torr` or `z9play`.
- Windows target: Win98 first (Win32 Debug API). Linux is the test platform (ptrace).
- RAM: compiler peak must not regress measurably with `-d`; debugger < 32 MB
  (`ulimit -v 32768`), 16 MB target.
- Performance: breakpoint hit → source display < 100 ms; sorted symbol arrays + lazy reads.

---

## 6. Architecture

```
                    z9dbg (out-of-process debugger, terminal UI)
                   /        \
         ptrace backend     Win32 Debug-API backend (dbg-mini lineage)
                   \        /
                    map reader (lazy, sectioned)
                        |
      <stem>.z98dbg.syms  <stem>.z98dbg.lines  [<stem>.z98dbg.cnames]
                        |
   compiler --debug/-d  ->  side-table capture at lowering
                         ->  line counter + map writer at emission (streamed)
```

- **Compiler side** (sf/src): capture spans at `emitInst` (lowering) into a per-function
  side table; spill per `LirSlot.disk_offset`; at emission resolve spans → lines and
  stream sorted map rows while the output files are written.
- **Map side**: three files (below). Text/derived names are backend-neutral except
  `.cnames` which is optional and C-specific.
- **Debugger side**: a standalone Z98 program (`examples/z98/z9dbg/`), shared upper layer
  (command loop, map reader, source display, breakpoint table) + two thin backends.

---

## 7. Contracts (binding)

### 7.1 Compiler flag + banners

- `--debug` and `-d` are the same flag. With it, the compiler writes the map files next to
  the primary output (`<output-stem>.z98dbg.*`). Without it: no map files, emitted bytes
  identical, no map allocation at all (gate at `lower.zig:574`).
- Compiler startup banner (all runs, one line to **stderr**, suppressed by `--quiet`):
  `Z98 Compiler 2026 (map: on|off)` (no runtime seed number — settlement §14).
- Map format is machine-readable binary, compact: fixed 8-byte header per file
  (`Z98DBGxx`), u32 counts, length-prefixed strings, integer little-endian; `.lines`
  grouped per `out_file` in emission order with RLE on consecutive rows (§7.2/§14).
  Exact byte layout is specified in the plan; the contract is: streamed (≤ O(one function)
  RAM in the compiler), stable ordering, versioned header.

### 7.2 Map files

| File | Content |
|---|---|
| `<stem>.z98dbg.syms` | source-level symbols: `kind` (fn/global), `src_name`, `module_stem`, `src_file`, `src_line` |
| `<stem>.z98dbg.lines` | line map rows: `src_file, src_line, out_file, out_line` — grouped per `out_file`, emission order across functions, RLE merges consecutive rows sharing `src_line` with adjacent `out_line`s |
| `<stem>.z98dbg.cnames` | C-backend names: `src_name → mangled_c_name` (and reverse); **emitted whenever `-d`**; consumer-side optional only |

- The source-level files never mention C. `.cnames` is the only C-aware file; a future asm
  backend ships its own `.anames`-style companion and keeps `.syms`/`.lines` unchanged.
- Debugger works without `.cnames` (shows Z98 names); with it, `backtrace`/`dump variables`
  can also print the generated symbol for cross-reading with gdb on Win98.

### 7.3 Line-map fidelity

- Statement granularity: every inst-emission site maps to the nearest enclosing Z98
  statement line. Known approximations (documented, not bugs): emitter DCE skips (no row),
  hoisted declarations (row = owning statement), nest-inlining (row = outer call), async
  step/driver synthesized functions (rows map to the suspending function's line).
- One Z98 line may map to 0..N output lines; one output line maps to exactly one Z98 line.

### 7.4 Debugger UX (exact strings)

- Session: `z9dbg <exe> [args…]` spawns the debuggee and stops at the first mapped source
  line of the entry function. `break` is valid only while stopped. No `run` command in v1.
- Startup: `Z98 debugger has started...`
- Commands (minimal, terminal, identical on both platforms):
  `break <file>:<line>`, `continue`, `step`, `backtrace`, `dump variables`, `quit`.
- Stop display: `Stopped at <path>:<line>` then the function name and nearby source lines.
- `step` = step-into: advance to the next mapped Z98 source line, stepping through unmapped
  C (libc) until back on a mapped line. No `next` in v1.
- Breakpoint semantics (source-line based; `<file>` matches map `src_file` by basename or
  path suffix):
  - Whitespace-only source line → `break: no executable code at line N` and **do nothing**.
  - Any other line lacking an executable address (comment-only, `}`, declaration, struct
    field) → snap to the nearest executable line at-or-after; if none before the next
    function, the "no executable code" message and no breakpoint. Snap prints
    `break: moved to line M`.
  - The snapped line is the breakpoint; `break` reports the line it actually used; `int3`
    is planted at every machine address mapped to that line.
- `dump variables` writes a snapshot file (registers + call stack + globals) then resumes.
  File name default `z98-dump-<n>.txt`, overridable as `dump variables <path>`.
- `quit` restores original breakpoint bytes first; then Linux `PTRACE_DETACH` (debuggee
  lives) / Win98 terminates the spawned debuggee.

### 7.5 Backends

- **Linux:** `ptrace` (PTRACE_TRACEME/ATTACH, PEEK/POKETEXT, GETREGS/SETREGS, SINGLESTEP,
  CONT). Never shells out to gdb. Same upper layer as Win98.
- **Win98:** Win32 Debug API (`CreateProcess(DEBUG_ONLY_THIS_PROCESS)`,
  `WaitForDebugEvent`, `ContinueDebugEvent`, `GetThreadContext`, `SetThreadContext`,
  `ReadProcessMemory`, `WriteProcessMemory`), int3 breakpoints with saved original byte and
  trap-flag single-step re-insert. Debug loop uses a 50 ms `WaitForDebugEvent` timeout so
  the terminal UI keeps pumping (Win98 has no `MsgWaitForMultipleObjects` for debug events).
- Backend selection is contained (one module per backend + a tiny vtable); switching
  backends must not touch the upper layer.

### 7.6 Machine addresses (out of map scope)

- Function-entry breakpoints: resolved from the post-link symbol table (ELF/COFF) when
  present.
- Source-line breakpoints: resolved via the C compiler's line table read **at debug time**
  by the debugger's own readers (in-z9dbg, Z98):
  - **Linux:** DWARF line program (input `-gdwarf-2`, accepts DWARF 2/3/4; DWARF 5 out of v1).
  - **Win98:** **embedded COFF line/symbol records** — `MSVC /Z7` or OpenWatcom `-d2`.
    No PDB parser in v1 (`/Zi` CodeView-in-PDB is out; blueprint COFF-first path).
  The map alone cannot produce machine addresses; docs and UI must say so plainly.

---

## 8. Testing

1. **Map correctness:** for `hello`, `mud_server`, `lisp_interpreter_curr`, `z9torr` or
   `z9play` — every emitted map row resolves to a real Z98 line and a real output line;
   determinism 3× (byte-identical maps); `--debug` off ⇒ output bytes identical (pin set
   unchanged); flag on ⇒ program semantics unchanged (tiers still green).
2. **Compiler cost:** `-d` overhead measured on the test set (time + peak RSS) and recorded;
   expect near-zero (side table ≈ 4 B/inst worst, streamed out).
3. **Debugger:** scripted sessions on the test set — break/continue/step/backtrace/dump
   variables/quit; breakpoint latency < 100 ms; snapshot file contents sane; empty-line and
   declaration-line breakpoint cases per §7.4.
4. **Linux ptrace backend** is the default CI path; **Win98 backend** verified via Wine
   where possible + `check_win9x_imports.sh` gate; real Win98 hardware remains
   operator-owned.

## 9. Risks

- **R1 Mapping fidelity** — DCE/hoisted/nest/async rows are approximations; mitigate with
  statement granularity + documented caveats + fixture pins on tricky shapes.
- **R2 Manual honesty** — the manuals currently promise no `.z98dbg` format and no
  `#line`. This project keeps `#line` out but **does** grow a sidecar. §10 governs the doc
  correction.
- **R3 32 B LirInst** — never grows; all map state is side-table + spill (Review Focus).
- **R4 Memory** — compiler map must stream; debugger map lazy-loads. Both are gates.
- **R5 Machine-address layer** — depends on C compiler debug info; without `-g`/`/Z7`,
  source-line breakpoints degrade to function-entry breakpoints with a clear message.
- **R6 Backend drift** — keep both backends behind one interface; the command set is the
  contract, not the backend.

---

## 10. Docs / honesty plan

- `vol3-15-debugger-workflow.html`, `vol5-13-debugger.html`, `vol3-07-friction.html` must be
  truthed up to describe the sidecar map as **compiler-dev tooling** (opt-in, off by
  default, no `#line`, default output unchanged) rather than "will not grow one soon".
- New doc page for the map format + debugger usage; QUICK_REF gets the `-d` recipe.
- The "debugging surface is the generated C" story stays true for default builds.

## 11. Milestones (one plan, sequential)

- **M1** — `--debug`/`-d` map emission (side-table capture, line counter, streamed writer,
  `.syms`/`.lines`/`.cnames`, banners, determinism + zero-cost-off gates).
- **M2** — map reader + shared debugger core (command loop, source display, breakpoint
  table, snap rule, `dump variables` v1).
- **M3** — Linux ptrace backend + scripted session tests on the test set.
- **M4** — Win98 Win32 Debug-API backend + Wine/import gates + docs truth-up + closeout.

## 12. What's left to the builder

Exact map byte layout is **pinned in the implementation plan (M1 task)**; exact
side-table/spill struct shapes, the debugger's module split, snapshot file layout, and the
scripted test harness details remain builder choices within §7 rules.
Everything else here is binding.

---

## 13. Decisions log (operator)

1. Map is the core deliverable; machine addresses come from C debug info, never invented.
2. Format: machine-readable, compact, streamed/delta — "as compacted as possible".
3. Flag: `--debug`/`-d`, performance evaluated on the test set.
4. Test set: `hello`, `mud_server`, `lisp_interpreter_curr`, then `z9torr` or `z9play`.
5. Compiler banner `Z98 Compiler 2026…`; debugger banner `Z98 debugger has started...`;
   stop display `Stopped at <path>:<line>` + function + nearby source.
6. Commands: `break`, `continue`, `step`, `backtrace`, `dump variables`, `quit`.
7. Linux = ptrace + map, never gdb wrapper; `-d` also outputs mangled C names for
   gdb-assisted inspection on Win98.
8. Mangled C names live in a **separate optional file** so backends/old debuggers are safe.
9. `dump variables` v1 = registers/call stack/globals only; measure before evolving.
10. Breakpoints are source-line based; empty lines rejected; declaration lines snap forward
    with `break: moved to line N` warning (warning over silence).
11. Win98 machine-address format = **embedded COFF** (`MSVC /Z7` or Watcom `-d2`) — no PDB
    parser in v1; COFF reader ships in M4, DWARF reader (Linux) ships in M3.

## 14. Builder-check settlements (2026-10-24)

Recorded as decided (builder-check piles 1–2; operator accepted the calls):

- **Unwinding** = frame-pointer builds only (`-fno-omit-frame-pointer`); FPO builds get
  unreliable backtraces, documented.
- **`std.os` debug bindings are in scope** (ptrace/waitpid on Linux, Win32 debug API on
  Win98) — new std work the debugger needs.
- **Debug-info readers live inside z9dbg, written in Z98** — DWARF line-program interpreter
  + ELF symtab (Linux), COFF line records + symtab (Win98). No helper binaries.
- **`.cnames` is emitted whenever `-d`** — "optional" is consumer-side only.
- **`-d` is unclaimed** in the CLI short-flag table (`main.zig`); no collision.
- **`dump variables` auto-resumes** after writing the snapshot file (deliberate).
- **Debuggee arch = i386** — register dump = i386 GPRs; both backends use i386 context.
- **`.lines` layout** — grouped per `out_file`, emission order across functions; RLE merges
  consecutive rows sharing `src_line` with adjacent `out_line`s; reader keeps forward +
  reverse indices.
- **Breakpoint line classification** — whitespace-only line = reject
  (`break: no executable code at line N`, no-op); any other line lacking an executable
  address (comment-only, `}`, declaration, struct field) = snap forward with
  `break: moved to line M`; no target before the next function = reject message.
- **`step`** = step-into; advance to the next mapped Z98 source line, stepping through
  unmapped C (libc) until back on a mapped line. No `next` in v1.
- **Session model** — `z9dbg <exe> [args…]` spawns the debuggee and stops at the first
  mapped source line of the entry function; `break` valid only while stopped; no `run`
  command in the v1 command set.
- **`quit` split** — Linux: restore original bytes + `PTRACE_DETACH` (debuggee lives);
  Win98: restore bytes + terminate the spawned debuggee.
- **Breakpoint plants `int3` at every machine address** mapped to the snapped line (one
  Z98 line → 0..N output lines).
- **Debuggee build flags** — `-g -O0 -fno-omit-frame-pointer -m32`; the Linux reader accepts
  DWARF 2/3/4 line tables (CI pins `-gdwarf-2`); DWARF 5 is out of v1. Goes in QUICK_REF.
- **`break <file>:<line>` matching** — basename or path-suffix match against map `src_file`.
- **Map file location** — next to the primary output (root-module C stem), honoring
  `--output-dir`; `out_file` columns hold basenames.
- **Banners to stderr on all runs** (compiler banner suppressed by `--quiet`); golden/pin
  tests compare stdout/files only. Compiler banner string is
  `Z98 Compiler 2026 (map: on|off)` — no runtime seed number (a baked seed constant would
  have to be choreographed through every rotation; documented as a settlement call).
