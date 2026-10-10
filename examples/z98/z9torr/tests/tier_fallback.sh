#!/bin/sh
# tier_fallback.sh — z9torr M4.1 Task 5 gate: encrypted-first plaintext fallback.
#
# Proves the binding fallback policy A end-to-end and NON-VACUOUSLY: the client
# is encrypted-first, so against a PLAINTEXT-ONLY peer its MSE/PE probe must
# fail, after which it reconnects and completes a real plaintext BitTorrent
# handshake + byte-verified download.
#
# The peer is the existing one-shot plaintext `tools/mock_peer` (not MSE-capable,
# so the encrypted path cannot succeed). Because it accepts exactly ONE
# connection, it is kept alive behind a restart wrapper that reloads it after a
# deliberate gap (`Z9TORR_FB_GAP_MS`, default 200 ms) — i.e. the peer is briefly
# UNreachable exactly when the client falls back. The fallback must therefore
# keep retrying for its ~3 s window instead of giving up after a few fast-failed
# connects.
#
# Assertions (all non-vacuous):
#   - the client attempted MSE first (log: `mse stage=ya` and `mse-fail`);
#   - the fallback path was actually used (log: `handshake ok plain`);
#   - the encrypted path was NOT used against the plaintext mock (no
#     `handshake ok enc`);
#   - exit 0 and a byte-verified output (sha1 == the fixture golden).
#
# PRE-FIX behaviour (M4.1 Task 4 regression, now fixed): `plainReconnect` carried
# a fixed `attempt < 100` cap; once Task 4 replaced its 20 ms `sleepMs` pause with
# a cooperative `@asyncSuspend`, those 100 attempts exhausted in microseconds, so
# with any restart gap the client logged `reconnect-fail` and exited 4 with 0
# bytes — the fallback "never succeeded". With the wall-clock-throttled retry loop
# it now honours the full window and this tier is GREEN.
#
# POSIX sh. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_fallback}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

# The fixture announces at 127.0.0.1:6969, so the tracker must use that port.
P_TRACKER="${Z9TORR_FB_TRACKER:-6969}"
P_PEER="${Z9TORR_FB_PEER:-6978}"
GAP_MS="${Z9TORR_FB_GAP_MS:-200}"
GAP_S="$(echo "$GAP_MS" | awk '{ printf "%.3f", $1 / 1000 }')"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

if port_busy "$P_TRACKER"; then
    echo "FAIL: declared tracker port already in use (tracker=$P_TRACKER)"
    exit 1
fi
if port_busy "$P_PEER"; then
    echo "FAIL: declared peer port already in use (peer=$P_PEER)"
    exit 1
fi

TR_PID=""
PEER_PID=""
cleanup() {
    [ -n "$PEER_PID" ] && kill "$PEER_PID" 2>/dev/null
    [ -n "$TR_PID" ] && kill "$TR_PID" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

# --- build (binding recipe) -------------------------------------------------
build_bin() {
    _dir="$1"; _entry="$2"; _name="$3"
    mkdir -p "$_dir"
    if ! timeout 120 "$ZIG" -ffast -o "$_dir" "$_entry" >"$_dir/zig.log" 2>&1; then
        echo "FAIL: zig compile $_name (see $_dir/zig.log)"
        return 1
    fi
    if ! sh "$_dir/build_target.sh" linux "$_dir/prog" >"$_dir/build.log" 2>&1; then
        echo "FAIL: target link $_name (see $_dir/build.log)"
        return 1
    fi
    [ -x "$_dir/prog" ] || { echo "FAIL: $_name not built"; return 1; }
    return 0
}

echo "== building z9torr, mock_tracker, mock_peer (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
build_bin "$OUT/pe" "examples/z98/z9torr/tools/mock_peer.zig" "mock_peer" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"
PEER="$OUT/pe/prog"

# --- golden payload (identical recipe to tests/mkfixture.sh) ----------------
echo "== generating payload =="
awk -v seed=1 -v size=1048576 \
    'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' > "$WORK/t1.payload"
WANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
GOT="$(sha1sum "$WORK/t1.payload" | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then
    pass_case "t1 payload sha1 == expected"
else
    fail_case "t1 payload sha1 got '$GOT' want '$WANT' (awk differs?)"
fi

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_PEER" >"$OUT/tr.log" 2>&1 &
    TR_PID=$!
    _i=0
    while [ "$_i" -lt 50 ]; do
        if port_busy "$P_TRACKER"; then return 0; fi
        if ! kill -0 "$TR_PID" 2>/dev/null; then return 1; fi
        sleep 0.1
        _i=$((_i + 1))
    done
    return 1
}

