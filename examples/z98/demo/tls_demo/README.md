# tls_demo — HTTPS fetch over `std_net` + `std_tls` (Phase 1 M4)

`tls_demo` is a Z98 program that fetches an HTTPS URL through
`std_http.httpGetOver` using a transport built on `std_net` TCP and the
sans-I/O `std_tls` TLS 1.2 client. Server certificates are validated against
the pinned `ca_store.bin` trust store (M3) with the driver-supplied wall clock.
It runs on Linux and builds as a `-osw` Win9x (no-CRT) executable.

```
tls_demo [url] [store] [clock_override_unix]
```

- `url` — default `https://www.google.com/`.
- `store` — default `ca_store.bin`; if that file is not in the current
  directory the demo falls back to
  `examples/z98/demo/tls_demo/ca_store.bin` (tree-relative).
- `clock_override_unix` — optional seconds-since-epoch. Use it on a Win9x
  machine with a dead/incorrect RTC. Without it the demo reads
  `std_time.wallClockUnix()`; an implausible system clock fails cleanly as
  `cert: time`.

Only HTTPS URLs are accepted. HTTP redirects and gzip are deferred, so the URL
must return the response directly (no `301`/`302` follow).

## Build and run (Linux)

From the repository root, using a seed-built compiler whose sibling `lib/`
carries `std_tls.zig`, `std_http.zig`, and the rest of the std modules:

```bash
mkdir -p /tmp/tls_demo
/path/to/zig1_5_clean -fsafe -o /tmp/tls_demo examples/z98/demo/tls_demo/main.zig
sh /tmp/tls_demo/build_target.sh linux /tmp/tls_demo/tls_demo

/tmp/tls_demo/tls_demo \
  https://www.google.com/ \
  examples/z98/demo/tls_demo/ca_store.bin
```

To use the default store lookup, copy the asset next to the executable and run
from that directory:

```bash
cp examples/z98/demo/tls_demo/ca_store.bin /tmp/tls_demo/
cd /tmp/tls_demo && ./tls_demo https://example.com/
```

## Build and run (Win9x, `-osw`)

```bash
mkdir -p /tmp/tls_demo_win
/path/to/zig1_5_clean -fsafe -osw -o /tmp/tls_demo_win \
  examples/z98/demo/tls_demo/main.zig
sh /tmp/tls_demo_win/build_target.sh mingw /tmp/tls_demo_win/tls_demo.exe
```

Copy `tls_demo.exe` and `ca_store.bin` to the Win9x machine and run:

```bat
tls_demo.exe https://example.com/ ca_store.bin 1790000000
```

The executable imports only `KERNEL32.DLL` and `WSOCK32.DLL` (no CRT/msvcrt)
and passes `scripts/win32_cross/check_win9x_imports.sh 9x`. Win95 needs the
Winsock 2 update installed (Win98/ME ship it). The demo only needs an existing
TCP stack; the WireGuard userspace stack is a later milestone.

## Output

On success:

```
status=200
<first 4096 bytes of the response body>
tls_demo ok status=200 bytes=90582 arena_peak=231301 rss_peak=3112 cpu_ms=1750
```

- `status` — HTTP status parsed by `std_http`.
- body — at most the first 4096 bytes; a trailing newline is added if the body
  does not end with one.
- `bytes` — full fetched body length (the `std_http` cap is 1 MiB).
- `arena_peak` — bytes allocated from the demo's 4 MiB `std_arena` (the arena is
  never reset, so used == peak).
- `rss_peak` — Linux `VmHWM` from `/proc/self/status`, in KiB. `0` on Windows.
- `cpu_ms` — user+system CPU ms from `/proc/self/stat` fields 14/15 (Linux
  `CLK_TCK` is 100 on the supported hosts), measured after the fetch. `0` on
  Windows.

On failure the process exits nonzero and prints exactly one reason line:

