# Z98 Compiler Quick Reference

## ⭐ SUBAGENT CHEAT-SHEET — READ THIS SECTION BEFORE ANY BUILD/COMPILE/RUN ⭐

**Every subagent doing build/compile/run/gate work MUST read this section first.** These are the
exact, verified commands. Do not improvise flags or rediscover linking — copy these.

> **Runtime safety:** `-fsafe` is the default (six runtime checks — cast / div-mod / shift /
> null-unwrap / index-OOB / integer-overflow — plus `undefined` `0xAA` poison); `-ffast` disables
> them. `unreachable`/`@panic` trap in **both** modes (`@panic` prints `panic: <msg>` to **stderr**).
> `std.arena.alloc` is `ArenaError![*]u8` — use `try`/`catch`, never `orelse` (`error[3016]`).

> **Mutable `for` capture (`|*item|`):** `for (xs) |*item|` / `|*item, index|` binds a pointer
> into the iterable storage (`*T`, or `*const T` for a const element type such as `[]const T` /
> `*const [N]T`, or a const-bound array; a const binding of a mutable slice keeps `*T`); `item.*` /
> `item.field` write through it while the binding stays immutable. A range iterable, a
> non-variable array value, or an iterable with no resolvable element type rejects `error[3078]`.
> `if`/`while`/switch-prong pointer captures remain unsupported.

> **CWD collision hazard:** `zig1` writes shared `.zig1_*.tmp` spill files in the CWD. Two `zig1`
> runs in the same directory collide — parallel invocations can emit empty or corrupt dumps, and a
> byte-identity/pin md5 taken from such a run is meaningless. Run gate/compile invocations
> **sequentially**, or give each run its own CWD. Measured 2026-10-27: two parallel dumps in one CWD
> produced empty stdout (md5 `d41d8cd98f00b204e9800998ecf8427e`); sequential reruns were clean.

### Build zig1 (the compiler under test)

zig0 is retired and the old zig0 cycle (`sf/scripts/build_release.sh`,
`sf/build/out_release/`) no longer builds current `sf/src` — do NOT use it as
the build path or gate on it. Rebuild from the committed seed with the recipe
in the next section; that is the only supported path.

### Seed model — rebuild zig1 from the committed seed (`release/seed/`) [updated: 2026-11-11 — seed v148]

**Seed location + contents:** the committed rotating seeds are
`release/seed/zig1-seed.tgz` (Linux/gcc canonical fixed point) and
`release/seed/zig1_seed_w9.zip` (Win9x companion) — both git-tracked;
provenance + rotation history in `release/seed/CHANGELOG.md`, full recipes +
current md5s in the archive's `zig1-seed/SEED_README.txt` and the v148 CHANGELOG entry.

**Current seed: v148** (rotated 2026-11-11 for the Phase 4 P3 closeout;
packaging base HEAD `fb896e2b`). Archived binary md5
(= fixed point) `73c75a65e30dfd212fdf93ae1e57a687`; archive md5
`2bd90de43b29b070abb70a2448dabbeb`; Win9x zip md5
`48ba3422e710e18dfb3e065abbc7c8bc`; `gen/` 48 `.c` + 49 `.h` (12,932,829
bytes); `lib/` **65** std `.zig` (`std.zig` + 64 `std_*.zig`) plus
`lib/manifest.md5` (per-file std attribution pin, manifest md5
`7fb073e7b153e34d9c216adce7d896f4`; includes `std_ddraw.zig`,
`std_ddraw_pal.zig`, `std_dinput.zig`, `std_dinput_pal.zig`, `std_dsound.zig`,
`std_dsound_pal.zig`, `std_tls_io.zig`, `std_hpack.zig`, `std_http2.zig`).
A rebuild from the committed v148 archive is two-hop
**hop1 == hop2 == `73c75a65…`**. The compiler source is **`-fsafe`-clean**.
v148 is the std-only Phase 4 P3 rotation: it adds `std_ddraw*`, `std_dinput*`,
and `std_dsound*` to `lib/` (59 -> 65) with no compiler-source or barrel change,
so the fixed point and the 8 emission pins stay `73c75a65…`. v147 was the final
Phase 3.5 expected-type-contract rotation; its narrative and fixed-point history
remain in `release/seed/CHANGELOG.md`.


**Win9x companion zip:** `release/seed/zig1_seed_w9.zip` unpacks to
`zig1-seed-w9/{README.txt, lib/, win/}`. `win/` is the Windows-target
`zig1 -osw` compiler C/runtime with the two emitted static-CRT compiler
build scripts plus the MinGW fallback pair, no prebuilt `zig1.exe`. To build
the compiler on the era machine:

```bat
rem OpenWatcom: run C:\WATCOM\OWSETENV.BAT in this window first
cd zig1-seed-w9\win
build_owc_crt.bat
copy prog.exe ..\zig1.exe
```

