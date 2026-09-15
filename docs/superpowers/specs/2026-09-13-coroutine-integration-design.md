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
only**, with two operator-authorized `sf/src` exceptions — Task 0 (multi-module
`__Z98Step_<f>` emitter fix) and Task 0b (`std.async` task ownership +
`awaitTask` non-suspending-context guard) — and no other `sf/src` module, builtin,
or `std_async.zig` internals.

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
   each accepted client to a **per-client task** driven by `std.async`; `main`
   (which is not a coroutine) drives and retires completed tasks with
   `waitAll(s)`/a `tick` loop, replacing the manual fd-set bookkeeping.
   `std.async.awaitTask` is **coroutine-internal** and MUST NOT be called from a
   non-suspending context.

**Hard requirement.** The committed goldens stay **byte-identical**:
`bash scripts/closeout/verify_upgraded.sh <zig1>` must print `CLOSEOUT OK` and exit 0
with lisp canonical `96654b39…` and rogue `3fb6709e…` (canonical q) /
`b3c5b0e1…` (canonical move) / `7361d248…` (demo) / `aa40a52e…` (net variant). See
§3.3 for the full byte-identity model and §3.4 for the per-entry fallback rule.

## 2. Non-goals

- No `sf/src` change beyond the two operator-authorized Track-4 fixes (Task 0
  emitter step-emission; Task 0b `std.async` ownership + `awaitTask` guard). No
  other parser/type/sema/lowering/emitter edit.
- No new builtin or error code. Track 4's `awaitTask` guard is a library-level
  rejection (`@panic`), not a new diagnostic.
- The two authorized `sf/src` fixes move the self-emission fixed point (Task 0)
  and change `lib/std_async.zig` (Task 0b); the seed IS rotated at Track-4
  closeout. No corpus re-baseline beyond the async fixture class movements.
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

**Track 3 `std.async`** (from `../specs/2026-09-13-std-async-design.md`; Amendment 7
adopts the ruled **heterogeneous self-dispatch** model — the scheduler stores no
step, takes no step parameter, and drives `@asyncResume(t.frame, t.arg)`):

```zig
pub const Context = struct { /* pool owner; shape defined by Track 3 */ };
pub const TaskState = enum(u8) { ready = 0, running = 1, suspended = 2, done = 3, cancelled = 4 };
pub const Task = struct {
    frame: *void,          // root frame from @asyncInit (step word in frame header)
    ctx: *Context,         // per-task child-frame pool
    state: TaskState,
    cancel_requested: bool,
    result: *void,         // caller-provided result slot (L3)
    arg: *void,            // resume argument to @asyncResume
};
pub const Scheduler = struct { tasks: [*]Task, capacity: usize, count: usize, current: usize };

pub fn schedulerInit(tasks: []Task) Scheduler;
pub fn addTask(s: *Scheduler, t: *Task) bool;
pub fn tick(s: *Scheduler) void;                 // drives @asyncResume(t.frame, t.arg) once per runnable task
pub fn awaitTask(s: *Scheduler, t: *Task) void;  // coroutine-internal: mark the current task waiting on t; reject outside a suspending context
pub fn cancel(s: *Scheduler, t: *Task) void;     // cooperative cancel_requested
pub fn cancelAll(s: *Scheduler) void;
pub fn waitAll(s: *Scheduler) void;
```

**Amendment rule.** This design pins the Track 3 surface as the spike report §5.2
shape, **as amended by Amendment 7** (self-dispatch; no `Task.step`; no `step`
parameter). If the landed `std_async.zig` differs (naming or `Task` fields), this
subspec and its plan are amended in place to match the landed surface; the
conversion mapping and the byte-identity invariants do not change.

### 3.2 Per-entry conversion mapping

Each entry is converted independently and is independently revertable (§3.4). The
`Invariant` column is the property that must hold after conversion.

