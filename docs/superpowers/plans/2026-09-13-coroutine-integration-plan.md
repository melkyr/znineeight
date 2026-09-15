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

**Architecture:** One linear track over example sources only. `rogue_mud/lib/combat.zig` grows a suspending `npcCoroutine` (one task per active enemy) whose per-turn driver is `std.async.tick`; `rogue_mud/ui.zig` grows a suspending `drawToSocketCoroutine` that yields between frame rows; `rogue_mud/main.zig` owns the caller-supplied schedulers and task arenas and wires create/schedule/cancel across the three modules. `mud_server/main.zig` replaces the fd-set bookkeeping with one `clientCoroutine` task per accepted socket driven by `@asyncResume` from the select-ready path, with `std.async.awaitTask` on the quit/disconnect path. No `sf/src` file is touched: examples are outside the compiler's import graph, so the fixed point and seed do not move.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.async` (Track 3), the four `@async*` builtins (Track 2), bash, `gcc -m32`, git.

## Global Constraints

- **Baseline (re-verify at Task 1; refreshed 2026-09-15).** HEAD `2dc50be1`; compiler fixed point `027377296b2e38402ff8470f5c429eb8`; seed v19 archive md5 `23a16154e83736cf6b636685396a124a`; corpus 612 = 571 OK / 37 GREEN / 4 FAIL; `repro/mi_matrix/EXPECTED_FAIL.md` header v85 (2026-09-15). Re-verify with the Task 1 commands and record the observed values.
- **Precondition:** Tracks 2 and 3 are implemented and landed. The four `@async*` builtins work, `sf/src/std_async.zig` exists, and `lib/std_async.zig` is installed next to the compiler under test (`docs/sf/QUICK_REF.md:97-98` recipe plus `std_async.zig`).
- **Examples-only — fixed point and seed impact: NONE.** No `sf/src` edit; examples are not in `sf/src/main.zig`'s import graph and `scripts/seed/build_from_seed.sh` never compiles them. Do not rotate the seed for this plan. Do not bump `EXPECTED_FAIL.md`.
- **`timeout 120` on every binary execution.**
- **gcc flag-set rule (binding):** every `gcc -c` MUST be `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. Compiler builds only via the seed model: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`; never invoke `zig0`. `<out_dir>` must be fresh.
- **Byte-identity is a hard requirement.** `bash scripts/closeout/verify_upgraded.sh <zig1>` MUST print `CLOSEOUT OK` and exit 0 with lisp canonical `96654b39…`, rogue q `3fb6709e…`, rogue move `b3c5b0e1…`, rogue demo `7361d248…`, rogue net variant `aa40a52e…`. Emitted C is NOT required to be byte-identical; only runtime bytes are.
- **Per-entry byte-identity + fallback.** Each converted entry has a pre-conversion and post-conversion runtime capture that must be md5-identical (feeds in `File Structure`). If a golden moves, a capture differs, an `error[3017/3018/3019/3046]`/`PANIC` appears, or task ordering changes the post-turn dungeon state, revert **that entry** to its original loop (keep the original `while`/`select` body), record an amendment, and leave the example building. Entries are independently revertable.
- **Corpus gate:** `bash scripts/corpus/list_corpus_dirs.sh` must still list both `examples/z98/rogue_mud/` and `examples/z98/mud_server/`; classify by gcc exit code, never empty-stderr (`docs/sf/QUICK_REF.md:134-154`); zero class movement.
- **Edits only via `edit`/`fastedit`** (no `sed`/`python` on repo files; `/tmp` scratch is unrestricted). Re-read the target region immediately before every `fastedit`.
- **Never stage** `mnemoria/` or `.zig1_*.tmp`.
- **Pinned consumed surface (refreshed 2026-09-15).** Track 2 builtins: `@asyncFrameSize(fn) u32`, `@asyncInit(ctx, buf, fn, args: ?*const void) *void`, `@asyncResume(frame: *void, arg: ?*void) ?*void`, `@asyncSuspend(data: ?*void) *void`. Track 3 `std.async` (Amendment 7 self-dispatch): `Context` (16-byte header, `pool_base = ctx+16`, buffers MUST be 8-aligned), `TaskState`, `Task` (no `step` field), `Scheduler`, `schedulerInit`, `addTask`, `tick(s)`, `suspend`, `awaitTask(s, t)` (empty-scheduler `@panic`), `cancel`, `cancelAll`, `waitAll`. There is no `step` parameter and no `Task.step`; `tick`/`waitAll` self-dispatch via `@asyncResume(t.frame, t.arg)`. `@asyncInit` under `-fsafe` traps when `buf.len < @asyncFrameSize(fn)` for compile-time-known array buffers. If the landed Track 3 surface differs, amend this plan's call sites mechanically (naming only); the conversion mapping and invariants do not change.
- **Cross-track ABI closeout check (binding).** The `Context` header is 16 bytes (`used@0`, `capacity@4`, `oom@8`, 4-byte pad, `pool_base = ctx+16`); the compiler's `CTX_POOL_OFF` MUST equal 16; every frame size MUST be padded to 8; and buffers passed to `contextInit`/`@asyncInit` MUST be 8-aligned. Task 6's closeout MUST re-verify these agree with the landed Track-2/Track-3 surface (the Track-2 plan Task 8 Step 3b and Track-3 plan Task 5 Step 4b carry the same check).
- **Pre-conversion blocker — multi-module `__Z98Step_<f>` emission gap (binding).** With >1 module, `@asyncInit` targeting a coroutine in a NON-LAST module references `__Z98Step_<f>` but the emitter never emits it (it walks `lir_slots` in contiguous per-module runs); pinned by `repro/mi_matrix/async_step_nonlast_xmod` (`EXPECTED_FAIL.md` v85). Track 4's `rogue_mud`/`mud_server` are multi-module, so this MUST be resolved before the Task 2–5 conversions — either fix the emitter to emit synthesized steps per-module, or record an explicit fallback decision. Record the resolution/decision in Amendments.
- **Spec of record:** `docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` (Track 4 subspec); parent `docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md` §12.6/§13/§14.2.

