#!/bin/sh
# tier3_encrypted.sh — z9torr M4 gate: MSE/PE encrypted download.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. refuse to run if the declared ports are busy;
#   2. build z9torr, mock_tracker, mock_mse_peer with the binding seed recipe;
#   3. generate the t1 golden payload and check it;
#   4. start mock_tracker advertising the MSE peer; start mock_mse_peer
#      (requires MSE, responds as the MSE responder, then serves the file);
#   5. run the client with Z9TORR_LOG=1 and assert:
#        - exit 0,
#        - output sha1 == expected (byte-verified download),
#        - the peer log shows `handshake ok enc` (the MSE path was actually used).
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier3}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

# The fixture's announce URL is fixed at 127.0.0.1:6969, so tier3 must use that
# tracker port. Its MSE peer uses a dedicated port (tier2 uses 6970-6973).
P_TRACKER="${Z9TORR_T3_TRACKER:-6969}"
P_PEER="${Z9TORR_T3_PEER:-6974}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

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
CLIENT_PID=""
cleanup() {
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
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
    if [ ! -x "$_dir/prog" ]; then
        echo "FAIL: $_name not built"
        return 1
    fi
    return 0
}

echo "== building z9torr, mock_tracker, mock_mse_peer (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
build_bin "$OUT/pe" "examples/z98/z9torr/tools/mock_mse_peer.zig" "mock_mse_peer" || exit 1
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
    pass_case "t1 payload sha1 == expected ($GOT)"
else
    fail_case "t1 payload sha1 got '$GOT' want '$WANT' (awk differs?)"
fi

INFO_HASH="$(cat "$EXPDIR/t1_single_1m.infohash")"

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

# mock_mse_peer accepts exactly ONE connection, so a connect probe would consume
# it; wait briefly on process liveness instead.
start_peer() {
    timeout 300 "$PEER" --port "$P_PEER" --file "$WORK/t1.payload" \
        --piece-length 262144 --info-hash "$INFO_HASH" >"$OUT/pe.log" 2>&1 &
    PEER_PID=$!
    sleep 0.5
    if kill -0 "$PEER_PID" 2>/dev/null; then return 0; fi
    return 1
}

echo "== starting mock_tracker =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

echo "== starting mock_mse_peer =="
if ! start_peer; then
    fail_case "mock_mse_peer started"
else
    pass_case "mock_mse_peer started"
fi

# --- encrypted download -----------------------------------------------------
echo "== download t1_single_1m (MSE) =="
D1="$WORK/run"
rm -rf "$D1"
mkdir -p "$D1"
( cd "$D1" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D1/out.txt" 2>&1 )
RC=$?
if [ "$RC" -eq 0 ]; then pass_case "encrypted download exit 0"; else fail_case "encrypted download exit 0 (got $RC)"; fi

GOT="$(sha1sum "$D1/t1.bin" 2>/dev/null | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then pass_case "encrypted output sha1 == expected"; else fail_case "encrypted output sha1 got '$GOT' want '$WANT'"; fi

if grep -aq 'handshake ok enc' "$D1/z9torr.log" 2>/dev/null; then
    pass_case "peer trace shows MSE handshake (handshake ok enc)"
else
    fail_case "peer trace shows MSE handshake (handshake ok enc)"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier3 summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER3 FAIL"
    exit 1
fi
echo "TIER3 PASS"
exit 0
