#!/bin/sh
# tier_udp_tracker.sh — z9torr M4 gate: UDP tracker (BEP 15) discovery.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. refuse to run if the declared ports are busy;
#   2. build z9torr, mock_udp_tracker, mock_peer with the binding seed recipe;
#   3. generate the t1 golden payload and check it;
#   4. start mock_udp_tracker (returning a compact peer list) and a restarted
#      mock_peer (the M4 encrypted-first probe consumes one connection);
#   5. download t6_udp_1m (whose only announce is `udp://127.0.0.1:6975/...`)
#      and assert exit 0 + sha1 == expected (byte-verified through the
#      scheduler), and that the client log shows the UDP path was taken.
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_udp}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

# The fixture's announce URL is fixed at udp://127.0.0.1:6975/announce; the peer
# uses a dedicated TCP port (tier2 uses 6970-6973, tier3 uses 6974).
P_TRACKER="${Z9TORR_UDP_TRACKER:-6975}"
P_PEER="${Z9TORR_UDP_PEER:-6976}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
# UDP cannot be probed this way; the UDP mock's bind failure is caught by its
# process-liveness check instead.
port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

if port_busy "$P_PEER"; then
    echo "FAIL: declared peer port already in use (peer=$P_PEER)"
    exit 1
fi

TR_PID=""
PEER_PIDS=""
CLIENT_PID=""
cleanup() {
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
    for _pid in $PEER_PIDS; do kill "$_pid" 2>/dev/null; done
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
    if ! timeout 120 "$ZIG" -fsafe -o "$_dir" "$_entry" >"$_dir/zig.log" 2>&1; then
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

echo "== building z9torr, mock_udp_tracker, mock_peer (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_udp_tracker.zig" "mock_udp_tracker" || exit 1
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
    pass_case "t1 payload sha1 == expected ($GOT)"
else
    fail_case "t1 payload sha1 got '$GOT' want '$WANT' (awk differs?)"
fi

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peer "127.0.0.1:$P_PEER" --event-log "$OUT/events.txt" >"$OUT/tr.log" 2>&1 &
    TR_PID=$!
    sleep 0.5
    if kill -0 "$TR_PID" 2>/dev/null; then return 0; fi
    return 1
}

# mock_peer accepts exactly ONE connection, and the M4 client's MSE probe
# consumes one before falling back to a plaintext reconnect; restart the mock
# after every connection (same wrapper as tier2). The wrapper is killed as a
# unit (its TERM trap stops the in-flight mock child).
start_peer() {
    (
        _child=""
        trap 'if [ -n "$_child" ]; then kill "$_child" 2>/dev/null; fi; exit 0' TERM INT HUP
        while :; do
            timeout 300 "$PEER" --port "$P_PEER" --file "$1" --piece-length 262144 --mode normal &
            _child=$!
            wait "$_child"
            _child=""
        done
    ) >"$OUT/pe.log" 2>&1 &
    _pid=$!
    PEER_PIDS="$PEER_PIDS $_pid"
    sleep 0.5
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    return 1
}

echo "== starting mock_udp_tracker =="
if ! start_tracker; then
    echo "FAIL: mock_udp_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

if start_peer "$WORK/t1.payload"; then
    pass_case "mock_peer started"
else
    fail_case "mock_peer started"
fi

# --- UDP-tracked download ---------------------------------------------------
echo "== download t6_udp_1m (BEP 15) =="
D1="$WORK/run"
rm -rf "$D1"
mkdir -p "$D1"
( cd "$D1" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 "$PROG" "$FIXDIR/t6_udp_1m.torrent" >"$D1/out.txt" 2>&1 )
RC=$?
if [ "$RC" -eq 0 ]; then pass_case "udp download exit 0"; else fail_case "udp download exit 0 (got $RC)"; fi

GOT="$(sha1sum "$D1/t1.bin" 2>/dev/null | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then pass_case "udp output sha1 == expected"; else fail_case "udp output sha1 got '$GOT' want '$WANT'"; fi

if grep -aq 'udp announce peers=' "$D1/z9torr.log" 2>/dev/null; then
    pass_case "client log shows the UDP announce path"
else
    fail_case "client log shows the UDP announce path"
fi

# The mock records each received announce's BEP 15 event code; the client sends
# `started` (BEP 15 2) first and `completed` (BEP 15 1) last. This directly
# checks the explicit AnnounceEvent -> BEP 15 map (never a raw enum cast).
if [ -f "$OUT/events.txt" ]; then
    _e_first="$(head -n1 "$OUT/events.txt" 2>/dev/null)"
    _e_last="$(tail -n1 "$OUT/events.txt" 2>/dev/null)"
    if [ "$_e_first" = "event=2" ]; then
        pass_case "started announce carries BEP 15 event=2"
    else
        fail_case "started announce carries BEP 15 event=2 (got '$_e_first')"
    fi
    if [ "$_e_last" = "event=1" ]; then
        pass_case "completed announce carries BEP 15 event=1"
    else
        fail_case "completed announce carries BEP 15 event=1 (got '$_e_last')"
    fi
else
    fail_case "mock event log written"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_udp_tracker summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_UDP_TRACKER FAIL"
    exit 1
fi
echo "TIER_UDP_TRACKER PASS"
exit 0
