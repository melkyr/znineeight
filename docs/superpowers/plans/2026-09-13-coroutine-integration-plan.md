# Z98 Coroutine Integration Implementation Plan (Track 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **TRACK-4 ALIGNMENT (2026-09-15, operator ruling; supersedes the STALE-SCHEDULER
> MARKER).** The scheduler surface is aligned to Amendment 7 (heterogeneous
> `@asyncResume` self-dispatch): `tick(s)`, `awaitTask(s, t)`; no `Task.step` and
> no `step` parameter — matching the Track-4 spec. The baseline, pinned consumed
> surface, cross-track ABI closeout check, and the multi-module `__Z98Step_<f>`
> emission-gap pre-conversion blocker are refreshed in Global Constraints; the
> full record is **Amendment 1** below. Re-verify at Task 1 before dispatch.

**Goal:** Convert the `rogue_mud` NPC AI and per-connection broadcast paths and the `mud_server` `select` accept/read loop to cooperative coroutines on the Track 2 builtins and Track 3 `std.async`, with the committed goldens byte-identical.

**Architecture:** One linear track. Two operator-authorized `sf/src` changes precede the conversions: **Task 0** fixes the multi-module `__Z98Step_<f>` emission gap in the C emitter (the self-emission fixed point MOVES), and **Task 0b** changes `std.async` task ownership (`addTask` stores `*Task`; not in the compiler import graph, so no fixed-point move, but the seed archive's `lib/std_async.zig` changes). **Task 2a** (a prelude exposed by the Task 2 dispatch) fixes the nested module value-position access gap (`std.async.HEADER_SIZE` → `error[3042]`+`warning[3023]`) that blocks Tasks 2/4/5; I then F, `sf/src` change, fixed point MOVES. The seed is rotated at Task 6 closeout. Then `rogue_mud/lib/combat.zig` grows a suspending `npcCoroutine` (one task per active enemy) whose per-turn driver is `std.async.tick`; `rogue_mud/ui.zig` grows a suspending `drawToSocketCoroutine` that yields between frame rows; `rogue_mud/main.zig` owns the caller-supplied schedulers and task arenas and wires create/schedule/cancel across the three modules. `mud_server/main.zig` replaces the fd-set bookkeeping with one `clientCoroutine` task per accepted socket driven by `@asyncResume` from the select-ready path, with `std.async.awaitTask` on the quit/disconnect path. The example conversions themselves touch no `sf/src` file.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.async` (Track 3), the four `@async*` builtins (Track 2), bash, `gcc -m32`, git.

## Global Constraints

- **Baseline (re-verify at Task 1; the fixed point MOVES in Task 0).** Pre-Task-0 HEAD `0aa5e13d`; pre-Task-0 compiler fixed point `027377296b2e38402ff8470f5c429eb8`; seed v19 archive md5 `23a16154e83736cf6b636685396a124a`; corpus 612 = 571 OK / 37 GREEN / 4 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v85 (2026-09-15). Task 0 (emitter fix) and Task 0b (`std.async` ownership fix) change `sf/src`, so the fixed point and seed move; Task 1 re-verifies and records the post-Task-0/0b values before capturing goldens.
- **Precondition:** Tracks 2 and 3 are implemented and landed. The four `@async*` builtins work, `sf/src/std_async.zig` exists, and `lib/std_async.zig` is installed next to the compiler under test (`docs/sf/QUICK_REF.md:97-98` recipe plus `std_async.zig`).
- **`sf/src` scope (operator-authorized 2026-09-15; supersedes the original examples-only constraint).** Authorized `sf/src` changes: **Task 0** (multi-module `__Z98Step_<f>` emission; `sf/src/c89_emit.zig`+`sf/src/main.zig`; fixed point MOVES); **Task 0b** (`std.async` task ownership; `sf/src/std_async.zig`; fixed point UNMOVED but `lib/std_async.zig` changes); **Task 0d** (switch-expression string-literal-prong `string_to_slice` length; `sf/src/semantic_analyzer.zig`; fixed point MOVES); **Task 0f** (S20 un-annotated inference + S21 error-union/optional payload string→slice; `sf/src/semantic_analyzer.zig` + `sf/src/lower.zig`; fixed point MOVES); **Task 0h** (residual latent risks: F-M4 non-literal pointer→slice length-1 default, T0b `error[3043]` `[*]*T` element field store, F-M1 prong guard, T0-M2 grouped tail; `sf/src/lower.zig` + `sf/src/semantic_analyzer.zig` + `sf/src/main.zig`; fixed point MOVES). **Task 2a-F** (nested module value-position access gap exposed by Task 2; `sf/src/lower.zig` +/or `sf/src/semantic_analyzer.zig`; fixed point MOVES). The seed is rotated at Task 6 closeout. No other `sf/src` edit is authorized; Tasks 1-5 touch examples only (the fix tasks re-capture the goldens they change).
- **Standing rule — declare every residual gap (binding).** Any gap a fix leaves behind (a construct still affected, a distinct adjacent bug, a known limitation) MUST be declared before its task is marked complete: a tracked fixture (or an `EXPECTED_FAIL.md` entry for a compile-fail) + a plan/spec note. "Approved with a Minor" is NOT a declaration. S20/S21 (Task 0d residuals) are the first application.
- **`timeout 120` on every binary execution.**
- **gcc flag-set rule (binding):** every `gcc -c` MUST be `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. Compiler builds only via the seed model: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`; never invoke `zig0`. `<out_dir>` must be fresh.
- **Byte-identity is a hard requirement.** `bash scripts/closeout/verify_upgraded.sh <zig1>` MUST print `CLOSEOUT OK` and exit 0 with lisp canonical `96654b39…`, rogue q `3fb6709e…`, rogue move `b3c5b0e1…`, rogue demo `7361d248…`, rogue net variant `aa40a52e…`. Emitted C is NOT required to be byte-identical; only runtime bytes are.
- **Per-entry byte-identity + fallback.** Each converted entry has a pre-conversion and post-conversion runtime capture that must be md5-identical (feeds in `File Structure`). If a golden moves, a capture differs, an `error[3017/3018/3019/3046]`/`PANIC` appears, or task ordering changes the post-turn dungeon state, revert **that entry** to its original loop (keep the original `while`/`select` body), record an amendment, and leave the example building. Entries are independently revertable.
- **Corpus gate:** `bash scripts/corpus/list_corpus_dirs.sh` must still list both `examples/z98/rogue_mud/` and `examples/z98/mud_server/`; classify by gcc exit code, never empty-stderr (`docs/sf/QUICK_REF.md:134-154`); zero class movement on the two examples.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the target region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Pinned consumed surface (landed Track 3, verified 2026-09-15).** Track 2 builtins: `@asyncFrameSize(fn) u32`, `@asyncInit(ctx: *Context, buf: [*]u8, fn, args: ?*const void) *void`, `@asyncResume(frame: *void, arg: ?*void) ?*void`, `@asyncSuspend(data: ?*void) *void`. Track 3 `std.async` as landed in `sf/src/std_async.zig`: `Context` (`HEADER_SIZE = 16`, `pool_base = ctx+16`, `contextInit(buf: []u8) *Context`; buffers MUST be 8-aligned — back them with a `u64` array, never a bare `[N]u8`), `TaskState`, `Task { frame: *void, ctx: *Context, state, cancel_requested, result: *void, arg: *void, waiting_on: *Task, has_waiting_on: bool }` (**no `arena`/`arena_capacity`/`arena_used` fields, no `step` field**), `Scheduler`, `schedulerInit(tasks: []Task) Scheduler`, `addTask(s, t) bool`, `tick(s: *Scheduler) FrameError!void` (**returns an error union — every call site must `try`/`catch`**), `suspend(s, t)`, `awaitTask(s, t) void` (empty-scheduler `@panic`), `cancel(s, t)`, `cancelAll(s)`, `waitAll(s) FrameError!void`. No `step` parameter; `tick`/`waitAll` self-dispatch via `@asyncResume(t.frame, t.arg)`. `@asyncInit` under `-fsafe` traps when `buf.len < @asyncFrameSize(fn)` for compile-time-known array buffers. **Task 0b** changes `Scheduler.tasks` to `[*]*Task` and `schedulerInit(tasks: []*Task)`, so `addTask` stores the caller's `*Task` (no by-value copy) and callers may keep their own `Task` handles. **Caller-side ABI (Amendment 3, B1/B2/B3):** the `@asyncInit` args argument is `@ptrCast(*const void, &record)` — a plain `*const void`, NEVER `?*const void` (a `?*const void` is a non-scalar optional struct and emits invalid C89; the non-optional `*const void` coerces into the optional parameter). `@asyncInit` copies the record **positionally into the coroutine's parameters** (`sf/src/lower.zig:4362-4386`), so each coroutine's params ARE the record's fields — e.g. `npcCoroutine(na: *NpcArgs)` + record `{ na: *NpcArgs }`, `clientFrameCoroutine(ctx: *std.async.Context, cfa: *ClientFrameArgs)` + record `{ ctx, cfa }`, `clientCoroutine(cta: *ClientTaskArgs)` + record `{ cta }`. Root-frame arenas MUST start at `std.async.HEADER_SIZE` (the 16-byte `Context` header occupies `buf[0..16]`; `pool_base = ctx+16`); a root-frame arena bound at `buf[0..]` aliases the header and corrupts frame 0.
- **Cross-track ABI closeout check (binding).** The `Context` header is 16 bytes (`used@0`, `capacity@4`, `oom@8`, 4-byte pad, `pool_base = ctx+16`); the compiler's `CTX_POOL_OFF` MUST equal 16; every frame size MUST be padded to 8; and buffers passed to `contextInit`/`@asyncInit` MUST be 8-aligned. Task 6's closeout MUST re-verify these agree with the landed Track-2/Track-3 surface (the Track-2 plan Task 8 Step 3b and Track-3 plan Task 5 Step 4b carry the same check).
- **Pre-conversion blocker — multi-module `__Z98Step_<f>` emission gap (RESOLVED by Task 0).** With >1 module, `@asyncInit` targeting a coroutine in a NON-LAST module referenced `__Z98Step_<f>` but the emitter never emitted it (it walks `lir_slots` in contiguous per-module runs, and the synthesized steps are appended after the module loop). Task 0 fixes the emitter to emit each step in the module that owns it; `repro/mi_matrix/async_step_nonlast_xmod` flips from EXPECTED-FAIL to PASS. Tasks 2-5 MUST NOT dispatch until Task 0 is complete.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` (Track 4 subspec); parent `docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md` §12.6/§13/§14.2.

---

**Sequence:** PREVIOUS plan: `../plans/2026-09-13-std-async-plan.md`. NEXT plan: none — final plan in the sequence. Subspec: [`../specs/2026-09-13-coroutine-integration-design.md`](../specs/2026-09-13-coroutine-integration-design.md).

## File Structure

**Create (Task 0 emitter fix / Task 0b ownership fix):**
- `repro/mi_matrix/async_step_midmodule_xmod/` — 3 modules; the suspending coroutine lives in the MIDDLE (non-last) module; PASSES after Task 0.
- `repro/mi_matrix/stdlib_async_handle_xmod/` — caller-handle task identity (`addTask` stores `*Task`); PASSES after Task 0b.

**Create (Cat 2 real-bug fixtures):**
- `repro/mi_matrix/async_frame_lifetime_xmod/` — S10: ticks a coroutine across enough turns to prove its root frame survives an arena reset.
- `repro/mi_matrix/async_client_cells_xmod/` — S11: two yielding writers with separate cells buffers; each captured stream matches its own pattern.

**Create (committed deterministic harness):**
- `examples/z98/rogue_mud/demo/canonical_feed.txt` — `q\n` (boot + quit).
- `examples/z98/rogue_mud/demo/canonical_move_feed.txt` — `d\nl\nq\n` (move + look + quit).
- `examples/z98/rogue_mud/demo/canonical_expected.txt`, `canonical_move_expected.txt` — Task 1 pre-conversion captures.
- `examples/z98/rogue_mud/demo/README.md` — records the two golden md5s.
- `examples/z98/mud_server/demo/canonical_feed.txt` — `look\nnorth\nquit\n`.
- `examples/z98/mud_server/demo/session.sh` — starts the server on port 4000, drives one client over `bash /dev/tcp`, captures BOTH the server stdout (`canonical_expected.txt`) and the client-received bytes (`canonical_client_expected.txt`), kills by PID, verifies port clear.
- `examples/z98/mud_server/demo/canonical_expected.txt` — Task 1 pre-conversion SERVER-stdout capture.
- `examples/z98/mud_server/demo/canonical_client_expected.txt` — Task 1 pre-conversion CLIENT-received-bytes capture.
- `examples/z98/mud_server/demo/README.md` — records both golden md5s.

**Modify (Task 0 / Task 0b — authorized `sf/src` scope):**
- `sf/src/c89_emit.zig`, `sf/src/main.zig` — emit each `__Z98Step_<f>` in the module that owns `<f>` (Task 0).
- `sf/src/std_async.zig` — `Scheduler.tasks: [*]*Task`, `schedulerInit(tasks: []*Task)`, `addTask` stores the caller's `*Task` (Task 0b).
- `repro/mi_matrix/stdlib_async_{sched,oom,await,cancelall}_xmod/main.zig` — migrate to `[N]*Task` handle arrays (Task 0b).
- `repro/mi_matrix/async_step_nonlast_xmod/main.zig` — comment update (no longer expected-fail); `async_libctx_mix_xmod/main.zig` — annotate as the last-module-coroutine fixture (Task 0).
- `repro/mi_matrix/EXPECTED_FAIL.md` — remove `async_step_nonlast_xmod`; bump header (Task 0).

**Modify (example conversions):**
- `examples/z98/rogue_mud/lib/combat.zig` — `NpcArgs`, `npcStep`, `npcCoroutine`, `spawnEnemies`, `updateEnemies`.
- `examples/z98/rogue_mud/ui.zig` — `ClientArgs`, `drawToSocketCoroutine`.
- `examples/z98/rogue_mud/main.zig` — schedulers/task arenas, per-client cells buffers, `ClientFrameArgs`, `clientFrameCoroutine`, broadcast calls, cancel paths.
- `examples/z98/mud_server/main.zig` — `ClientTaskArgs`, `clientCoroutine`, per-client tasks, `awaitTask` on quit/disconnect.

**Runner (unchanged, reused as the gate):** `scripts/closeout/verify_upgraded.sh`, `scripts/closeout/run_upgraded.sh`.

---

### Task 0: Multi-module `__Z98Step_<f>` emission fix (S15)

**Files:**
- Modify: `sf/src/c89_emit.zig`, `sf/src/main.zig`
- Modify: `repro/mi_matrix/async_step_nonlast_xmod/main.zig` (comment: no longer expected-fail)
- Modify: `repro/mi_matrix/async_libctx_mix_xmod/main.zig` (annotate: last-module coroutine)
- Create: `repro/mi_matrix/async_step_midmodule_xmod/main.zig`, `repro/mi_matrix/async_step_midmodule_xmod/mid.zig`, `repro/mi_matrix/async_step_midmodule_xmod/last.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (remove `async_step_nonlast_xmod`; bump header)

**Interfaces:**
- Consumes: nothing.
- Produces: the C emitter emits `__Z98Step_<f>` in the `.c`/header of the module that owns `<f>`, for every function with `is_suspending` set — not only the last-emitted module. The self-emission fixed point MOVES.

- [ ] **Step 1: RED — confirm the gap**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t4_t0
rm -rf /tmp/t4_t0_dump && mkdir -p /tmp/t4_t0_dump
/tmp/t4_t0/zig1_5_clean --dump-c89 --output-dir /tmp/t4_t0_dump repro/mi_matrix/async_step_nonlast_xmod/main.zig; echo "dump rc=$?"
grep -rln "__Z98Step_caller" /tmp/t4_t0_dump/*.c
for f in /tmp/t4_t0_dump/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_t0_dump -c "$f" -o /dev/null || echo "GCCFAIL $f"; done
```
Expected: an emitted `.c` references `__Z98Step_caller` but none defines it; gcc fails `undeclared`/`undefined`. Record the exact failure.

- [ ] **Step 2: Fix the emitter**

The synthesized steps are appended to `lir_slots` after the module loop (`sf/src/async_state_machine.zig:754`), so the per-module contiguous-run emission (`sf/src/main.zig:1160-1254`, `emitModuleFile`) and the single-file `emitModule` (`sf/src/c89_emit.zig:2711`) never emit a step whose owning module is not last. Change the emission so each synthesized `__Z98Step_<f>` is emitted in the `.c`/`.h` of its owning module (match the step `LirFunction.module_id`), in BOTH the `-o` per-module path and the `--dump-c89` path. Do not change the frame ABI, `CTX_POOL_OFF`, or the scheduler surface.

- [ ] **Step 3: GREEN — fixtures**

Run (per fixture dir, `--dump-c89` + gcc-clean + link + run):
```bash
for d in async_step_nonlast_xmod async_step_midmodule_xmod async_libctx_mix_xmod; do
  rm -rf /tmp/t4_t0/$d && mkdir -p /tmp/t4_t0/$d
  /tmp/t4_t0/zig1_5_clean --dump-c89 --output-dir /tmp/t4_t0/$d repro/mi_matrix/$d/main.zig; echo "$d dump rc=$?"
  for f in /tmp/t4_t0/$d/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_t0/$d -c "$f" -o "${f%.c}.o" || echo "GCCFAIL $f"; done
  gcc -m32 -o /tmp/t4_t0/$d/prog /tmp/t4_t0/$d/*.o && (cd /tmp/t4_t0/$d && timeout 120 ./prog); echo "$d run rc=$?"
done
```
Expected: all three dump rc=0, no GCCFAIL, run rc=0. All other `repro/mi_matrix/async_*` fixtures are unchanged (re-run the corpus gate).

- [ ] **Step 4: Annotate the last-module fixture + add the non-last fixture**

- `async_libctx_mix_xmod/main.zig`: add one line stating this is the **last-module-coroutine** fixture (it imports `co.zig` last on purpose).
- `async_step_nonlast_xmod/main.zig`: replace the EXPECTED-FAIL header with a PASS note (the gap is fixed).
- New `async_step_midmodule_xmod`: `main.zig` imports `mid.zig` then `last.zig`; the suspending `caller` lives in `mid.zig` (NON-last of 3); `main` drives it to completion and asserts the result (mirror the `async_step_nonlast_xmod` body, frame size `@asyncFrameSize(mid.caller)`).

- [ ] **Step 5: Re-baseline `EXPECTED_FAIL.md` + fixed point**

Remove `async_step_nonlast_xmod` from the fail list; bump the header. Rebuild the two-hop closure and record the NEW fixed point (`bash scripts/seed/build_from_seed.sh ...`; hop1==hop2). Run the corpus gate and record the class movement (the two async dirs flip FAIL→OK). Seed rotation is Task 6.

- [ ] **Step 6: Commit**

```bash
git add sf/src/c89_emit.zig sf/src/main.zig repro/mi_matrix/async_step_nonlast_xmod repro/mi_matrix/async_step_midmodule_xmod repro/mi_matrix/async_libctx_mix_xmod repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix(emit): emit __Z98Step_<f> per owning module (Track4 S15)"
```

---

### Task 0b: `std.async` task ownership — `addTask` stores `*Task` (S14)

**Files:**
- Modify: `sf/src/std_async.zig`
- Modify: `repro/mi_matrix/stdlib_async_sched_xmod/main.zig`, `repro/mi_matrix/stdlib_async_oom_xmod/main.zig`, `repro/mi_matrix/stdlib_async_await_xmod/main.zig`, `repro/mi_matrix/stdlib_async_cancelall_xmod/main.zig`
- Create: `repro/mi_matrix/stdlib_async_handle_xmod/main.zig`
- Create: `repro/mi_matrix/stdlib_async_await_nonctx_xmod/main.zig`

**Interfaces:**
- Consumes: `std.async`.
- Produces: `Scheduler { tasks: [*]*Task, capacity: usize, count: usize, current: usize, in_task: bool }`; `schedulerInit(tasks: []*Task) Scheduler`; `addTask(s, t) bool` stores the caller's `t` (no by-value copy); `tick`/`awaitTask` read/write through `s.tasks[i]`; `tick` sets `in_task` true around `@asyncResume`; `awaitTask` `@panic`s when called from a non-suspending context (`!s.in_task`). The compiler fixed point is UNMOVED (`std_async.zig` is not in `sf/src/main.zig`'s import graph); the seed archive's `lib/std_async.zig` changes, so Task 6 rotates the seed.

- [ ] **Step 1: Change `sf/src/std_async.zig`**

```zig
pub const Scheduler = struct { tasks: [*]*Task, capacity: usize, count: usize, current: usize };

pub fn schedulerInit(tasks: []*Task) Scheduler {
    var s = Scheduler{ .tasks = tasks.ptr, .capacity = tasks.len, .count = 0, .current = 0 };
    return s;
}

pub fn addTask(s: *Scheduler, t: *Task) bool {
    if (s.count >= s.capacity) return false;
    s.tasks[s.count] = t;
    t.state = TaskState.ready;
    t.has_waiting_on = false;
    s.count += 1;
    return true;
}
```
`tick`: `var t: *Task = s.tasks[i];` (was `&s.tasks[i]`). `awaitTask`: `var cur: *Task = s.tasks[s.current];`. `allSettled`/`cancelAll` keep `s.tasks[i].state` (auto-deref through `*Task`). `suspend`/`cancel`/`waitAll` unchanged.
**`awaitTask` context guard (S17 ruling):** add `in_task: bool` to `Scheduler`; `schedulerInit` sets `in_task = false`; in `tick`, set `s.in_task = true` immediately before `@asyncResume(t.frame, t.arg)` and `s.in_task = false` immediately after; `awaitTask` begins with `if (!s.in_task) @panic("std.async: awaitTask called from a non-suspending context");`. This makes `awaitTask` coroutine-internal: a call from `main`/outside a running task traps instead of silently corrupting `s.tasks[s.current]`.

- [ ] **Step 2: Migrate the four scheduler fixtures** to `var pt: [N]*Task = undefined;` + `pt[i] = &t_i;` + `schedulerInit(pt[0..])`; the existing `&s.tasks[i]` handles become `s.tasks[i]` (still valid). `stdlib_async_pool_xmod` / `headerexact_xmod` / `f64align_xmod` do not use `Scheduler` — unchanged.

- [ ] **Step 3: Add `stdlib_async_handle_xmod`** — caller-handle identity fixture. Build `t0`, `t1`; `var pt: [2]*Task = [2]*Task{ &t0, &t1 };` `var s = schedulerInit(pt[0..]);` `addTask(&s, &t0); addTask(&s, &t1);` `cancel(&s, &t0);` then `waitAll`; assert `t0.state == cancelled` AND `s.tasks[0].state == cancelled` (same object), and that a `t1` that `awaitTask(&s, &t0)`s runs only after `t0` settles. Expected deterministic stdout: `4 4 20` (3× identical md5). This fixture FAILS against the by-value copy and PASSES after Task 0b.

- [ ] **Step 3b: Add `stdlib_async_await_nonctx_xmod`** — the S17 rejection fixture. A program that builds a scheduler with one task and calls `awaitTask(&s, &s.tasks[0])` from `main` (a non-suspending context). Expected: dump rc=0, gcc/link rc=0, run rc≠0 with the message `std.async: awaitTask called from a non-suspending context` (trap). Guard fixture: compiles OK; the rejection IS the assertion.

- [ ] **Step 4: Verify**

Run each `stdlib_async_*` fixture (dump rc=0 / gcc-clean / 3× md5 / run rc=0). Rebuild the seed closure and confirm the compiler fixed point is UNMOVED; run the corpus gate (zero class movement).

- [ ] **Step 5: Commit**

```bash
git add sf/src/std_async.zig repro/mi_matrix/stdlib_async_sched_xmod repro/mi_matrix/stdlib_async_oom_xmod repro/mi_matrix/stdlib_async_await_xmod repro/mi_matrix/stdlib_async_cancelall_xmod repro/mi_matrix/stdlib_async_handle_xmod repro/mi_matrix/stdlib_async_await_nonctx_xmod
git commit -m "fix(std.async): addTask stores *Task + awaitTask non-suspending guard (Track4 S14/S17)"
```

---

### Task 0c: Pin the switch-expression string-literal-prong slice corruption + coverage (I)

**Files:**
- Create: `repro/mi_matrix/switch_str_literal_prong_xmod/main.zig` (single-module RED)
- Create: `repro/mi_matrix/switch_str_literal_prong_xmod_xmod/main.zig`, `.../mid.zig` (cross-module RED)
- Create: one corpus fixture per OTHER confirmed-affected construct (Step 3)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` only if a fixture is a compile-fail (expected: none)

**Interfaces:**
- Consumes: nothing.
- Produces: tracked RED fixtures (part of the corpus) that pin the bug, plus an audit of every construct that can be corrupted/trimmed the same way.

- [ ] **Step 1: Single-module RED fixture.** `switch_str_literal_prong_xmod` — a function returning `switch (tag) { .A => "alpha\r\n", .B => "beta\r\n" }` typed `[]const u8`; print both prongs; the header declares the bug + RED/GREEN (mirror `repro/mi_matrix/switch_expr_payload_capture_xmod`'s header style). RED today: each prong prints only its first byte.

- [ ] **Step 2: Cross-module RED fixture.** `switch_str_literal_prong_xmod_xmod` — the same switch living in a NON-last module (imported then followed by another module), proving after the fix that the failure cannot occur cross-module either. Include a last-module sibling so the coroutine/step grouping is exercised too.

- [ ] **Step 3: Coverage audit.** Enumerate every construct where a string/array literal coerces to a slice and could be trimmed/corrupted the same way — at minimum: string literals in `if`/`else` expressions, in error-union payload positions, in struct-field initializers, as function-call arguments, in nested switches, in payload-capture prongs, and plain `array → slice` coercions. For each CONFIRMED-affected construct, add a corpus fixture (RED header). Record confirmed-UNAFFECTED constructs in the report with evidence. This audit IS the task's main deliverable.

- [ ] **Step 4: Corpus.** All new fixtures are auto-included by `scripts/corpus/list_corpus_dirs.sh`; run the classifier and record the class deltas (expect new compile-clean dirs whose RUNTIME output is wrong — they classify OK at the gcc gate but fail a runtime assert; note that distinction explicitly).

- [ ] **Step 5: Commit.** `git add repro/mi_matrix/switch_str_literal_prong_xmod* ...` + `git commit -m "test(async): pin switch-expression string-prong slice corruption (Track4 S19 I)"`.

### Task 0d: Fix the switch-expression string-prong `string_to_slice` length (F)

**Files:**
- Modify: `sf/src/lower.zig` (and `sf/src/semantic_analyzer.zig` as needed)
- Modify: the Task 0c fixtures (RED→GREEN)
- Modify: `examples/z98/mud_server/demo/canonical_client_expected.txt` + `README.md` (re-captured)
- Modify: `examples/z98/rogue_mud/demo/*` only if the fix changes the rogue captures

**Interfaces:**
- Consumes: Task 0c fixtures.
- Produces: the fix; every Task 0c fixture GREEN; the affected Task 1 goldens re-captured. The self-emission fixed point MOVES.

- [ ] **Step 1: Fix.** In `sf/src/lower.zig` `applyCoercion` → `CoercionKind.string_to_slice` (`:6623-6638`) the slice length is the literal's length ONLY when `coercion.node_idx` is an `AstKind.string_literal`; on the switch-expression prong path the coercion is keyed on the prong/wrapper node (`sf/src/semantic_analyzer.zig:1980` `tryRecordCoercion(self, prong.child_0, bt, unified)`), so it defaults to `sllen = 1`. Fix by keying the coercion on the actual string-literal node (or by recovering the literal length from the prong value in `applyCoercion`). Do NOT change unrelated coercion kinds.

- [ ] **Step 2: GREEN.** Every Task 0c fixture now prints the full strings; re-run each (dump rc=0 / gcc-clean / deterministic) and flip its header RED→GREEN.

- [ ] **Step 3: Re-capture the affected Task 1 goldens.** The fix changes the mud_server client bytes (`G` → `Goodbye!`); re-capture `examples/z98/mud_server/demo/canonical_client_expected.txt` (and `canonical_expected.txt` if the server stdout changes) and update the README md5s. Verify whether the rogue captures change (the feeds may not hit `getDirectionString`); if they do, re-capture and update.

- [ ] **Step 4: Fixed point + corpus.** Rebuild the two-hop closure; record the NEW fixed point; run the corpus gate and record the class movement (the Task 0c RED fixtures flip to GREEN output). Seed rotation is Task 6.

- [ ] **Step 5: Commit.** `git commit -m "fix(lower): recover string-literal length on switch-prong slice coercion (Track4 S19 F)"`.

### Task 0e: Declare + pin the residual string→slice gaps (S20 inference, S21 error-union payload) (I)

**Files:**
- Create (runtime-RED, corpus): `repro/mi_matrix/switch_unannotated_str_xmod/main.zig`, `repro/mi_matrix/switch_unannotated_diffstr_xmod/main.zig`, `repro/mi_matrix/if_unannotated_str_xmod/main.zig`, plus a cross-module `..._xmod_xmod` variant of each (switch/if in a NON-last module)
- Create (compile-FAIL, corpus): `repro/mi_matrix/errunion_payload_str_xmod/main.zig`, `repro/mi_matrix/opt_payload_str_xmod/main.zig`, plus call-arg / var-init / struct-field payload variants
- Modify: `repro/mi_matrix/switch_expr_payload_capture_xmod/main.zig` (header RED→GREEN — it is GREEN now)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add the S21 compile-fail dirs; bump the header)
- Create/declare: a fixture OR an explicit known-issue entry for the Task 0c-reported bare-plain-enum-literal mis-lowering and array-of-slices literal emission gaps

**Interfaces:**
- Consumes: nothing.
- Produces: tracked declarations (fixtures + `EXPECTED_FAIL.md`) of EVERY confirmed residual gap. No `sf/src` change; no fix.

- [ ] **Step 1: S20 runtime-RED fixtures.** Un-annotated expression positions: `var s = switch (c) { .A => "alpha\r\n", .B => "beta\r\n" };`, a differing-length variant, and `var s = if (c) "alpha\r\n" else "beta\r\n";`. Each prints `s` + `s.len` and asserts the full string/length (so RED = run rc≠0). Add cross-module variants (expression in a non-last module).
- [ ] **Step 2: S21 compile-FAIL fixtures.** `fn f() E![]const u8 { return "alpha\r\n"; }` and the `?[]const u8` analogue, plus call-arg / var-init / struct-field payload positions. RED = dump rc≠0 or gcc FAIL; add each to `EXPECTED_FAIL.md` with the exact diagnostic, and bump the header.
- [ ] **Step 3: Correct stale declarations.** `switch_expr_payload_capture_xmod` header RED→GREEN. Declare the Task 0c-reported enum-literal and array-of-slices gaps (fixture or known-issue entry).
- [ ] **Step 4: Corpus + classify.** All new dirs are auto-listed; run the classifier and record class deltas (runtime-RED dirs classify OK at the gcc gate; S21 dirs are FAIL/GREEN as declared).
- [ ] **Step 5: Commit.** `git commit -m "test(async): declare residual string->slice gaps S20/S21 (Track4 S20/S21 I)"`.

### Task 0f: Fix the residual string→slice gaps (S20 un-annotated inference, S21 error-union/optional payload) (F)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`
- Modify: the Task 0e fixtures (RED→GREEN); `repro/mi_matrix/EXPECTED_FAIL.md` (remove the S21 dirs)
- Modify: any golden the fix changes

**Interfaces:**
- Consumes: Task 0e fixtures.
- Produces: both residual gaps closed; every Task 0e fixture GREEN (or its declared state removed). Fixed point MOVES.

- [ ] **Step 1: S20 fix.** In the `switch`/`if` expression resolvers (`sf/src/semantic_analyzer.zig`), when there is NO expected type, unify string-literal prongs to `[]const u8` (peer-type resolution) and record the `string_to_slice` coercion on each prong node — not the first prong's `*const [N:0]u8`.
- [ ] **Step 2: S21 fix.** In `sf/src/lower.zig` `materializeInto`'s payload path (`:2032-2043`) apply the inner `string_to_slice` coercion to the payload BEFORE the `wrap_error_ok`/`wrap_optional` layer.
- [ ] **Step 3: GREEN.** Flip every Task 0e fixture GREEN; remove the S21 dirs from `EXPECTED_FAIL.md`; re-run the classifier.
- [ ] **Step 4: Re-capture affected goldens.** If any example output changes, re-capture and update the demo READMEs. Rebuild the two-hop closure; record the NEW fixed point. Seed rotation is Task 6.
- [ ] **Step 5: Commit.** `git commit -m "fix(lower/sema): close residual string->slice gaps S20/S21 (Track4 S20/S21 F)"`.

### Task 0g: Declare + pin the residual latent risks (F-M4, error[3043], F-M3, T0-M2) (I)

**Files:**
- Create (runtime-RED, corpus): `repro/mi_matrix/nonliteral_ptr_to_slice_xmod/main.zig` (F-M4)
- Create (compile-FAIL, corpus): `repro/mi_matrix/taskptr_field_store_xmod/main.zig` (T0b `error[3043]`)
- Create (characterization, corpus): `repro/mi_matrix/unannotated_infer_samelength_xmod/main.zig`, `repro/mi_matrix/unannotated_infer_stmtexpr_xmod/main.zig` (F-M3)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add the `error[3043]` dir; bump header)
- Modify: plan/spec notes marking T0b-M1 by-design and D-M1/D-M2/D-M3 closed

**Interfaces:**
- Consumes: nothing.
- Produces: tracked declarations (fixtures + `EXPECTED_FAIL.md`) of every remaining latent risk. No `sf/src` change; no fix (that is Task 0h).

- [ ] **Step 1: F-M4 fixture (runtime-RED).** Exercise a NON-literal `*const u8` → `[]const u8` coercion through `materializeInto`'s no-layer path (`sf/src/lower.zig:2029-2035`) so `applyCoercion` defaults `sllen = 1`. Print the slice + its `.len` and assert the real length (RED = length 1). Header declares the mechanism + RED/GREEN.
- [ ] **Step 2: `error[3043]` fixture (compile-FAIL).** `s.tasks[i].cancel_requested = true` on a `[*]*Task` (`lowerFieldStore` unwraps one pointer level → `*Task`, not a struct → `iceFieldStoreUnsupported`). Add to `EXPECTED_FAIL.md` with the exact diagnostic; bump the header.
- [ ] **Step 3: F-M3 characterization fixtures.** Un-annotated `var s = switch (c) { .A => "abc", .B => "xyz" };` (same-length) and a statement-position literal if-expr; assert the inferred type behaves as a slice (`s.len` works). These are GREEN today — they pin the new inference breadth.
- [ ] **Step 4: Record the closed/by-design items** in the report: T0b-M1 (`in_task` public) by-design; D-M1/D-M3 cosmetic/closed; D-M2 fixed in Task 0f; T0-M2 is a latent invariant dependency (not currently reachable) to be made impossible in Task 0h.
- [ ] **Step 5: Corpus + classify + commit.** `git commit -m "test(async): declare residual latent risks F-M4/error3043/F-M3 (Track4 S22 I)"`.

### Task 0h: Fix the residual latent risks (F-M4, error[3043], F-M1, T0-M2) (F)

**Files:**
- Modify: `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/main.zig`
- Modify: the Task 0g fixtures (RED/FAIL→GREEN); `repro/mi_matrix/EXPECTED_FAIL.md` (remove the `error[3043]` dir)
- Modify: any golden the fix changes

**Interfaces:**
- Consumes: Task 0g fixtures.
- Produces: every latent risk closed; Task 0g fixtures GREEN. Fixed point MOVES.

- [ ] **Step 1: F-M4 fix (A1 root cause — operator ruling).** Type string literals as `*const [N:0]u8` (Zig langref `*const [N]T to []const T`; Z98 spec `docs/reference/Language_Spec_Z98.md:72,384`) instead of the current bare `*const c_char` (`sf/src/semantic_analyzer.zig:2064-2065`; mirror in `sf/src/lower.zig:2408`). Consequences to verify: (a) `"abc"` AND `const p = "abc"` carry the length in the type and coerce via `array_to_slice` with the REAL length; (b) a bare `*const u8`/`*const c_char` → `[]const u8` is correctly rejected, not silently length-1; (c) the `materializeInto` synthesis (`lower.zig:2029-2035`/`:2048-2050`) applies only where the source is array / array-pointer (length known). Re-verify the S21 fixtures still pass (literal payloads). This is a broad change — string literals appear everywhere — so the corpus sweep in Step 5 is mandatory.
- [ ] **Step 2: `error[3043]` fix.** In `sf/src/lower.zig` `lowerFieldStore` (`:1740-1831`) handle a `[*]*T` element base (unwrap the element pointer so `s.tasks[i].field = v` resolves to the struct). Remove the `cancelAll` local-`*Task` workaround in `sf/src/std_async.zig` once the direct form works.
- [ ] **Step 3: F-M1 guard.** In `sf/src/semantic_analyzer.zig:2000`, guard the `astStoreNodeAt(prong.child_0)` read with `prong.child_0 != 0`.
- [ ] **Step 4: T0-M2.** In `sf/src/main.zig` (grouped-slot construction `:1168-1197`), make the uninitialized-tail impossible (write a sentinel or advance `ctx.lir_slots.len` only by the written count).
- [ ] **Step 5: GREEN + FULL corpus regression sweep + fixed point + commit.** Flip the Task 0g GREEN fixtures GREEN; move `nonliteral_ptr_to_slice_xmod` to a compile-reject (`EXPECTED_FAIL.md`) since bare-pointer→slice is now correctly rejected; remove the `error[3043]` dir from `EXPECTED_FAIL.md`; re-capture affected goldens. **Run the FULL corpus sweep at `-s0` (`bash scripts/corpus/list_corpus_dirs.sh`, classify by gcc exit code) and compare the per-dir class map against the pre-fix baseline `641 = 599 OK / 37 GREEN / 4 FAIL / 1 ICE`** — the ONLY acceptable movements are the intended ones (F-M4 fixture FAIL/ICE, `error[3043]` dir OK, plus the `error[3043]`-related flips); ANY other movement is a regression to STOP on. Also run `check_emit_support.sh` (5/5), the 4-MD5 gates, and `verify_upgraded.sh` (`CLOSEOUT OK`). Rebuild the two-hop closure and record the NEW fixed point. Seed rotation is Task 6. `git commit -m "fix(sema/lower): string literals typed *const [N:0]u8; close F-M4/error3043/F-M1/T0-M2 (Track4 S22 F)"`.

### Task 0i: Exhaustive investigation of the Task 0h residuals (I)

> **Task 0h status: NEEDS FIXES** (review Critical C1) — its commit `5b9208c7` is on the branch but incomplete; Task 0i investigates and Task 0j fixes. Do NOT re-baseline anything in Task 0i.

**Files:**
- Create (corpus): fixtures pinning each confirmed residual (bare-pointer→slice must frontend-reject; the A1 warning-regression repro; the M4 reachability case)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` as needed
- No `sf/src` change; **no re-baseline applied**

**Interfaces:**
- Consumes: Task 0h's commit `5b9208c7`.
- Produces: an exhaustive, evidence-backed investigation (report + fixtures) of every residual; the exact fix set for Task 0j.

- [ ] **Step 1: C1 duplicate block.** Confirm `sf/src/type_registry.zig:1257-1263` is a duplicate ptr→slice assignability block that still returns true for a bare `*const u8`/`*const c_char` → `[]const u8`, making the A1 `:1231-1243` edit a no-op. Determine whether `:1261-1262` can be safely deleted (grep for any reliance, e.g. legacy C-interop `*const c_char`→slice). **If it cannot be deleted, document exactly why in the report — do NOT mark it minor.**
- [ ] **Step 2: Frontend rejection.** Confirm that after removing the duplicate the mismatch is emitted only as `warning[3000]` (`semantic_analyzer.zig:2993`, `level=1`) and does not stop emission. Identify the exact contexts (var-decl / if / switch / return) that must become a **hard error** (0 `.c`), and build a fixture proving the frontend rejects (not gcc).
- [ ] **Step 3: A1 warning regression.** Enumerate EVERY emitted-C warning category and count introduced by the A1 string-literal typing across the corpus + the example programs (compare pre-`5b9208c7` vs post). Identify the emission mechanism (the `string_const` temp is now C pointer-to-array `unsigned char (*)[N]`) and the fix options (decay the temp to a plain pointer vs cast at use sites). Quantify per program (e.g. json_parser 1→60).
- [ ] **Step 4: M4 reachability.** Determine whether `applyCoercion`'s `array_to_slice` `arr_len = 1` default (`lower.zig:6627`) is reachable; if so, pin it.
- [ ] **Step 5: 4-MD5 runtime proof (MANDATORY before any re-baseline).** Run the four gate programs (gol / lisp / json / mud) under the pre-`5b9208c7` and post-`5b9208c7` compilers and prove their **runtime output is byte-identical** (or document any difference precisely). A new 4-MD5 baseline may only be recorded after this proof.
- [ ] **Step 6: Commit** the fixtures + report. `git commit -m "test(async): investigate Task 0h residuals C1/frontend/warnings/M4 (Track4 S23 I)"`.

### Task 0j: Fix the Task 0h residuals (F)

**Files:**
- Modify: `sf/src/type_registry.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig` (as the Task 0i findings dictate)
- Modify: the Task 0i fixtures; `repro/mi_matrix/EXPECTED_FAIL.md`
- Modify: `docs/sf/QUICK_REF.md` (4-MD5 re-baseline, only after the Step 5 runtime proof)

**Interfaces:**
- Consumes: Task 0i findings.
- Produces: C1 closed; type errors rejected in the **frontend**; A1 warning regression fixed; 4-MD5 re-baselined with runtime proof; M4 hardened. Fixed point MOVES.

- [ ] **Step 1: C1.** Delete/dedupe `type_registry.zig:1261-1262` (or apply the Task 0i-documented alternative if deletion is unsafe). Verify `typeRegistryIsAssignable(*const u8, []const u8) == false`.
- [ ] **Step 2: Hard frontend error.** Make the impossible-coercion case a hard error (0 `.c`, `error[3000]`) in the Task 0i-identified contexts. Verify the fixture is frontend-rejected.
- [ ] **Step 3: Warnings.** Fix the emitted-C pointer-type warnings (Task 0i's chosen mechanism). **Gate:** `gcc -m32 -std=c89 -O0 -Wall -Wextra -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc> -fsyntax-only` over the corpus + examples at warning parity with pre-`5b9208c7` (only the 1 pre-authorized `fwrite` carve-out).
- [ ] **Step 4: 4-MD5.** Record the new baseline in `docs/sf/QUICK_REF.md` ONLY after the Task 0i runtime proof.
- [ ] **Step 5: M4.** Harden the `arr_len = 1` default.
- [ ] **Step 6: Sweep.** Full corpus (`-s0`) with only intended movements; the warning gate; `check_emit_support.sh` 5/5; 4-MD5 gates; `verify_upgraded.sh` CLOSEOUT OK; two-hop fixed-point closure. Seed rotation is Task 6. Commit.

### Task 0k: Classify every warning — valid Z98 vs invalid (I) — **STOP after this task**

> Operator ruling: do NOT narrow/suppress warnings. First understand what each warning is about and whether the underlying construct is legitimate Z98 or invalid Zig. **No fixes and no re-baseline in this task; STOP and present the classification before Task 0l.**

**Files:**
- Create (corpus): fixtures pinning each classified construct (the 3 pointer-warning emission shapes; representative `warning[3000]` cases incl. the compiler's own)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` as needed
- No `sf/src` change; no re-baseline

**Interfaces:**
- Consumes: Task 0h `5b9208c7`, Task 0i `caa8e56d`.
- Produces: a per-warning classification, the A1-induced-vs-pre-existing split, the correct C-model decision for `*const [N]u8`, and the Task 0l fix set.

- [ ] **Step 1: `-Wincompatible-pointer-types` (A1, +1360).** For each emission shape (`"abc"`→`unsigned char (*)[N]`; `(*)[N]`→`char*`; `(*)[N]`→`unsigned char*`; the `strtod` arg), state the underlying Zig and confirm it is valid Z98; pin the exact C-emission defect; decide the correct C model for `*const [N]u8` (decay the temp to a plain pointer vs pointer-to-array + casts) and whether A1's type model is right or the emitter must change.
- [ ] **Step 2: `warning[3000]` — EVERY case (the compiler's 19 + the corpus ~89).** For each, classify **(a) valid Z98, the warning is a type-checker false positive** (fix accuracy) or **(b) invalid Zig that must be a hard `error[3000]`** (0 `.c`). Cite the exact construct and source location. Do NOT mark any as minor.
- [ ] **Step 3: A1-induced vs pre-existing.** Diff the `[3000]` set between pre-A1 `97cd5a03` and post-A1 `958a5e0f` (and post-deletion `ed206028`) so we know exactly what A1 changed.
- [ ] **Step 4: Runtime correctness** of each valid-but-warned case — does the tolerated mismatch actually produce correct code?
- [ ] **Step 5: Fixtures + report + commit.** `git commit -m "test(async): classify warnings valid-vs-invalid Z98 (Track4 S24 I)"`. **STOP and present.**

### Task 0l: Investigate the false-positive `warning[3000]` fix (I)

> Operator ruling (S25): the 0l work is a SERIES, ordered below; the hard-error promotion is LAST. Do the false-positive fix FIRST. This I task exists because the fix is not yet proven ultra-clear; if it proves trivially clear, collapse it into Task 0m and say so.

**Files:** fixtures + report only. No `sf/src` change; no re-baseline.
**Consumes:** Task 0k's classification (48 `(a)` valid-Z98 false positives — Task 0k said 49; `repro/field_store_tagged` was ruled a TRUE POSITIVE in Task 0l and its fixture fixed, so it is not `(a)`: self 12 — slice `.ptr`→`[*]T` (spec:68), `bool` from `and`/`or` where the checker returns `void` (`semantic_analyzer.zig:1639-1640`, `c89_emit.zig:745`), `undefined`→many-ptr; corpus 36).
**Produces:** the exact, minimal fix set for each `(a)` family (where the checker mis-types), with evidence, and the Task 0m design.
- [ ] Per `(a)` family: locate the checker mis-type (e.g. `and`/`or` result type), confirm real Zig accepts the construct, and specify the fix. Determine whether one fix covers several families.
- [ ] Fixtures pinning each family (GREEN once 0m lands). Report + commit. **No re-baseline.**

### Task 0m: Fix the false-positive `warning[3000]` type-checker cases (F)

**Files:** `sf/src/semantic_analyzer.zig` (+ `c89_emit.zig` if the `and`/`or` type is set there) per Task 0l; Task 0l fixtures.
**Produces:** the 48 `(a)` cases no longer warn (the checker returns the right types). The 12 `(b)` are still tolerated here (promotion is Task 0q, LAST). Self-compile stays gcc-clean with the `[3000]` count reduced by the fixed families; corpus warning census reflects only the fixed families. Fixed point MOVES. No re-baseline yet.
- [ ] Apply the Task 0l fix; verify each fixture no longer warns; self-compile closure; corpus class map; commit.

### Task 0n: Migrate the compiler's implicit enum→int sites to `@enumToInt` (F)

> Separate task per the ruling. `@enumToInt` is available (Z98 spec:298; used throughout `sf/src`). Verify the emitted C is accurate for the builtin usage.

**Files:** the 7 self-compile sites (`sf/src/semantic_analyzer.zig:1190,1197`; `sf/src/lower.zig:3093,3618,3768,3771,3892`) — wrap the implicit enum→int reads in `@enumToInt(...)`; plus any other non-self site the classification names.
**Produces:** no implicit enum→int remains in the compiler source; the explicit `@enumToInt` conversion is used. **Verify the emitted C is correct for the builtin usage** (inspect the emitted `.c` for a representative site and run the affected programs). Self-compile closure; corpus class map. Fixed point MOVES.
- [ ] Migrate the 7 sites; build; confirm the 7 `[3000]` warnings are gone (they were `(b)`, not fixed by 0m) and nothing else changed; verify emitted C + runtime; commit.

### Task 0o: Fix the pre-existing `strtod` null-optional warning (F)

**Files:** `sf/src/...` (the null-optional `?[*]const c_char` emission path) + a fixture.
**Produces:** the pre-existing `passing argument 2 of 'strtod'` warning gone (`json_parser` back to its non-strtod baseline). Not A1-caused; independent. Fixed point MOVES.
- [ ] Fix; verify json_parser warning count; corpus; commit.

### Task 0o2: Fix the `json_parser` `strtod` declaration + corpus expected-warning repro (F)

> Operator S25 directive: "lets fix the example but in corpus lets declare (if they are not already) the offending syntax as a repro of a expected warnings that will produce ilegal C." Scope ruling (B): fix all three canonical `examples/z98/*` copies; leave `examples/zig0/*` (outside the canonical corpus); add a NEW corpus fixture.

**Files:** the `endptr` declaration in `examples/z98/json_parser/file.zig`, `examples/z98/json_parser_upgraded/file.zig`, `examples/z98/json_parser_workaround/file.zig`; a new `repro/mi_matrix/` fixture; `repro/mi_matrix/EXPECTED_FAIL.md`.
**Produces:** the example's `strtod` `endptr` declaration corrected from `?[*]const c_char` (= `const char*`) to the `char**` shape (candidate `?*[*]c_char`, confirmed by an emission test) in all three canonical `examples/z98/*` copies; `examples/zig0/*` left as-is and declared; a new corpus fixture carrying the offending syntax (a wrong extern declaration + a NON-NULL argument) declared in `EXPECTED_FAIL.md` as an EXPECTED WARNING that produces non-conforming C (`gcc -Wincompatible-pointer-types`). Fixed point UNMOVED (example + corpus only, no `sf/src` change) unless the emission test proves an `sf/src` change necessary.
- [ ] Confirm the correct `char**` Z98 type by emission test; fix the three `examples/z98/*` declarations; verify the warnings drop for both null and non-null args; runtime unchanged (`json_parser` stdout md5 `8bda3d5a…`); `CLOSEOUT OK`.
- [ ] Add the offending-syntax corpus fixture (non-null `endptr`); declare the expected warning in `EXPECTED_FAIL.md`; verify auto-listed + census.

### Task 0p: Decay the `string_const` temp emission (F)

**Files:** `sf/src/c89_emit.zig` (emit the `string_const` result temp as a plain element pointer, keeping the LIR/sema type `*const [N]u8` — `materializeInto` classifies on it and the slice length is a separate temp).
**Produces:** the +1360 `-Wincompatible-pointer-types` gone; warning gate back to the pre-`5b9208c7` 144 baseline; runtime byte-identical (Task 0i proved it). Fixed point MOVES.
- [ ] Decay in emission; warning gate; runtime proof; corpus; commit.

### Task 0q: Promote the 12 `(b)` invalid-Zig cases to hard `error[3000]` (F) — **LAST**

> Real Zig settles all 12 as invalid (langref coercion test suite: no `*T`→`[*]T`; no array elem/len coercion; no superset→subset error coercion; enum→int only via `@intFromEnum`/`@enumToInt`). This is the FINAL step; it must not precede 0m-0p.

**Files:** `sf/src/semantic_analyzer.zig` (`:2984` var-decl, `:1872` assignment, `:1407-1430` return, `:1561` call-arg) — level 0 for the `(b)` shapes ONLY; `sf/src/type_registry.zig` (dedupe `:1257-1263`); the Task 0k/0i fixtures; `EXPECTED_FAIL.md`; `QUICK_REF.md` (4-MD5, after runtime proof).
**Produces:** the 12 `(b)` cases (7 self enum→int sites + 5 corpus dirs) are hard `error[3000]` (0 `.c`); the 48 `(a)` are NOT caught (scoped); self-compile stays green (the 7 enum sites are already `@enumToInt` from 0n); the F-M4 fixture frontend-rejects. Fixed point MOVES; seed rotation at Task 6.
- [ ] Dedupe `type_registry.zig:1257-1263`; raise the 4 sites to level 0 **scoped to the `(b)` shapes**; verify the `(a)` corpus census is unchanged and self-compile is green; full corpus + warning gate + 4-MD5 + `CLOSEOUT OK`; commit.

### Task 0q2: Investigate the enum→int return/call-arg migration feasibility (I)

> Operator S25 (m0480): after Task 0q, do an I task FIRST to determine whether the compiler's own implicit enum→int sites at return/call-arg can be migrated to `@enumToInt` so the shape can be promoted to a hard `error[3000]`. The `*T`→`[*]T` half is **NOT** in scope — its compiler reliance is the valid array→pointer idiom (`&arr[0]`, spec:382, explicitly allowed at call-arg/return), so promoting it risks rejecting legal Z98. The genuine gap is implicit enum→int at return/call-arg.

**Files:** report + fixtures only. No `sf/src` change; no re-baseline.
**Consumes:** Task 0q's residual (return `:1430` + call-arg `:1509/:1583` promote 3 of 5 shapes; `full=false` excludes `*T`→`[*]T` and enum→int).
**Produces:** the exact, exhaustive list of the compiler's own implicit enum→int sites at return/call-arg (candidates: `sf/src/lower.zig:4007,5686,5752`; `sf/src/parser.zig:1715,1722,1725` — `itoa(value: u32)` called with bare `AstKind` enum fields; `symbol_registrator.zig` already uses explicit `@enumToInt`), and a determination of whether migrating each to `@enumToInt` (a) is mechanically safe, (b) leaves self-compile green, and (c) enables promoting enum→int at return/call-arg without breaking the valid `&arr[0]` array→pointer idiom. State the exact fix set for a follow-up F task.
- [ ] Enumerate every self enum→int return/call-arg site (exhaustive, with evidence); test a scratch migration; report whether it is really possible without issue. **No `sf/src` change; no re-baseline.**

### Task 0q3: Migrate the compiler's enum→int call-arg sites + promote enum→int at return/call-arg (F)

> Operator S25 (m0487): proceed with the F task — Task 0q2 proved it feasible (scratch build green, self-compile green, enum→int promotable independently of `*T`→`[*]T`).

**Files:** the 7 compiler call-arg enum→int sites (`sf/src/lower.zig:3914,4007,5686,5752`; `sf/src/parser.zig:1715,1722,1725`) → `@intCast(u32, @enumToInt(...))`; `sf/src/semantic_analyzer.zig:2612` (drop the `full and` guard so enum→int is promoted at return/call-arg); `EXPECTED_FAIL.md`; `QUICK_REF.md` (4-MD5, after runtime proof).
**Produces:** enum→int is a hard `error[3000]` at return/call-arg (in addition to var-decl/assignment); the compiler's own 7 call-arg sites migrated; self-compile stays green (48 `.c`, 0 `[3000]`); `*T`→`[*]T` stays tolerated at return/call-arg (declared, out of scope — see Task 0q2); the 48 `(a)` remain uncaptured. Fixed point MOVES. No re-baseline; seed rotation at Task 6.
- [ ] Migrate the 7 sites; drop the `full and` guard at `:2612`; verify self-compile green + closure, the `(a)` census 39/0 unchanged, the `(b)` corpus dirs still hard-error, `*T`→`[*]T` still compiles at return/call-arg, 4-MD5 byte-identical, class map unchanged, `CLOSEOUT OK`; commit.

### Task 1: Baseline, reference compiler, and pre-conversion golden captures

**Files:**
- Create: `examples/z98/rogue_mud/demo/canonical_feed.txt`, `examples/z98/rogue_mud/demo/canonical_move_feed.txt`, `examples/z98/rogue_mud/demo/canonical_expected.txt`, `examples/z98/rogue_mud/demo/canonical_move_expected.txt`, `examples/z98/rogue_mud/demo/README.md`
- Create: `examples/z98/mud_server/demo/canonical_feed.txt`, `examples/z98/mud_server/demo/session.sh`, `examples/z98/mud_server/demo/canonical_expected.txt`, `examples/z98/mud_server/demo/README.md`

**Interfaces:**
- Consumes: nothing (baseline task).
- Produces: a seeded reference compiler at `/tmp/t4_ref/zig1_5_clean` with `lib/std_async.zig` installed; the harness feeds and the pre-conversion `canonical_expected.txt` md5s that Tasks 2–5 must reproduce.

- [ ] **Step 1: Re-verify the baseline**

Run:
```bash
cd /workspace/znineeight
git log --oneline -1
git status --porcelain
md5sum release/seed/zig1-seed.tgz
bash scripts/corpus/list_corpus_dirs.sh | wc -l
sed -n '1p' repro/mi_matrix/EXPECTED_FAIL.md
```
Expected: HEAD `0aa5e13d` (or later); tree clean except the Track 4 docs; pre-Task-0 archive md5 `23a16154e83736cf6b636685396a124a` (seed v19); corpus `612`; header `v85`. Record the observed values. Tasks 0/0b run first and change `sf/src`, so the committed seed and fixed point will have moved — re-record the post-Task-0/0b fixed point here and in the reference-compiler build below.

- [ ] **Step 2: Build the reference compiler and install `std_async.zig`**

Run:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t4_ref
mkdir -p /tmp/t4_ref/lib
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig \
   sf/src/std_str.zig sf/src/std_mem.zig sf/src/std_math.zig sf/src/std_debug.zig \
   sf/src/std_async.zig /tmp/t4_ref/lib/
ls /tmp/t4_ref/lib/
```
Expected: `=== [seed] Done: /tmp/t4_ref ===`; nine `.zig` files listed including `std_async.zig`. If `sf/src/std_async.zig` is missing, Track 3 is not landed — STOP.

- [ ] **Step 3: Baseline the closeout gate**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean
```
Expected: verdict table all PASS and `CLOSEOUT OK`, exit 0; the five hashes of the Global Constraints. Record the exit code.

- [ ] **Step 4: Write the deterministic harness**

`examples/z98/rogue_mud/demo/README.md`:
```markdown
# rogue_mud — coroutine-conversion demo feeds

- `canonical_feed.txt` / `canonical_expected.txt` — boot + quit (`q`). Deterministic.
- `canonical_move_feed.txt` / `canonical_move_expected.txt` — move + look + quit (`d`, `l`, `q`). Deterministic.

The expected files are the PRE-coroutine-conversion captures (Track 4 Task 1)
and are the byte-identity target for the converted program.
```

`examples/z98/mud_server/demo/README.md`:
```markdown
# mud_server — coroutine-conversion demo session

`session.sh` starts the server on port 4000, drives `canonical_feed.txt`
(`look`, `north`, `quit`) from one client over `bash /dev/tcp`, captures BOTH the
server stdout (`canonical_expected.txt`) and the bytes the client receives
(`canonical_client_expected.txt`), kills the server by PID, and verifies the
port is clear. Both files are the PRE-coroutine-conversion captures (Track 4
Task 1) and are byte-identity targets for the converted program.
```

Create the feeds:
```bash
printf 'q\n' > examples/z98/rogue_mud/demo/canonical_feed.txt
printf 'd\nl\nq\n' > examples/z98/rogue_mud/demo/canonical_move_feed.txt
printf 'look\nnorth\nquit\n' > examples/z98/mud_server/demo/canonical_feed.txt
```

`examples/z98/mud_server/demo/session.sh`:
```bash
#!/usr/bin/env bash
# session.sh <mud_server_binary> <server_out_file> <client_out_file>
set -u
BIN="$1"; OUT="$2"; COUT="$3"; FEED="$(dirname "$0")/canonical_feed.txt"
port_busy() { awk 'NR>1{split($2,a,":"); if(a[2]=="0FA0" && $4=="0A") f=1} END{exit !f}' /proc/net/tcp 2>/dev/null; }
if port_busy; then echo "port 4000 already listening"; exit 1; fi
"$BIN" >"$OUT" 2>/dev/null &
SRV=$!
sleep 0.3
exec 3<>/dev/tcp/127.0.0.1/4000
# Capture the bytes the server sends to this client (client-received stream).
timeout 5 cat <&3 >"$COUT" &
READER=$!
while IFS= read -r line; do printf '%s\r\n' "$line" >&3; sleep 0.1; done <"$FEED"
sleep 0.3
exec 3>&-
wait "$READER" 2>/dev/null
sleep 0.2
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if port_busy; then echo "port 4000 still listening"; exit 1; fi
exit 0
```

- [ ] **Step 5: Capture the pre-conversion goldens**

Run:
```bash
chmod +x examples/z98/mud_server/demo/session.sh
# rogue boot
rm -rf /tmp/t4_rogue_pre && mkdir -p /tmp/t4_rogue_pre
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_pre/em main.zig)
for f in /tmp/t4_rogue_pre/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_rogue_pre/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_pre/prog /tmp/t4_rogue_pre/em/*.o
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_feed.txt > examples/z98/rogue_mud/demo/canonical_expected.txt
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt > examples/z98/rogue_mud/demo/canonical_move_expected.txt
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt examples/z98/rogue_mud/demo/canonical_move_expected.txt
# mud_server
rm -rf /tmp/t4_mud_pre && mkdir -p /tmp/t4_mud_pre/em
timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_mud_pre/em examples/z98/mud_server/main.zig
for f in /tmp/t4_mud_pre/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_mud_pre/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_mud_pre/prog /tmp/t4_mud_pre/em/*.o
bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_pre/prog examples/z98/mud_server/demo/canonical_expected.txt examples/z98/mud_server/demo/canonical_client_expected.txt; echo "session rc=$?"
md5sum examples/z98/mud_server/demo/canonical_expected.txt examples/z98/mud_server/demo/canonical_client_expected.txt
```
Expected: each program builds (dump rc=0, gcc+link rc=0); the rogue captures contain the boot banner and are 3× deterministic (re-run and compare); the mud_server session rc=0, the server-stdout capture contains `MUD server listening on port 4000` and the client-bytes capture contains the `look`/`north` responses (`You are in a dark forest…` / `A sunny clearing…`). Record the FOUR md5s (rogue boot, rogue move, mud server stdout, mud client bytes) in the respective `README.md` files. If a program does not build at the baseline, STOP and report the Track 2/3 regression.

- [ ] **Step 6: Run the corpus gate at baseline**

Run:
```bash
ok=0; green=0; fail=0
for d in examples/z98/rogue_mud examples/z98/mud_server; do
  rm -rf /tmp/t4_cor; mkdir -p /tmp/t4_cor
  timeout 120 /tmp/t4_ref/zig1_5_clean --dump-c89 --output-dir /tmp/t4_cor "$d/main.zig" >/dev/null 2>/tmp/t4_cor/err.txt; rc=$?
  if [ "$rc" -ne 0 ]; then grep -qE 'error\[' /tmp/t4_cor/err.txt && green=$((green+1)) || fail=$((fail+1)); continue; fi
  [ -z "$(ls /tmp/t4_cor/*.c 2>/dev/null)" ] && { fail=$((fail+1)); continue; }
  good=1; for f in /tmp/t4_cor/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || { good=0; break; }; done
  [ "$good" -eq 1 ] && ok=$((ok+1)) || fail=$((fail+1))
done
echo "examples OK=$ok GREEN=$green FAIL=$fail"
```
Expected: `OK=2 GREEN=0 FAIL=0`. Record the count.

- [ ] **Step 7: Commit the harness**

```bash
git add examples/z98/rogue_mud/demo examples/z98/mud_server/demo
git commit -m "test(coroutine): Track4 pre-conversion golden harness (Track4)"
```

---

### Task 2a: nested module value-position access gap — I then F (prelude exposed by Task 2)

**Origin (prelude on Track 2, exposed by Task 2, 2026-09-16).** The Task 2 Step 3 code uses `std.async.HEADER_SIZE` (Amendment 3 B2); lowering it fails with `error[3042] non-value base expression in field access` + `warning[3023] module used as value expression`. This is the pre-existing `std.async` value-position gap documented as DEFERRED in the Track-1 prelude spec (`docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md:474`, "Amendment 7, Res 4"; also `2026-09-13-std-async-design.md:407`). It blocks Tasks 2/4/5, which all read `std.async.HEADER_SIZE` (plan lines 730, 1077).

**Verified matrix (compiler fixed point `286c9011691ccd39403534019baa12c6`):**

| construct | result |
|---|---|
| `std.async.HEADER_SIZE` (scalar const, 2-level alias) | FAIL `error[3042]` + `warning[3023]` |
| `std.async.TaskState.ready` (enum member, 2-level alias) | FAIL `error[3042]` + `warning[3023]` |
| `const x = std.async; x.HEADER_SIZE` (alias-to-alias) | FAIL `error[3042]` |
| `std.async.schedulerInit(...)` (function, 2-level alias) | OK |
| `@import("std_async.zig").HEADER_SIZE` (1-level direct import) | OK |

**Preliminary upstream cause:** the lowerer's field-access path lowers the base as a value (`sf/src/lower.zig:3352`); a module base yields `TEMP_NONE` + `warning[3023]` (`:3124-3128`) then `error[3042]` (`:3356`). Module-base handling exists only for a DIRECT module ident (`:3400-3416`, functions only) and `fa_ty.kind == module_type` returns 0 (`:3420-3422`). A nested alias (`std.async`) is itself a member access on `std`, not recognized as a module reference. Sema already has a module-base case (`sf/src/semantic_analyzer.zig:659`) and the type resolver too (`sf/src/type_resolver.zig:892`), so the gap is likely in lowering.

#### Task 2a-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set.** Create `repro/mi_matrix/module_value_pos_xmod/` (the minimal repro) plus a construct matrix covering: scalar `pub const` via 2-level alias; `pub const` of other types (bool/usize/i32/array/slice/struct-value/enum-value/fn-ptr); type via 2-level alias; enum member via 2-level alias; `pub var` via 2-level alias; 3-level alias; alias-to-alias; 1-level direct import (control); module-local `pub const` (control); and positions (var-init, call-arg, return, array-size, arithmetic). Each fixture documents RED (current) + the expected GREEN contract.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) exact failing constructs + diagnostics; (Q2) full work/fail matrix; (Q3) which pass fails and where; (Q4) why functions work but values do not; (Q5) minimal fix locus; (Q6) related module-as-value / nested-alias failures; (Q7) existing error/warning codes vs a new one; (Q8) dependence on const type / nesting depth / position.
- [ ] **Step 3: Declare.** Add the fixtures to the corpus; bump `repro/mi_matrix/EXPECTED_FAIL.md` (v100→v101) for the compile-FAIL cases; record the deferred prelude-spec reference.
- [ ] **Step 4: Report + present the fix surface for Task 2a-F.** No `sf/src` change; corpus/census delta recorded.

#### Task 2a-F: fix the gap (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** the lowerer (and/or the sema/lower cooperation) so a nested module-alias value-position access resolves to the member, mirroring the direct-module path, without regressing the function path.
- [ ] **Step 2: Fixtures RED→GREEN**; full corpus sweep; `check_emit_support.sh` 5/5; self-compile closure.
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; record the new fixed point. Seed rotation stays at Task 6.
- [ ] **Step 4: Re-dispatch Task 2** (which then uses `std.async.HEADER_SIZE` as written).

**Declared residual gaps (Task 2a-F, per the standing declare-every-gap rule):** (1) a field-access/compound expression in **array-size** position (`[mid.leaf.HEADER_SIZE]u8`) is rejected with `error[20]` — nesting-independent, pinned by `repro/mi_matrix/module_value_arraysize_xmod`, out of 2a-F scope; (2) address-of a module global through a nested alias (`&mid.leaf.counter`) is unsupported (`error[3043]`, no `addr_of_global` LIR), declared in the manifest, not pinned by a fixture.

**Declared residual gaps (Task 2, per the standing rule):** (1) `main.zig` declares `ClientFrameArgs`/`ClientFrameCoroutineArgs` module-scope vars that are undefined until Tasks 3/4; the compiler tolerates undefined types in unused module-scope declarations (emit rc=0) — latent compiler leniency, recorded here and in the Task-2 report; (2) the current compiler does not persist a loop-carried local live across `@asyncSuspend`; the S10 fixture `async_frame_lifetime_xmod` uses a straight-line (unrolled) counter to avoid that pre-existing codegen gap (`npcCoroutine` is unaffected — its live-across value is the `na` parameter).

---

### Task 2: `rogue_mud` NPC AI → per-NPC coroutine (entry E1)

**Files:**
- Modify: `examples/z98/rogue_mud/lib/combat.zig:1-104`
- Modify: `examples/z98/rogue_mud/main.zig` (NPC scheduler setup + the two `updateEnemies` call sites at `:207` and `:258`)

**Interfaces:**
- Consumes: `std.async.Context`, `std.async.Scheduler`, `std.async.tick`, `@asyncFrameSize`, `@asyncInit`, `@asyncSuspend`, `sand_mod.sand_alloc`.
- Produces: `NpcArgs`, `NpcCoroutineArgs`, `npcStep(na)`, `npcCoroutine(na: *NpcArgs)`, `spawnEnemies(ctx, sched, tasks: []*std.async.Task, args: []NpcArgs, recs: []NpcCoroutineArgs, dungeon, frame_arena, path_arena) usize`, `updateEnemies(sched) FrameError!void`.

**Binding pre-step (post-0-series compiler rebuild).** The `/tmp/t4_ref` compiler built in Task 1 predates the Task 0/0b series, so its `lib/std_async.zig` is pre-0b (value-array scheduler). Rebuild it from the current seed before Task 2:
```bash
rm -rf /tmp/t4_ref && bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t4_ref
mkdir -p /tmp/t4_ref/lib
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig \
   sf/src/std_str.zig sf/src/std_mem.zig sf/src/std_math.zig sf/src/std_debug.zig \
   sf/src/std_async.zig /tmp/t4_ref/lib/
```
Gate `=== [seed] Done: /tmp/t4_ref ===`; the current fixed point is `5c24305437629da54b4e4de1ed52e0e0` (post-Task-2g-F; was `495ceae3…`). The committed goldens are unaffected (runtime byte-identical). **Pointer-array API (Task 0b):** `Scheduler.tasks` is `[*]*Task`, `schedulerInit` takes `[]*Task`, and `addTask` stores the caller's `*Task`; a task set is a `[N]*std.async.Task` pointer array whose slots are bound to `[N]std.async.Task` value storage (`pt[i] = &tasks[i]`), mirroring `repro/mi_matrix/stdlib_async_sched_xmod/main.zig:50-57`.

- [ ] **Step 1: Record the pre-conversion capture (RED baseline)**

Run:
```bash
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum
cat examples/z98/rogue_mud/demo/README.md
```
Expected: the md5 equals `examples/z98/rogue_mud/demo/canonical_move_expected.txt`. This is the invariant the converted program must reproduce.

- [ ] **Step 2: Refactor `updateEnemies` into `npcStep` + `npcCoroutine`**

In `examples/z98/rogue_mud/lib/combat.zig`, add `const std = @import("std");` after the existing imports (`:1-5`), then append:
```zig
pub const NpcArgs = struct {
    dungeon: *scenario.Dungeon_t,
    entity_idx: usize,
    arena: *sand_mod.Sand,
};

fn npcStep(na: *NpcArgs) void {
    const dungeon = na.dungeon;
    const i = na.entity_idx;
    const player_node = dungeon.entities[0];
    const enemy = &dungeon.entities[i];
    if (!enemy.active) return;

    const player_pt = point_mod.Point{ .x = player_node.x, .y = player_node.y };
    const enemy_pt = point_mod.Point{ .x = enemy.x, .y = enemy.y };

    if (pathfinding.findPath(na.arena, dungeon.*, enemy_pt, player_pt)) |path| {
        if (path.len > 0) {
            const next_step = path[0];
            const dx = @intCast(i8, @intCast(i32, next_step.x) - @intCast(i32, enemy.x));
            const dy = @intCast(i8, @intCast(i32, next_step.y) - @intCast(i32, enemy.y));
            moveEntity(dungeon, i, dx, dy);
        }
    } else {
        var dx: i8 = 0;
        var dy: i8 = 0;
        if (enemy.x < player_node.x) dx = 1
        else if (enemy.x > player_node.x) dx = -1;
        if (enemy.y < player_node.y) dy = 1
        else if (enemy.y > player_node.y) dy = -1;
        if (dx != 0) {
            moveEntity(dungeon, i, dx, 0);
        } else if (dy != 0) {
            moveEntity(dungeon, i, 0, dy);
        }
    }
}

// B3 (option a): `@asyncInit` copies an args record POSITIONALLY into the
// coroutine's parameters, so the record's fields ARE the coroutine's params
// (fixtures: `caller(out: *i32)` + `CArgs{ out }`). `npcCoroutine` therefore
// takes the `NpcArgs` pointer directly, and the record is `{ na: *NpcArgs }`.
pub const NpcCoroutineArgs = struct { na: *NpcArgs };

pub fn npcCoroutine(na: *NpcArgs) void {
    while (true) {
        npcStep(na);
        _ = @asyncSuspend(null);
    }
}

pub fn spawnEnemies(ctx: *std.async.Context, sched: *std.async.Scheduler,
    tasks: []*std.async.Task, args: []NpcArgs, recs: []NpcCoroutineArgs,
    dungeon: *scenario.Dungeon_t,
    frame_arena: *sand_mod.Sand, path_arena: *sand_mod.Sand) usize {
    var n: usize = 0;
    var i: usize = 1;
    while (i < dungeon.entity_count and n < tasks.len) : (i += 1) {
        args[n] = NpcArgs{ .dungeon = dungeon, .entity_idx = i, .arena = path_arena };
        recs[n] = NpcCoroutineArgs{ .na = &args[n] };
        const sz = @intCast(usize, @asyncFrameSize(npcCoroutine));
        // S10: root frames come from a PERMANENT arena, never the per-turn
        // temp_arena that sand_reset reclaims.
        const frame = sand_mod.sand_alloc(frame_arena, sz, 8) catch return n;
        tasks[n].frame = @asyncInit(ctx, @ptrCast([*]u8, frame), npcCoroutine, @ptrCast(*const void, &recs[n]));
        tasks[n].ctx = ctx;
        tasks[n].arg = @ptrCast(*void, &recs[n]);
        tasks[n].result = @ptrCast(*void, &recs[n]);
        tasks[n].cancel_requested = false;
        tasks[n].waiting_on = tasks[n];
        tasks[n].has_waiting_on = false;
        _ = std.async.addTask(sched, tasks[n]);
        n += 1;
    }
    return n;
}

pub fn updateEnemies(sched: *std.async.Scheduler) std.async.FrameError!void {
    try std.async.tick(sched);
}
```
Then **delete** the old `updateEnemies` body (`:63-104`); `npcStep` is that body with `na.entity_idx`/`na.arena`/`na.dungeon` substituted for the removed loop. `ctx` is unused by `npcCoroutine` because `npcStep` has no suspending callee; it is retained in the signature so `@asyncFrameSize`/`@asyncInit` share one step ABI.

- [ ] **Step 3: Wire the NPC scheduler in `main.zig`**

In `examples/z98/rogue_mud/main.zig`, add module-scope state after `local_cells` (`:26`):
```zig
const MAX_NPCS: usize = 16;
var npc_tasks: [MAX_NPCS]std.async.Task = undefined;
var npc_task_ptrs: [MAX_NPCS]*std.async.Task = undefined;
var npc_args: [MAX_NPCS]combat_mod.NpcArgs = undefined;
var npc_recs: [MAX_NPCS]combat_mod.NpcCoroutineArgs = undefined;
var npc_sched: std.async.Scheduler = undefined;
var client_frame_tasks: [5]std.async.Task = undefined;
var client_frame_task_ptrs: [5]*std.async.Task = undefined;
var client_frame_args: [5]ClientFrameArgs = undefined;
var client_frame_recs: [5]ClientFrameCoroutineArgs = undefined;
var client_cells: [5][80 * 50]ui_mod.Cell = undefined;
var client_sched: std.async.Scheduler = undefined;
// S10: root frames live in a PERMANENT arena over this 8-aligned backing,
// separate from `temp_buffer`, so `sand_reset(&temp_arena)` never reclaims a
// live coroutine frame. `[K]u64` is 8-aligned; a bare `[N]u8` is 1-aligned and
// would trip `contextInit`'s alignment @panic.
var async_storage: [32 * 1024]u64 = undefined;
```
After the enemy-placement loop (`:79-86`), bind the permanent arena + context and spawn:
```zig
    var k: usize = 0;
    while (k < MAX_NPCS) : (k += 1) {
        npc_task_ptrs[k] = &npc_tasks[k];
    }
    var async_arena = sand_mod.sand_init(@ptrCast([*]u8, &async_storage)[std.async.HEADER_SIZE .. 32 * 1024 * 8], true);
    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    npc_sched = std.async.schedulerInit(npc_task_ptrs[0..]);
    _ = combat_mod.spawnEnemies(async_ctx, &npc_sched, npc_task_ptrs[0..], npc_args[0..], npc_recs[0..], &dungeon, &async_arena, &temp_arena);
```
Replace both `combat_mod.updateEnemies(&temp_arena, &dungeon);` calls (`:207`, `:258`) with:
```zig
            try combat_mod.updateEnemies(&npc_sched);
```
`spawnEnemies` allocates each NPC root frame from `async_arena` (permanent) and stores `&temp_arena` as the per-NPC pathfinding scratch, so the per-turn `sand_reset(&temp_arena)` at `:208`/`:259` cannot reclaim a live frame.

- [ ] **Step 4: Rebuild, run, and verify the byte-identity invariant**

Run:
```bash
rm -rf /tmp/t4_rogue_new && mkdir -p /tmp/t4_rogue_new
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_new/em main.zig) >/tmp/t4_rogue_new/em/stderr.log 2>&1; echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_rogue_new/em/stderr.log 2>/dev/null || true
for f in /tmp/t4_rogue_new/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_rogue_new/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_new/prog /tmp/t4_rogue_new/em/*.o; echo "link rc=$?"
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_new/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
timeout 30 /tmp/t4_rogue_new/prog < examples/z98/rogue_mud/demo/canonical_feed.txt | md5sum
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt
```
Expected: emit/link rc=0; zero `error[3017/3018/3019/3046]`/`PANIC` lines in `em/stderr.log` (the compiler writes diagnostics to stderr — there is no `em/dump.log`); all three move runs print the same md5 and it equals `canonical_move_expected.txt`; the boot run equals `canonical_expected.txt`. If the move md5 differs, apply the §Global-Constraints fallback: restore the original `updateEnemies` body and `updateEnemies(&temp_arena, &dungeon)` call sites, record an amendment, and continue to Task 3 with E1 unconverted.

- [ ] **Step 4b: S10 frame-lifetime fixture**

Create `repro/mi_matrix/async_frame_lifetime_xmod/` proving a coroutine's root frame survives an arena reset between ticks (the S10 bug). Shape: a root frame in a PERMANENT backing buffer; a coroutine whose frame holds a monotonically increasing counter across `@asyncSuspend`; the driver resets/zeroes a SEPARATE scratch buffer between ticks (mirroring `sand_reset(&temp_arena)`) and asserts the counter is preserved across N (e.g. 8) ticks. If the frame lived in the reset arena, the counter would be clobbered and the assertion traps. Run `--dump-c89` + gcc-clean + 3× identical stdout/run rc=0; record the expected stdout in the commit. This fixture FAILS if the frame is allocated from the reset arena and PASSES when it is permanent.

- [ ] **Step 5: Re-run the closeout gate**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean | tail -3
```
Expected: `CLOSEOUT OK`. If not, E1 is reverted per the fallback rule before committing.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/rogue_mud/lib/combat.zig examples/z98/rogue_mud/main.zig
git commit -m "feat(rogue): per-NPC coroutine for updateEnemies (Track4 E1)"
```

---

### Task 2b: residual codegen gaps — I then F (#9 loop-carried local, #5 &nested.global, #1 array-size)

**Origin (exposed by Task 2, 2026-09-16).** Three residual gaps were declared after Task 2a/Task 2. The dangerous one is #9: a loop-carried local live across `@asyncSuspend` is not persisted (the Task-2 S10 fixture dodged it with a straight-line counter). Tasks 3/5 carry locals across suspend (`drawToSocketCoroutine` `last_fg`/`y`/`x`; `clientCoroutine` `j`/`k`), so #9 must be closed before Task 3.

**Declared residual gaps (from Task 2a-F / Task 2, `26a2d78d`):**
1. **#1** — a non-literal / field-access expression in array-size position (`[mid.leaf.HEADER_SIZE]u8`) is rejected with `error[20]`; nesting-independent (a 1-level direct import fails identically). Pinned by `repro/mi_matrix/module_value_arraysize_xmod` (FAIL). Out of Task 2a-F scope.
2. **#5** — address-of a nested module global (`&mid.leaf.counter`) is unsupported (`error[3043]`, no `addr_of_global` LIR); declared in the manifest, not pinned by a fixture.
3. **#9 (DANGEROUS)** — a local that is live across `@asyncSuspend` is not persisted. Read-only loci: P3 `asyncLayoutFrame` (`sf/src/async_frame_layout.zig:481-519`) computes LIVE temps and adds `ASYNC_FIELD_LIVE`; the state machine saves/reloads them (`saveAllFields`/`reloadAllFields`, `sf/src/async_state_machine.zig:253-279`, called at `:562`/`:571` and `:1023`/`:1033`); P2 `asyncFrameSizeRun` (`sf/src/async_analysis.zig:684-732`) sizes the frame (step+ctx+state + params + `scanFrameLocals` at `:702`/`:381-393` + hidden tail). The suspect is the LIVE-ANALYSIS precision (P3), not the save/reload emission. Task 2b-I must pin the exact failure mode (panic vs wrong output vs mis-size).

#### Task 2b-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set.** Create `repro/mi_matrix/async_live_local_across_suspend_xmod/` (a coroutine with a loop-carried local mutated and read across `@asyncSuspend` inside a `while`; assert preservation over N ticks — runtime-RED today) and `repro/mi_matrix/module_value_addr_global_xmod/` (#5; `&mid.leaf.counter`; RED today). Keep `module_value_arraysize_xmod/` (#1) as the #1 pin. Each fixture documents RED (current) + the expected GREEN contract.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact #9 failure mode and which pass (P2 size / P3 layout / save-reload emission); (Q2) P2-vs-P3 authority for live fields; (Q3) where live locals are computed vs reserved; (Q4) is the save/reload emission correct once the live analysis is fixed; (Q5) #5 fix locus (`addr_of_global` LIR vs the field-access path); (Q6) #1 fix locus (array-size expression handling); (Q7) confirm the Task-2a-F chain-walk vs the sema `module_type` path (#2); (Q8) is `sf/src/lower.zig:1687-1704` safely removable (#6); (Q9) which gaps MUST be fixed before Task 3; (Q10) minimal fix surface + risk.
- [ ] **Step 3: Declare.** Add the fixtures to the corpus; bump `repro/mi_matrix/EXPECTED_FAIL.md` (v103→v104) for the FAIL/RED cases.
- [ ] **Step 4: Report + present the fix surface for Task 2b-F.** No `sf/src` change; corpus/census delta recorded.

#### Task 2b-F: fix #9 + #5 + #1 (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** the live-local persistence (#9) so a loop-carried local across `@asyncSuspend` is preserved; fix `&nested-module-global` (#5); fix the non-literal/field-access array-size expression (#1). No unrelated changes.
- [ ] **Step 2: Fixtures RED→GREEN**; full corpus sweep (class map delta = intended dirs only); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.
- [ ] **Step 4: Then Task 3** (which carries locals across suspend).

**Sequencing gate:** Task 3 MUST NOT start until #9 is closed (Task 2b-F landed).

---

### Task 2c: const-expression array sizes — fold + fallback diagnostic — I then F

**Origin (discovered by Task 3, 2026-09-16).** While writing the S11 fixture, Task 3 found a new gap adjacent to Task 2b-F #1 and the declared variant (e): a module-level `const CELLS = ROWS * COLS` (a const whose initializer is an arithmetic expression of other consts) used in **array-size** position is **not folded**; the compiler **silently emits invalid C** (dump rc=0, but the local array is undeclared / struct fields dropped) with no frontend diagnostic. Valid Zig must fold; an unfolable size must be a hard error, never silent invalid C.

**Verified root cause (read-only, `sf/src`):** `resolveTypeExprFull`'s `array_type` arm (`sf/src/type_resolver.zig:1109-1173`) resolves the size via `evalConstU32Full` (`:744`), which handles `int_literal`, `ident_expr`, and (Task 2b-F) `field_access` — **no `binary` case**. `const CELLS = ROWS*COLS` recurses into the initializer (`ROWS*COLS`, a `binary` node) and returns `0xFFFFFFFF`; `arr_resolved` stays false and the resolver returns `TYPE_UNDEFINED` (`:1173`) with no diagnostic. The arm already folds **inline** `add/sub/mul/div/mod` (`:1123-1139`), so only the const-behind-an-expression case is broken. `TypeResolveEnv` (`sf/src/type_resolver.zig:27-33`) has **no diagnostics handle** (`store/typereg/symbol_reg/interner/module_id` only), so the fallback diagnostic must be emitted in sema (where `self.diag` exists) or the handle threaded in.

**Operator rulings (2026-09-16):** (1) fix **variant (e)** (function-local const array size) in the **same F task** — thread the function-local const scope into the type resolver; (2) the fallback diagnostic is a **hard error** (new `ERR_3050_ARRAY_SIZE_NOT_CONSTANT`, explicit numeric per the `diagnostics.zig` convention).

#### Task 2c-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set** (`repro/mi_matrix/`, auto-listed; each documents RED-now + the GREEN contract):
  - `const_size_arith_xmod/` — module-level `const A: usize = 4; const B: usize = 4; const C = A * B; var x: [C]u8`, plus `+ - / %` and nested (`A * B + 2`) variants.
  - `const_size_member_xmod/` — `const C = mid.leaf.HEADER_SIZE * 2; var x: [C]u8`.
  - `const_size_local_xmod/` — function-local `const N = A * B; var x: [N]u8` (variant (e), now IN scope).
  - `const_size_unfoldable_xmod/` — a non-foldable size (e.g. a runtime value / call) → must be a **hard error**, never silent invalid C.
  - controls: inline `[A * B]u8` (already folds), a literal, and a direct ident const.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact failure mode and where `arr_resolved=false` flows; (Q2) why an inline expression folds but the same expression behind a `const` does not; (Q3) the fold locus; (Q4) the **diagnostic** locus (sema `self.diag` vs threading a diagnostics handle into `TypeResolveEnv`) and the code to use; (Q5) the **(e) mechanism** — how the resolver can see the enclosing function's local-const scope (`TypeResolveEnv` has none today); (Q6) the minimal fix surface + risk; (Q7) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixtures to the corpus; bump `repro/mi_matrix/EXPECTED_FAIL.md` (v105→v106) for the RED/FAIL cases; record the corpus delta.
- [ ] **Step 4: Report + present the fix surface for Task 2c-F.** No `sf/src` change.

#### Task 2c-F: fold + hard-error fallback (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fold** arithmetic const expressions (a `binary` case: `add/sub/mul/div/mod`, and `negate`) in `evalConstU32Full` / the array-size path; thread the **function-local const scope** so variant (e) folds.
- [ ] **Step 2: Add the fallback hard error** — a new `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` emitted when an array-size expression cannot be const-folded (never silent invalid C).
- [ ] **Step 3: Fixtures RED→GREEN**; full corpus sweep (class map delta = intended dirs only — any other movement is a regression to STOP on); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 4: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.

**Sequencing gate:** Task 4 MUST NOT start until Task 2c-F is landed (the plan's array-size family is closed).

---

### Task 3: `rogue_mud` per-connection broadcast → coroutine (entry E2)

**Files:**
- Modify: `examples/z98/rogue_mud/ui.zig:61-87`
- Modify: `examples/z98/rogue_mud/main.zig:277-363`

**Interfaces:**
- Consumes: `std.async.Context`, `@asyncSuspend`, `@asyncFrameSize`, `@asyncInit`; the existing `sendColorANSI` (`ui.zig:89`).
- Produces: `ui.ClientArgs`, `ui.drawToSocketCoroutine(ctx, args)`; `main.ClientFrameArgs`, `main.clientFrameCoroutine(ctx, args)`; the client scheduler in `main`.

- [ ] **Step 1: Add the suspending socket writer to `ui.zig`**

After `drawToSocket` (`:61-87`), add:
```zig
pub const ClientArgs = struct {
    sock: i32,
    rows: usize,
    cols: usize,
    cells: [*]const Cell,
};

pub fn drawToSocketCoroutine(ctx: *std.async.Context, args: *void) void {
    const ca = @ptrCast(*ClientArgs, args);
    const sock = ca.sock;
    const rows = ca.rows;
    const cols = ca.cols;
    const cells = ca.cells;

    const clear_home: []const u8 = "\x1b[2J\x1b[H";
    _ = std_net.send(sock, clear_home.ptr, @intCast(i32, clear_home.len));

    var last_fg: u8 = 255;
    var y: usize = 0;
    while (y < rows) : (y += 1) {
        var x: usize = 0;
        while (x < cols) : (x += 1) {
            const cell = cells[y * cols + x];
            if (cell.fg != last_fg) {
                sendColorANSI(sock, cell.fg);
                last_fg = cell.fg;
            }
            const char_buf: [1]u8 = [1]u8{ cell.ch };
            _ = std_net.send(sock, &char_buf[0], 1);
        }
        const nl: []const u8 = "\r\n";
        _ = std_net.send(sock, nl.ptr, 2);
        _ = @asyncSuspend(null);
    }
    const reset: []const u8 = "\x1b[0m";
    _ = std_net.send(sock, reset.ptr, @intCast(i32, reset.len));
}
```
`drawToSocket` (`:61-87`) is **left in place** so `ui.draw`-based renderers and the upgraded closeout program are untouched; the coroutine duplicates the byte sequence exactly.

- [ ] **Step 2: Add the per-client frame coroutine to `main.zig`**

Add after `broadcastOneClient` (`:363`):
```zig
pub const ClientFrameArgs = struct {
    server: *net_mod.Server,
    dungeon: *scenario.Dungeon_t,
    client_idx: usize,
    cells: [*]ui_mod.Cell,
};

// B3 (option a): the `@asyncInit` args record's fields ARE the coroutine's
// parameters. `clientFrameCoroutine` needs both the task `ctx` (to forward to
// the socket-writer coroutine) and the frame args.
pub const ClientFrameCoroutineArgs = struct { ctx: *std.async.Context, cfa: *ClientFrameArgs };

pub fn clientFrameCoroutine(ctx: *std.async.Context, cfa: *ClientFrameArgs) void {
    const sock = cfa.server.clients[cfa.client_idx].socket;

    const rows = @intCast(usize, cfa.dungeon.height) + 1;
    const cols = @intCast(usize, cfa.dungeon.width);

    buildBroadcastCells(cfa.dungeon, cfa.cells, rows, cols);

    const ca = ui_mod.ClientArgs{ .sock = sock, .rows = rows, .cols = cols,
        .cells = @ptrCast([*]const ui_mod.Cell, cfa.cells) };
    ui_mod.drawToSocketCoroutine(ctx, @ptrCast(*void, &ca));
}
```
Extract the existing body of `broadcastOneClient` (`:286-362`) into a plain helper `buildBroadcastCells(dungeon: *scenario.Dungeon_t, cells: [*]ui_mod.Cell, rows: usize, cols: usize)` that fills the **passed** `cells` buffer exactly as today (replace every `local_cells[...]` write with `cells[...]`). The coroutine path calls `buildBroadcastCells` then `drawToSocketCoroutine`. Keep `broadcastOneClient` as a thin wrapper over `buildBroadcastCells` + `ui_mod.drawToSocket` for the upgraded-closeout compatibility path, or delete it if Step 3 shows it is unused. **S11:** each client task MUST build into its OWN cells buffer — a single shared `local_cells` is corrupted when two yielding tasks interleave (one task overwrites the other's rows mid-frame). See Step 3.

- [ ] **Step 3: Drive the client scheduler from `broadcastDungeon`**

Replace `broadcastDungeon` (`:277-284`) with a version that takes the server and the client scheduler and ticks ONCE per broadcast (client tasks are bound ONCE — see Task 4 Step 1 — not re-added per broadcast):
```zig
fn broadcastDungeon(server: *net_mod.Server, sched: *std.async.Scheduler) void {
    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        if (server.clients[i].active) {
            client_frame_args[i].server = server;
        }
    }
    std.async.tick(sched) catch {};
}
```
`tick(s)` (landed signature, returns `FrameError!void`) resumes every registered client task once; `catch {}` is acceptable here because the client tasks are bounded and sized from `@asyncFrameSize` (pool exhaustion triggers the §Global-Constraints fallback and is re-checked in Task 6). Module-scope `client_frame_tasks: [5]std.async.Task` + `client_frame_task_ptrs: [5]*std.async.Task` and `client_frame_args: [5]ClientFrameArgs` are bound once in Task 4 Step 1. **S11:** `client_frame_args[i].cells` points at a per-client buffer — add `var client_cells: [5][80 * 50]ui_mod.Cell = undefined;` next to `local_cells` and bind `.cells = @ptrCast([*]ui_mod.Cell, &client_cells[i][0])`. Update the two call sites (`:210`, `:260`) to `broadcastDungeon(&server, &client_sched)` and initialize `client_sched` next to `npc_sched` in Task 2's setup block.

- [ ] **Step 4: Verify the broadcast byte-identity**

Run:
```bash
rm -rf /tmp/t4_rogue_b && mkdir -p /tmp/t4_rogue_b
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_b/em main.zig) >/tmp/t4_rogue_b/em/stderr.log 2>&1; echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_rogue_b/em/stderr.log 2>/dev/null || true
for f in /tmp/t4_rogue_b/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_rogue_b/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_b/prog /tmp/t4_rogue_b/em/*.o
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_b/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
```
Expected: emit/link rc=0; zero `error[3017/3018/3019/3046]`/`PANIC` lines in `em/stderr.log`; all three move runs reproduce `canonical_move_expected.txt`. The local (single-player) path has no connected clients, so the client scheduler is exercised only by the net variant in Task 4; the byte-identity here proves the client-task wiring did not disturb the local turn. If the md5 differs, apply the fallback for E2 (restore `broadcastOneClient`/`drawToSocket` and the original `broadcastDungeon`), record an amendment, and continue.

- [ ] **Step 4b: S11 per-client cells fixture**

Create `repro/mi_matrix/async_client_cells_xmod/` proving two yielding writers with separate cells buffers never observe each other's rows (the S11 bug). Shape: two `ClientArgs`-like tasks, each with its OWN cells buffer filled with a distinct repeating pattern; each task streams its buffer row-by-row with `@asyncSuspend` between rows into a captured output; tick the scheduler to completion; assert each captured stream equals its own pattern (no interleaved bytes). A single shared buffer FAILS (task A's later rows read task B's pattern); per-task buffers PASS. Run `--dump-c89` + gcc-clean + 3× identical stdout/run rc=0; record the expected stdout.

- [ ] **Step 5: Closeout gate + commit**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean | tail -3
git add examples/z98/rogue_mud/ui.zig examples/z98/rogue_mud/main.zig
git commit -m "feat(rogue): per-client broadcast coroutine (Track4 E2)"
```
Expected: `CLOSEOUT OK`.

---

### Task 2e: diagnostic excerpt renders the wrong source line — I then F

**Origin (surfaced by the Task 2c-F fix round, 2026-09-16).** The diagnostic renderer prints the **wrong source line** (or no excerpt). Root cause (read-only): `mem.binary_search` (`sf/src/util/mem.zig:9-25`) already returns the index of the greatest `offsets[i] <= target` (an `upper_bound - 1`), and `source_manager.zig:155` uses it correctly (`line = line_idx + 1`). But `diagnostics.zig:500-501` applies an **extra** `if (line_idx > 0) line_idx -= 1;`, so the excerpt line is one line *before* the line containing the span — observed: a `p3.zig` error at line 3 printed line 2's text, and some fixtures print no excerpt at all. This affects **every** diagnostic's excerpt (not just `error[3050]`).

#### Task 2e-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set.** Create a corpus fixture (or a small driver) that provokes diagnostics whose spans start at various positions — line start, mid-line, column 1, a multi-line span, a span on the first line (line 1, where `line_idx == 0`), and a multi-file (imported-module) diagnostic — and **capture the rendered stderr excerpt** (the source line + caret) verbatim for each. Pin the current WRONG rendering (RED) and the expected correct rendering (GREEN contract). Confirm whether the caret column/count is also off (the renderer uses `loc.col` directly as the space count).
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact off-by-one and why `line_idx -= 1` is a double subtraction; (Q2) whether `loc.line`/`loc.col` (from `sourceManagerGetLocation`) are consistent with the excerpt's `line_idx`/caret (any second off-by-one?); (Q3) why some fixtures print no excerpt (`if (l_start < l_end and l_end <= content.len)`); (Q4) the minimal fix locus; (Q5) whether `mem.binary_search`'s `target < offsets[0]` behavior (returns 0) and `target >= last offset` are correct for both callers; (Q6) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixture(s) to the corpus; record the RED/GREEN in `repro/mi_matrix/EXPECTED_FAIL.md` (v108→v109) or the appropriate known-issue location.
- [ ] **Step 4: Report + present the fix surface for Task 2e-F.** No `sf/src` change.

#### Task 2e-F: fix the excerpt lookup (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** the excerpt line lookup (remove/correct the extra decrement; fix the caret column/count if Q2 shows a second off-by-one) so every diagnostic's excerpt shows the source line containing the span, with the caret at the span.
- [ ] **Step 2: Fixtures RED→GREEN**; full corpus sweep (class-map delta = intended dirs only); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.

**Sequencing gate:** Task 4 MUST NOT start until Task 2e-F is landed.

---

### Task 2f: multi-dimensional fixed-array element access — silent invalid C — I then F

**Origin (blocked Task 4 / E3, 2026-09-16).** Task 4 Step 1 indexes `client_cells: [5][80 * 50]ui_mod.Cell` as `&client_cells[ci][0]`. The compiler lowers the outer index into an **array-typed temp** and the emitter emits an array-to-array C assignment, which is illegal C89:

```c
zT_80B7AEA1_Arr_zT_E90A7BD5_Cel zT_297;      /* array-typed temp */
zT_297 = zG_6E96A0B4_client_cells[ci];       /* array = array; invalid C89 */
```

Emit is **rc=0 with 0 target diagnostics** (silent); gcc rejects `assignment to expression with array type`. The same failure hits the rvalue `arr[i][j]`. Minimal repro: `var g: [5][4]u8; sink(@ptrCast([*]u8, &g[i][0]))` (global or local, dynamic `i`). Flat 1D arrays work. Not in `EXPECTED_FAIL.md`. Baseline HEAD `c8cfd82a` emits/links clean and reproduces both `rogue_mud` goldens ×3, so E3 introduced the failure; `client_cells` was declared in Task 3 but never exercised until Task 4.

**Verified candidate (NOT applied):** the address-of-the-row form `@ptrCast([*]ui_mod.Cell, @ptrCast(*[80 * 50]ui_mod.Cell, &client_cells[ci]))` avoids the array temp and works — but the operator ruled a **compiler fix** (this task), not an examples workaround.

**Operator ruling (2026-09-16):** add a new compiler-fix task (this I/F pair); do NOT apply the examples-only workaround or flatten `client_cells`.

#### Task 2f-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set** (`repro/mi_matrix/`, auto-listed; each documents RED-now + the GREEN contract):
  - `multiarray_index_xmod/` — `var g: [5][4]u8;` with `&g[i][0]` (dynamic `i`) and the rvalue `g[i][j]`; RED (emit rc=0, gcc FAIL `assignment to expression with array type`).
  - `multiarray_index_const_xmod/` — the constant-index form `&g[2][0]` / `g[2][3]`.
  - `multiarray_index_local_xmod/` — a function-local `[5][4]u8`.
  - `multiarray_index_3d_xmod/` — a 3-level array `[3][4][5]u8`.
  - controls: a flat 1D `[20]u8` index (already OK), and a 2D array whose element is a struct (`[5][4]Cell`) mirroring the Task 3/4 shape.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact lowering/emission path that produces the array-typed temp (`sf/src/lower.zig` index_access `:1363`/`:1509`/`:3080` and the emitter's array-temp handling `sf/src/c89_emit.zig`); (Q2) why the outer index yields an array-typed value rather than an address/element pointer; (Q3) the correct C89 shape (decay to a pointer, or emit an element address); (Q4) the minimal fix locus (lowerer vs emitter) + whether `getCTypeName`'s `Arr_*` array typedef path (`c89_emit.zig:710-761`) is involved; (Q5) whether the fix must also cover the address-of and rvalue forms and nested (3D) access; (Q6) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixtures; record the RED in `repro/mi_matrix/EXPECTED_FAIL.md` (v110→v111) or the appropriate known-issue location.
- [ ] **Step 4: Report + present the fix surface for Task 2f-F.** No `sf/src` change.

#### Task 2f-F: fix the lowering/emission (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** so a multi-dimensional fixed-array element access lowers/emits valid C89 (the outer index must not produce an array-to-array assignment).
- [ ] **Step 2: Fixtures RED→GREEN**; full corpus sweep (class-map delta = intended dirs only — any other movement is a regression to STOP on); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.

**Sequencing gate:** Task 4 MUST NOT start until Task 2f-F is landed.

---

### Task 2g: array-to-array class not fully closed — for-loop iteration + pointer-to-array — I then F

**Origin (Task 2f-F review, 2026-09-16).** Task 2f-F fixed direct multi-dimensional fixed-array element access, but the review found the **same array-to-array defect class** is still reachable, and neither residual was declared (fixture + `EXPECTED_FAIL.md` + report) as the standing rule requires:
- **(a) for-loop iteration:** `for (multiDimArray) |row|` keeps `decay = 0` and an array-typed `item_temp` (`sf/src/lower.zig:6128-6131`) — the array-to-array emission reached through iteration, so the class is not fully closed.
- **(b) pointer-to-array element access:** genuine `pp: *[4]u8; pp[0][1] = 3;` is broken (pre-existing; BASE `8a322dd9` and fix `7f9afa82` byte-identical) — a separate frontend/lowering quirk.
- **(c) field store through a multi-dim element (SILENT WRONG CODE):** `lowerFieldStore`'s `index_access` base branch (`sf/src/lower.zig:1780-1787`) builds the field base as a raw `ptr + idx` (`BIN_ADD`) on the decayed row pointer, so `gc[1][2].v = 5` scales by the **whole row** (32 B instead of 8). gcc emits only `-Wincompatible-pointer-types` (a warning) → the classifier stays OK. Reachable from the Track-4 `client_cells` (`[5][80*50]Cell`) shape. (Found by Task 2g-I Q5.)
- **(d) multi-dim array-literal init:** `assign_index` (`sf/src/lower.zig:5048`/`:5254`) assigns element arrays array-to-array. (Q5.)
- **(e) row store into a multi-dim element:** `assign_index` (`sf/src/lower.zig:1564`); `g[0] = row;` array-to-array. (Q5.)

**Operator rulings (2026-09-16):** (1) fix (a) + (b) via an I task + F task (this pair); (2) for **(b)**, check the official Zig docs — **if Zig rejects it, Z98 must too**. Verified against the Zig langref (master): `pp[0][1]` does **not** compile in real Zig — `*[N]T` supports index syntax `array_ptr[i]` but `pp[0]` yields the **element** (`u8`), not the array; the element is reached via `pp[1]` or `pp.*[1]`. Therefore **(b) is a hard `error[3000]`** (matching real Zig and Z98 spec `Language_Spec_Z98.md:32`), not a compile-clean decay. (3) **fold (c)/(d)/(e) into Task 2g-F.**

#### Task 2g-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set** (`repro/mi_matrix/`, auto-listed; each documents RED-now + the GREEN contract):
  - `multiarray_for_iter_xmod/` — `for (g) |row|` over a `[5][4]u8` (and a `[5][4]Cell`), reading/streaming each row; RED (array-to-array emission).
  - `ptr_to_array_index_xmod/` — `var pp: *[4]u8;` with `pp[0][1] = 3;` and the rvalue `pp[0][1]`; RED.
  - nested/3-D variants of the for-loop case.
  - controls: a for-loop over a **flat 1-D** array (already OK); a for-loop that only reads a scalar element.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact lowering path for a `for`-loop array item (`sf/src/lower.zig:6128-6131`) and why it keeps `decay = 0`; (Q2) the exact lowering for `pp: *[N]T` element access and why it is broken; (Q3) whether the 2f-F `decay` mechanism (`load_index{decay}`, `&(*base)[idx]`/`&base[idx]`) can be reused for both; (Q4) the minimal fix locus for each; (Q5) whether any other array-to-array producer remains (grep the emitter/lowerer for array-typed temp assignment/store); (Q6) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixtures; record the RED in `repro/mi_matrix/EXPECTED_FAIL.md` (v112→v113) or the appropriate known-issue location.
- [ ] **Step 4: Report + present the fix surface for Task 2g-F.** No `sf/src` change.

#### Task 2g-F: fix both (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** (a) the for-loop iteration array-to-array emission (reuse the 2f-F `decay` mechanism); **(b) make `pp: *[N]T` element access a hard `error[3000]`** (matching real Zig — the element is reached via `pp[1]`/`pp.*[1]`); **(c) fix the `lowerFieldStore` field-store base** so `gc[i][j].v` scales by the element, not the whole row (silent wrong code); **(d)** the multi-dim array-literal init; **(e)** the row store `g[i] = row`. Do NOT apply an examples-only workaround.
- [ ] **Step 2: Fixtures RED→GREEN** (the 2g-I fixtures + new (c)/(d)/(e) fixtures; (b) becomes the hard error); full corpus sweep (class-map delta = intended dirs only — any other movement is a regression to STOP on); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.

**Sequencing gate:** Task 4 MUST NOT start until Task 2g-F is landed.

---

### Task 4: `rogue_mud` cross-module task create/schedule/cancel (entry E3)

**Files:**
- Modify: `examples/z98/rogue_mud/main.zig:90-274` (game loop), `examples/z98/rogue_mud/lib/combat.zig`, `examples/z98/rogue_mud/ui.zig`
- Reuse: `examples/z98/rogue_mud_upgraded/demo/canonical_feed.txt` for the single-player regression only

**Interfaces:**
- Consumes: `combat.spawnEnemies`, `combat.updateEnemies`, `ui.drawToSocketCoroutine`, `main.clientFrameCoroutine`, `std.async.addTask`/`tick`/`cancel`/`cancelAll`.
- Produces: one NPC scheduler + one client scheduler bound once per program run; cancel issued on the death/disconnect/quit paths.

- [ ] **Step 1: Bind both schedulers and both task sets once**

In `main.zig`, after `async_ctx` is created, replace the Task 2 spawn block with:
```zig
    var k: usize = 0;
    while (k < MAX_NPCS) : (k += 1) {
        npc_task_ptrs[k] = &npc_tasks[k];
    }
    npc_sched = std.async.schedulerInit(npc_task_ptrs[0..]);
    _ = combat_mod.spawnEnemies(async_ctx, &npc_sched, npc_task_ptrs[0..], npc_args[0..], npc_recs[0..], &dungeon, &async_arena, &temp_arena);

    var ck: usize = 0;
    while (ck < @intCast(usize, 5)) : (ck += 1) {
        client_frame_task_ptrs[ck] = &client_frame_tasks[ck];
    }
    client_sched = std.async.schedulerInit(client_frame_task_ptrs[0..]);
    var ci: usize = 0;
    while (ci < @intCast(usize, 5)) : (ci += 1) {
        // S11: each client builds into its OWN cells buffer.
        client_frame_args[ci] = ClientFrameArgs{ .server = &server, .dungeon = &dungeon,
            .client_idx = ci, .cells = @ptrCast([*]ui_mod.Cell, &client_cells[ci][0]) };
        client_frame_recs[ci] = ClientFrameCoroutineArgs{ .ctx = async_ctx, .cfa = &client_frame_args[ci] };
        const csz = @intCast(usize, @asyncFrameSize(clientFrameCoroutine));
        const cframe = sand_mod.sand_alloc(&async_arena, csz, 8) catch return;
        client_frame_task_ptrs[ci].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), clientFrameCoroutine, @ptrCast(*const void, &client_frame_recs[ci]));
        client_frame_task_ptrs[ci].ctx = async_ctx;
        client_frame_task_ptrs[ci].arg = @ptrCast(*void, &client_frame_recs[ci]);
        client_frame_task_ptrs[ci].result = @ptrCast(*void, &client_frame_recs[ci]);
        client_frame_task_ptrs[ci].cancel_requested = false;
        client_frame_task_ptrs[ci].waiting_on = client_frame_task_ptrs[ci];
        client_frame_task_ptrs[ci].has_waiting_on = false;
        _ = std.async.addTask(&client_sched, client_frame_task_ptrs[ci]);
    }
