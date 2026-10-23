# wireguard_demo — userspace TCP/IP through a real WireGuard tunnel (Phase 1 M7)

`wireguard_demo` is a Z98 program that acts as a WireGuard initiator with
`std_wireguard`, runs a client-only IPv4/TCP/UDP/DNS/ICMP stack with
`std_tcpip`, and opens a TCP session to the repository's `mud_server` **through
the tunnel**. The far side is a Linux **kernel** WireGuard interface; the only
transport socket the demo owns is a `std_net` UDP socket carrying WireGuard
datagrams.

It prints the MUD banner, sends exactly one command line (`look` by default),
prints the reply, and exits with the resource line:

```
wireguard_demo ok bytes=N arena_peak=N rss_peak=N cpu_ms=N
```

## Usage

```
wireguard_demo [wg.conf] [clock_override_unix]
```

- `wg.conf` — default `wg.conf` in the current directory.
- `clock_override_unix` — optional Unix seconds; overrides
  `clock_override_unix` from the config. Use it on a dead-RTC Win9x machine.
  The wall clock feeds the WireGuard TAI64N timestamp; it is never derived from
  monotonic `now_ms`.

`clock_override_unix` matters when reusing one kernel peer across several
runs: WireGuard rejects a non-increasing TAI64N timestamp. The tier passes a
distinct second per invocation.

## `wg.conf`

`key = value` lines; `#`/`;` comments. See
[`wg.conf.example`](wg.conf.example). Keys accept 64 hex characters or
standard base64 (padding optional).

| key | required | meaning |
|---|---|---|
| `private_key` | yes | client interface private key |
| `peer_public_key` | yes | kernel far-side public key |
| `endpoint` | yes | underlay `host:port` (resolved by the host at startup) |
| `address` | yes | local tunnel IPv4 `a.b.c.d[/prefix]` (default `/24`) |
| `gateway` | no | logical gateway for off-subnet targets (default `0`) |
| `dns_server` | no | tunnel DNS server IPv4; enables the DNS target path |
| `mud_host` | yes* | mud target IPv4 literal (direct) or DNS name |
| `mud_ip` | no | force a direct IPv4 target, skipping DNS |
| `mud_port` | no | mud TCP port (default `4000`) |
| `allowed_ips` | no | comma-separated CIDRs copied to `WgPeer` (max 8) |
| `mtu` | no | inner IPv4 MTU incl. headers (default `1400`) |
| `clock_override_unix` | no | wall-clock seconds for dead-RTC machines |
| `seed` | no | deterministic `std_rand.xoshiroInit` seed |
| `command` | no | one command line (default `look`) |

\* One of `mud_host`/`mud_ip` is required by the demo. A non-literal
`mud_host` requires `dns_server`; IPv4 literals and `mud_ip` skip DNS.

Aliases such as `tunnel_ip`, `server_host`, `server_ip`, `server_port`,
`public_key`, and hyphenated spellings are accepted. Unknown keys fail as
`wg: BadConfig`.

## Flow

1. Read `wg.conf`; initialise the arena-backed `std_tcpip` stack
   (`cfg.mtu`, `cfg.dns_server`, local address/prefix).
2. `wgInit`, then **reseed** `dev.rng = std_rand.xoshiroInit(seed)` — `wgInit`
   zeroes the RNG. `seed` is config-supplied or derived from `std_time.highRes`
   and the wall clock.
3. `wgTick` sends the NoiseIK initiation; incoming UDP is fed to `wgReceive`
   until `session_up`. All wire timestamps use `wall_unix_ns = sec * 1e9`.
4. Resolve the mud target. A name is resolved with the pump-driven DNS helper:
   call `dnsResolve` (pending -> `error.Timeout`), poll `tcpipPoll` until
   `.done`, then call `dnsResolve` again for the A record or `DnsFailed`.
   Direct-IP configs skip this step.
