# Task 3 report — Fix the MSE handshake (per Task 1 findings)

**Status:** DONE
**Plan:** `docs/superpowers/plans/2026-10-10-z9torr-mse-real-handshake-plan.md` (Task 3)
**Spec:** `docs/superpowers/specs/2026-10-10-z9torr-mse-real-handshake-design.md` (§3.2/§5)
**Commit:** `256fb1bcc8d75166c7c28b1314db13dd387d1418` —
`fix(z9torr): correct the MSE handshake against reference peers`
**Compiler:** `/tmp/z9_m41_seed/zig1_5_clean`, closure md5
`46e3e7af98af3b5ff2a960c7c96025e3` (seed v96; matches the plan). `-ffast` +
`build_target.sh linux`. No compiler/seed changes.

## Step 1 — RED (pre-fix, reproduced exactly as T2 recorded)

Both reference tiers failed on the un-fixed client, each localizing to its
T1-identified defect:

- `tier_refseed_py.sh`: `client-exit=124`, `3 passed, 3 failed`; MSE
  `stage=done` + `handshake ok enc` but the responder saw no `request (id=6)` →
  `piece.bitGet` decoded the peer bitfield LSB-first, so the spec-correct
  `0xF0` bitfield read as pieces 4–7 (≥ `n_pieces=4`) → client saw an empty
  peer and stalled.
- `tier_refseed.sh`: `client-exit=4`, `3 passed, 3 failed`; `hsenc
  reserved=0000000000100004` → `wire.reservedAccepted` rejected aria2c's Fast
  Extension bit (`reserved[7]=0x04`) → `HandshakeFailed`.

## Step 2 — Fixes

### (a) Client bitfield bit order — `examples/z98/z9torr/piece.zig`

`bitGet`/`bitSet` now index bit `i` MSB-first, per BEP 3:
byte `i / 8`, mask `1 << (7 - (i % 8))` (was `>> (i % 8)`, LSB-first).
This is the same order the wire `bitfield` message uses and the order the
client must use for its own completed-piece bitset, so a decode/encode pair
stays symmetric.

### (a-consistency) Shared `completed_bits` buffer — `examples/z98/z9torr/resume.zig`

The `completed_bits` byte buffer is written by `peer.zig` via
`piece.bitSet`/`bitGet` **and** read/rehashed by `resume.zig` via its own
private `bitGet`/`bitSet`/`bitClear`; the same slice is then read again by
`main.zig` via `piece.bitGet`. Changing only `piece.zig` would make the
producer MSB-first while `resume.zig` still decoded LSB-first, aliasing
`piece j`'s MSB bit onto `piece i`'s LSB bit and letting `rehash` mark the
wrong pieces verified (a latent correctness bug). `resume.zig`'s three bitmap
helpers are therefore flipped to the identical
`BITS_PER_BYTE - 1 - (i % BITS_PER_BYTE)` shift. This buffer is z9torr-private
(sidecar-persisted, no external wire contract), so the flip is
self-consistent; `tier2`'s resume assertions are bit-position-agnostic
("completed_bits has a set byte") and stay green.

### (b) Fast Extension reserved bit — `examples/z98/z9torr/wire.zig`

`reservedAccepted` now allows the BEP 6 Fast Extension bit (`reserved[7]`,
`0x04`) in addition to BEP 5 DHT (`0x01`) and BEP 10 (`reserved[5]`, `0x10`):
the `reserved[7]` reject mask changed from `0xFE` to `0xFA` (rejects every bit
except `0x01|0x04`). DHT (`0x01`) handling is unchanged and still accepted;
unknown bits (e.g. `0x02`, `0x08`) are still rejected, as is any non-zero byte
outside 5/7. z9torr does NOT advertise `0x04` itself, so a peer that sets the
bit (aria2c) does not switch to fast-extension messages (no `have all` /
`have none` / `reject` traffic); it still sends a normal bitfield — confirmed
empirically below.

### (c) Tier harness — `examples/z98/z9torr/tests/tier_refseed.sh`

