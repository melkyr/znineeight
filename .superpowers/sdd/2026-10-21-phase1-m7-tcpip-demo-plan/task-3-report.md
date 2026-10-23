# M7 Task 3 report — `wireguard_demo` + `tier_wireguard.sh`

Status: COMPLETE — tier 2× green (5/5 cases each), demo targeted checks green

## Environment

- Repo: `/workspace/znineeight`
- Base: `5ec5cb71` (M7 T2 complete ledger)
- Seed compiler: `/tmp/m6_t3_v118_rotated/zig1_5_clean`
- Portable tier tools: `/tmp/m7_tools` (`ip`, `wg`, `libbpf`/`libmnl`); the tier
  also falls back to host `ip`/`wg`, then a no-root `.deb` extraction.
- Far side: Linux kernel WireGuard in `unshare -Urn` + repo `mud_server` +
  tunnel A-record DNS responder.
- Tier path: `examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh`

## Step 1 — demo implementation

Created exactly:

- `examples/z98/demo/wireguard_demo/main.zig`
- `examples/z98/demo/wireguard_demo/wg.conf.example`
- `examples/z98/demo/wireguard_demo/README.md`
- `examples/z98/demo/wireguard_demo/NOTES.md`
- `examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh`

### Contract coverage

- Config-driven (`private_key`, `peer_public_key`, `endpoint`, `address`,
  optional `dns_server`, `mtu` default 1400, `clock_override_unix`, plus
  `mud_host`/`mud_ip`, `mud_port`, `allowed_ips`, `gateway`, `seed`,
  `command`). Unknown keys -> `wg: BadConfig`. Keys accept hex or base64.
- After `wgInit`, `dev.rng = std_rand.xoshiroInit(seed)` from config or
  `std_time.highRes`/wall/local data.
- Explicit monotonic `now_ms` (highRes/highResFreq) and wall
  `wall_unix_ns = clock_unix * 1e9`; the wire timestamp is never derived from
  `now_ms`.
- DNS is pumped exactly as required: `dnsResolve` -> pending
  `error.Timeout` -> `tcpipPoll` until `.done` -> final `dnsResolve` for the A
  record or `DnsFailed`. Direct IPv4/`mud_ip` configs skip DNS.
- NoiseIK handshake completes before any inner packet is passed (`wgSend`
  `NoSession` discipline); UDP receive feeds `wgReceive`; `inner_packet` bytes
  feed `tcpipPoll`; `send_pkt` bytes feed `wgSend`.
- Connects to the MUD tunnel IP port 4000, prints the banner line, sends one
  `look` command, prints the reply line, then the exact line
  `wireguard_demo ok bytes=N arena_peak=N rss_peak=N cpu_ms=N`.
- Precise failures: `wg: <Reason>` for config/tunnel, `tcp: <Reason>` for
  stack/DNS/TCP. README lists the complete set.
- No heap; fixed static driver/config/rx/tx buffers and a 512 KiB
  `std_arena` for the `std_tcpip` stack.

Two Z98-era issues found and fixed during bring-up (recorded in NOTES):

1. The base64 accumulator must be masked (24 bits); an unmasked `u32`
   accumulator corrupted keys and surfaced as `wg: InvalidPeer`.
2. Nested writes via `g_peers[0].field[0..]` could target a by-value temporary
   in the old emitter; the demo writes through `*wg.WgPeer`.

Also fixed a driver bug: `tcpipPoll` output and `wgSend` output must be
distinct buffers; aliasing corrupted the inner packet and produced a
handshake-only session with DNS failure.

## Step 2 — tier

`tests/tier_wireguard.sh`:

- Prefers the portable `/tmp/m7_tools` `ip`/`wg` (env `M7_TOOLS`), then host
  tools, then extracts the portable `.deb` set into `OUT` without root.
- Verifies `unshare -Urn` and kernel WireGuard interface creation; otherwise
  prints a loud `SKIP - ...` + `TIER_WIREGUARD SKIP` (verified separately).
- Builds `mud_server`, the Linux `-fsafe` demo, and the `-osw` demo.
- Runs `check_win9x_imports.sh 9x` (KERNEL32 + WSOCK32 only).
- Creates a netns kernel `wg0` via `ip link add wg0 type wireguard` +
  `wg setconf` (portable `ip`/`wg`; `wg-quick` not required), address
  `10.7.0.1/24`, starts `mud_server` and a tunnel DNS responder on
  `10.7.0.1:53`.
- Cases: Linux DNS (exact CRLF banner + reply + resource line), Linux DNS
  again (deterministic banner/reply), Wine `-osw` against the same far side,
  Linux direct-IP (no DNS), Linux under `ulimit -v 32768` with
  `/usr/bin/time -v` peak RSS.
- Each case uses a distinct client tunnel IP and a distinct
  `clock_override_unix` (same kernel peer across runs; TAI64N replay
  protection). The server peer allows `10.7.0.0/24`.

## Step 3 — gates run

`tier_wireguard.sh` run 1:

```
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
```

`tier_wireguard.sh` run 2 (deterministic):

```
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
```

Observed cases (both runs green):