```
`async_arena` is the PERMANENT arena bound in Task 2 Step 3 (`sand_init` over `async_storage`, `true`), so `sand_reset(&temp_arena)` cannot reclaim coroutine root frames. The landed `Task` has **no** `arena`/`arena_capacity`/`arena_used` fields — child frames are allocated from the task's `ctx` pool at await sites; all tasks share the one `async_ctx`.

- [ ] **Step 2: Replace the cancel sites**

At the client-disconnect branch (`main.zig:178-182`), insert the cooperative cancel before closing:
```zig
                    std.async.cancel(&client_sched, client_frame_task_ptrs[client_idx]);
                    dungeon.entities[client.entity_idx].active = false;
                    client.active = false;
                    net_mod.close(client.socket);
```
At game over (`main.zig:270-273`), cancel all NPC and client tasks before the break:
```zig
        if (!dungeon.entities[0].active) {
            std.io.print("You have died. Game Over.\n");
            std.async.cancelAll(&npc_sched);
            std.async.cancelAll(&client_sched);
            break :game_loop;
        }
```

- [ ] **Step 3: Verify local byte-identity and cross-module propagation**

Run:
```bash
rm -rf /tmp/t4_rogue_c && mkdir -p /tmp/t4_rogue_c
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_c/em main.zig) >/tmp/t4_rogue_c/em/stderr.log 2>&1; echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_rogue_c/em/stderr.log 2>/dev/null || true
for f in /tmp/t4_rogue_c/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_rogue_c/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_c/prog /tmp/t4_rogue_c/em/*.o
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
```
Expected: emit/link rc=0; zero `error[3017/3018/3019/3046]`/`PANIC` lines in `em/stderr.log`; both feeds reproduce their expected md5 across 3 runs. `is_suspending` must have propagated `main → combat.npcCoroutine` and `main → ui.drawToSocketCoroutine` (if not, the frame is mis-sized and the run is nondeterministic or traps). Record the observed md5s.

- [ ] **Step 4: Closeout gate + commit**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean | tail -3
git add examples/z98/rogue_mud/main.zig examples/z98/rogue_mud/lib/combat.zig examples/z98/rogue_mud/ui.zig
git commit -m "feat(rogue): cross-module task create/schedule/cancel (Track4 E3)"
```
Expected: `CLOSEOUT OK`.

---

### Task 4a: `rogue_mud` client-task wiring — uninitialized socket + one-frame lifecycle — I then F

**Origin (Task 4 review, 2026-09-16).** Task 4 landed E3, but its review found two plan-mandated client-task defects (both in the currently-disabled multiplayer path, `MULTIPLAYER_ENABLED = false`, so the goldens are unaffected):
- **(1) uninitialized socket:** the 5 client tasks are added at startup (`main.zig:114-135`) and `tick(client_sched)` fires on every local move (`broadcastDungeon`), so `clientFrameCoroutine` reads `cfa.server.clients[ci].socket` while it is still `undefined` in single-player, and `drawToSocketCoroutine` calls `std_net.send()` on it (Linux `ENOTSOCK`, no write — UB-dependent but harmless today).
- **(2) one-frame lifecycle:** each client frame task completes after ONE frame (`drawToSocketCoroutine` returns after one pass of `rows`; `tick` then marks the task `done`) and is never re-added, so after ~`rows` moves no further frames reach a connected client.

**Operator ruling (2026-09-16):** fix **both**, via an I task + F task (this pair), before Task 5.

#### Task 4a-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set / capture.** Determine the correct wiring and pin the current defect(s). Since `MULTIPLAYER_ENABLED = false` makes the path dead in-corpus, pin via a **deterministic repro** (a small driver or a corpus fixture that enables the client path / simulates an active client) that demonstrates (a) a client task running against a non-active client (uninitialized socket) and (b) a client task going `done` after one frame and never re-rendering. Capture the exact behavior + the expected GREEN contract. If a corpus fixture cannot exercise it, say so and propose the closest pinnable form (do NOT leave it prose-only — the standing rule requires a fixture or an explicit, justified declaration).
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact current lifecycle of a client task (add → tick → done) and where it goes wrong; (Q2) whether the correct design is to add a task only when a client becomes active (and remove/cancel it on disconnect) or to keep one long-lived task per slot that loops; (Q3) how `broadcastDungeon`/`tick` should gate on `server.clients[i].active`; (Q4) how `clientFrameCoroutine` should loop across broadcasts (what `@asyncSuspend`/`tick` shape keeps it alive) while preserving the per-client cells buffer (S11); (Q5) whether `client_sched`/task-set binding must move from startup to per-connection; (Q6) the minimal fix surface + risk; (Q7) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixture(s)/repro; record the RED in `repro/mi_matrix/EXPECTED_FAIL.md` (v115→v116) or the appropriate known-issue location.
- [ ] **Step 4: Report + present the fix surface for Task 4a-F.** No `sf/src` change.

#### Task 4a-F: fix the client-task wiring (`sf/src`-free; fixed point should NOT move)

- [ ] **Step 1: Fix** (1) so a client task never runs against a non-active client; (2) so a connected client keeps receiving frames across broadcasts (long-lived task or per-connection add/cancel); and **(3) the arena/ctx aliasing** — `main.zig:105-106` binds the root-frame `async_arena` and the `async_ctx` pool over the same bytes (`pool_base == async_storage[16]`), so a nested `drawToSocketCoroutine` child frame overwrites the first root frame (Task 4a-I measured the active task stalling, `active_total:74`/`active_state:3`). Give the client root frames their own arena separate from the ctx pool (or the report's option B: inline the row loop). Preserve the per-client cells buffer (S11) and the byte-identity of the local path.
- [ ] **Step 2: Fixtures/repro RED→GREEN**; full corpus sweep (class-map delta = intended dirs only); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; record the fixed point (expected UNMOVED). Seed rotation stays at Task 6.

**Sequencing gate:** Task 5 MUST NOT start until Task 4a-F is landed.

---

### Task 4b: 1-task scheduler root-frame nested-loop suspend quirk — I then F

**Origin (Task 4a-F, 2026-09-16).** While fixing the `rogue_mud` client-task wiring (option B: inline the row loop), Task 4a-F exposed a pre-existing compiler/runtime quirk: **a coroutine whose nested-loop `@asyncSuspend` lives in the ROOT frame only advances correctly with ≥2 registered tasks (`scheduler.count`); a 1-task scheduler re-sends one row per tick.** The example registers 5 client tasks (and a 5-task probe gives the correct GREEN), so the shipped example is unaffected — but the quirk is real and could bite Task 5 (`mud_server` per-client tasks) or any 1-task scheduler.

**Operator ruling (2026-09-16):** add a new I/F pair (this task) to investigate + **fix** the quirk before continuing. Task 4a-F stays as implemented (option B).

#### Task 4b-I: investigate + pin (no `sf/src` change)

- [ ] **Step 1: Fixture set** (`repro/mi_matrix/`, auto-listed; each documents RED-now + the GREEN contract):
  - `async_single_task_suspend_xmod/` — ONE registered task whose coroutine has a nested `while`/`for` loop with `@asyncSuspend` in the ROOT frame; tick to completion and assert the correct number of iterations (RED today: re-sends one row per tick).
  - `async_two_task_suspend_xmod/` — the ≥2-task control (already correct).
  - variants: suspend inside the loop body vs. at the loop tail; a non-loop single suspend (control); a nested coroutine (child frame) with the same shape.
- [ ] **Step 2: Questionnaire.** Answer in the report: (Q1) the exact mechanism (how `tick` + `scheduler.count` interact with a root-frame loop suspend — `sf/src/std_async.zig` `tick`, `sf/src/async_state_machine.zig`); (Q2) why ≥2 tasks masks it (the resume/state bookkeeping vs the loop back-edge); (Q3) whether the bug is in the scheduler's `tick` loop, the state machine's resume-block routing, or the frame layout's live analysis; (Q4) the minimal fix locus; (Q5) whether it also affects implicit awaits (not just `@asyncSuspend`) and nested coroutines; (Q6) corpus/diagnostic delta.
- [ ] **Step 3: Declare.** Add the fixtures; record the RED in `repro/mi_matrix/EXPECTED_FAIL.md` (v117→v118) or the appropriate known-issue location.
- [ ] **Step 4: Report + present the fix surface for Task 4b-F.** No `sf/src` change.

#### Task 4b-F: fix the quirk (`sf/src` change; fixed point MOVES)

- [ ] **Step 1: Fix** so a 1-task scheduler advances a root-frame nested-loop `@asyncSuspend` coroutine correctly.
- [ ] **Step 2: Fixtures RED→GREEN**; full corpus sweep (class-map delta = intended dirs only — any other movement is a regression to STOP on); `check_emit_support.sh` 5/5; self-compile closure (48 `.c`, 0 `[3000]`).
- [ ] **Step 3: Re-verify** the four goldens + `CLOSEOUT OK`; 4-MD5 byte-identical; record the new fixed point. Seed rotation stays at Task 6.

**Sequencing gate:** Task 5 MUST NOT start until Task 4b-F is landed.

---

### Task 5: `mud_server` `select` loop → per-client tasks (entry E4)

**Files:**
- Modify: `examples/z98/mud_server/main.zig:1-200`
- Reuse: `examples/z98/mud_server/demo/session.sh`, `demo/canonical_feed.txt`

**Interfaces:**
- Consumes: `std.async.Context`, `Task`, `Scheduler`, `schedulerInit`, `addTask`, `tick`, `awaitTask`, `@asyncFrameSize`, `@asyncInit`, `@asyncSuspend`, `@asyncResume`.
- Produces: `ClientTaskArgs`, `clientCoroutine(ctx, args)`, per-client tasks replacing the fd-set bookkeeping; `awaitTask` on the quit/disconnect path.

- [ ] **Step 1: Add the per-client coroutine**

In `examples/z98/mud_server/main.zig`, after `processCommand` (`:202-224`), append:
```zig
pub const ClientTaskArgs = struct {
    player: *Player,
    rooms: [*]Room,
};

// B3 (option a): the `@asyncInit` args record's fields ARE the coroutine's
// parameters; the record is `{ cta: *ClientTaskArgs }`.
pub const ClientCoroutineArgs = struct { cta: *ClientTaskArgs };

pub fn clientCoroutine(cta: *ClientTaskArgs) void {
    const p = cta.player;
    while (true) {
        if (!p.is_active) return;
        const n = std_net.recv(p.socket, &p.buffer[p.pos], @intCast(i32, BUFFER_SIZE - p.pos));
        if (n <= 0) {
            std.io.print("Client disconnected\n", .{});
            p.is_active = false;
            return;
        }
        p.pos += @intCast(usize, n);
        var j: usize = 0;
        while (j < p.pos) {
            if (p.buffer[j] == '\n') {
                var end = j;
                if (end > 0 and p.buffer[end - 1] == '\r') end -= 1;
                const cmd = parseCommand(p.buffer[0..end]);
                const response = processCommand(p, cmd);
                _ = std_net.send(p.socket, response.ptr, @intCast(i32, response.len));
                if (j + 1 < p.pos) {
                    var k: usize = 0;
                    while (k < p.pos - (j + 1)) {
                        p.buffer[k] = p.buffer[j + 1 + k];
                        k += 1;
                    }
                    p.pos -= (j + 1);
                } else {
                    p.pos = 0;
                }
                break;
            }
            j += 1;
        }
        _ = @asyncSuspend(null);
    }
}
```

- [ ] **Step 2: Replace the fd-set bookkeeping with per-client tasks**

Add module-scope state after `rooms` (`:31`):
```zig
var client_tasks: [MAX_CLIENTS]std.async.Task = undefined;
var client_task_ptrs: [MAX_CLIENTS]*std.async.Task = undefined;
var client_args: [MAX_CLIENTS]ClientTaskArgs = undefined;
var client_recs: [MAX_CLIENTS]ClientCoroutineArgs = undefined;
var client_sched: std.async.Scheduler = undefined;
// 8-aligned backing; a bare [N]u8 is 1-aligned and trips contextInit's @panic.
var async_storage: [32 * 1024]u64 = undefined;
```
After the `players` initialization loop (`:90-95`), bind the permanent arena + context and pre-mark the slots:
```zig
    var async_arena = std_arena.init(@ptrCast([*]u8, &async_storage)[std.async.HEADER_SIZE .. 32 * 1024 * 8]);
    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    client_sched = std.async.schedulerInit(client_task_ptrs[0..]);
    i = 0;
    while (i < MAX_CLIENTS) {
        client_task_ptrs[i] = &client_tasks[i];
        client_task_ptrs[i].frame = @ptrFromInt(*void, 0);
        client_task_ptrs[i].state = .done;
        client_task_ptrs[i].cancel_requested = false;
        i += 1;
    }
```
`std_arena` is the landed `std.arena` module: add `const std_arena = @import("std_arena");` and read `sf/src/std_arena.zig` for the exact `init`/`alloc` signature (error-union vs optional) before writing the alloc call.
In the accept path (`:121-150`), when a free slot is found, replace the player assignment with:
```zig
                        players[i] = Player{ .socket = client, .room_id = @intCast(u8, 0),
                            .buffer = undefined, .pos = @intCast(usize, 0), .is_active = true };
                        client_args[i] = ClientTaskArgs{ .player = &players[i], .rooms = &rooms };
                        client_recs[i] = ClientCoroutineArgs{ .cta = &client_args[i] };
                        const csz = @intCast(usize, @asyncFrameSize(clientCoroutine));
                        const cframe = std_arena.alloc(&async_arena, csz) catch {
                            const full2: []const u8 = "Server is full.\r\n";
                            _ = std_net.send(client, full2.ptr, @intCast(i32, full2.len));
                            std_net.close(client);
                            players[i].is_active = false;
                            i += 1;
                            continue;
                        };
                        client_task_ptrs[i].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), clientCoroutine, @ptrCast(*const void, &client_recs[i]));
                        client_task_ptrs[i].ctx = async_ctx;
                        client_task_ptrs[i].arg = @ptrCast(*void, &client_recs[i]);
                        client_task_ptrs[i].result = @ptrCast(*void, &client_recs[i]);
                        client_task_ptrs[i].cancel_requested = false;
                        client_task_ptrs[i].waiting_on = client_task_ptrs[i];
                        client_task_ptrs[i].has_waiting_on = false;
                        _ = std.async.addTask(&client_sched, client_task_ptrs[i]);
```
The `welcome` send (`:136-137`) and `found = true` stay. In the `!found` branch (`:144-148`), also mark `players[i].is_active = false` before closing if a slot was tentatively used.

- [ ] **Step 3: Drive the tasks from the select-ready path with `awaitTask` on quit**

Replace the whole `select` + "Data on client sockets" section (`:99-196`) with a loop that keeps `select` (the one piece of fd bookkeeping that is not scheduler state) and drives exactly the ready tasks:
```zig
    while (true) {
        std_net.fdZero(@ptrCast(*u8, &read_fds));
        std_net.fdSet(server, @ptrCast(*u8, &read_fds));
        var max_fd = server;
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active) {
                std_net.fdSet(players[i].socket, @ptrCast(*u8, &read_fds));
                if (players[i].socket > max_fd) max_fd = players[i].socket;
            }
            i += 1;
        }
        const ready_count = std_net.select(max_fd + 1, @ptrCast(*u8, &read_fds), null, null, 100);
        if (ready_count < 0) { std.io.print("select error\n", .{}); break; }
        if (ready_count == 0) continue;
        if (std_net.fdIsset(server, @ptrCast(*u8, &read_fds))) {
            const client = std_net.accept(server);
            if (client >= 0) { /* accept block from Step 2 */ }
        }
        i = 0;
        while (i < MAX_CLIENTS) {
            if (players[i].is_active and std_net.fdIsset(players[i].socket, @ptrCast(*u8, &read_fds))) {
                const step = @asyncResume(client_task_ptrs[i].frame, null);
                if (step == null) {
                    // coroutine completed (quit or disconnect): free the slot
                    std_net.close(players[i].socket);
                    players[i].is_active = false;
                    client_task_ptrs[i].state = .done;
                }
            }
            i += 1;
        }
        std.async.tick(&client_sched) catch {};
    }
