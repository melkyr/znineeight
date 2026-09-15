# Z98 std.async Library (Track 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Amendment — Track-3 alignment (2026-09-15, operator ruling m1662)

This plan is amended to the landed Track 2 compiler surface. The previous
**STALE-SCHEDULER MARKER** (pinning `Task.step`/`StepFn` and the homogeneous step
ABI) is **removed**; its deferral is now applied here.

- **A — strike Track-3 independence.** The "no builtin / independent" clauses are
  struck. `std.async`'s scheduler self-dispatches through the compiler builtin
  `@asyncResume(frame, arg)` (Amendment 7 of
  [`2026-09-13-async-compiler-core-plan.md`](2026-09-13-async-compiler-core-plan.md)),
  so the library **depends on Track 2** (landed and closed). Dispatch order:
  **Track 2 → Track 3 → Track 4**. The fixtures build frames **by hand** (a
  struct whose first field is the step function pointer at offset 0) and drive
  them through the library scheduler.
- **B — branch (a) accepted.** `contextInit(buf: []u8) *Context`; the `Context`
  sits at the head of the caller's pool buffer (`pool_base = ctx + 12`, DERIVED).
  The by-value `Context` + separate `pool_base` alternative is **rejected**
  (redoes landed Track 2 work for a smaller safety margin). See Task 6.
- **Amendment 7 — drop `Task.step`/`step`.** `Task` has no `step` field and no
  scheduler function takes a `step` parameter; `tick`/`waitAll` drive each task
  with `@asyncResume(t.frame, t.arg)`. Fixtures set the step function as the
  **first field** of their `Frame`.
- **Baseline refresh.** HEAD `e2a0f30a`; fixed point
  `eda943dc1f77a48eae039e39ea4bfe04`; seed v15
  (`cd09877cbc373ad5c8801b93faccf188`); corpus 599 = 560 OK / 36 GREEN / 3 FAIL;
  `EXPECTED_FAIL.md` v80. Target corpus 604 = 565 OK / 36 GREEN / 3 FAIL;
  `EXPECTED_FAIL.md` v80 → v81.

**Goal:** Build the concrete, no-generics `std.async` Z98 library (`Context` per-task LIFO child-frame pool, `Task`, `Scheduler`, and the cooperative scheduler free functions) and wire it into every std-install touchpoint, so Track 4 can drive compiler-synthesized coroutine steps.

**Architecture:** `sf/src/std_async.zig` is a plain-Z98 user module (not in the compiler import graph): structs + free functions, no generics, no module-scope mutable globals. It adds **no** compiler-core machinery but **depends on Track 2**: the scheduler **self-dispatches** through the compiler builtin `@asyncResume(t.frame, t.arg)` (Amendment 7), so there is no `Task.step` field and no `step` parameter. `Context` is a per-task frame stack for **child** frames only (bump pointer + mark); the root frame lives in the caller-owned `buf` outside the pool, and the `Context` itself sits at the head of the pool buffer (`contextInit` returns a `*Context`). Pool exhaustion surfaces as `error.OutOfFrame`, never a crash. The module is re-exported from `std.zig` and added to all seed/self-compile `lib/` install paths; its five corpus fixtures **hand-build frames** (step function pointer as the first struct field at offset 0) and drive them through the library scheduler.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), gcc `-m32 -std=c89`, bash, git. Compiler builds via the seed/forward path `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`; never invoke `zig0`.

## Global Constraints

- **Baseline (re-verify at Task 1):** branch `zig1_improvements`; HEAD `e2a0f30a`; design fixed point `eda943dc1f77a48eae039e39ea4bfe04`; seed v15 archive md5 `cd09877cbc373ad5c8801b93faccf188`; corpus 599 = 560 OK / 36 GREEN / 3 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v80. **Track 2 (`async-compiler-core-plan.md`) is landed and closed**; Track 3 **depends on** its `@asyncResume`/frame surface (dispatch order Track 2 → Track 3). Target corpus after the five new fixtures: 604 = 565 OK / 36 GREEN / 3 FAIL; `EXPECTED_FAIL.md` v80 → v81.
- **`timeout 120` on every binary execution.**
- **Binding gcc flag set for every `gcc -c`/link:** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. The compiler fixed point reproduces only with `-Wall`.
- **Compiler build:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; gate `=== [seed] Done: <fresh_out> ===`; result `<fresh_out>/zig1_5_clean` + `<fresh_out>/lib/`. Never invoke `zig0`.
- **Fixture build/run recipe:** `"$ZIG1" -ffast --dump-c89 --output-dir "$OUT" repro/.../main.zig`, then compile every `"$OUT"/*.c` with the flag set, then `( cd "$OUT" && sh build_target.sh linux <prog> )` and run. Classify by gcc exit code, never by empty stderr (`docs/sf/QUICK_REF.md:134-145`).
- **`sf/src` file scope is exactly two files:** create `sf/src/std_async.zig`, append one re-export line to `sf/src/std.zig`. `std.zig` is **not** imported by `sf/src/main.zig`, so the self-emission fixed point must NOT move; if it does, STOP and investigate before continuing.
- **Library constraints:** no generics/`anytype`/`@Type`; explicit `@intCast`; no module-scope mutable globals (the caller supplies `Scheduler` and `Context`); `switch` needs `else`; use the `var msg: []const u8 = "...";` pattern for string writes.
- **No `?*T` struct field:** arrays of a struct with an optional pointer field emit invalid C at the design fixed point (`field = 0` to an `Opt_` type). `Task` uses `waiting_on: *Task` + `has_waiting_on: bool`; do not simplify back.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files). Never stage `mnemoria/` or `.zig1_*.tmp`.
- **Seed rotation is closeout-only (Task 5):** `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`. Never rotate mid-plan.
- **STOP-present** after each task; await GO before the next task.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-std-async-design.md`. This plan is amendable in place.

---

**Sequence:** Previous plan: [`../plans/2026-09-13-async-compiler-core-plan.md`](../plans/2026-09-13-async-compiler-core-plan.md) — **landed and closed** (Track 3 **consumes** its `@asyncResume` builtin / hidden-step-word frame surface); Next plan: [`../plans/2026-09-13-coroutine-integration-plan.md`](../plans/2026-09-13-coroutine-integration-plan.md) — **consumes Track 3**; subspec: [`../specs/2026-09-13-std-async-design.md`](../specs/2026-09-13-std-async-design.md). Dispatch order: **Track 2 → Track 3 → Track 4**.

## File Structure

- `sf/src/std_async.zig` — **new**: `TaskState`, `FrameError`, `StepFn`, `Context` + pool primitives, `Task`, `Scheduler`, and the scheduler free functions (§3.1 of the subspec).
- `sf/src/std.zig` — append `pub const async = @import("std_async.zig");` after `net` (`:7`).
- `scripts/seed/build_from_seed.sh` — `:139` `lib/` `cp` list + `:24` "8 std" comment (Task 1; needed to test the installed module).
- `scripts/seed/archive_seed.sh` — `:109` `lib/` loop + `:28-29`, `:156-158`, `:210-211` std-set comments/counts (Task 4).
- `scripts/self_compile/build_zig1_5.sh` — `:12` `lib/` `cp` (Task 4).
- `docs/sf/QUICK_REF.md` — `:98` install recipe + `:36-37` seed inventory count (Task 4).
- Fixtures (new dirs, each `main.zig`): `repro/mi_matrix/stdlib_async_pool_xmod/` (Task 1), `stdlib_async_sched_xmod/`, `stdlib_async_oom_xmod/` (Task 2), `stdlib_async_await_xmod/`, `stdlib_async_cancelall_xmod/` (Task 3).
- `repro/mi_matrix/EXPECTED_FAIL.md` — header bump v81 with the new corpus counts (Task 5).
- `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` — closeout rotation (Task 5).

---

### Task 1: `std.async` core — types + `Context` pool + re-export + build-path install

**Files:**
- Create: `sf/src/std_async.zig`
- Modify: `sf/src/std.zig` (append re-export after `:7`)
- Modify: `scripts/seed/build_from_seed.sh:24,139`
- Create: `repro/mi_matrix/stdlib_async_pool_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDASYNC-report.md` (`## Task 1`)

