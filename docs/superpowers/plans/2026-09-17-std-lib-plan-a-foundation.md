# Z98 std-lib Plan A — L0-L2 foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the L0-L2 std-lib foundation from the blueprint — `std_bits`, `std_os`, `std_time`, the `std_debug` extension, `std_buf`, and the `std_str` extension — with fixtures, the R7b usage programs under `stdlib_test/`, and the layering/dependency gate green.

**Architecture:** One plan, six module tasks plus a usage-program task, ordered by the blueprint's construction order (L0 → L1 → L2). Each module is authored in `sf/src/std_<name>.zig` with the blueprint's exact signatures, gets `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixtures, and is validated by the six gates; the band's usage programs (R7b) compose the modules and are gated the same way. Task 4 is followed by the optional-fn-pointer C-emission defect I/F pair (Task 4b-I investigate/pin, Task 4b-F fix, Task 4c revert `std_debug.setTrapHandler` to the blueprint's `?fn` signature) — operator ruling m1243. Task 6 is followed by the `-ffast` undefined slice-array emission defect I/F pair (Task 6b-I investigate/pin, Task 6b-F fix) — operator ruling m1277. **This plan runs after Task 0 (separation audit); its successor is Plan B (L3 + L6).**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan A), §5, §6; module signatures in `sf/docs/std_lib_extension.txt` §3 (L0-L2).

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-task0-separation-plan.md`](2026-09-17-std-lib-task0-separation-plan.md) (separation audit). NEXT plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6).

## Global Constraints

