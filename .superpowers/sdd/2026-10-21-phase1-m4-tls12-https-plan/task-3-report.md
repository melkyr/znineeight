# M4 Task 3 report — tls_demo + tier_tls

Branch: `zig1_improvements` (base `7d5dd742`).
Scope: Task 3 only (demo, README, tier, test certs); no `sf/src` changes, no
seed rotation, no full stdlib gate, no compiler battery.

## Environment

- Repo root `/workspace/znineeight`.
- Compiler `/tmp/m2_t4_v114_build/zig1_5_clean`
  (md5 `45158dcede81125a39a2c2c58478e21e`); sibling `lib/` matches the current
  `sf/src` (verified `std_tls.zig` / `std_http.zig` md5s unchanged).
- Host `openssl 3.0.22`, `gcc -m32`, mingw cross tools, `/usr/bin/time`,
  `python3`.
- Local server: `openssl s_server -tls1_2 -WWW -quiet` with committed test
  certs in `examples/z98/demo/tls_demo/tests/certs/`.

## Files

Created:

- `examples/z98/demo/tls_demo/main.zig` — `tls_demo [url] [store]
  [clock_override_unix]`, default `https://www.google.com/`, default store
  `ca_store.bin` with tree-path fallback, transport over `std_net` TCP +
  `std_tls`, `std_http.httpGetOver`, 4 KiB body cap, resource line.
- `examples/z98/demo/tls_demo/README.md` — Linux + Win9x `-osw` build/run,
  config, output fields/units, RAM expectations, store refresh, troubleshooting,
  test-cert inventory.
- `examples/z98/demo/tls_demo/tests/tier_tls.sh` — local s_server happy +
  negatives, `Z98_NET` internet smoke, RAM ceiling, `-osw` + import gate.
- `examples/z98/demo/tls_demo/tests/certs/` — test-only root/localhost/expired/
  wronghost/rogue-root/untrusted cert+key material and `store.bin` (1 anchor).

No `sf/src` edits. `ca_store.bin` (M3) is the demo's default asset; the tier
uses the smaller committed test store so local anchors are hermetic.

## Step 1 — demo

Default URL is `https://www.google.com/`; optional args are
`[url] [store] [clock_override_unix]`. The clock override is parsed as decimal
Unix seconds; with no override, an implausible wall clock (before 2000-01-01 or
after 2100-01-01) fails cleanly as `cert: time`.

The transport performs the TLS handshake lazily on construction, then
`httpGetOver` writes the HTTP/1.1 request via `tlsWrite` and reads decrypted
application bytes via `tlsRead`. `cert:` errors are emitted for
`CertificateExpired`, `CertificateNotYetValid`, `UnknownIssuer`,
`HostnameMismatch`, `BadSignature`, `ChainTooLong`, `UnsupportedAlgorithm`, and
`time`; all other failures are `tls: <Reason>`, exit 1.

Build recipe used:

```
mkdir -p /tmp/tier_tls/emit
/tmp/m2_t4_v114_build/zig1_5_clean -fsafe -o /tmp/tier_tls/emit \
  examples/z98/demo/tls_demo/main.zig
sh /tmp/tier_tls/emit/build_target.sh linux /tmp/tier_tls/tls_demo
```

Observed: emit rc 0 (two `warning[3037]: potential null pointer dereference`
warnings), build rc 0, `tls_demo` produced.

## Step 2/3 — tier

### Local happy path (exact body)

```
ROOT=/workspace/znineeight
CERTS=$ROOT/examples/z98/demo/tls_demo/tests/certs
BIN=/tmp/tier_tls/tls_demo
WORK=/tmp/tls_t3_manual; rm -rf "$WORK"; mkdir -p "$WORK"
printf 'tls tier body\n' > "$WORK/body.txt"
( cd "$WORK" && exec openssl s_server -accept 14443 -tls1_2 \
    -cert "$CERTS/localhost.pem" -key "$CERTS/localhost.key" \
    -WWW -quiet ) >"$WORK/srv_happy.log" 2>&1 &
sleep 0.5
"$BIN" https://localhost:14443/body.txt "$CERTS/store.bin"
```

Observed (exit 0):

```
status=200
tls tier body
tls_demo ok status=200 bytes=14 arena_peak=321 rss_peak=2820 cpu_ms=330
```

Tier assertion: `ok - local TLS 1.2 fetch: status=200, exact body, bytes=14`.

### Local negatives (fail closed, exact text)

Same `openssl s_server -tls1_2 -WWW -quiet` launcher, substituted cert/key:

```
( cd "$WORK" && exec openssl s_server -accept 14445 -tls1_2 \
    -cert "$CERTS/expired.pem"   -key "$CERTS/expired.key"   -WWW -quiet ) &
"$BIN" https://localhost:14445/body.txt "$CERTS/store.bin"   # exit 1
( cd "$WORK" && exec openssl s_server -accept 14446 -tls1_2 \
    -cert "$CERTS/wronghost.pem" -key "$CERTS/wronghost.key" -WWW -quiet ) &
"$BIN" https://localhost:14446/body.txt "$CERTS/store.bin"   # exit 1
( cd "$WORK" && exec openssl s_server -accept 14447 -tls1_2 \
    -cert "$CERTS/untrusted.pem" -key "$CERTS/untrusted.key" \
    -cert_chain "$CERTS/rogue-root.pem" -WWW -quiet ) &
"$BIN" https://localhost:14447/body.txt "$CERTS/store.bin"   # exit 1
```

