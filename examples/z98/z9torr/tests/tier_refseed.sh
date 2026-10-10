#!/bin/sh
# tier_refseed.sh -- z9torr M4.1 Task 2: real-seed tier (aria2c reference).
#
# A hermetic loopback REAL-encrypted-download gate. It does NOT mock the peer:
#   * a committed deterministic single-file torrent fixture
#     (testdata/t1_single_1m.torrent; 1 MiB, 4 x 256 KiB, announce 127.0.0.1:6969);
#   * a real aria2c (staged, no root, by tests/get_aria2.sh) run as a
#     FORCED-encryption seeder (--bt-require-crypto=true --bt-min-crypto-level=arc4);
#   * mock_tracker advertising 127.0.0.1:<aria2 listen port>;
#   * the unmodified z9torr client.
# The tier asserts a byte-verified completed download (output SHA-1 == the
# fixture's expected SHA-1) after a real MSE/PE handshake and encrypted transfer.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Exits:
#   0   PASS  byte-verified encrypted download
#   1   FAIL  build error, or the download did not complete/verify
#   77  SKIP  aria2c could not be staged (offline / apt unreachable) -- with an
#             explicit `SKIP: <reason>` line, never a silent pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_refseed}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
GET_ARIA2="$SCRIPT_DIR/get_aria2.sh"

# The fixture announces at 127.0.0.1:6969, so the tracker must use that port.
P_TRACKER="${Z9TORR_RS_TRACKER:-6969}"
P_ARIA="${Z9TORR_RS_ARIA:-6975}"
P_ARIA_DHT="${Z9TORR_RS_ARIA_DHT:-6976}"
CLIENT_TIMEOUT="${Z9TORR_RS_TIMEOUT:-30}"

SKIP_EXIT=77
PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
note() { echo "note - $1"; }
skip() {
    echo
    echo "SKIP: $1"
    echo "== tier_refseed summary: SKIP ($PASSES passed, $FAILS failed; reason: $1) =="
    echo "TIER_REFSEED SKIP"
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
busy_check "$P_ARIA" aria2

TR_PID=""
ARIA_PID=""
cleanup() {
    [ -n "$ARIA_PID" ] && kill "$ARIA_PID" 2>/dev/null
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

# --- acquire aria2c (SKIP-with-reason if unavailable) -----------------------
ARIA2=""
ARIA_LD=""
if [ ! -x "$GET_ARIA2" ]; then
    skip "get_aria2.sh missing ($GET_ARIA2)"
fi
ARIA_TMP="$OUT/aria"
mkdir -p "$ARIA_TMP"
if ARIA_OUT="$(TMP="$ARIA_TMP" SYS="$ARIA_TMP/sys" timeout 240 sh "$GET_ARIA2" 2>"$ARIA_TMP/err.log")"; then
    ARIA2="$(printf '%s\n' "$ARIA_OUT" | sed -n 's/^aria2c: //p')"
    ARIA_LD="$(printf '%s\n' "$ARIA_OUT" | sed -n 's/^LD_LIBRARY_PATH: //p')"
fi
if [ -z "$ARIA2" ] || [ ! -x "$ARIA2" ]; then
    skip "aria2c unavailable (offline / apt unreachable; see $ARIA_TMP/err.log)"
fi
pass_case "aria2c staged ($(env LD_LIBRARY_PATH="$ARIA_LD" "$ARIA2" --version 2>/dev/null | head -n1))"

# --- mock lifecycle ---------------------------------------------------------
start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$P_ARIA" >"$OUT/tr.log" 2>&1 &
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

echo "== starting mock_tracker (advertises 127.0.0.1:$P_ARIA) =="
if ! start_tracker; then
    echo "FAIL: mock_tracker did not start (see $OUT/tr.log)"
    exit 1
fi

# --- aria2c forced-encryption seeder ----------------------------------------
echo "== starting aria2c forced-encryption seeder =="
mkdir -p "$OUT/aria/dl"
cp "$WORK/t1.payload" "$OUT/aria/dl/t1.bin"
env LD_LIBRARY_PATH="$ARIA_LD" timeout 120 "$ARIA2" \
    --seed-time=1 --bt-require-crypto=true --bt-min-crypto-level=arc4 \
    --enable-dht=false --bt-enable-lpd=false --enable-rpc=false \
    --listen-port="$P_ARIA" --dht-listen-port="$P_ARIA_DHT" --console-log-level=warn \
    -d "$OUT/aria/dl" --allow-overwrite=true "$TORRENT" >"$OUT/aria/aria.log" 2>&1 &
ARIA_PID=$!
sleep 2
if ! kill -0 "$ARIA_PID" 2>/dev/null; then
    echo "FAIL: aria2c seeder exited early (see $OUT/aria/aria.log)"
    exit 1
fi

# --- real encrypted download ------------------------------------------------
echo "== download t1_single_1m from aria2c (MSE) =="
D="$WORK/run"
rm -rf "$D"
mkdir -p "$D"
( cd "$D" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout "$CLIENT_TIMEOUT" \
    "$PROG" "$TORRENT" >"$D/out.txt" 2>&1 )
RC=$?
kill "$ARIA_PID" 2>/dev/null; wait "$ARIA_PID" 2>/dev/null; ARIA_PID=""
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

# Non-vacuousness: prove this exercise actually drove the encrypted path, and
# on the pre-fix client localize the expected failure to the reserved-bit defect.
if [ "$FAILS" -ne 0 ]; then
    if grep -aq 'handshake-fail err=HandshakeFailed' "$LOG" 2>/dev/null; then
        RES="$(grep -a 'hsenc reserved=' "$LOG" 2>/dev/null | tail -1)"
        note "pre-fix divergence: $RES -> HandshakeFailed"
        note "  cause = wire.reservedAccepted rejects the Fast Extension bit (reserved[7]=0x04)."
    elif grep -aq 'mse stage=done' "$LOG" 2>/dev/null; then
        note "pre-fix divergence: MSE handshake done but no byte-verified download."
    fi
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_refseed summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_REFSEED FAIL"
    exit 1
fi
echo "TIER_REFSEED PASS"
exit 0
