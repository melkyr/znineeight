# z9torr M3 — multi-peer scheduler, rate limits, stats — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download from N concurrent peers with rarest-first piece selection and no piece claimed twice, honour `--max-up`/`--max-down`, and show a live 1 Hz stats line.

**Architecture:** Generalize M2's single peer into a `Scheduler` holding up to `--max-peers` `Peer` slots (spec §6). Each peer is a coroutine; the scheduler owns piece state and claims. A global token bucket gates sends; `stats` renders `\r`-overwritten progress.

**Tech Stack:** Z98 (`zig1`), C89, `gcc -m32`, `std_async`, `std_net`, `std_time`, POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` (binding; §6, §8, §9, §10).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-08-z9torr-m2-single-peer-download-plan.md`. NEXT: `docs/superpowers/plans/2026-10-08-z9torr-m4-win9x-plan.md`.

## Global Constraints

- **Depends on M2.** Single-peer download + resume must pass tier2.
- **Scheduler invariants (binding).** A piece in `requested` is not claimable; on peer disconnect/corruption every piece it claimed returns to `missing` (partial blocks retained if already written-through); a peer slot is freed and reused to bound memory at `--max-peers`.
- **Timing (binding).** Monotonic ms via `std.time.ticksMs`; all elapsed-time math is unsigned subtraction (wraps correctly). Token bucket refills every 100 ms with `rate/10`, burst = `rate`. The bucket is **global** (shared across peers).
- **Tier-2 only.** No Win9x here (M4).
- Build recipe / gitignore / edit rules / no-push / no-compression as M1. **No compiler gate:** the compiler is untouched; gates are the example's own tier tests, not the fixed point / dump-MD5 / corpus classify. Reports under `.superpowers/sdd/2026-10-08-z9torr-m3-multi-peer-plan/`.
- Z98 rules: no method syntax; no generics; strict `@intCast`; `switch` needs `else`; string literals via `var s: []const u8 = "x";`.

## File Structure

- Create: `examples/z98/z9torr/{scheduler.zig,ratelimit.zig,stats.zig}`
- Modify: `examples/z98/z9torr/{main.zig,peer.zig,piece.zig,tests/tier2.sh}`

---

### Task 0: Token-bucket rate limiter

**Files:**
- Create: `examples/z98/z9torr/ratelimit.zig`

**Interfaces:**
- Produces: `TokenBucket = struct { tokens: u32, capacity: u32, rate: u32, last_refill_ms: u32 }`; `pub fn bucketInit(rate: u32) TokenBucket`; `pub fn refill(b: *TokenBucket, now_ms: u32) void`; `pub fn take(b: *TokenBucket, n: u32) bool`.

- [ ] **Step 1: Implement.** `refill`: `elapsed = now - last` (unsigned); add `rate * elapsed / 1000`, cap at `capacity = rate`; update `last`. `take(n)`: if `tokens >= n`, subtract + true; else false (the peer coroutine yields and retries next tick).
- [ ] **Step 2: Unit harness.** Synthetic sequence with a fixed clock: a 10 KB/s bucket over 60 s admits 600,000 ±10% bytes; no over-admit. Assert with a small deterministic test program under `testdata/` or inline.
- [ ] **Step 3: Commit + report.** `git commit -m "example(z9torr): add token-bucket rate limiter"`

---

### Task 1: Stats + display

**Files:**
- Create: `examples/z98/z9torr/stats.zig`

**Interfaces:**
- Produces: `Stats` (spec §6); `pub fn statsRender(s: *Stats, out_buf) []const u8` producing one line `NN.N% [####----] 1.2MB/25.0MB 340KB/s peers=4 eta=1m02s`, using integer math + a manual decimal point (no float printf dependency).

- [ ] **Step 1: Implement** byte formatting (`MB = bytes/1048576`, `frac = (bytes%1048576)*100/1048576`), a 40-char progress bar, a 5-sample rolling rate window, and ETA guarded against `down_rate == 0`.
- [ ] **Step 2: Snapshot test.** On a synthetic `Stats` sequence, the rendered lines are byte-stable; refresh at 1 Hz.
- [ ] **Step 3: Commit + report.** `git commit -m "example(z9torr): add stats counters + display"`

---

