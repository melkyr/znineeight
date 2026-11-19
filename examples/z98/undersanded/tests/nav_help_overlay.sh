#!/bin/sh
# nav_help_overlay.sh — focused regression for the dock help-overlay precedence.
#
# Opens help at the dock, presses Esc, reopens it, presses q (then y so a buggy
# quit prompt would save and quit). The driver's sentinel save0.dat must remain
# byte-identical and no quit prompt may appear.
#
# Env: ZIG compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT scratch dir (default /tmp/undersanded_nav_help)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_nav_help}"

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/run"
cd "$ROOT" || exit 1

if ! "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
    "$SCRIPT_DIR/nav_help_overlay_test.zig" >"$OUT/zig.log" 2>&1; then
    echo "FAIL: nav_help_overlay_test.zig -fsafe -W compile failed"
    tail -20 "$OUT/zig.log"
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/nav_help_overlay_test" \
    >"$OUT/link.log" 2>&1; then
    echo "FAIL: native link failed"
    tail -20 "$OUT/link.log"
    exit 1
fi

cd "$OUT/run" || exit 1
printf '?\033?qy' | timeout 30 "$OUT/nav_help_overlay_test" \
    >"$OUT/run.log" 2>&1
RC=$?

FAILS=0
fail() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
pass() { echo "ok   - $1"; }

if [ "$RC" -eq 0 ]; then
    pass "driver exits 0"
else
    fail "driver exit $RC"
fi
if grep -qx 'nav_help_overlay_test PASS' "$OUT/run.log"; then
    pass "driver asserts sentinel/no-bak/dock/money"
else
    fail "driver did not print PASS"
fi
if grep -qF 'UNDERSANDED  HELP' "$OUT/run.log"; then
    pass "help overlay rendered"
else
    fail "help overlay never rendered"
fi
if grep -qF 'UNDERSANDED  DOCK' "$OUT/run.log"; then
    pass "loop continued to the dock"
else
    fail "dock screen missing from loop output"
fi
if grep -qF 'Save before quitting?' "$OUT/run.log"; then
    fail "quit prompt fired while help was open"
else
    pass "no quit prompt while help was open"
fi

if [ "$FAILS" -ne 0 ]; then
    echo "nav_help_overlay FAIL $FAILS"
    exit 1
fi
echo "nav_help_overlay PASS"
