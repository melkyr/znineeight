#!/bin/sh
# tier_pex.sh — z9torr M4 gate: PEX (BEP 11) over the extension protocol (BEP 10).
#
# POSIX sh. Run from anywhere (paths resolved from this script). Two parts:
#
#   A. In-process self-test (fast): a synthetic BEP 10 extended handshake
#      negotiates `ut_pex`, a `ut_pex` message's `added` list names two peers
#      that must reach the scheduler (addPeer); a re-send is deduped, a
#      drop-only message is a no-op, an un-negotiated id is ignored, and every
#      emitted dict is canonically keyed (F1).
#
#   B. End-to-end spawn/connect (non-vacuous, F2): the tracker advertises a live
#      peer (A) that serves the file. The client injects a synthetic `ut_pex`
#      naming a second, live peer (B). A control run without the injection is
#      byte-identical except that B is never spawned; with the injection B must
#      appear in the peer trace (`dyn spawn` + `start ... port=<B>`), proving the
#      PEX-learned peer is actually dialed, not merely added.
#
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_pex}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

P_TRACKER="${Z9TORR_PEX_TRACKER:-6969}"
P_PEER_A="${Z9TORR_PEX_PEER_A:-6970}"
P_PEER_B="${Z9TORR_PEX_PEER_B:-6971}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

if port_busy "$P_TRACKER"; then
    echo "FAIL: declared tracker port already in use (tracker=$P_TRACKER)"
    exit 1
fi
for _pp in "$P_PEER_A" "$P_PEER_B"; do
    if port_busy "$_pp"; then
        echo "FAIL: declared peer port already in use (peer=$_pp)"
        exit 1
    fi
done

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
pass_case "z9torr + mocks built"

# --- part A: in-process self-test ------------------------------------------
echo "== A: in-process PEX self-test =="
env Z9TORR_PEX_SELFTEST=1 "$PROG" >"$OUT/selftest.txt" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then pass_case "pex self-test exit 0"; else fail_case "pex self-test exit 0 (got $RC)"; fi
if grep -aq 'pex selftest: PASS' "$OUT/selftest.txt"; then
    pass_case "pex self-test reports PASS"
else
    fail_case "pex self-test reports PASS"
fi
if grep -aq 'ut_pex added/dropped feed addPeer' "$OUT/selftest.txt"; then
    pass_case "pex unit path: ut_pex -> addPeer"
else
    fail_case "pex unit path: ut_pex -> addPeer"
fi

# --- golden payload --------------------------------------------------------
echo "== generating payload =="
awk -v seed=1 -v size=1048576 \
    'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' > "$WORK/t1.payload"
WANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
GOT="$(sha1sum "$WORK/t1.payload" | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then
    pass_case "t1 payload sha1 == expected"
else
    fail_case "t1 payload sha1 got '$GOT' want '$WANT'"
fi

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_PEER_A" >"$OUT/tr.log" 2>&1 &
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

start_peer_port() {
    (
        _child=""
        trap 'if [ -n "$_child" ]; then kill "$_child" 2>/dev/null; fi; exit 0' TERM INT HUP
        while :; do
            timeout 300 "$PEER" --port "$1" --file "$2" --piece-length 262144 --mode "$3" &
            _child=$!
            wait "$_child"
            _child=""
        done
    ) >"$OUT/pe_$1.log" 2>&1 &
    _pid=$!
    PEER_PIDS="$PEER_PIDS $_pid"
    sleep 0.5
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    return 1
}

stop_peers() {
    for _pid in $PEER_PIDS; do kill "$_pid" 2>/dev/null; done
    for _pid in $PEER_PIDS; do wait "$_pid" 2>/dev/null; done
    PEER_PIDS=""
    sleep 0.5
}

echo "== starting mock_tracker =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

# --- part B1: control (no injection) -> peer B never appears ---------------
echo "== B1: control run without injection never dials peer B =="
D0="$WORK/run_noinj"
rm -rf "$D0"; mkdir -p "$D0"
if start_peer_port "$P_PEER_A" "$WORK/t1.payload" "normal"; then
    ( cd "$D0" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D0/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 0 ]; then pass_case "control download exit 0"; else fail_case "control download exit 0 (got $RC)"; fi
    if grep -aq "port=$P_PEER_B" "$D0/z9torr.log" 2>/dev/null; then
        fail_case "control run dialed peer B without PEX"
    else
        pass_case "control run never dialed peer B"
    fi
else
    fail_case "control: mock_peer A started"
fi
stop_peers

# --- part B2: WITH injection the PEX peer is dynamically spawned + dialed ---
echo "== B2: PEX-injected peer must be spawned + connected =="
D1="$WORK/run_inj"
rm -rf "$D1"; mkdir -p "$D1"
_ok=1
start_peer_port "$P_PEER_A" "$WORK/t1.payload" "normal" || _ok=0
start_peer_port "$P_PEER_B" "$WORK/t1.payload" "normal" || _ok=0
if [ "$_ok" -eq 1 ]; then
    ( cd "$D1" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 \
        Z9TORR_PEX_INJECT="127.0.0.1:$P_PEER_B" \
        "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D1/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 0 ]; then pass_case "pex injection download exit 0"; else fail_case "pex injection download exit 0 (got $RC)"; fi
    GOT="$(sha1sum "$D1/t1.bin" 2>/dev/null | awk '{print $1}')"
    if [ "$GOT" = "$WANT" ]; then pass_case "pex injection output sha1 == expected"; else fail_case "pex injection output sha1 got '$GOT' want '$WANT'"; fi
    if grep -aq 'dyn spawn' "$D1/z9torr.log" 2>/dev/null; then
        pass_case "PEX peer dynamically spawned"
    else
        fail_case "PEX peer dynamically spawned (no 'dyn spawn' in log)"
    fi
    if grep -aq "start ip=127.0.0.1 port=$P_PEER_B" "$D1/z9torr.log" 2>/dev/null; then
        pass_case "PEX peer actually dialed (peer coroutine started for port=$P_PEER_B)"
    else
        fail_case "PEX peer actually dialed (no 'start ... port=$P_PEER_B' in log)"
    fi
else
    fail_case "injection: mock_peers started"
fi
stop_peers

# --- summary ----------------------------------------------------------------
echo
echo "== tier_pex summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_PEX FAIL"
    exit 1
fi
echo "TIER_PEX PASS"
exit 0
