#!/bin/sh
# tier2.sh — z9torr M3 end-to-end gate: multi-peer download + no-double-request
# + interrupt/restart resume + malformed-peer rejection.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. refuse to run if the declared ports (testdata/ports.txt) are busy;
#   2. build z9torr, mock_tracker, mock_peer with the binding seed recipe;
#   3. generate the golden payloads (mkfixture.sh awk recipe) and check them;
#   4. start mock_tracker (advertising every declared peer port) + mock_peers;
#   5. download t1_single_1m (single-peer shape) and t2_single_25m (multi-peer,
#      all declared ports): exit 0 + sha1sum == expected;
#   6. assert the multi-peer scheduler invariant via Z9TORR_CLAIM_LOG: exactly
#      one claim per piece (no duplicate piece indices) and >1 peer slot worked;
#   7. resume: kill a multi-peer t2 run with >=1 verified piece and a non-empty
#      sidecar partial[] mask, restart, assert exit 0 + sha1 + strictly fewer
#      fetched bytes than the cold run's `summary: fetched=` line;
#   8. malformed peers: wrong-info-hash and bad-bitfield-length each exit 4.
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier2}"
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
# The first declared peer port is the single-peer shape's server.
P_PEER=""
for _pp in $PEER_PORTS; do P_PEER="$_pp"; break; done
# Comma-separated compact list the tracker advertises.
TRACKER_PEERS=""
for _pp in $PEER_PORTS; do
    if [ -z "$TRACKER_PEERS" ]; then TRACKER_PEERS="127.0.0.1:$_pp"
    else TRACKER_PEERS="$TRACKER_PEERS,127.0.0.1:$_pp"; fi
done

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

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

# --- golden payloads (identical recipe to tests/mkfixture.sh) ---------------
gen_payload() {
    awk -v seed="$1" -v size="$2" \
        'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' > "$3"
}

echo "== generating payloads =="
gen_payload 1 1048576 "$WORK/t1.payload"
gen_payload 2 26214400 "$WORK/t2.payload"

check_payload() {
    _name="$1"; _file="$2"
    _want="$(cat "$EXPDIR/$_name.sha1")"
    _got="$(sha1sum "$_file" | awk '{print $1}')"
    if [ "$_got" = "$_want" ]; then
        pass_case "$_name payload sha1 == expected ($_got)"
    else
        fail_case "$_name payload sha1 got '$_got' want '$_want' (awk differs?)"
    fi
}
check_payload t1_single_1m "$WORK/t1.payload"
check_payload t2_single_25m "$WORK/t2.payload"

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "$TRACKER_PEERS" >"$OUT/tr.log" 2>&1 &
    TR_PID=$!
    # The mock's stdout is block-buffered, so poll the listen port with a
    # connect attempt (safe: mock_tracker loops over connections).
    _i=0
    while [ "$_i" -lt 50 ]; do
        if port_busy "$P_TRACKER"; then return 0; fi
        if ! kill -0 "$TR_PID" 2>/dev/null; then return 1; fi
        sleep 0.1
        _i=$((_i + 1))
    done
    return 1
}

# Start one mock_peer on port `$1` serving `$2` in mode `$3`. mock_peer accepts
# exactly ONE connection, so a connect probe would consume it; wait briefly on
# process liveness instead (bind+listen precede accept, and the client spends
# longer than this in its tracker announce).
start_peer_port() {
    timeout 300 "$PEER" --port "$1" --file "$2" --piece-length 262144 --mode "$3" >"$OUT/pe_$1.log" 2>&1 &
    _pid=$!
    PEER_PIDS="$PEER_PIDS $_pid"
    sleep 0.5
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    return 1
}

# Single-peer shape: only the first declared port serves (the tracker still
# advertises all of them, but the absent ones simply refuse the connection).
start_first_peer() {
    start_peer_port "$P_PEER" "$1" "$2"
}

