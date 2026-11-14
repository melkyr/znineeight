#!/bin/sh
# tier_win9x_io.sh — z9torr M5 T3b gate: stdout redirection vs a console.
#
# The 1 Hz progress line must be rewritten in place with '\r' ONLY when stdout
# is an interactive console. When stdout is redirected (to a file/pipe) each
# refresh must be emitted on its own line ('\n'), so a redirect log is
# line-per-refresh, not a stream of raw CR bytes. This is the Win9x
# GetFileType/`isatty` fallback (console.zig).
#
# Hermetic: a mock_tracker advertising a mock_blackhole_peer keeps the client
# running at 0.0% for several seconds (the peer accepts the TCP connect but
# never speaks), so the sampler fires at least once. The client is run with
# stdout redirected to a file; the gate asserts:
#   - a progress line was emitted (grep 'KB/s peers='), and
#   - the redirected output contains NO CR byte (0x0D).
# A POSIX pty (via `script`) is used for the console case when available: the
# same run attached to a pty must contain CR bytes and a progress line.
#
# POSIX sh. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m5_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_win9x_io}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
TORRENT="$FIXDIR/t1_single_1m.torrent"

# Declared ports (distinct from tier_stall's 6991/6992).
P_TRACKER="${Z9TORR_IO_TRACKER:-6969}"
P_BH="${Z9TORR_IO_BH:-6993}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

rm -rf "$OUT"
mkdir -p "$OUT"

# A connect attempt is the only busy-port probe available here (no ss/lsof).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

if port_busy "$P_TRACKER"; then
    echo "FAIL: declared tracker port already in use (tracker=$P_TRACKER)"
    exit 1
fi
if port_busy "$P_BH"; then
    echo "FAIL: declared black-hole port already in use (bh=$P_BH)"
    exit 1
fi

TR_PID=""
BH_PID=""
CLIENT_PID=""
cleanup() {
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
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

echo "== building z9torr, mock_tracker, mock_blackhole_peer (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
build_bin "$OUT/bh" "examples/z98/z9torr/tools/mock_blackhole_peer.zig" "mock_blackhole_peer" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"
BLACKHOLE="$OUT/bh/prog"

# --- mock lifecycle ---------------------------------------------------------
echo "== starting mock_tracker (advertising black-hole $P_BH) =="
timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_BH" >"$OUT/tr.log" 2>&1 &
TR_PID=$!
_i=0
while [ "$_i" -lt 50 ]; do
    if port_busy "$P_TRACKER"; then break; fi
    if ! kill -0 "$TR_PID" 2>/dev/null; then
        echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
        exit 1
    fi
    sleep 0.1
    _i=$((_i + 1))
done

echo "== starting mock_blackhole_peer =="
timeout 300 "$BLACKHOLE" --port "$P_BH" >"$OUT/bh.log" 2>&1 &
BH_PID=$!
sleep 0.5

# --- case 1: stdout redirected to a file ------------------------------------
# The black-hole keeps the run alive so the 1 Hz sampler fires; poll for the
# first progress line rather than waiting for the (much later) peer timeout.
echo "== case 1: stdout redirected to a file =="
R1="$OUT/redirect"
mkdir -p "$R1"
( cd "$R1" && exec env Z9TORR_SEED="$SEED" "$PROG" "$TORRENT" >"$R1/out.txt" 2>"$R1/err.txt" ) &
CLIENT_PID=$!
_i=0
while [ "$_i" -lt 400 ]; do
    if grep -q 'KB/s peers=' "$R1/out.txt" 2>/dev/null; then break; fi
    if ! kill -0 "$CLIENT_PID" 2>/dev/null; then break; fi
    sleep 0.05
    _i=$((_i + 1))
done
kill "$CLIENT_PID" 2>/dev/null
wait "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""

if grep -q 'KB/s peers=' "$R1/out.txt" 2>/dev/null; then
    pass_case "redirected run emitted a progress line"
else
    fail_case "redirected run emitted a progress line (none in $R1/out.txt)"
fi

CR_COUNT="$(tr -cd '\r' <"$R1/out.txt" 2>/dev/null | wc -c | tr -d ' ')"
if [ "$CR_COUNT" -eq 0 ]; then
    pass_case "redirected progress has no bare CR (line-per-refresh)"
else
    fail_case "redirected progress has no bare CR (got $CR_COUNT CR bytes)"
fi

# --- case 2: attached to a pty (console) ------------------------------------
# Optional: needs `script` to allocate a pty. When absent, report and skip.
echo "== case 2: attached to a pty (console) =="
if command -v script >/dev/null 2>&1; then
    R2="$OUT/console"
    mkdir -p "$R2"
    script -qec "cd $R2 && env Z9TORR_SEED=$SEED $PROG $TORRENT" "$R2/typescript" >/dev/null 2>&1
    CTR_COUNT="$(tr -cd '\r' <"$R2/typescript" 2>/dev/null | wc -c | tr -d ' ')"
    if grep -q 'KB/s peers=' "$R2/typescript" 2>/dev/null && [ "$CTR_COUNT" -gt 0 ]; then
        pass_case "console run uses in-place CR (CR bytes=$CTR_COUNT)"
    else
        fail_case "console run uses in-place CR (progress=$(grep -c 'KB/s peers=' "$R2/typescript" 2>/dev/null) CR=$CTR_COUNT)"
    fi
else
    echo "  note: 'script' not found; console pty case not run"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_win9x_io summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_WIN9X_IO FAIL"
    exit 1
fi
echo "TIER_WIN9X_IO PASS"
exit 0
