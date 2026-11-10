#!/bin/sh
# tier_smoke.sh — z9gb P1 gate: platform table + headless backend.
#
# Task 1 scope: both platform modules must dump cleanly, appear in the emitted
# C, and pull in no Win32/DirectX header. main.zig arrives in Task 2; this
# script is extended there to build the CLI and check the deterministic
# framebuffer.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_smoke)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_tier_smoke}"

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

# Dump one module to stdout (module-only C, no runtime PAL) and assert that
# its entry symbol appears and that it imports no Win32/DirectX header.
dump_module() {
    label="$1"
    src="$2"
    marker="$3"
    dump="$OUT/$label.c"
    if timeout 120 "$ZIG" -ffast --dump-c89 "$src" >"$dump" 2>"$OUT/$label.err"; then
        pass_case "$label dumps (rc=0)"
    else
        fail_case "$label dumps (rc=0)"
        tail -20 "$OUT/$label.err" | sed 's/^/       /'
        return
    fi
    if grep -q "$marker" "$dump"; then
        pass_case "$label appears in the dump ($marker)"
    else
        fail_case "$label appears in the dump ($marker)"
    fi
    if grep -Eq 'windows\.h|ddraw\.h|dsound\.h|dinput\.h|d3d[0-9]*\.h' "$dump"; then
        fail_case "$label imports no Win32/DirectX header"
    else
        pass_case "$label imports no Win32/DirectX header"
    fi
}

cd "$ROOT" || exit 1
dump_module backend examples/z98/z9gb/platform/backend.zig platformNoop
dump_module headless examples/z98/z9gb/platform/headless.zig platformHeadless

echo
echo "== tier_smoke summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_SMOKE FAIL"
    exit 1
fi
echo "TIER_SMOKE PASS"
exit 0
