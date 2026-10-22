#!/usr/bin/env bash
# tier_tls.sh — Phase 1 M4/M5 integration tier for tls_demo.
#
# (a) local `openssl s_server` (committed test certs) happy paths: TLS 1.2
#     fallback (client offers 1.3+1.2, server -tls1_2) and TLS 1.3 with both
#     supported suites (AES-128-GCM, ChaCha20-Poly1305), each to an exact body.
#     Then the three fail-closed negatives: expired leaf
#     (`cert: CertificateExpired`), wrong host (`cert: HostnameMismatch`),
#     untrusted anchor (`cert: UnknownIssuer`). Local runs pin the cert clock
#     to 2030-01-01 so the tier is date-stable; a clock-overflow regression
#     asserts `tls: BadArgs` (not an -fsafe trap).
# (b) `Z98_NET=1` internet smoke: google.com + example.com return status 200
#     with bytes>0, plus www.microsoft.com/en-us/ as the RSA-PSS TLS 1.3 host.
#     With Z98_NET unset the smoke is a loud SKIP, never a pass.
# (c) RAM: run the local happy path under `ulimit -v 32768` and record the
#     `/usr/bin/time -v` peak RSS.
# (d) `-osw -fsafe` emit + mingw build + `check_win9x_imports.sh 9x`.
# Plus two-run byte checks of the 1.2 fallback and both 1.3 happy
# status/body/bytes lines.
#
# usage: tier_tls.sh
# Env: ZIG (default /tmp/m2_t4_v114_build/zig1_5_clean), OUT (/tmp/tier_tls)
#
# POSIX tooling: bash, openssl, /usr/bin/time, file, i686-w64-mingw32-*.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$DEMO_DIR/../../../.." && pwd)"
ZIG="${ZIG:-/tmp/m2_t4_v114_build/zig1_5_clean}"
OUT="${OUT:-/tmp/tier_tls}"
ENTRY="$DEMO_DIR/main.zig"
CERTS="$SCRIPT_DIR/certs"
STORE="$CERTS/store.bin"
BODY_TEXT="tls tier body"
BODY_LEN="$(printf '%s\n' "$BODY_TEXT" | wc -c | tr -d ' ')"
# Pin local cert validation to 2030-01-01 so the tier is independent of the
# current host date; the committed leaves are valid 2026..2036.
LOCAL_CLOCK=1893456000

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

for tool in "$ZIG" openssl /usr/bin/time file python3 i686-w64-mingw32-gcc \
            i686-w64-mingw32-objdump; do
    if [ ! -x "$tool" ] && ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required tool unavailable: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"
printf '%s\n' "$BODY_TEXT" >"$WORK/body.txt"

BIN="$OUT/tls_demo"
EMIT="$OUT/emit"
mkdir -p "$EMIT"

echo "== build tls_demo (linux, -fsafe) =="
if timeout 240 "$ZIG" -fsafe -o "$EMIT" "$ENTRY" >"$OUT/emit.log" 2>&1 \
   && sh "$EMIT/build_target.sh" linux "$BIN" >"$OUT/build.log" 2>&1 \
   && [ -x "$BIN" ]; then
    pass_case "linux -fsafe build produced tls_demo"
else
    fail_case "linux -fsafe build (see $OUT/emit.log / $OUT/build.log)"
    tail -20 "$OUT/emit.log" "$OUT/build.log" 2>/dev/null | sed 's/^/       /'
    echo "== tier_tls summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    echo "TIER_TLS FAIL"
    exit 1
fi

