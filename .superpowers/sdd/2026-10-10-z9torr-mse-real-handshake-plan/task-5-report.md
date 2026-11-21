# Task 5 report — Fallback policy + fix + live retest + closeout

**Status:** DONE
**Plan:** `docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md` (Task 5)
**Spec:** `docs/superpowers/specs/2026-10-10-z9torr-mse-real-handshake-design.md`
**Commit:** `example(z9torr): M4.1 real-handshake closeout` (see `git log`; report
included via `git add -f`). No push.
**Compiler:** `/tmp/z9_m41_seed/zig1_5_clean`, closure md5
`46e3e7af98af3b5ff2a960c7c96025e3` (seed v96; matches the plan). `-ffast` +
`build_target.sh linux`. **No compiler/seed change** (`sf/`, `scripts/`,
`release/` untouched).

## Step 1 — Policy A + the plaintext-fallback fix

Policy A (operator ruling) was already the shipped shape: encrypted-first, and on
any MSE failure a fresh plaintext reconnect (`peer.zig` `peerRun` -> `plainReconnect`
-> `writeHandshake`/`readHandshakeAsync`). It is kept unchanged.

### The real defect (root cause)

`plainReconnect` had a fixed `attempt < 100` cap combined with an inter-attempt
pause. **M4.1 Task 4 replaced that pause (`std.time.sleepMs(20)`) with a
cooperative `_ = @asyncSuspend(null)`** (to stop blocking the scheduler), but kept
the cap. Because `main.zig`'s drive loop calls `std.async.tick` in a tight loop
with **no sleep**, a suspended task is resumed on the very next tick: 100
fast-failing connects exhaust in **microseconds**, so the fallback returned
`reconnect-fail` long before its nominal ~3 s budget — a plaintext peer that only
became reachable shortly after the MSE probe never got a second connection. This
is exactly the operator's "the plaintext fallback currently never succeeds".

### Reproduced (non-vacuous RED)

A plaintext-only `mock_peer` behind a restart wrapper with a **300 ms gap**
(pre-fix client `/tmp/z9_t5_out/prog`, commit `f2d627a3`):

```
mse stage=yb fail err=NetFailed
peer slot=0 mse-fail err=NetFailed
peer slot=0 reconnect-fail          <-- gave up after ~100 tight retries
peer slot=0 end down=0
exit code=4 reason=peer incomplete  (output sha1 3b71f43f…, 0 bytes)
```

### Fix (`examples/z98/z9torr/peer.zig`)

`plainReconnect` is now **deadline-driven** (`FALLBACK_WINDOW_MS = 3000`) with a
**wall-clock-throttled** retry (`FALLBACK_RETRY_MS = 20`): it yields cooperatively
(no blocking `sleepMs`, preserving Task 4) but attempts a connect at most once
per 20 ms, so an immediate `ECONNREFUSED` cannot burn the budget in a spin and the
full ~3 s window is honoured regardless of how fast connects fail. Two named
constants added near `CONNECT_TIMEOUT_MS`; the stale 100-attempt cap removed.

### GREEN (same scenario, fixed client)

```
hs fd=5 ok
peer slot=0 handshake ok plain
peer slot=0 break reason=completion
peer slot=0 end down=1048576
exit code=0 reason=ok  (sha1 7a985d40cf76ef129b2889fa5bfce75304067dc9)
```

Also verified against a realistic **persistent** plaintext-only peer (accept loop,
validates the plaintext handshake, serves the payload) and against a peer that
holds the MSE-probe connection silently: both complete byte-verified (the MSE
probe times out at 3 s, then the fallback succeeds).

### Hermetic test (new) — `examples/z98/z9torr/tests/tier_fallback.sh`

Uses the **existing one-shot plaintext `tools/mock_peer`** (a plaintext-only peer,
so the encrypted path cannot succeed) kept alive behind a restart wrapper with a
deliberate `Z9TORR_FB_GAP_MS` (default 200 ms) gap — i.e. the peer is briefly
UNreachable exactly when the client falls back, forcing the fallback to keep
retrying. Asserts (8 cases, all non-vacuous):

- MSE attempted first: `mse stage=ya` + `mse-fail`;
- fallback path used: `handshake ok plain`;
- encrypted path NOT used against the plaintext mock (no `handshake ok enc`);
- no `reconnect-fail`;
- exit 0 + byte-verified output (`sha1 == 7a985d40…`).

`tier_fallback.sh`: **8 passed, 0 failed** (`TIER_FALLBACK PASS`, ~0.5 s). RED on
the pre-fix client (reproduces `reconnect-fail` -> exit 4 with the gap).

## Step 2 — lin_bin rebuilt + best-effort live Debian retest

`lin_bin/` rebuilt (untracked bundle; torrent unchanged): new Linux x86-64
`z9torr` from the fixed sources, md5 **`d3acae94810682c5fef746c710773fc7`**
(previous M4 binary `f42f9011…`). `INSTRUCTIONS.txt` updated to seed v96 closure
`46e3e7af98af3b5ff2a960c7c96025e3` and the new md5.