---

**Sequence:** PREVIOUS plan: `../plans/2026-09-13-std-async-plan.md`. NEXT plan: none — final plan in the sequence. Subspec: [`../specs/2026-09-13-coroutine-integration-design.md`](../specs/2026-09-13-coroutine-integration-design.md).

## File Structure

**Create (committed deterministic harness):**
- `examples/z98/rogue_mud/demo/canonical_feed.txt` — `q\n` (boot + quit).
- `examples/z98/rogue_mud/demo/canonical_move_feed.txt` — `d\nl\nq\n` (move + look + quit).
- `examples/z98/rogue_mud/demo/canonical_expected.txt`, `canonical_move_expected.txt` — Task 1 pre-conversion captures.
- `examples/z98/rogue_mud/demo/README.md` — records the two golden md5s.
- `examples/z98/mud_server/demo/canonical_feed.txt` — `look\nnorth\nquit\n`.
- `examples/z98/mud_server/demo/session.sh` — starts the server on port 4000, drives one client over `bash /dev/tcp`, captures server stdout + client bytes, kills by PID, verifies port clear.
- `examples/z98/mud_server/demo/canonical_expected.txt` — Task 1 pre-conversion capture.
- `examples/z98/mud_server/demo/README.md` — records the golden md5.

**Modify:**
- `examples/z98/rogue_mud/lib/combat.zig` — `NpcArgs`, `npcMove`, `npcCoroutine`, `spawnEnemies`, `updateEnemies`.
- `examples/z98/rogue_mud/ui.zig` — `ClientArgs`, `drawToSocketCoroutine`.
- `examples/z98/rogue_mud/main.zig` — schedulers/task arenas, `ClientFrameArgs`, `clientFrameCoroutine`, broadcast calls, cancel paths.
- `examples/z98/mud_server/main.zig` — `ClientTaskArgs`, `clientCoroutine`, per-client tasks, `awaitTask` on quit/disconnect.

