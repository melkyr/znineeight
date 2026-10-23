# wireguard_demo — implementation notes (Phase 1 M7 Task 3)

## Scope

Userspace WireGuard initiator + client-only IPv4/TCP/UDP/DNS/ICMP stack +
one MUD exchange through a real Linux kernel WireGuard far side. The demo owns
no TUN/TAP device and opens exactly one UDP socket; the inner datagrams are the
bytes produced/consumed by `tcpipPoll`.

Files:

- `main.zig` — config parser, NoiseIK driver, UDP pump, DNS/TCP client, output.
- `wg.conf.example` — canonical config keys.
- `tests/tier_wireguard.sh` — netns kernel-WireGuard tier (Linux + Wine + RAM +
  import gate + DNS/direct paths).

## Driver notes

- **RNG reseed after `wgInit`.** `wgInit` zeroes `dev.rng`; the demo reseeds it
  with `std_rand.xoshiroInit(seed)` from `seed` in the config, or from
  `std_time.highRes`/wall/local address/port when absent.
- **Two time bases.** `now_ms` is monotonic (`highRes / highResFreq`) for
  timers. `wall_unix_ns` is wall-clock seconds × 1e9 for TAI64N. The demo never
  derives one from the other.
- **DNS is a pump.** `dnsResolve` starts a request and returns `error.Timeout`;
  the driver polls `tcpipPoll` until `.done`, then calls `dnsResolve` again for
  the address or `DnsFailed`. It does not block waiting for a "DNS complete"
  event. Direct IPv4/`mud_ip` configs skip DNS entirely.
- **Buffer separation.** `tcpipPoll` writes the inner packet into `pkt_buf`;
  `wgSend` writes ciphertext into `wg_out`. Using the same buffer for both
  corrupts the plaintext before encryption (observed during bring-up as a
  handshake-only, no-transport session).
- **Receive path.** UDP payload -> `wg_in`; `wgReceive` writes plaintext ->
  `wg_out`; the `inner_packet` length is copied to `rx_buf` and passed to the
  next `tcpipPoll`. Handshake responses and transport packets share the same
  loop.
- **Config parser.** Fixed 8 KiB read via `std.io.fileOpen/fileRead` (works on
  Win9x), no allocation, unknown keys fail `wg: BadConfig`. Keys accept hex or
  base64; the base64 accumulator is masked to 24 bits (an unmasked `u32`
  accumulator loses high bits after several sextets).
- **Z98 codegen workaround.** `g_peers[0].field[0..]` in the old emitter can
  materialise a by-value temporary, so writes were lost. The demo takes
  `var pp: *wg.WgPeer = &g_peers[0]` and writes through the pointer.

## Tier notes

- The far side runs in `unshare -Urn`: `ip link add wg0 type wireguard`,
  `wg setconf`, address `10.7.0.1/24`, then `mud_server` (0.0.0.0:4000) and a
  tiny Python A-record DNS responder on `10.7.0.1:53`. The demo runs in the
  same namespace and sends WireGuard UDP to `127.0.0.1:51820`; the server peer
  learns the client endpoint from the authenticated initiation.
- The server peer allows the whole `10.7.0.0/24`. Each case uses a distinct
  client tunnel IP (`.2`, `.3`, ...). This avoids stale far-side TCP state from
  a previous process that exited without a userspace FIN (the demo's TCP stack
  has no kernel socket to close on process exit).
- Each case uses a distinct `clock_override_unix` because the same kernel peer
  applies TAI64N replay protection across runs.
- Portable `/tmp/m7_tools` `ip`/`wg` are preferred; host tools are next; the
  tier will attempt a no-root `.deb` extraction into `OUT` before skipping.
  Missing kernel WireGuard/netns/tools produce a loud `SKIP`, never a pass.
- Wine runs against the same far side with a fresh `WINEPREFIX` in `OUT`. The
  Windows resource line reads host `/proc` through Wine on this host, so
  `rss_peak`/`cpu_ms` are nonzero; the tier only requires numeric fields.

## Observed M7 host results

Two consecutive `tier_wireguard.sh` invocations: `5 passed, 0 failed, 0
skipped` each.

- Linux DNS run: `bytes=100 arena_peak=275192 rss_peak≈2600 cpu_ms≈70`.
- Wine -osw run: same bytes/arena, `rss_peak≈6800 cpu_ms≈440`.
- RAM run under `ulimit -v 32768`: peak RSS 2312–2472 KiB.
- Import gate: `KERNEL32.DLL`, `WSOCK32.DLL` only.
- Direct-IP run: green (no `dns_server` in config).
- Banner/reply byte-identical across the two Linux runs and Wine.

## Deferred / concerns

- DNS is A/IN only; CNAME chains fail `DnsFailed` (std_tcpip contract).
- The demo exits after the reply without a graceful FIN; the tier isolates runs
  with distinct client IPs. A manual user reconnecting from the same source
  port/IP to a non-reset far side may need a short wait.
- Full stdlib gate and seed rotation are Task 4 (closeout), not this task.
