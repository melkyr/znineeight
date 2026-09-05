# std_net Extern OS Bindings + Target Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Z98 networking correct on win9x/win32 and Linux by moving OS-facing networking out of the compiler into `std_net` as target-selected `extern "c"` bindings, adding a target model (`-osl`/`-osw`) with target-aware `@isWindows()`, and deleting the 11 socket builtins.

**Architecture:** Four incremental sections, each with its own I (investigation) and F (implementation) tasks, in one plan: S1 target model + `@isWindows()` (I settles the extern-emission mechanism, F implements flag/fold); S2 `std_net` extern rewrite (API-identical); S3 socket-builtin removal; S4 gates/verification + operator-ruled re-baselines. No release pressure — correctness first.

**Tech Stack:** zig1 (reference `/tmp/fx_subfolder/zig1` md5 `7c08d2d5`, std lib at `/tmp/fx_subfolder/lib`), `gcc -m32`, `i686-w64-mingw32-gcc` + wine32 prefix `/tmp/wine32`, harness `scripts/win32_cross/cross_{build_run,parity}.sh` + `scripts/closeout/`.

Design spec: `docs/superpowers/specs/2026-09-05-std-net-extern-target-design.md` (operator-approved).

## Global Constraints

- Compiler source edits are the point of this plan (`sf/src/`); edits per `docs/sf/AGENTS.md` X.7 (fastedit: re-read region immediately before each edit; absolute line numbers; bottom-to-top edits; INSERT = replace anchor line keeping the original at the end of new_code). No python/sed/bulk transforms; no `git checkout` to erase.
- Example sources (`mud_server`, `rogue_mud`, `rogue_mud_upgraded`, demo client) and `std_net` **public API** are NOT to change.
- Every I task is read-only evidence-gathering ending in a recorded verdict; every F task implements only what the preceding I verdict selected. STOP-present on any divergence; no "improvisation".
- 4-MD5 gates: gol `302df36b`/lisp `3591bad9`/json `76056b97` must remain byte-identical throughout; the `mud_server` gate (`53405b3b`) and the self-compile fixed point (`85733145`) move ONLY via explicit operator ruling (STOP-present, never silent). Full battery on any F that touches `sf/src`.
- Reference compiler rebuild after `sf/src` edits (`timeout 900 bash sf/scripts/build_release.sh` → `/tmp/fx_subfolder/zig1`), then re-copy std lib `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib` (rebuilds wipe it).
- Wine: dedicated `/tmp/wine32` prefix (`WINEPREFIX=/tmp/wine32 WINEARCH=win32`); parity for CRT-path programs is LF-normalized (AMENDMENT-1 of the win32 pre-test); console-render output is NOT a stdout gate.
- Net runs: localhost only, port-4000 discipline (check free before bind, kill only own PIDs, never `pkill`, verify no listener left).
- Pre-existing dirty/untracked set never staged (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `examples/z98/json_parser_upgraded/`).
- Reports accumulate in `.superpowers/sdd/task-NETBIND-report.md` (gitignored). Ledger `.superpowers/sdd/progress.md`. Memory `mnemoria --path .opencode/memory`, agent `netbind-session`.

---

# SECTION 1 — Target model + `@isWindows()`

### Task 1-0: I — extern-emission mechanism + target plumbing inventory (read-only, no commit)

**Files:**
- Read: `sf/src/main.zig` (CLI ~:1009-1029, `matchFlag` :1118, config plumbing), `sf/src/config.zig`, `sf/src/comptime_eval.zig` (:20-60 ids/init, :205-220 `@isWindows` fold), `sf/src/c89_emit.zig` (:2225-2362 include/header machinery, :2281 fwd-decl skip, :1984/:2047 extern original-name), `sf/src/cinclude.zig`, `sf/src/extern_c.zig`, `sf/src/extern_c_z98.zig`, `sf/src/pal.zig`, `examples/z98/rogue_mud_upgraded/lib/persistence.zig` (extern precedent).
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S1-I section).

**Interfaces:**
- Produces: (a) verdict on extern-emission mechanism; (b) exact touch-map for the `-osl`/`-osw` flag + fold; (c) list of ALL `@isWindows`/target-folding sites.

