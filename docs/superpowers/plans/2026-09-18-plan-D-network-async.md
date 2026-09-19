# Z98 std-lib Plan D — network async (non-blocking sockets + `SocketLineReader` + `MsgReader`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the network half of the `std_stream` two-reader surface: the `std_net` non-blocking socket primitives, `std_stream.SocketLineReader`, and `std_stream.MsgReader` (length-prefix framing) — the pieces deferred from Plan B by the `answerT4` ruling.

**Architecture:** One plan, three module tasks plus an optional primitive task and the closeout. Non-blocking socket support is the gating change: it is the only new OS surface, and it is what makes a socket source suspendable in the Model C (cooperative-yield) tick model. Once it exists, `SocketLineReader` is the socket analog of Plan B's `FileLineReader`, and `MsgReader` is the length-prefix frame reader over the same primitive.

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, `std.async` (Track 3), `std_net` (Plan B), `std_stream` (Plan B), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan D), §5, §6, §7; module signatures in `sf/docs/std_lib_extension.txt` §3 (L3 `std_net`, L6 `std_stream`) and §4; the Model C ruling in `sf/docs/answerT4.txt`.

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-plan-b-resources-stream.md`](2026-09-17-std-lib-plan-b-resources-stream.md) (L3 + L6 file-only). **Recorded, NOT scheduled:** execute after the Plan A / Plan B / Plan C foundation (the ruled chain is Task 0 → A → A-hardening → B → B-hardening → C → C-hardening → D). NEXT plan: none — this is the network-async capstone of the std-lib extension program.

## Global Constraints

- **Precondition:** Task 0 + Plan A + Plan B + Plan C complete.
- **Baseline (re-verify at Task 1).** Record HEAD, the fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. The non-blocking `std_net` change is a `sf/src` change and MOVES the fixed point (it adds OS externs to the emitted `net_prelude.h`/module set) — record the new value and rotate the seed at closeout.
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; never invoke `zig0`.
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Model C (the `answerT4` ruling, binding).** Z98 is cooperative-yield: the caller drives `tick`; there is no executor and no `poll` loop. A socket coroutine yields on `WouldBlock` and is re-driven next tick. Do NOT introduce an executor or a background wakeup.
- **Layering (R3):** `std_net` imports L0-L2; `std_stream` (L6) imports L0-L5 + `std.async`. No sibling imports. `std_stream` remains the only module importing `std.async` transitively.
- **Coroutine rules (blueprint §4):** C1 — a `*Async` function is the same module, same error set, same return type as its sync sibling; only the body may suspend. C2 — no std module calls `std.async.tick`/`waitFor`/`waitAll` (those are `main`-level). C3 — a synchronous function never calls a `*Async` function.
- **R8 PAL boundary:** the std lib never edits `sf/src/pal.zig`/`sf/src/include/zig_pal.c`/`sf/src/emit_support.zig`, except a prelude change if a new OS prototype is required (the `net_prelude.h` analog is an authorized compiler-graph change; record it and the fixed-point move).
- **`std.async` API (landed):** `TaskState`, `FrameError{OutOfFrame}`, `Context`, `Task`, `Scheduler`, `schedulerInit/addTask/removeTask/tick/suspend/awaitTask/waitFor/waitAll/cancel/cancelAll`. **There is no `wait` primitive** — Task 4 of this plan is optional and only lands if a poll-based wakeup justifies it.
- **Fixtures (R7):** one `repro/mi_matrix/stdlib_<module>_<name>_xmod` per public function; loopback for network fixtures; per-dir `ports.txt` for any fixed port.
- **Usage programs (R7b):** the band ships `stdlib_test/net_stream_usage/main.zig` (the network analog of Plan B's `file_stream_usage`).
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Modify (modules):**
- `sf/src/std_net.zig` — add the non-blocking surface (`setNonBlocking`, `recvNonBlocking`, `sendNonBlocking`).
- `sf/src/std_stream.zig` — add `SocketLineReader` (+ `initSocketLineReader`) and `MsgReader` (+ `initMsgReader`).

**Create (fixtures):** one dir per public function under `repro/mi_matrix/`:
- `stdlib_net_setnonblocking_xmod/`, `stdlib_net_recvnonblocking_xmod/`, `stdlib_net_sendnonblocking_xmod/` (loopback; the would-block path; per-dir `ports.txt`).
- `stdlib_stream_socketlinereader_xmod/`, `stdlib_stream_msgreader_xmod/` (loopback; partial frames; frame boundaries).

**Create (usage program, R7b):**
- `stdlib_test/net_stream_usage/main.zig` — composes `std_net` + `std_stream` + `std.async`.

**Modify (closeout):**
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump once at Plan D closeout.
- `docs/sf/QUICK_REF.md` — the std-module inventory + the pinned-dir count.
- `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` — seed rotation (the fixed point moves).

**Reference (read-only):** `sf/docs/std_lib_extension.txt` §3 (L3/L6) + §4, `sf/docs/answerT4.txt`, `sf/docs/tech_docs/12_async_coroutines.md`, `docs/sf/QUICK_REF.md`.

---

### Task 1: `std_net` non-blocking primitives (L3)

**Files:**
- Modify: `sf/src/std_net.zig`
- Create: the `stdlib_net_{set,recv,send}nonblocking_xmod` fixtures

**Interfaces:**
- Consumes: the existing TCP/UDP socket surface (Plan B).
- Produces: `setNonBlocking(s: *Socket) NetError!void`, `recvNonBlocking(s: *Socket, buf: []u8) NetError!usize` (returns `error.WouldBlock` when no data is ready, 0 at peer close), `sendNonBlocking(s: *Socket, buf: []const u8) NetError!usize`.

- [ ] **Step 1: Record the baseline** (HEAD; the fixed point via a fresh seed build; the seed md5; EXPECTED_FAIL header).
- [ ] **Step 2: Write the failing fixtures** (loopback set/recv/send; the would-block path; per-dir `ports.txt`).
- [ ] **Step 3: RED.**
- [ ] **Step 4: Implement the primitives** via `ioctlsocket(FIONBIO)` (win32) / `fcntl(O_NONBLOCK)` (POSIX); map `WSAEWOULDBLOCK`/`EAGAIN` to `error.WouldBlock`. Route any new OS prototype through `net_prelude.h` (the authorized prelude change) and record the fixed-point move.
- [ ] **Step 5: GREEN + determinism/safety gates + the `-osw`+mingw+wine cross-check.**
- [ ] **Step 6: Fixed point MOVED (recorded) + commit.**

---

### Task 2: `std_stream.SocketLineReader` (L6)

**Files:**
- Modify: `sf/src/std_stream.zig`
- Create: the `stdlib_stream_socketlinereader_xmod` fixture

**Interfaces:**
- Consumes: `std_net.recvNonBlocking` (Task 1), `std.async`.
- Produces: `SocketLineReader` + `initSocketLineReader` + `readSocketLineSync`/`readSocketLineAsync` (the socket half of the two-reader surface; same shape as `FileLineReader`).

- [ ] **Step 1: Write the failing fixture** (loopback line stream; a partial line across ticks; ≥2 suspends per call).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `SocketLineReader`** — `readSocketLineAsync` yields on `error.WouldBlock` and is re-driven next tick (Model C); `readSocketLineSync` blocks.
- [ ] **Step 4: GREEN + determinism/safety gates + the async gate.**
- [ ] **Step 5: Fixed point MOVED/UNMOVED (recorded) + commit.**

---

### Task 3: `std_stream.MsgReader` (L6)

**Files:**
- Modify: `sf/src/std_stream.zig`
- Create: the `stdlib_stream_msgreader_xmod` fixture

**Interfaces:**
- Consumes: `SocketLineReader` (Task 2), `std.async`.
- Produces: `MsgReader` + `initMsgReader` — a length-prefix frame reader over the same non-blocking primitive.

- [ ] **Step 1: Write the failing fixture** (loopback; a partial frame across ticks; back-to-back frames; an oversized prefix).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `MsgReader`** — read the length prefix, then the body, yielding on would-block; no callbacks, no state enum in user code.
- [ ] **Step 4: GREEN + determinism/safety gates + the async gate.**
- [ ] **Step 5: Fixed point MOVED/UNMOVED (recorded) + commit.**

---

### Task 4 (OPTIONAL): `std.async.wait(handle)`

**Files:**
- Modify: `sf/src/std_async.zig` (only if this task is justified)

**Interfaces:**
- Consumes: the scheduler.
- Produces: an optional `wait(handle)`-style readiness primitive.

- [ ] **Step 1: Decide.** Only land this if a poll-based wakeup justifies it over the Model C would-block yield. If not justified, record the decision and skip Tasks 4's steps.
- [ ] **Step 2: If justified:** pin with fixtures, implement, run the gates, record the fixed-point move.

---

### Task 5: Plan D closeout

**Files:**
- Create: `stdlib_test/net_stream_usage/main.zig` (R7b)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`

