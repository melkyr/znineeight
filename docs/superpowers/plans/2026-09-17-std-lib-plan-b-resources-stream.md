# Z98 std-lib Plan B — L3 resources + L6 `std_stream` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the L3 resource modules (`std_file`, `std_stdin`, the `std_net` UDP extension) and the L6 capstone `std_stream` — the coroutine-aware composition layer that composes L3 resources over `std.async`.

**Architecture:** One plan, five module tasks plus the band's R7b usage programs in the closeout, ordered by the blueprint's construction order (L3 file/stdin → L3 UDP → L6 stream). Each module is authored in `sf/src/std_<name>.zig` with the blueprint's exact signatures, gets `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixtures, and is validated by the six gates. **This plan runs after Plan A (L0-L2); its successor is Plan C (L4 + L5).**

**Tech Stack:** Z98/`zig1` self-hosted compiler (C89 emission), `std.arena`, `std.async` (Track 3), bash, `gcc -m32`, git.

**Spec:** `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` §4 (Plan B), §5, §6; module signatures in `sf/docs/std_lib_extension.txt` §3 (L3, L6) and §4.

**Sequence:** PREVIOUS plan: [`2026-09-17-std-lib-plan-a-foundation.md`](2026-09-17-std-lib-plan-a-foundation.md) (L0-L2). NEXT plan: [`2026-09-17-std-lib-plan-c-data-codecs.md`](2026-09-17-std-lib-plan-c-data-codecs.md) (L4 + L5). DEFERRED follow-up: [`2026-09-18-plan-D-network-async.md`](2026-09-18-plan-D-network-async.md) (the `std_stream` network reader + non-blocking sockets; recorded, scheduled after A/B/C).

## Global Constraints

- **Precondition:** Task 0 + Plan A complete.
- **Baseline (re-verify at Task 1).** Record HEAD, the fixed point, the seed version/archive md5, the corpus `EXPECTED_FAIL.md` header. Adding std modules MUST NOT move the fixed point — if it does, STOP.
- **Build only via the seed model:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh_out>`; never invoke `zig0`.
- **gcc flag-set (binding):** `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`. `timeout 120` on every binary.
- **Layering (R3):** L3 imports L0-L2; L6 imports L0-L5 + `std.async`. No sibling imports.
- **Coroutine rules (blueprint §4):** C1 — a `*Async` function is the same module, same error set, same return type as its sync sibling; only the body may call `std.async.wait`. C2 — no std module calls `std.async.tick`/`waitFor`/`waitAll` (those are `main`-level). C3 — a synchronous function never calls a `*Async` function.
- **Async isolation gate (binding, Plan B only):** a program that does not use `std_stream` MUST NOT link the async runtime. Assert this in the import graph for every new L3 module (none may import `std.async`).
- **`std.async` API (landed):** `TaskState`, `FrameError{OutOfFrame}`, `Context` (16-byte header, `pool_base=ctx+16`, 8-aligned buffers), `Task`, `Scheduler`, `schedulerInit/addTask/removeTask/tick/suspend/awaitTask/waitFor/waitAll/cancel/cancelAll`.
- **Fixtures (R7):** one `repro/mi_matrix/stdlib_<module>_<name>_xmod` per public function; L6 fixtures suspend at least twice per call.
- **Usage programs (R7b):** each layer band ships usage programs under `stdlib_test/`; every module in this band is complete only when its usage program is GREEN.
- **Seed `lib/` copy lists:** each task that adds a module extends both `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` `lib/` copy lists in the same commit; the closeout verifies the lists are complete. (`scripts/self_compile/build_zig1_5.sh:12` keeps its legacy 5-module list on the retired zig0 path — a known divergence; do not silently change it.)
- **Edits only via `edit`/`fastedit`**; never stage `mnemoria/` or `.zig1_*.tmp`; declare every residual gap.

---

## File Structure

**Create (modules):**
- `sf/src/std_file.zig` — L3, binary-safe file I/O (owns the OS handle).
- `sf/src/std_stdin.zig` — L3, line-based stdin.
- `sf/src/std_stream.zig` — L6, file-only coroutine-aware composition (`FileLineReader`, `initFileLineReader`, `readFileLineSync`, `readFileLineAsync`; `SocketLineReader`/`MsgReader` are Plan D).

**Modify (modules):**
- `sf/src/std_net.zig` — add the UDP surface (`IpAddr`, `udpBind`, `udpSendTo`, `udpRecvFrom`, `udpSetTimeout`).
- `sf/src/std.zig` — add re-exports if the blueprint's §6 distribution requires them (L3/L6 are by-path imports; confirm against §6).
- Create `sf/src/std_file_pal.zig` / `sf/src/std_stdin_pal.zig` as needed (std-side extern "c" bindings, `std_net.zig` pattern). **Forbidden:** any edit to `sf/src/pal.zig`/`sf/src/include/zig_pal.c`. If an OS primitive is missing, add it to the std-side PAL module, not the compiler.

**Create (fixtures):** one dir per public function under `repro/mi_matrix/`:
- `stdlib_file_<name>_xmod/` (open/read/write/seek/EOF/size/flush/exists/remove/rename/readAll/writeAll; the binary round-trip uses `\r\n\0`).
- `stdlib_stdin_<name>_xmod/` (multi-line; EOF with no trailing newline; buffer overflow).
- `stdlib_net_udp_<name>_xmod/` (loopback send/recv; timeout; zero-length datagram; truncation behavior).
- `stdlib_stream_<name>_xmod/` — 4 file-only fixtures: `stdlib_stream_readline_xmod` (async, small file), `stdlib_stream_readline_noeof_xmod` (async, no trailing newline), `stdlib_stream_readline_empty_xmod` (async, empty file), `stdlib_stream_readlinesync_xmod` (sync).

**Create (usage programs, R7b):**
- `stdlib_test/file_stdin_usage/main.zig` — composes `std_file` + `std_stdin`.
- `stdlib_test/file_stream_usage/main.zig` — composes `std_file` + `std_stream` + `std.async` (file-only; the network reader is Plan D).

**Modify (closeout):**
- `repro/mi_matrix/EXPECTED_FAIL.md` — bump once at Plan B closeout.
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` — the `lib/` copy list is extended per-task (one module per task commit); the closeout verifies it is complete.