# Persistent plaintext peer: the one-shot mock_peer is reloaded after every
# connection with a deliberate gap, so the peer is briefly unreachable when the
# client's fallback reconnect begins (mirrors a real peer whose accept is
# momentarily busy). The wrapper is killed as a unit by `cleanup`.
start_peer() {
    (
        _child=""
        trap 'if [ -n "$_child" ]; then kill "$_child" 2>/dev/null; fi; exit 0' TERM INT HUP
        while :; do
            timeout 300 "$PEER" --port "$P_PEER" --file "$1" --piece-length 262144 --mode normal &
            _child=$!
            wait "$_child"
            _child=""
            sleep "$GAP_S"
        done
    ) >"$OUT/pe.log" 2>&1 &
    PEER_PID=$!
    sleep 0.5
    if kill -0 "$PEER_PID" 2>/dev/null; then return 0; fi
    return 1
}

echo "== starting mock_tracker (advertises 127.0.0.1:$P_PEER) =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

echo "== starting persistent plaintext mock_peer (restart gap ${GAP_MS}ms) =="
if ! start_peer "$WORK/t1.payload"; then
    fail_case "plaintext mock_peer started"
else
    pass_case "plaintext mock_peer started"
fi

# --- encrypted-first, plaintext-fallback download ---------------------------
echo "== download t1_single_1m from a plaintext-only peer (fallback) =="
D="$WORK/run"
rm -rf "$D"
mkdir -p "$D"
START_MS="$(date +%s%3N)"
( cd "$D" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout 30 \
    "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D/out.txt" 2>&1 )
RC=$?
END_MS="$(date +%s%3N)"
ELAPSED_MS=$((END_MS - START_MS))
LOG="$D/z9torr.log"
echo "client-exit=$RC"
echo "elapsed-ms=$ELAPSED_MS"

if [ "$RC" -eq 0 ]; then
    pass_case "fallback download exit 0"
else
    fail_case "fallback download exit 0 (got $RC)"
fi

GOT="$(sha1sum "$D/t1.bin" 2>/dev/null | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then
    pass_case "byte-verified fallback download (sha1 == expected)"
else
    fail_case "byte-verified fallback download (sha1 got '$GOT' want '$WANT')"
fi

if grep -aq 'mse stage=ya' "$LOG" 2>/dev/null \
    && grep -aq 'mse-fail' "$LOG" 2>/dev/null; then
    pass_case "MSE/PE attempted first (mse stage=ya + mse-fail)"
else
    fail_case "MSE/PE attempted first (mse stage=ya + mse-fail)"
fi

if grep -aq 'handshake ok plain' "$LOG" 2>/dev/null; then
    pass_case "plaintext fallback path used (handshake ok plain)"
else
    fail_case "plaintext fallback path used (handshake ok plain)"
fi

if grep -aq 'handshake ok enc' "$LOG" 2>/dev/null; then
    fail_case "encrypted path NOT used against the plaintext-only mock"
else
    pass_case "encrypted path NOT used against the plaintext-only mock"
fi

# Non-vacuity: the peer was unreachable past the first few retries, so the
# fallback had to keep retrying across the gap; a fixed-attempt cap would have
# logged `reconnect-fail` and never reached `handshake ok plain`.
if grep -aq 'reconnect-fail' "$LOG" 2>/dev/null; then
    fail_case "fallback must not give up (no reconnect-fail)"
else
    pass_case "fallback must not give up (no reconnect-fail)"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_fallback summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_FALLBACK FAIL"
    exit 1
fi
echo "TIER_FALLBACK PASS"
exit 0