- [ ] **Step 1: Verify the seed scripts' `lib/` copy list is complete.**
- [ ] **Step 2: Create the R7b usage program** — `stdlib_test/net_stream_usage/main.zig` composes `std_net` + `std_stream` + `std.async`; deterministic stdout; compiled/run under the fixture gates.
- [ ] **Step 3: Run the full corpus + gates** (count; `check_emit_support`; `CLOSEOUT OK`; zero class movement on pre-existing dirs).
- [ ] **Step 4: Bump `EXPECTED_FAIL.md`** once (header + a Plan D section).
- [ ] **Step 5: Update the QUICK_REF std-module inventory.**
- [ ] **Step 6: Rotate the seed** (the fixed point moved).
- [ ] **Step 7: Record the next-plan pointer** (none — final plan in the std-lib extension program).
- [ ] **Step 8: Commit** (`chore(std-lib): Plan D closeout — network async landed`).

---

## Self-Review

- **Spec coverage:** the `answerT4` deferred package → Tasks 1-3; the optional `wait(handle)` → Task 4; R7b → Task 5 Step 2; R3/C1-C3 → the Global Constraints + the per-task gates; the seed rotation → Task 5 Step 6.
- **Placeholder scan:** the module signatures are referenced to the blueprint (§3 L3/L6) as the exact-signature source of record; each task names concrete files + the observable result.
- **Type consistency:** `SocketLineReader`/`MsgReader`/`recvNonBlocking`/`sendNonBlocking`/`setNonBlocking` are named identically across tasks and the file structure.