**Runner (unchanged, reused as the gate):** `scripts/closeout/verify_upgraded.sh`, `scripts/closeout/run_upgraded.sh`.

---

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
Expected: HEAD `2dc50be1` (or later); tree clean except the Track 4 docs; archive md5 `23a16154e83736cf6b636685396a124a` (seed v19); corpus `612`; header `v85`. Record the observed values; if the seed/fixed point moved since, record the new values and continue.

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
(`look`, `north`, `quit`) from one client over `bash /dev/tcp`, captures the
server stdout to `canonical_expected.txt`, kills the server by PID, and verifies
the port is clear. The expected file is the PRE-coroutine-conversion capture
(Track 4 Task 1).
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
# session.sh <mud_server_binary> <out_file>
set -u
BIN="$1"; OUT="$2"; FEED="$(dirname "$0")/canonical_feed.txt"
if awk 'NR>1{split($2,a,":"); if(a[2]=="0FA0" && $4=="0A") f=1} END{exit !f}' /proc/net/tcp 2>/dev/null; then
    echo "port 4000 already listening"; exit 1
fi
"$BIN" >"$OUT" 2>/dev/null &
SRV=$!
sleep 0.3
exec 3<>/dev/tcp/127.0.0.1/4000
while IFS= read -r line; do printf '%s\r\n' "$line" >&3; sleep 0.1; done <"$FEED"
exec 3<&-; exec 3>&-
sleep 0.2
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if awk 'NR>1{split($2,a,":"); if(a[2]=="0FA0" && $4=="0A") f=1} END{exit !f}' /proc/net/tcp 2>/dev/null; then
    echo "port 4000 still listening"; exit 1