- [ ] **Step 1: Map the CLI/config.** Record how `main.zig` parses flags (the `s_*` string constants ~:1009-1029 + `matchFlag` :1118-1124 + where flags set config), where `config.host_is_windows` is read (`comptime_eval.zig:214`), and how config objects flow to the analyzer/lowerer (which struct carries it). Identify the cleanest field to carry a `target_os: u8`/bool that `@isWindows()` reads at dump time.
- [ ] **Step 2: Investigate the extern-emission mechanism.** Answer by reading the emitter (do not guess): when a program module declares `extern "c" fn foo(u16, [*]u8) i32;` and calls it, (1) is any C prototype emitted for `foo`? (trace `emitFunctionForwardDecl` skip at :2281, the fn-def emit at :2510/:2704, call emit at :6171/:6196, tail/ref at :6338/:6923); (2) how do `@cInclude` strings reach the emitted file (`c_includes` merge via `cinclude.zig` + `emitModuleHeader*` :2249-2362)? (3) does anything already emit target-guarded C at the *module* level (e.g. `emitBuiltinIncludes` `#ifdef` blocks :2225-2247)? Verdict between:
   - (a) platform-conditional include (a `@cInclude`/header path that emits `#ifdef _WIN32 … #endif` or is dropped under the unselected target);
   - (b) emitter auto-prototypes externs (relax the :2281 skip so non-variadic externs get fwd-decls built from their zig signature; then `std_net` needs no system header);
   - (c) other.
   Recommend ONE with the code evidence. If genuinely ambiguous, STOP-present.
- [ ] **Step 3: Enumerate `@isWindows`/target sites.** All readers of `config.host_is_windows` and every `if (@isWindows())`/`@isWindows()` use in `sf/src/` and `examples/z98/`; note which are comptime-fold consumers vs runtime. Record current behavior (all fold false today).
- [ ] **Step 4: Report + ledger.** Record verdict, touch-map, site list. Read-only: no commit, no source edits.

### Task 1-1: F — `-osl`/`-osw` flag + target-aware `@isWindows()`

**Files:**
- Modify per Task 1-0 verdict: `sf/src/main.zig` (flag parse + config), `sf/src/config.zig` or equivalent target field, `sf/src/comptime_eval.zig` (fold reads target), + any plumbed struct from the I map.
- Create: `repro/mi_matrix/target_is_windows_xmod/main.zig` RED fixture.
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S1-F section).

**Interfaces:**
- Consumes: Task 1-0 verdict + touch-map.
- Produces: `-osl`/`-osw` (+ `--target linux|windows` alias), `@isWindows()` correct per target, fixture GREEN both targets.

- [ ] **Step 1: Implement the flag + fold per the I touch-map.** `-osl` default. Fold `@isWindows()` from the target. Verify existing behavior unchanged when no flag is given (default linux ⇒ identical to today for all current builds: the `-osl` path must produce byte-identical output to no-flag).
- [ ] **Step 2: RED fixture** `target_is_windows_xmod/main.zig`:

```zig
const std = @import("std");

pub fn main() void {
    var x: i32 = 0;
    if (@isWindows()) {
        x = 111;
    } else {
        x = 222;
    }
    std.io.printInt(x);
    std.io.print("\n");
}
```

Expected GREEN: `-osw` → `111`, `-osl` (and no flag) → `222`.
- [ ] **Step 3: Build + verify.** Rebuild reference; run-gate both targets (linux path: dump `-osl` → gcc → run → `222`; `-osw` → mingw → wine → `111`); 3× deterministic each.
- [ ] **Step 4: Regression.** `-osl`/no-flag byte-identical on: the 4-MD5 gates (gol/lisp/json/mud), the golden 9/9, and the std_net-importing examples' dumps must be identical to pre-change (default-target path). Confirm nothing else drifted. (mud gate may move only if a std_net edit landed — it should NOT in this task.)
- [ ] **Step 5: Commit.**

```bash
git add sf/src/main.zig sf/src/config.zig sf/src/comptime_eval.zig repro/mi_matrix/target_is_windows_xmod
git commit -m "feat: target model -osl/-osw with target-aware @isWindows() (S1)"
```

- [ ] **Step 6: Report + ledger.** Evidence table (flag × target × output md5), regression proof, concerns.

---

# SECTION 2 — `std_net` extern rewrite

### Task 2-0: I — extern signature/layout verification (read-only, no commit)

**Files:**
- Scratch probes under `/tmp/`.
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S2-I section).

**Interfaces:**
- Produces: verified extern declarations + struct layouts for both targets; byte-offset proof; calling-convention proof; the final list of function signatures used in Task 2-1.