5. `tcpConnect` to the mud tunnel IP on port 4000. Inner IPv4 datagrams from
   `tcpipPoll.send_pkt` are encrypted by `wgSend`; decrypted `inner_packet`
   bytes from `wgReceive` are fed back to `tcpipPoll`.
6. Print the banner line, send one command, print the reply line, print the
   resource line, exit `0`.

## Failure text

Failures exit non-zero with one precise line:

```
wg: BadArgs
wg: BadConfig
wg: ConfigRead
wg: BadKey
wg: BadClock
wg: BadIp
wg: SocketFailed
wg: Corrupt
wg: AuthenticationFailed
wg: NoSession
wg: SessionExpired
wg: OutputTooSmall
wg: Timeout
wg: NoSpace
wg: InvalidPeer
tcp: DnsFailed
tcp: NoRoute
tcp: ConnRefused
tcp: Timeout
tcp: Closed
tcp: Corrupt
tcp: Failed
tcp: OutOfMemory
tcp: OutputTooSmall
```

`wg: ...` covers config and the WireGuard tunnel; `tcp: ...` covers the inner
stack, DNS, and the MUD session.

## Build and run (Linux)

From the repository root with a seed-built compiler whose sibling `lib/`
contains `std_tcpip.zig` and `std_wireguard.zig`:

```bash
mkdir -p /tmp/wireguard_demo
/path/to/zig1_5_clean -fsafe -o /tmp/wireguard_demo \
  examples/z98/demo/wireguard_demo/main.zig
sh /tmp/wireguard_demo/build_target.sh linux /tmp/wireguard_demo/wireguard_demo

/tmp/wireguard_demo/wireguard_demo /path/to/wg.conf
```

The demo needs no privileged TUN/TAP device: it is a userspace IP stack over
one ordinary UDP socket. The *far side* is privileged kernel WireGuard (or a
test netns).

## Build and run (Win9x, `-osw`)

```bash
mkdir -p /tmp/wireguard_demo_win
/path/to/zig1_5_clean -fsafe -osw -o /tmp/wireguard_demo_win \
  examples/z98/demo/wireguard_demo/main.zig
sh /tmp/wireguard_demo_win/build_target.sh mingw \
  /tmp/wireguard_demo_win/wireguard_demo.exe
```

Copy `wireguard_demo.exe` and a `wg.conf` to the Win9x machine. The executable
imports only `KERNEL32.DLL` and `WSOCK32.DLL` (no CRT/msvcrt) and passes
`scripts/win32_cross/check_win9x_imports.sh 9x`. Win95 needs the Winsock 2
update installed (Win98/ME ship it). The box only needs its normal TCP/IP
stack plus UDP connectivity to the WireGuard endpoint; no TUN driver is
required.

## Far side (kernel WireGuard + mud_server)

Manual `wg-quick` recipe on a Linux host or VM:

```ini
# /etc/wireguard/wg0.conf
[Interface]
PrivateKey = <server-private-key>
Address = 10.7.0.1/24
ListenPort = 51820
MTU = 1400

[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.7.0.2/32
```

```bash
wg-quick up wg0
# build/run examples/z98/mud_server (listens on 0.0.0.0:4000)
./mud_server
```

The demo's `endpoint` is the host's UDP address; `mud_host`/`mud_ip` is the
tunnel address of the machine running `mud_server` (normally `10.7.0.1`). If
you serve DNS on the tunnel, point `dns_server` at it and use a name for
`mud_host`. The tier uses a netns-local kernel interface (`ip link add wg0
type wireguard`, `wg setconf`) so it needs no root install and no host
network changes.

## Tests

```bash
bash examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh
```

The tier creates `unshare -Urn` kernel WireGuard (`wg`/`ip` portable tools
preferred), starts `mud_server` and a tunnel A-record DNS responder, then runs:

- Linux DNS path (exact banner + `look` reply + resource line);
- the same Linux case again (deterministic banner/reply, resource line
  ignored);
