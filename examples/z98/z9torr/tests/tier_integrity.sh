#!/bin/sh
# tier_integrity.sh — z9torr corrupt-peer integrity gate.
#
# Proves, end-to-end and NON-VACUOUSLY, that the client's per-piece SHA-1
# verification (piece.zig `onBlock` -> `BlockResult.Corrupt` -> scheduler
# re-queue) rejects a peer that serves a corrupt piece, and that a multi-peer
# download still yields the correct full-file SHA-1.
#
# Case A (corrupt + >=3 good, general swarm): a `corrupt-piece` mock_peer sits
#   on the first declared port (slot 0, so the scheduler's lowest-index
#   tie-break makes it claim piece 0) and every remaining declared port serves
#   `normal`. Run z9torr on t1_single_1m. With >=4 live peers and 4 pieces every
#   good peer finishes its single piece and goes idle before the corrupt piece
#   is re-queued; recovery therefore requires the client to WAKE an idle peer
#   when `scheduler.corrupt` puts piece 0 back to `missing`, not merely to rely
#   on a peer that still had unclaimed work. Assertions (all non-vacuous):
#     - exit 0 and `sha1sum t1.bin == testdata/expected/t1_single_1m.sha1`;
#     - all declared peers dialed (`spawn=N`);
#     - the corrupt peer's log shows it actually served a corrupt piece
#       (`mock_peer corrupt piece=0 begin=...`);
#     - the client log shows it detected + dropped the corrupt peer
#       (`break reason=corrupt`) and then completed the download.
#   A client that trusted corrupt bytes would either complete with a wrong
#   SHA-1 or fail; this case proves detection AND recovery from a good peer.
#
# Case B (control, corrupt-only): start ONLY the `corrupt-piece` peer and run
#   z9torr. Assertions:
#     - the run does NOT complete (nonzero exit);
#     - the output SHA-1 is NOT the golden (or the file is absent);
#     - the corrupt peer's log still shows it served the corrupt piece.
#   This is the non-vacuous control: a client that trusted corrupt data would
#   "finish" here (exit 0 / wrong SHA-1) instead of failing.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Hermetic:
# mock_tracker + one mock_peer per declared port (testdata/ports.txt), timeout
# guards, teardown trap, PASS/FAIL counters, non-zero exit on failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_integrity}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# --- declared ports (tracker on line 1; peer ports on lines 2..N) -----------
P_TRACKER="$(sed -n '1p' "$FIXDIR/ports.txt" | tr -d ' ')"
P_TRACKER="${P_TRACKER:-6969}"
PEER_PORTS="$(sed -n '2,$p' "$FIXDIR/ports.txt" | tr -d ' ')"
if [ -z "$PEER_PORTS" ]; then PEER_PORTS="6970"; fi

# The first declared peer port is the CORRUPT peer; every remaining declared
# port is a good `normal` peer. Case A is a general multi-peer swarm: with a
# 4-peer / 4-piece workload (1 corrupt + 3 good) every good peer finishes its
# single piece and idles before the corrupt piece is re-queued, so the fix under
# test (wake an idle peer on re-queue) is required for the run to recover.
P_CORRUPT=""
for _pp in $PEER_PORTS; do P_CORRUPT="$_pp"; break; done
GOOD_PORTS=""
for _pp in $PEER_PORTS; do
    if [ "$_pp" != "$P_CORRUPT" ]; then
        if [ -z "$GOOD_PORTS" ]; then GOOD_PORTS="$_pp"; else GOOD_PORTS="$GOOD_PORTS $_pp"; fi
    fi
done

# Count the declared peers and build the comma-separated tracker peer list in
# declared order (corrupt first, so it is slot 0 and claims piece 0).
N_PEERS=0
TRACKER_PEERS_A=""
for _pp in $PEER_PORTS; do
    N_PEERS=$((N_PEERS + 1))
    if [ -z "$TRACKER_PEERS_A" ]; then TRACKER_PEERS_A="127.0.0.1:$_pp"
    else TRACKER_PEERS_A="$TRACKER_PEERS_A,127.0.0.1:$_pp"; fi
done
# Case B advertises only the corrupt peer.
TRACKER_PEERS_B="127.0.0.1:$P_CORRUPT"

if [ "$N_PEERS" -lt 4 ]; then
    echo "FAIL: Case A needs >=4 declared peer ports (1 corrupt + >=3 good)"
    exit 1
fi
if [ -z "$GOOD_PORTS" ]; then
    echo "FAIL: Case A needs >=1 good peer port (ports.txt)"
    exit 1
fi

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

if port_busy "$P_TRACKER"; then
    echo "FAIL: declared tracker port already in use (tracker=$P_TRACKER)"
    echo "      free it (stop leftover mock_tracker) and re-run"
    exit 1
fi
for _pp in $PEER_PORTS; do
    if port_busy "$_pp"; then
        echo "FAIL: declared peer port already in use (peer=$_pp)"
        echo "      free it (stop leftover mock_peer) and re-run"
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
    pass_case "t1 payload sha1 == expected ($GOT)"
else
    fail_case "t1 payload sha1 got '$GOT' want '$WANT' (awk differs?)"
fi

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "$1" >"$OUT/tr.log" 2>&1 &
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

stop_tracker() {
    [ -n "$TR_PID" ] && kill "$TR_PID" 2>/dev/null
    [ -n "$TR_PID" ] && wait "$TR_PID" 2>/dev/null
    TR_PID=""
    sleep 0.2
}