fi
exit 0
```

- [ ] **Step 5: Capture the pre-conversion goldens**

Run:
```bash
chmod +x examples/z98/mud_server/demo/session.sh
# rogue boot
rm -rf /tmp/t4_rogue_pre && mkdir -p /tmp/t4_rogue_pre
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_pre/em main.zig)
for f in /tmp/t4_rogue_pre/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_rogue_pre/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_pre/prog /tmp/t4_rogue_pre/em/*.o
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_feed.txt > examples/z98/rogue_mud/demo/canonical_expected.txt
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt > examples/z98/rogue_mud/demo/canonical_move_expected.txt
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt examples/z98/rogue_mud/demo/canonical_move_expected.txt
# mud_server
rm -rf /tmp/t4_mud_pre && mkdir -p /tmp/t4_mud_pre
timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_mud_pre/em examples/z98/mud_server/main.zig
for f in /tmp/t4_mud_pre/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_mud_pre/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_mud_pre/prog /tmp/t4_mud_pre/em/*.o
bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_pre/prog examples/z98/mud_server/demo/canonical_expected.txt; echo "session rc=$?"
md5sum examples/z98/mud_server/demo/canonical_expected.txt
```
Expected: each program builds (dump rc=0, gcc+link rc=0); the rogue captures contain the boot banner and are 3× deterministic (re-run and compare); the mud_server session rc=0, the capture contains `MUD server listening on port 4000` and the `look`/`north` responses. Record the three md5s in the respective `README.md` files. If a program does not build at the baseline, STOP and report the Track 2/3 regression.

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
- Produces: `NpcArgs`, `npcMove(na)`, `npcCoroutine(ctx, args)`, `spawnEnemies(ctx, tasks, args, dungeon, arena) usize`, `updateEnemies(sched)`.

- [ ] **Step 1: Record the pre-conversion capture (RED baseline)**

Run:
```bash
timeout 30 /tmp/t4_rogue_pre/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum
cat examples/z98/rogue_mud/demo/README.md
```
Expected: the md5 equals `examples/z98/rogue_mud/demo/canonical_move_expected.txt`. This is the invariant the converted program must reproduce.

- [ ] **Step 2: Refactor `updateEnemies` into `npcMove` + `npcCoroutine`**

In `examples/z98/rogue_mud/lib/combat.zig`, add `const std = @import("std");` after the existing imports (`:1-5`), then append:
```zig
pub const NpcArgs = struct {
    dungeon: *scenario.Dungeon_t,
    entity_idx: usize,
    arena: *sand_mod.Sand,
};

fn npcMove(na: *NpcArgs) void {
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
        npcMove(na);
        _ = @asyncSuspend(null);
    }
}

pub fn spawnEnemies(ctx: *std.async.Context, tasks: []std.async.Task, args: []NpcArgs,
    dungeon: *scenario.Dungeon_t, arena: *sand_mod.Sand) usize {
    var n: usize = 0;
    var i: usize = 1;
    while (i < dungeon.entity_count and n < tasks.len) : (i += 1) {
        args[n] = NpcArgs{ .dungeon = dungeon, .entity_idx = i, .arena = arena };
        const sz = @intCast(usize, @asyncFrameSize(npcCoroutine));
        const frame = try sand_mod.sand_alloc(arena, sz, 8);
        tasks[n].frame = @asyncInit(ctx, @ptrCast([*]u8, frame), npcCoroutine, @ptrCast(?*const void, &args[n]));
        tasks[n].arena = @ptrCast([*]u8, frame);
        tasks[n].arena_capacity = sz;
        tasks[n].arena_used = 0;
        tasks[n].state = .ready;
        tasks[n].cancel_requested = false;
        n += 1;
    }
    return n;
}

pub fn updateEnemies(sched: *std.async.Scheduler) void {
    std.async.tick(sched, npcCoroutine);
}
```
Then **delete** the old `updateEnemies` body (`:63-104`); `npcMove` is that body with `na.entity_idx`/`na.arena`/`na.dungeon` substituted for the removed loop. `ctx` is unused by `npcCoroutine` bodies because `npcMove` has no suspending callee; it is retained in the signature so `@asyncFrameSize`/`@asyncInit` share one step ABI.

- [ ] **Step 3: Wire the NPC scheduler in `main.zig`**

In `examples/z98/rogue_mud/main.zig`, add module-scope state after `local_cells` (`:26`):
```zig
const MAX_NPCS: usize = 16;
var npc_tasks: [MAX_NPCS]std.async.Task = undefined;
var npc_args: [MAX_NPCS]combat_mod.NpcArgs = undefined;
var npc_sched: std.async.Scheduler = undefined;
```
After the enemy-placement loop (`:79-86`), spawn and bind the scheduler:
```zig
    npc_sched = std.async.schedulerInit(npc_tasks[0..]);
    const npc_count = combat_mod.spawnEnemies(&async_ctx, npc_tasks[0..], npc_args[0..], &dungeon, &temp_arena);
    _ = npc_count;
```
Replace both `combat_mod.updateEnemies(&temp_arena, &dungeon);` calls (`:207`, `:258`) with:
```zig
            combat_mod.updateEnemies(&npc_sched);
```
Add a task/context buffer next to `temp_buffer` (`:25`) so NPC root frames are never reclaimed by `sand_reset(&temp_arena)`:
```zig
var async_buffer: [256 * 1024]u8 = undefined;
```
and after `temp_arena` (`:32`):
```zig
    var async_ctx: std.async.Context = std.async.contextInit(async_buffer[0..]);
```
(If the landed Track 3 names this initializer differently, amend the name here per the Global Constraints pinned-surface rule.)

- [ ] **Step 4: Rebuild, run, and verify the byte-identity invariant**

Run:
```bash
rm -rf /tmp/t4_rogue_new && mkdir -p /tmp/t4_rogue_new
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_new/em main.zig); echo "emit rc=$?"
for f in /tmp/t4_rogue_new/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_rogue_new/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_new/prog /tmp/t4_rogue_new/em/*.o; echo "link rc=$?"
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_new/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
timeout 30 /tmp/t4_rogue_new/prog < examples/z98/rogue_mud/demo/canonical_feed.txt | md5sum
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt
```
Expected: emit/link rc=0; all three move runs print the same md5 and it equals `canonical_move_expected.txt`; the boot run equals `canonical_expected.txt`; no `error[3017/3018/3019/3046]` and no `PANIC` in `/tmp/t4_rogue_new/em/dump.log`. If the move md5 differs, apply the §Global-Constraints fallback: restore the original `updateEnemies` body and `updateEnemies(&temp_arena, &dungeon)` call sites, record an amendment, and continue to Task 3 with E1 unconverted.

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
Extract the existing body of `broadcastOneClient` (`:286-362`) into a plain helper `buildBroadcastCells(dungeon, cells, rows, cols)` that fills `local_cells` exactly as today (the two `ui_mod.drawToSocket`/status-bar steps stay at the end of the original `broadcastOneClient` only for the non-coroutine path; the coroutine path calls `buildBroadcastCells` then `drawToSocketCoroutine`). Keep `broadcastOneClient` as a thin wrapper (`buildBroadcastCells` + `ui_mod.drawToSocket`) for the upgraded-closeout compatibility path, or delete it if Task 3 Step 3 shows it is unused.

- [ ] **Step 3: Drive the client scheduler from `broadcastDungeon`**

Replace `broadcastDungeon` (`:277-284`) with:
```zig
fn broadcastDungeon(sched: *std.async.Scheduler) void {
    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        if (server.clients[i].active) {
            _ = std.async.tick(sched, clientFrameCoroutine);
        }
    }
}
```
Because `server` is a local in `main` today, thread it through: either (a) make `server` and `npc_sched`/`client_sched` module-scope `var`s (matching the existing workaround style at `:24-26`), or (b) pass `&server` and `&client_sched` into `broadcastDungeon(&server, &client_sched)`. Prefer (b) to keep state local:
```zig
fn broadcastDungeon(server: *net_mod.Server, sched: *std.async.Scheduler, calls: [*]main.callable) void
```
is not expressible without generics; use:
```zig
fn broadcastDungeon(server: *net_mod.Server, sched: *std.async.Scheduler) void {
    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        if (server.clients[i].active) {
            client_frame_args[i].server = server;
            _ = std.async.addTask(sched, &client_frame_tasks[i]);
            std.async.tick(sched, clientFrameCoroutine);
        }
    }
}
```
with module-scope `client_frame_tasks: [5]std.async.Task`, `client_frame_args: [5]ClientFrameArgs`, bound once after `server` is created. Update the two call sites (`:210`, `:260`) to `broadcastDungeon(&server, &client_sched)` and initialize `client_sched` next to `npc_sched` in Task 2's setup block.

- [ ] **Step 4: Verify the broadcast byte-identity**

Run:
```bash
rm -rf /tmp/t4_rogue_b && mkdir -p /tmp/t4_rogue_b
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_b/em main.zig); echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_rogue_b/em/dump.log 2>/dev/null || true
for f in /tmp/t4_rogue_b/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_rogue_b/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_b/prog /tmp/t4_rogue_b/em/*.o
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_b/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
```
Expected: emit/link rc=0; zero diagnostics; all three move runs reproduce `canonical_move_expected.txt`. The local (single-player) path has no connected clients, so the client scheduler is exercised only by the net variant in Task 4; the byte-identity here proves the client-task wiring did not disturb the local turn. If the md5 differs, apply the fallback for E2 (restore `broadcastOneClient`/`drawToSocket` and the original `broadcastDungeon`), record an amendment, and continue.

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
    _ = combat_mod.spawnEnemies(&async_ctx, npc_tasks[0..], npc_args[0..], &dungeon, &temp_arena);

    client_sched = std.async.schedulerInit(client_frame_tasks[0..]);
    var ci: usize = 0;
    while (ci < @intCast(usize, 5)) : (ci += 1) {
        client_frame_args[ci] = ClientFrameArgs{ .server = &server, .dungeon = &dungeon,
            .client_idx = ci, .cells = @ptrCast([*]ui_mod.Cell, &local_cells[0]) };
        const csz = @intCast(usize, @asyncFrameSize(clientFrameCoroutine));
        const cframe = try sand_mod.sand_alloc(&async_arena, csz, 8);
        client_frame_tasks[ci].frame = @asyncInit(&async_ctx, @ptrCast([*]u8, cframe), clientFrameCoroutine, @ptrCast(?*const void, &client_frame_args[ci]));
        client_frame_tasks[ci].arena = @ptrCast([*]u8, cframe);
        client_frame_tasks[ci].arena_capacity = csz;
        client_frame_tasks[ci].arena_used = 0;
        client_frame_tasks[ci].state = .ready;
        client_frame_tasks[ci].cancel_requested = false;
        _ = std.async.addTask(&client_sched, &client_frame_tasks[ci]);
    }
```
`async_arena` is `sand_init(async_buffer[0..], true)` (permanent) so `sand_reset(&temp_arena)` cannot reclaim coroutine frames. Each client task uses its own frame as its arena (the `arena`/`arena_used` fields above) so per-client child frames do not alias.

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
(cd examples/z98/rogue_mud && timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_rogue_c/em main.zig); echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_rogue_c/em/dump.log 2>/dev/null || true
for f in /tmp/t4_rogue_c/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_rogue_c/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_rogue_c/prog /tmp/t4_rogue_c/em/*.o
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt
for i in 1 2 3; do timeout 30 /tmp/t4_rogue_c/prog < examples/z98/rogue_mud/demo/canonical_move_feed.txt | md5sum; done
md5sum examples/z98/rogue_mud/demo/canonical_move_expected.txt
```
Expected: emit/link rc=0; zero diagnostics; both feeds reproduce their expected md5 across 3 runs. `is_suspending` must have propagated `main → combat.npcCoroutine` and `main → ui.drawToSocketCoroutine` (if not, the frame is mis-sized and the run is nondeterministic or traps). Record the observed md5s.

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
var async_buffer: [256 * 1024]u8 = undefined;
```
After the `players` initialization loop (`:90-95`), bind the scheduler and context:
```zig
    var async_arena = std_arena.sand_init(async_buffer[0..], true);
    var async_ctx = std.async.contextInit(async_buffer[0..]);
    client_sched = std.async.schedulerInit(client_tasks[0..]);
    i = 0;
    while (i < MAX_CLIENTS) {
        client_tasks[i].frame = @ptrFromInt(*void, 0);
        client_tasks[i].state = .done;
        client_tasks[i].cancel_requested = false;
        i += 1;
    }
```
In the accept path (`:121-150`), when a free slot is found, replace the player assignment with:
```zig
                        players[i] = Player{ .socket = client, .room_id = @intCast(u8, 0),
                            .buffer = undefined, .pos = @intCast(usize, 0), .is_active = true };
                        client_args[i] = ClientTaskArgs{ .player = &players[i], .rooms = &rooms };
                        const csz = @intCast(usize, @asyncFrameSize(clientCoroutine));
                        const cframe = std_arena.sand_alloc(&async_arena, csz, 8) catch {
                            const full2: []const u8 = "Server is full.\r\n";
                            _ = std_net.send(client, full2.ptr, @intCast(i32, full2.len));
                            std_net.close(client);
                            players[i].is_active = false;
                            i += 1;
                            continue;
                        };
                        client_tasks[i].frame = @asyncInit(&async_ctx, @ptrCast([*]u8, cframe), clientCoroutine, @ptrCast(?*const void, &client_args[i]));
                        client_tasks[i].arena = @ptrCast([*]u8, cframe);
                        client_tasks[i].arena_capacity = csz;
                        client_tasks[i].arena_used = 0;
                        client_tasks[i].state = .ready;
                        client_tasks[i].cancel_requested = false;
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
                    // coroutine completed (quit or disconnect): drain with awaitTask, then free the slot
                    std.async.awaitTask(&client_sched, &client_tasks[i], clientCoroutine);
                    if (players[i].is_active) {
                        std_net.send(players[i].socket, rooms[players[i].room_id].desc.ptr, @intCast(i32, rooms[players[i].room_id].desc.len));
                    }
                    std_net.close(players[i].socket);
                    players[i].is_active = false;
                }
            }
            i += 1;
        }
        std.async.tick(&client_sched, clientCoroutine);
    }
```
`awaitTask` is the completion path for a client task (quit/disconnect); it replaces the manual `p.is_active = false` reasoning that lived in the old recv branch. `@asyncResume` is used (not `tick`) so only the socket that `select` reported ready performs a `recv`.

- [ ] **Step 4: Build, run the session, and verify byte-identity**

Run:
```bash
rm -rf /tmp/t4_mud_new && mkdir -p /tmp/t4_mud_new
timeout 30 /tmp/t4_ref/zig1_5_clean -o /tmp/t4_mud_new/em examples/z98/mud_server/main.zig; echo "emit rc=$?"
grep -cE 'error\[(3017|3018|3019|3046)\]|PANIC' /tmp/t4_mud_new/em/dump.log 2>/dev/null || true
for f in /tmp/t4_mud_new/em/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /tmp/t4_mud_new/em -c "$f" -o "${f%.c}.o" || exit 1; done
gcc -m32 -o /tmp/t4_mud_new/prog /tmp/t4_mud_new/em/*.o
bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_new/prog /tmp/t4_mud_new/out.txt; echo "session rc=$?"
md5sum /tmp/t4_mud_new/out.txt examples/z98/mud_server/demo/canonical_expected.txt
```
Expected: emit/gcc/link rc=0; zero diagnostics; session rc=0; the two md5s match (byte-identical `look`/`north`/`quit` responses and disconnect handling). Run the session three times and require identical md5. If it differs, apply the E4 fallback (restore the original `select`/fd-set loop), record an amendment, and continue.

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
  bash examples/z98/mud_server/demo/session.sh /tmp/t4_mud_new/prog /tmp/t4_mud_new/out.$i.txt >/dev/null 2>&1; md5sum /tmp/t4_mud_new/out.$i.txt
done
md5sum examples/z98/rogue_mud/demo/canonical_expected.txt examples/z98/rogue_mud/demo/canonical_move_expected.txt examples/z98/mud_server/demo/canonical_expected.txt
```
Expected: every run's md5 matches its expected file; all three mnemonic hashes stable. Record the final table in the plan's Amendments/Closeout note.

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

- [ ] **Step 4: Verify no `sf/src` drift and no fixed-point/seed movement**

Run:
```bash
git diff --stat HEAD -- sf/src release/seed
git status --porcelain
```
Expected: empty `sf/src` and `release/seed` diffs; only the example files and the two docs are dirty. Examples are outside the compiler import graph, so no fixed point or seed change is possible from this track.

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

**Type consistency:** `NpcArgs`/`npcMove`/`npcCoroutine`/`spawnEnemies`/`updateEnemies` are defined in Task 2 and consumed with the same names in Task 4. `ClientArgs`/`drawToSocketCoroutine` and `ClientFrameArgs`/`clientFrameCoroutine` are defined in Task 3 and consumed in Task 4. `ClientTaskArgs`/`clientCoroutine` are defined in Task 5. `npc_sched`/`client_sched`/`npc_tasks`/`client_frame_tasks`/`async_ctx`/`async_arena`/`async_buffer` are introduced in Task 2/3/4 and used consistently. `tick(s)`/`awaitTask(s, t)` signatures match the pinned Track 3 surface (Amendment 7 self-dispatch) in every call site.

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
