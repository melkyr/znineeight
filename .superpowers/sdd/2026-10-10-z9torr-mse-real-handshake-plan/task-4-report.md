# Task 4 report — Non-blocking connect + MSE probe

**Status:** DONE
**Plan:** `docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md` (Task 4)
**Spec:** `docs/superpowers/specs/2026-10-10-z9torr-mse-real-handshake-design.md` (§3.3/§5)
**Commit:** (see below) — `perf(z9torr): non-blocking connect + MSE probe`
**Compiler:** `/tmp/z9_m41_seed/zig1_5_clean`, closure md5
`46e3e7af98af3b5ff2a960c7c96025e3` (seed v96; matches the plan). `-ffast` +
`build_target.sh linux`. **No compiler/seed change** (`sf/`, `scripts/`,
`release/` untouched).

## Step 1 — Coroutine-aware connect + MSE probe

### (a) Non-blocking connect — `examples/z98/z9torr/peer.zig`

The old path used `std_net.connectToIp`, which does a non-blocking `connect(2)`
and then **blocks in `select(2)`** for up to `CONNECT_TIMEOUT_MS` (1000 ms) — so
one dead peer froze the single-threaded `tick` loop. Added `connectAsync`:

- issues the raw `connect(2)` via an example-local `extern "stdcall" fn
  connect_os(...)` (aliased to the OS `connect` by the emitted `net_prelude.h`)
  on an already non-blocking socket;
- then polls `select(..., timeout 0)` and, while the connect is in progress,
  yields via `@asyncSuspend(null)`; a real failure surfaces through the pub
  `std_net.checkSoError` (SO_ERROR), and a still-in-progress connect gives up at
  `error.Timeout` once `deadline_ms` elapses;
- `errno` is private to `std_net`, so the outcome is read from the socket
  (select + `checkSoError`) rather than the raw `connect_os` return code.

`std_net`'s `SockAddrIn` is private, so the same 16-byte IPv4 layout is declared
locally in `peer.zig` (documented). The initial connect in `peerRun` and the
plaintext-fallback reconnect (`plainReconnect`) both use `connectAsync`;
`plainReconnect`'s inter-attempt `sleepMs(20)` became a cooperative
`@asyncSuspend(null)`, so it too never blocks the scheduler.

### (b) Non-blocking MSE probe — `examples/z98/z9torr/mse.zig`

`mseConnect` (select(2)-gated blocking, `DEADLINE_MS = 3000`) became
`mseConnectAsync`:

- `sendAllMse`/`recvExactMse` now yield on `WouldBlock` via `@asyncSuspend` and
  time out at the same absolute `start_ms + DEADLINE_MS`. The two private
  `waitReadable`/`waitWritable` (blocking `select`) helpers are removed;
- the two RC4 contexts are written through a caller-owned `out: *Rc4Pair`
  (no struct-return temp crosses a suspension);
- **all fixed-size handshake scratch moved to a caller-owned
  `mse.MseScratch` (`peer.msesc`)**: the zig1 emitter saves a frame array across
  a suspension with a C array assignment, which C89 rejects
  (`assignment to expression with array type`) — the same reason
  `wire.readHandshakeAsync` takes slices. RC4 contexts stay frame locals (struct
  assignment is valid C89).

The encrypted-first / plaintext-fallback structure is unchanged.

### (c) zig1 async-transform ordering constraint (worked around, no compiler change)

Adding value-returning implicit awaits of **different** return types to
`peerRun` (`connectAsync: NetError!void`, `mseHandshake/plainReconnect: bool`)
tripped the async transform's P2/P4 assertion:

```
error[3043]: async parent_result slot type mismatch (P2/P3 vs P4 order desync)
```

(`async_state_machine.zig:429`). The AST slot scan and the LIR await walk
disagreed on the parent_result slot order once value-awaits of distinct types
were interleaved through the connect path. Fixed **without touching the
compiler** by making the three new helpers return `void` and report success via
`*bool` out-params (`connectPeer`, `mseHandshake`, `plainReconnect`), so
`peerRun`'s only value-returning implicit awaits remain the homogeneous
`PeerError!void` readers. This is a compiler-shape constraint, not a semantic
change; all tiers stay green.

## Step 2 — Many-peers stall scenario (non-vacuous)

New `tools/mock_blackhole_peer.zig` (accepts TCP, never reads/writes/closes) and
`tests/tier_stall.sh`. The tracker advertises the **black-hole first** (slot 0,
ticked before the healthy peer) and a healthy `mock_mse_peer` second (slot 1).

