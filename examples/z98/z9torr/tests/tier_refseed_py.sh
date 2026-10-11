#!/bin/sh
# tier_refseed_py.sh -- z9torr M4.1 Task 2: real-seed tier (Python MSE responder).
#
# A hermetic loopback REAL-encrypted-download gate driven by an INDEPENDENT
# implementation of the MSE/PE byte layout (tests/mse_ref.py, stdlib only):
#   * a committed deterministic single-file torrent fixture
#     (testdata/t1_single_1m.torrent; 1 MiB, 4 x 256 KiB, announce 127.0.0.1:6969);
#   * tests/mse_ref.py --serve as the seeder/responder (real handshake + transfer,
#     NOT a mock);
#   * mock_tracker advertising 127.0.0.1:<python listen port>;
#   * the unmodified z9torr client.
# The tier asserts a byte-verified completed download (output SHA-1 == the
# fixture's expected SHA-1) after a real MSE/PE handshake and encrypted transfer.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Exits:
#   0   PASS  byte-verified encrypted download
#   1   FAIL  build error, or the download did not complete/verify
#   77  SKIP  python3 unavailable -- with an explicit `SKIP: <reason>` line,
#             never a silent pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_refseed_py}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
PY_REF="$SCRIPT_DIR/mse_ref.py"

# The fixture announces at 127.0.0.1:6969, so the tracker must use that port.
P_TRACKER="${Z9TORR_RSP_TRACKER:-6969}"
P_PY="${Z9TORR_RSP_PY:-6977}"
CLIENT_TIMEOUT="${Z9TORR_RSP_TIMEOUT:-30}"

SKIP_EXIT=77
PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
note() { echo "note - $1"; }
skip() {
    echo
    echo "SKIP: $1"
    echo "== tier_refseed_py summary: SKIP ($PASSES passed, $FAILS failed; reason: $1) =="
    echo "TIER_REFSEED_PY SKIP"
    exit "$SKIP_EXIT"
}

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

busy_check() {
    if port_busy "$1"; then
        echo "FAIL: declared $2 port already in use ($1)"
        exit 1
    fi
}
busy_check "$P_TRACKER" tracker
busy_check "$P_PY" python

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
if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 unavailable"
fi
if [ ! -f "$PY_REF" ]; then
    skip "mse_ref.py missing ($PY_REF)"
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

echo "== building z9torr, mock_tracker (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"

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

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_PY" >"$OUT/tr.log" 2>&1 &
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

echo "== starting mock_tracker (advertises 127.0.0.1:$P_PY) =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

# --- Python MSE responder seeder --------------------------------------------
echo "== starting mse_ref.py responder seeder =="
MSE_REF_DEBUG=1 timeout 300 python3 "$PY_REF" --serve "$WORK/t1.payload" \
    --info-hash "$INFO_HASH" --port "$P_PY" --piece-length 262144 --seed "$SEED" \
    >"$OUT/pe_py.log" 2>&1 &
PEER_PID=$!
sleep 1.0
if ! kill -0 "$PEER_PID" 2>/dev/null; then
    echo "FAIL: mse_ref.py seeder exited early (see $OUT/pe_py.log)"
    exit 1
fi

# --- real encrypted download ------------------------------------------------
echo "== download t1_single_1m from mse_ref.py (MSE) =="
D="$WORK/run"
rm -rf "$D"
mkdir -p "$D"
( cd "$D" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout "$CLIENT_TIMEOUT" \
    "$PROG" "$TORRENT" >"$D/out.txt" 2>&1 )
RC=$?
kill "$PEER_PID" 2>/dev/null; wait "$PEER_PID" 2>/dev/null; PEER_PID=""
LOG="$D/z9torr.log"
echo "client-exit=$RC"

if [ "$RC" -eq 0 ]; then
    pass_case "encrypted download exit 0"
else
    fail_case "encrypted download exit 0 (got $RC)"
fi

GOT="$(sha1sum "$D/t1.bin" 2>/dev/null | awk '{print $1}')"
if [ "$GOT" = "$WANT" ]; then
    pass_case "byte-verified download (sha1 == expected)"
else
    fail_case "byte-verified download (sha1 got '$GOT' want '$WANT')"
fi

if grep -aq 'mse stage=done' "$LOG" 2>/dev/null; then
    pass_case "real MSE handshake reached stage=done"
else
    fail_case "real MSE handshake reached stage=done"
fi
if grep -aq 'handshake ok enc' "$LOG" 2>/dev/null; then
    pass_case "encrypted BitTorrent handshake accepted"
else
    fail_case "encrypted BitTorrent handshake accepted"
fi
if grep -aq 'frame id=6' "$OUT/pe_py.log" 2>/dev/null; then
    pass_case "responder observed an encrypted request (id=6)"
else
    fail_case "responder observed an encrypted request (id=6)"
fi

# Non-vacuousness: prove this exercise actually drove the encrypted path, and
# on the pre-fix client localize the expected failure to the bitfield defect.
if [ "$FAILS" -ne 0 ]; then
    if grep -aq 'mse stage=done' "$LOG" 2>/dev/null \
        && ! grep -aq 'frame id=6' "$OUT/pe_py.log" 2>/dev/null; then
        note "pre-fix divergence: MSE handshake done, responder saw no request (id=6)."
        note "  cause = piece.bitGet decodes the peer bitfield LSB-first vs BT MSB-first,"
        note "          so the client sees an empty peer and never sends requests."
    fi
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_refseed_py summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_REFSEED_PY FAIL"
    exit 1
fi
echo "TIER_REFSEED_PY PASS"
exit 0