```
cert: CertificateExpired
cert: CertificateNotYetValid
cert: UnknownIssuer
cert: HostnameMismatch
cert: BadSignature
cert: ChainTooLong
cert: UnsupportedAlgorithm
cert: time
tls: HandshakeFailed
tls: Corrupt
tls: AuthenticationFailed
tls: RecordTooLarge
tls: UnsupportedSuite
tls: UnsupportedGroup
tls: DnsFailed
tls: ConnectFailed
tls: Timeout
tls: StoreRead
tls: StoreCorrupt
tls: BadArgs
tls: HttpBadUrl
tls: HttpTooLarge
tls: TlsInternal
```

## RAM expectations

The demo is a 32-bit program with fixed static state: `TlsSession` is about
110 KiB, the store arena is 512 KiB, and the fetch arena is 4 MiB. The tier runs
the local fetch under `ulimit -v 32768` (32 MiB hard ceiling) and records
`/usr/bin/time -v` peak RSS; observed Linux peaks are about 2.3–2.6 MiB, well
under the 16 MiB target. The response body itself is capped at 1 MiB by
`std_http`.

## Trust store

`ca_store.bin` is the M3 pinned store: magic `Z98CA100`, anchor count, total
length, then `(subject, SPKI, notBefore, notAfter)` per anchor. It was produced
from the Mozilla bundle with the sibling `caconv` tool; see
[`caconv/README.md`](caconv/README.md) for the refresh recipe.

## Tests and troubleshooting

```bash
bash examples/z98/demo/tls_demo/tests/tier_tls.sh
Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh
```

The tier builds the demo, runs a local `openssl s_server -tls1_2` happy path
with an exact body, asserts the expired/wrong-host/untrusted negatives, checks
the `Z98_NET` internet smoke (google.com + example.com) or prints a loud SKIP
when unset, measures RAM under `ulimit -v 32768`, and builds/gates the `-osw`
Win9x executable. Test certificates and keys under `tests/certs/` are
**test-only** and must never be trusted outside the tier.

Common failures:

- `cert: UnknownIssuer` — the server chain does not reach a pinned anchor. Check
  the `store` path and whether a proxy/MITM is intercepting TLS.
- `cert: HostnameMismatch` — the URL host is absent from the leaf SAN.
- `cert: CertificateExpired` / `CertificateNotYetValid` — the system clock is
  wrong or the certificate is stale. Pass the current Unix time as the third
  argument (`date +%s`).
- `cert: time` — the system clock is implausible (before 2000 or after 2100)
  and no `clock_override_unix` was supplied.
- `tls: DnsFailed` / `ConnectFailed` / `Timeout` — no DNS/route, a firewall, or
  (on Win95) no Winsock 2 update.
- `tls: UnsupportedSuite` / `UnsupportedGroup` — the server offers none of the
  four M4 suites (`ECDHE-{ECDSA,RSA}-AES128-GCM-SHA256` or
  `ECDHE-{ECDSA,RSA}-CHACHA20-POLY1305-SHA256`) or no P-256/x25519 group.
- `tls: StoreRead` / `StoreCorrupt` — missing or malformed `ca_store.bin`; rerun
  `caconv` from the current Mozilla bundle.

## Committed test material (`tests/certs/`)

| file | purpose |
|---|---|
| `root.pem`, `root.key` | test-only CA that signs the happy/wrong/expired leaves |
| `localhost.pem`, `localhost.key` | valid leaf, `SAN=DNS:localhost` |
| `expired.pem`, `expired.key` | leaf valid 2020-01-01 … 2021-01-01 (`CertificateExpired`) |
| `wronghost.pem`, `wronghost.key` | valid leaf, `SAN=DNS:wrong.example.test` |
| `rogue-root.pem`, `rogue-root.key` | test-only CA absent from `store.bin` |
| `untrusted.pem`, `untrusted.key` | `localhost` leaf signed by the rogue root |
| `store.bin` | pinned store containing only `root.pem` |

They were generated with host `openssl` (RSA-2048, SHA-256) and `store.bin` with
`sibling/caconv root.pem store.bin` (`wrote 1 anchors`). The tier uses
`openssl s_server -tls1_2 -WWW` so the body is file-exact.