**Reference (read-only):** `sf/docs/std_lib_extension.txt` §3 (L3/L6) + §4, `sf/docs/tech_docs/12_async_coroutines.md`, `docs/sf/QUICK_REF.md`.

---

### Task 1: Baseline + `std_file` (L3)

**Files:**
- Create: `sf/src/std_file.zig`
- Create: the `stdlib_file_*_xmod` fixtures
- Modify: `sf/src/std.zig` (per §6)
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_file.zig` + any `std_file_pal.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_arena`, `std_buf`, `std_str`.
- Produces: `File`, `Mode`, `SeekWhence`, `FileError` + the blueprint §3 L3 surface (`open`/`close`/`read`/`write`/`seek`/`size`/`flush`/`exists`/`remove`/`rename`/`readAll`/`writeAll`).

- [ ] **Step 1: Record the baseline** (HEAD; fixed point via a fresh seed build; seed md5; EXPECTED_FAIL header).
- [ ] **Step 2: Write the failing fixtures** (read, write, seek, EOF, binary round-trip with `\r\n\0`, exists/remove).
- [ ] **Step 3: RED** (`error[3048]`).
- [ ] **Step 4: Implement `std_file.zig`.** Win32 opens through `CreateFileA` (never `fopen`); `size` uses `GetFileSizeEx` (never `ftell`); `read` returns 0 at EOF (not an error); `write` may return fewer bytes (callers loop). Route through the std-side `std_file_pal.zig` (`@cInclude` + `extern`, `@isWindows()` guards). The existing `pal_file_open/read/write/close` symbols in the emitted `zig_pal.c` are compiler-PAL; do **not** add to them. (`std_io.zig:62-70` declares those four as bare externs — the `std_file` design must not extend that surface.)
- [ ] **Step 5: GREEN** + the safety/determinism gates.
- [ ] **Step 6: Assert the async-isolation gate** — `grep -n 'std.async' sf/src/std_file.zig` is empty.
- [ ] **Step 7: Fixed point UNMOVED + commit** (stage `sf/src/std_file.zig`, any `std_file_pal.zig`, `sf/src/std.zig`, the fixtures, and both seed scripts).

---

### Task 2: `std_stdin` (L3)

**Files:**
- Create: `sf/src/std_stdin.zig`
- Create: the `stdlib_stdin_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_stdin.zig` + any `std_stdin_pal.zig` to both `lib/` copy lists — same commit)

**Interfaces:**
- Consumes: `std_file`, `std_file_pal`.
- Produces: `readLine(buf: []u8) ?[]u8` (strips `\n` and `\r\n`; returns a slice into `buf`; `null` at EOF with no partial line) and `readAll(arena) ![]u8`.

- [ ] **Step 1: Write the failing fixtures** (multi-line; EOF with no trailing newline; buffer-overflow behavior).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement `std_stdin.zig`.**
- [ ] **Step 4: GREEN + safety/determinism gates.**
- [ ] **Step 5: Async-isolation gate + fixed point UNMOVED + commit** (stage `sf/src/std_stdin.zig`, any `std_stdin_pal.zig`, the fixtures, and both seed scripts).

---

### Task 3: `std_net` UDP extension (L3)

**Files:**
- Modify: `sf/src/std_net.zig` (add `IpAddr` + `udpBind`/`udpSendTo`/`udpRecvFrom`/`udpSetTimeout`)
- Create: the `stdlib_net_udp_*_xmod` fixtures

**Interfaces:**
- Consumes: the existing TCP socket surface (unchanged).
- Produces: the blueprint §3 L3 UDP surface.

- [ ] **Step 1: Write the failing fixtures** (loopback send/recv; timeout; zero-length datagram; truncation behavior).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement the UDP surface.** `udpRecvFrom` returns 0 for zero-length datagrams; datagram truncation is not detectable under WinSock (documented).
- [ ] **Step 4: GREEN + safety/determinism gates.**
- [ ] **Step 5: Windows cross-check** — the existing `-osw` path + wine evidence for the UDP externs (the blueprint's L3 net is target-selected).
- [ ] **Step 6: Async-isolation gate + fixed point UNMOVED + commit.**

---

### Task 4: `std_stream` (L6) — file-only capstone

**Files:**
- Create: `sf/src/std_stream.zig`
- Create: the 4 `stdlib_stream_*_xmod` fixtures
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (append `std_stream.zig` to both `lib/` copy lists — same commit)
- Modify (docs, folded in): `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md` (§2, §4, §5 R4, §7, §8, §10), `sf/docs/std_lib_extension.txt` (§3 L6, §4 C2)

**Interfaces:**
- Consumes: `std_file` (L3), `std.async` (the `@asyncSuspend` builtin + the scheduler the caller drives).
- Produces: `FileLineReader`, `initFileLineReader`, `readFileLineSync` (blocking), `readFileLineAsync` (coroutine) — the file half of the blueprint §3 L6 two-reader surface. `SocketLineReader` / `MsgReader` are deferred to Plan D.

**Operator ruling (`sf/docs/answerT4.txt` + m1449/m1451):** Z98 is Model C — cooperative-yield. The caller drives `tick`; there is no executor and no `poll` loop. `readFileLineAsync` is NOT a wrapper over `readFileLineSync`: it is a separate implementation that reads a chunk and `@asyncSuspend`s per incomplete read. `std_stream` is file-only in Plan B; `SocketLineReader`, `MsgReader`, the non-blocking socket primitives, and an optional `std.async.wait(handle)` are Plan D (recorded, not scheduled).

- [ ] **Step 1: Resolve the async boundary (RESOLVED).** `std_stream` is the only module importing `std.async`; it uses `@asyncSuspend` (the builtin), never `tick`/`waitFor`/`waitAll` — C2. The landed `std.async` has no `wait` primitive; per the ruling that primitive is deferred to Plan D and is not needed for the file reader.
- [ ] **Step 2: Write the failing fixtures** (4): `stdlib_stream_readline_xmod` (`readFileLineAsync` on a small file), `stdlib_stream_readline_noeof_xmod` (last line without a trailing newline), `stdlib_stream_readline_empty_xmod` (empty file), `stdlib_stream_readlinesync_xmod` (`readFileLineSync`). Each `readFileLineAsync` fixture suspends ≥2× per call.
- [ ] **Step 3: RED.**
- [ ] **Step 4: Implement `std_stream.zig`.** `FileLineReader` over a `*std.file.File` + a caller buffer; `readFileLineSync` blocks; `readFileLineAsync` is a separate chunked implementation that yields per incomplete read. No callbacks, no state enum in user code.
- [ ] **Step 5: GREEN + safety/determinism gates + the async gate** (suspend ≥2× per call).
- [ ] **Step 6: Graph assertion (C3 isolation)** — `std_stream` does NOT source-import `std.async` (it reaches async only via the `@asyncSuspend` builtin), so the assertion actually proved is: a program that imports only `std_file`/`std_net`/`std_stdin` does NOT link the async runtime. Emit an L3-only program and an L3+`std_stream` program and compare the module set to confirm the async runtime is absent unless the program itself imports `std.async`.
- [ ] **Step 7: Docs amendments (folded in)** — program spec §2 (add Plan D), §4 (L6 file-only), §5 R4 (Model C + the asset-loading idiom), §7 (`std_stream` = `FileLineReader`), §8 (the deferrals), §10 (Plan D entry); blueprint §3 L6 (two-reader surface, `readFileLineSync`/`readFileLineAsync` as separate implementations, `MsgReader` deferred) and §4 C2 (Model C; `wait(handle)` deferred).
- [ ] **Step 8: Fixed point UNMOVED + commit** (stage `sf/src/std_stream.zig`, the fixtures, both seed scripts, the spec, and the blueprint).
---


### Task 5: Plan B closeout

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (verify the `lib/` copy list is complete), `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Create: `stdlib_test/file_stdin_usage/main.zig`, `stdlib_test/file_stream_usage/main.zig` (R7b usage programs; the stream one is file-only)