or `build_target_crt.bat` from a fresh window after `VCVARS32.BAT` (never with
the Watcom env); with a Windows-hosted MinGW gcc put its `bin` directory on
`PATH` and use `build_mingw_crt.bat` (CRT-linked) or `build_mingw_nocrt.bat`
(no-CRT). The OpenWatcom/MSVC scripts read compiler flags from `z98_cc.rsp`
(`/fpc` / `/Op`) and link inputs from `z98_link.lnk` / `z98_link.rsp`; the
MinGW scripts are response-file-free (gcc 3.4.5 has no `@file`) with explicit
chunked `gcc -r` partial links and a short final link. Each script echoes
every command and its output to `00.txt` in `win/` (last line `Built: prog.exe`
or `BUILD FAILED`) and writes `prog.exe` (arguments are ignored by design — the
scripts are command.com-safe); copy it to `..\zig1.exe`. The MSVC script's
`CL_EXE` / `LINK_EXE` variables can point at absolute tool paths when another
toolchain shadows `cl.exe`/`link.exe`. `..\lib\` is the standard library. The MSVC/OWC pair uses a static CRT (`/MT` / OpenWatcom static CLIB),
no `msvcrt.dll`, single EXE, and may import KERNEL32 names beyond the strict 9x
whitelist. The compiler
source in the zip is `-fsafe`-clean; the Windows-hosted `std_async.zig:259`
field-resolution failure was root-caused to a C89 update-stream fseek elision
in `spill_store.zig` and fixed, so this CRT build is **app-ready**. The compiler's own
no-CRT build is deferred until the asm_x86 backend; emitted programs still
default to no-CRT. The zip is not a fixed-point artifact; `archive_seed.sh`
packs it deterministically with python3 `zipfile`.


Top-level `zig1-seed/`: `zig1` (reference binary), `gen/` (its self-emission C89
module set — 48 `.c` + 49 `.h`, including `zig_special_types.h`; the emitted
runtime/support sources are NOT in `gen/`), top-level `c_exit.c`, `runtime/`
(the emitted 6: `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h`,
`zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c` — NO `net_prelude.h`), `lib/` (the
tracked seed archive **v148 carries the full 65 std `.zig`** = `std.zig` plus
64 `std_*.zig`; `scripts/seed/build_from_seed.sh` and `archive_seed.sh` install
the current `sf/src` set into the produced compiler's `lib/` and the archive),
and `SEED_README.txt`.

**Std-module inventory:** the `sf/src` std set is **64** `std_*.zig` + `std.zig`
(`std_io`, `std_fmt`, `std_arena`, `std_str`, `std_mem`, `std_math`, `std_debug`,
`std_net`, `std_async`, `std_bits`, `std_os`, `std_os_pal`, `std_time`,
`std_time_pal`, `std_page`, `std_page_pal`, `std_gpa`, `std_pool`, `std_buf`,
`std_file`, `std_file_pal`, `std_stdin`,
`std_stdin_pal`, `std_stream`, `std_crypto`, `std_cipher`, `std_ecc`,
`std_parse`, `std_bencode`,
`std_map`, `std_sort`, `std_heap`, `std_rle`, `std_base64`, `std_hex`,
`std_utf8`, `std_http`, `std_rand`, `std_noise`, `std_lz4`, `std_zstd`,
`std_deflate`, `std_ddraw`, `std_ddraw_pal`, `std_dinput`, `std_dinput_pal`, `std_dsound`, `std_dsound_pal`, `std_num`, `std_pathfind`, `std_hpa`, `std_physics`, `std_asn1`, `std_x509`,
`std_tls`, `std_tls_io`, `std_hpack`, `std_http2`, `std_wireguard`, `std_tcpip`, `std_gfx`, `std_gfx_pal`,
`std_fold`, `std_fft`). `std.zig` re-exports
the core **17** names (`io/fmt/arena/str/mem/math/debug/net/async/bits/os/time/page/gpa/pool/buf/fold`);
the higher-layer modules (L3-L6) are imported by path, not re-exported.
`scripts/seed/build_from_seed.sh` installs all 65 into the rebuilt compiler's `lib/`.

**Phase 3.1 allocators (`std.page`/`std.gpa`/`std.pool`) — scope and limits.**
`std.page` exposes `posix_mode` = `auto`/`remap`/`protect`/`modern` (POSIX
`mmap`/`mprotect`; Windows `VirtualAlloc`); the optional `madvise_fn` callback is
used only by the `modern` mode. Win32 `pageRelease` is
`VirtualFree(ptr, 0, MEM_RELEASE)` — the size argument is deliberately 0, unlike
POSIX `munmap`, which rounds the reservation size. `std.gpa` profiles are
`target32/64/128/256/512/modern`; the default is `target64` (64 KiB medium cap,
2 MiB chunks, 64 MB target). `align` must be a power of two in `[8, 4096]`.
`safe_checks` is explicit in `GpaConfig`: `-fsafe` alone does **not** enable the
GPA magic/ownership validation. TLS is design-only; `.encrypted` is deferred;
there is no compiler allocator migration and no security or cycle-target claim.
Win9x evidence is cross-build/Wine only.
**`std_crypto` (M4):** carries streaming SHA-1/SHA-256/MD5 + CRC-32 plus RC4 (`rc4Init`/`rc4Apply`, RFC 6229 vectors) and modular exponentiation (`modpow`, fixed 32-bit limbs sized for the MSE/PE 768-bit Diffie-Hellman prime) for the encrypted handshake.
**`std_crypto` M2 additions:** SHA-384/512, HMAC-SHA256 (one-shot + streaming), HKDF extract/expand (RFC 5869), BLAKE2s + HMAC-BLAKE2s (RFC 7693 / WireGuard MAC), and verify-only RSA PKCS#1 v1.5 / PSS (RFC 8017, generic modexp cap 4096-bit). Errors: `BadSignature` / `Corrupt` (`UnsupportedAlgorithm` is unrepresentable via `HashAlg`).
**`std_cipher` (M2):** ChaCha20 (RFC 8439, 20 rounds unrolled), Poly1305 (donna 5×26-bit limbs, constant-time), ChaCha20-Poly1305 AEAD (`error.AuthenticationFailed`), AES-128 (FIPS-197, 4 KiB `const` T-tables `R/r` rodata), AES-128-GCM (SP800-38D, GHASH 4-bit tables). Pure, no heap/arena; fixtures `stdlib_chacha_poly_xmod` + `stdlib_aes_gcm_xmod`; T-table gate `scripts/compiler/gate_cipher_rodata.sh`. Doc: `sf/docs/std_lib/cipher.md`.
**`std_ecc` (M2):** X25519 (ref10 26/25-bit ladder, RFC 7748 clamp + all-zero `error.WeakPublicKey`), P-256 keygen/ECDH/ECDSA verify, P-384 ECDSA verify (shared BearSSL i31 engine, MIT). No heap/libm/f64; constant-time scalar paths; uncompressed pubkeys 65/97 bytes. Fixtures `stdlib_x25519_xmod` + `stdlib_ecc_verify_xmod` (plus `scripts/stdlib/run_ecc_safe.sh`). Doc: `sf/docs/std_lib/ecc.md`.
**`std_asn1` (M3):** streaming DER TLV reader (`Asn1Reader`/`Tlv`/`TagClass`, `asn1Init`/`asn1Remaining`/`asn1ReadTlv`); no allocation, slices alias the input, definite/minimal-length only, `error.Corrupt` only. Fixture `stdlib_asn1_xmod`. Doc: `sf/docs/std_lib/asn1.md`.
**`std_x509` (M3):** certificate parse (`Cert`/`x509Parse`), browser-grade leaf-to-anchor chain verification (`x509VerifyChain`, depth ≤ 8, exact §5.4 error set), SAN dNSName-only hostname matching, and pinned §5.5 trust store (`trustStoreLoad`). Fixtures `stdlib_x509_parse_xmod`, `stdlib_x509_verify_xmod`, `stdlib_truststore_xmod`. Asset + converter: `examples/z98/demo/tls_demo/ca_store.bin`, `examples/z98/demo/tls_demo/caconv/`. Doc: `sf/docs/std_lib/x509.md`.
**`std_tls` (M4/M5):** sans-I/O TLS 1.2/1.3 record layer + client handshakes — 5-byte header, 16 KiB plaintext cap, four TLS 1.2 suites (`ECDHE-{ECDSA,RSA}-{AES128-GCM,CHACHA20-POLY1305}-SHA256`) plus two TLS 1.3 suites (`AES_128_GCM_SHA256`/`CHACHA20_POLY1305_SHA256`), RFC 5288/7905 nonces, ECDHE P-256/x25519 (1.2) and x25519 key_share (1.3), SNI, `std_x509` chain validation at the caller's `now_unix`, PRF_SHA256 Finished (1.2) / HKDF-Expand-Label + 32-byte Finished (1.3), ECDSA P-256/P-384 and RSA-PSS CertificateVerify (PKCS#1 v1.5 rejected), `SendClientHello … Established`. KeyUpdate is unsupported (receipt → `error.Closed`). Fixtures `stdlib_tls_record_xmod`, `stdlib_tls12_handshake_xmod`, `stdlib_tls13_handshake_xmod`, `stdlib_tls13_auth_xmod`, `stdlib_tls13_fallback_xmod`. Demo `examples/z98/demo/tls_demo`; tier includes local 1.3 (both suites), 1.2 fallback, and a `Z98_NET=1` RSA-PSS host. Doc: `sf/docs/std_lib/tls.md`.
**`std_tls` ALPN + `prefer_chacha20` (Phase 3.3):** `TlsConfig.alpn_h2` (default `false`) appends the ALPN extension offering `h2` then `http/1.1`; `TlsSession.alpn`/`tlsAlpnSelected` report `.none`/`.h2`/`.http11`/`.other`, and a server-selected protocol the client never offered is rejected (`HandshakeFailed`). `TlsConfig.prefer_chacha20` (default `false`) reorders suites ChaCha20-first (TLS 1.3 `0x1303` before `0x1301`; the TLS 1.2 ChaCha pair before AES) and supported groups x25519-first; the HTTP/2 path sets it, and the default keeps existing wire fixtures byte-identical. Fixture `stdlib_tls_alpn_xmod`; gate `scripts/stdlib/run_tls_alpn.sh`.
**`std_tls_io` (Phase 3.3):** nonblocking TLS socket driver on `std_net` — `TlsIo`, `TlsIoError` (the full `TlsError`∪`NetError` name union, 31 names; no catch-map), `tlsIoInit`/`tlsIoHandshakePump`/`tlsIoReadPump`/`tlsIoWritePump`/`tlsIoClose`/`tlsIoCloseForce`, with `tlsIoPending` (queued ciphertext, `out_off < out_len`) and `tlsIoClosePending` (a prior close deferred). The pumps are non-suspending, own their out/in buffers, flush pending wire bytes before each step, and return `WouldBlock` instead of blocking; `tlsIoCloseForce` flushes best-effort then closes the fd. Fixture `stdlib_tls_io_xmod`; gate `scripts/stdlib/run_async_io.sh <zig1> tlsio`.
**`std_hpack` (Phase 3.3):** 61-entry static table, integer/string codec, full canonical-Huffman decode (two-level table + rare-code tail), ring dynamic table with caller storage and O(1) eviction; encoding is literal-only. `hpackInit`/`hpackDecode`/`hpackEncode`; malformed input fails closed as `HpackError.Corrupt`. Fixtures `stdlib_hpack_vectors_xmod`, `stdlib_hpack_huffman_xmod`, `stdlib_hpack_dynamic_xmod`.
**`std_http2` (Phase 3.3):** frame/settings codec, connection/streams/flow control, TLS+ALPN and h2c prior-knowledge adapters, and the body API. `Http2Config` defaults: `max_streams` 16, `max_header_list` 65536, `initial_window` 65535, `max_frame_size` 16384, `header_table_size` 4096. `http2OpenTransport` is the test seam; `http2OpenTls` returns `NotHttp2` unless `tlsAlpnSelected == .h2`; `http2OpenTcp` is h2c prior knowledge. `http2Submit` queues, `http2Pump` is non-suspending (`progress`/`would_block`/`closed`) and never blocks, and `http2Wait` suspends. The caller loop must select **read AND write** readiness with a bounded timeout and a stall watchdog, and re-arm writability whenever the pump reports pending output. A closed/reset stream slot is **leased**, not free: `http2Wait` by id stays valid until `http2Release` returns the slot to idle; `http2Close` reclaims abandoned leases and is graceful/retryable: it returns `CloseStatus.pending` while HTTP output, queued TLS ciphertext (`tlsIoPending`), or a deferred TLS close (`tlsIoClosePending`) remains, drives one nonblocking `tlsIoWritePump(io, empty)` flush per call when ciphertext is queued, re-checks after `close_fn`, and the caller re-arms writability and retries until `.closed` (a blocked close never finalizes or leaks the socket); `http2CloseForce` is the unconditional teardown (one best-effort flush, exactly one transport close, unsent output dropped; the TLS path uses `tlsIoCloseForce`, which closes the fd even when the final ciphertext flush would block), and `http2ClosePending` remains available for polling loops. Buffered `TooLarge` is stream-local: `http2Pump` continues, `http2Wait` returns `error.TooLarge`, and other streams keep running. Malformed response header semantics (RFC 7540 §8.1.2.6: empty/uppercase/non-token names, CR/LF/NUL values, missing/duplicate/misordered `:status`) are also stream-local: RST that stream, keep pumping, and `http2Wait` returns `error.Protocol`; HPACK `Corrupt` remains connection-level. Convenience functions `http2Get`/`http2Post`/`http2GetStream`/`http2PostStream` are `Http2Error!void` with a trailing `id_out: *u32` (D14: Z98 cannot lower the suspending `Http2Error!u32` wrapper shape), wait internally, and do not release. Buffered bodies are copied into the **caller-owned `out.body` capacity** and capped at 1 MiB; over-cap or too-small capacity returns `TooLarge`, and larger bodies use `ResponseSink`. Headers stay valid until release. No server push, no priority scheduling, no HTTP/2 Upgrade. Fixtures `stdlib_http2_frames_xmod`/`_state_`/`_body_`/`_tls_`/`_h2c_xmod`; gates `run_fixtures.sh` / `run_phase33_safe.sh` and `run_http2.sh` (Node 18+; absent prints `SKIP`, never PASS). z9git remains HTTP/1.1.
**`std_wireguard` (M6):** sans-I/O WireGuard **initiator** (`WgDevice`/`WgPeer`, `wgInit`/`wgAddPeer`/`wgTick`/`wgReceive`/`wgSend`; `WgAction = union(enum){ none, send_handshake, send_keepalive, session_up, inner_packet, dropped_replay }`). NoiseIK per §5.7 with HKDF-BLAKE2s KDF and ChaCha20-Poly1305; initiation 148 B / response 92 B / transport header 16 B with zero padding to 16 and a 64-bit LE counter nonce. TAI64N comes from `wall_unix_ns` (never `now_ms` — a monotonic-derived timestamp is rejected as a replay after restart). Timers via `wgTick(now_ms)` only (no `sleep`): 120 s rekey, 180 s reject (`wgSend`/`wgReceive` → `error.SessionExpired`), 5 s + bounded jitter retry, 10 s keepalive. 2048-bit replay window (authenticate before window update), CookieReply consumption with `mac2` (generation out of scope), and rekey continuity (active session/keys/indices/counter/replay preserved while a new initiation is pending; the response installs pending state atomically and returns `.session_up`). Errors `Corrupt`/`AuthenticationFailed`/`NoSession`/`SessionExpired`/`OutputTooSmall` (+ `NoSpace`/`InvalidPeer`). Fixtures `stdlib_wg_handshake_xmod`, `stdlib_wg_transport_xmod`, crosscheck `stdlib_wireguard_cross_xmod` (3 vectors). Doc: `sf/docs/std_lib/wireguard.md`.
**`std_tcpip` (M7):** client-only userspace IPv4 stack (`TcpipConfig`/`TcpipStack`, `tcpipInit`/`tcpipPoll`, `tcpConnect`/`tcpSend`/`tcpRecv`/`tcpClose`, `udpOpen`/`udpSendTo`/`udpRecvFrom`, `dnsResolve`, `icmpPing`; `TcpipAction = union(enum){ send_pkt, wait, connected, data, closed, failed, done }`). Sans-I/O pump: the caller feeds raw IPv4 datagrams and sends the returned datagrams. TCP client only (3WHS, fixed 8 KiB window, MTU-authoritative `mss = min(peer MSS, mtu - 40)`, fixed 1 s RTO with simplified Karn, slow start + AIMD, no SACK/scaling, no fragment reassembly); UDP one TX/RX slot per socket; DNS A/IN only (CNAME chains `DnsFailed`); ICMP echo with fixed 1 s × 3 retries. `tcpipPoll` returns `.done` on a terminal DNS/ICMP request; the final helper call returns the A record/RTT or `DnsFailed`/terminal `Timeout`. State is arena-backed and fixed: `TcpipStack` 648 B + `max_sockets × (TcpSock 65648 + UdpSock 2988)`. Fixtures `stdlib_tcpip_tcp_xmod`, `stdlib_tcpip_udp_xmod`, `stdlib_tcpip_dns_xmod`; demo `examples/z98/demo/wireguard_demo`; tier `tier_wireguard.sh`. Doc: `sf/docs/std_lib/tcpip.md`.
**`std_http` transport (M4 + Phase 3 v136/v138):** `HttpTransport` (read/write/close callbacks) and `httpGetOver` (GET, HTTP/1.1, `Connection: close`, identity + chunked body decode) make HTTPS a std capability. Phase 3 adds `httpPostOver` (POST with `content_type`/`accept`; empty values omit those headers; same 1 MiB whole-body cap) and `httpPostStreamOver` with `ResponseSink` (headers land in `out_head` with an empty body; de-chunked body bytes flow to the sink in bounded ~1 MiB chunks, unbounded apart from hardware); the convenience `post()` mirrors `get()`. v138 adds `httpGetHeadersOver` (buffered GET with caller headers, including `Range` for static servers), `httpGetStreamOver` (the same extra-header GET with the body streamed to a `ResponseSink`), and `RequestSource`/`httpPostStreamBodyOver` (a POST request body streamed from a caller source with a declared `Content-Length`, response streamed through the same sink path). Extra-header names/values reject CR/LF/NUL with `BadHeader`. `get()`/`post()` follow a 301/302/303/307 `Location` once. The pure `parseResponse` still requires a `Content-Length` or a close-delimited body and rejects `Transfer-Encoding: chunked` with `BadResponse` (the transport paths decode chunked); keep-alive remains **DEFERRED**. Fixtures `stdlib_http_transport_xmod`, `stdlib_http_post_xmod`, `stdlib_http_post_stream_xmod` (v138 adds no new fixture dirs; the eight `stdlib_http_*` dirs are 8/8 PASS). Doc: `sf/docs/std_lib/http.md`.
**`std_zstd` dictionaries (Phase 3 v136):** `zstdDecompressDict(src, dst, dict, max_window_log) !u32` accepts RFC 8878 magic dictionaries (id parsed; a frame's nonzero dict id must match, a frame id of 0 accepts any supplied dict) and raw-content dictionaries (dict-id-0 frames only); the dict's entropy tables seed first-block Repeat and its content pre-seeds history. `zstdDecompress` itself is unchanged and still rejects a nonzero dict id. Fixtures `stdlib_zstd_dict_{basic,entropy,hist,mismatch,raw}_xmod`. Doc: `sf/docs/std_lib/zstd.md`.
**`std_deflate` (Phase 3 v136):** new L4 single-shot inflater, no heap, caller-owned `dst`. `inflateRaw(src, dst, used) !u32` decodes RFC 1951 raw DEFLATE; `inflateZlib(src, dst, used) !u32` validates the RFC 1950 CMF/FLG/FCHECK wrapper, rejects `FDICT`, and verifies Adler-32. Both write the consumed input byte count (wrapper included) to `used`; errors are `error.Corrupt` / `error.OutputTooSmall`. Fixtures `stdlib_deflate_*_xmod`. Doc: `sf/docs/std_lib/deflate.md`.
**`std_math` f64 (M2, z9play):** adds pure-Z98 `sqrt(x: f64) f64` (correctly rounded: exact integer square root of the significand, 0 ULP), plus `sin(x: f64) f64` / `cos(x: f64) f64` (Cody-Waite argument reduction on a split `2/pi` + fdlibm `__kernel_sin`/`__kernel_cos` minimax, one op per statement so the C89 emitter's f64 stores defeat x87 excess precision). **Pure Z98 — no libm, no `@sqrt`/`@sin`/`@cos` builtins**; the emitted C imports no math symbol (the z9play M2 tier asserts `nm -u` has no `sqrt`/`sin`/`cos`/`pow` and DT_NEEDED has no `libm`). `sin`/`cos` are valid for `|x| <= 2^20*(pi/2) ≈ 1.65e6` (fdlibm medium-reduction cap; covers the Vorbis IMDCT/window range with >60x headroom) and return NaN outside it; `sqrt` maps `x<0` to NaN and passes `0`/`inf` through. Accuracy <= 1 ULP vs a glibc/python oracle. Fixture: `repro/mi_matrix/stdlib_math_f64_xmod`; z9play gate: `examples/z98/z9play/tests/tier_math.sh`. See `sf/src/std_math.zig`.
**`std_noise` (M2):** Kurt Spencer's **2014 OpenSimplex v1.1** (NOT OpenSimplex2) — `opensimplexInit`/`noise2d`/`noise3d`/`noiseFbm2d`, 512 B state (`perm` + `perm_grad`) seeded via `std_rand` xoshiro Fisher–Yates; f64 throughout (no f32 shortcut — it fails the visual golden). Canonical 2014-reference constant literals (`0.366025403784439` / `-0.16666666666666666`); the temporary adjacent-literal lexer workaround was removed at the M2 T1D closeout (T1B correctly-rounded `parseF64`). Pins: crosscheck `scripts/stdlib/vectors/std_noise/grid.expected` md5 `94314ebd32053089b226387770c0cd5d` (Z98 == C89 ref), visual golden `pgm fnv1a64 4921c94f3ec08543` (`stdlib_noise_basic_xmod`). Doc: `sf/docs/std_lib/noise.md`.
**`std_num` (M4):** Dormand–Prince **7-stage embedded 5(4)** adaptive RK45 (`Rk45Config`/`Rk45State`/`rk45Step`), FSAL 7th stage reused via the caller's `dy`, scaled-RMS error norm, accept `err <= 1`, reject `0.9*err^(-1/5)`, grow `1.5x` only when `err < 0.5` (capped at `max_step`). Allocation-free, caller-owned `y`/`dy`, error set exactly `error.StepTooSmall`, fixed scratch cap `RK45_MAX_DIM = 64`. Explicit method — stiff systems are out of scope. Pins: basic fixture `stdlib_num_basic_xmod` (byte-exact stdout), crosscheck `stdlib_num_cross_xmod` + `scripts/stdlib/vectors/std_num/basic.{in,expected}` (Z98 == C89 ref). Doc: `sf/docs/std_lib/num.md`.
**`std_pathfind` (M5):** Jump Point Search (`Point`/`Grid`/`jpsFind`) plus optional static-grid JPS+ (`JpsPlus`/`jpsPlusBuild`/`jpsPlusFind`). 8-connected uniform cell cost: cardinal 10, diagonal 14, heuristic `10*max+4*min`; strict no-corner-cut (a diagonal needs both adjacent cardinals walkable), Harabor & Grastien SoCS 2012. `jpsFind` reads the live grid; `jpsPlusBuild` precomputes 8 signed `i32` distances per cell in N,NE,E,SE,S,SW,W,NW order (positive jump, negative wall, 0 blocked) at 32 bytes/cell persistent (33 bytes/cell peak with the transient build bitmap), arena only, and the map must be rebuilt if tiles change. Both functions return the full tile count; `out` is capacity, writes at most `out.len/2` forward pairs, ignores an odd trailing slot. Pins: basic/plus fixtures + crosscheck (`stdlib_pathfind_*`, Z98 == C89 A*); report-only perf: JPS+ 6.06 ms vs `jpsFind` 8.87 ms per query (22% obstacle), 0.127 ms vs 3.37 ms (open); A* still faster. Doc: `sf/docs/std_lib/pathfind.md`.

**`std_physics` (M6):** Position-Based Dynamics (`Particle`/`DistanceConstraint`/`PbdWorld`, `pbdInit`/`pbdAddParticle`/`pbdAddDistance`/`pbdPin`/`pbdStep`) for cloth, soft bodies, and ropes. `pbdStep` integrates non-pinned particles with `new = pos + (pos-prev)*(1-damping) + gravity*dt*dt`, stores `prev = old pos`, then runs `iterations` projection rounds over a seeded Fisher–Yates shuffle of the constraint order. Distances use f64 `std_math.sqrt` then an f32 cast; projection splits by inverse mass (`wa/(wa+wb)`, `wb/(wa+wb)`) and skips `len==0`/`wa+wb==0`. `stiffness` is the per-iteration fraction (1 = exact in one projection); cloth starts at 1 with 4–8 iterations, soft bodies use lower stiffness and more iterations. v1 has no collision constraints; a pin is `inv_mass = 0` (never moves). Same seed + world + dt sequence ⇒ bit-identical trajectory. Over-capacity adds, negative `inv_mass`, `a==b`, out-of-range indices, and `pbdPin` out of range panic. Pins: basic/cross fixtures, particle/distance panic fixtures, `stdlib_test/physics_usage`, and crosscheck (`stdlib_physics_*`, Z98 == C89 ref). Doc: `sf/docs/std_lib/physics.md`.

**`std_hpa` (M7):** Exact-cost **HPA\*** (`Cluster`/`AbstractNode`/`AbstractEdge`/`AbstractMap`, `hpaBuild`/`hpaFind`) over the M5 8-connected grid (cardinal 10, diagonal 14, strict no-corner-cut). Clusters are clipped `cluster_w × cluster_h` rectangles, row-major. One abstract node per **transition tile** (walkable with a legal cross-cluster 8-neighbour); node ids are cluster-major then row-major. Cross-cluster adjacencies are directed 10/14 edges both ways; every reachable same-cluster transition-node pair gets both directed edges at the exact cluster-restricted `jpsFind` cost. Adjacency ranges are sorted by `to`. `hpaFind` adds temporary `S`/`G` nodes (cluster-local reachability, plus a direct `S -> G` edge for same-cluster queries), searches with the octile heuristic and `(f<<32)|(~g)` key, then refines with cluster-local `jpsFind`, dropping duplicate boundary tiles. Build leaves only map allocations in the caller arena; query scratch is separate and resettable. Maps are static — rebuild after any tile change. Classic Botea entrance-segment compression is deferred; v1 is exact, not approximate. `out` is capacity in `u32` slots, writes at most `out.len/2` forward pairs, ignores an odd trailing slot, and returns the full tile count. Pins: basic/cross fixtures, `stdlib_test/hpa_usage`, crosscheck (`stdlib_hpa_*`, Z98 == C89 full-grid A\*), 3× deterministic. Doc: `sf/docs/std_lib/hpa.md`.

- **Compiler↔std separation:** the compiler's import graph reaches **no std module** —
  the transitive `@import` closure from `sf/src/main.zig` is zero std modules. The std lib is
  **user-side `.zig`, compiled on demand** from `<exe_dir>/lib/`; the self-emission fixed point
  is therefore **independent of the std lib** (adding or removing std modules does not move it).
- zig0 is retired; the seed model (`scripts/seed/build_from_seed.sh`) is the only rebuild path.
- **C89-AHEAD note:** `runtime/` carries the compiler's **emitted, mode-specific** support (the
  `-ffast` self-emission support), not the canonical `-fsafe` `sf/src/include` files, so a
  gcc-only rebuild of the archive C reproduces the archived binary's fixed point exactly.


### Compiler limits — `Type`-column ceilings  [added: 2026-10-08]

The type-registry `Type` record (`sf/src/type_registry.zig`) is **20 B**; its four
ceiling columns are `name_id`/`payload_idx` = **u32** and `module_id`/`alignment` =
**u16**. The only residual ceilings are the u16 pair — **65,535** modules / alignment
value — and both are **effectively unreachable** (no program reaches 65,535 modules or
such alignment values; `name_id`/`payload_idx` are back to the pre-plan u32 width).

The earlier structural-narrowing `Type` 32 B→16 B shrink had created real user-facing
ceilings that the **type-limit widening** (2026-10-08) raised: `name_id` u16 (65,535
distinct interned strings — a **global** interner id, not a type count), `payload_idx`
u16 (65,535 entries in one payload array), `module_id` u8 (256 modules) and `alignment`
u8 (255). The widening removed those and deleted the
`typeDbCeiling`/`typeNarrowU16`/`typeNarrowU8` guards.

The string interner imposes **no** ceiling: its buckets auto-migrate u16→u32 when the
u16 range is exhausted (`sf/src/string_interner.zig`), so a wide program keeps interning.
No `Type`-column user ceiling remains in practice.

### Compiler limits — expression / recursion depth  [added: 2026-10-26]

Two independent depth ceilings exist. Both are documented here; the defects file
(`examples/torrent_example_defects.md`) tracks only open defects.

**1. Parser — expression *nesting* cap: 12.** `sf/src/parser.zig:373-378` increments
`expr_depth` per nested expression and emits `panic: max expression recursion depth
exceeded` past 12. This bounds *nesting* (`f(g(h(x)))`, `if (c) if (c) …`), not chain
length. A chain `a0 + a1 + … + aN` is left-associative and parses at depth 1, so it is
unaffected by this cap.

**2. Semantic analyzer — expression *chain* ceiling.**
`semanticAnalyzerResolveExpr` (`sf/src/semantic_analyzer.zig`, 86 recursive call sites)
recurses per AST level at ~7.7 KB of C stack.

**Effective ceiling is a fixed 130 terms on every platform** — `SEMA_GUARD_MAX`
(`sf/src/semantic_analyzer.zig`), a depth guard added 2026-10-26. Past it the compiler
reports a clean `error[3077] expression nesting too deep for semantic analysis (limit 130)`
and emits no `.c`. The guard is a flat count, so it does **not** scale with available
stack. The table below is the *natural* stack-derived ceiling the guard is sized under;
on a large-stack platform the guard is what actually binds, not the stack.

| stack | natural ceiling (terms) | effective |
|---|---|---|
| 1 MB — Win9x MSVC default `/STACK` | ~139 | **130** (guard) |
| 2 MB — MinGW `SizeOfStackReserve` | ~270 | **130** (guard) |
| 8 MB — Linux default | ~1080 | **130** (guard) |

**The guard does not raise the ceiling** — it makes the failure honest instead of a
stack-overflow SIGSEGV. Phase 2.5 Task 2 executed both refinements: the cap was
re-measured and raised 128 -> 130 (1 MB wall ~139 terms; 131 trips with an 8-frame
margin) and the diagnostic moved to the limit-family `error[3077]`
(`ERR_3077_EXPR_NESTING_LIMIT`, outside the corpus `ICE_RE`), so a guard trip classifies
as FAIL rather than ICE. Raising it further still needs `semanticAnalyzerResolveExpr`
converted to the explicit continuation stack the lowerer uses (deferred; see the
semantic-analyzer limit note above).

**`error[3078]` is the mutable-capture reject, not a depth guard.**
`ERR_3078_MUTABLE_CAPTURE_UNSUPPORTED` fires level-0 (rc=2 / 0 `.c`) for a `|*item|`
capture whose iterable has no addressable element: a range iterable or a
non-variable array value reports `mutable for-item capture requires an addressable
element (a range or a copied array value has none)`, and a named capture over an
iterable with no resolvable element type reports `mutable for-item capture requires
an iterable with a resolvable element type`. It is outside the corpus `ICE_RE`.

**Real-world incidence is low.** Every real Z98 source in the repo was scanned — the
compiler itself, the std library, all `examples/`, all 1193 corpus dirs. Longest operator
chains: 35 ops (a synthetic repro fixture), 10 (`std_ecc.zig` curve polynomial multiplies),
9 (`lexer.zig` keyword-match `and` chains). Distribution: 1 line ≥20 ops, **0 lines ≥40**.
Production code tops out at ~10 terms, so the tightest platform (Win9x, 1 MB) has ~3.8x
headroom over real code.

**The lowerer is no longer depth-limited.** It was converted to an explicit continuation
stack in the iterative-lowering milestone (2026-10-26), so lowering no longer consumes C
stack per expression level. `repro/mi_matrix/emission_sibling_payload_xmod` (the original
70-term repro) compiles at 1 MB stack; it did not before.

### Calling convention (Win9x) — `extern "stdcall"` / `extern "cdecl"`  [added: 2026-09-14]

- **Surface:** a calling convention may be written on an extern fn declaration and on a function-pointer type — `extern "stdcall" fn(...) T`, `extern "cdecl" fn(...) T`, `extern "c" fn(...) T`; a bare `fn(...) T` is default cdecl. Accepted names: `"c"`/`"cdecl"` → cdecl (byte-identical to no string), `"stdcall"` → stdcall. Unknown → `error[3045]`; variadic `stdcall` → `error[3012]`; assigning a cross-convention fn-pointer → `error[3000]` (all clean: rc=2, 0 `.c`).
- **`Z98_STDCALL` macro** (emitted in `zig_compat.h`; single hand-edited source `sf/src/emit_support.zig`, `sf/src/include/zig_compat.h` is its generated snapshot): `__attribute__((stdcall))` on Win32 gcc, `__stdcall` on MSVC/Watcom, **empty on non-Windows** — so linux default-cdecl emission is byte-identical.
- **Option-B use-site-cast rule (operator ruling; SUPERSEDES the earlier forced-prototype rule):** do **NOT** emit a second convention-bearing prototype for a convention extern. The C header remains the **sole declaration source** (this is what lets `std_net` use the real `<winsock.h>`/`windows.h` prototypes without conflict). The convention rides on the fn type/LIR and is applied **at the use site** as a cast to the convention-qualified `FS_…` fn-pointer typedef in `zig_special_types.h`: `((zT_…_FS_…)MessageBoxA)(...)`. `typeRegistryGetOrCreateFn` marks the stdcall fn type used so the `FS_…` typedef is emitted. Standalone (non-header-covered) stdcall fixtures are **emission-inspection only** — the cast names the extern symbol, whose declaration is the C header's responsibility.
- **`std_net` Win32 externs** are migrated to `extern "stdcall"` (all 15 in `sf/src/std_net.zig`); every `std`-importing program's dump gains the `FS_…` typedefs + use-site casts (the re-export pulls `std_net` in).



### Compile + RUN a program (repro or example) with zig1  — VERIFIED RECIPE
```bash
# the gate compiler is the seed-built zig1; sf/build/out_release/zig1 is retired (cannot build)
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_seed
/tmp/z9_seed/zig1_5_clean --dump-c89 <FILE.zig> > /tmp/x.c 2>/tmp/x.err ; echo "dump rc=$?"
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x ; echo "gcc rc=$?"
/tmp/x ; echo "run rc=$?"
```
- You **must** link `sf/src/include/zig_runtime.c` AND `sf/src/include/zig_pal.c`, and pass
  `-I sf/src/include`. Missing any of these is the #1 cause of wasted turns.
- **Default safety mode is `-fsafe`.** A user program's emitted C includes the six check guards, so it
  differs from the `-ffast` compiler self-emission. Pass `-ffast` to `zig1` to reproduce pre-C89-AHEAD
  emitted C. No new link flags are needed — `pal_trap()` lives in the already-linked `zig_pal.c`.
- For **mud_server** add `sf/src/include/net_runtime.c` ONLY when building the pre-F6
  `examples/zig0/mud_server` bootstrap example — the migrated `examples/z98/mud_server`
  (std_net) links WITHOUT it (F6).
- For a **no-`main` repro** (compile-only, no link/run) use `gcc -m32 -std=c89 -c ... -o /dev/null`.
- **[updated: 2026-08-14] examples/repros now use bare `@import("std")`**, resolved
  via the search path: (1) importer's dir, (2) `-I`/`--lib-dir` dirs in CLI order, (3) the default
  install path `<exe_dir>/lib`, (4) CWD. To run a migrated example/repro you must first install the
  canonical std lib next to the compiler under test:
  `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_fmt.zig sf/src/std_arena.zig sf/src/std_net.zig sf/src/std_str.zig sf/src/std_mem.zig sf/src/std_math.zig sf/src/std_debug.zig sf/src/std_async.zig sf/src/std_bits.zig sf/src/std_os.zig sf/src/std_os_pal.zig sf/src/std_time.zig sf/src/std_time_pal.zig sf/src/std_page.zig sf/src/std_page_pal.zig sf/src/std_gpa.zig sf/src/std_pool.zig sf/src/std_buf.zig sf/src/std_file.zig sf/src/std_file_pal.zig sf/src/std_stdin.zig sf/src/std_stdin_pal.zig sf/src/std_stream.zig sf/src/std_crypto.zig sf/src/std_cipher.zig sf/src/std_ecc.zig sf/src/std_parse.zig sf/src/std_bencode.zig sf/src/std_map.zig sf/src/std_sort.zig sf/src/std_heap.zig sf/src/std_rle.zig sf/src/std_base64.zig sf/src/std_hex.zig sf/src/std_utf8.zig sf/src/std_http.zig sf/src/std_rand.zig sf/src/std_noise.zig sf/src/std_lz4.zig sf/src/std_zstd.zig sf/src/std_deflate.zig sf/src/std_num.zig sf/src/std_pathfind.zig sf/src/std_physics.zig sf/src/std_hpa.zig sf/src/std_asn1.zig sf/src/std_x509.zig sf/src/std_tls.zig sf/src/std_tls_io.zig sf/src/std_hpack.zig sf/src/std_http2.zig sf/src/std_wireguard.zig sf/src/std_tcpip.zig sf/src/std_gfx.zig sf/src/std_gfx_pal.zig sf/src/std_fold.zig sf/src/std_fft.zig <exe_dir>/lib/`
  (for `/tmp/fx_subfolder/zig1` that is `/tmp/fx_subfolder/lib/`). The canonical set
  includes `std_fmt.zig` (the print-formatting layer, auto-imported by the compiler
  whenever a `print` is lowered); a compiler whose `lib/` predates it can resolve a
  `print`-using program only when the std_fmt file is import-adjacent.
- A compiler ICE shows as `dump rc=134` (SIGABRT) with a `PANIC:` line — note the panic text may land
  on **stdout** (`/tmp/x.c`), not stderr.

**`--check` (sema-only; no emission).** `zig1 --check <FILE.zig>` runs import resolution →
semantic analysis → static analyzers → const-init and stops. It prints the banner and all
diagnostics, exits 0 when clean and 2 on errors; with `-W`/`--warn-error` a warning-only run
also exits 2. It truly ignores `-o`/`--output-dir`/`-d` (no output-path validation, no spill
redirect): no `.c`/`.h`/build scripts/`.zig1_lir.tmp` are written, while the earlier
`.zig1_*.tmp` scratch spills are left in the CWD. Use it for syntax/type checks without an
output directory.

### Windows (`-osw`) build — Win9x target; every `std` import emits `std_net`, so link `-lwsock32`  [updated: 2026-09-30]

On seed v89 the `std` re-export pulls `std_net` in, so **every** `@import("std")` program — even a stdio-only one such as `docs/sf/manuals/src/vol3/hello.z98` — emits **`std_net_*.c/.h`** and its mingw link **needs `-lwsock32`** (without it: `undefined reference to '_imp__recv@16'` / `'_imp__WSAStartup@8'`). This is consistent with the `std_net` use-site-cast note above; the earlier "EMITEMIT prunes `std_net` from a never-net `std` import" claim does not hold for the seed-v89 re-export.
- `net_prelude.h` is now **emitted into the output dir by the compiler** (self-contained emission, alongside `zig_compat.h`/`zig_runtime.h`/`zig_runtime.c`/`zig_pal.c`/`c_exit.c`); it resolves via `-I .` in the dump dir. It is no longer pulled from `sf/src/include`. (The pre-EMITEMIT header-location note is superseded: `net_prelude.h` is now emitted, while link-time `-lwsock32` is still needed by every `std` importer on seed v89.)
- **PROBE (re-measured 2026-09-30, seed v89):** never-net `repro/mi_matrix/std_import_bare_xmod` `-osw` **does** emit `std_net_*.c/.h`; mingw link **without** `-lwsock32` FAILS (`undefined reference to '_imp__recv@16'`), **with** rc=0. `docs/sf/manuals/src/vol3/hello.z98` (only `std.io.print`) behaves identically. Net `repro/mi_matrix/net_bind_startup_xmod` likewise emits `std_net` and needs `-lwsock32`.
- The emitted companion `build_target.sh` sets `LIBS="-lwsock32"` in its mingw branch for every `std`-importing program (the `.bat`/owc scripts likewise on `-osw`); prefer it:
```bash
cd /workspace/znineeight
# 1) emit the self-contained dir (default emission; no --dump-c89 needed)
timeout 120 <zig1> -osw -o <dump> <entry.zig>
# 2) build for windows (mingw gcc); the script links -lwsock32 (every std import emits std_net)
cd <dump> && timeout 120 sh build_target.sh mingw
```
- Harness wrapper: `scripts/win32_cross/cross_build_run.sh <zig1> <entry> <workdir> <exe> [-lwsock32]` — `cross_build_run.sh` links `-lwsock32` unconditionally (Amendment A0), so no extra flag is needed.

### GUI (`std_gfx`) no-CRT build + Xvfb/Wine smoke — `gfx_demo` / `z9edit` [added: 2026-10-27]

`std_gfx` is a std module pair (`sf/src/std_gfx.zig` + `std_gfx_pal.zig`) with a
Win9x window + windowed DirectDraw7 backend. GUI programs are built with the
no-CRT harness and three additive hooks:

```bash
cd /workspace/znineeight
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32" \
  bash scripts/win32_cross/cross_nocrt.sh <zig1> \
    examples/z98/z9edit/main.zig /tmp/z9edit/work /tmp/z9edit/z9edit.exe

