#!/bin/sh
# tier_math.sh — z9play M2 gate (Task 4): pure-Z98 std_math f64 sqrt/sin/cos.
#
# Builds a z9play-local Z98 program (mathtest.zig) with the binding seed recipe
# under -fsafe, then:
#   1. asserts its stdout is byte-identical to the committed
#      tests/mathtest.expected (the same sqrt/sin/cos identities and f64
#      bit-pattern inputs as the std fixture stdlib_math_f64_xmod), and that the
#      process exits 0;
#   2. asserts that oracle file still matches repro/mi_matrix/
#      stdlib_math_f64_xmod/expected.txt (integration guard against drift);
#   3. asserts the linked binary imports NO libm symbol: `nm -u` shows no
#      undefined sqrt/sin/cos/pow and DT_NEEDED contains no libm (only libc);
#   4. NON-VACUOUS: a control binary that really calls sqrt() with -lm is built
#      and the same detector MUST flag it, proving the libm check is live.
# Exits non-zero on any failure and prints a PASS/FAIL summary.
# POSIX sh + coreutils + nm/objdump/gcc. Run from anywhere (paths resolved from
# this script).
#
# Env: ZIG  compiler (default the v97 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_math)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_math}"
EXPECTED="$SCRIPT_DIR/mathtest.expected"
STD_EXPECTED="$ROOT/repro/mi_matrix/stdlib_math_f64_xmod/expected.txt"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

# Undefined libm symbols (sqrt/sin/cos/pow, incl. f/l variants and versioned
# names like sqrt@GLIBC_2.0) in a linked binary. Empty output == clean.
libm_undefined() {
    nm -u "$1" 2>/dev/null | awk '{print $NF}' | grep -E '^(sqrt|sin|cos|pow)(f|l)?(@.*)?$' || true
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== building z9play mathtest (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9play/mathtest.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -20 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/mathtest" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
BIN="$OUT/mathtest"
if [ ! -x "$BIN" ]; then
    echo "FAIL: $BIN not built"
    exit 1
fi

echo "== sqrt/sin/cos identities vs committed expected =="
"$BIN" >"$OUT/stdout.txt" 2>"$OUT/stderr.txt"
rc=$?
if [ "$rc" -eq 0 ]; then pass_case "mathtest exit 0"; else fail_case "mathtest exit 0 (got $rc)"; fi
if cmp -s "$EXPECTED" "$OUT/stdout.txt"; then
    pass_case "mathtest stdout == tests/mathtest.expected"
else
    fail_case "mathtest stdout != tests/mathtest.expected"
    diff -u "$EXPECTED" "$OUT/stdout.txt" | sed 's/^/       /'
fi
if [ -f "$STD_EXPECTED" ] && cmp -s "$STD_EXPECTED" "$EXPECTED"; then
    pass_case "mathtest expected == std fixture expected (no drift)"
else
    fail_case "mathtest expected != std fixture expected"
fi

echo "== no libm linkage =="
if [ -n "$(nm -u "$BIN" 2>/dev/null)" ]; then
    pass_case "binary has undefined symbols (nm -u is meaningful)"
else
    fail_case "binary has no undefined symbols (nm -u vacuous)"
fi
bad="$(libm_undefined "$BIN")"
if [ -z "$bad" ]; then
    pass_case "no undefined libm symbol (sqrt/sin/cos/pow)"
else
    fail_case "undefined libm symbol(s) present"
    printf '%s\n' "$bad" | sed 's/^/       /'
fi
if objdump -p "$BIN" 2>/dev/null | awk '/NEEDED/{print $2}' | grep -q 'libm'; then
    fail_case "DT_NEEDED links libm"
else
    pass_case "DT_NEEDED links no libm"
fi
nonlibc="$(objdump -p "$BIN" 2>/dev/null | awk '/NEEDED/{print $2}' | grep -v '^libc\.so' || true)"
if [ -z "$nonlibc" ]; then
    pass_case "DT_NEEDED only libc"
else
    fail_case "DT_NEEDED has non-libc entries"
    printf '%s\n' "$nonlibc" | sed 's/^/       /'
fi

echo "== non-vacuous control (a real -lm sqrt MUST be detected) =="
if command -v gcc >/dev/null 2>&1; then
    printf 'extern double sqrt(double);\nvolatile double g;\nint main(void){ g = sqrt(2.0); return 0; }\n' >"$OUT/libm_control.c"
    if gcc -m32 -O0 -fno-builtin "$OUT/libm_control.c" -o "$OUT/libm_control" -lm >"$OUT/control.log" 2>&1; then
        ctrl="$(libm_undefined "$OUT/libm_control")"
        if [ -n "$ctrl" ]; then
            pass_case "detector flags a real sqrt() import"
        else
            fail_case "detector missed a real sqrt() import"
        fi
    else
        fail_case "control build failed (see $OUT/control.log)"
    fi
else
    echo "skip - gcc not found; cannot build libm control"
fi

echo
echo "== tier_math summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_MATH FAIL"
    exit 1
fi
echo "TIER_MATH PASS"
exit 0