- [ ] **Step 1: Verify the seed scripts' `lib/` copy list is complete** — Tasks 1/2/4 each appended their module in the same commit; confirm `std_file.zig`/`std_stdin.zig`/`std_stream.zig` (plus any `std_file_pal.zig`/`std_stdin_pal.zig` created) are present in both scripts (UDP is a `std_net` edit, already listed). Add any missing entry here.
- [ ] **Step 2: Create the Plan B usage programs (R7b)** — `stdlib_test/file_stdin_usage/main.zig` composes `std_file` + `std_stdin`; `stdlib_test/file_stream_usage/main.zig` composes `std_file` + `std_stream` + `std.async` (file-only; the network reader is Plan D, not deferred here). Each has a deterministic stdout contract and is compiled/run under the fixture gates (3× emission md5, `-fsafe`/`-ffast` parity). Confirm `scripts/corpus/list_corpus_dirs.sh | grep stdlib_test` enumerates both.
- [ ] **Step 3: Run the full corpus + gates** (count; `check_emit_support` 5/5; `CLOSEOUT OK`; zero class movement on pre-existing dirs).
- [ ] **Step 4: Bump `EXPECTED_FAIL.md`** once (header + a Plan B section).
- [ ] **Step 5: Update the QUICK_REF std-module inventory.**
- [ ] **Step 6: Record the next-plan pointer.**

```markdown
## Next plan
Plan B complete. NEXT: `docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md`
(L4 data structures + L5 encoders/decoders).
```

- [ ] **Step 7: Commit** (`chore(std-lib): Plan B closeout — L3 resources + std_stream landed`).

---

## Self-Review

- **Spec coverage:** spec §4 Plan B (L3 + L6) → Tasks 1-4; §5 R4/C1-C3 → the coroutine rules + Task 4 Steps 1/6; §5 R7b → Task 5 Step 2; §6 async gate → Task 4 Step 5; §7 distribution → Task 5 Step 1; §8 async-isolation risk → Task 1 Step 6 + Task 4 Step 6; §10 index → the `Sequence:` line + Task 5 Step 6.
- **Placeholder scan:** module signatures are referenced to the blueprint (§3 L3/L6) as the exact-signature source of record. Every step has a concrete command/expected output.
- **Type consistency:** `std_file`/`std_stdin`/`std_stream` and the UDP additions to `std_net` are named identically across tasks and the file structure.