| # | Entry | Current site | Target coroutine shape | Driver | Invariant |
|---|---|---|---|---|---|
| E1 | `rogue_mud` NPC AI | `lib/combat.zig:63-104` `updateEnemies(arena, dungeon)` — `for i in 1..entity_count`, `findPath`, `moveEntity` | `npcCoroutine(ctx, args)` → per active enemy; body `npcStep(na); _ = @asyncSuspend(null);` in a `while (true)`; `npcStep` is the existing per-enemy pathfinding move extracted verbatim | `combat.updateEnemies(sched)` calls `std.async.tick(sched)` (self-dispatch) once per player turn | after each `updateEnemies` call, every entity's `(active, x, y, hp)` equals the pre-conversion state, produced in entity-index order |
| E2 | `rogue_mud` per-connection broadcast | `main.zig:277-284` `broadcastDungeon`; `main.zig:286-363` `broadcastOneClient`; `ui.zig:61-87` `drawToSocket` | `clientFrameCoroutine(ctx, args)` builds the frame via the existing logic, then `ui.drawToSocketCoroutine(sock, rows, cols, cells)` sends the clear/home bytes, then one row per `@asyncSuspend(null)` | `main` ticks the client scheduler once after each turn that calls `broadcastDungeon` | for each socket, the concatenated byte stream equals the pre-conversion stream (cross-socket interleaving is unobservable) |
| E3 | `rogue_mud` cross-module lifecycle | calls in `main.zig` game loop; step in `lib/combat.zig`; writer in `ui.zig` | `std.async.addTask`/`tick`/`cancel` invoked across `main.zig` → `lib/combat.zig` → `ui.zig`; the step function is the suspending callee in each module | `main.zig` | task creation order = client-slot / entity-index order; cancel is issued exactly where the original cleared `active` (`main.zig:180-182`, `:270-273`) |
| E4 | `mud_server` accept/read loop | `main.zig:100-174` `select` + fd-set accept + per-client `recv`/line processing | `clientCoroutine(ctx, args)` does one non-blocking `recv` + line processing then `@asyncSuspend(null)`; `main` accepts a socket, `@asyncInit`s a task, `addTask`s it; on the quit/disconnect path `main` retires the completed task (detected by `@asyncResume` returning null) via a `tick`/`waitAll` drive — `awaitTask` is coroutine-internal and is NOT used from `main` | `main.zig` | each client receives the same response bytes; the connect/look/north/quit/disconnect sequence is unchanged; no fd-set bookkeeping remains |

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
  loopback, capturing **two** files — the server stdout (`canonical_expected.txt`)
  and the bytes each client receives (`canonical_client_expected.txt`); both are
  byte-identity gates.

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
pub fn updateEnemies(sched: *std.async.Scheduler) void;      // std.async.tick(sched) (self-dispatch)

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

**Frame self-dispatch (Amendment 7).** The step is **never passed and never stored
in `Task`**. The compiler writes a pointer-sized step word into each frame header
(offset 0) at `@asyncInit`; `tick`/`awaitTask`/`waitAll` drive
`@asyncResume(t.frame, t.arg)`, which loads the step word and dispatches. The
synthesized `__async_step_<f>` is compiler-managed and not user-nameable
(Prelude B), so a scheduler is **heterogeneous**: `rogue_mud` may drive its NPC
and client tasks — and `mud_server` its client tasks — through one scheduler
surface with no per-step plumbing. The earlier explicit-step/homogeneous-scheduler
workaround is superseded.

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

- **`fn_ptr_struct_field` gap — superseded (Amendment 7).** The design no longer
  stores or passes a step pointer: the frame carries a compiler-written
  pointer-sized step word (offset 0) and `@asyncResume` self-dispatches. The gap
  was re-verified **closed** at the current fixed point; even if it regressed, the
  raw step word is loaded as an integer and cast at the dispatch site rather than
  emitted as a typed fn-ptr struct field. Mitigation: `stdlib_async_sched_xmod`
  (heterogeneous self-dispatch) plus the core Task-6 fixtures.
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
- The two authorized `sf/src` fixes move the self-emission fixed point (Task 0)
  and require a seed rotation at closeout (Task 0b changes `lib/std_async.zig`);
  the example conversions themselves move nothing.

## 9. Closeout reconciliation (standing)

Every track-N closeout MUST reconcile this spec's claims about the landed surface
against the actual `sf/src` (types, signatures, field names, call-site semantics).
A spec can drift from the landed code without the plan drifting — **S17** is the
first instance (`awaitTask` was described as a `main`-side "drain" while the
landed function is coroutine-internal and `main` is not a coroutine). On any
drift: correct the spec text in place, record the change in the plan's
Amendments, and re-verify. This is a standing requirement for every track-N
closeout in the async sequence, not only Track 4.

**Declare every residual gap (standing).** Any gap a fix leaves behind — a
construct still affected, a distinct adjacent bug, or a known limitation — MUST
be declared with a tracked fixture (or an `EXPECTED_FAIL.md` entry for a
compile-fail) plus a plan/spec note **before the task is marked complete**. An
"Approved with a Minor" review verdict is not a declaration. S20 (un-annotated
`switch`/`if` string-literal prongs) and S21 (`E![]const u8` / `?[]const u8`
payload string literals) are the first applications.