- the `-osw` Wine build against the same far side;
- a Linux direct-IP config that skips DNS;
- a Linux run under `ulimit -v 32768` with `/usr/bin/time -v` peak RSS;
- `check_win9x_imports.sh 9x`.

It repeats the tier twice for determinism. If kernel WireGuard/netns or the
portable tools are unavailable it prints a loud `SKIP - ...` and
`TIER_WIREGUARD SKIP` (never a vacuous pass). `wg-quick` is not required by the
tier; the portable `ip`/`wg` pair configures the same kernel interface.

## Output and resources

A successful local run:

```
Welcome to the MUD! Type 'look' to start.
You are in a dark forest. There is a path to the north.
wireguard_demo ok bytes=100 arena_peak=275192 rss_peak=2600 cpu_ms=70
```

- `bytes` — application bytes received (banner + reply).
- `arena_peak` — bytes allocated from the demo's 512 KiB `std_arena`
  (the arena is monotonic, so used == peak).
- `rss_peak` — Linux `VmHWM` KiB; `0` when `/proc` is unavailable.
- `cpu_ms` — user+system CPU ms from `/proc/self/stat`; `0` when unavailable.

Measured at Phase 1 M7 closeout on the seed-v119 compiler
(`45158dce…`), with the portable kernel-WireGuard netns far side:

| Environment | Case | `bytes` | `arena_peak` (B) | `rss_peak` (KiB) | `cpu_ms` |
|---|---|---|---:|---:|---:|
| Linux | DNS through the tunnel | 100 | 275192 | 2556 | 70 |
| Linux (`ulimit -v 32768`) | DNS through the tunnel | 100 | 275192 | 2388 | — |
| Wine `-osw` | DNS through the tunnel | 100 | 275192 | 6804 | 450 |

The RAM row is `/usr/bin/time -v` peak process RSS (**2388 KiB**), not the
demo's own field. `arena_peak` is the exact `tcpipInit` charge for
`max_sockets = 4`: `648 + 4 * 68636 = 275192` bytes (see
[`tcpip.md`](../../../../sf/docs/std_lib/tcpip.md#memory-bounds)). Every row is
far below the 16 MiB target / 32 MiB hard ceiling. Wine reads the host `/proc`
for `rss_peak`/`cpu_ms`; real Win9x hardware reports `0` when those files are
absent.

## Related demos and docs

- [`tls_demo`](../tls_demo/README.md) — the Phase 1 M4/M5 HTTPS demo; same
  Linux + `-osw` Win9x build/run shape, resource line, and RAM discipline.
- [`sf/docs/std_lib/tcpip.md`](../../../../sf/docs/std_lib/tcpip.md) — the
  userspace IPv4/TCP/UDP/DNS/ICMP contract driven by this demo.
- [`sf/docs/std_lib/wireguard.md`](../../../../sf/docs/std_lib/wireguard.md) —
  the sans-I/O WireGuard initiator used for the tunnel.

## Troubleshooting

- `wg: ConfigRead` — wrong config path or empty file.
- `wg: BadKey` / `wg: BadConfig` — check base64/hex key length and required
  keys; every line must be `key = value` with a known key.
- `wg: Timeout` — endpoint unreachable, wrong `peer_public_key`, or the kernel
  peer rejected the handshake. Check the far-side `wg show`.
- `wg: AuthenticationFailed` — keys do not match.
- `wg: BadClock` — no usable wall clock; pass `clock_override_unix`.
- `tcp: DnsFailed` — tunnel DNS missing, CNAME-only answer, or QNAME mismatch
  (only direct A records are supported).
- `tcp: ConnRefused` / `tcp: Timeout` — `mud_host`/`mud_ip` or port wrong, the
  far side is not forwarding the tunnel subnet, or `mud_server` is not running.
- Repeated runs against the same kernel peer need a strictly increasing
  `clock_override_unix` (WireGuard replay protection).
- On Win9x, `tcp: SocketFailed` or no UDP path usually means the Winsock 2
  update is missing.