**Interfaces:**
- Consumes: umbrella m1166/m1172 (`buf` outside the pool; per-task LIFO child-frame stack; bump + mark; `error.OutOfFrame`).
- Produces: `TaskState`, `FrameError`, `StepFn`, `Context`, `contextInit`, `contextAlloc`, `contextMark`, `contextRelease`; the `std.async` re-export; the 9-file `build_from_seed.sh` `lib/` install.

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/stdlib_async_pool_xmod/main.zig`:

```zig
// stdlib_async_pool_xmod — Track 3 std.async Context pool fixture.
//
// Validates the std.async re-export reachable from a bare @import("std"):
//   contextInit / contextAlloc / contextMark / contextRelease
//   - 8+8 alloc -> used 16; mark at 16; alloc 8 -> used 24; release -> 16
//   - alloc 40 -> used 56; alloc 40 -> OutOfFrame (sticky oom), used stays 56
//   - buf is 80 B; capacity = 80 - 12 = 68 usable bytes after the 12-byte header
// GREEN: exact stdout 1 1 1 1 0 1 1 (RUNRC=0).
const std = @import("std");

fn tryAlloc(ctx: *std.async.Context, n: usize) bool {
    var p = std.async.contextAlloc(ctx, n) catch return false;
    _ = p;
    return true;
}

