#!/bin/sh
# tier_real.sh — z9torr M4 best-effort real-swarm gate.
#
# POSIX sh. Run from anywhere (paths resolved from this script).
#
# This tier is NOT part of the hard CI gate set (spec §6: the eight mock/self
# tiers are the hard gate). It reaches the public internet, which the build
# environment may deny; reachability is environmental, not a code defect. It
# therefore reports honestly and never passes silently:
#
#   exit 0  PASS  measurable progress was observed (resume sidecar / fetched
#                 bytes / "download complete").
#   exit 77 SKIP  a real attempt was made or a precondition was missing, AND the
#                 client exited with a recognized environmental code (spec §8:
#                 2 parse, 3 tracker, 4 peer, 5 disk; plus 124 bounded-timeout):
#                 no torrent, no egress, tracker unreachable, no reachable peers,
#                 or handshake/MSE rejection. An explicit `SKIP: <reason>` line
#                 is printed.
#   exit 1  FAIL  a build/link error, an unexpected internal state, or any other
#                 nonzero client exit (crash/signal, e.g. 139 = SIGSEGV, or an
#                 unknown code) — a defect is never masked as an environmental
#                 SKIP.
#
# The client always attempts MSE/PE encrypted-first (spec §4.2); it uses a UDP
# tracker (BEP 15) whenever the torrent lists a `udp://` announce, else the HTTP
# tracker (spec §4.3); DHT (spec §4.4) defaults to public bootstrap routers and
# can be disabled with `Z9TORR_REAL_DHT=`. A real torrent is used from
# `Z9TORR_REAL_TORRENT` when set, else the diagnostic Debian torrent under
# `lin_bin/` when present.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_real}"
SEED="${Z9TORR_SEED:-12345}"

# Best-effort knobs (all optional):
#   Z9TORR_REAL_TORRENT  explicit real .torrent path
#   Z9TORR_REAL_DHT      DHT bootstrap host[:port][,...] (default: public
#                        routers; set to empty to disable DHT)
#   Z9TORR_REAL_TIMEOUT  bounded run seconds (default 90)
TORRENT="${Z9TORR_REAL_TORRENT:-}"
BOOT="${Z9TORR_REAL_DHT-router.bittorrent.com:6881,dht.transmissionbt.com:6881,dht.libtorrent.org:25401}"
RUN_SECS="${Z9TORR_REAL_TIMEOUT:-90}"

# Conventional "skipped" status (autotools/automake). Distinct from PASS (0)
# and FAIL (1) so a silent no-op can never be mistaken for success.
SKIP_EXIT=77

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

# Print an explicit, classified SKIP and exit with the defined skip status.
skip() {
    echo
    echo "SKIP: $1"
    echo "== tier_real summary: SKIP ($PASSES passed, $FAILS failed; reason: $1) =="
    echo "TIER_REAL SKIP"
    exit "$SKIP_EXIT"
}

rm -rf "$OUT"
mkdir -p "$OUT/work"
WORK="$OUT/work"

# A connect attempt is the only reachability probe available here (no ss/lsof).
port_busy() {
    bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}
# Egress probe against well-known anycast resolvers (informational: used only
# to classify a tracker failure as no-egress vs tracker-down).
egress_ok=0
for _hp in "1.1.1.1:443" "1.1.1.1:53" "8.8.8.8:53"; do
    _h="${_hp%:*}"
    _p="${_hp#*:}"
    if port_busy "$_h" "$_p"; then egress_ok=1; break; fi
done

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

echo "== building z9torr (binding recipe) =="
cd "$ROOT" || exit 1
if ! build_bin "$OUT/z9" "examples/z98/z9torr/main.zig" "z9torr"; then
    fail_case "z9torr built"
    echo "== tier_real summary: $PASSES passed, $FAILS failed =="
    echo "TIER_REAL FAIL"
    exit 1
fi
PROG="$OUT/z9/prog"
pass_case "z9torr built"

# --- locate a real torrent --------------------------------------------------
if [ -z "$TORRENT" ]; then
    for _cand in \
        "$ROOT/lin_bin/debian-13.7.0-amd64-netinst.iso.torrent" \
        "$Z9DIR/testdata/real.torrent"; do
        if [ -f "$_cand" ]; then TORRENT="$_cand"; break; fi
    done
fi
if [ -z "$TORRENT" ] || [ ! -f "$TORRENT" ]; then
    skip "no real torrent (set Z9TORR_REAL_TORRENT or provide lin_bin/debian-13.7.0-amd64-netinst.iso.torrent)"
fi

# Announce scheme: the client prefers a `udp://` announce when the torrent has
# one, else the HTTP tracker. Report which path this torrent exercises.
if grep -aq 'udp://' "$TORRENT"; then SCHEME="http+udp"; else SCHEME="http (no udp:// announce)"; fi
echo "torrent=$TORRENT"
echo "tracker-scheme=$SCHEME"
if [ -n "$BOOT" ]; then echo "dht-bootstrap=$BOOT"; else echo "dht-bootstrap=(unset)"; fi

if [ "$egress_ok" -ne 0 ]; then
    echo "egress-probe=ok"
else
    echo "egress-probe=unreachable"
fi

# --- bounded real run -------------------------------------------------------
echo "== running z9torr against the real swarm (timeout ${RUN_SECS}s) =="
D1="$WORK/run"
rm -rf "$D1"
mkdir -p "$D1"
if [ -n "$BOOT" ]; then
    ( cd "$D1" && timeout "$RUN_SECS" env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 Z9TORR_DHT="$BOOT" "$PROG" "$TORRENT" >"$D1/out.txt" 2>&1 )
