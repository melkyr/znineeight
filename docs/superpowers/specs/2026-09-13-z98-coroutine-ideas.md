# Formal Plan: Z98 Coroutine Implementation via `@async*` Builtins

Surface: Zig issue #23446's four builtins. Std library layered on top. No language keywords.

---

## Cross-cutting decisions (locked before Stage 1)

| Decision | Value | Reason |
|---|---|---|
| Surface | `@asyncFrameSize`, `@asyncInit`, `@asyncResume`, `@asyncSuspend` | #23446, Zig-aligned |
| Cancellation | Cooperative via a `cancel_requested` flag in the std `Task` | #23446 has no cancel builtin; std-level is correct |
| Result delivery | Caller-provided result slot (`*void`) | No generics; old-Zig `@asyncCall` pattern |
| State counter width | `u8` if ≤200 suspension points, `u16` if ≤50000, else `u32` | Smallest fitting; deterministic |
| Suspension in `defer` | `error[3000]` | Consistent with existing `break`/`continue`/`return` ban |
| Function pointers | Suspending functions cannot be stored in fn pointers → `error[3020]` | Static analysis cannot see through fn pointers |
| Analysis ordering | Parse all → Stage 1 (all) → Stage 2 (all) → Stage 3+4 (all) | Cross-module frame lookup needs Stage 2 complete |

---

## Stage 1 — Suspension Detection

### Parts
- `is_suspending: bool` added to the function symbol record.
- Call-graph construction over all parsed modules.
- Worklist algorithm: a function is suspending if its body contains `@asyncSuspend` **or** it calls a suspending function. Iterate to fixed point.
- Propagate through imports; every module's function record is updated.

### Cross-module
The call graph is program-wide. Module resolution happens before this pass. An imported function's `is_suspending` is resolved by the time any caller is analyzed, because the fixed point iterates over the whole program.

### Edge cases
1. **Recursion / mutual recursion** — worklist handles; verify termination with a cycle fixture.
2. **Function pointers to suspending functions** — `error[3020]`. Detected at the assignment/coercion site, not at the call site.
3. **Suspension under a compile-time-false branch** — no `comptime`, so all branches are real. The function is suspending.
4. **Dead code** — a suspending function never called still gets a frame. Not optimized away.
5. **`main` or `export fn` becoming suspending** — allowed; the caller drives it via a scheduler loop. Document the canonical entry pattern.
6. **Suspension inside an `if` expression** — propagates; the function is suspending.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 01 | direct `@asyncSuspend` call | marked suspending |
| 02 | indirect via one callee | marked suspending |
| 03 | mutual recursion A↔B | both suspending; algorithm terminates |
| 04 | no suspension | not marked |
| 05 | suspending fn stored in `fn()` pointer | `error[3020]` |
| 06 | `export fn` calls suspending | marked; allowed |
| 07 | suspending fn never called | marked; frame still generated |

---

## Stage 2 — Frame Layout

### Parts
- Per-function CFG construction.
- Liveness analysis: which locals and temps are live at each suspension point.
- Frame struct synthesis (declaration order preserved):
  - `state: uN` (chosen width)
  - Each hoisted local (aligned)
  - All parameters (always hoisted — they are live at entry)
- `@asyncFrameSize(fn)` returns the constant.
- Frame struct name: `__Z98Frame_<mangled_fn>` in emitted C89.

### Sizing rules
- Count suspension points `N`.
- Width: `u8` if `N ≤ 200`, `u16` if `N ≤ 50000`, else `u32`.
- Alignment: largest field alignment, capped at 4 unless `f64` present (then 8, with a note about C89 `double` alignment).
- All fields packed in declaration order; no reordering (determinism).

### Cross-module
Frame types are **function-local**, never exported. `@asyncFrameSize` is comptime-known at any call site, including across modules, because Stage 2 completes for all modules before Stage 3 begins. No header coordination is required between modules.