bash scripts/win32_cross/check_win9x_imports.sh /tmp/z9edit/z9edit.exe 9x
# PASS: GDI32/USER32/KERNEL32, no DDRAW, no MSVCRT
```

- `DUMP_TARGET="-osw"` is required when the program imports `std_time`/`std_os`
  (z9edit does, for the 2 s ident-idle timer); without it the emitted C takes
  the POSIX branches and the mingw link fails on `gettimeofday`/`fork`. The
  env var is empty by default, so every pre-existing caller is unchanged.
- No extra C file is needed: DDraw is loaded dynamically from `ddraw.dll` and
  the window is polled (`GetClientRect`/`IsWindow`) instead of using a stdcall
  WndProc shim. `EXTRA_LIBS` adds GDI/User32 only (no `ddraw`).
- **OWC no-CRT is not a GUI build:** the emitted `build_owc_nocrt.bat` uses
  `option nodefaultlibs` and links only `kernel32,clib3r,winmm`, so `user32`
  and `gdi32` stay unresolved. For GUI programs use `build_owc_crt.bat`
  (verified static-CRT Win9x path), `build_target_crt.bat` (MSVC 6), or
  `build_mingw_crt.bat` (MinGW, needs `msvcrt.dll`); the no-CRT alternates
  remain valid for non-GUI console programs.
- The gate is `examples/z98/z9edit/tests/tier_edit_gui.sh` (build + import
  gate + compile RSS + Xvfb/Wine `--smoke` 2× save-byte golden + all three
  theme screenshots/save bytes + F2 cycle + bad-config fallback). `gfx_demo` has
  the layer-only `examples/z98/gfx_demo/tests/tier_gfx.sh` (also runs
  `--theme-test` for the memory-safe theme API).
- **Themes (P4-M4):** `std_gfx.Theme = { white, solarized, dark }`, default
  **white**; `gfxSetTheme` rebuilds the PAL brushes + glyph atlas (old theme
  kept on failure). z9edit reads `z9edit.ini` then `z9edit.cfg` (exe dir first,
  then CWD) for `theme=white|solarized|dark`, case-insensitive; unknown/missing/
  malformed -> white. `F2` cycles white -> solarized -> dark -> white for the
  session only (it never rewrites the config). A memory Gfx accepts
  `gfxSetTheme` and leaves the grid unchanged.
- **GDI fallback (Phase 2.5):** startup-only backend choice in `std_gfx_pal`.
  GDI is used when any DirectDraw open step fails, when
  `GetDeviceCaps(GetDC(NULL), BITSPIXEL) < 8` (16-color machines), or when
  `Z98_GFX_SOFTWARE=1`. The GDI path reuses the glyph atlas into a compatible
  client-sized back bitmap and presents with one window-DC `BitBlt` per frame;
  memory mode ignores the env var and never opens a backend. `gfxOpen` logs
  exactly one `gfx: backend=ddraw|gdi` line. Both GUI tiers run the same
  windowed/pixel sections in normal and forced-GDI modes. The automatic
  fallback and real 16-color fidelity are operator-hardware checks.
- **Visible startup errors:** `gfxShowError(title, msg)` uses `MessageBoxA` in
  a GUI build (live window or before the window opens) and stderr + the
  existing exit code in console/memory mode; `--smoke`/memory paths never call
  it, and the tiers never trigger the message box (timeout-guarded runs).

**Xvfb + Wine smoke recipe** (evidence, never a pixel gate):

```bash
Xvfb :77 -screen 0 1024x768x24 -nolisten tcp &
export DISPLAY=:77 WINEPREFIX=/tmp/z9edit/wineprefix WINEARCH=win32 WINEDEBUG=-all
wineboot -i
cd /tmp/z9edit && wine ./z9edit.exe --smoke in.z98 out.tmp &   # prints flushed READY
# wait for READY, then:
import -window root shot.png
wineserver -k; kill %1
cmp out.tmp edit_smoke.expected
```

The app paints a few frames before the scripted sequence so windowed DDraw has
presented (an immediate capture during the first idle can be black). Pixel
output is Wine/font-specific; the save-byte golden and exit 0 are the gates.
Real hardware is the operator's Win98 session.

**Measured on this test box (P4-M3, 2026-10-27):**

| Metric | Value | Notes |
|:--|--:|:--|
| `z9edit/main.zig` compile max RSS (`-osw --dump-c89`) | **7,012–7,304 KiB** | compile-only 16 MB gate |
| `z9edit` runtime RSS under Wine | **≈35.4 MiB** | evidence only, not gated (Wine overhead) |
| Open 100 KB (native core `bufLoad` + `identScan`) | **≈40 ms** | 3,414 lines |
| `--smoke` save bytes | md5 `974243c97df614039f01da3b86c67b3c` | 2× byte-identical |
| Xvfb screenshot | 1024×768, mean 0.0280 / 222 colors | evidence only |

**The 16 MB gate is compile-only.** Runtime RSS is not gated; the Wine number
is evidence, and real Win98 keystroke→screen/runtime RSS are **not measured**
here (operator hardware).


### Spill level switch (`-s<N>`) — RAM/I-O tradeoff  [updated: 2026-10-29]

`-s<N>` picks how many of the six spills live in RAM instead of the `.zig1_*.tmp` disk files.
Default `-s0` = all on disk. Deactivation order (oldest-spill-first): **S-AST → S-LIR → S-HASH →
S-RES → S-SIDE → S-EXTRA** — `-s1` moves AST to RAM, `-s2` also LIR, ... `-s6` = all RAM (no spill
files). S-EXTRA is the AST index-side `extra_children`/`extra_ranges` write-through pool pair
(`.zig1_extra_ec.tmp` / `.zig1_extra_er.tmp`). Higher `-s` = more RAM, less disk I/O; emission is
**byte-identical in every mode** (same data, different storage). **Current v137 spill ladder
(unchanged from v135/v136 — same fixed point `cf68f192…`; the numbers were measured on the v135
seed on 2026-11-05, not re-measured for v136 or v137):** `-s0` pool=18677K (18.2 MB, all disk);
`-s1` pool=50421K (49.2 MB); `-s2`/`-s3` pool=119477K (116.7 MB); `-s4` pool=123573K
(120.7 MB); `-s5` pool=126645K (123.7 MB); `-s6` pool=131765K (128.7 MB, all RAM). `-s0`
and `-s1` fit the 64 MB `-mm` default; `-s2`–`-s5` must be paired with `-mm128`, and
**`-s6` now needs `-mm160`** (its pool exceeds 128 MB; `-mm128` ICEs with rc=3). Historical v123
ladder (fixed point `2fc64ffe…`, measured 2026-10-27): `-s0` pool=18416K; `-s1` 51407K;
`-s2`/`-s3` 120400K; `-s4` 124496K; `-s5` 127568K; `-s6` 130640K. Historical (superseded): seed v89 ≈
20.6/57.4/…/130.6 MB pool; `553a39b4…` ≈ 13.8/33.1/70.0/73.0/74.0/77.0 MB;
M1 `21c957…` `-s0` pool=18871K. Range 0..6; bare
`-s` / non-digit / out-of-range (`-s7`) error rc=1. Per-level smoke: `.zig1_ast.tmp` absent at
`-s1`, `.zig1_lir.tmp` absent at `-s2`, ..., `.zig1_extra_ec.tmp`/`.zig1_extra_er.tmp` absent at
`-s6` — the spill-file ladder is the mode marker.

### Corpus gate (`repro/mi_matrix/*/main.zig` + the top-level `repro/` sweep) — classify by gcc EXIT CODE  [updated: 2026-09-02]
For each `repro/mi_matrix/*/main.zig`: run `zig1 --dump-c89 --output-dir DIR`, then compile
every emitted per-module `.c` file:
```bash
for f in DIR/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c "$f" -o /dev/null || exit 1; done
```
- **Classify by gcc EXIT CODE, never by empty-stderr** (warnings are nonzero-length but rc=0; a
  stderr-emptiness classifier gives false counts like 68/63).
- `dump` rc≥128 = CRASH; stderr matching `error\[(48|9001|3043)\]|AddressSanitizer` = ICE; gcc rc==0 = OK; else FAIL.
  (`error[3048]` file diagnostics and a clean undefined-module-member `error[3042]` reject with 0 `.c` are
  deliberately NOT in the ICE regex — they are frontend rejections, not internal compiler errors, so they
  classify as ordinary FAIL. Genuine ICE markers `error[48]`/`error[9001]`/`error[3043]`/`AddressSanitizer`
  stay ICE. The canonical classifier is `scripts/corpus/classify`.)

- **A repro that fails the frontend (dump emits 0 `.c` files with a `error[NNNN]` diagnostic) is a
  FAILURE — a real compiler gap — NOT "OK".** Do NOT count an empty output dir as OK. The per-file
  gcc loop above is only the emission check; a frontend error must be checked separately:
  ```bash
  if [ -z "$(ls DIR/*.c 2>/dev/null)" ]; then result=FAIL; fi   # 0 .c emitted = frontend gap
  ```
- **Green-guards are a distinct bucket**: a valid program CORRECTLY rejected by the frontend with the
  documented `error[3000]` diagnostic and 0 `.c` emitted is a green-guard (correct rejection matching
  the zig0 oracle), counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
  (See EXPECTED_FAIL.md "Green-guards" section.)


**Analyzer detection paths activated (2026-08-03):** null, lifetime, and doublefree
detection now route through `visitStatement` for full control-flow-aware analysis.
Single wrapper function `detectorVisit` (`sf/src/analyzer.zig:759`); per-pass
statement handler stored in `AnalyzerContext.on_stmt_cb` (`sf/src/analyzer.zig:383`).

### Byte-identical gate (mud / gol / lisp / json) — z98-only, self-consistency check

Gate entries (`examples/z98/` paths, NOT `examples/zig0/`). The gate compiler is the
**seed-built `zig1`** — the release path is retired (`sf/build/out_release/zig1` does not exist
and cannot build current `sf/src`; zig0 aborts), so build the seed first:
```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_seed
# <mode> = -fsafe (default) or -ffast; <ENTRY> = the examples/z98 gate program
/tmp/z9_seed/zig1_5_clean <mode> --dump-c89 <ENTRY> > /tmp/new.c
diff /tmp/ref.c /tmp/new.c   # compare against reference (ref.c captured at prior gate baseline)
/tmp/z9_seed/zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum   # compare to the 8-pin table below
```
This is the command that reproduces the 8-pin table below (the retired
`sf/build/out_release/zig1` path is NOT used by any current gate).

**Gate-program runtime outputs** (stable byte-identity reference; runtime behavior is the gate — dump byte-identity alone is not sufficient):
- `game_of_life` (100 generations) stdout: `fcbf7e7cead5082f0a8caadd5a8f0ff9`
- `lisp_interpreter_curr` `(+ 1 2)` stdout: `b3d9f8974da24ddbf9d389f3d7d97322`; canonical 12-line feed stdout: `96654b3910a54d8bb7ec3ddfc0f26c6a`
- `json_parser` stdout: `8bda3d5a1ec07d14a301bc343df32bf8`
- `mud_server` server stdout: `66c8f0abb926cca7baf9a0d1692ab318` / client bytes: `93147d0f0bbd983a9d844fea8b7a6fa7` (canonical session via `demo/session.sh`, rc 0)
- `scripts/closeout/verify_upgraded.sh` runs the whole battery and prints `CLOSEOUT OK` (A1-A5, B1-B7) on success.

**8-pin table (current; Phase 3.5 Task 12 re-baseline).** Measured with the seed-built compiler from the repo
root with relative entry paths:
`<seed-built zig1_5_clean> <mode> --dump-c89 <ENTRY> | md5sum`. Pin values are
**compiler-build dependent**; compare only same-build runs.

| Entry Path | `-fsafe` md5 (authoritative) | `-ffast` md5 |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `9691c2878564d61fe4272c3d3b5da253` | `fef5196eec58b82323bac3ce78c0e815` |
| `examples/z98/game_of_life/main.zig` | `0be513f90937621d47a331211bef9d67` | `b1f536d2905ce51d474d4167b2408f29` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `a2169c2c5b019504eaa9da0a851d8658` | `291a159925a7aa2f622bc1a87536a0e3` |
| `examples/z98/json_parser/main.zig` | `bbcd375f657d168df504d1f4ae06774e` | `219ddfff7095c84ab1dde2e82e3c50f0` |

- Self-consistency gate: compare current zig1 `--dump-c89` against a pre-captured reference .c file. If the reference .c is outdated (intentional baseline change), re-capture via `cp /tmp/new.c /tmp/ref.c`. Never compare against parent-zig1 output directly — parent builds may fail silently.
- Do **NOT** compare `zig1 --dump-c89` output against `zig0`'s C output. `zig0` emits a legacy bootstrap format that is byte-level incompatible with zig1.

### TCO gate recipes (examples/z98/tco_*) — [updated: 2026-08-03]

Self-recursion TCO: emitted C must contain a `z_bb_0:` label in the recursive fn + rebind assigns +
`goto z_bb_0;` back-edge (NO retained self `call`). Deep recursion (100k) must run with O(1) stack.

```bash
ZIG=${ZIG:-<out_dir>/zig1_5_clean}
for ex in tco_factorial tco_return_try tco_defer; do
  OUT=/tmp/tco_$ex
  rm -rf "$OUT" && mkdir -p "$OUT"
  "$ZIG" -fsafe -o "$OUT" examples/z98/$ex/main.zig || exit 1
  (cd "$OUT" && sh build_target.sh linux prog) || exit 1
  grep -R -n "goto z_bb_0;" "$OUT"/*.c || exit 1
  "$OUT/prog" || exit 1
done
```

Expected: each program prints its documented result and exits 0; the recursive
function has a `z_bb_0:` back-edge and no retained self-call. `tco_defer` fires
its defer exactly once at terminal return.



Gate: dump rc=0, gcc rc=0, run rc=0, `goto z_bb_0;` present, no self-call retained in the emitted
recursive fn. A compiler ICE shows as `dump rc=134` with a `PANIC:` line (may land on stdout).
`gcc -Wunused-label` warnings for `z_bb_0:` are expected and harmless.

**Consumer-guard note:** `hasOtherConsumers` (`lower.zig:4265`) scans all blocks before
`zeroCallCFG` to ensure no secondary consumers of the call result exist. Defensive — not
triggerable by current Z98 patterns. [updated: 2026-08-03]

### z_bb_0: labels in every function — [updated: 2026-08-03]

Since the TCO feature (F-S2/F-S3), **every** emitted function body contains a `z_bb_0:` label
(AMENDMENT 8). It is the entry-block label emitted by the `.loop_header` LirInst arm
(`c89_emit.zig:2775`), and it is the target of self-TCO `goto z_bb_0;` back-edges. It is EXPECTED:
- For self-recursive fns it is the live TCO jump target.
- For all other fns it is an unused label → `gcc -Wunused-label` warning (tolerated; the md5-gate
  baselines already include the label).

Do NOT treat `z_bb_0:` or the unused-label warning as a regression.

### Multi-Module Build — self-contained output dir  [updated: 2026-09-10]

`zig1 -o DIR <entry>` emits a **complete self-contained C89 tree** (needed-only module `.c`/`.h`
plus runtime/platform headers and runtime sources) and a companion `build_target.sh`. Build it:

```bash
zig1 -o DIR <entry>            # default emission (no --dump-c89 needed)
cd DIR
gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I . -c *.c
gcc -m32 -O0 *.o -o prog
# or simply:
sh DIR/build_target.sh         # (./DIR/build_target.sh after the first run)
```
- `-I .` is enough — the emitted dir carries its own runtime/platform headers (`zig_compat.h`,
  `zig_runtime.h`, and `net_prelude.h` iff `std_net` is emitted). No repo
  `-I sf/src/include` and no hand-listed `zig_runtime.c`/`zig_pal.c`/`c_exit.c` trio are needed;
  the emitted support sources are already in `DIR/*.c`.
- Run `gcc -c` INSIDE DIR — `gcc -c DIR/*.c` from outside writes the `.o` files to the caller's
  CWD, so the `*.o` link glob fails (`cannot find DIR/*.o`).
- The emitted `build_target.sh` uses an intentional **modules-then-runtime link order** (the
  compiler-enumerated module `.o` list first, runtime `.o` last). This deliberately differs from
  the seed recipe's plain alphabetical `*.o` glob and is not a bug.
- `--dump-c89` remains a debug alias: single-file to stdout without `-o`, or per-module `.c`/`.h`
  with `-o`.

### Editing source
Use `edit` (exact strings) or `fastedit` (line ranges, see AGENTS.md §X.7 — re-read the region
immediately before each edit; edit bottom-to-top). No `sed`/python/bulk transforms.

**HARD RULE — destructive git is PROHIBITED (every agent + controller).** Never run `git reset --hard`, `git reset --keep`, `git checkout -- <file>`, `git restore`, `git clean`, `git stash drop/clear`, force-push, or any other history-rewriting / work-discarding command. A 2026-10-08 `git reset --hard` silently destroyed uncommitted edits to two tracked ledger files. If you need to move off the current commit, **STOP and report to the controller — do not reset/clean.** Undo a mistaken commit with a NEW commit (or `git revert`), never by discarding state. `git commit --amend` on your OWN just-created commit is the only rewrite permitted, and only when nothing else is uncommitted. When in doubt: **stop and report, do not act.**

---


### Canonical Examples vs Legacy Oracle Examples

- **Canonical examples** live under `examples/z98/` and use current Z98 syntax
  (`@cInclude` + `extern fn`).
- `examples/zig0/` is legacy oracle material only; do not use it as the current
  build/example reference.
- **App entries (matrix 29/29):** `examples/z98/z9git` (local/`file://` +
  smart HTTP(S) clone/log/checkout, shallow/partial/resume; gate
  `tests/tier_git.sh`) and `examples/z98/z9zstddecomp` (`std_zstd` frame/dict
  CLI; gate `tests/tier_zstddecomp.sh`). `examples/z98/z9gb` is the Phase 4 P2
  DMG core (`--headless`, `--frames`, `--fb-out`, `--rom`, `--serial`,
  `--turbo`, `--mooneye`, `--save`, `--rtc-fixed`; MBC1/MBC3(+RTC)/MBC5, DMG
  CPU/PPU/timer/serial, battery saves; gates `tests/tier_dmg.sh --all` and
  `--gates`). Example READMEs carry the exact CLI, flags and exit codes.

### Compile + run an example with the seed-built compiler

```bash
ZIG=${ZIG:-<out_dir>/zig1_5_clean}
OUT=/tmp/z1ex
rm -rf "$OUT" && mkdir -p "$OUT"
"$ZIG" -fsafe -o "$OUT" examples/z98/json_parser/main.zig
(cd "$OUT" && sh build_target.sh linux prog)
```

For diagnostics:
```bash
"$ZIG" --markers --dump-c89 --output-dir /tmp/z1ex \
  examples/z98/mud_server/main.zig 2> /tmp/z1ex/markers.txt
```

`--dump-c89` requires a pre-created `--output-dir`. The emitted directory
contains its own build scripts and runtime support; prefer
`build_target.sh linux` over hand-assembling a gcc link line.

### Build mud_server

Use the same `-fsafe -o <out>` + `build_target.sh linux` recipe on
`examples/z98/mud_server/main.zig`. There is no current zig0 build cycle.

### Build z9gb (P2 DMG core, headless)

```bash
ZIG=${ZIG:-<out_dir>/zig1_5_clean}
OUT=/tmp/z9gb_p2
rm -rf "$OUT" && mkdir -p "$OUT"
"$ZIG" -ffast -o "$OUT" examples/z98/z9gb/main.zig
sh "$OUT/build_target.sh" linux "$OUT/z9gb"
"$OUT/z9gb" --headless --frames 1 --fb-out /tmp/z9gb_p2.fb
```

P2 emulates a DMG CPU, MMU/timer/serial, and scanline PPU with
MBC1/MBC3(+RTC)/MBC5 cartridges and battery `.sav`/`.rtc` saves. It does not
emulate CGB, APU, or a windowed/direct backend. Headless is the only platform.
The framebuffer dump is 92,160 bytes (160×144 little-endian RGB32).

```bash
# Inline tiers (fast + safe) and external hard gates; both must PASS:
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates
# Memory + three-run framebuffer determinism:
bash examples/z98/z9gb/tests/measure_rss.sh "$ZIG" /tmp/z9gb_p2_rss
```

External ROMs are not committed. Gate runners read `Z9GB_ROM_DIR`, else
`/tmp/z9gb_roms`, else `examples/z98/z9gb/testdata/roms`; populate the tree from
the pinned sources in `examples/z98/z9gb/testdata/roms/README.md` and verify
with `sha256sum -c .../testdata/roms/manifest.sha256`. P2 hard gates are Blargg
`cpu_instrs`/`instr_timing`/`mem_timing`, the 15-ROM Mooneye timer/MBC1/PPU/OAM
subset, and `dmg-acid2` (golden SHA-256
`c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083`). Blargg
`interrupt_time` is CGB-only and is not a P2 gate.


## Run tests

Current coverage is the stdlib fixture/crosscheck harness; `build_test.sh` is a
legacy, pre-existing broken path and is not the gate.

```bash
bash scripts/stdlib/verify_stdlib.sh <out_dir>/zig1_5_clean
bash scripts/stdlib/run_fixtures.sh <out_dir>/zig1_5_clean <fixture-dir>
bash scripts/stdlib/run_crosscheck.sh <out_dir>/zig1_5_clean <module>

# Phase 3.3 (HTTP/2) gates. Server-backed cases need Node 18+; when Node is
# absent they print SKIP and never claim PASS. The argless usage goldens are
# checked before any server starts.
bash scripts/stdlib/run_tls_alpn.sh <zig1>      # TLS 1.2/1.3 ALPN + prefer_chacha20
bash scripts/stdlib/run_async_io.sh <zig1> net  # coroutine socket helpers
bash scripts/stdlib/run_async_io.sh <zig1> tlsio # std_tls_io pumps
bash scripts/stdlib/run_http2.sh <zig1>         # TLS+ALPN h2 / h2c / flow / GOAWAY / RST
bash scripts/stdlib/run_phase33_safe.sh <zig1>  # Phase 3.3 fixtures under -fsafe
```


## Std-lib Runtime Gate

Runtime-behavior gate for the std-lib fixtures (spec
`docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md` §2). The
corpus classifier stays compile-only; this gate builds, links, RUNS, and
golden-diffs each fixture.

```bash
# full discovered std set (repro/mi_matrix/stdlib_*/ + stdlib_test/*/)
bash scripts/stdlib/run_fixtures.sh <seed-built-zig1_5_clean>

# restrict to explicit dirs (repo-relative or absolute)
bash scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_bits_table_xmod

# re-capture a fixture's goldens from the observed run (writes expected.txt +
# expected.rc and prints what it wrote; refuses an undeclared nonzero rc).
# ALWAYS review the observed output against the fixture's documented GREEN
# contract before committing a capture.
bash scripts/stdlib/run_fixtures.sh --capture <zig1> repro/mi_matrix/stdlib_bits_table_xmod

# closeout wrapper (full discovered set; nonzero + STDLIB GATE FAILED on any fail)
bash scripts/stdlib/verify_stdlib.sh <zig1>
```

Per fixture the harness: `zig1 -ffast -o <tmp> <entry>` → gcc every emitted
`.c` with the binding flag-set (`-m32 -std=c89 -O0 -Wall -Wno-long-long
-Wno-pointer-sign -Wno-implicit-function-declaration -I .`) → `sh
<tmp>/build_target.sh linux <prog>` → run 3× under `timeout 120` from a scratch
CWD. A fixture passes only when all 3 stdouts are byte-identical, stdout
`cmp`-equals `<dir>/expected.txt`, and rc equals `<dir>/expected.rc`
(whitespace-trimmed).

**Discovery pin + unpinned-dir guard + port guard (binding):**
- Discovery is `repro/mi_matrix/stdlib_*/` (any `stdlib_*` dir, not just
  `_xmod`) plus `stdlib_test/*/`. In discovery mode the harness asserts the
  discovered dir set EQUALS the committed baseline
  `scripts/stdlib/expected_dirs.txt` (339 dirs today: 329
  `repro/mi_matrix/stdlib_*` + 10 `stdlib_test/*`), so a dropped/renamed/added
  fixture FAILS the gate instead of silently shrinking coverage. Update the pin
  intentionally when a band adds/removes fixtures.
- Independently of the discovery pin, a guard ALWAYS fails
  `unpinned-stdlib-dir (<dir>)` if any `repro/mi_matrix/stdlib_*/` or
  `stdlib_test/*/` dir exists on disk that is not in the pin — even in explicit
  `<dir>` runs, and even for a dir with no resolvable entry (so a std-looking
  dir cannot silently escape the gate). Explicit `<dir>` runs skip only the
  discovery-pin set-equality check (targeted runs), not the guard.
- A fixture that binds TCP ports ships `<dir>/ports.txt` (one port per line,
  `#` comments allowed). The harness fails `PORT-IN-USE:<port>` if a LISTEN
  socket already exists on a declared port before the run.

**Fixture naming contract (binding):**
- Std fixtures live at `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the
  `_xmod` suffix is the corpus convention; discovery matches any `stdlib_*`
  dir). Workflow-level fixtures live under `stdlib_test/<name>/`.
- Every discovered fixture MUST have a committed `expected.txt` +
  `expected.rc` and be listed in `scripts/stdlib/expected_dirs.txt` (no silent
  skips).

**Golden convention (binding):**
- `<dir>/expected.txt` = exact stdout bytes; `<dir>/expected.rc` = expected exit code.
- A missing golden is a FAIL (no silent skips).
- Goldens are runtime-only (stdout+rc), never emitted-C bytes; captured from a
  known-good compiler at the plan baseline and re-captured only on an intentional
  behavior change.
- `--capture` writes the observed stdout+rc, but REFUSES a nonzero rc that is
  not already declared in an existing `expected.rc` (a crashing fixture is not
  silently frozen — a probe declares its `expected.rc` first).
- Capture only after confirming the observed output matches the fixture's
  documented GREEN contract in its `main.zig` header (never freeze a wrong output).
- Expected-failure probes (e.g. `stdlib_debug_defaulttrap_xmod` rc=134,
  `stdlib_async_waitfor_unregistered_xmod` rc=133) ship an `expected.rc` of the
  signal code and an empty `expected.txt` — the expected failure is itself asserted.
- `.gitignore` carries `!expected.txt` so the stdout goldens are committable source.

`scripts/closeout/verify_upgraded.sh` phase C runs this gate, so `CLOSEOUT OK`
requires it to pass.


## Debug with GDB on the seed-built compiler

The current compiler is `<out_dir>/zig1_5_clean` from
`scripts/seed/build_from_seed.sh`; `sf/build/out_release/zig1` is retired.

### Emit + build with debug symbols
```bash
ZIG=${ZIG:-<out_dir>/zig1_5_clean}
mkdir -p /tmp/z1dbg
"$ZIG" --dump-c89 --output-dir /tmp/z1dbg <entry.zig>
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /tmp/z1dbg /tmp/z1dbg/*.c -o /tmp/z1dbg/prog
```

### Find a function or line in generated C
```bash
grep -n "function_name_part" /tmp/z1dbg/semantic_analyzer_*.c | head
grep -n "keyword" /tmp/z1dbg/semantic_analyzer_*.c | head
```

Generated C has **no `#line` directives**. Break on `zF_*`/`zT_*` symbols or
the module file/line; use the debugger sidecar once available. Run
`gdb --args /tmp/z1dbg/prog ...` with the same arguments as the original
program.


### Filter output to variable values
```bash
gdb -batch ... 2>&1 | grep "^\$"
```

### Common breakpoints in resolveSwitchExpr (line numbers may shift after edits)
| Purpose | Approx C Line | Look for |
|---------|---------------|----------|
| Function entry | search for `static unsigned int zF_...manticAnalyzerResolveSwitchExpr` | Declaration line + 14 = unified init |
| Loop start | search for `__loop_0_start` in function body | `if (!(i < prongs.len))` |
| `unified = bt` (i==0) | ~2225 | `un_box[0] = bt;` or `unified = bt;` |
| `bt == unified` check | ~2227 | `bt == un_box[0]` or `bt == unified` |
| TYPE_VOID return | ~2267 | `return zC_..._TYPE_VOID;` |
| Loop exit | ~2275 | `__loop_0_end:` label |


### Diagnostic markers

Use `pal.markerWrite` / `pal.markerWriteInt` with a named or direct string
literal (string literals coerce to `[]const u8`; no zig0 workaround needed):

```zig
var m: []const u8 = "LABEL:n";
pal.markerWriteInt(m, val);
```

`palMarkerWriteInt` writes `LABEL:n<value>\n`.

### Marker extraction — use `grep -a`, NOT `strings`

`strings` strips null bytes and can silently drop entries. Capture with the
seed-built compiler:

```bash
ZIG=${ZIG:-<out_dir>/zig1_5_clean}
"$ZIG" --markers --dump-c89 --output-dir /tmp/z1mk \
  examples/z98/mud_server/main.zig 2> /tmp/markers.bin
grep -a "^PREFIX:" /tmp/markers.bin
```

Further filters:
```bash
grep -a -c "^PREFIX:" /tmp/markers.bin
grep -a "^PREFIX:" /tmp/markers.bin | sed 's/PREFIX: *//' | sort -n
grep -a "^IFST:\|^PBD:\|^EBLK:" /tmp/markers.bin
```

Current reference for the `mud_server` capture (seed v147; unchanged from the
Phase 3.5 Task 12 re-anchor): **4441 lines / 51346 B** (md5
`3fb045267ad401b112d5d7cd0f4816a2`).



### Common marker labels in sema.zig (all use markerWriteInt)

| Marker | Meaning | Example |
|--------|---------|---------|
| STX:N | resolveExpr entry (node_idx) | STX:N   453 |
| STX:K | resolveExpr entry (kind) | STX:K    24 |
| STX:R | resolveExpr entry (result type) | STX:R    10 |
| A4:N/K/R | STB stored (non-VOID result) | A4:N   453 |
| STB:N/R | STB confirmation | STB:N   453 |
| BLK:N | resolveStmtDepth block handler entry | BLK:N   727 |
| BLK:C | Block child count | BLK:C    11 |
| BCK:B | Block child — block node_idx | BCK:B   727 |
| BCK:I | Block child — index | BCK:I     0 |
| BCK:N | Block child — child node_idx | BCK:N   345 |
| BCK:K | Block child — child kind | BCK:K    30 |
| EBLK:N | resolveExpr block handler entry | EBLK:N  753 |
| IFST:N | if_stmt handler — if_stmt node | IFST:N  427 |
| IFST:C | if_stmt handler — child_1 node | IFST:C  426 |
| IFST:K | if_stmt handler — child_1 kind | IFST:K   79 |
| IFST:2 | if_stmt handler — child_2 node | IFST:2    0 |
| IFST:K2 | if_stmt handler — child_2 kind | IFST:K2   0 |
| WST:N | while_stmt handler — node_idx | WST:N   726 |
| WST:K | while_stmt handler — body kind | WST:K    76 |
| WST:D | while_stmt handler — depth | WST:D     3 |
| PBD:N | resolveSwitchExpr prong body node | PBD:N   753 |
| PBD:K | resolveSwitchExpr prong body kind | PBD:K    76 |


## Non-Issues: Warnings That Are NOT Bugs or Blockers

Symptoms that look like failures but are EXPECTED. Do NOT treat them as
regressions, do NOT open blockers for them, and do NOT spend investigation
time chasing them.

| Symptom | Why it is NOT a bug | What to actually check |
|---------|---------------------|------------------------|
| **game_of_life: literal ANSI / terminal-clear escape codes appear in the output** | `system("clear")` writes terminal escape sequences to stdout. When output is piped or captured (not a live TTY), those sequences show up as literal bytes. **Both zig0 AND zig1 behave this way** — it is terminal behavior, not codegen. | Whether the patterns (glider, blinker, block, beehive, LWSS) and the `Generation: N` lines render correctly. The presence of escape codes is irrelevant. |
| **gcc *warnings* (as opposed to errors)** | Build commands intentionally suppress noise via `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Any remaining gcc *warnings* do not affect correctness of the produced binary. | Only the `error:` count matters. Gate builds on `gcc ... 2>&1 \| grep -c "error:"` equal to `0`. |