else
    ( cd "$D1" && timeout "$RUN_SECS" env Z9TORR_SEED="$SEED" Z9TORR_LOG=1 "$PROG" "$TORRENT" >"$D1/out.txt" 2>&1 )
fi
RC=$?
LOG="$D1/z9torr.log"
echo "client-exit=$RC (124 = bounded-timeout after the run window)"

# --- measurable progress ----------------------------------------------------
PROGRESS=0
PDESC=""
if [ -f "$D1/.z9torr.resume" ] && [ -s "$D1/.z9torr.resume" ]; then
    PROGRESS=1
    PDESC="resume sidecar written"
fi
if grep -aq 'summary: fetched=' "$D1/out.txt" 2>/dev/null; then
    FETCHED="$(sed -n 's/.*summary: fetched=\([0-9][0-9]*\).*/\1/p' "$D1/out.txt" | tail -n 1)"
    if [ -n "$FETCHED" ] && [ "$FETCHED" -gt 0 ]; then
        PROGRESS=1
        PDESC="summary fetched=$FETCHED bytes"
    fi
fi
if grep -aq 'download complete' "$D1/out.txt" 2>/dev/null; then
    PROGRESS=1
    PDESC="download complete"
fi

if [ "$PROGRESS" -eq 1 ]; then
    pass_case "measurable real-swarm progress ($PDESC)"
    if grep -aq 'announce peers=' "$LOG" 2>/dev/null; then
        PEERS="$(sed -n 's/.*announce peers=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"
        pass_case "tracker announced peers (peers=${PEERS:-?})"
    fi
    if grep -aq 'handshake ok enc' "$LOG" 2>/dev/null; then
        pass_case "MSE/PE encrypted handshake completed against a real peer"
    fi
    echo
    echo "== tier_real summary: $PASSES passed, $FAILS failed =="
    if [ "$FAILS" -ne 0 ]; then
        echo "TIER_REAL FAIL"
        exit 1
    fi
    echo "TIER_REAL PASS"
    exit 0
fi

# --- no progress: classify honestly (never silently pass) --------------------
# The client's exit code must be a recognized environmental one. A crash/signal
# (e.g. 139 = SIGSEGV, 134 = SIGABRT), a usage error (1), or any other unknown
# nonzero exit is an UNEXPECTED internal failure — FAIL (exit 1), never masked
# as an environmental SKIP. Recognized environmental RCs (spec §8): 2 parse,
# 3 tracker, 4 peer, 5 disk, plus 124 (the bounded-window timeout). The 3/4
# cases are classified in depth from the diagnostic log below.
RC_RECOGNIZED=0
case "$RC" in
    2|3|4|5|124) RC_RECOGNIZED=1 ;;
esac
if [ "$RC_RECOGNIZED" -ne 1 ]; then
    echo "FAIL - client exit=$RC is not a recognized environmental exit (2 parse, 3 tracker, 4 peer, 5 disk, 124 bounded-timeout); treating as an internal failure"
    fail_case "recognized environmental client exit (got $RC)"
    echo
    echo "== tier_real summary: $PASSES passed, $FAILS failed =="
    echo "TIER_REAL FAIL"
    exit 1
fi

REASON="no payload progress (unclassified)"
if [ ! -f "$LOG" ]; then
    REASON="no client diagnostic log produced (build/launch problem?)"
    fail_case "client produced a diagnostic log"
    echo
    echo "== tier_real summary: $PASSES passed, $FAILS failed =="
    echo "TIER_REAL FAIL"
    exit 1
fi

# Reason precedence: an explicit parse/disk exit beats peer hints; a tracker
# exit is split by the egress probe; 124 means the bounded window elapsed.
if [ "$RC" -eq 2 ]; then
    REASON="torrent parse/open error (exit 2; not a valid single-file .torrent)"
elif [ "$RC" -eq 5 ]; then
    REASON="disk error (exit 5)"
elif [ "$RC" -eq 3 ]; then
    if [ "$egress_ok" -eq 0 ]; then
        REASON="no egress: tracker announce unreachable (exit 3)"
    else
        REASON="tracker unreachable (exit 3; egress probe ok)"
    fi
elif [ "$RC" -eq 124 ]; then
    REASON="no payload progress within the ${RUN_SECS}s bounded window (exit 124; environmental)"
elif grep -aq 'announce peers=' "$LOG" 2>/dev/null; then
    PEERS="$(sed -n 's/.*announce peers=\([0-9][0-9]*\).*/\1/p' "$LOG" | tail -n 1)"
    if [ "${PEERS:-0}" = "0" ]; then
        REASON="tracker returned no peers"
    elif grep -aq 'handshake ok enc' "$LOG" 2>/dev/null; then
        REASON="peers reachable (MSE handshake ok) but no payload progress in ${RUN_SECS}s"
    elif grep -aq 'handshake ok' "$LOG" 2>/dev/null; then
        REASON="peers reachable (plaintext handshake ok) but no payload progress in ${RUN_SECS}s"
    elif grep -aq 'mse-fail' "$LOG" 2>/dev/null; then
        REASON="TCP connects succeeded but MSE handshake closed/failed (${PEERS} announced; environmental)"
    elif grep -aq 'handshake-fail' "$LOG" 2>/dev/null; then
        REASON="TCP connects succeeded but the BitTorrent handshake failed (${PEERS} announced)"
    elif grep -aq 'connect-fail' "$LOG" 2>/dev/null; then
        REASON="no peer TCP connect succeeded (egress/NAT) despite ${PEERS} announced"
    else
        REASON="announced peers=${PEERS} but none produced payload progress"
    fi
elif [ "$egress_ok" -eq 0 ]; then
    REASON="no egress: no TCP reachability and no tracker announce"
else
    REASON="tracker announce failed before any peer (exit $RC)"
fi

skip "$REASON"
