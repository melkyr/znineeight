#!/bin/sh
# tier_stall.sh — z9torr M4.1 Task 4 gate: non-blocking connect + MSE probe.
#
# Demonstrates that one dead/unresponsive peer no longer serializes the swarm.
# A mock_tracker advertises TWO peers in this order:
#   1. mock_blackhole_peer  — accepts the TCP connect but never speaks, so the
#      client's MSE probe must wait out its 3 s deadline;
#   2. mock_mse_peer        — a healthy MSE seeder that serves the payload.
# Because the black-hole is slot 0, the scheduler ticks it first. With a
# BLOCKING connect/MSE probe that peer would freeze `tick` for >=3 s (and the
# peer log would show `mse-fail err=Timeout` BEFORE any healthy-peer progress);
# with the coroutine-aware probe it yields on WouldBlock, the healthy peer
# completes the encrypted download in well under the black-hole deadline, and
# the process exits on completion (so the stall line may never even be logged).
#
# Assertions (all non-vacuous):
#   - exit 0 and a byte-verified output;
#   - `handshake ok enc` (the healthy peer completed the real MSE handshake);
#   - both candidates were dialed (`spawn=2`);
#   - ordering: the first `handshake ok enc` precedes the first
#     `mse-fail err=Timeout` (or the stall never logs);
#   - wall time < 3000 ms (the black-hole MSE deadline; pre-fix this run takes
#     >3 s because the block serializes).
#
# POSIX sh. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_stall}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

# The fixture announces at 127.0.0.1:6969, so the tracker must use that port.
P_TRACKER="${Z9TORR_STALL_TRACKER:-6969}"
P_BH="${Z9TORR_STALL_BH:-6991}"
P_GOOD="${Z9TORR_STALL_GOOD:-6992}"

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
if port_busy "$P_BH"; then
    echo "FAIL: declared black-hole port already in use (bh=$P_BH)"
    exit 1
fi
# mock_mse_peer accepts exactly ONE connection: probing P_GOOD would consume it.
if port_busy "$P_GOOD"; then
    echo "FAIL: declared good-peer port already in use (good=$P_GOOD)"
    exit 1
fi

TR_PID=""
BH_PID=""
PEER_PID=""
cleanup() {
    [ -n "$PEER_PID" ] && kill "$PEER_PID" 2>/dev/null
    [ -n "$BH_PID" ] && kill "$BH_PID" 2>/dev/null
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
    [ -x "$_dir/prog" ] || { echo "FAIL: $_name not built"; return 1; }
    return 0
}

echo "== building z9torr, mock_tracker, mock_mse_peer, mock_blackhole_peer =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
build_bin "$OUT/pe" "examples/z98/z9torr/tools/mock_mse_peer.zig" "mock_mse_peer" || exit 1
build_bin "$OUT/bh" "examples/z98/z9torr/tools/mock_blackhole_peer.zig" "mock_blackhole_peer" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"
GOODPEER="$OUT/pe/prog"
BLACKHOLE="$OUT/bh/prog"

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

INFO_HASH="$(cat "$EXPDIR/t1_single_1m.infohash")"
TORRENT="$FIXDIR/t1_single_1m.torrent"

# Black-hole FIRST so it is spawned into slot 0 (the scheduler ticks it first).
echo "== starting mock_tracker (black-hole first) =="
timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_BH,127.0.0.1:$P_GOOD" >"$OUT/tr.log" 2>&1 &
TR_PID=$!
_i=0
while [ "$_i" -lt 50 ]; do
    if port_busy "$P_TRACKER"; then break; fi
    if ! kill -0 "$TR_PID" 2>/dev/null; then echo "FAIL: mock_tracker did not start"; exit 1; fi
    sleep 0.1
    _i=$((_i + 1))
done

echo "== starting mock_blackhole_peer (slot 0) =="
timeout 300 "$BLACKHOLE" --port "$P_BH" >"$OUT/bh.log" 2>&1 &
BH_PID=$!

echo "== starting mock_mse_peer (slot 1) =="
timeout 300 "$GOODPEER" --port "$P_GOOD" --file "$WORK/t1.payload" \
    --piece-length 262144 --info-hash "$INFO_HASH" >"$OUT/pe.log" 2>&1 &
PEER_PID=$!
# mock_mse_peer accepts exactly ONE connection, so wait on liveness, not a probe.
sleep 0.6

# --- run --------------------------------------------------------------------
echo "== run: healthy MSE peer must complete despite the stalled black-hole =="
D="$WORK/run"
mkdir -p "$D"
START_NS="$(date +%s%N)"
( cd "$D" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout 20 "$PROG" "$TORRENT" \
    >"$D/out.txt" 2>&1 )
RC=$?
END_NS="$(date +%s%N)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
LOG="$D/z9torr.log"

if [ "$RC" -eq 0 ]; then pass_case "stall run exit 0"; else fail_case "stall run exit 0 (got $RC)"; fi

GOT="$(sha1sum "$D/t1.bin" 2>/dev/null | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then pass_case "byte-verified encrypted download"; else fail_case "byte-verified encrypted download"; fi

if grep -aq 'handshake ok enc' "$LOG" 2>/dev/null; then
    pass_case "healthy peer completed the MSE handshake (handshake ok enc)"
else
    fail_case "healthy peer completed the MSE handshake (handshake ok enc)"
fi

if grep -aq '^spawn=2$' "$LOG" 2>/dev/null; then
    pass_case "both candidates dialed (spawn=2)"
else
    fail_case "both candidates dialed (spawn=2)"
fi

# The black-hole peer was actually dialed into slot 0.
if grep -aq "start ip=127.0.0.1 port=$P_BH" "$LOG" 2>/dev/null; then
    pass_case "black-hole peer dialed first (slot 0)"
else
    fail_case "black-hole peer dialed first (slot 0)"
fi

# Non-vacuous ordering: healthy-peers' success must precede the stall failure.
OK_LINE="$(grep -an 'handshake ok enc' "$LOG" 2>/dev/null | head -1 | cut -d: -f1)"
STALL_LINE="$(grep -an 'mse-fail err=Timeout' "$LOG" 2>/dev/null | head -1 | cut -d: -f1)"
if [ -z "$STALL_LINE" ]; then
    pass_case "stall failure absent before exit (healthy peer won the race)"
elif [ -n "$OK_LINE" ] && [ "$OK_LINE" -lt "$STALL_LINE" ]; then
    pass_case "healthy handshake precedes the stall timeout (line $OK_LINE < $STALL_LINE)"
else
    fail_case "healthy handshake precedes the stall timeout (ok='$OK_LINE' stall='$STALL_LINE')"
fi

# Wall time: pre-fix the black-hole serializes >=3000 ms before any other peer.
if [ "$ELAPSED_MS" -lt 3000 ]; then
    pass_case "run completed in ${ELAPSED_MS}ms (< 3000ms black-hole deadline)"
else
    fail_case "run completed in ${ELAPSED_MS}ms (>= 3000ms: stall serialized?)"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_stall summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_STALL FAIL"
    exit 1
fi
echo "TIER_STALL PASS"
exit 0
