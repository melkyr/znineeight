#!/usr/bin/env bash
# Coroutine socket-I/O gate for the Phase 3.3 std fixtures.
#
# usage: run_async_io.sh <zig1> [net]
#
# `net` (default) emits repro/mi_matrix/stdlib_net_async_xmod under BOTH -ffast
# and -fsafe (default), builds each through the emitted build_target.sh, checks
# the argless usage golden, then starts a local Node TCP echo server and runs
# each binary against it. Expected: stdout `async=hello`, rc 0, both modes.
#
# Task 3 adds the `tlsio` mode (stdlib_tls_io_xmod); this script is the shared
# driver home for both modes.
#
# If Node is unavailable the server-backed checks print SKIP and never claim
# PASS.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

export Z98_SEED=1

if [ "$#" -lt 1 ]; then
    echo "usage: run_async_io.sh <zig1> [net]" >&2
    exit 2
fi

ZIG1="$1"
MODE="${2:-net}"
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

case "$MODE" in
    net)
        DIR="repro/mi_matrix/stdlib_net_async_xmod"
        WANT="async=hello"
        ;;
    *)
        echo "error: unknown mode '$MODE' (supported: net)" >&2
        exit 2
        ;;
esac

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP - node unavailable (server-backed fixture not run)"
    exit 0
fi

tmp="$(mktemp -d /tmp/stdlib_async_io.XXXXXX)"
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

# emit_build <label> [compiler flags...]
# Emits and builds the fixture into $tmp/<label>/prog. Returns nonzero on error.
emit_build() {
    local label="$1"; shift
    local out="$tmp/$label"
    mkdir -p "$out"
    if ! timeout 180 "$ZIG1" "$@" -o "$out" "$DIR/main.zig" \
            >"$out/emit.log" 2>&1; then
        echo "FAIL - $label emit" >&2
        head -5 "$out/emit.log" 2>/dev/null | sed 's/^/    /' >&2 || true
        return 1
    fi
    if ! ls "$out"/*.c >/dev/null 2>&1; then
        echo "FAIL - $label emit produced no .c files" >&2
        return 1
    fi
    if ! ( cd "$out" && timeout 180 sh "$out/build_target.sh" linux "$out/prog" ) \
            >"$out/build.log" 2>&1 || [ ! -x "$out/prog" ]; then
        echo "FAIL - $label build" >&2
        head -5 "$out/build.log" 2>/dev/null | sed 's/^/    /' >&2 || true
        return 1
    fi
    return 0
}

echo "== emit + build $DIR (-ffast and -fsafe) =="
emit_build fast -ffast || fail_case "$MODE emit+build (-ffast)"
emit_build safe || fail_case "$MODE emit+build (-fsafe)"

if [ "$fail" -ne 0 ]; then
    echo "----------------------------------------"
    echo "run_async_io: $pass PASS / $fail FAIL"
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi

echo "== argless usage golden =="
want_rc="$(tr -d '[:space:]' < "$DIR/expected.rc")"
timeout 30 "$tmp/fast/prog" >"$tmp/usage.out" 2>"$tmp/usage.err"
usage_rc=$?
if [ "$usage_rc" = "$want_rc" ] && cmp -s "$tmp/usage.out" "$DIR/expected.txt"; then
    pass_case "argless usage (rc $usage_rc)"
else
    fail_case "argless usage (rc=$usage_rc want=$want_rc)"
    diff -u "$DIR/expected.txt" "$tmp/usage.out" 2>/dev/null | head -10 | sed 's/^/    /' >&2 || true
fi

echo "== local Node TCP echo server =="
cat >"$tmp/echo.js" <<'JS'
const net = require("net");
const fs = require("fs");
const ready = process.env.ECHO_READY;
const srv = net.createServer((c) => {
    c.on("error", () => {});
    c.pipe(c);
});
srv.listen(0, "127.0.0.1", () => {
    fs.writeFileSync(ready, String(srv.address().port));
});
process.on("SIGTERM", () => { srv.close(); process.exit(0); });
process.on("SIGINT", () => { srv.close(); process.exit(0); });
JS

ready="$tmp/echo.ready"
rm -f "$ready"
ECHO_READY="$ready" node "$tmp/echo.js" >"$tmp/server.log" 2>&1 &
SERVER_PID=$!

i=0
while [ "$i" -lt 50 ]; do
    if [ -s "$ready" ]; then break; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    i=$((i + 1))
    sleep 0.1
done
if [ ! -s "$ready" ]; then
    fail_case "$MODE server start (see $tmp/server.log)"
    head -5 "$tmp/server.log" 2>/dev/null | sed 's/^/    /' >&2 || true
else
    read -r port <"$ready"
    for label in fast safe; do
        timeout 40 "$tmp/$label/prog" "127.0.0.1:$port" \
            >"$tmp/$label/run.out" 2>"$tmp/$label/run.err"
        rc=$?
        got="$(tr -d '\r' < "$tmp/$label/run.out")"
        if [ "$rc" -eq 0 ] && [ "$got" = "$WANT" ]; then
            pass_case "$MODE $label -> $WANT"
        else
            fail_case "$MODE $label (rc=$rc got='$got' want='$WANT')"
            head -3 "$tmp/$label/run.err" 2>/dev/null | sed 's/^/    /' >&2 || true
        fi
    done
fi

stop_server

echo "----------------------------------------"
echo "run_async_io: $pass PASS / $fail FAIL"
if [ "$fail" -ne 0 ]; then
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi
exit 0