- [ ] **Step 1: Verify `extern "c"` support.** Probe (tiny Z98 programs through the Task 1-1 mechanism): extern fns with `u16` param, `[*]u8`/`*const void`/`usize` params, `i32`/`?*void` returns, and multiple params — compile+link+run under `gcc -m32` AND `i686-w64-mingw32-gcc` + wine. Confirm the C name emitted equals the source name (no mangling) and the calling convention is correct on both. Record any type that does not lower cleanly (STOP-present if a needed signature shape is unsupported).
- [ ] **Step 2: Verify layouts byte-exact.** Emit/probe (offsetof-style prints): win32 `WSADATA` (400B; fields wVersion@0 u16, wHighVersion@2 u16, szDescription@4 [257]u8, szSystemStatus@261 [129]u8, iMaxSockets@390 u16, iMaxUdpDg@392 u16, lpVendorInfo@396 *u8 (4-aligned; the design-phase 394 was a misaligned slip — S2-I verified 396), padded 400), `sockaddr_in` (16B; sin_family@0 u16, sin_port@2 u16, sin_addr@4 u32, sin_zero@8 [8]u8), win32 `fd_set` (`fd_count` u32 @0 + `fd_array[64]` u32 @4 = 260B), linux `fd_set` (`fds_bits[32]` u32 = 128B), `timeval` both (8B, longs). Cross-check against a tiny mingw C probe printing `sizeof`/`offsetof`. Record final layout consts.
- [ ] **Step 3: Confirm the S1 extern mechanism works for the chosen names** (wsock32 on `-osw`, libc on `-osl`) with no duplicate-prototype or header issues. Verify `select`, `setsockopt`, `socket`, `bind`, `listen`, `accept`, `connect`, `recv`, `send`, `closesocket`/`close`, `WSAStartup`, `WSACleanup`, `htons`, `htonl` all resolve.
- [ ] **Step 4: Record verdict + full signature list** (per target) + layout table in the report. Ledger line. Read-only: no commit.

### Task 2-1: F — `std_net.zig` extern rewrite (API-identical)

**Files:**
- Modify: `sf/src/std_net.zig` (full rewrite of internals; public API + `fd_set` blob unchanged).
- Create: `repro/mi_matrix/net_bind_startup_xmod/main.zig` RED fixture (mud-style init check).
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S2-F section).

**Interfaces:**
- Consumes: Task 2-0 signature/layout verdict + Task 1-1 extern mechanism.
- Produces: `std_net` with correct `init()`/`cleanup()` (WSAStartup/WSACleanup) and all socket ops as extern calls under `if (@isWindows())`; manual byte-swap helpers + extern `htons`/`htonl`.

- [ ] **Step 1: Rewrite `std_net.zig`.** Internal structure (per the S2-I verdict), keeping the exact public API (init/cleanup/createTcpServer/bindListen/accept/connect/send/recv/close/select/fdZero/fdSet/fdIsset + `pub const fd_set = struct { data: [128]u32 }`). The core:

```zig
extern "c" fn htons(x: u16) u16;
extern "c" fn htonl(x: u32) u32;

pub fn htonsManual(x: u16) u16 {
    return @intCast(u16, ((x & @intCast(u16, 0xFF)) << 8) | (x >> 8));
}
```

Add the target-specific extern set + layout structs + FD helpers per the S2-I verdict, all under `if (@isWindows()) { … } else { … }` (only the selected target's code survives comptime). `init()` windows = `WSAStartup(MAKEWORD(1,1), &wsa)` propagation; `cleanup()` windows = `WSACleanup()`; linux no-ops. Map `INVALID_SOCKET`/`SOCKET_ERROR` → `-1` exactly as the old builtins did.
- [ ] **Step 2: RED fixture** `net_bind_startup_xmod/main.zig` (thin: import `std_net`, `init() != 0` → error exit; on linux expect rc 0). Verifies init plumbing without a full server.
- [ ] **Step 3: Build + verify.** Rebuild reference + re-copy lib. Linux (`-osl`): dump all std_net-importing examples (mud_server, rogue_mud, rogue_mud_upgraded, demo client) → 0 `error[`/0 PANIC; run mud_server boot/move + rogue q/move/i/net demos → byte-identical goldens (LF-normalized where applicable). Windows (`-osw`): mingw + wine — mud_server **binds** (`MUD server listening on port 4000`, no `10093`); rogue net demo runs vs `demo/net_demo_expected.txt` WITHOUT the extra warning line; client rc 0. 3× deterministic.
- [ ] **Step 4: 4-MD5 + full battery.** gol/lisp/json gates byte-identical; mud gate will move (STOP-present the new hash for operator re-baseline — do NOT commit a silent re-baseline); self-compile round trip; golden 9/9; matrix 21/21; corpus 426 `-s0`.
- [ ] **Step 5: Commit.**

```bash
git add sf/src/std_net.zig repro/mi_matrix/net_bind_startup_xmod
git commit -m "feat: std_net extern OS bindings — target-selected wsock32/libc, WSAStartup init, manual byte-swap helpers (S2)"
```

- [ ] **Step 6: Report + ledger.** Signature/layout evidence, both-target run tables + md5s, gate movement STOP-present, concerns.

---

# SECTION 3 — Socket-builtin removal

### Task 3-0: I — full socket-builtin reference inventory (read-only, no commit)

**Files:**
- Read/grep `sf/src/{semantic_analyzer,lower,c89_emit}.zig` + docs.
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S3-I section).

