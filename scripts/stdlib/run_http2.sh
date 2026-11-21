#!/usr/bin/env bash
# Local HTTP/2 integration gate (Phase 3.3 Task 8).
#
# usage: run_http2.sh <zig1>
#
# Emits repro/mi_matrix/stdlib_http2_tls_xmod and
# repro/mi_matrix/stdlib_http2_h2c_xmod under BOTH -ffast and the compiler
# default (-fsafe), builds each through the emitted build_target.sh, checks
# each argless usage golden, then starts an ephemeral Node 18+ server in
# $TMPDIR (server.js is never committed):
#   - http2.createSecureServer with ALPNProtocols ['h2','http/1.1'] and the
#     committed localhost certificate (TLS cases),
#   - http2.createServer for h2c prior knowledge (cleartext cases),
#   - a secure server offering only http/1.1 for the ALPN fallback case.
#
# Cases / expected stdout (both modes):
#   TLS       two concurrent GETs /a,/b + POST /echo
#   H2C       same multiplexing + POST echo over cleartext
#   FLOW      GET /large (256 KiB) with WINDOW_UPDATE flow control
#   GOAWAY    GET /goaway -> error.GoAway
#   RST       GET /rst -> error.StreamReset
#   FALLBACK  server selects http/1.1 -> http2OpenTls returns NotHttp2
#
# If Node is absent (or older than v18) the harness prints SKIP and exits 0;
# it never reports a false PASS.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

export Z98_SEED=1

if [ "$#" -lt 1 ]; then
    echo "usage: run_http2.sh <zig1>" >&2
    exit 2
fi

ZIG1="$1"
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not found"
    exit 0
fi
node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "${node_major:-0}" -lt 18 ]; then
    echo "SKIP: node v${node_major} < 18"
    exit 0
fi

TLS_DIR="repro/mi_matrix/stdlib_http2_tls_xmod"
H2C_DIR="repro/mi_matrix/stdlib_http2_h2c_xmod"
CERTS="$ROOT/examples/z98/demo/tls_demo/tests/certs"

tmp="$(mktemp -d /tmp/stdlib_http2.XXXXXX)"
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

pass_case() { pass=$((pass + 1)); echo "HTTP2 $1 PASS"; }
fail_case() {
    fail=$((fail + 1))
    FAILED+=("$1")
    echo "HTTP2 $1 FAIL" >&2
}

