# M6 Task 2 report — transport, timers, replay, cookies

Status: complete (Task 2 only). Docs, tier, seed rotation, full stdlib gate,
compiler battery, and `progress.md`/`run.err` are untouched.

## 1. Environment / base

- Repo root `/workspace/znineeight`; branch `zig1_improvements`; task base
  `cbd98e66` (`a4570e36` is the T1-closeout ledger commit).
- Compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  (`md5sum` = `45158dcede81125a39a2c2c58478e21e`).
- Only `sf/src/std_wireguard.zig` was synced into the compiler's sibling
  `lib/` for tests; seed not rotated.
- `run.err` remains untracked/untouched.

## 2. Reference capture (`ref.c`, C89)

Extended `scripts/stdlib/ref/std_wireguard/ref.c` with:
- transport-data encryption (type 4, 64-bit LE counter, zero pad to 16,
  ChaCha20-Poly1305, empty AD);
- CookieReply generation/consumption (XChaCha20-Poly1305, AD = initiation
  `mac1`), and mac2 inclusion in a re-initiation;
- crosscheck line modes `t <counter> <pt-hex|->` and
  `c <seed> <wall> <cookie-reply-hex>` while retaining the original
  `<seed> <wall>` handshake mode.

Reference build (strict C89, m32):

```text
$ gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration scripts/stdlib/ref/std_wireguard/ref.c \
    -o /tmp/wg_ref_c89 -lm
RC=0
```

(The only warnings are the pre-existing `x25519.c` `-Wstringop-overread`
warnings; no new ref warnings.)

Existing handshake vector unchanged:

```text
$ /tmp/wg_ref_c89 --crosscheck < scripts/stdlib/vectors/std_wireguard/handshake.in > /tmp/h.out
$ cmp /tmp/h.out scripts/stdlib/vectors/std_wireguard/handshake.expected && echo HANDSHAKE_MATCH
HANDSHAKE_MATCH
```

Transport capture (inputs are the three committed `transport.in` lines):

```text
$ /tmp/wg_ref_c89 --transport-capture
04000000d4c3b2a100000000000000003c1d454b2ffa5e2b2c6cfb1330b8d3d02ad4aee303176f955a423c2c40cbfaa9
04000000d4c3b2a10100000000000000c9a3a70c59fb5a3e7e518aabcab9564a437c3cdcef1f9b0d9bf948393c00b489
04000000d4c3b2a1fedfffffffffffff0fde66cda55701a5e7adac8d8e9f313d
```

Cookie capture (line 1 is `cookie.in`; line 2 is `cookie.expected`):

```text
$ /tmp/wg_ref_c89 --cookie-capture
c 81985529216486895 1800000000123456789 03000000cf5492ac000102030405060708090a0b0c0d0e0f10111213141516171bed1ea5491192f1c710d2cc96a85d70740a32f6af197515a5c337843d1f212d
01000000cf5492ac5ac39f7a9b74c617f2c191c2a9504e5dc0a0bb51edc1ab756de2a6883fdfa65f7c5c9820bad0f86cba59b3911b5251e0e5522aca30e7633ee3b54990f58d8082555f1fffa1c98a828bb2da07059593e3274039d419c4fdd4364ee749bb2bc2e3f21c67eb0e1420f9de88c10f3466ac286f3266335dacfe24859fd4c1da3c58e10b14ef16c6fc9272a5dd1882
```

Both committed vectors re-verified against the ref crosscheck mode:

```text
$ /tmp/wg_ref_c89 < scripts/stdlib/vectors/std_wireguard/transport.in > /tmp/t.out
$ cmp /tmp/t.out scripts/stdlib/vectors/std_wireguard/transport.expected && echo TRANSPORT_REF_MATCH
TRANSPORT_REF_MATCH
$ /tmp/wg_ref_c89 < scripts/stdlib/vectors/std_wireguard/cookie.in > /tmp/c.out
$ cmp /tmp/c.out scripts/stdlib/vectors/std_wireguard/cookie.expected && echo COOKIE_REF_MATCH
COOKIE_REF_MATCH
```

## 3. Failing fixture first