```
linux DNS run: exact banner + look reply + resource line
  bytes=100 arena_peak=275192 rss_peak=2608 cpu_ms=70   (run 1)
linux banner/reply identical 2x
wine -osw run: exact banner + look reply + resource line
  bytes=100 arena_peak=275192 rss_peak=6784 cpu_ms=440
linux direct-IP run: exact banner + look reply + resource line
RAM ceiling ok: peak RSS=2312 kB (ulimit -v 32768)      (run 1)
  peak_rss_kb=2472                                       (run 2)
check_win9x_imports.sh 9x whitelist PASS
  DLL KERNEL32.DLL
  DLL WSOCK32.DLL
```

Targeted demo checks (3×):

```
run1 rc=1 out=wg: ConfigRead
run2 rc=1 out=wg: ConfigRead
run3 rc=1 out=wg: ConfigRead
```

Loud-SKIP check (`M7_TOOLS=/nonexistent`, no host `ip`/`wg`):

```
SKIP - no usable kernel-WireGuard tools: portable ip/wg, host ip/wg, and .deb extraction all unavailable
SKIP - M7 integration pending (kernel WireGuard far side not exercised)
TIER_WIREGUARD SKIP
```

Within the two tier runs the Linux demo itself executed 3 times per invocation
(DNS ×2, direct ×1) plus the RAM and Wine runs, so the network happy path is
well past 3×.

## Scope

No changes to `sf/src`, seed, compiler, `std.zig`, or unrelated files. Full
stdlib gate and seed rotation remain Task 4 closeout per brief.

## Concerns

- DNS is A/IN only; CNAME chains are `DnsFailed` by the `std_tcpip` contract.
- The demo exits after the reply without a graceful userspace FIN; repeated
  manual runs against the same kernel peer should use a distinct client tunnel
  IP or wait for far-side state cleanup. The tier isolates runs by client IP.
- Reusing one kernel peer requires an increasing `clock_override_unix`;
  otherwise WireGuard replay protection rejects the handshake.
- The tier uses manual `ip`/`wg` on a kernel interface rather than `wg-quick`.
  The amended plan/spec (`26219b62`) now explicitly allow the portable
  `ip`/`wg` netns equivalent, so this is no longer a deviation; the pair also
  avoids `wg-quick`'s host-config/resolvconf dependencies.

## Commits

- `65c20b1c` `example(z9demo): wireguard_demo (Phase1 M7)`
- `18fb5a10` `test(tier): tier_wireguard (Phase1 M7)`
- `ec9e8772` `docs(sdd): M7 T3 report`

## Fix round — config error prefix + tier byte pin

Base: `ec9e8772`; plan amendment: `26219b62` (portable kernel-WireGuard tools
explicitly allowed).

- **`fail()` routing.** `DemoError.BadConfig` previously fell through to the
  `tcp:` fallback because only the default name was `BadConfig`; the prefix was
  still set to `tcp: `. Added an explicit `wg:` branch. Unknown key, missing
  required key, and malformed value now print `wg: BadConfig`; malformed key
  material stays `wg: BadKey`.
- **Targeted config checks.** The tier now runs four pre-netns config cases:
  unknown key -> `wg: BadConfig`, missing required key -> `wg: BadConfig`,
  invalid key -> `wg: BadKey`, malformed value (`mtu = not-a-number`) ->
  `wg: BadConfig`. Each asserts nonzero exit and exact output.
- **Tier byte pin.** `check_output` now extracts `bytes=N` and requires it to
  equal the exact expected banner+reply byte count (currently 100), instead of
  accepting any numeric value.

Targeted checks before the full tier (3× each):

```
run1 unknown rc=1 out=wg: BadConfig
run1 missing rc=1 out=wg: BadConfig
run1 badkey  rc=1 out=wg: BadKey
run1 badvalue rc=1 out=wg: BadConfig
run2 unknown rc=1 out=wg: BadConfig
run2 missing rc=1 out=wg: BadConfig
run2 badkey  rc=1 out=wg: BadKey
run2 badvalue rc=1 out=wg: BadConfig
run3 unknown rc=1 out=wg: BadConfig
run3 missing rc=1 out=wg: BadConfig
run3 badkey  rc=1 out=wg: BadKey
run3 badvalue rc=1 out=wg: BadConfig
```

Tier 2× after the fix (both green; config cases + inner integration):

```
run 1:
ok   - config unknown -> wg: BadConfig
ok   - config missing_required -> wg: BadConfig
ok   - config bad_key -> wg: BadKey
ok   - config malformed_value -> wg: BadConfig
ok   - linux DNS run: exact banner + look reply + resource line
       wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=2576 cpu_ms=70
ok   - linux banner/reply identical 2x
ok   - wine -osw run: exact banner + look reply + resource line
       wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=6740 cpu_ms=450
ok   - linux direct-IP run
ok   - RAM ceiling ok: peak RSS=2172 kB (ulimit -v 32768)
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS

run 2:
ok   - config unknown -> wg: BadConfig
ok   - config missing_required -> wg: BadConfig
ok   - config bad_key -> wg: BadKey
ok   - config malformed_value -> wg: BadConfig
ok   - linux DNS run: exact banner + look reply + resource line
       wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=2500 cpu_ms=70
ok   - linux banner/reply identical 2x
ok   - wine -osw run: exact banner + look reply + resource line
       wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=6784 cpu_ms=450
ok   - linux direct-IP run
ok   - RAM ceiling ok: peak RSS=2196 kB (ulimit -v 32768)
== tier_wireguard summary: 5 passed, 0 failed, 0 skipped ==
TIER_WIREGUARD PASS
```

The resource byte pin uses the exact `expected.txt` length (100 bytes for the
CRLF banner + reply); every case's `bytes=N` must equal it.
