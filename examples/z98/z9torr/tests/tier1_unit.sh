#!/bin/sh
# tier1_unit.sh — z9torr unit gate: build + run the orphaned testdata
# harnesses (ratelimit_test, scheduler_test, stats_test). Each is a Z98
# executable built with the binding seed recipe; any build failure or non-zero
# run exit fails the gate. Wired into tests/tier1.sh so it runs with the
# milestone gate set.
#
# Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier1_unit}"

UNITS="ratelimit_test scheduler_test stats_test"

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

cd "$ROOT" || exit 1
fails=0
for name in $UNITS; do
    dir="$OUT/$name"
    mkdir -p "$dir"
    if ! timeout 120 "$ZIG" -fsafe -o "$dir" "examples/z98/z9torr/testdata/$name.zig" >"$dir/zig.log" 2>&1; then
        echo "FAIL - $name: zig compile (see $dir/zig.log)"
        fails=$((fails + 1))
        continue
    fi
    if ! sh "$dir/build_target.sh" linux "$dir/prog" >"$dir/build.log" 2>&1; then
        echo "FAIL - $name: target link (see $dir/build.log)"
        fails=$((fails + 1))
        continue
    fi
    if [ ! -x "$dir/prog" ]; then
        echo "FAIL - $name: binary not built"
        fails=$((fails + 1))
        continue
    fi
    if "$dir/prog" >"$dir/out.txt" 2>&1; then
        echo "ok   - $name ($(cat "$dir/out.txt"))"
    else
        rc=$?
        echo "FAIL - $name: exit $rc (see $dir/out.txt)"
        fails=$((fails + 1))
    fi
done

if [ "$fails" -ne 0 ]; then
    echo "== tier1_unit: $fails FAILED =="
    exit 1
fi
echo "== tier1_unit: all passed =="
exit 0