| Assertion | Result |
|---|---|
| run exit 0 | PASS |
| byte-verified encrypted download | PASS |
| healthy peer `handshake ok enc` | PASS |
| both candidates dialed (`spawn=2`) | PASS |
| black-hole dialed into slot 0 | PASS |
| `handshake ok enc` before `mse-fail err=Timeout` (or stall never logged) | PASS |
| wall time < 3000 ms (black-hole MSE deadline) | PASS (473–479 ms) |

**Non-vacuity proven** by running the identical scenario on the pre-change
binary (`/tmp/t4_base/prog`, built from commit `6dafd966` before this task):

| | pre-fix (blocking) | post-fix |
|---|---|---|
| elapsed | **3436 ms** (serialized the 3000 ms MSE deadline) | **473–479 ms** |
| first stall line | `peer slot=0 mse-fail err=Timeout` (line 10) | absent (healthy peer won the race) |
| `handshake ok enc` | line 26 (after the stall) | line 23-ish (before any stall) |

`tier_stall.sh`: **8 passed, 0 failed** (`TIER_STALL PASS`).

## Step 3 — Battery (all green)

Run with `ZIG=/tmp/z9_m41_seed/zig1_5_clean`:

| Tier | Result |
|---|---|
| `tier1.sh` | 16 passed, 0 failed |
| `tier1_cli.sh` | all passed |
| `tier1_unit.sh` | all passed |
| `tier2.sh` | 17 passed, 0 failed (incl. plaintext fallback + resume) |
| `tier3_encrypted.sh` | 5 passed, 0 failed (mock_mse_peer) |
| `tier_udp_tracker.sh` | 7 passed, 0 failed |
| `tier_dht.sh` | 4 passed, 0 failed |
| `tier_pex.sh` | 11 passed, 0 failed |
| `tier_stall.sh` (new) | 8 passed, 0 failed |
| `tier_refseed_py.sh` | 6 passed, 0 failed |
| `tier_refseed.sh` (aria2c 1.36.0) | 6 passed, 0 failed |

`mock_mse_peer`/`mock_tracker`/`mock_peer`/`mock_blackhole_peer` all build.

### `--dump-c89` md5 / compiler closure

- Compiler closure md5: `46e3e7af98af3b5ff2a960c7c96025e3` (seed v96, unchanged).
- `cd <repo-root> && timeout 120 /tmp/z9_m41_seed/zig1_5_clean --dump-c89
  examples/z98/z9torr/main.zig | md5sum` → **`5c2f2b190dc98ff76d1f2aee7d28c14e`**
  (rc=0). Example-only change; the compiler is untouched.

## Concerns

1. **zig1 async P2/P4 order constraint** (worked around, no compiler change):
   interleaving value-returning awaits of distinct types in one coroutine is
   rejected as `error[3043]`. The workaround (void helpers + `*bool` out-params)
   is local and idiomatic here, but it is a compiler-shape constraint future
   coroutine work should know about. NOT a compiler change (frozen post-D1–D5).
2. **Fixed-array scratch across a suspension** is un-emittable (C array
   assignment, C89-invalid). Solved by the caller-owned `mse.MseScratch`
   (`peer.msesc`); `Peer` grows by ≈468 B (16 slots ≈ 7.5 KB, well inside the
   4 MiB scheduler arena). RC4 contexts remain frame locals.
3. **Raw `connect_os` extern in the example.** `std_net` exposes no public
   non-blocking connect and `SockAddrIn` is private; the example declares the
   `net_prelude.h` alias and the sockaddr layout locally. This is example-only
   and Linux-verified; the emitted prelude is target-neutral (Windows branch
   present) but only the Linux path was exercised here.
4. **`connectAsync` reads the outcome from `select(0)` + `SO_ERROR`, not errno**
   (errno is private to `std_net`). Standard non-blocking-connect semantics;
   verified by loopback success (all tiers) and refusal/timeout paths
   (`tier_stall`, `tier2` malformed peers).
5. **No push; no destructive git; no compiler/seed change.** Files:
   `peer.zig`, `mse.zig`, `tests/tier_stall.sh`, `tools/mock_blackhole_peer.zig`
   (+ this report via `git add -f`).

## Commit

`perf(z9torr): non-blocking connect + MSE probe` —
`examples/z98/z9torr/peer.zig`, `examples/z98/z9torr/mse.zig`,
`examples/z98/z9torr/tests/tier_stall.sh`,
`examples/z98/z9torr/tools/mock_blackhole_peer.zig`. No push.