**Comparison rule:** do not use zig0 as an oracle. Validate against the frozen
corpus classification, pinned goldens, and the seed/fixed-point closure; emitted
C is not byte-compatible with legacy zig0 output.

## Memory Recall (DEPRECATED — use mnemoria instead)

Deprecated memory recall is not functional anymore.
Use Mnemoria below.
## Memory Recall via Mnemoria

Memories live in `.opencode/memory/` (managed by mnemoria; do NOT edit manually).

### Query Commands

```bash
# Stats
mnemoria --path .opencode/memory stats

# Search by keyword (semantic)
mnemoria --path .opencode/memory search "keyword"

# Ask a question (RAG-based)
mnemoria --path .opencode/memory ask "What issues were found?"

# Recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Filter by agent (legacy memories stored under two agents):
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"
mnemoria --path .opencode/memory search --agent legacy-deleted "keyword"

# View timeline for specific agent
mnemoria --path .opencode/memory timeline --agent legacy-zni --limit 5
```

### Legacy Agent Names

| agent_name | Content | Count |
|---|---|---|
| `legacy-zni` | Active memories from pre-migration logfmt system | 1,498 entries |
| `legacy-deleted` | Previously deleted/forgotten memories, retained for reference | 431 entries |

### Type Mapping (logfmt types → mnemonia entry_type)

