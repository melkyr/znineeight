#!/bin/sh
# tier_dht.sh — z9torr M4 gate: DHT (BEP 5 / KRPC) get_peers discovery.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. build z9torr with the binding seed recipe (main.zig is the entry);
#   2. run its in-process DHT self-test, which binds two UDP nodes on loopback:
#      node B knows a peer for an info_hash, node A sends a real KRPC
#      `get_peers`, and must learn that peer from B's `values` response.
#   3. assert exit 0 and the PASS line.
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier_dht}"

# Two loopback UDP ports for the in-process nodes (tier_udp_tracker uses
# 6975/6976). UDP has no /dev/tcp probe, so a busy port surfaces as the self-
# test's binding failure, which fails the gate loudly instead of hanging.
P_DHT_A="${Z9TORR_DHT_PORT_A:-6977}"
P_DHT_B="${Z9TORR_DHT_PORT_B:-6978}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

# --- build (binding recipe) -------------------------------------------------
echo "== building z9torr (binding recipe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -ffast -o "$OUT" "examples/z98/z9torr/main.zig" >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile z9torr (see $OUT/zig.log)"
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link z9torr (see $OUT/build.log)"
    exit 1
fi
PROG="$OUT/prog"
if [ ! -x "$PROG" ]; then
    echo "FAIL: z9torr not built"
    exit 1
fi
pass_case "z9torr built"

# --- in-process DHT self-test ----------------------------------------------
echo "== running DHT get_peers two-node self-test =="
env Z9TORR_DHT_SELFTEST=1 Z9TORR_DHT_PORT_A="$P_DHT_A" Z9TORR_DHT_PORT_B="$P_DHT_B" \
    "$PROG" >"$OUT/out.txt" 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    pass_case "dht self-test exit 0"
else
    fail_case "dht self-test exit 0 (got $RC; see $OUT/out.txt)"
fi
if grep -aq 'dht selftest: PASS' "$OUT/out.txt"; then
    pass_case "dht self-test reports PASS"
else
    fail_case "dht self-test reports PASS"
fi
if grep -aq 'get_peers two-node discovery' "$OUT/out.txt"; then
    pass_case "dht discovery exercised get_peers"
else
    fail_case "dht discovery exercised get_peers"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier_dht summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DHT FAIL"
    exit 1
fi
echo "TIER_DHT PASS"
exit 0