Live retest: `Z9TORR_LOG=1 timeout 100 ./z9torr debian-13.7.0-amd64-netinst.iso.torrent`
(from `lin_bin/`; `out.txt` + `z9torr.log` refreshed). Honest outcome:

| metric | result |
|---|---|
| tracker peers | **50** (`announce peers=50 interval=900`) |
| spawned | 16 (`spawn=16`) |
| TCP connects (`fd=`) | 7 (`fd=5,6,7,8,12,13,14`); 9 `connect-fail err=timeout`, 1 `refused` |
| **MSE** | **1 real encrypted success: `mse stage=done` + `handshake ok enc`** (slot 9) |
| **plaintext fallback** | **1 real success: `mse-fail err=PeerClosed` then `handshake ok plain`** (slot 7) |
| `reconnect-fail` | **0** (the fix — the fallback no longer gives up) |
| other handshake fails | `HandshakeFailed` / `NetFailed` / `PeerClosed` at/after the handshake |
| bytes | **0** (`summary` absent; exit 4 `peer incomplete`) |

So the milestone goal (a **real** MSE handshake, and a real plaintext fallback)
is now demonstrated against the live swarm — neither ever happened before. No
payload arrived because the reachable peers closed right after the transport
handshake or were rejected on reserved bits (below); egress itself works (HTTP
tracker + 7 connects). This is the sandbox/NAT reality, reported, never hidden.

### Unforeseen divergence found (reported, deliberately NOT fixed here)

During the retest, real qBittorrent/libtorrent peers send reserved bytes
`0000000000180005` (i.e. `reserved[5]=0x18`, `reserved[7]=0x05`). z9torr's
`wire.reservedAccepted` allows only `reserved[5]&0x10` and `reserved[7]&0x01|0x04`,
so it returns `HandshakeFailed` (`peer slot=0`/`2 handshake-fail`). Per BEP 3,
unknown reserved bits MUST be ignored, not rejected. This is a real remaining
compatibility gap, but it is OUTSIDE M4.1's fallback scope; per the plan's
"STOP-present on divergence" rule it is recorded (NOTES/README/spec/plan) as the
first item of the resumed M4 polish rather than patched under Task 5.

## Step 3 — Battery (all green) + docs

Run with `ZIG=/tmp/z9_m41_seed/zig1_5_clean` from the repo root:

| Tier | Result |
|---|---|
| `tier1.sh` | 16 passed, 0 failed |
| `tier1_cli.sh` | all passed (8/8) |
| `tier1_unit.sh` | all passed (3/3) |
| `tier2.sh` | 17 passed, 0 failed |
| `tier3_encrypted.sh` | 5 passed, 0 failed |
| `tier_udp_tracker.sh` | 7 passed, 0 failed |
| `tier_dht.sh` | 4 passed, 0 failed |
| `tier_pex.sh` | 11 passed, 0 failed |
| `tier_stall.sh` | 8 passed, 0 failed |
| **`tier_fallback.sh` (new)** | **8 passed, 0 failed** |
| `tier_refseed_py.sh` | 6 passed, 0 failed |
| `tier_refseed.sh` (aria2c 1.36.0; NO SKIP — egress available) | 6 passed, 0 failed |

`--dump-c89` md5 of `main.zig`: **`14fae4e8c108d5d60944faba604ae343`** (stable
3x). Compiler closure unchanged (`46e3e7af98af3b5ff2a960c7c96025e3`); example-only
change.

Docs updated: `examples/z98/z9torr/NOTES.md` (M4.1 section + counts + finding),
`README.md`, `demo/README.md` (new md5, M4.1 gate table), and the M4.1
`spec`/`plan` both marked **DONE**, NEXT = resume z9torr M4 polish (relax unknown
reserved bits) then M5 (Win9x).

## Step 4 — Commit

`example(z9torr): M4.1 real-handshake closeout` — `peer.zig`,
`tests/tier_fallback.sh` (new), `NOTES.md`, `README.md`, `demo/README.md`,
`docs/.../2026-10-10-z9torr-mse-real-handshake-design.md`,
`docs/.../2026-10-10-z9torr-mse-real-handshake-plan.md`, and this report
(`git add -f`). No push; no destructive git; single commit.

## Concerns

1. **The Task 5 directive's premise was reproduced as a real defect**, but not
   where the operator located it: the fallback *path* is correct; the bug was the
   Task-4 interaction (100-attempt cap + zero-delay `@asyncSuspend`). Fixed here
   with a deadline-driven, wall-clock-throttled retry.
2. **Unknown reserved bits are still rejected** (qBittorrent `reserved[5]=0x18`).
   This is the next M4-polish step (BEP 3 says ignore). It reduced the live
   retest's usable peers; reported, not patched (scope).
3. **Live retest fetched 0 bytes** — honest environmental outcome (peers close
   after the handshake / reject on reserved bits / NAT-egress). The milestone's
   *proof* is the hermetic tiers (`tier_refseed`, `tier_refseed_py`,
   `tier_fallback`) plus the now-real `handshake ok enc` / `handshake ok plain`.
4. **No client regression** (Task 4's non-blocking intent preserved: no blocking
   `sleepMs` in the fallback); all 12 tiers green. Compiler/seed untouched.
