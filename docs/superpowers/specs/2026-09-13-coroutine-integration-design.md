# Z98 Coroutine Integration (Track 4) — Design

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**Baseline HEAD:** `f755dbed` (parent `14129e68`); compiler fixed point `1467d932a876402f40a56316dfcad0e5`;
seed v10 (`ca18fc9f9af55d58147fcb7ff7a662b6`); corpus 570 = 541 OK / 29 GREEN / 0 FAIL;
`repro/mi_matrix/EXPECTED_FAIL.md` v77. At execution time the baseline is the **post-Track-3**
fixed point/seed (Tracks 2 and 3 move it; this track does not).

**Parent spec:** [`2026-09-13-async-prelude-and-feasibility-design.md`](./2026-09-13-async-prelude-and-feasibility-design.md).
**Derives from:** umbrella §12.6 (Stage 6 — integration, candidate sub-project 3),
§13 (testing strategy), §14.2 Track 2 item 3 (Integration/port — Stage 6), §5
(locked decisions L1 implicit-await, L2/m1166 `@asyncInit(ctx, buf, fn, args)`,
L3 caller result slot), §6 (non-negotiable concerns 1 `fn_ptr_struct_field` and 2
module-scope mutable globals), and the umbrella Global Constraints.

**Sibling subspecs:**
[`2026-09-13-win9x-calling-convention-design.md`](./2026-09-13-win9x-calling-convention-design.md) (Track 1),
[`2026-09-13-async-compiler-core-design.md`](./2026-09-13-async-compiler-core-design.md) (Track 2),
[`2026-09-13-std-async-design.md`](./2026-09-13-std-async-design.md) (Track 3).

**Previous subspec:** std-async.
**Next subspec:** none (final).
**Plan:** [`../plans/2026-09-13-coroutine-integration-plan.md`](../plans/2026-09-13-coroutine-integration-plan.md).
**Status:** draft, amendable in place.

---

## 1. Scope

Track 4 is the **integration/port** stage of the async sequence. It converts the
example event loops of two user programs to cooperative coroutines on top of the
Track 2 builtins and the Track 3 `std.async` library. It changes **example source
only** — no `sf/src` module, no builtin, no `std_async.zig` internals.

1. `examples/z98/rogue_mud` NPC AI: `lib/combat.zig:63 updateEnemies` (the per-enemy
   `findPath`/`moveEntity` loop, `:63-104`) becomes a **per-NPC coroutine** driven by
   the scheduler; `updateEnemies` becomes the per-turn scheduler tick.
2. `examples/z98/rogue_mud` per-connection work:
   `main.zig:277 broadcastDungeon`, `main.zig:286 broadcastOneClient`, and
   `ui.zig:61 drawToSocket` become a **per-client coroutine** that builds a frame and
   sends it with a yield between rows.
3. `examples/z98/rogue_mud` **cross-module task create/schedule/cancel**: task
   creation in `main.zig`, the NPC step in `lib/combat.zig`, and the socket writer in
   `ui.zig` exercise multi-module `is_suspending` propagation and frame synthesis.
4. `examples/z98/mud_server`: the `select` accept/read loop (`main.zig:100-174`) maps
   each accepted client to a **per-client task** driven by `std.async`, with
   `awaitTask` on the client-completion path, replacing the manual fd-set
   bookkeeping.

**Hard requirement.** The committed goldens stay **byte-identical**:
`bash scripts/closeout/verify_upgraded.sh <zig1>` must print `CLOSEOUT OK` and exit 0
with lisp canonical `96654b39…` and rogue `3fb6709e…` (canonical q) /
`b3c5b0e1…` (canonical move) / `7361d248…` (demo) / `aa40a52e…` (net variant). See
§3.3 for the full byte-identity model and §3.4 for the per-entry fallback rule.

## 2. Non-goals

- No `sf/src` change: no parser/type/sema/lowering/emitter/`std_async.zig` edit.
- No new builtin, diagnostic, or error code. Track 4 emits no diagnostic of its own.
- No fixed-point movement, no seed rotation, no corpus re-baseline **from this track**
  (examples are outside the compiler import graph; `build_from_seed.sh` never compiles
  them). If a prior track moved the point, that rotation belongs to that track.