After (a)+(b), the client accepted aria2c's encrypted handshake but still
stalled. Root-caused (not a client divergence): the tier copied the payload to
aria2's download dir but started aria2 **without hash-checking it**, so aria2
announced `left=1048576` (0 completed pieces), stayed a leecher, and — being a
non-Fast-Extension peer — queued no bitfield at all (`addBitfieldMessageToQueue`
sends nothing when completed length is 0 and the peer is not fast-extension
enabled). The client, seeing no peer pieces, sent no requests. Fix: add
`--check-integrity=true` to the aria2 seeder invocation so aria2 verifies the
pre-seeded payload and becomes a real SEEDER (`Seeder state` choke round;
debug-confirmed it then emits a normal bitfield). `sleep 2` → `3` to let the
1 MiB hash check finish before the client dials. This is a test-harness
correction only; no client/compiler behavior changed for it.

## Step 3 — GREEN

Both reference tiers now complete a byte-verified encrypted download, and the
`mock_mse_peer` tier stays green:

| Tier | Result |
|------|--------|
| `tier_refseed_py.sh` (python responder) | 6 passed, 0 failed — `client-exit=0`, output sha1 `7a985d40cf76ef129b2889fa5bfce75304067dc9`, `mse stage=done`, `handshake ok enc`, responder saw `frame id=6` |
| `tier_refseed.sh` (aria2c 1.36.0, forced enc.) | 6 passed, 0 failed — `client-exit=0`, output sha1 `7a985d40…`, `mse stage=done`, `handshake ok enc` |
| `tier3_encrypted.sh` (mock_mse_peer) | 5 passed, 0 failed |

## Step 4 — Battery (all existing tiers green)

Run with `ZIG=/tmp/z9_m41_seed/zig1_5_clean`:

| Tier | Result |
|------|--------|
| `tier1.sh` | 16 passed, 0 failed |
| `tier1_cli.sh` | all passed |
| `tier1_unit.sh` | all passed |
| `tier2.sh` | 17 passed, 0 failed (incl. interrupt/restart resume) |
| `tier3_encrypted.sh` | 5 passed, 0 failed |
| `tier_udp_tracker.sh` | 7 passed, 0 failed |
| `tier_dht.sh` | 4 passed, 0 failed |
| `tier_pex.sh` | 11 passed, 0 failed |

### `--dump-c89` md5 / compiler closure

- Compiler closure md5 (`/tmp/z9_m41_seed/zig1_5_clean`):
  `46e3e7af98af3b5ff2a960c7c96025e3` (seed v96, unchanged).
- `cd <repo-root> && timeout 120 /tmp/z9_m41_seed/zig1_5_clean --dump-c89
  examples/z98/z9torr/main.zig | md5sum` → **`af255fda2f7463da3c3f982588485f64`**
  (rc=0). Example-only changes; the compiler is untouched, so this naturally
  differs from the T1/T2 example source (expected).

## Concerns

1. **`resume.zig` consistency fix included.** Task 1 localized only
   `piece.zig`; but `completed_bits` is shared with `resume.zig`'s private
   bitmap helpers, so a `piece.zig`-only change would have introduced a
   producer/consumer bit-order mismatch. The three `resume.zig` shifts were
   flipped to MSB-first for consistency. It is a self-contained, format-local
   change; all 8 battery tiers (incl. tier2 resume) stay green.
2. **aria2 tier residual was a harness flaw, not a client bug.** The T2 tier
   never hash-checked the seeded payload, so aria2 was a 0-piece leecher.
   `--check-integrity=true` makes it a real seeder; the underlying client MSE
   handshake + encrypted transfer was already correct after (a)+(b). Localized
   and fixed; documented above. No client behavior was altered to accommodate
   it.
3. **aria2 acquisition is network-dependent** (`get_aria2.sh` runs `apt-get
   update` + `--download-only`). It succeeded here (aria2 1.36.0); offline it
   SKIPs with an explicit reason (exit 77) rather than a silent pass. The
   Python tier carries the hermetic gate offline.
4. **Fast Extension semantics:** z9torr does not advertise `reserved[7]&0x04`,
   so peers that set it keep using classic wire messages (no have-all/
   have-none/reject). Confirmed with aria2c (normal bitfield + byte-verified
   transfer).
5. **No push; no destructive git; no compiler/seed change.** Files changed:
   `piece.zig`, `resume.zig`, `wire.zig`, `tests/tier_refseed.sh`. (Reports
   under `.superpowers/...` added via `git add -f`.)

## Commit

`256fb1bc` `fix(z9torr): correct the MSE handshake against reference peers` —
`examples/z98/z9torr/piece.zig`, `examples/z98/z9torr/resume.zig`,
`examples/z98/z9torr/wire.zig`, `examples/z98/z9torr/tests/tier_refseed.sh`.
No push.