# Multi-peer: one mock_peer per declared port, all serving the same file.
start_all_peers() {
    _bad=0
    for _pp in $PEER_PORTS; do
        start_peer_port "$_pp" "$1" "$2" || _bad=1
    done
    return $_bad
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

fetched_of() {
    sed -n 's/^summary: fetched=\([0-9]*\).*/\1/p' "$1" | head -n1
}

# True when the sidecar's completed_bits (13 bytes for 100 pieces) has a set bit.
have_verified_piece() {
    _s="$1"
    [ -f "$_s" ] || return 1
    _off="$(grep -abo '14:completed_bits13:' "$_s" 2>/dev/null | head -n1 | cut -d: -f1)"
    [ -n "$_off" ] || return 1
    od -An -tu1 -j $((_off + 20)) -N 13 "$_s" 2>/dev/null | \
        awk '{ for (i = 1; i <= NF; i++) if ($i + 0 != 0) { f = 1 } } END { exit !f }'
}

echo "== starting mock_tracker =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

# --- 1. t1 download ---------------------------------------------------------
echo "== download t1_single_1m =="
D1="$(fresh_dir t1)"
if start_first_peer "$WORK/t1.payload" normal; then
    ( cd "$D1" && env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D1/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 0 ]; then pass_case "t1 download exit 0"; else fail_case "t1 download exit 0 (got $RC)"; fi
    GOT="$(sha1sum "$D1/t1.bin" 2>/dev/null | awk '{print $1}')"
    WANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
    if [ "$GOT" = "$WANT" ]; then pass_case "t1 output sha1 == expected"; else fail_case "t1 output sha1 got '$GOT' want '$WANT'"; fi
else
    fail_case "t1: mock_peer started"
fi
stop_peers

# --- 2. t2 download (cold reference; multi-peer) ---------------------------
echo "== download t2_single_25m (cold, all declared peers) =="
D2="$(fresh_dir t2)"
COLD_FETCHED=""
if start_all_peers "$WORK/t2.payload" normal; then
    ( cd "$D2" && env Z9TORR_SEED="$SEED" Z9TORR_CLAIM_LOG=1 "$PROG" "$FIXDIR/t2_single_25m.torrent" >"$D2/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 0 ]; then pass_case "t2 download exit 0"; else fail_case "t2 download exit 0 (got $RC)"; fi
    GOT="$(sha1sum "$D2/t2.bin" 2>/dev/null | awk '{print $1}')"
    WANT="$(cat "$EXPDIR/t2_single_25m.sha1")"
    if [ "$GOT" = "$WANT" ]; then pass_case "t2 output sha1 == expected"; else fail_case "t2 output sha1 got '$GOT' want '$WANT'"; fi
    COLD_FETCHED="$(fetched_of "$D2/out.txt")"
    if [ -n "$COLD_FETCHED" ]; then pass_case "t2 cold summary: fetched=$COLD_FETCHED"; else fail_case "t2 cold summary: fetched present"; fi

    # No-double-request invariant (deferred from Task 0): every piece is claimed
    # exactly once, so 100 claims cover 100 distinct piece indices. The distinct
    # slots in the same log prove more than one peer actually did work.
    grep -o 'claim slot=[0-9]* piece=[0-9]*' "$D2/out.txt" >"$D2/claims.txt" 2>/dev/null || true
    NCLAIM="$(wc -l <"$D2/claims.txt" | tr -d ' ')"
    NPIECE="$(sed 's/.*piece=//' "$D2/claims.txt" | sort -n | uniq | wc -l | tr -d ' ')"
    NSLOT="$(sed 's/claim slot=//; s/ .*//' "$D2/claims.txt" | sort -u | wc -l | tr -d ' ')"
    if [ "$NCLAIM" -eq 100 ] && [ "$NPIECE" -eq 100 ]; then
        pass_case "t2 no double-request: $NCLAIM claims / $NPIECE unique pieces"
    else
        fail_case "t2 no double-request: claims=$NCLAIM unique=$NPIECE (want 100/100)"
    fi
    if [ "$NSLOT" -gt 1 ]; then
        pass_case "t2 multi-peer: $NSLOT peer slots claimed work"
    else
        fail_case "t2 multi-peer: $NSLOT peer slot(s) claimed work (want >1)"
    fi
else
    fail_case "t2: mock_peer started"
fi
stop_peers

# --- 3. interrupt + restart resume -----------------------------------------
echo "== resume: interrupt t2 + restart =="
DR="$(fresh_dir resume)"
if start_all_peers "$WORK/t2.payload" normal; then
    ( cd "$DR" && exec env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t2_single_25m.torrent" ) >"$DR/out1.txt" 2>&1 &
    CLIENT_PID=$!
    S="$DR/.z9torr.resume"
    _i=0
    READY=1
    while [ "$_i" -lt 200 ]; do
        if [ -f "$S" ] && grep -aq 'partialld' "$S" && have_verified_piece "$S"; then
            READY=0
            break
        fi
        if ! kill -0 "$CLIENT_PID" 2>/dev/null; then break; fi
        sleep 0.05
        _i=$((_i + 1))
    done
    if [ "$READY" -eq 0 ] && kill -0 "$CLIENT_PID" 2>/dev/null; then
        pass_case "resume: live client has >=1 verified piece + non-empty partial[]"
    else
        fail_case "resume: live client has >=1 verified piece + non-empty partial[]"
    fi
    kill -9 "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
    CLIENT_PID=""
    if grep -aq 'partialld' "$S" 2>/dev/null; then
        pass_case "resume: sidecar carried a non-empty partial[] before restart"
    else
        fail_case "resume: sidecar carried a non-empty partial[] before restart"
    fi
else
    fail_case "resume: mock_peer started (interrupt run)"
fi
stop_peers

if start_all_peers "$WORK/t2.payload" normal; then
    ( cd "$DR" && env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t2_single_25m.torrent" >"$DR/out2.txt" 2>&1 )
    RC2=$?
    if [ "$RC2" -eq 0 ]; then pass_case "resume restart exit 0"; else fail_case "resume restart exit 0 (got $RC2)"; fi
    GOT="$(sha1sum "$DR/t2.bin" 2>/dev/null | awk '{print $1}')"
    WANT="$(cat "$EXPDIR/t2_single_25m.sha1")"
    if [ "$GOT" = "$WANT" ]; then pass_case "resume restart output sha1 == expected"; else fail_case "resume restart output sha1 got '$GOT' want '$WANT'"; fi
    RES_FETCHED="$(fetched_of "$DR/out2.txt")"
    if [ -n "$RES_FETCHED" ]; then pass_case "resume restart summary: fetched=$RES_FETCHED"; else fail_case "resume restart summary: fetched present"; fi
    if [ -n "$COLD_FETCHED" ] && [ -n "$RES_FETCHED" ] && [ "$RES_FETCHED" -lt "$COLD_FETCHED" ]; then
        pass_case "resume re-fetched strictly fewer bytes ($RES_FETCHED < $COLD_FETCHED)"
    else
        fail_case "resume re-fetched strictly fewer bytes (resume=$RES_FETCHED cold=$COLD_FETCHED)"
    fi
else
    fail_case "resume: mock_peer started (restart run)"
fi
stop_peers

# --- 4. malformed peers -----------------------------------------------------
echo "== malformed peers =="
DB="$(fresh_dir badbf)"
if start_first_peer "$WORK/t1.payload" bad-bitfield-length; then
    ( cd "$DB" && env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$DB/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 4 ]; then pass_case "bad-bitfield-length rejected (exit 4)"; else fail_case "bad-bitfield-length rejected (got $RC, want 4)"; fi
else
    fail_case "bad-bitfield-length: mock_peer started"
fi
stop_peers

DW="$(fresh_dir wronginfo)"
if start_first_peer "$WORK/t1.payload" wrong-info-hash; then
    ( cd "$DW" && env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$DW/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 4 ]; then pass_case "wrong-info-hash rejected (exit 4)"; else fail_case "wrong-info-hash rejected (got $RC, want 4)"; fi
else
    fail_case "wrong-info-hash: mock_peer started"
fi
stop_peers

# --- summary ----------------------------------------------------------------
echo
echo "== tier2 summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER2 FAIL"
    exit 1
fi
echo "TIER2 PASS"
exit 0