- No change to observable program behaviour: stdout, per-socket bytes, input
  handling, and turn ordering are preserved exactly.
- No new example program and no rewrite of unrelated example logic; only the two
  named programs and the sites listed in §1/§3.2.
- No preemption, threads, or `std.Io` event loop; cooperative round-robin only.
- No port of any `repro/mi_matrix/*` fixture.

## 3. Detailed design

### 3.1 Consumed surface (pinned)

**Track 2 builtins** (from `../specs/2026-09-13-async-compiler-core-design.md` §4):

```zig
@asyncFrameSize(fn) u32
@asyncInit(ctx: *Context, buf: [*]u8, fn, args: ?*const void) *void
@asyncResume(frame: *void, arg: ?*void) ?*void
@asyncSuspend(data: ?*void) *void
```

**Track 3 `std.async`** (from `../specs/2026-09-13-std-async-design.md`; the surface
below is the spike report §5.2 shape, adapted to the still-open
`fn_ptr_struct_field` gap — track 2 explicitly forbids storing a `step` fn-ptr in a
struct field, so the step is passed explicitly and each scheduler is
**homogeneous**: all its tasks share one step function):

```zig
pub const Context = struct { /* opaque pool owner; shape defined by Track 3 */ };
pub const TaskState = enum(u8) { ready = 0, running = 1, suspended = 2, done = 3, cancelled = 4 };
pub const Task = struct {
    frame: *void,          // root frame from @asyncInit
    arena: [*]u8,          // per-task child-frame arena backing
    arena_capacity: usize,
    arena_used: usize,
    state: TaskState,
    cancel_requested: bool,
    result: *void,         // caller-provided result slot (L3)
};
pub const Scheduler = struct { tasks: [*]Task, capacity: usize, count: usize, current: usize };

pub fn schedulerInit(tasks: []Task) Scheduler;
pub fn addTask(s: *Scheduler, t: *Task) bool;
pub fn tick(s: *Scheduler, step: *const void) void;              // resume each ready/suspended task once
pub fn awaitTask(s: *Scheduler, t: *Task, step: *const void) void; // drive until t.state == .done
pub fn cancel(s: *Scheduler, t: *Task) void;                     // cooperative cancel_requested
pub fn cancelAll(s: *Scheduler) void;
pub fn waitAll(s: *Scheduler, step: *const void) void;
```

**Amendment rule.** This design pins the Track 3 surface as the spike report §5.2
shape. If the landed `std_async.zig` differs (naming, `Task` fields, or the
whether-`step`-is-stored decision), this subspec and its plan are amended in place to
match the landed surface; the conversion mapping and the byte-identity invariants do
not change.

### 3.2 Per-entry conversion mapping

Each entry is converted independently and is independently revertable (§3.4). The
`Invariant` column is the property that must hold after conversion.

| # | Entry | Current site | Target coroutine shape | Driver | Invariant |
|---|---|---|---|---|---|
| E1 | `rogue_mud` NPC AI | `lib/combat.zig:63-104` `updateEnemies(arena, dungeon)` — `for i in 1..entity_count`, `findPath`, `moveEntity` | `npcCoroutine(ctx, args)` → per active enemy; body `npcStep(na); _ = @asyncSuspend(null);` in a `while (true)`; `npcStep` is the existing per-enemy pathfinding move extracted verbatim | `combat.updateEnemies(sched)` calls `std.async.tick(sched, npcStepFn)` once per player turn | after each `updateEnemies` call, every entity's `(active, x, y, hp)` equals the pre-conversion state, produced in entity-index order |
| E2 | `rogue_mud` per-connection broadcast | `main.zig:277-284` `broadcastDungeon`; `main.zig:286-363` `broadcastOneClient`; `ui.zig:61-87` `drawToSocket` | `clientFrameCoroutine(ctx, args)` builds the frame via the existing logic, then `ui.drawToSocketCoroutine(sock, rows, cols, cells)` sends the clear/home bytes, then one row per `@asyncSuspend(null)` | `main` ticks the client scheduler once after each turn that calls `broadcastDungeon` | for each socket, the concatenated byte stream equals the pre-conversion stream (cross-socket interleaving is unobservable) |
| E3 | `rogue_mud` cross-module lifecycle | calls in `main.zig` game loop; step in `lib/combat.zig`; writer in `ui.zig` | `std.async.addTask`/`tick`/`cancel` invoked across `main.zig` → `lib/combat.zig` → `ui.zig`; the step function is the suspending callee in each module | `main.zig` | task creation order = client-slot / entity-index order; cancel is issued exactly where the original cleared `active` (`main.zig:180-182`, `:270-273`) |
| E4 | `mud_server` accept/read loop | `main.zig:100-174` `select` + fd-set accept + per-client `recv`/line processing | `clientCoroutine(ctx, args)` does one non-blocking `recv` + line processing then `@asyncSuspend(null)`; `main` accepts a socket, `@asyncInit`s a task, `addTask`s it; on the quit/disconnect path `main` uses `std.async.awaitTask` to drain the client task before freeing its slot | `main.zig` | each client receives the same response bytes; the connect/look/north/quit/disconnect sequence is unchanged; no fd-set bookkeeping remains |