### Edge cases
1. **No locals live across suspension** — frame is `{ state: u8 }`; size 1 padded to alignment 4.
2. **Large local** — `[256]u8` buffer live across suspension → 256-byte frame.
3. **Pointer to local** — `&local` that survives a suspension must resolve to a frame offset; verify pointer identity after resume.
4. **Loop variable** captured by `for` and live across suspension — hoisted.
5. **Switch payload capture** — immutable, but live across suspension if used after — hoisted.
6. **Optional/error-union unwrap temps** from `try`/`catch`/`orelse` — intermediate temps can be live across suspension; treated like locals.
7. **Suspension in `defer`** — rejected at Stage 1 (`error[3000]`); no frame impact.
8. **`undefined` initialization** — under `-fsafe`, frame is `0xAA`-filled; under `-ffast`, no fill. Document.
9. **`f64` field alignment** — C89 does not guarantee 8-byte alignment on all compilers; if a frame contains `f64`, alignment is 8 and the doc notes the caveat.
10. **Zero suspension points after Stages 1–2 disagree** — impossible; Stage 1 defines suspending, Stage 2 runs only on those.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 10 | no hoisted locals | frame size = alignment size (4 or 1) |
| 11 | one `i32` live across | size = 4 (state) + 4 (local) |
| 12 | `[256]u8` live across | size = 4 (state) + 256 |
| 13 | mixed `i32` + `u8` + `i64` | verify offsets and padding |
| 14 | `&local` across suspension | pointer resolves to frame offset after resume |
| 15 | 300 suspension points | state field is `u16` |
| 16 | `-fsafe` frame fill | frame bytes = `0xAA` on entry |
| 17 | loop var live across | hoisted; value preserved |
| 18 | switch capture live across | hoisted; value preserved |

---

## Stage 3 — State Machine Lowering

### Parts
For each suspending function `foo`:
- Emit struct `__Z98Frame_foo`.
- Emit `void foo_step(struct __Z98Frame_foo *f, void *arg, void *result)`.
- State `0` = entry; each suspension point gets a `case N:` (N ≥ 1); `TERMINAL` = final.
- Suspension:
  - store live locals to `f->...`
  - set `f->state = N+1`
  - return from step function
- Resume:
  - `switch (f->state)` dispatches to the correct case
  - `case N:` continues after the suspension point
- Completion:
  - store result into `*result`
  - set `f->state = TERMINAL`
  - return

### Cross-module
The step function is emitted in the owning module's C89 file. Callers use `@asyncInit`/`@asyncResume` (builtins), so the step function is **never called directly** across modules. No symbol export beyond what `export fn` already does.

### Edge cases
1. **Suspension in loop** — loop variable and loop condition temporaries hoisted.
2. **Suspension in switch prong with capture** — capture hoisted; switch dispatch re-entered correctly on resume.
3. **Nested suspension** — caller's frame holds its own state; callee has a separate frame; no frame nesting on the C stack.
4. **Error propagation across suspension** — `try suspending_call()` — error stored in frame during suspension, checked on resume; the error path runs through the frame.
5. **Recursion** — each recursive invocation gets its own frame (caller-allocated). No frame sharing.
6. **`defer` before a suspension** — the `defer` runs at scope exit; if scope exit is after a suspension, the deferred code runs on the resumed path, but it cannot itself suspend (already forbidden).
7. **Multiple suspensions in one expression** — AST lifting (§5) has already broken complex expressions into statement blocks with temporaries; each suspension is now at a statement boundary. Verify the lowering order.
8. **Double resume after terminal** — returns `null`; does not re-execute.
9. **Resume with wrong state value** — unreachable by construction; default case is `unreachable` → traps (per spec).
10. **`return` inside a loop with an outstanding `defer`** — `defer` runs on the return path; no suspension allowed inside.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 20 | one suspension, no locals | C89 md5 matches hand-written equivalent |
| 21 | suspension inside `while` | loop var preserved across resume |
| 22 | suspension inside switch prong with capture | capture preserved across resume |
| 23 | nested suspension (A calls B) | two frames, independent |
| 24 | `try` across suspension | error path runs correctly |
| 25 | recursive suspending fn | N frames for N-deep recursion |
| 26 | resume after terminal | returns `null` |
| 27 | default case hit (via forged state) | traps |
| 28 | suspension inside `if` expression | AST lifting already applied; verify |

---

## Stage 4 — Builtin Lowering