**Interfaces:**
- Produces: an exhaustive removal list (every reference to the 11 builtins and the net-include machinery), so Task 3-1 deletion is provably complete.

- [ ] **Step 1: Enumerate.** Grep the 11 socket names (`@socketCreate`, `@socketBindListen`, `@socketAccept`, `@socketConnect`, `@socketSend`, `@socketRecv`, `@socketSelect`, `@socketFdZero`, `@socketFdSet`, `@socketFdIsset`, `@socketClose`) and their name-id identifiers across `sf/src/`. List each site: sema struct fields/intern/assign/membership (`semanticAnalyzerIsBuiltinSupported`-style, F-CLEANDIAG whitelist)/dispatch arms; lower name-ids/intern/assign/branches; `c89_emit` net bodies (:4573-4811), `moduleHasNetBuiltin`, `emitBuiltinIncludes` winsock block (:2244), any type-name tables; any spill/serde/tests touching socket ids.
- [ ] **Step 2: Cross-check consumers.** Confirm the ONLY consumers are `std_net.zig` (rewritten in S2) + the repro fixtures (which will be re-verified to now yield the clean unsupported-builtin diagnostic). Check no example still calls `@socket*` directly.
- [ ] **Step 3: Report the removal list + a post-removal expectation** (compiler still self-compiles; `@socketCreate` → clean `error[3000] unsupported builtin` via F-CLEANDIAG). Ledger line. No commit.

### Task 3-1: F — delete the socket builtins

**Files:**
- Modify: `sf/src/{semantic_analyzer,lower,c89_emit}.zig` per the Task 3-0 list.
- Record: `.superpowers/sdd/task-NETBIND-report.md` (S3-F section).

**Interfaces:**
- Consumes: Task 3-0 removal list + S1/S2 (std_net no longer uses the builtins).
- Produces: zero socket builtins; `@socket*` yields the clean unsupported-builtin error.

- [ ] **Step 1: Delete per the inventory**, bottom-to-top fastedits. Keep the compiler self-consistent (no dangling name-id references).
- [ ] **Step 2: Build + verify.** Rebuild + re-copy lib. Self-compile clean. Re-run all S2 green paths on both targets (std_net is now builtin-free). Grep confirms zero `@socket`/socket-id references remain. Fixture/negative probe: a program calling `@socketCreate` now emits the clean F-CLEANDIAG diagnostic (rc2, 0 `.c`), not silent mis-emission.
- [ ] **Step 3: 4-MD5 + battery** (as Task 2-1 Step 4; gol/lisp/json identical, mud moved hash re-presented to operator, corpus).
- [ ] **Step 4: Commit.**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "feat: remove socket builtins — std_net is the sole networking surface (S3)"
```

- [ ] **Step 5: Report + ledger.** Deletion diff summary, negative-probe evidence, gate status, concerns.

---

# SECTION 4 — Gates / verification

### Task 4-0: F — combined verification + re-baseline STOP-present

**Files:**
- Record only: `.superpowers/sdd/task-NETBIND-report.md` (S4 section). Optionally extend `scripts/win32_cross/` if a runner tweak is needed.
- Record: EXPECTED_FAIL.md / QUICK_REF.md updates AFTER operator approval (Task 4-1).

**Interfaces:**
- Consumes: S1-S3 artifacts.

- [ ] **Step 1: Full combined battery.** golden 9/9; matrix 21/21; corpus 426 `-s0`; both-target net matrix (`-osl` linux run, `-osw` mingw+wine): mud_server bind/boot/move, rogue q/move/i + net demo + client; all goldens LF-normalized where applicable; determinism 3× on the net runs.
- [ ] **Step 2: 4-MD5 + fixed-point.** gol/lisp/json byte-identical (proof). mud gate new hash recorded. Self-compile fixed point new hash recorded.
- [ ] **Step 3: STOP-present re-baseline proposal** to the operator: mud 4-MD5 re-baseline `53405b3b` → `<new>` and self-compile fixed point `85733145` → `<new>` (operator-ruled; no silent re-baseline). Also present win9x-readiness note (what `-osw` + wine now proves: WSAStartup init correct, bind/serve/select working, no `10093`; what remains for the VM). No commit until ruling.

### Task 4-1: F — docs reconciliation (after operator approval)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`.