```
`@asyncResume` is used (not `tick`) so only the socket that `select` reported ready performs a `recv`; the trailing `tick` advances the rest. **FLAGGED S17 (operator ruling required):** the spec §3.2/§1 says `main` uses `std.async.awaitTask` on the quit/disconnect path, but the landed `awaitTask(s, t)` only marks the *current* running task as waiting on `t` — it does not "drain" a task from outside the scheduler, and `main` here is not a task. `@asyncResume` returning null already signals completion, so this plan frees the slot directly. If the operator wants the spec's `awaitTask` drain, either `awaitTask` gains drain semantics (`sf/src` change) or the conversion restructures; otherwise the plan's Step 3 stands as written and the spec text is corrected.

- [ ] **Step 4: Build, run the session, and verify byte-identity**

Run:
```bash
rm -rf /tmp/t4_mud_new && mkdir -p /tmp/t4_mud_new
timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_mud_new/em examples/z98/mud_server/main.zig >/tmp/t4_mud_new/em/stderr.log 2>&1; echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_mud_new/em/stderr.log 2>/dev/null || true
for f in /tmp/t4_mud_new/em/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /tmp/t4_mud_new/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_mud_new/prog /tmp/t4_mud_new/em/*.o
bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_new/prog /tmp/t4_mud_new/out.txt /tmp/t4_mud_new/client.txt; echo "session rc=$?"
md5sum /tmp/t4_mud_new/out.txt examples/z98/mud_server/demo/canonical_expected.txt /tmp/t4_mud_new/client.txt examples/z98/mud_server/demo/canonical_client_expected.txt
```
Expected: emit/gcc/link rc=0; zero `error[3017/3018/3019/3046]`/`PANIC` lines in `em/stderr.log`; session rc=0; BOTH md5 pairs match (server stdout AND client-received bytes byte-identical, including the `look`/`north`/`quit` responses and disconnect handling). Run the session three times and require identical md5s. If either differs, apply the E4 fallback (restore the original `select`/fd-set loop), record an amendment, and continue.

- [ ] **Step 5: Closeout gate + commit**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean | tail -3
git add examples/z98/mud_server/main.zig
git commit -m "feat(mud_server): per-client coroutine tasks replace select fd bookkeeping (Track4 E4)"
```
Expected: `CLOSEOUT OK`.

---

### Task 6: Full golden battery, fallback adjudication, and closeout

**Files:**
- Modify: `docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` (only if an entry was reverted; record the amendment in the plan, not the subspec)
- Modify: `docs/superpowers/plans/2026-09-13-coroutine-integration-plan.md` (Amendments section)
- Modify: `examples/z98/rogue_mud/demo/README.md`, `examples/z98/mud_server/demo/README.md` (record post-conversion md5s)

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: the final evidence table and the per-entry keep/revert decision.

- [ ] **Step 1: Run the authoritative closeout gate**

Run:
```bash
bash scripts/closeout/verify_upgraded.sh /tmp/t4_ref/zig1_5_clean; echo "closeout rc=$?"
```
Expected: full verdict table PASS, `CLOSEOUT OK`, rc=0, hashes lisp `96654b39…`, rogue `3fb6709e…`/`b3c5b0e1…`/`7361d248…`/`aa40a52e…`. If any phase fails, the corresponding track's entry must be reverted (fallback) before this task can pass.

- [ ] **Step 2: Run the per-entry byte-identity battery three times**

Run:
```bash
for i in 1 2 3; do
  timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_feed.txt | md5sum
  timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum
  bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_new/prog /tmp/t4_mud_new/out.$i.txt /tmp/t4_mud_new/client.$i.txt >/dev/null 2>&1; md5sum /tmp/t4_mud_new/out.$i.txt /tmp/t4_mud_new/client.$i.txt
done
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt examples/z98/rogue_mud/demo/canonical_move_expected.txt examples/z98/mud_server/demo/canonical_expected.txt examples/z98/mud_server/demo/canonical_client_expected.txt
```
Expected: every run's md5 matches its expected file (both mud_server captures); all hashes stable. Record the final table in the plan's Amendments/Closeout note.

- [ ] **Step 3: Run the corpus gate**

Run:
```bash
bash scripts/corpus/list_corpus_dirs.sh | grep -E 'examples/z98/(rogue_mud|mud_server)/'
ok=0; green=0; fail=0
for d in examples/z98/rogue_mud examples/z98/mud_server; do
  rm -rf /tmp/t4_cor; mkdir -p /tmp/t4_cor
  timeout 120 /tmp/t4_ref/zig1_5_clean --dump-c89 --output-dir /tmp/t4_cor "$d/main.zig" >/dev/null 2>/tmp/t4_cor/err.txt; rc=$?
  if [ "$rc" -ne 0 ]; then grep -qE 'error\[' /tmp/t4_cor/err.txt && green=$((green+1)) || fail=$((fail+1)); continue; fi
  [ -z "$(ls /tmp/t4_cor/*.c 2>/dev/null)" ] && { fail=$((fail+1)); continue; }
  good=1; for f in /tmp/t4_cor/*.c; do gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null || { good=0; break; }; done
  [ "$good" -eq 1 ] && ok=$((ok+1)) || fail=$((fail+1))
done
echo "examples OK=$ok GREEN=$green FAIL=$fail"
```
Expected: both dirs listed; `OK=2 GREEN=0 FAIL=0`, matching Task 1's baseline (zero class movement).

- [ ] **Step 4: Verify the example conversions touch no new `sf/src`; rotate the seed**

Run:
```bash
git diff --stat HEAD -- sf/src release/seed
git status --porcelain
```
Expected: no NEW `sf/src` change beyond the Task 0/0b commits; the only dirty files are the examples and docs. Because Task 0 moved the self-emission fixed point and Task 0b changed `lib/std_async.zig`, **rotate the seed** at closeout (this supersedes the original "do not rotate" constraint):
```bash
bash scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog
```
Record the new seed version + archive md5; update `docs/sf/QUICK_REF.md` (fixed point, seed version, archive md5) and confirm the rotation prepended the `release/seed/CHANGELOG.md` entry.

- [ ] **Step 4c: Spec-vs-landed reconciliation (standing)**

Re-read `docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` and confirm every claim about the landed surface (types, signatures, field names, call-site semantics) matches `sf/src` and the converted examples. Correct any drift in the spec in place and record it here. S17 (`awaitTask` described as a `main`-side drain vs the landed coroutine-internal function) is the first instance of spec drift WITHOUT plan drift; treat this as a standing item for EVERY track-N closeout, not just Track 4.

- [ ] **Step 5: Update the demo READMEs and record the amendment status**

For every entry that passed, append the post-conversion md5 to the demo `README.md` as the authoritative golden. For every reverted entry, add an amendment line to `## Amendments` with date, entry id (E1–E4), reason (a/b/c/d from the subspec §3.4), and the concrete revert performed. No `TBD`/`TODO` markers.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/rogue_mud/demo examples/z98/mud_server/demo docs/superpowers/plans/2026-09-13-coroutine-integration-plan.md
git commit -m "chore(coroutine): Track4 golden battery + fallback adjudication (Track4)"
```

---

## Self-Review

**Spec coverage:**
- Subspec §1 E1 (NPC AI) → Task 2.
- Subspec §1 E2 (per-connection broadcast, `main.zig:277/:286` + `ui.zig:61`) → Task 3.
- Subspec §1 E3 (cross-module create/schedule/cancel) → Task 4.
- Subspec §1 E4 (`mud_server` `main.zig:100-174` + `awaitTask`) → Task 5.
- Subspec §3.1 pinned builtin/`std.async` surface → Global Constraints + each task's **Interfaces**.
- Subspec §3.2 per-entry mapping and ordering rules → Task 2 Steps 2–3, Task 3 Step 3, Task 4 Steps 1–2, Task 5 Steps 2–3.
- Subspec §3.3 byte-identity gates → Tasks 2–6 evidence commands + Global Constraints.
- Subspec §3.4 fallback rule → Global Constraints + each task's "if it differs, revert" step + Task 6 Step 5.
- Subspec §4 interfaces → named identically in each task's **Interfaces** block.
- Subspec §5 diagnostics → Task 2 Step 4 / Task 3 Step 4 / Task 4 Step 3 / Task 5 Step 4 zero-diagnostic gates; no new codes planned.
- Subspec §6 testing/goldens → Task 1 harness, Tasks 2–5 captures, Task 6 battery + closeout + corpus.
- Subspec §7 risks (fn-ptr gap, mutable globals, arena lifetime, ordering) → Global Constraints pinned-surface rule, Task 2 Step 3 permanent `async_arena`, ordering rules.
- Subspec §8 dependencies → Sequence line + Global Constraints precondition.

**Placeholder scan:** no `TBD`/`TODO`/"add error handling"/"similar to Task N"; every code step shows the code and every command shows expected evidence. The only enumerated-by-reference item is the landed Track 3 initializer/field-name surface, which the Global Constraints pinned-surface amendment rule covers explicitly (naming-only amendments).

**Type consistency:** `NpcArgs`/`npcStep`/`npcCoroutine`/`spawnEnemies`/`updateEnemies` are defined in Task 2 and consumed with the same names in Task 4. `ClientArgs`/`drawToSocketCoroutine` and `ClientFrameArgs`/`clientFrameCoroutine` are defined in Task 3 and consumed in Task 4. `ClientTaskArgs`/`clientCoroutine` are defined in Task 5. `npc_sched`/`client_sched`/`npc_tasks`/`client_frame_tasks`/`async_ctx`/`async_arena`/`async_storage`/`client_cells` are introduced in Task 2/3/4 and used consistently. `tick(s)` (returns `FrameError!void`) / `awaitTask(s, t)` signatures match the landed Track 3 surface in every call site. Tasks 0/0b precede everything; the landed surface is pinned in Global Constraints. Coroutine arg records `NpcCoroutineArgs`/`ClientFrameCoroutineArgs`/`ClientCoroutineArgs` and their `npc_recs`/`client_frame_recs`/`client_recs` storage are introduced in Tasks 2/4/5; each coroutine's params ARE the record's fields (Amendment 3 B3), and every `@asyncInit` caller cast is `@ptrCast(*const void, …)` (B1).

## Amendments

This plan is amendable in place. Any deviation discovered during execution — a reverted entry, a Track 3 surface rename, or a harness change — is recorded here as an explicit amendment (date, task, entry, reason, decision) and the affected task body is edited rather than appended. No `TBD`/`TODO` markers are permitted in amendments; each must state the concrete change and its verification. Track 4 is the final plan in the sequence; there is no next plan.

### Amendment 1 — Track-4 alignment (2026-09-15, operator ruling)

Applied before dispatch:

1. **Stale-scheduler marker resolved.** The plan's `tick(s, step)`/`awaitTask(s, t, step)`
   and homogeneous-step-ABI surface is aligned to Amendment 7 (heterogeneous
   `@asyncResume` self-dispatch): `tick(s)`, `awaitTask(s, t)`; no `Task.step`,
   no `step` parameter. This matches the Track-4 spec (already Amendment-7-correct).
   Global Constraints + the Type-consistency note are updated.
2. **Baseline refreshed** to the landed post-Track-3 state (HEAD `2dc50be1`;
   fixed point `027377296b2e38402ff8470f5c429eb8`; seed v19 archive md5
   `23a16154e83736cf6b636685396a124a`; corpus 612 = 571 OK / 37 GREEN / 4 FAIL;
   `EXPECTED_FAIL.md` v85).
3. **Pinned consumed surface refreshed** with the landed Track-3 surface (16-byte
   `Context` header, 8-aligned buffers, `awaitTask` empty-scheduler `@panic`,
   `@asyncInit` `-fsafe` frame-size bounds check); the superseded
   `fn_ptr_struct_field`/homogeneous reasoning is dropped.
4. **Cross-track ABI closeout check added** (Task 6 must re-verify the `Context`
   header/`CTX_POOL_OFF` = 16 and 8-padded frames agree across tracks).
5. **Multi-module `__Z98Step_<f>` emission gap recorded as a binding pre-conversion
   blocker** (see Global Constraints), pinned by
   `repro/mi_matrix/async_step_nonlast_xmod` (`EXPECTED_FAIL.md` v85). Track 4's
   `rogue_mud`/`mud_server` are multi-module, so this MUST be resolved (emitter fix
   or an explicit, recorded fallback decision) before the Task 2–5 conversions.

No `sf/src` edit is made by this amendment (docs-only).

### Amendment 2 — pre-flight ruling: Cat 1/2/3 + S15 emitter fix (2026-09-15, operator ruling)

The pre-flight scan (`.superpowers/sdd/2026-09-13-coroutine-integration-plan/progress.md`) found the plan body written against a superseded `std.async` surface. The operator ruled a three-category handling plus a compiler fix; all are applied in place above.

**S15 — multi-module `__Z98Step_<f>` emission gap: FIX THE EMITTER (new Task 0).** `emitModule`/`emitModuleFile` must emit a step for every `is_suspending` function in EVERY module, not only the last. `async_libctx_mix_xmod` is annotated as the last-module-coroutine fixture; a new non-last fixture `async_step_midmodule_xmod` lands in the same commit and passes; `async_step_nonlast_xmod` flips EXPECTED-FAIL → PASS. Fixed point MOVES; seed rotation at Task 6.

**Cat 1 — genuine plan drift (docs-only; corrected in place).** S1-S3 stale 2/3-arg `tick`/`awaitTask`; S4 non-existent `Task.arena*` fields; S5 1-aligned `[N]u8` context buffer; S6 `*Context` vs value; S7 `try sand_alloc` in a non-error fn; S8 `spawnEnemies` never `addTask`; S9 `npcMove`→`npcStep` (spec §4); S12 gcc flag set; S16 `tick` returns `FrameError!void`. Global Constraints pin the landed surface.

**Cat 2 — real bugs (fixed before Task 4).**
- S10 (Task 2): NPC root frames must live in PERMANENT storage (`async_storage`/`async_arena`), never the per-turn `temp_arena`. Fixture `async_frame_lifetime_xmod` (Task 2 Step 4b).
- S11 (Task 3): per-client cells buffers (`client_cells[i]`), not a shared `local_cells`. Fixture `async_client_cells_xmod` (Task 3 Step 4b). I-task recommendation: per-client buffers.
- S14 (Task 0b): `addTask` stores the caller's `*Task` (`Scheduler.tasks: [*]*Task`), not a by-value copy. Fixture `stdlib_async_handle_xmod`. I-task recommendation: pointer storage. Not in the compiler import graph → no fixed-point move; seed archive `lib/std_async.zig` changes.

**Cat 3 — S13 (docs-only).** Compiler diagnostics go to stderr; there is no `em/dump.log`. Every task's evidence now captures `> em/stderr.log 2>&1` and greps `em/stderr.log`. (Operator shorthand `2>&1 > em/stderr.log` reordered to actually capture stderr.)

**S17 — FLAGGED, awaiting ruling.** Task 5 Step 3: the spec says `main` uses `awaitTask` to drain a completed client task, but the landed `awaitTask(s, t)` only marks the current task as waiting. The plan frees the slot directly; a spec/`sf/src` change is required if the drain semantics are wanted.

### Amendment 3 — Task 2 blockers: caller-side `@asyncInit` ABI (2026-09-16, operator ruling)

Task 2 dispatch was BLOCKED by three confirmed plan/design defects in the `@asyncInit` caller surface; the operator ruled B1/B2/B3 and all are applied in place above (the dispatch made no commit; its uncommitted edits were reverted).

**B1 — caller cast.** The plan wrote `@ptrCast(?*const void, &args[n])`; a `?*const void` is a non-scalar optional struct in Z98, so the emitted C89 is invalid (`conversion to non-scalar type requested`). Every landed fixture passes a plain `*const void` (`async_await_xmod/main.zig:35`), which coerces into the optional parameter. Fixed at all three call sites (Tasks 2/4/5).

**B2 — root-frame arena vs the `Context` header.** The plan bound `async_arena` and `async_ctx` both at `async_storage[0..]`; the first root frame aliased the 16-byte `Context` header and each `@asyncInit` reset `ctx.used`/`ctx.oom` at +0/+8, clobbering frame 0's step word (tick trap). The root-frame arena now starts at `std.async.HEADER_SIZE` (Tasks 2/5).

**B3 — coroutine parameter ABI (option a).** `@asyncInit` copies the args record POSITIONALLY into the coroutine's parameters (`sf/src/lower.zig:4362-4386`), so a `(ctx: *Context, args: *void)` coroutine maps `ctx ← record.field0`, `args ← record.field1`. Each `@asyncInit` target now takes the record's fields directly and a matching record type is added: `npcCoroutine(na: *NpcArgs)` + `NpcCoroutineArgs{ na }`; `clientFrameCoroutine(ctx, cfa: *ClientFrameArgs)` + `ClientFrameCoroutineArgs{ ctx, cfa }`; `clientCoroutine(cta: *ClientTaskArgs)` + `ClientCoroutineArgs{ cta }`. `drawToSocketCoroutine` is NOT an `@asyncInit` target (called directly) and keeps `(ctx, args)`.

### Amendment 4 — Task 2a: nested module value-position access gap (2026-09-16, operator ruling)

The Task 2 re-dispatch was BLOCKED by a compiler gap: lowering `std.async.HEADER_SIZE` (a scalar `pub const` accessed through a nested module alias) emits `error[3042] non-value base expression in field access` + `warning[3023] module used as value expression` (0 `.c`). The operator ruled this a real gap to be addressed by an I/F pair, added to the plan as **Task 2a** (a prelude on Track 2 exposed by Task 2). It is the pre-existing deferred `std.async` value-position gap (`docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md:474`, "Amendment 7, Res 4"). Task 2a-I investigates + pins (fixtures + questionnaire + declaration, no `sf/src` change); Task 2a-F fixes it (`sf/src` change; fixed point MOVES). Tasks 2/4/5 read `std.async.HEADER_SIZE` (plan lines 730, 1077), so Task 2a-F must land before Task 2 re-dispatches.
