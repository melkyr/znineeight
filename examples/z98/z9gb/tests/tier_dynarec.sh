#!/bin/sh
# tier_dynarec.sh — z9gb P5 dynarec block IR unit gate.
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else the P2 seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_dynarec)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
if [ "$#" -gt 0 ]; then shift; fi
OUT="${OUT:-/tmp/z9gb_tier_dynarec}"

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

run_unit_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/dynarec_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -I "$ROOT/sf/src" -o "$OUT/$mode" "$Z9DIR/tests/dynarec_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "dynarec $mode emits"
    else
        fail_case "dynarec $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "dynarec $mode links"
    else
        fail_case "dynarec $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "dynarec $mode runs"
    else
        fail_case "dynarec $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^dynarec ok ' "$OUT/$mode/run.out"; then
        pass_case "dynarec $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "dynarec $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

echo "== dynarec block IR builder vs interpreter oracle =="
run_unit_mode fast -ffast
run_unit_mode safe -fsafe

echo
echo "== tier_dynarec summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DYNAREC FAIL"
    exit 1
fi
echo "TIER_DYNAREC PASS"
exit 0