### Parts
| Builtin | Lowering |
|---|---|
| `@asyncFrameSize(fn)` | comptime constant from Stage 2 |
| `@asyncInit(buf: [*]u8, fn) *void` | zero `state`; copy params into frame; return `buf` as `*void` |
| `@asyncResume(frame: *void, arg: *void) ?*void` | load `state`; dispatch; run to next suspension or completion; return `arg` or `null` |
| `@asyncSuspend(data: *void) *void` | store live locals; set next state; return `data` |

### Type checking rules
- `@asyncFrameSize` requires a function symbol; non-suspending → 0 with `warning[30XX]`.
- `@asyncInit` requires `[*]u8` and a function symbol.
- `@asyncResume` requires `*void`; can appear anywhere.
- `@asyncSuspend` only inside a suspending function → `error[3021]` otherwise.
- `@asyncSuspend` inside `defer`/`errdefer` → `error[3000]`.

### Cross-module
All four builtins operate on runtime values. After Stage 2, `@asyncFrameSize` on an imported function is a resolved constant. No symbol visibility issues: the frame struct is not shared, and `@asyncInit` takes a raw byte buffer.

### Edge cases
1. **Buffer smaller than frame size** — `-fsafe`: runtime trap; `-ffast`: silent corruption; document.
2. **Frame initialized for `foo`, resumed as `bar`** — not detectable; UB; document.
3. **`@asyncFrameSize` on a non-suspending function** — 0 and warning; document.
4. **`@asyncSuspend` outside suspending context** — `error[3021]`.
5. **Null frame to `@asyncResume`** — `-fsafe`: trap; `-ffast`: UB.
6. **Reinitializing a live frame** — second `@asyncInit` on the same buffer discards state; allowed, documented.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 30 | `@asyncFrameSize(foo)` | compile-time constant |
| 31 | `@asyncInit` fills buffer | buffer bytes match frame layout |
| 32 | `@asyncResume` drives task | runs to next suspension or terminal |
| 33 | `@asyncSuspend` in suspending fn | compiles |
| 34 | `@asyncSuspend` outside | `error[3021]` |
| 35 | `@asyncSuspend` in `defer` | `error[3000]` |
| 36 | buffer too small | `-fsafe` trap; `-ffast` UB |
| 37 | `@asyncFrameSize` on non-suspending | 0 + warning |

---

## Stage 5 — `std.async` Library

### Parts
```zig
pub const Frame = struct {
    buf: [*]u8,
};

pub const Task = struct {
    frame: Frame,
    cancel_requested: bool,
    done: bool,
    result: ?*void,
};

pub const Scheduler = struct {
    tasks: [*]Task,
    count: usize,
    capacity: usize,
};

pub fn suspend(task: *Task, data: *void) !*void;
pub fn awaitTask(task: *Task, out: *void) !void;
pub fn addTask(sched: *Scheduler, task: *Task) void;
pub fn tick(sched: *Scheduler) void;
pub fn cancelAll(sched: *Scheduler) void;
pub fn waitAll(sched: *Scheduler) void;
```

### Cancellation semantics
- `cancel(task)` sets `task.cancel_requested = true`.
- `suspend()` checks the flag; if set, returns `error.Canceled`.
- The coroutine's error path runs (`errdefer` chains).
- The scheduler sees `done = true` after the next tick.
- Cooperative only; no preemption.

### Cross-module
- `std.async` is a normal module.
- `Task` and `Scheduler` are plain structs; passing pointers across module boundaries works normally.
- Module A can create a Task; module B can cancel it; module C can `awaitTask` it.
- No special cross-module machinery.

### Edge cases
1. **Tick after cancel** — drives the task to its terminal path.
2. **Await on already-done task** — returns stored result immediately.
3. **Await from non-suspending `main`** — requires a busy-drive loop; provide `std.async.runUntil(task, out)` for this case.
4. **Cross-module cancel** — normal field access.
5. **Arena lifetime** — if a Task's frame lives in an arena, resetting the arena invalidates the Task; document.
6. **Task slot reuse** — call `@asyncInit` on the same buffer; the second init discards the first.
7. **Zero-task tick** — no-op.
8. **`waitAll` with cancellations** — drives cancelled tasks to their terminal path.
9. **Scheduler overflow** — `addTask` beyond `capacity`; `-fsafe` trap; `-ffast` UB; document.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 40 | one task, one suspension | tick twice → done |
| 41 | cancel mid-flight | error path runs; task terminates |
| 42 | awaitTask from scheduler loop | returns result |
| 43 | reuse task slot | second `@asyncInit` works |
| 44 | cross-module create/cancel | works |
| 45 | 3 tasks in scheduler | tick until all done |
| 46 | await on done task | returns immediately |
| 47 | await from non-suspending main | uses `runUntil` |

