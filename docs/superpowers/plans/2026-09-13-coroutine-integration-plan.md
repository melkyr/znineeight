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

**Architecture:** One linear track. Two operator-authorized `sf/src` changes precede the conversions: **Task 0** fixes the multi-module `__Z98Step_<f>` emission gap in the C emitter (the self-emission fixed point MOVES), and **Task 0b** changes `std.async` task ownership (`addTask` stores `*Task`; not in the compiler import graph, so no fixed-point move, but the seed archive's `lib/std_async.zig` changes). The seed is rotated at Task 6 closeout. Then `rogue_mud/lib/combat.zig` grows a suspending `npcCoroutine` (one task per active enemy) whose per-turn driver is `std.async.tick`; `rogue_mud/ui.zig` grows a suspending `drawToSocketCoroutine` that yields between frame rows; `rogue_mud/main.zig` owns the caller-supplied schedulers and task arenas and wires create/schedule/cancel across the three modules. `mud_server/main.zig` replaces the fd-set bookkeeping with one `clientCoroutine` task per accepted socket driven by `@asyncResume` from the select-ready path, with `std.async.awaitTask` on the quit/disconnect path. The example conversions themselves touch no `sf/src` file.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.async` (Track 3), the four `@async*` builtins (Track 2), bash, `gcc -m32`, git.

## Global Constraints

- **Baseline (re-verify at Task 1; the fixed point MOVES in Task 0).** Pre-Task-0 HEAD `0aa5e13d`; pre-Task-0 compiler fixed point `027377296b2e38402ff8470f5c429eb8`; seed v19 archive md5 `23a16154e83736cf6b636685396a124a`; corpus 612 = 571 OK / 37 GREEN / 4 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v85 (2026-09-15). Task 0 (emitter fix) and Task 0b (`std.async` ownership fix) change `sf/src`, so the fixed point and seed move; Task 1 re-verifies and records the post-Task-0/0b values before capturing goldens.
- **Precondition:** Tracks 2 and 3 are implemented and landed. The four `@async*` builtins work, `sf/src/std_async.zig` exists, and `lib/std_async.zig` is installed next to the compiler under test (`docs/sf/QUICK_REF.md:97-98` recipe plus `std_async.zig`).
- **`sf/src` scope (operator-authorized 2026-09-15; supersedes the original examples-only constraint).** Authorized `sf/src` changes: **Task 0** (multi-module `__Z98Step_<f>` emission; `sf/src/c89_emit.zig`+`sf/src/main.zig`; fixed point MOVES); **Task 0b** (`std.async` task ownership; `sf/src/std_async.zig`; fixed point UNMOVED but `lib/std_async.zig` changes); **Task 0d** (switch-expression string-literal-prong `string_to_slice` length; `sf/src/semantic_analyzer.zig`; fixed point MOVES); **Task 0f** (residual S20 un-annotated inference + S21 error-union/optional payload string→slice; `sf/src/semantic_analyzer.zig` + `sf/src/lower.zig`; fixed point MOVES). The seed is rotated at Task 6 closeout. No other `sf/src` edit is authorized; Tasks 1-5 touch examples only (the fix tasks re-capture the goldens they change).
- **Standing rule — declare every residual gap (binding).** Any gap a fix leaves behind (a construct still affected, a distinct adjacent bug, a known limitation) MUST be declared before its task is marked complete: a tracked fixture (or an `EXPECTED_FAIL.md` entry for a compile-fail) + a plan/spec note. "Approved with a Minor" is NOT a declaration. S20/S21 (Task 0d residuals) are the first application.
- **`timeout 120` on every binary execution.**
- **gcc flag-set rule (binding):** every `gcc -c` MUST be `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. Compiler builds only via the seed model: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`; never invoke `zig0`. `<out_dir>` must be fresh.
- **Byte-identity is a hard requirement.** `bash scripts/closeout/verify_upgraded.sh <zig1>` MUST print `CLOSEOUT OK` and exit 0 with lisp canonical `96654b39…`, rogue q `3fb6709e…`, rogue move `b3c5b0e1…`, rogue demo `7361d248…`, rogue net variant `aa40a52e…`. Emitted C is NOT required to be byte-identical; only runtime bytes are.
- **Per-entry byte-identity + fallback.** Each converted entry has a pre-conversion and post-conversion runtime capture that must be md5-identical (feeds in `File Structure`). If a golden moves, a capture differs, an `error[3017/3018/3019/3046]`/`PANIC` appears, or task ordering changes the post-turn dungeon state, revert **that entry** to its original loop (keep the original `while`/`select` body), record an amendment, and leave the example building. Entries are independently revertable.
- **Corpus gate:** `bash scripts/corpus/list_corpus_dirs.sh` must still list both `examples/z98/rogue_mud/` and `examples/z98/mud_server/`; classify by gcc exit code, never empty-stderr (`docs/sf/QUICK_REF.md:134-154`); zero class movement on the two examples.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the target region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Pinned consumed surface (landed Track 3, verified 2026-09-15).** Track 2 builtins: `@asyncFrameSize(fn) u32`, `@asyncInit(ctx: *Context, buf: [*]u8, fn, args: ?*const void) *void`, `@asyncResume(frame: *void, arg: ?*void) ?*void`, `@asyncSuspend(data: ?*void) *void`. Track 3 `std.async` as landed in `sf/src/std_async.zig`: `Context` (`HEADER_SIZE = 16`, `pool_base = ctx+16`, `contextInit(buf: []u8) *Context`; buffers MUST be 8-aligned — back them with a `u64` array, never a bare `[N]u8`), `TaskState`, `Task { frame: *void, ctx: *Context, state, cancel_requested, result: *void, arg: *void, waiting_on: *Task, has_waiting_on: bool }` (**no `arena`/`arena_capacity`/`arena_used` fields, no `step` field**), `Scheduler`, `schedulerInit(tasks: []Task) Scheduler`, `addTask(s, t) bool`, `tick(s: *Scheduler) FrameError!void` (**returns an error union — every call site must `try`/`catch`**), `suspend(s, t)`, `awaitTask(s, t) void` (empty-scheduler `@panic`), `cancel(s, t)`, `cancelAll(s)`, `waitAll(s) FrameError!void`. No `step` parameter; `tick`/`waitAll` self-dispatch via `@asyncResume(t.frame, t.arg)`. `@asyncInit` under `-fsafe` traps when `buf.len < @asyncFrameSize(fn)` for compile-time-known array buffers. **Task 0b** changes `Scheduler.tasks` to `[*]*Task` and `schedulerInit(tasks: []*Task)`, so `addTask` stores the caller's `*Task` (no by-value copy) and callers may keep their own `Task` handles.
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

### Task 2: `rogue_mud` NPC AI → per-NPC coroutine (entry E1)

**Files:**
- Modify: `examples/z98/rogue_mud/lib/combat.zig:1-104`
- Modify: `examples/z98/rogue_mud/main.zig` (NPC scheduler setup + the two `updateEnemies` call sites at `:207` and `:258`)

**Interfaces:**
- Consumes: `std.async.Context`, `std.async.Scheduler`, `std.async.tick`, `@asyncFrameSize`, `@asyncInit`, `@asyncSuspend`, `sand_mod.sand_alloc`.
- Produces: `NpcArgs`, `npcStep(na)`, `npcCoroutine(ctx, args)`, `spawnEnemies(ctx, sched, tasks, args, dungeon, frame_arena, path_arena) usize`, `updateEnemies(sched) FrameError!void`.

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

pub fn npcCoroutine(ctx: *std.async.Context, args: *void) void {
    const na = @ptrCast(*NpcArgs, args);
    while (true) {
        npcStep(na);
        _ = @asyncSuspend(null);
    }
}

pub fn spawnEnemies(ctx: *std.async.Context, sched: *std.async.Scheduler,
    tasks: []std.async.Task, args: []NpcArgs, dungeon: *scenario.Dungeon_t,
    frame_arena: *sand_mod.Sand, path_arena: *sand_mod.Sand) usize {
    var n: usize = 0;
    var i: usize = 1;
    while (i < dungeon.entity_count and n < tasks.len) : (i += 1) {
        args[n] = NpcArgs{ .dungeon = dungeon, .entity_idx = i, .arena = path_arena };
        const sz = @intCast(usize, @asyncFrameSize(npcCoroutine));
        // S10: root frames come from a PERMANENT arena, never the per-turn
        // temp_arena that sand_reset reclaims.
        const frame = sand_mod.sand_alloc(frame_arena, sz, 8) catch return n;
        tasks[n].frame = @asyncInit(ctx, @ptrCast([*]u8, frame), npcCoroutine, @ptrCast(?*const void, &args[n]));
        tasks[n].ctx = ctx;
        tasks[n].arg = @ptrCast(*void, &args[n]);
        tasks[n].result = @ptrCast(*void, &args[n]);
        tasks[n].cancel_requested = false;
        tasks[n].waiting_on = &tasks[n];
        tasks[n].has_waiting_on = false;
        _ = std.async.addTask(sched, &tasks[n]);
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
var npc_args: [MAX_NPCS]combat_mod.NpcArgs = undefined;
var npc_sched: std.async.Scheduler = undefined;
// S10: root frames live in a PERMANENT arena over this 8-aligned backing,
// separate from `temp_buffer`, so `sand_reset(&temp_arena)` never reclaims a
// live coroutine frame. `[K]u64` is 8-aligned; a bare `[N]u8` is 1-aligned and
// would trip `contextInit`'s alignment @panic.
var async_storage: [32 * 1024]u64 = undefined;
```
After the enemy-placement loop (`:79-86`), bind the permanent arena + context and spawn:
```zig
    var async_arena = sand_mod.sand_init(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8], true);
    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    npc_sched = std.async.schedulerInit(npc_tasks[0..]);
    _ = combat_mod.spawnEnemies(async_ctx, &npc_sched, npc_tasks[0..], npc_args[0..], &dungeon, &async_arena, &temp_arena);
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

pub fn clientFrameCoroutine(ctx: *std.async.Context, args: *void) void {
    const cfa = @ptrCast(*ClientFrameArgs, args);
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
`tick(s)` (landed signature, returns `FrameError!void`) resumes every registered client task once; `catch {}` is acceptable here because the client tasks are bounded and sized from `@asyncFrameSize` (pool exhaustion triggers the §Global-Constraints fallback and is re-checked in Task 6). Module-scope `client_frame_tasks: [5]std.async.Task` and `client_frame_args: [5]ClientFrameArgs` are bound once in Task 4 Step 1. **S11:** `client_frame_args[i].cells` points at a per-client buffer — add `var client_cells: [5][80 * 50]ui_mod.Cell = undefined;` next to `local_cells` and bind `.cells = @ptrCast([*]ui_mod.Cell, &client_cells[i][0])`. Update the two call sites (`:210`, `:260`) to `broadcastDungeon(&server, &client_sched)` and initialize `client_sched` next to `npc_sched` in Task 2's setup block.

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
    npc_sched = std.async.schedulerInit(npc_tasks[0..]);
    _ = combat_mod.spawnEnemies(async_ctx, &npc_sched, npc_tasks[0..], npc_args[0..], &dungeon, &async_arena, &temp_arena);

    client_sched = std.async.schedulerInit(client_frame_tasks[0..]);
    var ci: usize = 0;
    while (ci < @intCast(usize, 5)) : (ci += 1) {
        // S11: each client builds into its OWN cells buffer.
        client_frame_args[ci] = ClientFrameArgs{ .server = &server, .dungeon = &dungeon,
            .client_idx = ci, .cells = @ptrCast([*]ui_mod.Cell, &client_cells[ci][0]) };
        const csz = @intCast(usize, @asyncFrameSize(clientFrameCoroutine));
        const cframe = sand_mod.sand_alloc(&async_arena, csz, 8) catch return;
        client_frame_tasks[ci].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), clientFrameCoroutine, @ptrCast(?*const void, &client_frame_args[ci]));
        client_frame_tasks[ci].ctx = async_ctx;
        client_frame_tasks[ci].arg = @ptrCast(*void, &client_frame_args[ci]);
        client_frame_tasks[ci].result = @ptrCast(*void, &client_frame_args[ci]);
        client_frame_tasks[ci].cancel_requested = false;
        client_frame_tasks[ci].waiting_on = &client_frame_tasks[ci];
        client_frame_tasks[ci].has_waiting_on = false;
        _ = std.async.addTask(&client_sched, &client_frame_tasks[ci]);
    }
```
`async_arena` is the PERMANENT arena bound in Task 2 Step 3 (`sand_init` over `async_storage`, `true`), so `sand_reset(&temp_arena)` cannot reclaim coroutine root frames. The landed `Task` has **no** `arena`/`arena_capacity`/`arena_used` fields — child frames are allocated from the task's `ctx` pool at await sites; all tasks share the one `async_ctx`.

- [ ] **Step 2: Replace the cancel sites**

At the client-disconnect branch (`main.zig:178-182`), insert the cooperative cancel before closing:
```zig
                    std.async.cancel(&client_sched, &client_frame_tasks[client_idx]);
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

pub fn clientCoroutine(ctx: *std.async.Context, args: *void) void {
    const cta = @ptrCast(*ClientTaskArgs, args);
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
var client_args: [MAX_CLIENTS]ClientTaskArgs = undefined;
var client_sched: std.async.Scheduler = undefined;
// 8-aligned backing; a bare [N]u8 is 1-aligned and trips contextInit's @panic.
var async_storage: [32 * 1024]u64 = undefined;
```
After the `players` initialization loop (`:90-95`), bind the permanent arena + context and pre-mark the slots:
```zig
    var async_arena = std_arena.init(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    var async_ctx: *std.async.Context = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);
    client_sched = std.async.schedulerInit(client_tasks[0..]);
    i = 0;
    while (i < MAX_CLIENTS) {
        client_tasks[i].frame = @ptrFromInt(*void, 0);
        client_tasks[i].state = .done;
        client_tasks[i].cancel_requested = false;
        i += 1;
    }
```
`std_arena` is the landed `std.arena` module: add `const std_arena = @import("std_arena");` and read `sf/src/std_arena.zig` for the exact `init`/`alloc` signature (error-union vs optional) before writing the alloc call.
In the accept path (`:121-150`), when a free slot is found, replace the player assignment with:
```zig
                        players[i] = Player{ .socket = client, .room_id = @intCast(u8, 0),
                            .buffer = undefined, .pos = @intCast(usize, 0), .is_active = true };
                        client_args[i] = ClientTaskArgs{ .player = &players[i], .rooms = &rooms };
                        const csz = @intCast(usize, @asyncFrameSize(clientCoroutine));
                        const cframe = std_arena.alloc(&async_arena, csz) catch {
                            const full2: []const u8 = "Server is full.\r\n";
                            _ = std_net.send(client, full2.ptr, @intCast(i32, full2.len));
                            std_net.close(client);
                            players[i].is_active = false;
                            i += 1;
                            continue;
                        };
                        client_tasks[i].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), clientCoroutine, @ptrCast(?*const void, &client_args[i]));
                        client_tasks[i].ctx = async_ctx;
                        client_tasks[i].arg = @ptrCast(*void, &client_args[i]);
                        client_tasks[i].result = @ptrCast(*void, &client_args[i]);
                        client_tasks[i].cancel_requested = false;
                        client_tasks[i].waiting_on = &client_tasks[i];
                        client_tasks[i].has_waiting_on = false;
                        _ = std.async.addTask(&client_sched, &client_tasks[i]);
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
                const step = @asyncResume(client_tasks[i].frame, null);
                if (step == null) {
                    // coroutine completed (quit or disconnect): free the slot
                    std_net.close(players[i].socket);
                    players[i].is_active = false;
                    client_tasks[i].state = .done;
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

**Type consistency:** `NpcArgs`/`npcStep`/`npcCoroutine`/`spawnEnemies`/`updateEnemies` are defined in Task 2 and consumed with the same names in Task 4. `ClientArgs`/`drawToSocketCoroutine` and `ClientFrameArgs`/`clientFrameCoroutine` are defined in Task 3 and consumed in Task 4. `ClientTaskArgs`/`clientCoroutine` are defined in Task 5. `npc_sched`/`client_sched`/`npc_tasks`/`client_frame_tasks`/`async_ctx`/`async_arena`/`async_storage`/`client_cells` are introduced in Task 2/3/4 and used consistently. `tick(s)` (returns `FrameError!void`) / `awaitTask(s, t)` signatures match the landed Track 3 surface in every call site. Tasks 0/0b precede everything; the landed surface is pinned in Global Constraints.

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
