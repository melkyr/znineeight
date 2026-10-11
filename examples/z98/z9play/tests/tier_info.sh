#!/bin/sh
# tier_info.sh — z9play M0 gate (Task 5): `z9play --info` metadata vs golden.
#
# Builds z9play with the binding seed recipe under -fsafe, then:
#   1. for EACH fixture, asserts `--info <file>` exits 0 and its stdout is
#      byte-identical to testdata/expected/<name>.meta (the committed golden);
#   2. asserts the argument exit codes (--help/--version = 0; unknown flag /
#      missing --info argument / no arguments = 1);
#   3. NON-VACUOUS open/decoder negatives: a missing file exits 2, and a
#      non-OGG file, a truncated file, and a mutated capture pattern each
#      exit 3.
# Exits non-zero on any failure and prints a PASS/FAIL summary.
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG  compiler (default the v97 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_info)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_info}"
FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
FIXTURES="sine_mono_44100 sine_stereo_44100 sine_stereo_48000 tagged_unicode short"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== building z9play (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9play/main.zig >"$OUT/zig.log" 2>&1; then
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

echo "== --info metadata vs goldens =="
for name in $FIXTURES; do
    FIX="$FIXDIR/$name.ogg"
    EXP="$EXPDIR/$name.meta"
    "$PROG" --info "$FIX" >"$OUT/$name.out" 2>"$OUT/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "$name: --info exit 0"
    else
        fail_case "$name: --info exit 0 (got $rc)"
    fi
    if cmp -s "$EXP" "$OUT/$name.out"; then
        pass_case "$name: stdout == golden"
    else
        fail_case "$name: stdout != golden"
        diff -u "$EXP" "$OUT/$name.out" | sed 's/^/       /'
    fi
done

echo "== exit codes: arguments =="
"$PROG" --help >"$OUT/help.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then pass_case "--help exit 0"; else fail_case "--help exit 0 (got $rc)"; fi
"$PROG" --version >"$OUT/version.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then pass_case "--version exit 0"; else fail_case "--version exit 0 (got $rc)"; fi
if grep -q "z9play" "$OUT/version.out"; then pass_case "--version prints z9play"; else fail_case "--version prints z9play"; fi
"$PROG" --bogus >"$OUT/bogus.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then pass_case "unknown flag exit 1"; else fail_case "unknown flag exit 1 (got $rc)"; fi
"$PROG" --info >"$OUT/noarg.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then pass_case "--info without file exit 1"; else fail_case "--info without file exit 1 (got $rc)"; fi
"$PROG" >"$OUT/noargs.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then pass_case "no arguments exit 1"; else fail_case "no arguments exit 1 (got $rc)"; fi

echo "== exit codes: open / decoder (non-vacuous) =="
"$PROG" --info "$OUT/missing.ogg" >"$OUT/missing.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then pass_case "missing file exit 2"; else fail_case "missing file exit 2 (got $rc)"; fi

printf 'THIS IS NOT AN OGG FILE\n' >"$OUT/notogg.bin"
"$PROG" --info "$OUT/notogg.bin" >"$OUT/notogg.out" 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then pass_case "non-OGG file exit 3"; else fail_case "non-OGG file exit 3 (got $rc)"; fi

dd if="$FIXDIR/short.ogg" of="$OUT/truncated.ogg" bs=1 count=16 2>/dev/null
"$PROG" --info "$OUT/truncated.ogg" >"$OUT/truncated.out" 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then pass_case "truncated file exit 3"; else fail_case "truncated file exit 3 (got $rc)"; fi

dd if="$FIXDIR/short.ogg" of="$OUT/badcapture.ogg" bs=1 count=32 2>/dev/null
printf 'X' | dd of="$OUT/badcapture.ogg" bs=1 seek=0 conv=notrunc 2>/dev/null
"$PROG" --info "$OUT/badcapture.ogg" >"$OUT/badcapture.out" 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then pass_case "bad capture exit 3"; else fail_case "bad capture exit 3 (got $rc)"; fi

echo
echo "== tier_info summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_INFO FAIL"
    exit 1
fi
echo "TIER_INFO PASS"
exit 0