fn pb(cond: bool) void {
    if (cond) {
        std.io.printInt(1);
    } else {
        std.io.printInt(0);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    var buf: [80]u8 = undefined;
    var ctx = std.async.contextInit(buf[0..]);
    pb(tryAlloc(ctx, 8));
    pb(tryAlloc(ctx, 8));
    var mark = std.async.contextMark(ctx);
    pb(tryAlloc(ctx, 8));
    std.async.contextRelease(ctx, mark);
    pb(tryAlloc(ctx, 40));
    pb(tryAlloc(ctx, 40));
    pb(ctx.used == 56);
    pb(ctx.oom);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_t1
OUT=/tmp/sa_t1/f1; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
    repro/mi_matrix/stdlib_async_pool_xmod/main.zig; echo "dump rc=$?"
ls "$OUT"/*.c 2>/dev/null | wc -l
```

Expected RED: `dump rc=2`, 0 `.c` emitted, diagnostics include `error[3000]` (the `std.async` field access resolves to a non-value/void module) — the re-export and module do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `sf/src/std_async.zig` with exactly:

```zig
// std_async.zig — concrete cooperative task scheduler + per-task child-frame
// pool for Z98 coroutines (Track 3, std.async). No generics, no module-scope
// mutable globals: the caller supplies all storage.
//
// Frame model (umbrella m1166/m1172):
//   - The root frame lives in the caller-owned `buf` passed to @asyncInit and
//     is OUTSIDE the pool.
//   - `Context` owns the caller-sized pool for CHILD frames only; it is a
//     per-task LIFO frame stack (bump pointer + mark), not a shared allocator.
//   - `contextAlloc` advances the bump; `contextMark`/`contextRelease` bracket a
//     child so it is reclaimed exactly when it returns. Exhaustion returns
//     `error.OutOfFrame` and sets the sticky `oom` flag; it is never a crash.
//
// Scheduler dispatch (Amendment 7): `Task` stores NO step pointer. `tick`/
// `waitAll` self-dispatch with `@asyncResume(t.frame, t.arg)`, which loads the
// hidden pointer-sized step word the compiler writes at frame offset 0. Track 3
// therefore DEPENDS on the landed Track 2 compiler core for `@asyncResume` and
// the frame/`ctx` layout. (The historical `fn_ptr_struct_field` gap is CLOSED;
// `StepFn` remains the documented `__async_step_<f>` ABI alias only.)

/// Cooperative task lifecycle.
pub const TaskState = enum(u8) {
    ready = 0,
    running = 1,
    suspended = 2,
    done = 3,
    cancelled = 4,
};

/// Pool exhaustion, surfaced by the scheduler free functions.
pub const FrameError = error{OutOfFrame};

/// The documented `__async_step_<f>` ABI alias: `fn(frame, arg) ?*void`; null =
/// terminal (done), non-null = still yielded. Documentation only — the scheduler
/// never stores or passes a `StepFn` (Amendment 7 self-dispatch via
/// `@asyncResume(t.frame, t.arg)`); Track 3 fixtures set it as the first `Frame`
/// field so it lands at frame offset 0.
pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;

// Branch (a) — DECIDED (operator ruling m1662). Context occupies the first 12
// bytes of the caller's pool buffer; the pool bytes follow: `pool_base =
// ctx + 12` (DERIVED — never stored). The by-value Context + separate
// `pool_base` alternative is REJECTED (redoes landed Track 2 work).
/// Per-task child-frame pool. The caller declares `var buf: [N]u8 = undefined;`
/// and the Context sits at the HEAD of that buffer; `capacity` is the usable
/// bytes AFTER the 12-byte header; `oom` is sticky for the pool's lifetime.
pub const Context = struct {
    used: usize,       // @ ctx+0
    capacity: usize,   // @ ctx+4 — usable bytes AFTER the 12-byte header
    oom: bool,         // @ ctx+8 — sticky
};

/// Places the Context at the head of `buf` and returns a pointer into `buf`.
pub fn contextInit(buf: []u8) *Context {
    var c: *Context = @ptrCast(*Context, buf.ptr);
    c.used = 0;
    c.capacity = buf.len - 12;
    c.oom = false;
    return c;
}

pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8 {
    if (ctx.used + size > ctx.capacity) {
        ctx.oom = true;
        return error.OutOfFrame;
    }
    var base: [*]u8 = @ptrCast([*]u8, ctx) + 12;
    var p: [*]u8 = base + ctx.used;
    ctx.used += size;
    return p;
}

pub fn contextMark(ctx: *Context) usize {
    return ctx.used;
}

pub fn contextRelease(ctx: *Context, mark: usize) void {
    ctx.used = mark;
}
```

Append to `sf/src/std.zig` (after `pub const net = ...` on line 7):

```zig
pub const async = @import("std_async.zig");
```

Modify `scripts/seed/build_from_seed.sh`:
- `:24` change the comment `#   std lib: 8 std .zig copied into <out>/lib/` -> `#   std lib: 9 std .zig copied into <out>/lib/`.
- `:139` append `"$ROOT"/sf/src/std_async.zig` to the `cp` argument list (after `"$ROOT"/sf/src/std_debug.zig`).

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_t1
ls /tmp/sa_t1/lib/ | wc -l           # expect 9
ls /tmp/sa_t1/lib/ | grep -c std_async.zig
OUT=/tmp/sa_t1/f1; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
    repro/mi_matrix/stdlib_async_pool_xmod/main.zig; echo "dump rc=$?"
( cd "$OUT" && for f in *.c; do \
    gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
        -Wno-implicit-function-declaration -I . -c "$f" -o /dev/null || echo "GCCFAIL $f"; done )
( cd "$OUT" && sh build_target.sh linux /tmp/sa_t1/f1_prog ) >/dev/null
for i in 1 2 3; do timeout 120 /tmp/sa_t1/f1_prog | md5sum; done
timeout 120 /tmp/sa_t1/f1_prog
```

Expected GREEN: `lib/` = 9 files including `std_async.zig`; `dump rc=0`; no `GCCFAIL`; 3 identical stdout md5s `38f19e53c09cbb69c1919cb5385c708d`; stdout exactly `1 1 1 1 0 1 1`; `run rc=0`. Also confirm the compiler fixed point did not move: the build gate prints `two-hop closure OK: hop1 == hop2 == eda943dc1f77a48eae039e39ea4bfe04`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/std_async.zig sf/src/std.zig scripts/seed/build_from_seed.sh \
    repro/mi_matrix/stdlib_async_pool_xmod
git commit -m "feat: std.async — Context pool + std.zig re-export + 9-file lib install (ASYNCTRACK3)"
```

---

### Task 2: `Task` + `Scheduler` + `tick`

**Files:**
- Modify: `sf/src/std_async.zig` (append `Task`/`Scheduler`/`schedulerInit`/`addTask`/`tick`)
- Create: `repro/mi_matrix/stdlib_async_sched_xmod/main.zig`
- Create: `repro/mi_matrix/stdlib_async_oom_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDASYNC-report.md` (`## Task 2`)

**Interfaces:**
- Consumes: Task 1's `TaskState`/`Context`/pool.
- Produces: `Task`, `Scheduler`, `schedulerInit`, `addTask`, `tick` (including `tick`'s `error.OutOfFrame` propagation from a task's sticky `Context.oom`); self-dispatch through the frame step word (`@asyncResume(t.frame, t.arg)`, no `Task.step`, no `step` parameter) exercised end-to-end.

- [ ] **Step 1: Write the failing test**

Create `repro/mi_matrix/stdlib_async_sched_xmod/main.zig`:

```zig
// stdlib_async_sched_xmod — Track 3 std.async scheduler fixture.
//
// The module is imported by file name so the full API (struct literals +
// enum literals) is available; it resolves from <exe_dir>/lib via the std
// search path. Three tasks each yield twice, then emit id*10:
//   addTask(&t0) -> true; count -> 3; suspend(t2) -> state 2;
//   waitAll resumes every task to done -> 10 20 30.
// GREEN: exact stdout 1 3 2 10 20 30 (RUNRC=0). Pins self-dispatch: the library
// `tick` calls `@asyncResume(t.frame, t.arg)` and the hand-built frame's step
// word at offset 0 is invoked; also the Task/Scheduler records.
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32, id: i32, val: i32 };

fn stepInc(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.ticks < 2) {
        fr.ticks += 1;
        return f;
    }
    fr.val = fr.id * 10;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 1, .val = 0 };
    var f1: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 2, .val = 0 };
    var f2: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 3, .val = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var r2: i32 = 0;
    var buf0: [16]u8 = undefined;
    var buf1: [16]u8 = undefined;
    var buf2: [16]u8 = undefined;
    var ctx0 = sa.contextInit(buf0[0..]);
    var ctx1 = sa.contextInit(buf1[0..]);
    var ctx2 = sa.contextInit(buf2[0..]);
    var tasks: [3]sa.Task = undefined;
    var s = sa.schedulerInit(tasks[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t2 = sa.Task{ .frame = @ptrCast(*void, &f2), .ctx = ctx2, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r2), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    p(if (sa.addTask(&s, &t0)) 1 else 0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);
    p(@intCast(i32, s.count));
    sa.suspend(&s, &s.tasks[2]);
    p(@intCast(i32, @intCast(u8, s.tasks[2].state)));
    sa.waitAll(&s) catch p(-1);
    p(f0.val);
    p(f1.val);
    p(f2.val);
}
```

Also create `repro/mi_matrix/stdlib_async_oom_xmod/main.zig` (pins `tick`'s `error.OutOfFrame` propagation from the sticky `Context.oom`):

```zig
// stdlib_async_oom_xmod — Track 3 std.async pool-exhaustion fixture.
// contextAlloc of 1000 into a 16-byte pool sets sticky oom (line 1), and tick
// surfaces error.OutOfFrame from the running task's context (line 2), not a
// crash. GREEN: exact stdout 1 1 (RUNRC=0).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32 };

fn stepNoop(f: *void, arg: ?*void) ?*void {
    _ = f;
    _ = arg;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var fr: Frame = Frame{ .step = stepNoop, .ticks = 0 };
    var buf: [16]u8 = undefined;
    var ctx = sa.contextInit(buf[0..]);
    _ = sa.contextAlloc(ctx, 1000) catch 0;
    p(@intCast(i32, if (ctx.oom) 1 else 0));

    var tasks: [1]sa.Task = undefined;
    var s = sa.schedulerInit(tasks[0..]);
    var t = sa.Task{ .frame = @ptrCast(*void, &fr), .ctx = ctx, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &fr), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    _ = sa.addTask(&s, &t);
    sa.tick(&s) catch {
        p(1);
        return;
    };
    p(0);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /workspace/znineeight
for name in sched oom; do
  OUT=/tmp/sa_t1/f2_$name; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
      repro/mi_matrix/stdlib_async_${name}_xmod/main.zig >/dev/null 2>/dev/null
  echo "$name dump rc=$?"
done
```

Expected RED: `dump rc=2` for each (Task 1's library has no `Task`/`Scheduler`/`schedulerInit`/`addTask`/`tick`); 0 `.c`.

- [ ] **Step 3: Write minimal implementation**

Append to `sf/src/std_async.zig`:

```zig
/// One cooperative task. `frame` is the root frame in caller `buf`; `ctx` is the
/// task's child-frame pool; `result` points at the caller's result slot (L3).
pub const Task = struct {
    frame: *void,
    ctx: *Context,
    state: TaskState,
    cancel_requested: bool,
    result: *void,
    arg: *void,
    waiting_on: *Task,
    has_waiting_on: bool,
};

pub const Scheduler = struct {
    tasks: [*]Task,
    capacity: usize,
    count: usize,
    current: usize,
};

pub fn schedulerInit(tasks: []Task) Scheduler {
    var s = Scheduler{ .tasks = tasks.ptr, .capacity = tasks.len, .count = 0, .current = 0 };
    return s;
}

pub fn addTask(s: *Scheduler, t: *Task) bool {
    if (s.count >= s.capacity) return false;
    s.tasks[s.count] = t.*;
    s.tasks[s.count].state = TaskState.ready;
    s.tasks[s.count].has_waiting_on = false;
    s.count += 1;
    return true;
}

fn allSettled(s: *Scheduler) bool {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        if (s.tasks[i].state != TaskState.done and s.tasks[i].state != TaskState.cancelled) {
            return false;
        }
    }
    return true;
}

/// Resume every ready/suspended task once. Returns `error.OutOfFrame` when a
/// resumed task's context pool overflowed, without resuming further tasks.
pub fn tick(s: *Scheduler) FrameError!void {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        var t: *Task = &s.tasks[i];
        var active: bool = true;
        if (t.state == TaskState.done) active = false;
        if (t.state == TaskState.cancelled) active = false;
        if (active and t.cancel_requested) {
            t.state = TaskState.cancelled;
            active = false;
        }
        if (active and t.has_waiting_on) {
            var dep: *Task = t.waiting_on;
            if (dep.state != TaskState.done and dep.state != TaskState.cancelled) {
                active = false;
            } else {
                t.has_waiting_on = false;
            }
        }
        if (active) {
            s.current = i;
            t.state = TaskState.running;
            var r: ?*void = @asyncResume(t.frame, t.arg);
            if (t.ctx.oom) return error.OutOfFrame;
            if (r == null) {
                t.state = TaskState.done;
            } else {
                t.state = TaskState.suspended;
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run (only the std module changed, so re-run the seed install to refresh `/tmp/sa_t1/lib/`, then dump/compile/run both fixtures):

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_t1
declare -A md5=( [sched]=29d3c32a9c1d30152faffca161cccac0 \
                 [oom]=f2160c8ffedf48068f2e1137e0a3a7e7 )
for name in sched oom; do
  OUT=/tmp/sa_t1/f2_$name; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
      repro/mi_matrix/stdlib_async_${name}_xmod/main.zig; echo "$name dump rc=$?"
  ( cd "$OUT" && for f in *.c; do \
      gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
          -Wno-implicit-function-declaration -I . -c "$f" -o /dev/null || echo "GCCFAIL $name $f"; done )
  ( cd "$OUT" && sh build_target.sh linux /tmp/sa_t1/f2_${name}_prog ) >/dev/null
  got=$(timeout 120 /tmp/sa_t1/f2_${name}_prog | md5sum | cut -d' ' -f1)
  echo "$name stdout md5=$got expected=${md5[$name]}"
  timeout 120 /tmp/sa_t1/f2_${name}_prog
done
```

Expected GREEN:
- `sched`: `dump rc=0`, no `GCCFAIL`, md5 `29d3c32a9c1d30152faffca161cccac0`, stdout exactly `1 3 2 10 20 30`.
- `oom`: `dump rc=0`, no `GCCFAIL`, md5 `f2160c8ffedf48068f2e1137e0a3a7e7`, stdout exactly `1 1`.
Both `run rc=0`. The `sched` fixture also pins self-dispatch: the library `tick` calls `@asyncResume(t.frame, t.arg)` and the hand-built `Frame`'s step word at offset 0 is invoked (no `Task.step`, no `step` parameter).

- [ ] **Step 5: Commit**

```bash
git add sf/src/std_async.zig repro/mi_matrix/stdlib_async_sched_xmod \
    repro/mi_matrix/stdlib_async_oom_xmod
git commit -m "feat: std.async — Task/Scheduler/tick + OutOfFrame + fixtures (ASYNCTRACK3)"
```

---

### Task 3: `suspend` / `awaitTask` / `cancel` / `cancelAll` / `waitAll` + error model

**Files:**
- Modify: `sf/src/std_async.zig` (append `suspend`/`awaitTask`/`cancel`/`cancelAll`/`waitAll`)
- Create: `repro/mi_matrix/stdlib_async_await_xmod/main.zig`
- Create: `repro/mi_matrix/stdlib_async_cancelall_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDASYNC-report.md` (`## Task 3`)

**Interfaces:**
- Consumes: Task 2's `Task`/`Scheduler`/`tick`.
- Produces: the complete scheduler API (`suspend`/`awaitTask`/`cancel`/`cancelAll`/`waitAll`); `waitAll` returning `error.OutOfFrame` end-to-end.

- [ ] **Step 1: Write the failing tests**

Create `repro/mi_matrix/stdlib_async_await_xmod/main.zig`:

```zig
// stdlib_async_await_xmod — Track 3 std.async await + cancel fixture.
// t1 waits on t0 (dependency), t2 is cancelled before it completes:
//   t0 -> 10 (id 1), t1 -> 20 (id 2) only after t0, t2 -> state 4.
// GREEN: exact stdout 10 20 4 (RUNRC=0).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct {
    step: sa.StepFn,
    ticks: u32,
    id: i32,
    val: i32,
};

fn stepInc(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.ticks < 2) {
        fr.ticks += 1;
        return f;
    }
    fr.val = fr.id * 10;
    return null;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 1, .val = 0 };
    var f1: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 2, .val = 0 };
    var f2: Frame = Frame{ .step = stepInc, .ticks = 0, .id = 3, .val = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var r2: i32 = 0;

    var buf0: [16]u8 = undefined;
    var buf1: [16]u8 = undefined;
    var buf2: [16]u8 = undefined;
    var ctx0 = sa.contextInit(buf0[0..]);
    var ctx1 = sa.contextInit(buf1[0..]);
    var ctx2 = sa.contextInit(buf2[0..]);

    var tasks: [3]sa.Task = undefined;
    var s = sa.schedulerInit(tasks[0..]);

    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t2 = sa.Task{ .frame = @ptrCast(*void, &f2), .ctx = ctx2, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r2), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };

    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);

    s.current = 1;
    sa.awaitTask(&s, &s.tasks[0]);
    sa.cancel(&s, &s.tasks[2]);

    sa.waitAll(&s) catch p(-1);
    p(f0.val);
    p(f1.val);
    p(@intCast(i32, @intCast(u8, s.tasks[2].state)));
}
```

Create `repro/mi_matrix/stdlib_async_cancelall_xmod/main.zig`:

```zig
// stdlib_async_cancelall_xmod — Track 3 std.async cancelAll fixture.
// Three never-completing tasks are resumed once, then cancelAll is requested;
// waitAll settles every task to cancelled (state 4).
// GREEN: exact stdout 4 4 4 (RUNRC=0).
const std = @import("std");
const sa = @import("std_async.zig");

const Frame = struct { step: sa.StepFn, ticks: u32 };

fn stepLong(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    fr.ticks += 1;
    return f;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var f0: Frame = Frame{ .step = stepLong, .ticks = 0 };
    var f1: Frame = Frame{ .step = stepLong, .ticks = 0 };
    var f2: Frame = Frame{ .step = stepLong, .ticks = 0 };
    var r0: i32 = 0;
    var r1: i32 = 0;
    var r2: i32 = 0;
    var buf0: [16]u8 = undefined;
    var buf1: [16]u8 = undefined;
    var buf2: [16]u8 = undefined;
    var ctx0 = sa.contextInit(buf0[0..]);
    var ctx1 = sa.contextInit(buf1[0..]);
    var ctx2 = sa.contextInit(buf2[0..]);
    var tasks: [3]sa.Task = undefined;
    var s = sa.schedulerInit(tasks[0..]);
    var t0 = sa.Task{ .frame = @ptrCast(*void, &f0), .ctx = ctx0, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r0), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t1 = sa.Task{ .frame = @ptrCast(*void, &f1), .ctx = ctx1, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r1), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    var t2 = sa.Task{ .frame = @ptrCast(*void, &f2), .ctx = ctx2, .state = sa.TaskState.ready, .cancel_requested = false, .result = @ptrCast(*void, &r2), .arg = @ptrCast(*void, @intToPtr(*void, 0)), .waiting_on = @ptrCast(*sa.Task, @intToPtr(*void, 0)), .has_waiting_on = false };
    _ = sa.addTask(&s, &t0);
    _ = sa.addTask(&s, &t1);
    _ = sa.addTask(&s, &t2);
    sa.tick(&s) catch p(-1);
    sa.cancelAll(&s);
    sa.waitAll(&s) catch p(-1);
    p(@intCast(i32, @intCast(u8, s.tasks[0].state)));
    p(@intCast(i32, @intCast(u8, s.tasks[1].state)));
    p(@intCast(i32, @intCast(u8, s.tasks[2].state)));
}
```


- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /workspace/znineeight
for name in await cancelall; do
  OUT=/tmp/sa_t1/f3_$name; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
      repro/mi_matrix/stdlib_async_${name}_xmod/main.zig >/dev/null 2>/dev/null
  echo "$name dump rc=$?"
done
```

Expected RED: `dump rc=2` for each (Task 2's library has no `awaitTask`/`cancel`/`cancelAll`); 0 `.c`.

- [ ] **Step 3: Write minimal implementation**

Append to `sf/src/std_async.zig`:

```zig
/// Mark `t` suspended (cooperative yield bookkeeping).
pub fn suspend(s: *Scheduler, t: *Task) void {
    _ = s;
    t.state = TaskState.suspended;
}

/// Suspend the currently-running task until `t` is done or cancelled.
pub fn awaitTask(s: *Scheduler, t: *Task) void {
    var cur: *Task = &s.tasks[s.current];
    cur.state = TaskState.suspended;
    cur.waiting_on = t;
    cur.has_waiting_on = true;
}

/// Request cooperative cancellation of `t`; observed at the next tick boundary.
pub fn cancel(s: *Scheduler, t: *Task) void {
    _ = s;
    t.cancel_requested = true;
}

pub fn cancelAll(s: *Scheduler) void {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        if (s.tasks[i].state != TaskState.done) {
            s.tasks[i].cancel_requested = true;
        }
    }
}

/// Tick until every task is done or cancelled.
pub fn waitAll(s: *Scheduler) FrameError!void {
    while (!allSettled(s)) {
        try tick(s);
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_t1
declare -A md5=( [await]=7bbb0c578b9e01e312325b4d2e5f8c93 \
                 [cancelall]=83b80a0f4d19b15f7cb1da65abf557a9 )
for name in await cancelall; do
  OUT=/tmp/sa_t1/f3_$name; rm -rf "$OUT"; mkdir -p "$OUT"
  timeout 120 /tmp/sa_t1/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
      repro/mi_matrix/stdlib_async_${name}_xmod/main.zig; echo "$name dump rc=$?"
  ( cd "$OUT" && for f in *.c; do \
      gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
          -Wno-implicit-function-declaration -I . -c "$f" -o /dev/null || echo "GCCFAIL $name $f"; done )
  ( cd "$OUT" && sh build_target.sh linux /tmp/sa_t1/f3_${name}_prog ) >/dev/null
  got=$(timeout 120 /tmp/sa_t1/f3_${name}_prog | md5sum | cut -d' ' -f1)
  echo "$name stdout md5=$got expected=${md5[$name]}"
  timeout 120 /tmp/sa_t1/f3_${name}_prog
done
```

Expected GREEN:
- `await`: `dump rc=0`, no `GCCFAIL`, md5 `7bbb0c578b9e01e312325b4d2e5f8c93`, stdout `10 20 4`.
- `cancelall`: `dump rc=0`, no `GCCFAIL`, md5 `83b80a0f4d19b15f7cb1da65abf557a9`, stdout `4 4 4`.
Both `run rc=0`.

- [ ] **Step 5: Commit**

```bash
git add sf/src/std_async.zig repro/mi_matrix/stdlib_async_await_xmod \
    repro/mi_matrix/stdlib_async_cancelall_xmod
git commit -m "feat: std.async — await/suspend/cancel/cancelAll/waitAll (ASYNCTRACK3)"
```

---

### Task 4: Install touchpoints (archive, self-compile, docs) + bare-import re-verify

**Files:**
- Modify: `scripts/seed/archive_seed.sh:28-29,109,156-158,210-211`
- Modify: `scripts/self_compile/build_zig1_5.sh:12`
- Modify: `docs/sf/QUICK_REF.md:36-37,98`
- Report: `.superpowers/sdd/task-STDASYNC-report.md` (`## Task 4`)

**Interfaces:**
- Consumes: Tasks 1–3's completed `sf/src/std_async.zig`.
- Produces: a self-consistent 9-file std set across every install enumeration; a fresh seed build that resolves `std.async` and `@import("std_async.zig")`.

- [ ] **Step 1: Edit every install enumeration**

`scripts/seed/archive_seed.sh`:
- `:28-29` header comment: add `std_async.zig` to the `lib/` repo list and change `8` to `9`.
- `:109` loop: `for f in std.zig std_io.zig std_arena.zig std_net.zig std_str.zig std_mem.zig std_math.zig std_debug.zig std_async.zig; do`.
- `:156-158` `SEED_README.txt` heredoc: `zig1-seed/lib/        the 8 std .zig` -> `the 9 std .zig`, listing `std_async.zig`.
- `:210-211` `SEED_README.txt` heredoc: `lib/ with the 8 std .zig` -> `lib/ with the 9 std .zig`.

`scripts/self_compile/build_zig1_5.sh:12`: append `"$ROOT"/sf/src/std_async.zig` to the `cp ... "$OUT/lib/"` list.

`docs/sf/QUICK_REF.md`:
- `:36-37`: `the 8 std .zig: std, std_io, ... std_debug` -> `the 9 std .zig: ..., std_debug, std_async` (keep the surrounding line wrap).
- `:98`: append ` sf/src/std_async.zig` before the ` <exe_dir>/lib/` destination in the `mkdir -p ... && cp ...` recipe.

- [ ] **Step 2: Fresh seed build + bare-import re-verify**

Run:

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_t4
ls /tmp/sa_t4/lib/ | wc -l; ls /tmp/sa_t4/lib/ | grep std_async.zig
# canonical recipe resolves std.async (bare) and the module file (direct)
OUT=/tmp/sa_t4/pool; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 /tmp/sa_t4/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
    repro/mi_matrix/stdlib_async_pool_xmod/main.zig; echo "pool dump rc=$?"
grep -l 'std_async' "$OUT"/*.c >/dev/null && echo "std_async module emitted"
OUT=/tmp/sa_t4/sched; rm -rf "$OUT"; mkdir -p "$OUT"
timeout 120 /tmp/sa_t4/zig1_5_clean -ffast --dump-c89 --output-dir "$OUT" \
    repro/mi_matrix/stdlib_async_sched_xmod/main.zig; echo "sched dump rc=$?"
( cd "$OUT" && sh build_target.sh linux /tmp/sa_t4/sched_prog ) >/dev/null
timeout 120 /tmp/sa_t4/sched_prog
```

Expected: `lib/` = 9 files incl. `std_async.zig`; `pool dump rc=0` and `std_async module emitted`; `sched dump rc=0`; `sched_prog` stdout `1 3 2 10 20 30`.

- [ ] **Step 3: Emitted-support byte-equality gate**

Run:

```bash
cd /workspace/znineeight
bash scripts/check_emit_support.sh /tmp/sa_t4/zig1_5_clean
```

Expected: `[check] OK: 5/5 support files byte-identical to canonical` (the user module does not change any emitted support file).

- [ ] **Step 4: Commit**

```bash
git add scripts/seed/archive_seed.sh scripts/self_compile/build_zig1_5.sh docs/sf/QUICK_REF.md
git commit -m "docs: std.async — 9-file std install touchpoints (seed/self-compile/QUICK_REF) (ASYNCTRACK3)"
```

---

### Task 5: Closeout — corpus battery, `EXPECTED_FAIL` bump, seed-lib rotation, docs GATE

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (header + counts)
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (rotation)
- Modify: `docs/sf/QUICK_REF.md` (newest-first baseline bullet; optionally the std count lines)
- Report: `.superpowers/sdd/task-STDASYNC-report.md` (`## Task 5`)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: the full gate evidence, the updated manifest, and the rotated seed (9-module `lib/`, unchanged fixed point).

- [ ] **Step 1: Full corpus sweep**

Build once, then classify the whole universe (follows `docs/sf/QUICK_REF.md:134-145`; read the GREEN/reject set from `EXPECTED_FAIL.md` rather than guessing):

```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/sa_close
ZIG1=/tmp/sa_close/zig1_5_clean
ok=0; green=0; fail=0; ice=0; crash=0
for d in $(bash scripts/corpus/list_corpus_dirs.sh); do
  dir="${d%/}"
  out="/tmp/sa_close/corpus/$(echo "$dir" | tr '/' '_')"
  rm -rf "$out"; mkdir -p "$out"
  timeout 120 "$ZIG1" -ffast --dump-c89 --output-dir "$out" "$dir/main.zig" >/dev/null 2>"$out/.err"
  rc=$?
  if [ "$rc" -ge 128 ]; then crash=$((crash+1)); echo "CRASH $dir";
  elif [ -z "$(ls "$out"/*.c 2>/dev/null)" ]; then
    if grep -q 'error\[' "$out/.err"; then green=$((green+1)); else fail=$((fail+1)); echo "FAIL(no-c) $dir"; fi
  else
    bad=0
    for f in "$out"/*.c; do
      gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
          -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null 2>/dev/null || bad=1
    done
    if [ "$bad" = 0 ]; then ok=$((ok+1)); else fail=$((fail+1)); echo "FAIL(gcc) $dir"; fi
  fi
done
echo "OK=$ok GREEN=$green FAIL=$fail ICE=$ice CRASH=$crash"
```

Expected: universe `604` dirs = `OK=565 / GREEN=36 / FAIL=3 / ICE=0 / CRASH=0`. Reconcile the GREEN/FAIL sets against the v80 manifest (see `repro/mi_matrix/EXPECTED_FAIL.md` for the exact sets; the five new async dirs are OK, not GREEN); if the printed `FAIL`/`GREEN` dir names differ from `EXPECTED_FAIL.md`, STOP-present before changing the manifest. Repeat with the default `-fsafe` (omit `-ffast`) and assert the counts are identical (zero-asymmetric).

- [ ] **Step 2: Bump `EXPECTED_FAIL.md`**

Update line 1 `# mi_matrix corpus — expected-fail manifest (v80 2026-09-13)` -> `(v81 2026-09-13)`, and prepend a short section immediately under the header recording the Track 3 movement:

```markdown
## std.async 9-module install (v81 2026-09-13)

Track 3 (`2026-09-13-std-async-plan.md`) added `sf/src/std_async.zig` and its
`std.zig` re-export, and installed it at every std touchpoint (9-file `lib/`).
No compiler-graph change: the self-emission fixed point is UNMOVED
`eda943dc1f77a48eae039e39ea4bfe04`. Corpus `-s0` universe **604 dirs** =
**565 OK / 36 GREEN / 3 FAIL / 0 ICE / 0 CRASH**; `-ffast` == `-fsafe`
zero-asymmetric. Five new OK dirs: `stdlib_async_{pool,sched,await,cancelall,oom}_xmod`.
```

(Track 2's landed fixed point; re-verify at Task 1.)

- [ ] **Step 3: Seed-lib rotation**

Confirm N-hop closure and that the fixed point is unchanged, then rotate:

```bash
cd /workspace/znineeight
md5sum /tmp/sa_close/hop2/zig1_hop2     # expect the fixed point (eda943dc...)
bash scripts/seed/archive_seed.sh /tmp/sa_close/hop2/zig1_hop2 /tmp/sa_close/hop2 \
    release/seed/zig1-seed.tgz --update-changelog
tar tzf release/seed/zig1-seed.tgz | grep 'zig1-seed/lib/' | sort
tar xzf release/seed/zig1-seed.tgz -O zig1-seed/lib/std_async.zig | md5sum
md5sum sf/src/std_async.zig
```

Expected: `[archive] gcc-only rebuild of archive C md5 (fixed point): eda943dc1f77a48eae039e39ea4bfe04`; archive `lib/` lists 9 modules including `std_async.zig`; the archived `std_async.zig` md5 equals the repo file's. Then append a one-line note to the new `release/seed/CHANGELOG.md` entry: **"9-file std lib install:** this archive's `lib/` carries all 9 std `.zig` (the 8 existing + `std_async.zig`), self-consistent with `build_from_seed.sh`/`archive_seed.sh`."

- [ ] **Step 4: Docs GATE + report**

Add a newest-first bullet to `docs/sf/QUICK_REF.md`'s baseline list recording: Track 3 `std.async` landed; 9-file lib; fixed point unmoved; corpus 604 = 565/36/3; the five new fixtures and their md5s. Append `## Task 5` to `.superpowers/sdd/task-STDASYNC-report.md` with the measured counts, the archive md5, the fixed point, and the `check_emit_support` result. One ledger line in `.superpowers/sdd/progress.md`.

- [ ] **Step 5: Commit + STOP-present**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md release/seed/zig1-seed.tgz \
    release/seed/CHANGELOG.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — std.async library + 9-file seed lib (ASYNCTRACK3)"
```

STOP-present the closeout: corpus counts, fixed-point md5 (unmoved), archive md5, the 9-module `lib/` listing, and the five fixture md5s. Await operator GO; this is the plan's last implementation task (Task 6 is the docs-only Track-3 alignment decision record).

---

### Task 6: Track-3 alignment — `Context` layout (DECIDED: branch (a))

**Type:** decision record (docs-only; **not** part of the five implementation
tasks; no `sf/src` change). This records the Task-7 review finding **I1**
(Context layout divergence) and its resolution.

**Finding (I1).** The compiler core (Track 2, Task 7; commit `b23ca20a`) pinned
the pool header `{ used @ ctx+0, capacity @ ctx+4, oom @ ctx+8, pool base
= ctx+12 (DERIVED) }`. The std-async design originally named `{ pool@0,
capacity@4, used@8, oom@12 }` (pool as a **stored** slice). The two are
**incompatible**, and a cross-read silently corrupts memory (see the design §4
WARNING).

**Decision — branch (a) accepted (operator ruling m1662).** `std.async.Context`
adopts the compiler-core inline layout `{ used, capacity, oom; pool bytes
follow }`, with the Context at the **head** of the caller's pool buffer and
`pool_base = ctx+12` **derived** (never stored). **Header = 12 B** (`used` 4 +
`capacity` 4 + `oom` 1 + 3 pad), saving **4 bytes per context** over branch (b).
`contextInit(buf: []u8) *Context` returns a pointer into `buf`; callers pass
`ctx` (not `&ctx`) to `contextAlloc`/`contextMark`/`contextRelease` and read
`ctx.used`/`ctx.oom`. Applied to the spec §3.1/§4 and to Task 1's `Context` code
block and pool fixture in this amendment.

**Rejected — branch (b) (by-value `Context` + separate `pool_base`).** Revising
the compiler core to `{pool@0, capacity@4, used@8, oom@12}` with a **stored**
slice (header 16 B, 4 bytes more per context) was **rejected**: it redoes landed
Track 2 work for a smaller safety margin, and a stored `pool_base` is a second
source of truth that can diverge from the actual allocation. (Worth a pass after
the track closeout to re-check.)

**Status:** applied here (past tense) — the spec §3.1/§4 and Task 1 already carry
branch (a); nothing is deferred to dispatch.

---

## Self-Review

**Spec coverage** (against `2026-09-13-std-async-design.md`):
- §3.1 public API -> Task 1 (types/Context/pool), Task 2 (`Task`/`Scheduler`/`tick`), Task 3 (`suspend`/`awaitTask`/`cancel`/`cancelAll`/`waitAll`).
- §3.2 Context pool semantics (m1166/m1172) -> Task 1 implementation + `stdlib_async_pool_xmod`.
- §3.3 Step ABI + self-dispatch (Amendment 7) -> `StepFn` (documented alias only) in Task 1; self-dispatch evidence in Task 2 (`stdlib_async_sched_xmod`).
- §3.4 scheduler semantics -> Task 2 `tick` + Task 3 `awaitTask`/`cancel`/`cancelAll`/`waitAll`; fixtures.
- §3.5 error model -> Task 2 `stdlib_async_oom_xmod` (`error.OutOfFrame` from `tick`, no crash) and Task 3 `waitAll` returning `FrameError!void`.
- §3.6 install surface -> Task 1 (`build_from_seed.sh`), Task 4 (`archive_seed.sh`, `build_zig1_5.sh`, `QUICK_REF`), Task 5 (seed rotation).
- §4 Interfaces -> `StepFn` in Task 1; the `Context` layout canon is design §3.1 (DECIDED: branch (a)) and is recorded by **Task 6**; the Track 2 reconciliation is documented in the subspec §4/§7.
- §6 Testing -> the five fixtures, corpus sweep, `check_emit_support`, seed rotation (Tasks 1–3, 4, 5).
- §7 Risks -> guarded by the Global Constraints (no optional struct field, no globals, two-file `sf/src` scope, install enumeration complete).

**Placeholder scan:** no "TBD/TODO/later"; every code step shows the exact module/fixture text; every command carries its expected rc/stdout/md5. The one branch (`EXPECTED_FAIL` GREEN reconciliation) has an explicit STOP-present instruction.

**Type/name consistency:** `TaskState`, `FrameError`, `StepFn`, `Context`, `contextInit`/`contextAlloc`/`contextMark`/`contextRelease`, `Task`, `Scheduler`, `schedulerInit`/`addTask`/`tick`/`suspend`/`awaitTask`/`cancel`/`cancelAll`/`waitAll`, `waiting_on`/`has_waiting_on` (no `Task.step`), and the fixture names/paths/md5s are identical across the subspec, the module code blocks, and the commands. The Task 1 + Task 2 + Task 3 code blocks concatenate to the `std_async.zig` module.

**Amendable in place.** This plan is amendable: the fixtures hand-build frames (step function first field) and drive them through the library scheduler, which self-dispatches via Track 2's `@asyncResume`; if Track 2's `__async_step_<f>` ABI, `@asyncResume` signature, or Context access mechanism changes, update `StepFn`/the Context layout and the `stdlib_async_*_xmod` fixtures in lockstep (and the subspec §4 reconciliation note).