free_port() {
    python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

wait_port() {
    local port="$1" pid="$2" i=0
    while [ "$i" -lt 80 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then return 1; fi
        if bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            exec 3>&- 2>/dev/null || true
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    return 1
}

SERVER_PID=""
stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
}
trap stop_server EXIT INT TERM

run_local() {
    local cert="$1" key="$2" chain="$3" url_path="$4" log="$5" port
    port="$(free_port)"
    if [ -n "$chain" ]; then
        ( cd "$WORK" && exec openssl s_server -accept "$port" -tls1_2 \
            -cert "$CERTS/$cert" -key "$CERTS/$key" \
            -cert_chain "$CERTS/$chain" -WWW -quiet ) >"$log" 2>&1 &
    else
        ( cd "$WORK" && exec openssl s_server -accept "$port" -tls1_2 \
            -cert "$CERTS/$cert" -key "$CERTS/$key" -WWW -quiet ) >"$log" 2>&1 &
    fi
    SERVER_PID=$!
    if ! wait_port "$port" "$SERVER_PID"; then
        echo "__NO_SERVER__"
        return 1
    fi
    timeout 40 "$BIN" "https://localhost:$port/$url_path" "$STORE" "$LOCAL_CLOCK"
    local rc=$?
    stop_server
    return "$rc"
}

run_local13() {
    local suite="$1" log="$2" port
    port="$(free_port)"
    ( cd "$WORK" && exec openssl s_server -accept "$port" -tls1_3 \
        -ciphersuites "$suite" -cert "$CERTS/localhost.pem" \
        -key "$CERTS/localhost.key" -WWW -quiet ) >"$log" 2>&1 &
    SERVER_PID=$!
    if ! wait_port "$port" "$SERVER_PID"; then
        echo "__NO_SERVER__"
        return 1
    fi
    timeout 40 "$BIN" "https://localhost:$port/body.txt" "$STORE" "$LOCAL_CLOCK"
    local rc=$?
    stop_server
    return "$rc"
}

echo "== (a) local openssl s_server: TLS 1.2 fallback happy path (exact body) =="
run_local localhost.pem localhost.key "" "body.txt" "$OUT/srv_happy.log" \
    >"$OUT/happy.out" 2>"$OUT/happy.err"
HAPPY_RC=$?
if [ "$HAPPY_RC" -eq 0 ] \
   && [ "$(sed -n '1p' "$OUT/happy.out")" = "status=200" ] \
   && [ "$(sed -n '2p' "$OUT/happy.out")" = "$BODY_TEXT" ] \
   && grep -Eq "^tls_demo ok status=200 bytes=$BODY_LEN arena_peak=[0-9]+ rss_peak=[0-9]+ cpu_ms=[0-9]+$" "$OUT/happy.out"; then
    pass_case "local TLS 1.2 fallback fetch: status=200, exact body, bytes=$BODY_LEN"
else
    fail_case "local TLS 1.2 fallback fetch (rc=$HAPPY_RC; see $OUT/happy.out / $OUT/happy.err / $OUT/srv_happy.log)"
    sed 's/^/       /' "$OUT/happy.out" "$OUT/happy.err" 2>/dev/null | head -20
fi
HAPPY_LINE="$(grep '^tls_demo ok' "$OUT/happy.out" 2>/dev/null | sed 's/ arena_peak=.*//')"
sed -n '1,2p' "$OUT/happy.out" >"$OUT/happy.norm" 2>/dev/null
printf '%s\n' "$HAPPY_LINE" >>"$OUT/happy.norm"

echo "== (a) local negatives (fail closed) =="
neg_case() {
    local label="$1" cert="$2" key="$3" chain="$4" want="$5" tag="$6"
    run_local "$cert" "$key" "$chain" "body.txt" "$OUT/srv_$tag.log" \
        >"$OUT/$tag.out" 2>"$OUT/$tag.err"
    local rc=$?
    local got
    got="$(cat "$OUT/$tag.out" "$OUT/$tag.err" 2>/dev/null)"
    if [ "$rc" -ne 0 ] && [ "$got" = "$want" ]; then
        pass_case "$label -> $want"
    else
        fail_case "$label (rc=$rc, got '$got', want '$want')"
    fi
}
neg_case "expired leaf" expired.pem expired.key "" "cert: CertificateExpired" expired
neg_case "wrong host" wronghost.pem wronghost.key "" "cert: HostnameMismatch" wronghost
neg_case "untrusted anchor" untrusted.pem untrusted.key rogue-root.pem "cert: UnknownIssuer" untrusted

echo "== (a) clock-override overflow (no -fsafe trap) =="
timeout 10 "$BIN" "https://localhost:9/body.txt" "$STORE" \
    999999999999999999999999999999 >"$OUT/clock_overflow.out" 2>"$OUT/clock_overflow.err"
CLOCK_RC=$?
CLOCK_GOT="$(cat "$OUT/clock_overflow.out" "$OUT/clock_overflow.err" 2>/dev/null)"
if [ "$CLOCK_RC" -ne 0 ] && [ "$CLOCK_GOT" = "tls: BadArgs" ]; then
    pass_case "clock override overflow -> tls: BadArgs"
else
    fail_case "clock override overflow (rc=$CLOCK_RC, got '$CLOCK_GOT', want 'tls: BadArgs')"
fi

echo "== (a) happy determinism (2 runs) =="
run_local localhost.pem localhost.key "" "body.txt" "$OUT/srv_happy2.log" \
    >"$OUT/happy2.out" 2>"$OUT/happy2.err"
HAPPY2_RC=$?
HAPPY2_LINE="$(grep '^tls_demo ok' "$OUT/happy2.out" 2>/dev/null | sed 's/ arena_peak=.*//')"
sed -n '1,2p' "$OUT/happy2.out" >"$OUT/happy2.norm" 2>/dev/null
printf '%s\n' "$HAPPY2_LINE" >>"$OUT/happy2.norm"
if [ "$HAPPY2_RC" -eq 0 ] && cmp -s "$OUT/happy.norm" "$OUT/happy2.norm"; then
    pass_case "happy status/body/bytes identical 2x"
else
    fail_case "happy status/body/bytes differ (rc=$HAPPY2_RC)"
fi

echo "== (a) local openssl s_server: TLS 1.3 happy paths (both suites) =="
run13_case() {
    local label="$1" suite="$2" tag="$3"
    run_local13 "$suite" "$OUT/srv13_$tag.log" \
        >"$OUT/13_$tag.out" 2>"$OUT/13_$tag.err"
    local rc=$?
    if [ "$rc" -eq 0 ] \
       && [ "$(sed -n '1p' "$OUT/13_$tag.out")" = "status=200" ] \
       && [ "$(sed -n '2p' "$OUT/13_$tag.out")" = "$BODY_TEXT" ] \
       && grep -Eq "^tls_demo ok status=200 bytes=$BODY_LEN arena_peak=[0-9]+ rss_peak=[0-9]+ cpu_ms=[0-9]+$" "$OUT/13_$tag.out"; then
        pass_case "local TLS 1.3 $label fetch: status=200, exact body, bytes=$BODY_LEN"
    else
        fail_case "local TLS 1.3 $label fetch (rc=$rc; see $OUT/13_$tag.out / $OUT/13_$tag.err / $OUT/srv13_$tag.log)"
        sed 's/^/       /' "$OUT/13_$tag.out" "$OUT/13_$tag.err" 2>/dev/null | head -20
    fi
    local line
    line="$(grep '^tls_demo ok' "$OUT/13_$tag.out" 2>/dev/null | sed 's/ arena_peak=.*//')"
    sed -n '1,2p' "$OUT/13_$tag.out" >"$OUT/13_$tag.norm" 2>/dev/null
    printf '%s\n' "$line" >>"$OUT/13_$tag.norm"
}
run13_case "AES-128-GCM" TLS_AES_128_GCM_SHA256 aes
run13_case "ChaCha20-Poly1305" TLS_CHACHA20_POLY1305_SHA256 chacha

echo "== (a) TLS 1.3 happy determinism (2 runs each suite) =="
run13_repeat() {
    local label="$1" suite="$2" tag="$3"
    run_local13 "$suite" "$OUT/srv13_${tag}2.log" \
        >"$OUT/13_${tag}2.out" 2>"$OUT/13_${tag}2.err"
    local rc=$?
    local line
    line="$(grep '^tls_demo ok' "$OUT/13_${tag}2.out" 2>/dev/null | sed 's/ arena_peak=.*//')"
    sed -n '1,2p' "$OUT/13_${tag}2.out" >"$OUT/13_${tag}2.norm" 2>/dev/null
    printf '%s\n' "$line" >>"$OUT/13_${tag}2.norm"
    if [ "$rc" -eq 0 ] && cmp -s "$OUT/13_$tag.norm" "$OUT/13_${tag}2.norm"; then
        pass_case "TLS 1.3 $label status/body/bytes identical 2x"
    else
        fail_case "TLS 1.3 $label status/body/bytes differ (rc=$rc)"
    fi
}
run13_repeat "AES-128-GCM" TLS_AES_128_GCM_SHA256 aes
run13_repeat "ChaCha20-Poly1305" TLS_CHACHA20_POLY1305_SHA256 chacha

echo "== (b) internet smoke (Z98_NET) =="
if [ "${Z98_NET:-}" = "1" ]; then
    net_case() {
        local host="$1" tag="$2" path="${3:-/}"
        timeout 60 "$BIN" "https://$host$path" "$DEMO_DIR/ca_store.bin" \
            >"$OUT/net_$tag.out" 2>"$OUT/net_$tag.err"
        local rc=$?
        local hdr="$(sed -n '1p' "$OUT/net_$tag.out")"
        local res="$(grep '^tls_demo ok' "$OUT/net_$tag.out" 2>/dev/null)"
        local bytes
        bytes="$(printf '%s\n' "$res" | sed -n 's/.* bytes=\([0-9][0-9]*\) .*/\1/p')"
        if [ "$rc" -eq 0 ] && [ "$hdr" = "status=200" ] \
           && [ -n "$bytes" ] && [ "$bytes" -gt 0 ]; then
            pass_case "internet $host$path status=200 bytes=$bytes"
        else
            fail_case "internet $host$path (rc=$rc, '$hdr', '$res')"
            head -5 "$OUT/net_$tag.err" 2>/dev/null | sed 's/^/       /'
        fi
    }
    net_case www.google.com google
    net_case example.com example
    # RSA-2048 certificate, RSA-PSS CertificateVerify over TLS 1.3. The root
    # returns a bot-check 403 to a bare GET; /en-us/ returns the real page 200.
    net_case www.microsoft.com microsoft /en-us/
else
    skip_case "Z98_NET unset: internet smoke SKIPPED (set Z98_NET=1 to run google.com + example.com + microsoft.com)"
fi

echo "== (c) RAM: ulimit -v 32768 + /usr/bin/time -v peak =="
RAM_PORT="$(free_port)"
( cd "$WORK" && exec openssl s_server -accept "$RAM_PORT" -tls1_2 \
    -cert "$CERTS/localhost.pem" -key "$CERTS/localhost.key" -WWW -quiet ) \
    >"$OUT/srv_ram.log" 2>&1 &
SERVER_PID=$!
if wait_port "$RAM_PORT" "$SERVER_PID"; then
    ( ulimit -v 32768; /usr/bin/time -v "$BIN" \
        "https://localhost:$RAM_PORT/body.txt" "$STORE" "$LOCAL_CLOCK" ) \
        >"$OUT/ram.out" 2>"$OUT/ram.err"
    RAM_RC=$?
else
    RAM_RC=1
fi
stop_server
RAM_PEAK="$(sed -n 's/.*Maximum resident set size (kbytes): *\([0-9][0-9]*\).*/\1/p' "$OUT/ram.err" 2>/dev/null | tail -1)"
if [ "$RAM_RC" -eq 0 ] && [ -n "$RAM_PEAK" ] && [ "$RAM_PEAK" -gt 0 ]; then
    pass_case "RAM ceiling ok: /usr/bin/time peak RSS=${RAM_PEAK} kB (ulimit -v 32768)"
    echo "       peak_rss_kb=$RAM_PEAK"
else
    fail_case "RAM ceiling run (rc=$RAM_RC, peak='${RAM_PEAK:-none}')"
    head -10 "$OUT/ram.err" 2>/dev/null | sed 's/^/       /'
fi

echo "== (d) -osw emit/build + Win9x import gate =="
WIN_EMIT="$OUT/win_emit"
EXE="$OUT/tls_demo.exe"
mkdir -p "$WIN_EMIT"
OSW_OK=0
if timeout 240 "$ZIG" -fsafe -osw -o "$WIN_EMIT" "$ENTRY" >"$OUT/osw_emit.log" 2>&1 \
   && grep -q -- '-lwsock32' "$WIN_EMIT/build_target.sh" \
   && sh "$WIN_EMIT/build_target.sh" mingw "$EXE" >"$OUT/osw_build.log" 2>&1 \
   && [ -f "$EXE" ]; then
    OSW_OK=1
fi
if [ "$OSW_OK" -eq 1 ]; then
    pass_case "-osw emit + mingw build produced tls_demo.exe"
else
    fail_case "-osw emit/build (see $OUT/osw_emit.log / $OUT/osw_build.log)"
    tail -15 "$OUT/osw_emit.log" "$OUT/osw_build.log" 2>/dev/null | sed 's/^/       /'
fi

if [ -f "$EXE" ]; then
    FT="$(file "$EXE" 2>/dev/null)"
    case "$FT" in
        *PE32*Intel\ 80386*) pass_case "file: PE32 i386" ;;
        *) fail_case "file is not PE32 i386: ${FT:-<none>}" ;;
    esac
    if bash "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$EXE" 9x \
        >"$OUT/imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x whitelist PASS"
        grep -E '^DLL ' "$OUT/imports.log" | sed 's/^/       /'
    else
        fail_case "check_win9x_imports.sh 9x whitelist FAILED"
        tail -15 "$OUT/imports.log" 2>/dev/null | sed 's/^/       /'
    fi
else
    fail_case "tls_demo.exe not produced; import gate unassertable"
fi

echo
echo "== tier_tls summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_TLS FAIL"
    exit 1
fi
echo "TIER_TLS PASS"
exit 0
