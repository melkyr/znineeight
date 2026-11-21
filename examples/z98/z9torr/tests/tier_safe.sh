#!/bin/sh
# tier_safe.sh — z9torr `-fsafe` end-to-end gate (M5 UB fix).
#
# Original M5 gate: `-ffast` hid example undefined behaviour (checked-integer
# overflow and `undefined` poison reads), so this tier builds the client with
# **`-fsafe`** (checked arithmetic + 0xAA-poisons `undefined`) and requires a
# real single-peer download of `t1_single_1m` to complete with the golden SHA-1.
# S2 extended the same mode to EVERY tier and to the mock tools.
#
# Steps:
#   1. refuse to run if the declared ports (testdata/ports.txt) are busy;
#   2. build z9torr with `-fsafe` and assert the emitted C actually carries
#      overflow checks (`zig_overflow_flag_*`), i.e. the mode is not vacuous;
#   3. build mock_tracker/mock_peer with `-fsafe` too (whole test surface safe);
#   4. generate the t1 payload and check its SHA-1;
#   5. start mock_tracker + one mock_peer, run the `-fsafe` client, assert
#      exit 0, output SHA-1 == expected, and "download complete";
#   6. teardown trap kills every mock and the client on any exit.
# Exits non-zero and prints a PASS/FAIL summary on any failure.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m5_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_safe}"
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
P_PEER=""
for _pp in $PEER_PORTS; do P_PEER="$_pp"; break; done
TRACKER_PEERS=""
for _pp in $PEER_PORTS; do
    if [ -z "$TRACKER_PEERS" ]; then TRACKER_PEERS="127.0.0.1:$_pp"
    else TRACKER_PEERS="$TRACKER_PEERS,127.0.0.1:$_pp"; fi
done

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

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

# --- build ------------------------------------------------------------------
# `$1` = dir, `$2` = entry, `$3` = name, `$4` = mode (`-fsafe` / `-ffast`).
build_bin() {
    _dir="$1"; _entry="$2"; _name="$3"; _mode="$4"
    mkdir -p "$_dir"
    if ! timeout 120 "$ZIG" "$_mode" -o "$_dir" "$_entry" >"$_dir/zig.log" 2>&1; then
        echo "FAIL: zig compile $_name ($_mode, see $_dir/zig.log)"
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

echo "== building client + mocks (-fsafe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr(-fsafe)" "-fsafe" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" "-fsafe" || exit 1
build_bin "$OUT/pe" "examples/z98/z9torr/tools/mock_peer.zig" "mock_peer" "-fsafe" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"
PEER="$OUT/pe/prog"

# Non-vacuous mode check: a `-fsafe` client emits overflow-checked arithmetic
# (`zig_overflow_flag_*`, which trap via `pal_trap`); the `-ffast` build does
# not. The `zig_runtime.c` always *defines* these helpers, so probe a client
# module file (`main_*.c`), not the runtime.
if grep -l "zig_overflow_flag_" "$OUT/z9"/main_*.c >/dev/null 2>&1; then
    pass_case "-fsafe build emits checked arithmetic (zig_overflow_flag_*)"
else
    fail_case "-fsafe build emits checked arithmetic (client C has no overflow checks)"
fi

# --- golden payload (identical recipe to tests/tier2.sh) --------------------
gen_payload() {
    awk -v seed="$1" -v size="$2" \
        'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' > "$3"
}

echo "== generating t1 payload =="
gen_payload 1 1048576 "$WORK/t1.payload"
WANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
GOTP="$(sha1sum "$WORK/t1.payload" | awk '{print $1}')"
if [ "$GOTP" = "$WANT" ]; then
    pass_case "t1 payload sha1 == expected ($GOTP)"
else
    fail_case "t1 payload sha1 got '$GOTP' want '$WANT' (awk differs?)"
fi

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "$TRACKER_PEERS" >"$OUT/tr.log" 2>&1 &
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

# The client is encrypted-first, so its MSE probe consumes one connection before
# the plaintext fallback; the one-shot mock_peer is restarted after every
# connection (same wrapper as tier2.sh). Killed as a unit by the TERM trap.
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

# --- t1 download under -fsafe ----------------------------------------------
echo "== download t1_single_1m with the -fsafe client =="
D1="$OUT/run.t1"
rm -rf "$D1"; mkdir -p "$D1"
if start_peer_port "$P_PEER" "$WORK/t1.payload" normal; then
    ( cd "$D1" && env Z9TORR_SEED="$SEED" "$PROG" "$FIXDIR/t1_single_1m.torrent" >"$D1/out.txt" 2>&1 )
    RC=$?
    if [ "$RC" -eq 0 ]; then
        pass_case "-fsafe t1 download exit 0"
    else
        fail_case "-fsafe t1 download exit 0 (got $RC -- SIGTRAP is 133)"
    fi
    GOT="$(sha1sum "$D1/t1.bin" 2>/dev/null | awk '{print $1}')"
    if [ "$GOT" = "$WANT" ]; then
        pass_case "-fsafe t1 output sha1 == expected ($GOT)"
    else
        fail_case "-fsafe t1 output sha1 got '$GOT' want '$WANT'"
    fi
    if grep -q "download complete" "$D1/out.txt"; then
        pass_case "-fsafe client reported download complete"
    else
        fail_case "-fsafe client reported download complete"
    fi
    if grep -q "summary: fetched=1048576" "$D1/out.txt"; then
        pass_case "-fsafe client fetched the full payload (summary: fetched=1048576)"
    else
        fail_case "-fsafe client fetched the full payload (summary missing)"
    fi
else
    fail_case "t1: mock_peer started"
fi
stop_peers

# --- summary ----------------------------------------------------------------
echo
echo "== tier_safe summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_SAFE FAIL"
    exit 1
fi
echo "TIER_SAFE PASS"
exit 0
