# M6 Task 1 report — NoiseIK initiator + handshake state

Status: complete (Task 1 only). Transport/timers/cookies/replay, docs, tier,
seed rotation, and the full stdlib gate are deferred to Tasks 2–3.

## 1. Environment / base

- Repo root `/workspace/znineeight`; branch `zig1_improvements`; base
  `94c86a6d798f989ab45deeee134236343d1f0240`.
- Compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  (`md5sum` = `45158dcede81125a39a2c2c58478e21e`).
- Only `sf/src/std_wireguard.zig` was synced into the compiler's sibling
  `lib/` for testing (seed not rotated).
- `run.err` remains untracked/untouched.

## 2. Vendored reference and capture

Created `scripts/stdlib/ref/std_wireguard/`:

- `ref.c` — initiator initiation + a responder half used only to produce the
  canned response. BSD-3-Clause attribution to wireguard-lwip / Daniel Hope.
- `crypto/refc/*` — vendored BLAKE2s, ChaCha20, Poly1305, X25519, with
  `x25519-license.txt`; `crypto.h`.
- Vendored `//` comments and `static inline` spelling were adapted to strict
  C89 (no algorithmic changes). This was required because
  `run_crosscheck.sh` builds every `ref.c` with `-std=c89`.

Reference build (strict C89, m32):

```text
$ cd scripts/stdlib/ref/std_wireguard
$ gcc -m32 -std=c89 -O0 ref.c -o /tmp/wg_ref_c89
$ echo $?
0
```

Capture (fixed RFC 7748 Alice/Bob statics, initiator seed
`0x0123456789ABCDEF`, responder seed `0x0F1E2D3C4B5A6978`, wall
`1800000000123456789`):

```text
$ /tmp/wg_ref_c89 --vectors
initiator_static_pub 8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a
responder_static_pub de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f
initiation 01000000cf5492ac5ac39f7a9b74c617f2c191c2a9504e5dc0a0bb51edc1ab756de2a6883fdfa65f7c5c9820bad0f86cba59b3911b5251e0e5522aca30e7633ee3b54990f58d8082555f1fffa1c98a828bb2da07059593e3274039d419c4fdd4364ee749bb2bc2e3f21c67eb0e1420f9de88c10f3466ac286f3266335dacfe24859fd4c100000000000000000000000000000000
timestamp 400000006b49d20a075bcd15
response 02000000d4c3b2a1cf5492aca2627451101c3cf13a244ee3403409481612fc8d37b2e6b222e8c1769e7cb478bb058395ece9b7d32e6193f14352ecc584de82e50375993a68284568f45c25a000000000000000000000000000000000
tx_key 1e30248f17e1a28a0eaaf896edf32830d0167347942393c15018c9585912bca6
rx_key b5eba4b4c280d30d0033299eda36840bc75e96dcfb842ed0e4f49cd3b6baa370
```

Crosscheck vectors deliberately vary seed and wall time:

```text
$ cat scripts/stdlib/vectors/std_wireguard/handshake.in
1 1800000000000000000
123 1800000000123456789
$ /tmp/wg_ref_c89 --crosscheck < scripts/stdlib/vectors/std_wireguard/handshake.in
010000007336239ac9442613efacd34b010982289bbf791b81c4e8f8aa12838e5a8bd3b74f69bd539774ee6ac510bc20a145b2edb52d6473ff2bf47e8b91eb43787fe31dd8bd802a47b81943e8cc198fe46a7911352ded3bea42e835f57bcca6486886d3943e2cbc2be0d95c686e3d28c00c9933e9bdd1df0660b678f89bf16342227a9400000000000000000000000000000000
01000000de789d951b0dcef5239da5944c045255f0940c67d59dc82f66b351c737acf5e73fefd26ec2a4f7d1bdcf02ff158679233987d26c7ad31af6b252265a0ab1ad8f4aa416217226f7f09122a0fceb705d65c5fa904de1383141a6475ef053fc5a89c7def751a054fc0883d2f9abee35f6e82232609362f44cfda17b7c15bf0f172e00000000000000000000000000000000
```

The same output is committed as
`scripts/stdlib/vectors/std_wireguard/handshake.expected`.

## 3. Failing fixture first

Created `repro/mi_matrix/stdlib_wg_handshake_xmod/main.zig` and pinned it in
`scripts/stdlib/expected_dirs.txt` before writing the module. Missing golden:

```text
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_wg_handshake_xmod
FAIL repro/mi_matrix/stdlib_wg_handshake_xmod (MISSING-GOLDEN)
----------------------------------------
run_fixtures: 0 PASS / 1 FAIL over 1 dirs
failed: repro/mi_matrix/stdlib_wg_handshake_xmod
RC=1
```

## 4. Implementation (`sf/src/std_wireguard.zig`)

- Spec §5.7 shapes: `WgPeer`, `WgDevice`, `wgInit`, `wgAddPeer`.
- Initiator handshake: `wgCreateInitiation(dev, peer, wall_unix_ns, out)`,
  `wgProcessResponse(dev, peer, msg)`, `wgTai64n(wall_unix_ns, out)`.
- NoiseIK construction/identifier hashes; WireGuard KDF1/2/3 with
  **HMAC-BLAKE2s** (not the keyed-BLAKE2s `hmacBlake2s` helper, whose name is
  misleading for this construction); mac1/mac2 use keyed BLAKE2s-128.
