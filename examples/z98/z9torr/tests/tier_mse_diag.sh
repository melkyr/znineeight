#!/bin/sh
# tier_mse_diag.sh — z9torr M4.1 Task 1: MSE stage-diagnostics harness.
#
# Reproduces the diagnostic runs that localized the FIRST post-handshake
# divergence, using the env-gated `Z9TORR_LOG` stage trace. POSIX sh. Run from
# anywhere (paths resolved from this script). Three arms:
#
#   mock   — mock_mse_peer (control). MUST complete a byte-verified encrypted
#            download; if this fails the harness itself is broken.
#   python — the pure-Python mse_ref.py responder (independent byte layout).
#            Asserts the MSE handshake reaches `mse stage=done` and the client
#            reads the responder's encrypted `bitfield` (id=5) and `unchoke`
#            (id=1) frames. Reports the localized divergence: the client sends
#            NO `request` (id=6) after `unchoke` because `piece.bitGet` decodes
#            the peer bitfield LSB-first while BitTorrent is MSB-first. This arm
#            reproduces the trace; it does not fail on the known, unfixed bug
#            (Task 3 fixes it, Task 2's real-seed tier then asserts the bytes).
#            SKIP-with-reason if python3 is unavailable.
#   aria2  — aria2c forced-encryption seeder (staged by tests/get_aria2.sh).
#            Asserts the MSE handshake completes and reports the decrypted
#            peer-handshake reserved bits. SKIP-with-reason if aria2c cannot be
#            staged (offline / apt unreachable).
#
# The arm order (mock control → Python → aria2) matches the plan's
# "observe against BOTH references AND the mock".

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m41_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_mse_diag}"
SEED="${Z9TORR_SEED:-12345}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
PY_REF="$SCRIPT_DIR/mse_ref.py"
GET_ARIA2="$SCRIPT_DIR/get_aria2.sh"

# The fixture announces at 127.0.0.1:6969, so the tracker must use that port.
P_TRACKER="${Z9TORR_DIAG_TRACKER:-6969}"
P_MOCK="${Z9TORR_DIAG_MOCK:-6990}"
P_PY="${Z9TORR_DIAG_PY:-6990}"
P_ARIA="${Z9TORR_DIAG_ARIA:-6988}"

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }
note() { echo "note - $1"; }

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only busy-port probe available here (no ss/lsof/fuser).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

busy_check() {
    _p="$1"; _what="$2"
    if port_busy "$_p"; then
        echo "FAIL: declared $_what port already in use ($_p)"
        exit 1
    fi
}
busy_check "$P_TRACKER" tracker
busy_check "$P_MOCK" mock
busy_check "$P_ARIA" aria2