- **Precondition:** Task 0 complete (the compiler↔std separation audit; the dead std-importing files deleted; the blueprint §6 claim corrected).
- **Baseline (re-verify at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, and the corpus `EXPECTED_FAIL.md` header at dispatch. The compiler's import graph reaches no std module, so adding std modules MUST NOT move the fixed point. **Exception (operator rulings 2026-09-17 / m1243 / m1277): the authorized compiler-graph changes that move the fixed point are the per-OS prelude work (Tasks 2-3: `std_os_prelude.h`/`std_time_prelude.h`, the `net_prelude.h` analog), Task 4's `std_debug` trap hook, the optional-fn-pointer C-emission defect fix (Task 4b-F; Task 4c is std-only), and the `-ffast` undefined slice-array emission defect fix (Task 6b-F). Re-baseline at Task 2 Step 6, Task 3 Step 6, Task 4 Step 6, Task 4b-F Step 5, Task 4c Step 4, and Task 6b-F Step 5. Tasks 1,5,6,7,8 MUST leave it unmoved — if it moves, STOP (a std module or an unauthorized PAL edit leaked into the compiler graph). Tasks 4b-I and 6b-I are investigation-only (no `sf/src` change) and MUST leave it unmoved; Task 5's `backtrace` is std-only and MUST leave it unmoved.**
- **PAL boundary (operator ruling 2026-09-17).** The std lib MUST NOT wrap or edit the compiler PAL for OS primitives. OS specifics live in std-side PAL modules (`sf/src/std_os_pal.zig`, `sf/src/std_time_pal.zig`) using the `std_net.zig` `@cInclude`+`extern`+`@isWindows()` pattern, with per-OS C prototypes supplied by the authorized prelude headers. The only authorized compiler edits in this plan are the prelude work (Tasks 2-3), the Task 4 trap hook, the optional-fn-pointer emission fix (Task 4b-F; operator ruling m1243 — Task 4c is std-only), and the `-ffast` undefined slice-array emission fix (Task 6b-F; operator ruling m1277) (see each task's Files list). The compiler's cost is what it imports; the library's cost is what emits.
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; never invoke `zig0`.
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Layering (R3):** a module may import only lower layers — never siblings, never higher. The dependency-graph check (one pass) is part of every module task's gate. The authoritative `std.zig` re-export set is the 12 names `io/arena/str/mem/math/debug/net/async/bits/os/time/buf` (grew from 8; operator ruling m1323). **Two documented R3 exceptions (operator rulings m1243 / m1323):** Exception 1 — `std_debug.backtrace(ctx, out: *std.buf.Buf)` (blueprint §3 L1) takes a `std_buf.Buf`, so `std_debug` (L1) imports `std_buf` (L2) for this one function; it is cycle-free (`std_buf` imports only `std_arena`) and sanctioned because the blueprint fixes the public API name/signature. Exception 2 — `std_debug` (L1) also imports the core `std_io` module (no imports of its own) for `log`/`writeCoreDump`; cycle-free and operator-authorized. No other L1→L2 import is permitted.
- **Arena (R1):** allocating functions take `arena: *std.arena.Arena` first; `OutOfMemory` in the error set.
- **Errors (R2):** one error set per module; no `catch unreachable`.
- **Determinism (R6):** no output may depend on addresses, the wall clock, or the PID unless the contract says so.
- **Fixtures (R7):** every public function gets a `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixture.
- **Usage programs (R7b):** each layer band ships usage programs under `stdlib_test/`; every module in this band is complete only when its usage program is GREEN.
- **Seed `lib/` copy lists:** each task that adds a module extends both `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` `lib/` copy lists in the same commit (so that task's own GREEN is reproducible). The closeout verifies the lists are complete. `scripts/self_compile/build_zig1_5.sh:12` keeps its legacy 5-module list on the retired zig0 path — a known divergence; do not silently change it.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Declare every residual gap** (report + docs + a tracked note).

---

## File Structure

**Create (modules):**
- `sf/src/std_bits.zig` — L0, pure bit manipulation.
- `sf/src/std_os.zig` — L1, process info; **imports the std-side PAL `sf/src/std_os_pal.zig`** (OS externs; never `sf/src/pal.zig`).
- `sf/src/std_os_pal.zig` — L1 private impl unit, `@cInclude`+`extern`+`@isWindows()` (the `std_net.zig` pattern).
- `sf/src/std_time.zig` — L1, monotonic + wall-clock; **imports the std-side PAL `sf/src/std_time_pal.zig`**.
- `sf/src/std_time_pal.zig` — L1 private impl unit, `@cInclude`+`extern`+`@isWindows()`.
- `sf/src/std_buf.zig` — L2, growable byte buffer over an arena.

**Modify (modules):**
- `sf/src/std_debug.zig` — add `TrapContext` + `setTrapHandler`/`defaultTrapHandler`/`writeCoreDump` (Task 4; `setTrapHandler` reverted to the blueprint's `?fn(*TrapContext) void` in Task 4c) and `backtrace` (Task 5, with `std_buf`).
- `sf/src/std_str.zig` — add `split`/`splitLines`/`join`/`trim*`/`indexOf`/`lastIndexOf`/`eqIgnoreCase`/`replace`/`count`/`repeat`.
- `sf/src/std.zig` — add re-exports for `bits`/`os`/`time`/`buf` (per the blueprint §6 distribution; `debug`/`str` already re-exported). The authoritative set after Plan A is the 12 names `io/arena/str/mem/math/debug/net/async/bits/os/time/buf` (operator ruling m1323).

**Create (fixtures):** one dir per public function under `repro/mi_matrix/`:
- `stdlib_bits_<name>_xmod/` (table-driven; the blueprint allows one fixture for the whole module — use `stdlib_bits_table_xmod`).
- `stdlib_os_argc_xmod/`, `stdlib_os_env_xmod/`, `stdlib_os_cwd_xmod/`.
- `stdlib_time_monotonic_xmod/`, `stdlib_time_sleep_xmod/`.
- `stdlib_debug_trap_xmod/`, `stdlib_debug_backtrace_xmod/` (the latter in Task 5, with `std_buf`).
- `opt_fnptr_extern_xmod/`, `opt_void_extern_xmod/` (Task 4b-I/4b-F; optional-fn-pointer C-emission defect probes).
- `undefined_slice_array_xmod/` (the `-ffast`-only failure) and `known_excluded/undefined_slice_array_safe_xmod/` (the off-corpus `-fsafe`/default control) (Task 6b-I/6b-F; `-ffast` undefined slice-array emission defect probes).
- `stdlib_buf_growth_xmod/`, `stdlib_buf_endian_xmod/`, `stdlib_buf_clear_xmod/`.
- one `stdlib_str_<name>_xmod/` per new `std_str` function.

**Create (usage programs, R7b):**
- `stdlib_test/bits_buf_str_usage/main.zig` — composes `std_bits` + `std_buf` + `std_str`.
- `stdlib_test/os_time_usage/main.zig` — composes `std_os` + `std_time` + `std_debug`.

**Modify (harness):**
- `scripts/corpus/list_corpus_dirs.sh` — container rule (D) for `stdlib_test/`.

**Modify (closeout):**
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump the header once at Plan A closeout.
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` — the `lib/` copy list is extended per-task (one module per task commit); the closeout verifies it is complete (same touchpoints as the existing 9).

**Reference (read-only):** `sf/docs/std_lib_extension.txt` §3 (L0-L2), `docs/sf/QUICK_REF.md`, `docs/sf/AGENTS.md`.

---

### Task 1: Baseline + `std_bits` (L0)

**Files:**
- Create: `sf/src/std_bits.zig`
- Create: `repro/mi_matrix/stdlib_bits_table_xmod/main.zig`
- Modify: `sf/src/std.zig` (add `pub const bits = @import("std_bits.zig");`)
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_bits.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: nothing.
- Produces: `std_bits` (`popcount32/64`, `clz32/64`, `ctz32/64`, `rotl32`, `rotr32`, `bitrev32`, `mask`, `extract`, `insert`, `isPow2`, `nextPow2`) — signatures in blueprint §3 L0.

- [ ] **Step 1: Record the baseline**

```bash
cd /workspace/znineeight
git rev-parse HEAD; md5sum release/seed/zig1-seed.tgz; head -1 repro/mi_matrix/EXPECTED_FAIL.md
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/planA_build
md5sum /tmp/planA_build/zig1_5_clean
```

Expected: a fresh fixed point md5. Record it — every later task must leave it UNMOVED.

- [ ] **Step 2: Write the failing fixture**

Create `repro/mi_matrix/stdlib_bits_table_xmod/main.zig`: a table-driven test calling every `std_bits` function with the blueprint's documented boundary cases (`clz32(0) == 32`, `ctz32(0) == 32`, `nextPow2(0) == 1`, `rotl32(x, 32) == x`, `mask(0) == 0`, `mask(32) == 0xFFFFFFFF`) and `@panic`ing on any mismatch; print `bits ok` at the end.

- [ ] **Step 3: Run the fixture — RED**

```bash
cd /workspace/znineeight
/tmp/planA_build/zig1_5_clean -o /tmp/planA_bits repro/mi_matrix/stdlib_bits_table_xmod/main.zig
```

Expected: FAIL — `error[3048]` / unresolved import (the module does not exist yet).

- [ ] **Step 4: Implement `std_bits.zig`**

Write `sf/src/std_bits.zig` with the blueprint's exact signatures and the documented traps (`extract`/`insert` trap on out-of-range offsets via `unreachable`; all others total). No imports (L0).

- [ ] **Step 5: Extend both `lib/` copy lists + re-export + run the fixture — GREEN**

Extend the `lib/` copy lists in `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` with `std_bits.zig` (convention: every Plan A task that adds a module extends both lists in the same commit, so this task's GREEN is reproducible). Add `pub const bits = @import("std_bits.zig");` to `sf/src/std.zig`, then rebuild the compiler so its `lib/` carries the module and run the fixture:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/planA_build
/tmp/planA_build/zig1_5_clean -o /tmp/planA_bits repro/mi_matrix/stdlib_bits_table_xmod/main.zig
cd /tmp/planA_bits && sh build_target.sh linux stdlib_bits_table && timeout 120 ./stdlib_bits_table; echo rc=$?
```

Expected: `bits ok`, rc=0.

- [ ] **Step 6: Run the safety + determinism gates**

```bash
cd /workspace/znineeight
for m in -fsafe -ffast; do
  /tmp/planA_build/zig1_5_clean $m -o /tmp/planA_bits_$m repro/mi_matrix/stdlib_bits_table_xmod/main.zig
done
```

Expected: both modes emit; run each 3× and confirm identical stdout. Record the md5s.

- [ ] **Step 7: Verify the fixed point is UNMOVED + commit**

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/planA_build2
md5sum /tmp/planA_build2/zig1_5_clean   # MUST equal Step 1
git add sf/src/std_bits.zig sf/src/std.zig repro/mi_matrix/stdlib_bits_table_xmod \
  scripts/seed/build_from_seed.sh scripts/seed/archive_seed.sh
git commit -m "feat(std): add std_bits (L0) + fixture + lib/ copy list (Plan A Task 1)"
```

---

### Task 2: `std_os` (L1)

**Files:**
- Create: `sf/src/std_os.zig`
- Create: `sf/src/std_os_pal.zig` (std-side OS externs — the `std_net.zig` pattern)
- Create: `repro/mi_matrix/stdlib_os_argc_xmod/`, `stdlib_os_env_xmod/`, `stdlib_os_cwd_xmod/`
- Create (authorized compiler change): `sf/src/include/std_os_prelude.h` (per-OS C prototypes; the `net_prelude.h` analog)
- Modify (authorized compiler change): `sf/src/emit_support.zig` (emit the prelude), `sf/src/c89_emit.zig` (conditional emission), `scripts/check_emit_support.sh` (prelude entry)
- Modify: `sf/src/std.zig` (re-export `os`)
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_os.zig` + `std_os_pal.zig` to both `lib/` copy lists — same commit)
- **Forbidden:** any edit to `sf/src/pal.zig` / `sf/src/include/zig_pal.c` (compiler PAL). A missing primitive is added to `std_os_pal.zig`.

**Interfaces:**
- Consumes: `std_bits` (optional).
- Produces: `std_os` (`argc`, `argv`, `exit`, `env`, `cwd`) — signatures in blueprint §3 L1.

- [ ] **Step 1: Write the failing fixtures** (`argc`/`argv` round-trip; env unset/set; cwd non-empty).
- [ ] **Step 2: Run them — RED** (`error[3048]`).
- [ ] **Step 3: Implement `std_os.zig`** with the blueprint signatures; `env` via `getenv` (`<stdlib.h>`); `cwd` allocates from the arena and fills via `GetCurrentDirectoryA`/`getcwd` (prototypes from the authorized `std_os_prelude.h`); `exit` via `@exit`. **`argc`/`argv` (operator ruling 2026-09-17): expose `std_os.initArgs(argc: i32, argv: [*]*const u8) void` mirroring `sf/src/pal.zig:184-195`, which the user calls from their `main`; `argc()`/`argv(i)` read the saved values. The compiler is untouched for this — no capture hook in the emitted `main` wrapper.**
- [ ] **Step 4: Re-export + run — GREEN** (all three fixtures rc=0, documented stdout).
- [ ] **Step 5: Safety/determinism gates** (`-fsafe`/`-ffast` parity, 3× md5).
- [ ] **Step 6: Fixed point MOVED (authorized prelude work) + commit** (`feat(std): add std_os (L1) + fixtures + lib/ copy list (Plan A Task 2)`). Adding `std_os_prelude.h` + its emitter wiring is part of the authorized prelude work; rebuild via the seed model and record the new fixed point md5. Stage `sf/src/std_os.zig`, `sf/src/std_os_pal.zig`, `sf/src/std.zig`, the prelude/emitter files, the fixtures, and both seed scripts.

---

### Task 3: `std_time` (L1)

**Files:**
- Create: `sf/src/std_time.zig`
- Create: `sf/src/std_time_pal.zig` (std-side OS externs — the `std_net.zig` pattern)
- Create: `repro/mi_matrix/stdlib_time_monotonic_xmod/`, `stdlib_time_sleep_xmod/`
- Create (authorized compiler change): `sf/src/include/std_time_prelude.h` (per-OS C prototypes; the `net_prelude.h` analog)
- Modify (authorized compiler change): `sf/src/emit_support.zig` (emit the prelude), `sf/src/c89_emit.zig` (conditional emission), `scripts/check_emit_support.sh` (prelude entry)
- Modify: `sf/src/std.zig` (re-export `time`)
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_time.zig` + `std_time_pal.zig` to both `lib/` copy lists — same commit)
- **Forbidden:** any edit to `sf/src/pal.zig` / `sf/src/include/zig_pal.c`.

**Interfaces:**
- Consumes: `std_os`.
- Produces: `std_time` (`ticksMs`, `highRes`, `highResFreq`, `wallClockUnix`, `sleepMs`) — blueprint §3 L1.

- [ ] **Step 1: Write the failing fixtures** (monotonicity over 100 calls; sleep-with-tolerance).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_time.zig`.** `ticksMs`/`highRes`/`highResFreq`/`wallClockUnix` are `@isWindows()`-guarded wrappers over `std_time_pal.zig` externs (`GetTickCount`/`QueryPerformanceCounter`/`QueryPerformanceFrequency`; `gettimeofday`/`time`), whose prototypes come from the authorized `std_time_prelude.h` (option B). `sleepMs` calls the `@sleepMs` builtin directly (do **not** import `std_io`; R3). Note R6: `ticksMs` wraps; `highRes` falls back to `ticksMs * 1000` on hardware without a high-res timer (documented, deterministic). The monotonicity fixture must be robust to the fallback.
- [ ] **Step 4: Re-export + GREEN.**
- [ ] **Step 5: Safety/determinism gates.**
- [ ] **Step 6: Fixed point MOVED (authorized prelude work) + commit.** Adding `std_time_prelude.h` + its emitter wiring is the prelude half of the authorized compiler-graph changes; rebuild via the seed model and record the new fixed point md5. Stage `sf/src/std_time.zig`, `sf/src/std_time_pal.zig`, `sf/src/std.zig`, the prelude/emitter files, the fixtures, and both seed scripts.

---

### Task 4: `std_debug` extension (L1)

**Files:**
- Modify: `sf/src/std_debug.zig` (add `TrapContext`, `setTrapHandler`, `defaultTrapHandler`, `writeCoreDump`; declare `extern "c" fn pal_set_trap_handler(...)`). **`TrapContext` field order MUST match `sf/src/include/zig_pal.c` exactly: `eip, esp, ebp, eflags, eax, ebx, ecx, edx, esi, edi` (10 × u32).** `backtrace` is **not** a Task 4 deliverable — it is deferred to Task 5 (forward-pointer below); `setTrapHandler`'s non-optional `*void` fallback is reverted to the blueprint's `?fn(*TrapContext) void` in Task 4c.
- Create: `repro/mi_matrix/stdlib_debug_trap_xmod/`
- Modify (authorized compiler change): `sf/src/include/zig_pal.c` (canonical), `sf/src/emit_support.zig` (`emitZigPalCSupport`), `sf/src/c89_emit.zig` (`emitZigPalC` dead mirror) — add `g_trap_handler`/`TrapContext`/`pal_set_trap_handler` and make `pal_trap()` call the handler. The canonical and emitted copies MUST stay byte-identical (`check_emit_support.sh`). **No other compiler file changes.**

**Interfaces:**
- Consumes: `std_os` (optional).
- Produces: the blueprint §3 L1 `std_debug` surface **except `backtrace`**.
- **Forward-pointer (`backtrace` → Task 5).** `backtrace` consumes `std_buf` (L2), which Task 4 does not create; it lands in Task 5 with `std_buf`. The deferral is because `std_debug` (L1) must not import L2 under R3 — so either `backtrace` moves to where `std_buf` lives or the layering is handled explicitly. **Decision:** keep the blueprint's public API `std_debug.backtrace` (its name/signature are fixed by blueprint §3 L1 and consumed by Plans B/C and the debugger) and handle the layering as the single documented R3 exception (`std_debug` imports `std_buf` for this one function; cycle-free — see Global Constraints). Moving it to `std_buf` would silently break the blueprint contract.

- [ ] **Step 1: Boundary resolved by operator ruling (2026-09-17).** The trap hook IS an authorized compiler-graph change (see Files above); implement it. Do not STOP. Any compiler-graph change beyond the **four** authorized ones (the Tasks 2-3 per-OS preludes, this trap hook, Task 4b-F's optional-fn-pointer fix per ruling m1243, and Task 6b-F's `-ffast` undefined slice-array fix per ruling m1277) requires a fresh operator ruling. The trap hook's shape — `int3`/SIGTRAP where available with the non-GCC/non-x86 `pal_abort()` fallback — is the operator-ruled restore (m1325).
- [ ] **Step 2: Write the failing fixture** (install a handler, trigger a trap, verify `ctx.eip != 0`).
- [ ] **Step 3: RED.**
- [ ] **Step 4: Implement the extension.**
- [ ] **Step 5: GREEN + safety/determinism gates.**
- [ ] **Step 6: Fixed point MOVED ONCE (authorized) + commit.** Rebuild via the seed model, record the new fixed point md5 as the Plan A baseline for Tasks 4b-7 and for Plans B/C. If it did **not** move, the hook is not actually compiled into `zig_pal` — STOP and diagnose.

---

### Task 4b-I: Optional-fn-pointer C emission — investigate + pin (I)

**Files:**
- Create: `repro/mi_matrix/opt_fnptr_extern_xmod/main.zig`, `repro/mi_matrix/opt_void_extern_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (classify/declare the two new dirs)
- **No `sf/src` change.** No STOP unless the premise below is disproved.

**Interfaces:**
- Consumes: the landed `std_debug.setTrapHandler` fallback (Task 4) and the Task 4 reviewer's probe.
- Produces: a pinned statement of exactly what the compiler emits for an optional function-pointer parameter and an optional `*void` in an `extern "c"` declaration, plus the fix surface for Task 4b-F.

**Premise (operator ruling m1243).** The landed `setTrapHandler` diverged from the blueprint's `setTrapHandler(h: ?fn(*TrapContext) void)` because `?fn`/`?*void` was believed not to lower. The reviewer's probe shows it **does** lower but emits `-Wincompatible-pointer-types` warnings — valid Zig compiling to incorrect C is a **compiler bug**. Do not revert the signature before this task pins the emission.

- [ ] **Step 1: Write the two probe fixtures**
  - `opt_fnptr_extern_xmod/main.zig`: `extern "c" fn take_fn(h: ?fn(i32) void) void;` (plus a local `?fn` parameter round-trip) called with a real function and with `null`.
  - `opt_void_extern_xmod/main.zig`: `extern "c" fn take_void(p: ?*void) void;` called with a non-null pointer and with `null`.
  Each prints a deterministic contract line; the GREEN target is warning-free C89 from the fixed compiler.
- [ ] **Step 2: Emit + inspect — pin the exact C.** Build with the Task 4 fixed-point compiler and read the emitted C and every gcc warning:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/planA_4b_base   # expect the Task 4 fixed point 0d3e5560…
/tmp/planA_4b_base/zig1_5_clean -o /tmp/opt_fnptr repro/mi_matrix/opt_fnptr_extern_xmod/main.zig
cd /tmp/opt_fnptr && sh build_target.sh linux opt_fnptr_extern   # capture warnings
```

  Record for both fixtures: the emitted prototype (plain `void (*)(int)` / `void*`, or a struct-wrapped optional?), the call site (does `null` emit `0` or a compound literal?), and every gcc diagnostic.
- [ ] **Step 3: Classify + declare.** Correct C (`void (*)(…)`/`void*`, null = `0`, no warnings) ⇒ premise disproved, STOP and report. Incorrect C (struct-wrapped optional, wrong call convention, or `-Wincompatible-pointer-types`) ⇒ premise confirmed; pin the defect to a file/function/line in the emitter and classify both dirs in `EXPECTED_FAIL.md`.
- [ ] **Step 4: Present the fix surface.** Name the emitter locus (e.g. optional/pointer C-type rendering in `sf/src/c89_emit.zig` and/or its C-type helper), the minimal change, and the blast radius. No `sf/src` change in this task.
- [ ] **Step 5: Commit** (`test(std): pin the optional-fn-pointer C-emission defect (Plan A Task 4b-I)`), staging the two fixtures + `EXPECTED_FAIL.md`.

---

### Task 4b-F: Fix the optional-fn-pointer C-emission defect (F)

**Files:**
- Modify: the emitter locus pinned by Task 4b-I (expected `sf/src/c89_emit.zig` and/or its C-type helper; confirm before editing) — **authorized compiler change (operator ruling m1243)**.
- Modify: `repro/mi_matrix/opt_fnptr_extern_xmod/main.zig`, `repro/mi_matrix/opt_void_extern_xmod/main.zig`; declassify both in `repro/mi_matrix/EXPECTED_FAIL.md`.
- **Forbidden:** any change beyond the pinned locus; no `sf/src/pal.zig`.

**Interfaces:**
- Consumes: Task 4b-I's pinned classification + fix surface.
- Produces: correct C for optional function pointers / optional `*void`; a MOVED fixed point.

- [ ] **Step 1: Implement the fix** at the pinned locus: render `?fn(…)` as a plain C function pointer (null = `0`) and `?*void` as `void*` (null = `0`) in `extern "c"` prototypes, parameters, and call sites.
- [ ] **Step 2: Fixtures RED → GREEN** — both probes compile warning-free and run with the documented stdout; the `null` case emits `0`.
- [ ] **Step 3: Safety/determinism gates** — 3× emission md5 stable; `-fsafe`/`-ffast` parity.
- [ ] **Step 4: Declassify** both dirs in `EXPECTED_FAIL.md`.
- [ ] **Step 5: Fixed point MOVES (authorized) + re-baseline.** Rebuild via the seed model; record the new fixed point as the Plan A baseline for Tasks 4c/5-7 and Plans B/C. Declare any residual (e.g. other optional-pointer shapes left unfixed) in the report + a tracked note.
- [ ] **Step 6: Commit** (`fix(compiler): correct C emission for optional fn-pointers / optional *void (Plan A Task 4b-F)`).

---

### Task 4c: Revert `std_debug.setTrapHandler` to the blueprint signature

**Files:**
- Modify: `sf/src/std_debug.zig` — restore `pub fn setTrapHandler(h: ?fn(*TrapContext) void) void`; **drop** `clearTrapHandler` (the `?fn` signature makes `setTrapHandler(null)` the null-uninstall, so the helper is redundant and non-blueprint).
- Modify: `repro/mi_matrix/stdlib_debug_trap_xmod/main.zig` (pass the handler directly).
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` if the fixture's classification changes.

**Interfaces:**
- Consumes: Task 4b-F's fixed optional-fn-pointer emission.
- Produces: the blueprint §3 L1 `std_debug` surface exactly; fixed point UNMOVED.

- [ ] **Step 1: Revert the signature** to `?fn(*TrapContext) void`; delete `clearTrapHandler` (rationale in Files); the extern setter takes the optional function pointer directly (null = `0`).
- [ ] **Step 2: Update the trap fixture** to the reverted API; keep the deterministic `assertion failed` / `debug trap ok` contract.
- [ ] **Step 3: Re-run the Task 4 gates** — dump/build/run rc=0, 3× emission md5, `-fsafe`/`-ffast` parity, `check_emit_support.sh` 5/5.
- [ ] **Step 4: Record the fixed point** — `std_debug` is not compiler-imported, so it MUST equal Task 4b-F's re-baseline; if it moves, STOP.
- [ ] **Step 5: Commit** (`refactor(std): restore the blueprint ?fn setTrapHandler signature (Plan A Task 4c)`).

---

### Task 5: `std_buf` (L2)

**Files:**
- Create: `sf/src/std_buf.zig`
- Create: `repro/mi_matrix/stdlib_buf_growth_xmod/`, `stdlib_buf_endian_xmod/`, `stdlib_buf_clear_xmod/`, `stdlib_debug_backtrace_xmod/`
- Modify: `sf/src/std_debug.zig` (add `backtrace`; the single documented L1→L2 import of `std_buf` — see Global Constraints)
- Modify: `sf/src/std.zig`
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_buf.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`; `std_debug` (`TrapContext`) for `backtrace`.
- Produces: `std_buf` (`Buf`, `init`, `initCapacity`, `append*`, `reserve`, `clear`, `slice`, `capacity`) — blueprint §3 L2; and `std_debug.backtrace(ctx: *const TrapContext, out: *std.buf.Buf) !void` (blueprint §3 L1), folded here because it consumes `std_buf`.

- [ ] **Step 1: Write the failing fixtures** (growth across 3 doublings; endian round-trips; clear-and-reuse with capacity retained) **and the `backtrace` fixture** `repro/mi_matrix/stdlib_debug_backtrace_xmod/` (build a `TrapContext` with a valid `ebp` chain, call `std_debug.backtrace(ctx, &buf)`, assert the `Buf` holds the frame addresses in walk order; a null/non-increasing `ebp` terminates the walk).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_buf.zig`.** Doubling growth; `slice()` valid until the next growing append; `clear` retains capacity; no `deinit`.
- [ ] **Step 4: Implement `std_debug.backtrace`.** Walk `ebp` frames from `ctx.ebp`; stop at null or a non-increasing frame pointer (blueprint §3 L1); append each frame address to `out` via `std_buf.append*`. This is the single documented L1→L2 import (Global Constraints); keep it confined to `backtrace`.
- [ ] **Step 5: GREEN** (all four fixtures).
- [ ] **Step 6: Arena gate** — a fixture that exhausts the arena; `append` returns `OutOfMemory`; no memory written outside the arena.
- [ ] **Step 7: Safety/determinism gates + fixed point UNMOVED + commit** (stage `sf/src/std_buf.zig`, `sf/src/std_debug.zig`, `sf/src/std.zig`, the four fixtures, and both seed scripts). `std_debug` is not compiler-imported, so the fixed point MUST equal Task 4b-F's re-baseline.

---

### Task 6: `std_str` extension (L2)

**Files:**
- Modify: `sf/src/std_str.zig` (add the 12 new functions)
- Create: one `repro/mi_matrix/stdlib_str_<name>_xmod/` per new function
- Modify: `sf/src/std.zig` (no change needed — `str` already re-exported)

**Interfaces:**
- Consumes: `std_arena`, `std_buf`.
- Produces: `split`, `splitLines`, `join`, `trim`, `trimLeft`, `trimRight`, `indexOf`, `lastIndexOf`, `eqIgnoreCase`, `replace`, `count`, `repeat` — blueprint §3 L2.

- [ ] **Step 1: Write the failing fixtures** (one per function; `split` also pins the slice-aliasing contract).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement the functions.** `split` returns slices into `s` (only the outer array allocates); `replace` allocates the result only; `from`/`to` may alias `s`.
- [ ] **Step 4: GREEN.**
- [ ] **Step 5: Safety/determinism gates + fixed point UNMOVED + commit.**

---

### Task 6b-I: `-ffast` undefined slice-array emission — investigate + pin (I)

**Files:**
- Create: `repro/mi_matrix/undefined_slice_array_xmod/main.zig` (the `-ffast`-only failure; auto-listed, so the `-ffast` corpus classifier pins it)
- Create: `repro/mi_matrix/known_excluded/undefined_slice_array_safe_xmod/main.zig` (the `-fsafe`/default control; `known_excluded` is never enumerated by `scripts/corpus/list_corpus_dirs.sh`, so it is not run through the `-ffast` classifier)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (classify/declare the new dirs)
- **No `sf/src` change.** No STOP unless the premise below is disproved.

**Interfaces:**
- Consumes: the landed `std_str` extension (Task 6) and its `[N][]const u8` fixtures.
- Produces: a pinned statement of exactly what the compiler emits under `-ffast` for a 1-D array of slices initialized `undefined`, plus the fix surface for Task 6b-F.

**Premise (operator ruling m1277).** Under `-ffast`, a 1-D array of slices initialized `undefined` (`var arr: [N][]const u8 = undefined;`) mis-emits the element fill as `arr[_i] = 0;`, which gcc rejects (assigning `int` to a slice). The default/`-fsafe` paths avoid it because `undefined` lowers to `poison_init` (`sf/src/c89_emit.zig:7329`); the `-ffast` path reaches the `.undefined_const` else-arm at `sf/src/c89_emit.zig:7308-7311`, whose scalar zero-fill is correct for scalar element kinds but wrong for a slice element kind (neither `array_type`/`struct_type`/`tagged_union_type`). This is a real, pre-existing compiler defect; it is mode-specific, not a frontend gap.

- [ ] **Step 1: Write the probe + control fixtures**
  - `undefined_slice_array_xmod/main.zig`: a function-local `var arr: [N][]const u8 = undefined;`, partially assigned, then printed with a deterministic contract line. This is the `-ffast`-only failure; the corpus classifier runs `-ffast`, so this dir pins the failure (FAIL pre-fix → OK post-fix).
  - `known_excluded/undefined_slice_array_safe_xmod/main.zig`: the SAME program as the off-corpus `-fsafe`/default control. Compiled manually under `-fsafe` and the default mode; it MUST build/run clean (classify OK) before and after the fix.
- [ ] **Step 2: Emit + inspect — pin the exact C.** Build with the Task 6 fixed-point compiler and read the emitted C and every gcc diagnostic in BOTH modes:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/planA_6b_base   # expect the Task 6 fixed point 4b1c029d…
# -ffast pin: expect the defect
/tmp/planA_6b_base/zig1_5_clean -ffast -o /tmp/undefined_slice_array repro/mi_matrix/undefined_slice_array_xmod/main.zig
cd /tmp/undefined_slice_array && sh build_target.sh linux undefined_slice_array   # capture gcc diagnostics
# -fsafe/default control: expect clean
/tmp/planA_6b_base/zig1_5_clean -fsafe -o /tmp/undefined_slice_array_safe repro/mi_matrix/known_excluded/undefined_slice_array_safe_xmod/main.zig
```

  Record for both: the emitted init loop (is the fill `arr[_i] = 0;` — an `int` to a slice — or a per-element poison/zero?), and every gcc diagnostic. Confirm the control is clean under `-fsafe`/default and the pin fails only under `-ffast`.
- [ ] **Step 3: Classify + declare.** Correct C (a slice-aware zero/poison fill, no warnings) ⇒ premise disproved, STOP and report. Incorrect C (`arr[_i] = 0;`, gcc `-Wint-conversion` / "assignment to … from int") ⇒ premise confirmed; pin the defect to `sf/src/c89_emit.zig:7308-7311` and classify the auto-listed `undefined_slice_array_xmod` in `EXPECTED_FAIL.md`. **Mode-specific gate:** the corpus classifier is `-ffast`-based, so the pin MUST classify **FAIL** pre-fix and **OK** post-fix; the `-fsafe`/default control (off-corpus) MUST build/run clean both pre- and post-fix. State explicitly that a `-fsafe`-only defect would be invisible to the `-ffast` classifier — this one is not, because the defect lives in the `-ffast` path.
- [ ] **Step 4: Present the fix surface.** Name the emitter locus (`sf/src/c89_emit.zig:7308-7311`, the `.undefined_const` else-arm), the minimal change (add a `slice_type` element arm that zero-fills the `{ptr, len}` fields — or route slice elements to the same `poison_init`/byte-fill path the safe mode uses), and the blast radius. No `sf/src` change in this task.
- [ ] **Step 5: Commit** (`test(std): pin the -ffast undefined slice-array emission defect (Plan A Task 6b-I)`), staging the two fixtures + `EXPECTED_FAIL.md`.

---

### Task 6b-F: Fix the `-ffast` undefined slice-array emission (F)

**Files:**
- Modify: the emitter locus pinned by Task 6b-I (`sf/src/c89_emit.zig:7308-7311`, the `.undefined_const` else-arm; confirm before editing) — **authorized compiler change (operator ruling m1277)**.
- Modify: `repro/mi_matrix/undefined_slice_array_xmod/main.zig` if needed; declassify the dir in `repro/mi_matrix/EXPECTED_FAIL.md`.
- **Forbidden:** any change beyond the pinned locus; no `sf/src/pal.zig`.

**Interfaces:**
- Consumes: Task 6b-I's pinned classification + fix surface.
- Produces: correct C for a 1-D array of slices initialized `undefined` under `-ffast`; a MOVED fixed point.

- [ ] **Step 1: Implement the fix** at the pinned locus: give the `.undefined_const` else-arm a slice element-kind path that zero-fills the element's `{ptr, len}` fields (or reuse the `poison_init`/byte-fill path the default/`-fsafe` modes use) instead of emitting `arr[_i] = 0;`.
- [ ] **Step 2: Fixtures RED → GREEN** — the `-ffast` pin compiles warning-free and runs with the documented stdout; the `-fsafe`/default control stays clean.
- [ ] **Step 3: Safety/determinism gates** — 3× emission md5 stable; `-fsafe`/`-ffast` parity.
- [ ] **Step 4: Declassify** the `undefined_slice_array_xmod` dir in `EXPECTED_FAIL.md`.
- [ ] **Step 5: Fixed point MOVES (authorized) + re-baseline.** Rebuild via the seed model; record the new fixed point as the Plan A baseline for Tasks 7/8 and Plans B/C. Declare any residual (e.g. other `undefined` element kinds — many-pointer/optional — left unfixed) in the report + a tracked note.
- [ ] **Step 6: Commit** (`fix(compiler): correct -ffast emission for an undefined 1-D array of slices (Plan A Task 6b-F)`).

---

### Task 7: Usage programs + corpus container (R7b)

**Files:**
- Modify: `scripts/corpus/list_corpus_dirs.sh` (add container rule D for `stdlib_test/`)
- Create: `stdlib_test/bits_buf_str_usage/main.zig`
- Create: `stdlib_test/os_time_usage/main.zig`

**Interfaces:**
- Consumes: `std_bits`/`std_buf`/`std_str` (Tasks 1/5/6), `std_os`/`std_time`/`std_debug` (Tasks 2/3/4).
- Produces: the Plan A usage programs; the `stdlib_test/` corpus container.

- [ ] **Step 1: Add container rule (D)** to `scripts/corpus/list_corpus_dirs.sh` — enumerate every immediate subdir of `stdlib_test/` via the existing `emit_dir` resolution (`main.zig` → `<basename>.zig` → first `*.zig`), mirroring rule (C) for `examples/z98/`; update the header universe list.
- [ ] **Step 2: Create `stdlib_test/bits_buf_str_usage/main.zig`** — a real program composing `std_bits` + `std_buf` + `std_str` in an intended workflow (e.g. build a bit field, append formatted bytes to a `Buf`, then split/trim/join the result), with a deterministic stdout contract.
- [ ] **Step 3: Create `stdlib_test/os_time_usage/main.zig`** — a real program composing `std_os` + `std_time` + `std_debug` (e.g. `initArgs`, print cwd, sample `highRes`/`ticksMs`, route a diagnostic through `std_debug`), deterministic except for the documented time contract.
- [ ] **Step 4: Compile and run both under the fixture gates** — 3× emission md5 identical; `-fsafe`/`-ffast` parity; documented stdout matches.
- [ ] **Step 5: Verify the harness enumerates both dirs** (`bash scripts/corpus/list_corpus_dirs.sh | grep stdlib_test`).
- [ ] **Step 6: Commit** (`feat(std): add Plan A usage programs + stdlib_test corpus container (Plan A Task 7)`).

---

### Task 8: Plan A closeout

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (verify the `lib/` copy list is complete)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump the header once)
- Modify: `docs/sf/QUICK_REF.md` (std-module inventory)

**Interfaces:**
- Consumes: Tasks 1-7 (including the Task 4b/4c optional-fn-pointer I/F pair and the Task 6b-I/6b-F `-ffast` undefined slice-array I/F pair).
- Produces: the Plan B pointer.

- [ ] **Step 1: Verify the seed scripts' `lib/` copy list is complete** — the module-adding tasks (1/2/3/5) each appended their module in the same commit; confirm `std_bits.zig`/`std_os.zig`/`std_os_pal.zig`/`std_time.zig`/`std_time_pal.zig`/`std_buf.zig` are all present in both `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` (the same touchpoints as the existing 9). Add any missing entry here; do not leave the list incomplete. Also confirm the `opt_fnptr_extern_xmod`/`opt_void_extern_xmod` dirs were declassified by Task 4b-F and the `undefined_slice_array_xmod` dir by Task 6b-F.
- [ ] **Step 2: Run the full corpus + gates.**

```bash
cd /workspace/znineeight
bash scripts/corpus/list_corpus_dirs.sh | wc -l
bash scripts/check_emit_support.sh
bash scripts/closeout/verify_upgraded.sh /tmp/planA_build2/zig1_5_clean
```

Expected: the count grew by the new fixtures; `OK: 5/5`; `CLOSEOUT OK`. Zero class movement on the pre-existing dirs.

- [ ] **Step 3: Bump `EXPECTED_FAIL.md`** once (header + a Plan A section recording the new dirs + the fixed point).
- [ ] **Step 4: Update the QUICK_REF std-module inventory.**
- [ ] **Step 5: Record the next-plan pointer.**

```markdown
## Next plan
Plan A complete. NEXT: `docs/superpowers/plans/2026-09-17-std-lib-plan-b-resources-stream.md`
(L3 resources + L6 std_stream).
```

- [ ] **Step 6: Commit** (`chore(std-lib): Plan A closeout — L0-L2 foundation landed`).

---

## Self-Review

- **Spec coverage:** spec §4 Plan A (all six modules) → Tasks 1-6; §5 R1-R7 → every module task's gates; §5 R7b → Task 7; §6 gates → Tasks 1-7 (+ 4b/4c and 6b) Step gates + Task 8; §7 distribution → Task 8 Step 1; §10 index → the `Sequence:` line + Task 8 Step 5. The optional-fn-pointer compiler defect (operator ruling m1243) → Tasks 4b-I/4b-F + 4c; the `-ffast` undefined slice-array compiler defect (operator ruling m1277) → Tasks 6b-I/6b-F; `backtrace` (blueprint §3 L1, Exception 1 of the two R3 exceptions) → Task 5.
- **Placeholder scan:** module signatures are referenced to the blueprint (§3 L0-L2) rather than duplicated — the blueprint is the exact-signature source of record and travels with the plan. Every step has a concrete command/expected output.
- **Type consistency:** the module names (`std_bits`/`std_os`/`std_time`/`std_buf`) and re-export names (`bits`/`os`/`time`/`buf`) are used identically across tasks. `std_debug.setTrapHandler` is `?fn(*TrapContext) void` after Task 4c (non-optional `*void` fallback only between Tasks 4 and 4c); `std_debug.backtrace` takes `*std.buf.Buf` and is delivered in Task 5.