**Ordering rules (byte-identity prerequisites).**

- NPC tasks are created in entity-index order (`i = 1..entity_count`) and resumed in
  that order; the spawner skips inactive enemies exactly as the original loop did.
- Client tasks are created in client-slot order (`i = 0..4`) and resumed in that order.
- No coroutine yields between two operations the original performed with no
  intervening observable write (e.g. `broadycastOneClient` must not interleave two
  clients' bytes on the same socket path; each socket has one writer task).
- `updateEnemies` still resets `temp_arena` after the tick, exactly where the
  original did (`main.zig:207-208`, `:258-259`).

### 3.3 Byte-identity constraint

**Authoritative gate.** `bash scripts/closeout/verify_upgraded.sh <zig1>`:
`CLOSEOUT OK`, exit 0, hashes lisp `96654b39…`, rogue q `3fb6709e…`, move
`b3c5b0e1…`, demo `7361d248…`, net `aa40a52e…`. Because Track 4 touches no `sf/src`
module, this gate cannot move from Track 4 alone; it is the cross-track regression bar
that proves Tracks 2–3 did not disturb the committed goldens.

**Per-entry gate.** For every converted entry, capture the program's runtime output
on a deterministic feed **before** the conversion and require an md5-identical
**after** capture:

- `rogue_mud` boot: feed `q\n`; `rogue_mud` move: feed `d\nl\nq\n` (the plain program
  has no `i` command, so the `_upgraded` demo feed is not used directly; the feed
  shape mirrors it).
- `mud_server`: a scripted single client (`look\n`, `north\n`, `quit\n`) over
  loopback, capturing the server stdout plus the bytes each client receives.

**Corpus gate.** `bash scripts/corpus/list_corpus_dirs.sh` (rule C enumerates
`examples/z98/*/`) must still list both example dirs; classify by gcc exit code per
`docs/sf/QUICK_REF.md:134-154`; both stay OK, zero class movement.

**What is *not* constrained.** Emitted C is **not** required to be byte-identical:
Tracks 2–3 legitimately change emitted C (new frame structs, `_step` functions).
Only **runtime** bytes are gated.

### 3.4 Fallback rule (amendable)

If any of (a)–(d) occurs for a given entry, that entry **must be reverted to its
original loop** (keep the original `while`/`select` body) and the decision recorded
as a plan amendment; the remaining entries are unaffected:

- (a) `verify_upgraded.sh` no longer prints `CLOSEOUT OK` or any hash changes;
- (b) the entry's post-conversion capture md5 differs from its pre-conversion capture;
- (c) compilation of the converted example produces `error[3017]`, `error[3018]`,
  `error[3019]`, `error[3046]`, or `PANIC`;
- (d) task ordering changes the dungeon state after a turn (invariant E1/E2/E3/E4
  fails).

The preferred fallback is the **exact byte-identity gate**: run the per-entry pre/post
md5 comparison inside the task and commit the conversion only if it passes; otherwise
keep the original loop. A fallback must never leave the example non-building and must
never touch a file outside the entry's own sites.

## 4. Interfaces

**Consumed (Track 2).** The four builtins of §3.1 with the exact signatures; the flat
`@asyncFrameSize` semantics and `ctx`-in-frame inheritance (Track 2 §3.2/§4).

**Consumed (Track 3).** `Context`, `TaskState`, `Task`, `Scheduler` and
`schedulerInit`/`addTask`/`tick`/`awaitTask`/`cancel`/`cancelAll`/`waitAll` of §3.1.

**Produced (example-local; no cross-track consumer).**

```zig
// examples/z98/rogue_mud/lib/combat.zig
pub const NpcArgs = struct { dungeon: *scenario.Dungeon_t, entity_idx: usize, arena: *sand_mod.Sand };
pub fn npcStep(na: *NpcArgs) void;                          // extracted from updateEnemies body
pub fn npcCoroutine(ctx: *std.async.Context, args: *void) void;  // suspending (contains @asyncSuspend)
pub fn spawnEnemies(ctx: *std.async.Context, tasks: []std.async.Task,
    args: []NpcArgs, dungeon: *scenario.Dungeon_t, arena: *sand_mod.Sand) usize;
pub fn updateEnemies(sched: *std.async.Scheduler) void;      // std.async.tick(sched, npcStepPtr)

// examples/z98/rogue_mud/ui.zig
pub const ClientArgs = struct { sock: i32, rows: usize, cols: usize, cells: [*]const Cell };
pub fn drawToSocketCoroutine(ctx: *std.async.Context, args: *void) void;  // suspending; one row per yield

// examples/z98/rogue_mud/main.zig
pub const ClientFrameArgs = struct {
    server: *net_mod.Server, dungeon: *scenario.Dungeon_t, client_idx: usize,
    cells: [*]ui_mod.Cell,
};
pub fn clientFrameCoroutine(ctx: *std.async.Context, args: *void) void;   // suspending; calls drawToSocketCoroutine

// examples/z98/mud_server/main.zig
pub const ClientTaskArgs = struct { player: *Player, rooms: [*]Room };
pub fn clientCoroutine(ctx: *std.async.Context, args: *void) void;        // suspending; one recv + line processing per yield
```

**Step-function pointers.** Because the `fn_ptr_struct_field` gap stays open (Track 2
non-negotiable concern 1), the step pointer is passed to `tick`/`awaitTask`, never
stored in `Task`. A scheduler is homogeneous (all tasks share one step), so
`rogue_mud` uses two schedulers — an NPC scheduler (`npcStepPtr`) and a client
scheduler (`clientFrameStepPtr`) — and `mud_server` uses one client scheduler
(`clientStepPtr`).

## 5. Diagnostics

Track 4 introduces **no diagnostic and no error code.**

| Code | Name | Expected during Track 4 | Handling |
|---|---|---|---|
| `3017` | `ERR_3017_SUSPENDING_FUNCTION_POINTER` | Must **not** fire: the builtin fn argument to `@asyncInit`/`@asyncFrameSize` is not ordinary function-value materialization | If it fires, the builtin arm in Track 2 is wrong — file against Track 2, revert the entry (§3.4c) |
| `3018` | `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING` | Must **not** fire: every `@asyncSuspend` is inside a suspending coroutine | Track 2 bug; revert the entry |
| `3019` | `ERR_3019_ASYNC_BUILTIN_IN_DEFER` | Must **not** fire: no async builtin is placed in `defer`/`errdefer` | rewrite the conversion without `defer`; revert if unavoidable |
| `3046` | `ERR_3046_ASYNC_FRAME_SIZE_INVALID` | Must **not** fire: every `@asyncFrameSize` argument is a suspending coroutine | Track 2 bug; revert the entry |

Any of the above appearing in the converted examples is a **blocker**, not an
accepted outcome. Runtime `error.OutOfFrame` (pool exhaustion) is likewise a blocker:
the per-task arenas of §3.1 are sized from `@asyncFrameSize` for a bounded task
count, so exhaustion indicates an under-sized pool and the entry is reverted.

## 6. Testing (goldens)

| Gate | Command | Pass evidence |
|---|---|---|
| Closeout goldens | `bash scripts/closeout/verify_upgraded.sh <zig1>` | `CLOSEOUT OK`, exit 0; `96654b39…`, `3fb6709e…`, `b3c5b0e1…`, `7361d248…`, `aa40a52e…` |
| Per-entry byte-identity | pre/post capture md5 on the §3.3 feed | identical md5, 3× deterministic |
| Corpus membership/class | `bash scripts/corpus/list_corpus_dirs.sh` + gcc-exit-code classify | both dirs listed and OK, zero class movement |
| Determinism | 3 consecutive runs of each converted example | identical stdout/bytes, identical md5 |
| Net variant discipline | the B6 flow inside `verify_upgraded.sh` | server stdout `aa40a52e…`, port 4000 clear after, no `pkill` |
| Build | seed-built reference compiler; gcc flag rule | dump rc=0, 0 `error[`, 0 `PANIC`, 0 `.c`-to-gcc failures |

Classification is by **gcc exit code**, never by empty stderr
(`docs/sf/QUICK_REF.md:134-154`). All binary executions carry `timeout 120`.

## 7. Risks

- **`fn_ptr_struct_field` gap (open).** Storing a step fn-ptr in `Task`/frame would
  emit the field as `void`. Mitigation: explicit step pointers, homogeneous
  schedulers (§3.1/§4); Track 2 forbids the stored form.
- **Module-scope mutable globals gap.** The scheduler is **caller-supplied**; no
  global scheduler/`Context` in either example. Existing module globals
  (`rogue_mud main.zig:24-26`, `ui.zig:27-28`; `mud_server main.zig:31`) are unchanged
  and are not used as scheduler state.
- **Frame arena lifetime.** Child frames are allocated from each task's arena;
  the existing `temp_arena` reset (`sand_reset`) must never reclaim a live coroutine
  frame. Mitigation: root frames and per-task arenas live in `buffer`/a dedicated
  permanent buffer, separate from `temp_buffer`.
- **Ordering drift.** A yield inserted before an observable write can reorder
  cross-socket sends. Mitigation: §3.2 ordering rules; one writer task per socket.
- **`select` semantics on Windows vs linux.** `mud_server` is POSIX-gated in the
  current loop (`@isWindows()`); the converted per-client task keeps the same
  blocking/non-blocking split and the same timeout.
- **Determinism of the player turn.** `updateEnemies` must complete all NPC moves
  before `broadcastDungeon`, exactly as the original sequence; only then are client
  frames ticked.
- **Lisp/rogue-upgraded goldens are not modified by this track**; the gate is a
  regression detector for Tracks 2–3. If it moves, the responsible track owns the fix.
- **Bootstrap staging.** Examples are not in `sf/src/main.zig`'s import graph and are
  never compiled by `build_from_seed.sh`; the new async syntax in examples is not
  exercised by the compiler's own rebuild.

## 8. Dependencies

**Consumes.**
- Parent umbrella §5 L1/L2/L3, §6 concerns 1–2, §12.6/§13/§14.2 Track 2 item 3,
  Global Constraints.
- Track 2 (`async-compiler-core-design.md`): the four builtins and their pinned
  signatures; `frame_sizes`/`@asyncFrameSize`; `ctx`-in-frame; the per-task LIFO
  child-frame contract; `ERR_3017/3018/3019/3046`.
- Track 3 (`std-async-design.md`): `Context`/`Task`/`Scheduler` and
  `schedulerInit`/`addTask`/`tick`/`awaitTask`/`cancel`/`cancelAll`/`waitAll`, plus the
  install-surface change that puts `std_async.zig` in the compiler's `lib/`.
- Track 1 (`win9x-calling-convention-design.md`): the `std_net` stdcall migration is a
  prerequisite for the `mud_server`/net-variant Windows build; the linux path is
  unaffected.
- Spike evidence `.superpowers/sdd/task-ASYNCPRELUDE-report.md` Task 2 §6.

**Produces.**
- Two converted user programs (Stage 6 complete): `rogue_mud` (per-NPC coroutine +
  per-client frame coroutine + cross-module task lifecycle) and `mud_server`
  (per-client tasks with `awaitTask`).
- No downstream consumer: this is the final subspec and plan in the async sequence.
- No fixed-point, seed, or corpus movement from this track.