| logfmt type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Adding New Memories

```bash
mnemoria --path .opencode/memory add \
  --agent my-agent-name \
  --type discovery \
  --summary "Brief description" \
  "Detailed content here"
```

> **Full reference:** `docs/sf/AGENTS.md` Section 9 covers all conventions, agent naming, and usage patterns in detail.

> **Memory store location (IMPORTANT — do not create a stray store):** the real,
> populated memory database lives at **`.opencode/memory`** (~2,100+ entries).
> ALWAYS pass `--path .opencode/memory` (or `-p .opencode/memory`). Running
> `mnemoria` from the repo root without `--path` reads/creates a DIFFERENT, near-empty
> store at `./mnemoria/` (a stray build-mode artifact with only a handful of entries) —
> that is NOT the project memory. If a search returns very few results, you are on the
> wrong store: re-run with `--path .opencode/memory`, raise `--limit` (default 10 is
> low; try `--limit 40`+), and vary phrasings before concluding a memory is absent.

## Writing Plans & Plan-Mode Write Permissions

The **superpowers `writing-plans` skill** produces bite-sized, TDD, task-by-task
implementation plans. Load it via the `skill` tool when you have a spec/requirements
for a multi-step task, before touching code.

- **Where plans are saved:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`.
  Current plans are **tracked**; write them in build mode.
- `.opencode/plans/` is a legacy/untracked scratch area, not the current plan
  location.
- **Plan mode is READ-ONLY for tracked project/code state.** Memory writes via
  `mnemoria add` and `compress` are permitted; editing tracked files, committing,
  or other project/system mutations are not.
- **Do not re-litigate this.** If unsure, search
  `mnemoria --path .opencode/memory search "plan mode memory-tool allowed"`.


## Code Review via Superpowers Skill

Trigger the requesting-code-review skill when auditing completed changes.

**Manual review (in-session, plan mode):** `skill: requesting-code-review`
1. Obtain diff: `git diff` or `git diff BASE..HEAD`
2. Audit against template at `~/.cache/opencode/packages/superpowers@.../superpowers/skills/requesting-code-review/code-reviewer.md`
3. Checklist: plan alignment, code quality, architecture, edge cases, tests
4. Categorize: Critical / Important / Minor
5. Give clear verdict: Ready to commit / With fixes / Do not merge

**Subagent review (build mode):** Dispatch general-purpose subagent with `BASE_SHA`/`HEAD_SHA`, fill template from `code-reviewer.md`. Reviewer inspects `git diff BASE..HEAD`, returns Strengths + Issues + Assessment.

**Key principles:** Review early/often. Fix Critical before proceeding, Important before merge. Categorize by actual severity — not everything is Critical. Acknowledge strengths before listing issues.

### Review Hardening (MANDATORY)

- Deviations from contract = `BLOCKED` (never `DONE`); controller must STOP before any commit containing a deviation.
- Reviewer prompts: no "do not flag", no pre-judged severities, no shielding of findings.
- Every fix-task gate battery MUST include RUNTIME execution; compile-only gates forbidden.
- All Important/Critical review findings → fix subagent + re-review, or explicit operator ruling. No self-adjudication.
- Verification claims require evidence (file:line, output). Unevidenced = false.

**Full policy:** `docs/sf/AGENTS.md` §2.5 (post-incident, 2026-07-17).


### Tech Docs (as-built pipeline reference)
Location: sf/docs/tech_docs/
INDEX.md — master cross-reference (error→phase, function→file, marker→meaning)
00_shared_infra.md — Allocator, Interner, Diagnostics, PAL, Source Manager, utility modules
00_lexer_parser.md — Lexer, Parser, AST
01_import_resolution.md — Module graph & import resolution
02_symbol_registration.md — Symbol table registration
03_type_resolution.md — Type resolution & registry
04_comptime_eval.md — Compile-time evaluation
05_semantic_analysis.md — Semantic analysis (resolveExpr, resolveStmtDepth)
06_static_analyzers.md — Flow-sensitive static analyzers
07_lir_lowering.md — LIR lowering & control-flow flattening
08_c89_emission.md — C89 code emission & name mangling
09_pipeline_orchestration.md — Pipeline orchestration (main.zig, main_dump.zig)
10_c_runtime.md — C runtime layer (zig_runtime.c/h, zig_pal.c/h)
11_build_system.md — Build scripts & output isolation