- [ ] **Step 1: EXPECTED_FAIL.md.** Header bump + record the S1/S2/S3 fixture rows (`target_is_windows_xmod`, `net_bind_startup_xmod`) and the target-model/net-bind change; preserve historical sections.
- [ ] **Step 2: QUICK_REF.md.** Newest-first baseline bullet: target flags `-osl`/`-osw`, `@isWindows()` target-aware, std_net extern bindings (wsock32/libc), socket builtins removed, mud gate + fixed-point re-baselines (operator-approved), win32 net verified under wine.
- [ ] **Step 3: Commit.**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — target model + std_net extern net bindings + builtin removal reconciliation"
```

- [ ] **Step 4: Report + STOP-present close** (operator review; further plans await direction).

---

## Plan Self-Review

1. **Spec coverage:** S1 → rulings 2/3 + architecture target model; S2 → rulings 4/5/7/8 + extern rewrite + manual helpers; S3 → builtin removal; S4 → rulings 9/gates. The extern-mechanism I task covers ruling 6. Out-of-scope items excluded from tasks.
2. **Placeholder scan:** I tasks carry explicit probe/decision steps and STOP conditions instead of pre-deciding verdicts; F tasks implement recorded verdicts. No TBD.
3. **Type/name consistency:** fixture names `<name>_xmod`; report `task-NETBIND-report.md`; flags `-osl`/`-osw`; std_net API names unchanged; helper names `htonsManual`/`htonlManual` (public), extern `htons`/`htonl`.

---

## AMENDMENT — S3 direct-`@socket*` caller rulings (2026-09-04, operator)

S3 Task 3-0 inventory (Approved) found two direct `@socket*` callers. Operator rulings (m0917):
- **C1 (a):** migrate `examples/z98/rogue_mud_upgraded/demo/net_demo_client.zig` (lines 6,8,10,15,18) to the `std_net` API (protected-example exemption granted for this one demo file so the win9x client demo survives builtin removal). Migration precedes Task 3-1. If a pure-public-API client socket factory does not exist in `std_net`, STOP-present a precise gap for a narrow follow-on ruling (no public-API behavior change).
- **C2:** leave `repro/mi_matrix/net_builtin_test/main.zig` as-is; it becomes the Task 3-1 negative probe (post-removal clean `error[3000] unsupported builtin`, rc2, 0 `.c`); EXPECTED_FAIL reconciled at S4.

## AMENDMENT — std_net public API extension (2026-09-04, operator)

The C1(a) client migration cannot be done with the existing public API (no client socket factory: `socket` is a private extern; `connect(fd,port)` consumes an existing fd). Operator ruling (m0926): **extend the std_net public API** — add `pub fn createTcpClient(port: u16) i32` (localhost client mirroring `createTcpServer`: `socket(2,1,0)`, SockAddrIn to 127.0.0.1 `htonl(0x7F000001)`, `connect_os`, on failure close + return -1, else return fd). This relaxes the Global-Constraints line "std_net public API NOT to change" for this single additive factory (no existing-name behavior change). `net_demo_client.zig` migrates to: `std_net.init()` → `createTcpClient(4000)` → `send('i')` → `recv` loop → `close` → `cleanup()`. Touching `sf/src/std_net.zig` re-moves the mud gate; the intermediate `962a692c` is superseded and **the final mud 4-MD5 + self-compile fixed-point re-baselines are settled once at S4 Task 4-0** (single combined STOP-present).