Created `repro/mi_matrix/stdlib_wg_transport_xmod/main.zig` and pinned it in
`scripts/stdlib/expected_dirs.txt` before implementation. Missing golden:

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_wg_transport_xmod
FAIL repro/mi_matrix/stdlib_wg_transport_xmod (MISSING-GOLDEN)
----------------------------------------
run_fixtures: 0 PASS / 1 FAIL over 1 dirs
failed: repro/mi_matrix/stdlib_wg_transport_xmod
RC=1
```

## 4. Implementation (`sf/src/std_wireguard.zig`)

- Added spec §5.7 `WgAction` union exactly as amended.
- Added `wgSend`, `wgTick`, `wgReceive`.
- Transport: type 4 header, LE receiver + 64-bit counter nonce, zero padding
  to 16, ChaCha20-Poly1305 with empty AD; keepalive is empty plaintext.
- `wgSend` requires a live session (`error.NoSession` otherwise), returns
  `error.SessionExpired` at/after 180 s or at `REJECT_AFTER_MESSAGES`;
  `wgTick` owns initiation/retry.
- Replay: 2048-bit window (32 × `u64`) with RFC 6479-style shift; duplicates,
  counters older than the window, and in-window duplicates return
  `WgAction.dropped_replay`; in-window unseen counters are accepted.
  Authentication is checked before the window is updated.
- Timers: keepalive 10 s idle, rekey initiation at 120 s, retry at
  `5 s + bounded per-attempt jitter` (attempt-dependent 0..333 ms, no sleep),
  reject at 180 s. Expired sessions never encrypt/keepalive in `wgTick`.
- Cookie: XChaCha20-Poly1305 CookieReply consumption (AD = pending initiation
  `mac1`), stores the 16-byte cookie; the next initiation includes mac2
  (`keyed BLAKE2s-128(cookie, initiation-minus-mac2)`).
- Response processing through `wgReceive` clears counters/replay state and
  returns `session_up`.
- `WgPeer` gained counter/replay/timer fields and `wgAddPeer` zeroes them.
- No `sleep`; all timer logic is `now_ms`-parameterized.

## 5. Fixture coverage and green result

`stdlib_wg_transport_xmod` pins:
- byte-exact transport for counters 0, 1, and
  `REJECT_AFTER_MESSAGES - 1` (13-byte IPv4-ish plaintext, 3-byte plaintext,
  and empty keepalive) including padding and tags;
- monotonic wire counters and `SessionExpired` on the next send after reject;
- `NoSession` without a session and `SessionExpired` at 180 s;
- replay: fresh, duplicate, window-edge, old-seen, in-window-unseen,
  in-window duplicate, window advance, too-old;
- timers: no action before 10 s, keepalive at 10 s, no action just before
  120 s, rekey at 120 s, retry at 125137 ms (5 s + 137 ms jitter), reject at
  180 s, expired pending handshake returns no keepalive;
- CookieReply consumption then mac2-bearing re-initiation byte-exact.

Capture:

```text
$ bash scripts/stdlib/run_fixtures.sh --capture \
    /tmp/m2_t4_v114_build/zig1_5_clean repro/mi_matrix/stdlib_wg_transport_xmod
CAPTURED repro/mi_matrix/stdlib_wg_transport_xmod (stdout 23 bytes, rc 0)
run_fixtures: --capture mode (goldens written; review before committing)
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
RC=0
$ cat repro/mi_matrix/stdlib_wg_transport_xmod/expected.txt
wireguard transport ok
$ cat repro/mi_matrix/stdlib_wg_transport_xmod/expected.rc
0
```

## 6. Crosscheck

Extended `repro/mi_matrix/stdlib_wireguard_cross_xmod/main.zig` with `t` and
`c` crosscheck modes; vectors are compared three ways (Z98 == ref ==
committed `.expected`).

```text
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean std_wireguard
PASS std_wireguard (3 vectors)
----------------------------------------
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
RC=0
```

## 7. Targeted 3×

```text
$ for i in 1 2 3; do
    bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      repro/mi_matrix/stdlib_wg_handshake_xmod \
      repro/mi_matrix/stdlib_wg_transport_xmod \
      repro/mi_matrix/stdlib_wireguard_cross_xmod
  done
PASS repro/mi_matrix/stdlib_wg_handshake_xmod
PASS repro/mi_matrix/stdlib_wg_transport_xmod
PASS repro/mi_matrix/stdlib_wireguard_cross_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
run1 rc=0
... identical run2 rc=0 / run3 rc=0 ...

$ for i in 1 2 3; do
    bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean std_wireguard
  done
PASS std_wireguard (3 vectors)
cross1 rc=0
cross2 rc=0
cross3 rc=0
```

## 8. `-osw` gate

```text
$ /tmp/m2_t4_v114_build/zig1_5_clean -osw -ffast -o /tmp/wg_osw \
    repro/mi_matrix/stdlib_wg_transport_xmod/main.zig
