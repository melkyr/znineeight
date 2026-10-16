#!/bin/sh
# tier_console.sh — z9play M5 Task 2 gate: Linux raw-console key input.
#
# Builds tests/console_test.zig with the binding seed recipe under -fsafe, then
# runs it under a pty (`script`) and asserts:
#   1. the test exits 0 and prints the PASS line — i.e. `termEnterRaw` really
#      disabled echo/canonical mode (ECHO/ICANON cleared, VMIN=VTIME=0, read
#      back from the live termios), a key written through the pty was returned
#      by `readKey`, an external SIGINT was surfaced as `Key.sigint`, and
#      `termLeaveRaw` restored the original termios (c_iflag/c_lflag/c_cc);
#   2. END-TO-END no-echo: the harness sends the key only after the program
#      signals (via a ready marker) that raw mode is active, so the key must
#      never appear in the pty output; an echo leak fails this check.
#
# Non-vacuous: the PASS line is unreachable unless the live-termios checks and
# the restore comparison hold (a control run with ECHO left on fails with
# "echo not disabled"), and the key feed is proven live because the program
# blocks until the byte arrives.
#
# Exits non-zero on any failure and prints a PASS/FAIL summary. POSIX sh +
# coreutils + `script` (pty). Run from anywhere (paths resolved from the
# script).
#
# Env: ZIG  compiler (default the v98 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_console)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed_v98/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_console}"
KEY_CHAR='@'

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed"
    exit 1
fi
if ! command -v script >/dev/null 2>&1; then
    echo "FAIL: 'script' (pty) not found; cannot run the console key test"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== building console_test (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9play/tests/console_test.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -20 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
PROG="$OUT/prog"
if [ ! -x "$PROG" ]; then
    echo "FAIL: $PROG not built"
    exit 1
fi

MARKER="$OUT/ready"
export Z9PLAY_CONSOLE_MARKER="$MARKER"
rm -f "$MARKER"

echo "== console_test under a pty (script) =="
# The writer waits for the program's ready marker (raw mode already active)
# before sending the key; it then waits for the PASS/FAIL line before closing
# the pipe, so the pty is never starved of input.
(
    i=0
    while [ ! -e "$MARKER" ] && [ "$i" -lt 2000 ]; do sleep 0.01; i=$((i + 1)); done
    printf '%s' "$KEY_CHAR"
    j=0
    while [ "$j" -lt 2000 ]; do
        if grep -q 'console_test: \(PASS\|FAIL\)' "$OUT/console.out" 2>/dev/null; then break; fi
        sleep 0.01
        j=$((j + 1))
    done
) | timeout 60 script -qec "$PROG" /dev/null >"$OUT/console.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "console_test exit 0"
else
    fail_case "console_test exit 0 (got $rc)"
fi

if grep -q 'console_test: PASS echo=off key=64 sigint=1 restored=1' "$OUT/console.out"; then
    pass_case "raw enter/read/sigint/restore asserted by the program"
else
    fail_case "console_test PASS line missing ($(tr -d '\r' <"$OUT/console.out" 2>/dev/null))"
fi

if [ -e "$MARKER" ]; then
    pass_case "ready marker created (key-feed sync point reached)"
else
    fail_case "ready marker not created (program never entered raw mode)"
fi

# Echo leak: with ECHO off the pty must not echo the injected key. The program
# prints only words/decimals, so any literal '@' in the pty log is an echo.
at_count="$(tr -cd "$KEY_CHAR" <"$OUT/console.out" 2>/dev/null | wc -c | tr -d ' ')"
if [ "$at_count" -eq 0 ]; then
    pass_case "injected key was not echoed (ECHO off end-to-end)"
else
    fail_case "injected key was echoed (ECHO leak; $at_count occurrence(s))"
fi

echo
echo "== tier_console summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_CONSOLE FAIL"
    exit 1
fi
echo "TIER_CONSOLE PASS"
exit 0