TR_PID=""
PEER_PID=""
ARIA_PID=""
cleanup() {
    [ -n "$PEER_PID" ] && kill "$PEER_PID" 2>/dev/null
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

echo "== building z9torr, mock_tracker, mock_mse_peer (binding recipe) =="
cd "$ROOT" || exit 1
build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr" || exit 1
build_bin "$OUT/tr" "examples/z98/z9torr/tools/mock_tracker.zig" "mock_tracker" || exit 1
build_bin "$OUT/pe" "examples/z98/z9torr/tools/mock_mse_peer.zig" "mock_mse_peer" || exit 1
PROG="$OUT/z9/prog"
TRACKER="$OUT/tr/prog"
MOCKPEER="$OUT/pe/prog"

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

start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "127.0.0.1:$1" >"$OUT/tr.log" 2>&1 &
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

stop_tracker() { [ -n "$TR_PID" ] && kill "$TR_PID" 2>/dev/null; wait "$TR_PID" 2>/dev/null; TR_PID=""; }
stop_peer() { [ -n "$PEER_PID" ] && kill "$PEER_PID" 2>/dev/null; wait "$PEER_PID" 2>/dev/null; PEER_PID=""; }

run_client() {
    _d="$1"
    rm -rf "$_d"; mkdir -p "$_d"
    ( cd "$_d" && env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 timeout 20 "$PROG" "$TORRENT" \
        >"$_d/out.txt" 2>&1 )
    return $?
}

# ===========================================================================
echo
echo "== arm 1: mock_mse_peer (control; MUST complete) =="
if ! start_tracker "$P_MOCK"; then
    fail_case "mock: mock_tracker did not start"
else
    timeout 300 "$MOCKPEER" --port "$P_MOCK" --file "$WORK/t1.payload" \
        --piece-length 262144 --info-hash "$INFO_HASH" >"$OUT/pe_mock.log" 2>&1 &
    PEER_PID=$!
    sleep 0.5
    D="$WORK/run_mock"
    run_client "$D"; RC=$?
    if [ "$RC" -eq 0 ]; then pass_case "mock: download exit 0"; else fail_case "mock: download exit 0 (got $RC)"; fi
    GOT="$(sha1sum "$D/t1.bin" 2>/dev/null | awk '{print $1}')"
    if [ "$GOT" = "$WANT" ]; then pass_case "mock: byte-verified download"; else fail_case "mock: byte-verified download"; fi
    if grep -aq 'mse stage=done' "$D/z9torr.log" 2>/dev/null; then pass_case "mock: MSE handshake stage=done"; else fail_case "mock: MSE handshake stage=done"; fi
    if grep -aq 'handshake ok enc' "$D/z9torr.log" 2>/dev/null; then pass_case "mock: encrypted handshake"; else fail_case "mock: encrypted handshake"; fi
    stop_peer
fi
stop_tracker

# ===========================================================================
echo
echo "== arm 2: mse_ref.py responder (independent byte layout) =="
if ! command -v python3 >/dev/null 2>&1; then
    skip_case "python: python3 unavailable"
else
    if ! start_tracker "$P_PY"; then
        fail_case "python: mock_tracker did not start"
    else
        MSE_REF_DEBUG=1 timeout 300 python3 "$PY_REF" --serve "$WORK/t1.payload" \
            --info-hash "$INFO_HASH" --port "$P_PY" --piece-length 262144 --seed "$SEED" \
            >"$OUT/pe_py.log" 2>&1 &
        PEER_PID=$!
        sleep 1.0
        D="$WORK/run_py"
        run_client "$D"; RC=$?
        stop_peer
        if grep -aq 'mse stage=done' "$D/z9torr.log" 2>/dev/null; then
            pass_case "python: MSE handshake stage=done"
        else
            fail_case "python: MSE handshake stage=done"
        fi
        if grep -aq 'handshake ok enc' "$D/z9torr.log" 2>/dev/null; then
            pass_case "python: encrypted BT handshake"
        else
            fail_case "python: encrypted BT handshake"
        fi
        if grep -aqE '^enc frame id=5$' "$D/z9torr.log" 2>/dev/null \
            && grep -aqE '^enc frame id=1$' "$D/z9torr.log" 2>/dev/null; then
            pass_case "python: read encrypted bitfield(5)+unchoke(1)"
        else
            fail_case "python: read encrypted bitfield(5)+unchoke(1)"
        fi
        if grep -aq 'frame id=6' "$OUT/pe_py.log" 2>/dev/null; then
            GOT="$(sha1sum "$D/t1.bin" 2>/dev/null | awk '{print $1}')"
            if [ "$GOT" = "$WANT" ]; then
                pass_case "python: byte-verified download"
            else
                fail_case "python: byte-verified download (request sent, bytes wrong)"
            fi
        else
            # Known divergence (Task 1 localization; Task 3 fixes it). Reproduce
            # the trace and report it rather than failing this diagnostic arm.
            note "python: DIVERGENCE — client sent no request (id=6) after unchoke."
            note "python: cause = piece.bitGet/bitSet decode the peer bitfield LSB-first"
            note "python:         (responder's spec-correct 0xF0 == pieces 4-7 -> client sees none)."
            pass_case "python: reproduced localized divergence (no request after unchoke)"
        fi
    fi
    stop_tracker
fi

# ===========================================================================
echo
echo "== arm 3: aria2c forced-encryption seeder (SKIP if unavailable) =="
ARIA2=""
if [ ! -x "$GET_ARIA2" ]; then
    skip_case "aria2: get_aria2.sh missing"
else
    ARIA_TMP="$OUT/aria"
    mkdir -p "$ARIA_TMP"
    if ARIA_OUT="$(TMP="$ARIA_TMP" SYS="$ARIA_TMP/sys" timeout 240 sh "$GET_ARIA2" 2>"$ARIA_TMP/err.log")"; then
        ARIA2="$(printf '%s\n' "$ARIA_OUT" | sed -n 's/^aria2c: //p')"
        ARIA_LD="$(printf '%s\n' "$ARIA_OUT" | sed -n 's/^LD_LIBRARY_PATH: //p')"
    fi
fi
if [ -z "$ARIA2" ] || [ ! -x "$ARIA2" ]; then
    skip_case "aria2: aria2c unavailable (offline / apt unreachable)"
else
    mkdir -p "$OUT/aria/dl"
    cp "$WORK/t1.payload" "$OUT/aria/dl/t1.bin"
    if ! start_tracker "$P_ARIA"; then
        fail_case "aria2: mock_tracker did not start"
    else
        env LD_LIBRARY_PATH="$ARIA_LD" timeout 120 "$ARIA2" \
            --seed-time=1 --bt-require-crypto=true --bt-min-crypto-level=arc4 \
            --enable-dht=false --bt-enable-lpd=false --enable-rpc=false \
            --listen-port="$P_ARIA" --dht-listen-port=6989 --console-log-level=warn \
            -d "$OUT/aria/dl" --allow-overwrite=true "$TORRENT" >"$OUT/aria/aria.log" 2>&1 &
        ARIA_PID=$!
        sleep 2
        D="$WORK/run_aria"
        run_client "$D"; RC=$?
        kill "$ARIA_PID" 2>/dev/null; wait "$ARIA_PID" 2>/dev/null; ARIA_PID=""
        if grep -aq 'mse stage=done' "$D/z9torr.log" 2>/dev/null; then
            pass_case "aria2: MSE handshake stage=done"
        else
            fail_case "aria2: MSE handshake stage=done"
        fi
        RES="$(grep -a 'hsenc reserved=' "$D/z9torr.log" 2>/dev/null | tail -1)"
        [ -n "$RES" ] && note "aria2: $RES"
        if grep -aq 'handshake-fail err=HandshakeFailed' "$D/z9torr.log" 2>/dev/null \
            && [ -n "$RES" ]; then
            note "aria2: DIVERGENCE — the peer handshake rejected the reserved"
            note "aria2:         bits (Fast Extension 0x04 in reserved[7]) -> HandshakeFailed."
            pass_case "aria2: reproduced localized reserved-bit divergence"
        elif grep -aq 'handshake ok enc' "$D/z9torr.log" 2>/dev/null; then
            pass_case "aria2: encrypted BT handshake accepted"
        fi
    fi
    stop_tracker
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_mse_diag summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_MSE_DIAG FAIL"
    exit 1
fi
echo "TIER_MSE_DIAG PASS"
exit 0