### Task 2: Scheduler

**Files:**
- Create: `examples/z98/z9torr/scheduler.zig`
- Modify: `examples/z98/z9torr/{peer.zig,piece.zig}`

**Interfaces:**
- Produces: `Scheduler` (spec §6); `pub fn schedulerInit(arena, t, max_peers) !Scheduler`; `pub fn pickPiece(s, peer) ?u32` (rarest-first: scan for the rarest piece this peer has and that is `missing`); `pub fn claim(s, index) void`; `pub fn release(s, peer) void` (re-queue every piece that peer held); `pub fn addPeer(s, addr) bool` (reuse a free slot; skip duplicate recently-seen addresses); `pub fn removePeer(s, peer) void`.

- [ ] **Step 1: Implement rarest-first without sorting.** Maintain `piece_rarest[i]` = count of connected peers with bit `i`; on `have`/bitfield update increment, on disconnect decrement (assert no underflow). `pickPiece` linear-scans eligible pieces for the minimum count.
- [ ] **Step 2: Claim/release.** `claim` marks the piece's owning peer; `release` returns the peer's claimed pieces to `missing` (retaining written-through blocks).
- [ ] **Step 3: Slot reuse + dedupe.** A small ring of recently-seen `PeerAddr`s skips duplicates; a freed slot is reused.
- [ ] **Step 4: Unit test.** Two mock peers with overlapping bitfields: assert `pickPiece` never returns a `requested` piece and prefers the rarer one.
- [ ] **Step 5: Commit + report.** `git commit -m "example(z9torr): add rarest-first multi-peer scheduler"`

---

### Task 3: Multi-peer integration + CLI flags

**Files:**
- Modify: `examples/z98/z9torr/{main.zig,tests/tier2.sh}`

**Interfaces:**
- Consumes: `Scheduler`, `TokenBucket`, `Stats`, `tracker.announce`.

- [ ] **Step 1: `main.zig`.** Announce, create the scheduler with `args.max_peers`, spawn one peer coroutine per `AnnounceResult.peers` entry (capped), run the `std.async` tick loop, and on completion announce `event=completed`. Gate every send through the global bucket at `args.max_down`/`args.max_up` (0 = unlimited).
- [ ] **Step 2: CLI flags honoured.** `--max-peers` caps slots; `--max-up`/`--max-down` set the bucket rates; `--help`/usage unchanged.
- [ ] **Step 3: Manual test** with 4 `mock_peer`s on distinct ports serving `t2_single_25m`; assert SHA-1 and that no two peers are asked for the same piece in a tick (log + assert).
- [ ] **Step 4: Commit + report.** `git commit -m "example(z9torr): multi-peer download with rate limits + stats"`

---

### Task 4: tier2 multi-peer + closeout

**Files:**
- Modify: `examples/z98/z9torr/{tests/tier2.sh,demo/README.md,NOTES.md}`
- Record: `.superpowers/sdd/2026-10-08-z9torr-m3-multi-peer-plan/task-4-report.md`

- [ ] **Step 1: Extend `tier2.sh`:** start 4 `mock_peer`s; download `t2_single_25m`; assert exit 0 + SHA-1; assert scheduler unit invariant (no double-request); run the resume test again (now multi-peer).
- [ ] **Step 2: Gate (example-only).** `bash examples/z98/z9torr/tests/tier2.sh` → all PASS (multi-peer download + no double-request + resume). No compiler-only gates — the compiler is untouched.
- [ ] **Step 3: Docs + commit + report.** Update `demo/README.md`/`NOTES.md`. Ledger line.
- [ ] **Step 4: Next plan.** State that M4 (`2026-10-08-z9torr-m4-win9x-plan.md`) is next.

## Self-Review

- **Spec coverage:** §6 `Scheduler`/`TokenBucket`/`Stats` → Tasks 0–2; §8 flags → Task 3; §9 timing/determinism → Task 0; §10 tier2 → Task 4.
- **Placeholder scan:** no TBDs; invariants are explicit and tested.
- **Type consistency:** `Scheduler`/`pickPiece`/`claim`/`release`/`addPeer`/`removePeer`, `TokenBucket`/`bucketInit`/`refill`/`take`, `Stats`/`statsRender` match spec §6.
