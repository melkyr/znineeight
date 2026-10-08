#!/bin/sh
# tier1_cli.sh — CLI shape tests for z9torr (M1 Task 1).
#
# Builds the example with the binding seed recipe, then asserts the exit code
# of each CLI shape with `test $? -eq N`. Non-zero overall on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier1_cli}"

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

echo "== building z9torr CLI =="
mkdir -p "$OUT"
if ! timeout 120 "$ZIG" -ffast -o "$OUT" "$Z9DIR/main.zig"; then
    echo "FAIL: zig compile"
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    exit 1
fi
PROG="$OUT/prog"
if [ ! -x "$PROG" ]; then
    echo "FAIL: $PROG not built"
    exit 1
fi

fails=0
pass_case() { echo "ok   - $1"; }
fail_case() { echo "FAIL - $1"; fails=$((fails + 1)); }

# 1. --help -> exit 0 + usage on stdout
"$PROG" --help >"$OUT/help.out" 2>&1
if test $? -eq 0 && grep -qi "usage" "$OUT/help.out"; then
    pass_case "--help exit 0 + usage on stdout"
else
    fail_case "--help exit 0 + usage on stdout"
fi

# 2. no args -> exit 1
"$PROG" >"$OUT/noargs.out" 2>&1
if test $? -eq 1; then
    pass_case "no args exit 1"
else
    fail_case "no args exit 1"
fi

# 3. unknown flag -> exit 1
"$PROG" --bogus >"$OUT/unknown.out" 2>&1
if test $? -eq 1; then
    pass_case "unknown flag exit 1"
else
    fail_case "unknown flag exit 1"
fi

# 4. --max-peers 101 -> exit 1 (reject > 100)
"$PROG" --max-peers 101 some.torrent >"$OUT/peers.out" 2>&1
if test $? -eq 1; then
    pass_case "--max-peers 101 exit 1"
else
    fail_case "--max-peers 101 exit 1"
fi

# 5. valid file.torrent (missing file) -> exit 2
"$PROG" "$OUT/missing.torrent" >"$OUT/missing.out" 2>&1
if test $? -eq 2; then
    pass_case "missing torrent exit 2"
else
    fail_case "missing torrent exit 2"
fi

# 6. --max-down 70000 -> exit 1 (reject > 65535)
"$PROG" --max-down 70000 some.torrent >"$OUT/down.out" 2>&1
if test $? -eq 1; then
    pass_case "--max-down 70000 exit 1"
else
    fail_case "--max-down 70000 exit 1"
fi

if [ "$fails" -ne 0 ]; then
    echo "== tier1_cli: $fails FAILED =="
    exit 1
fi
echo "== tier1_cli: all passed =="
exit 0