- ChaCha20-Poly1305 nonce 0 handshake AEAD; encrypted static (48 B), encrypted
  TAI64N (28 B); `mac2` zero until a cookie is stored.
- Ephemeral private key and 32-bit sender index come from `dev.rng`
  (`rand.Xoshiro256`, seeded explicitly by the caller). Unique-index rejection
  skips 0/0xFFFFFFFF and in-use handshake indices.
- TAI64N is `0x400000000000000a + wall_unix_ns/1e9`, then `wall_unix_ns%1e9`
  big-endian. No `now_ms` input exists on the handshake path.
- Response processing verifies type/length, receiver index, mac1, optional
  mac2, two ephemeral DHs + static DH, KDF3 with the peer PSK, empty AEAD tag,
  then KDF2 to `tx_key`/`rx_key` and marks the session valid.
- Wire integers use explicit little-endian `load32le`/`store32le`.
- Errors used: `Corrupt`, `AuthenticationFailed`, `NoSession`,
  `OutputTooSmall`, plus `NoSpace`/`InvalidPeer` for table/key validation.

## 5. Fixture vectors and negatives

`stdlib_wg_handshake_xmod` pins:

- initiator seed → byte-exact 148-byte initiation (through mac1; mac2 zero)
- `wgTai64n` bytes `400000006b49d20a075bcd15` from `wall_unix_ns`; a later wall
  value changes the timestamp
- canned 92-byte response → exact `tx_key`/`rx_key`, response sender index,
  `session_valid`
- wrong static key (mutate `iface_priv` after initiation) →
  `AuthenticationFailed`
- truncated response (91 bytes) → `Corrupt`
- mac1 bit flip → `Corrupt`

Green result:

```text
$ bash scripts/stdlib/run_fixtures.sh --capture \
    /tmp/m2_t4_v114_build/zig1_5_clean \
    repro/mi_matrix/stdlib_wg_handshake_xmod
CAPTURED repro/mi_matrix/stdlib_wg_handshake_xmod (stdout 23 bytes, rc 0)
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
$ cat repro/mi_matrix/stdlib_wg_handshake_xmod/expected.txt
wireguard handshake ok
$ cat repro/mi_matrix/stdlib_wg_handshake_xmod/expected.rc
0
```

Z98 initiation bytes were compared against the C reference byte-for-byte
during development (`diff` of initiation/tx/rx lines: MATCH).

## 6. Crosscheck assets

Because `scripts/stdlib/ref/std_wireguard/` is discovered by
`run_crosscheck.sh`, the matching driver/vectors were added so the full
crosscheck cannot fail with `MISSING-VECTORS`:

- `repro/mi_matrix/stdlib_wireguard_cross_xmod/main.zig` (default
  `wireguard cross ok`; `--crosscheck` emits initiation hex),
- `scripts/stdlib/vectors/std_wireguard/{handshake.in,handshake.expected}`,
- both fixture dirs pinned in `scripts/stdlib/expected_dirs.txt`.

Observed:

```text
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean \
    std_wireguard
PASS std_wireguard (1 vectors)
----------------------------------------
run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

Full crosscheck discovery (no unrelated module changed, but the new ref dir
must not break the gate):

```text
$ bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_wireguard (1 vectors)
PASS std_zstd (30 vectors)
----------------------------------------
run_crosscheck: 10 PASS / 0 FAIL over 10 modules
```

## 7. Targeted 3×

```text
$ for i in 1 2 3; do
    bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      repro/mi_matrix/stdlib_wg_handshake_xmod \
      repro/mi_matrix/stdlib_wireguard_cross_xmod
  done
run1 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs
run2 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs
run3 rc=0 run_fixtures: 2 PASS / 0 FAIL over 2 dirs

$ for i in 1 2 3; do
    bash scripts/stdlib/run_crosscheck.sh /tmp/m2_t4_v114_build/zig1_5_clean \
      std_wireguard
  done
cross1 rc=0 run_crosscheck: 1 PASS / 0 FAIL over 1 modules
cross2 rc=0 run_crosscheck: 1 PASS / 0 FAIL over 1 modules
cross3 rc=0 run_crosscheck: 1 PASS / 0 FAIL over 1 modules
```

## 8. Files changed

- `sf/src/std_wireguard.zig` (new)
- `repro/mi_matrix/stdlib_wg_handshake_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_wireguard_cross_xmod/{main.zig,expected.txt,expected.rc}`
- `scripts/stdlib/ref/std_wireguard/{ref.c,crypto.h,crypto/refc/*}`
- `scripts/stdlib/vectors/std_wireguard/{handshake.in,handshake.expected}`
- `scripts/stdlib/expected_dirs.txt` (two pins)

Not touched: `progress.md`, `run.err`, seed, docs, tiers.

## 9. Concerns

- `WgPeer.static_priv` is retained for the spec §5.7 API shape but the
  handshake uses `WgDevice.iface_priv` (single interface static key), matching
  wireguard-lwip. Task 2 may decide whether to drop or repurpose it.
- The vendored crypto files differ from upstream only in C89 comment/inline
  spelling; strict-C89 crosscheck build was verified byte-identical to the
  gnu89 capture build.
- Full `verify_stdlib.sh` (all fixtures) was intentionally not run in Task 1;
  Task 3 closeout owns the full gate.