# emit_build <label> <dir> [compiler flags...]
emit_build() {
    local label="$1" dir="$2"; shift 2
    local out="$tmp/build/$label"
    mkdir -p "$out"
    if ! timeout 180 "$ZIG1" "$@" -o "$out" "$dir/main.zig" \
            >"$out/emit.log" 2>&1; then
        echo "  $label emit failed" >&2
        head -5 "$out/emit.log" 2>/dev/null | sed 's/^/    /' >&2 || true
        return 1
    fi
    if ! ls "$out"/*.c >/dev/null 2>&1; then
        echo "  $label emit produced no .c files" >&2
        return 1
    fi
    if ! ( cd "$out" && timeout 180 sh "$out/build_target.sh" linux "$out/prog" ) \
            >"$out/build.log" 2>&1 || [ ! -x "$out/prog" ]; then
        echo "  $label build failed" >&2
        head -5 "$out/build.log" 2>/dev/null | sed 's/^/    /' >&2 || true
        return 1
    fi
    return 0
}

echo "== emit + build fixtures (-ffast and -fsafe) =="
build_ok=1
emit_build tls.fast "$TLS_DIR" -ffast || build_ok=0
emit_build tls.safe "$TLS_DIR" || build_ok=0
emit_build h2c.fast "$H2C_DIR" -ffast || build_ok=0
emit_build h2c.safe "$H2C_DIR" || build_ok=0

echo "== argless usage goldens =="
usage_ok=1
for pair in "tls:$TLS_DIR" "h2c:$H2C_DIR"; do
    name="${pair%%:*}"
    dir="${pair#*:}"
    want_rc="$(tr -d '[:space:]' < "$dir/expected.rc")"
    for variant in fast safe; do
        prog="$tmp/build/$name.$variant/prog"
        [ -x "$prog" ] || { usage_ok=0; continue; }
        timeout 30 "$prog" >"$tmp/usage.out" 2>"$tmp/usage.err"
        rc=$?
        if [ "$rc" != "$want_rc" ] || ! cmp -s "$tmp/usage.out" "$dir/expected.txt"; then
            usage_ok=0
            echo "  $name/$variant argless rc=$rc want=$want_rc" >&2
            diff -u "$dir/expected.txt" "$tmp/usage.out" 2>/dev/null | head -6 | sed 's/^/    /' >&2 || true
        fi
    done
done
if [ "$usage_ok" -ne 1 ]; then
    fail_case "USAGE"
fi

if [ "$build_ok" -ne 1 ]; then
    stop_server
    echo "----------------------------------------"
    echo "run_http2: $pass PASS / $fail FAIL"
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi

echo "== ephemeral Node HTTP/2 server =="
cat >"$tmp/server.js" <<'JS'
const http2 = require("http2");
const https = require("https");
const fs = require("fs");
const path = require("path");

const readyDir = process.env.H2_READY;
const key = fs.readFileSync(process.env.H2_KEY);
const cert = fs.readFileSync(process.env.H2_CERT);

const LARGE = Buffer.allocUnsafe(256 * 1024);
for (let i = 0; i < LARGE.length; i++) LARGE[i] = i & 0xff;

function onStream(stream, headers) {
    stream.on("error", () => {});
    const p = (headers[":path"] || "/").split("?")[0];
    if (p === "/a") {
        stream.respond({ ":status": 200, "content-length": 5 });
        stream.end("alpha");
        return;
    }
    if (p === "/b") {
        stream.respond({ ":status": 200, "content-length": 5 });
        stream.end("bravo");
        return;
    }
    if (p === "/large") {
        stream.respond({ ":status": 200, "content-length": LARGE.length });
        stream.end(LARGE);
        return;
    }
    if (p === "/echo") {
        const chunks = [];
        stream.on("data", (d) => chunks.push(d));
        stream.on("end", () => {
            const body = Buffer.concat(chunks);
            stream.respond({ ":status": 200, "content-length": body.length });
            stream.end(body);
        });
        return;
    }
    if (p === "/rst") {
        stream.close(http2.constants.NGHTTP2_INTERNAL_ERROR);
        return;
    }
    if (p === "/goaway") {
        // Node clamps GOAWAY's last-stream-id up to the highest stream it has
        // already received, so a GOAWAY alone leaves this stream open. The
        // follow-up RST closes it; the client still reports error.GoAway
        // because the connection-level GOAWAY arrived first.
        try { stream.session.goaway(0, 0); } catch (e) {}
        stream.close(http2.constants.NGHTTP2_CANCEL);
        return;
    }
    stream.respond({ ":status": 404 });
    stream.end("nope");
}

function onHttp1(req, res) {
    try {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("http1.1");
    } catch (e) {}
}

function writePort(name, srv) {
    fs.writeFileSync(path.join(readyDir, name), String(srv.address().port));
}

const tlsSrv = http2.createSecureServer({
    key: key,
    cert: cert,
    ALPNProtocols: ["h2", "http/1.1"],
});
tlsSrv.on("stream", onStream);
tlsSrv.on("error", () => {});
tlsSrv.on("tlsClientError", () => {});
tlsSrv.on("sessionError", () => {});
tlsSrv.listen(0, "127.0.0.1", () => writePort("tls.port", tlsSrv));

const h2cSrv = http2.createServer();
h2cSrv.on("stream", onStream);
h2cSrv.on("error", () => {});
h2cSrv.on("sessionError", () => {});
h2cSrv.listen(0, "127.0.0.1", () => writePort("h2c.port", h2cSrv));

const fbSrv = https.createServer({
    key: key,
    cert: cert,
    ALPNProtocols: ["http/1.1"],
}, onHttp1);
fbSrv.on("error", () => {});
fbSrv.on("tlsClientError", () => {});
fbSrv.listen(0, "127.0.0.1", () => writePort("fallback.port", fbSrv));


process.on("SIGTERM", () => { tlsSrv.close(); h2cSrv.close(); fbSrv.close(); process.exit(0); });
process.on("SIGINT", () => { tlsSrv.close(); h2cSrv.close(); fbSrv.close(); process.exit(0); });
JS

ready="$tmp/ready"
mkdir -p "$ready"
H2_READY="$ready" H2_KEY="$CERTS/localhost.key" H2_CERT="$CERTS/localhost.pem" \
    node "$tmp/server.js" >"$tmp/server.log" 2>&1 &
SERVER_PID=$!

i=0
while [ "$i" -lt 100 ]; do
    if [ -s "$ready/tls.port" ] && [ -s "$ready/h2c.port" ] && [ -s "$ready/fallback.port" ]; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    i=$((i + 1))
    sleep 0.1
done
if [ ! -s "$ready/tls.port" ] || [ ! -s "$ready/h2c.port" ] || [ ! -s "$ready/fallback.port" ]; then
    echo "  server start failed (see $tmp/server.log)" >&2
    head -8 "$tmp/server.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    for label in TLS H2C FLOW GOAWAY RST FALLBACK; do fail_case "$label"; done
    stop_server
    echo "----------------------------------------"
    echo "run_http2: $pass PASS / $fail FAIL"
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi

read -r tls_port <"$ready/tls.port"
read -r h2c_port <"$ready/h2c.port"
read -r fb_port <"$ready/fallback.port"
TLS_URL="https://localhost:$tls_port"
H2C_URL="http://127.0.0.1:$h2c_port"
FALLBACK_URL="https://localhost:$fb_port"

# check_mode <fixture> <mode> <url> <want> -> 0 when both variants match.
check_mode() {
    local fixture="$1" mode="$2" url="$3" want="$4"
    local ok=1
    for variant in fast safe; do
        local prog="$tmp/build/$fixture.$variant/prog"
        timeout 40 "$prog" "$url" "$mode" >"$tmp/run.out" 2>"$tmp/run.err"
        local rc=$?
        local got
        got="$(tr -d '\r' <"$tmp/run.out")"
        if [ "$rc" -ne 0 ] || [ "$got" != "$want" ]; then
            ok=0
            echo "  $fixture/$mode/$variant rc=$rc got='$got' want='$want'" >&2
            head -3 "$tmp/run.err" 2>/dev/null | sed 's/^/    /' >&2 || true
        fi
    done
    [ "$ok" -eq 1 ]
}

check_case() {
    local label="$1" fixture="$2" mode="$3" url="$4" want="$5"
    if check_mode "$fixture" "$mode" "$url" "$want"; then
        pass_case "$label"
    else
        fail_case "$label"
    fi
}

WANT_MUX=$'a=200:alpha\nb=200:bravo'
WANT_ECHO='echo=ping/echo/body'

if check_mode tls mux "$TLS_URL" "$WANT_MUX" && check_mode tls echo "$TLS_URL" "$WANT_ECHO"; then
    pass_case "TLS"
else
    fail_case "TLS"
fi

if check_mode h2c mux "$H2C_URL" "$WANT_MUX" && check_mode h2c echo "$H2C_URL" "$WANT_ECHO"; then
    pass_case "H2C"
else
    fail_case "H2C"
fi

check_case "FLOW" tls flow "$TLS_URL" "large=262144"
check_case "GOAWAY" tls goaway "$TLS_URL" "goaway=goaway"
check_case "RST" tls rst "$TLS_URL" "rst=stream_reset"
check_case "FALLBACK" tls alpn11 "$FALLBACK_URL" "fallback=not_http2"

stop_server

echo "----------------------------------------"
echo "run_http2: $pass PASS / $fail FAIL"
if [ "$fail" -ne 0 ]; then
    printf 'failed: %s\n' "${FAILED[*]}" >&2
    exit 1
fi
exit 0
