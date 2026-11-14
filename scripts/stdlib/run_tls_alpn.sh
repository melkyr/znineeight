#!/usr/bin/env bash
# ALPN negotiation gate for std_tls (Phase 3.3, task 1).
#
# usage: run_tls_alpn.sh <zig1>
#
# Emits repro/mi_matrix/stdlib_tls_alpn_xmod with -ffast, builds it through the
# emitted build_target.sh, checks its argless usage golden, then drives real
# `openssl s_server` instances (repo localhost certificate) for the six ALPN
# modes and asserts the exact selected protocol.
#
# Modes / expectations:
#   1.2h2       -tls1_2 -alpn h2,http/1.1                       -> alpn=h2
#   1.3h2       -tls1_3 -alpn h2,http/1.1                       -> alpn=h2
#   1.3http11   -tls1_3 -alpn http/1.1                          -> alpn=http11
#   1.3none     -tls1_3 (no ALPN)                               -> alpn=none
#   1.3chacha   -tls1_3 -ciphersuites TLS_CHACHA20_POLY1305_SHA256 -alpn h2,http/1.1
#               (fixture also asserts 0x1303-first suite / x25519-first group)
#   1.3badalpn  -tls1_3 -alpn foo (no overlap)                  -> alpn=none
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

export Z98_SEED=1

if [ "$#" -lt 1 ]; then
    echo "usage: run_tls_alpn.sh <zig1>" >&2
    exit 2
fi

ZIG1="$1"
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

DIR="repro/mi_matrix/stdlib_tls_alpn_xmod"
CERTS="$ROOT/examples/z98/demo/tls_demo/tests/certs"

for tool in openssl python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool unavailable: $tool" >&2
        exit 2
    }
done

tmp="$(mktemp -d /tmp/stdlib_tls_alpn.XXXXXX)"

SERVER_PID=""
stop_server() {
    if [ -n "${SERVER_PID:-}" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
}
cleanup() {
    stop_server
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

pass=0
fail=0
FAILED=()

pass_case() { pass=$((pass + 1)); echo "PASS - $1"; }
fail_case() {
    fail=$((fail + 1))
    FAILED+=("$1")
    echo "FAIL - $1" >&2
}

echo "== emit + build stdlib_tls_alpn_xmod (-ffast) =="
mkdir -p "$tmp/emit"
if ! timeout 180 "$ZIG1" -ffast -o "$tmp/emit" "$DIR/main.zig" \
        >"$tmp/emit.log" 2>&1; then
    echo "FAIL - emit" >&2
    cat "$tmp/emit.log" >&2
    echo "----------------------------------------"
    echo "run_tls_alpn: 0 PASS / 1 FAIL"
    exit 1
fi
if ! ls "$tmp/emit"/*.c >/dev/null 2>&1; then
    echo "FAIL - emit produced no .c files" >&2
    echo "run_tls_alpn: 0 PASS / 1 FAIL"
    exit 1
fi
if ! ( cd "$tmp/emit" && timeout 180 sh "$tmp/emit/build_target.sh" linux "$tmp/prog" ) \
        >"$tmp/build.log" 2>&1 || [ ! -x "$tmp/prog" ]; then
    echo "FAIL - build" >&2
    cat "$tmp/build.log" >&2
    echo "----------------------------------------"
    echo "run_tls_alpn: 0 PASS / 1 FAIL"
    exit 1
fi

echo "== argless usage golden =="
want_rc="$(tr -d '[:space:]' < "$DIR/expected.rc")"
timeout 30 "$tmp/prog" >"$tmp/usage.out" 2>"$tmp/usage.err"
usage_rc=$?
if [ "$usage_rc" = "$want_rc" ] && cmp -s "$tmp/usage.out" "$DIR/expected.txt"; then
    pass_case "argless usage (rc $usage_rc)"
else
    fail_case "argless usage (rc=$usage_rc want=$want_rc)"
    diff -u "$DIR/expected.txt" "$tmp/usage.out" 2>/dev/null | head -10 | sed 's/^/    /' >&2 || true
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
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    return 1
}

run_mode() {
    local mode="$1" srv_args="$2" want="$3"
    local port srv_log="$tmp/srv_$mode.log" got rc fifo="$tmp/srv_$mode.fifo"
    port="$(free_port)"
    # s_server reads commands from stdin and shuts down on EOF. Give it a FIFO
    # held open read/write so inherited /dev/null stdin cannot race the accept.
    rm -f "$fifo"
    mkfifo "$fifo"
    exec 8<>"$fifo"
    # shellcheck disable=SC2086
    ( exec openssl s_server -accept "$port" \
        -cert "$CERTS/localhost.pem" -key "$CERTS/localhost.key" \
        -quiet $srv_args ) <"$fifo" >"$srv_log" 2>&1 &
    SERVER_PID=$!
    if ! wait_port "$port" "$SERVER_PID"; then
        fail_case "$mode server start (see $srv_log)"
        stop_server
        exec 8>&-
        rm -f "$fifo"
        return
    fi
    timeout 40 "$tmp/prog" "localhost:$port" "$mode" \
        >"$tmp/$mode.out" 2>"$tmp/$mode.err"
    rc=$?
    stop_server
    exec 8>&-
    rm -f "$fifo"
    got="$(tr -d '\r' < "$tmp/$mode.out")"
    if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
        pass_case "$mode -> $want"
    else
        fail_case "$mode (rc=$rc got='$got' want='$want')"
        head -3 "$tmp/$mode.err" 2>/dev/null | sed 's/^/    /' >&2 || true
        head -3 "$srv_log" 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
}

echo "== ALPN modes (real openssl s_server) =="
run_mode "1.2h2" "-tls1_2 -alpn h2,http/1.1" "alpn=h2"
run_mode "1.3h2" "-tls1_3 -alpn h2,http/1.1" "alpn=h2"
run_mode "1.3http11" "-tls1_3 -alpn http/1.1" "alpn=http11"
run_mode "1.3none" "-tls1_3" "alpn=none"
run_mode "1.3chacha" "-tls1_3 -ciphersuites TLS_CHACHA20_POLY1305_SHA256 -alpn h2,http/1.1" "alpn=h2"
run_mode "1.3badalpn" "-tls1_3 -alpn foo" "alpn=none"

echo "----------------------------------------"
echo "run_tls_alpn: $pass PASS / $fail FAIL"
if [ "$fail" -ne 0 ]; then
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi
exit 0