Observed (exit 1 each):

```
cert: CertificateExpired
cert: HostnameMismatch
cert: UnknownIssuer
```

Tier assertion:

```
ok   - expired leaf -> cert: CertificateExpired
ok   - wrong host -> cert: HostnameMismatch
ok   - untrusted anchor -> cert: UnknownIssuer
```

### Internet smoke (`Z98_NET=1`)

```
Z98_NET=1 /tmp/tier_tls/tls_demo https://www.google.com/ \
  examples/z98/demo/tls_demo/ca_store.bin
Z98_NET=1 /tmp/tier_tls/tls_demo https://example.com/ \
  examples/z98/demo/tls_demo/ca_store.bin
```

Observed (two tier runs; body bytes vary with live content):

```
ok   - internet www.google.com status=200 bytes=90393
ok   - internet example.com status=200 bytes=577
...
ok   - internet www.google.com status=200 bytes=90480
ok   - internet example.com status=200 bytes=577
```

Default-store lookup without an explicit store arg also returned
`status=200` for `https://example.com/` (`bytes=577`).

With `Z98_NET` unset the tier prints the loud skip (never a pass):

```
SKIP - Z98_NET unset: internet smoke SKIPPED (set Z98_NET=1 to run google.com + example.com)
== tier_tls summary: 10 passed, 0 failed, 1 skipped ==
TIER_TLS PASS
```

### RAM (`ulimit -v 32768` + `/usr/bin/time -v`)

```
( ulimit -v 32768; /usr/bin/time -v /tmp/tier_tls/tls_demo \
    https://localhost:<port>/body.txt <store> )
```

Observed peaks across runs:

```
ok   - RAM ceiling ok: /usr/bin/time peak RSS=2500 kB (ulimit -v 32768)
ok   - RAM ceiling ok: /usr/bin/time peak RSS=2748 kB (ulimit -v 32768)
```

Resource lines reported `rss_peak` around 2.7 MiB; well under the 16 MiB target
and 32 MiB hard ceiling.

### `-osw` emit/build + Win9x import gate

```
/tmp/m2_t4_v114_build/zig1_5_clean -fsafe -osw -o /tmp/tier_tls/win_emit \
  examples/z98/demo/tls_demo/main.zig
sh /tmp/tier_tls/win_emit/build_target.sh mingw /tmp/tier_tls/tls_demo.exe
bash scripts/win32_cross/check_win9x_imports.sh \
  /tmp/tier_tls/tls_demo.exe 9x
```

Observed:

```
/tmp/tier_tls/tls_demo.exe: PE32 executable (console) Intel 80386 ...
ok   - -osw emit + mingw build produced tls_demo.exe
ok   - file: PE32 i386
ok   - check_win9x_imports.sh 9x whitelist PASS
       DLL KERNEL32.DLL
       DLL WSOCK32.DLL
```

(`WINMM` is not imported because the demo uses no audio; the import whitelist
allows KERNEL32 + WSOCK32 and the emitted link line carries `-lwsock32`.)

### Targeted consumers + 3x determinism

```
bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_v114_build/zig1_5_clean \
  repro/mi_matrix/stdlib_http_transport_xmod \
  repro/mi_matrix/stdlib_tls12_handshake_xmod
```

Observed:

```
PASS repro/mi_matrix/stdlib_http_transport_xmod
PASS repro/mi_matrix/stdlib_tls12_handshake_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

`run_fixtures.sh` runs each fixture 3x and byte-compares to the committed
golden; the tier itself also compares the local happy `status`/body/`bytes`
lines across two internal runs (`ok - happy status/body/bytes identical 2x`).

### Two full deterministic tier runs

```
Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh  # run 1
Z98_NET=1 bash examples/z98/demo/tls_demo/tests/tier_tls.sh  # run 2
```

Both observed:

```
== tier_tls summary: 12 passed, 0 failed, 0 skipped ==
TIER_TLS PASS
```

### Clock override checks

```
/tmp/tier_tls/tls_demo https://localhost:<port>/body.txt <store> 4102444800
# exit 1: cert: CertificateExpired
/tmp/tier_tls/tls_demo https://localhost:<port>/body.txt <store> notanumber
# exit 1: tls: BadArgs
```

## Commits

- `example(z9demo): tls_demo HTTPS fetch (Phase1 M4)` — `b9fb17bd`
- `test(tier): tier_tls (Phase1 M4)` — `dc591c3b`
- `docs(sdd): M4 T3 report` — this report

## Concerns

- Live internet body lengths vary (Google especially); the tier asserts
  `status=200` and `bytes>0`, not a body golden, by design.
- `cpu_ms` uses `/proc/self/stat` fields 14/15 with the Linux `CLK_TCK=100`
  assumption; `rss_peak` uses `VmHWM` in KiB. Both are recorded fields, not
  hard thresholds (RAM is gated by `ulimit -v 32768`).
- The committed test private keys are intentionally public and `tests/certs/`
  is test-only; the README says not to trust them outside the tier.
- Win9x hardware execution is operator-owned; this task gates emission, PE32,
  and the closed-world import whitelist only.