---

## Stage 6 — Integration and Application Tests

### Parts
- Convert `rogue_mud` NPC AI to coroutines.
- Convert `mud_server` per-connection handler to coroutines.
- Cross-module test: `main.zig` + `ai.zig` + `net.zig` with tasks created, scheduled, cancelled across modules.
- Golden comparison: existing goldens must remain byte-identical.

### Cross-module integration
- AI tasks created in `ai.zig`.
- Scheduled in `main.zig`.
- Cancelled in `net.zig`.
- Verifies all cross-module edges: frame size resolution, Task sharing, scheduler ownership.

### Determinism checks
- Run the same program three times; C89 emission md5 must match.
- Run under `-s0`..`-s5`; emission md5 must match.
- Run under `-osl` and `-osw`; behavior must match (output byte-identical after CRLF normalization, per existing rule).

### Edge cases
1. **Large frame spill** — a task with a >1KB frame; verify `-s<N>` doesn't affect emission.
2. **Cancellation inside `errdefer`** — the `errdefer` runs on cancellation; verify no suspension inside.
3. **Rapid create/destroy** — create 100 tasks, cancel 50, complete 50; verify no leak (frame pool accounting).
4. **Error union return across suspension** — the coroutine returns `!void`; the error is delivered to the await point.

### Repros
| ID | Fixture | Expected |
|---|---|---|
| 50 | `rogue_mud` with coroutine NPC AI | golden md5 matches existing |
| 51 | `mud_server` with coroutine handlers | golden md5 matches existing |
| 52 | 3-module, 5-task app | correct output |
| 53 | determinism, 3 runs | identical C89 md5 |
| 54 | `-fsafe` vs `-ffast` on correct program | identical behavior |
| 55 | `-osl` vs `-osw` | identical behavior (modulo CRLF) |
| 56 | large frame task | `-s0`..`-s5` all produce identical C89 |
| 57 | error union returned across suspension | error delivered correctly |

---

## Error codes to add

| Code | Condition |
|---|---|
| `error[3020]` | suspending function stored in a function pointer |
| `error[3021]` | `@asyncSuspend` outside a suspending function |
| `error[3022]` | `@asyncFrameSize` on non-suspending function (or warning) |
| `error[3023]` | (runtime, `-fsafe`) null frame to `@asyncResume` |

---

## Memory budget (compiler-side)

| Stage | Peak analysis state |
|---|---|
| 1 | O(function count); negligible |
| 2 | O(largest function's CFG + liveness); bounded, spillable |
| 3 | O(largest function's AST); bounded, emission-time |
| 4 | O(1) |
| 5 | O(runtime Task count); not compiler memory |

Estimated `-s0` delta for realistic programs: **100 KB – 1 MB**. Participates in the existing `-s<N>` spilling.

---

## Spec changes required

- **§1.2** — note `*void` as the type-erased pointer used by async builtins.
- **§3.1** — add: suspension inside `defer`/`errdefer` is `error[3000]`.
- **§4** — add the four builtins with signatures.
- **§5** — no generics → `*void` result slot; `Future(T)` impossible.
- **§6** — add canonical coroutine patterns: scheduler loop, cancellation, entry from `main`.
- **§7** — add: async primitives implemented; `std.Io` interface not yet.

---

## Implementation order

1. Stage 1 (detection) — smallest, validates the call-graph analysis.
2. Stage 2 (frame layout) — the real compiler work.
3. Stage 3 (lowering) — mechanical once Stage 2 is correct.
4. Stage 4 (builtins) — thin.
5. Stage 5 (std) — library work.
6. Stage 6 (integration) — the verification.

Each stage has its own repro set. No stage begins until the previous stage's repros all pass. Stage 6 is the gate for the whole feature.
