# Z98 std-lib Plan A — L0-L2 foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the L0-L2 std-lib foundation from the blueprint — `std_bits`, `std_os`, `std_time`, the `std_debug` extension, `std_buf`, and the `std_str` extension — with fixtures and the layering/dependency gate green.

**Architecture:** One plan, six module tasks, ordered by the blueprint's construction order (L0 → L1 → L2). Each module is authored in `sf/src/std_<name>.zig` with the blueprint's exact signatures, gets `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixtures, and is validated by the six gates. **This plan runs after Task 0 (separation audit); its successor is Plan B (L3 + L6).**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan A), §5, §6; module signatures in `sf/docs/std_lib_extension.txt` §3 (L0-L2).

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-task0-separation-plan.md`](2026-09-17-std-lib-task0-separation-plan.md) (separation audit). NEXT plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6).

## Global Constraints

- **Precondition:** Task 0 complete (the compiler↔std separation audit; the dead std-importing files deleted; the blueprint §6 claim corrected).
- **Baseline (re-verify at Task 1).** Record HEAD, the self-compile fixed point, the seed version/archive md5, and the corpus `EXPECTED_FAIL.md` header at dispatch. The compiler's import graph reaches no std module, so adding std modules MUST NOT move the fixed point. **Exception (operator ruling 2026-09-17): exactly two authorized compiler-graph changes move the fixed point — the per-OS prelude work (Tasks 2-3: `std_os_prelude.h`/`std_time_prelude.h`, the `net_prelude.h` analog) and Task 4's `std_debug` trap hook. Re-baseline at Task 2 Step 6, Task 3 Step 6, and Task 4 Step 6. Tasks 1,5,6,7 MUST leave it unmoved — if it moves, STOP (a std module or an unauthorized PAL edit leaked into the compiler graph).**
- **PAL boundary (operator ruling 2026-09-17).** The std lib MUST NOT wrap or edit the compiler PAL for OS primitives. OS specifics live in std-side PAL modules (`sf/src/std_os_pal.zig`, `sf/src/std_time_pal.zig`) using the `std_net.zig` `@cInclude`+`extern`+`@isWindows()` pattern, with per-OS C prototypes supplied by the authorized prelude headers. The only authorized compiler edits in this plan are the prelude work (Tasks 2-3) and the Task 4 trap hook (see each task's Files list). The compiler's cost is what it imports; the library's cost is what emits.
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; never invoke `zig0`.
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Layering (R3):** a module may import only lower layers — never siblings, never higher. The dependency-graph check (one pass) is part of every module task's gate.
- **Arena (R1):** allocating functions take `arena: *std.arena.Arena` first; `OutOfMemory` in the error set.
- **Errors (R2):** one error set per module; no `catch unreachable`.
- **Determinism (R6):** no output may depend on addresses, the wall clock, or the PID unless the contract says so.
- **Fixtures (R7):** every public function gets a `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixture.
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
- `sf/src/std_debug.zig` — add `TrapContext` + `setTrapHandler`/`defaultTrapHandler`/`writeCoreDump`/`backtrace`.
- `sf/src/std_str.zig` — add `split`/`splitLines`/`join`/`trim*`/`indexOf`/`lastIndexOf`/`eqIgnoreCase`/`replace`/`count`/`repeat`.
- `sf/src/std.zig` — add re-exports for `bits`/`os`/`time`/`buf` (per the blueprint §6 distribution; `debug`/`str` already re-exported).

**Create (fixtures):** one dir per public function under `repro/mi_matrix/`:
- `stdlib_bits_<name>_xmod/` (table-driven; the blueprint allows one fixture for the whole module — use `stdlib_bits_table_xmod`).
- `stdlib_os_argc_xmod/`, `stdlib_os_env_xmod/`, `stdlib_os_cwd_xmod/`.
- `stdlib_time_monotonic_xmod/`, `stdlib_time_sleep_xmod/`.
- `stdlib_debug_trap_xmod/`.
- `stdlib_buf_growth_xmod/`, `stdlib_buf_endian_xmod/`, `stdlib_buf_clear_xmod/`.
- one `stdlib_str_<name>_xmod/` per new `std_str` function.

**Modify (closeout):**
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump the header once at Plan A closeout.
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` — extend the `lib/` copy list with the new modules (same touchpoints as the existing 9).

**Reference (read-only):** `sf/docs/std_lib_extension.txt` §3 (L0-L2), `docs/sf/QUICK_REF.md`, `docs/sf/AGENTS.md`.

---

### Task 1: Baseline + `std_bits` (L0)

**Files:**
- Create: `sf/src/std_bits.zig`
- Create: `repro/mi_matrix/stdlib_bits_table_xmod/main.zig`
- Modify: `sf/src/std.zig` (add `pub const bits = @import("std_bits.zig");`)

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

- [ ] **Step 5: Add the re-export + run the fixture — GREEN**

Add `pub const bits = @import("std_bits.zig");` to `sf/src/std.zig`, then:

```bash
cd /workspace/znineeight
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
git add sf/src/std_bits.zig sf/src/std.zig repro/mi_matrix/stdlib_bits_table_xmod
git commit -m "feat(std): add std_bits (L0) + fixture (Plan A Task 1)"
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
- **Forbidden:** any edit to `sf/src/pal.zig` / `sf/src/include/zig_pal.c` (compiler PAL). A missing primitive is added to `std_os_pal.zig`.

**Interfaces:**
- Consumes: `std_bits` (optional).
- Produces: `std_os` (`argc`, `argv`, `exit`, `env`, `cwd`) — signatures in blueprint §3 L1.

- [ ] **Step 1: Write the failing fixtures** (`argc`/`argv` round-trip; env unset/set; cwd non-empty).
- [ ] **Step 2: Run them — RED** (`error[3048]`).
- [ ] **Step 3: Implement `std_os.zig`** with the blueprint signatures; `env` via `getenv` (`<stdlib.h>`); `cwd` allocates from the arena and fills via `GetCurrentDirectoryA`/`getcwd` (prototypes from the authorized `std_os_prelude.h`); `exit` via `@exit`. **`argc`/`argv` (operator ruling 2026-09-17): expose `std_os.initArgs(argc: i32, argv: [*]*const u8) void` mirroring `sf/src/pal.zig:184-195`, which the user calls from their `main`; `argc()`/`argv(i)` read the saved values. The compiler is untouched for this — no capture hook in the emitted `main` wrapper.**
- [ ] **Step 4: Re-export + run — GREEN** (all three fixtures rc=0, documented stdout).
- [ ] **Step 5: Safety/determinism gates** (`-fsafe`/`-ffast` parity, 3× md5).
- [ ] **Step 6: Fixed point MOVED (authorized prelude work) + commit** (`feat(std): add std_os (L1) + fixtures (Plan A Task 2)`). Adding `std_os_prelude.h` + its emitter wiring is part of the authorized prelude work; rebuild via the seed model and record the new fixed point md5.

---

### Task 3: `std_time` (L1)

**Files:**
- Create: `sf/src/std_time.zig`
- Create: `sf/src/std_time_pal.zig` (std-side OS externs — the `std_net.zig` pattern)
- Create: `repro/mi_matrix/stdlib_time_monotonic_xmod/`, `stdlib_time_sleep_xmod/`
- Create (authorized compiler change): `sf/src/include/std_time_prelude.h` (per-OS C prototypes; the `net_prelude.h` analog)
- Modify (authorized compiler change): `sf/src/emit_support.zig` (emit the prelude), `sf/src/c89_emit.zig` (conditional emission), `scripts/check_emit_support.sh` (prelude entry)
- Modify: `sf/src/std.zig` (re-export `time`)
- **Forbidden:** any edit to `sf/src/pal.zig` / `sf/src/include/zig_pal.c`.

**Interfaces:**
- Consumes: `std_os`.
- Produces: `std_time` (`ticksMs`, `highRes`, `highResFreq`, `wallClockUnix`, `sleepMs`) — blueprint §3 L1.

- [ ] **Step 1: Write the failing fixtures** (monotonicity over 100 calls; sleep-with-tolerance).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_time.zig`.** `ticksMs`/`highRes`/`highResFreq`/`wallClockUnix` are `@isWindows()`-guarded wrappers over `std_time_pal.zig` externs (`GetTickCount`/`QueryPerformanceCounter`/`QueryPerformanceFrequency`; `gettimeofday`/`time`), whose prototypes come from the authorized `std_time_prelude.h` (option B). `sleepMs` calls the `@sleepMs` builtin directly (do **not** import `std_io`; R3). Note R6: `ticksMs` wraps; `highRes` falls back to `ticksMs * 1000` on hardware without a high-res timer (documented, deterministic). The monotonicity fixture must be robust to the fallback.
- [ ] **Step 4: Re-export + GREEN.**
- [ ] **Step 5: Safety/determinism gates.**
- [ ] **Step 6: Fixed point MOVED (authorized prelude work) + commit.** Adding `std_time_prelude.h` + its emitter wiring is the prelude half of the two authorized compiler-graph changes; rebuild via the seed model and record the new fixed point md5.

---

### Task 4: `std_debug` extension (L1)

**Files:**
- Modify: `sf/src/std_debug.zig` (add `TrapContext`, `setTrapHandler`, `defaultTrapHandler`, `writeCoreDump`, `backtrace`; declare `extern "c" fn pal_set_trap_handler(...)`). **`TrapContext` field order MUST match `sf/src/include/zig_pal.c` exactly: `eip, esp, ebp, eflags, eax, ebx, ecx, edx, esi, edi` (10 × u32).**
- Create: `repro/mi_matrix/stdlib_debug_trap_xmod/`
- Modify (authorized compiler change): `sf/src/include/zig_pal.c` (canonical), `sf/src/emit_support.zig` (`emitZigPalCSupport`), `sf/src/c89_emit.zig` (`emitZigPalC` dead mirror) — add `g_trap_handler`/`TrapContext`/`pal_set_trap_handler` and make `pal_trap()` call the handler. The canonical and emitted copies MUST stay byte-identical (`check_emit_support.sh`). **No other compiler file changes.**

**Interfaces:**
- Consumes: `std_os`, `std_buf` (for `backtrace`).
- Produces: the blueprint §3 L1 `std_debug` surface.

- [ ] **Step 1: Boundary resolved by operator ruling (2026-09-17).** The trap hook IS an authorized compiler-graph change (see Files above); implement it. Do not STOP. Any compiler-graph change beyond the two authorized ones (the Tasks 2-3 per-OS preludes and this trap hook) requires a fresh operator ruling.
- [ ] **Step 2: Write the failing fixture** (install a handler, trigger a trap, verify `ctx.eip != 0`).
- [ ] **Step 3: RED.**
- [ ] **Step 4: Implement the extension.**
- [ ] **Step 5: GREEN + safety/determinism gates.**
- [ ] **Step 6: Fixed point MOVED ONCE (authorized) + commit.** Rebuild via the seed model, record the new fixed point md5 as the Plan A baseline for Tasks 5-7 and for Plans B/C. If it did **not** move, the hook is not actually compiled into `zig_pal` — STOP and diagnose.

---

### Task 5: `std_buf` (L2)

**Files:**
- Create: `sf/src/std_buf.zig`
- Create: `repro/mi_matrix/stdlib_buf_growth_xmod/`, `stdlib_buf_endian_xmod/`, `stdlib_buf_clear_xmod/`
- Modify: `sf/src/std.zig`

**Interfaces:**
- Consumes: `std_arena`.
- Produces: `std_buf` (`Buf`, `init`, `initCapacity`, `append*`, `reserve`, `clear`, `slice`, `capacity`) — blueprint §3 L2.

- [ ] **Step 1: Write the failing fixtures** (growth across 3 doublings; endian round-trips; clear-and-reuse with capacity retained).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_buf.zig`.** Doubling growth; `slice()` valid until the next growing append; `clear` retains capacity; no `deinit`.
- [ ] **Step 4: GREEN.**
- [ ] **Step 5: Arena gate** — a fixture that exhausts the arena; `append` returns `OutOfMemory`; no memory written outside the arena.
- [ ] **Step 6: Safety/determinism gates + fixed point UNMOVED + commit.**

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

### Task 7: Plan A closeout

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (extend the `lib/` copy list)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (bump the header once)
- Modify: `docs/sf/QUICK_REF.md` (std-module inventory)

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: the Plan B pointer.

- [ ] **Step 1: Extend the seed scripts' `lib/` copy list** with `std_bits.zig`/`std_os.zig`/`std_time.zig`/`std_buf.zig` (the same touchpoints as the existing 9).
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

- **Spec coverage:** spec §4 Plan A (all six modules) → Tasks 1-6; §5 R1-R7 → every module task's gates; §6 gates → Tasks 1-6 Step gates + Task 7; §7 distribution → Task 7 Step 1; §10 index → the `Sequence:` line + Task 7 Step 5.
- **Placeholder scan:** module signatures are referenced to the blueprint (§3 L0-L2) rather than duplicated — the blueprint is the exact-signature source of record and travels with the plan. Every step has a concrete command/expected output.
- **Type consistency:** the module names (`std_bits`/`std_os`/`std_time`/`std_buf`) and re-export names (`bits`/`os`/`time`/`buf`) are used identically across tasks.