# Start one mock_peer on port `$1` serving `$2` in mode `$3` with `$4` extra
# args. mock_peer accepts exactly ONE connection, so it is kept alive behind a
# restart wrapper (the encrypted-first client's MSE probe consumes one
# connection before the plaintext reconnect). A connect probe would consume the
# peer, so wait on process liveness instead.
start_peer_port() {
    (
        _child=""
        trap 'if [ -n "$_child" ]; then kill "$_child" 2>/dev/null; fi; exit 0' TERM INT HUP
        while :; do
            timeout 300 "$PEER" --port "$1" --file "$2" --piece-length 262144 --mode "$3" $4 &
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

fresh_dir() {
    _d="$OUT/run.$1"
    rm -rf "$_d"
    mkdir -p "$_d"
    printf '%s' "$_d"
}

# --- Case A: general multi-peer swarm, corrupt + >=3 good -------------------
echo "== Case A: general multi-peer swarm (corrupt + $((N_PEERS - 1)) good) =="
DA="$(fresh_dir caseA)"
if start_tracker "$TRACKER_PEERS_A"; then
    if start_peer_port "$P_CORRUPT" "$WORK/t1.payload" corrupt-piece "--corrupt-piece 0"; then
        pass_case "Case A: corrupt peer started on $P_CORRUPT"
    else
        fail_case "Case A: corrupt peer started on $P_CORRUPT"
    fi
    for _gp in $GOOD_PORTS; do
        if start_peer_port "$_gp" "$WORK/t1.payload" normal ""; then
            pass_case "Case A: good peer started on $_gp"
        else
            fail_case "Case A: good peer started on $_gp"
        fi
    done
    ( cd "$DA" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout 40 "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$DA/out.txt" 2>&1 )
    RC=$?
    CLIENT_PID=""
    cp "$OUT/pe_$P_CORRUPT.log" "$DA/corrupt-peer.log" 2>/dev/null || true
    LOG="$DA/z9torr.log"

    if [ "$RC" -eq 0 ]; then pass_case "Case A: download exit 0"; else fail_case "Case A: download exit 0 (got $RC)"; fi
    GOT="$(sha1sum "$DA/t1.bin" 2>/dev/null | awk '{print $1}')"
    if [ "$GOT" = "$WANT" ]; then
        pass_case "Case A: output sha1 == expected (corrupt piece detected + re-fetched)"
    else
        fail_case "Case A: output sha1 got '$GOT' want '$WANT'"
    fi

    if grep -aq "^spawn=$N_PEERS\$" "$LOG" 2>/dev/null; then
        pass_case "Case A: multi-peer (spawn=$N_PEERS slots)"
    else
        fail_case "Case A: multi-peer (spawn=$N_PEERS slots)"
    fi

    if grep -aq 'mock_peer corrupt piece=' "$DA/corrupt-peer.log" 2>/dev/null; then
        pass_case "Case A: corrupt peer served a corrupted piece (evidence in its log)"
    else
        fail_case "Case A: corrupt peer served a corrupted piece (evidence in its log)"
    fi

    if grep -aq 'break reason=corrupt' "$LOG" 2>/dev/null; then
        pass_case "Case A: client detected the corrupt piece (break reason=corrupt)"
    else
        fail_case "Case A: client detected the corrupt piece (break reason=corrupt)"
    fi
else
    fail_case "Case A: mock_tracker started"
fi
stop_peers
stop_tracker

# --- Case B: control, corrupt-only ------------------------------------------
echo "== Case B: control (corrupt peer only) =="
DB="$(fresh_dir caseB)"
if start_tracker "$TRACKER_PEERS_B"; then
    if start_peer_port "$P_CORRUPT" "$WORK/t1.payload" corrupt-piece "--corrupt-piece 0"; then
        pass_case "Case B: corrupt peer started on $P_CORRUPT"
    else
        fail_case "Case B: corrupt peer started on $P_CORRUPT"
    fi
    ( cd "$DB" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout 30 "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$DB/out.txt" 2>&1 )
    RC=$?
    CLIENT_PID=""
    cp "$OUT/pe_$P_CORRUPT.log" "$DB/corrupt-peer.log" 2>/dev/null || true
    LOG="$DB/z9torr.log"

    if [ "$RC" -ne 0 ]; then
        pass_case "Case B: corrupt-only run does NOT complete (exit $RC)"
    else
        fail_case "Case B: corrupt-only run completed (exit 0) — corrupt data was trusted"
    fi

    GOT="$(sha1sum "$DB/t1.bin" 2>/dev/null | awk '{print $1}')"
    if [ "$GOT" != "$WANT" ]; then
        pass_case "Case B: output sha1 is NOT the golden ('${GOT:-<absent>}')"
    else
        fail_case "Case B: output sha1 unexpectedly matched the golden (corrupt data trusted)"
    fi

    if grep -aq 'mock_peer corrupt piece=' "$DB/corrupt-peer.log" 2>/dev/null; then
        pass_case "Case B: corrupt peer served a corrupted piece (control is non-vacuous)"
    else
        fail_case "Case B: corrupt peer served a corrupted piece (control is non-vacuous)"
    fi
else
    fail_case "Case B: mock_tracker started"
fi
stop_peers
stop_tracker

# --- summary ----------------------------------------------------------------
echo
echo "== tier_integrity summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_INTEGRITY FAIL"
    exit 1
fi
echo "TIER_INTEGRITY PASS"
exit 0