OSW_DUMP_RC=0
error_brk=0  PANIC=0  emitted_c=11
$ cd /tmp/wg_osw && sh build_target.sh mingw /tmp/wg_osw/prog.exe
MINGW_BUILD_RC=0
$ cd /tmp && timeout 120 wine /tmp/wg_osw/prog.exe
wireguard transport ok
WINE_RC=0
```

## 9. Files changed

- `sf/src/std_wireguard.zig`
- `repro/mi_matrix/stdlib_wg_transport_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_wireguard_cross_xmod/main.zig`
- `scripts/stdlib/ref/std_wireguard/ref.c`
- `scripts/stdlib/vectors/std_wireguard/{transport,cookie}.{in,expected}`
- `scripts/stdlib/expected_dirs.txt`

Note: `.gitignore` line 60 (`tr*`) matches `transport.in`/`transport.expected`;
they must be force-added (`git add -f`) to be committed. No ignore rules were
changed.

## 10. Concerns

- Jitter is a deterministic bounded per-attempt value (0..333 ms) rather than
  RNG-derived, so timer tests are reproducible; the 5 s base is exact.
- Cookie expiry (`COOKIE_SECRET_MAX_AGE`) is not enforced because
  `wgCreateInitiation` has no `now_ms` parameter; consumed cookies remain
  usable until replaced. CookieReply generation remains out of scope.
- Initiator-only: received handshake initiation (type 1) returns `Corrupt`;
  transport/cookie/response paths are implemented.
- A real re-initiation while a handshake is pending chooses a fresh unique
  index (T1 rule); the cookie fixture abandons the old pending handshake first
  so it stays byte-exact against the ref capture.

## 11. Fix round — rekey continuity (base `a4c06008`)

Operator ruling: option 1, dual current/pending session state. Fixes in
`sf/src/std_wireguard.zig`:

- Added `pending_local_index`; `hs_valid`/`hs_initiator` plus pending
  ephemeral/hash/chaining key/mac1 now describe an in-flight initiation.
- `wgCreateInitiation` writes only pending state. It no longer changes active
  `local_index`, `remote_index`, `tx_key`, `rx_key`, `sending_counter`, or the
  replay window.
- `nextIndex` avoids both the active local index and the pending index.
- `wgSend` continues to use the active session while a rekey is pending.
- `wgReceive` matches type 2/CookieReply by `pending_local_index`; type 4
  transport still matches the active `local_index`.
- `wgProcessResponse` verifies the pending receiver index, derives into
  locals, then installs pending local/remote indices and tx/rx keys
  atomically, clears pending, resets `sending_counter`, and clears replay.
- Removed duplicate `WG_AUTHTAG_LEN`; updated the stale top-of-file comment.

Fixture addition (`stdlib_wg_transport_xmod`, rekey continuity):
- At 120 s `wgTick` returns `send_handshake` with a deterministic pending
  initiation (ref seed `1229782938247303444`, same wall time).
- Active local/remote indices, tx/rx keys, and `sending_counter` stay
  unchanged after the pending initiation.
- `wgSend` still emits the expected active-session packet (old key, old remote
  index, counter 7) and advances only the active counter.
- An old inbound transport (old rx key, old receiver index, counter 11) is
  accepted while rekey is pending.
- The canned response returns `session_up` and installs the pending local
  index, responder index, new tx/rx keys; counter/replay reset.
- Subsequent send is byte-exact under the new tx key/index/counter 0, and a
  transport under the new rx key/index is accepted.

Observed:

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_wg_handshake_xmod \
    repro/mi_matrix/stdlib_wg_transport_xmod \
    repro/mi_matrix/stdlib_wireguard_cross_xmod
PASS repro/mi_matrix/stdlib_wg_handshake_xmod
PASS repro/mi_matrix/stdlib_wg_transport_xmod
PASS repro/mi_matrix/stdlib_wireguard_cross_xmod
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
RC=0
```

3× fixture and crosscheck:

```text
run1 rc=0 / run2 rc=0 / run3 rc=0
cross1 rc=0 / cross2 rc=0 / cross3 rc=0
PASS std_wireguard (3 vectors)
```

`-osw`:

```text
OSW_DUMP_RC=0
ERR_BRK=0  PANIC=0  C_FILES=11
MINGW_BUILD_RC=0
wireguard transport ok
WINE_RC=0
```

Fix-round concern: the rekey fixture seed is written as decimal
`1229782938247303444`, not its hex form, because the current compiler
mis-handles that >2^60 `u64` hex literal (captured initiation diverged from
the ref until the seed was decimal). No compiler fix was attempted here.

No ref/vector changes were needed for the rekey test; `transport.in`/`.expected`
and `cookie.in`/`.expected` are unchanged.
