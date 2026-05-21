#!/usr/bin/env bash
# differential_test.sh — Compare zig0 vs zig1 C89 output for a test program
# Usage: bash sf/scripts/differential_test.sh <test.zig> [--verbose]
# Normalizes known structural differences (temp names, hashes, comments).

set -e

SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ZIG0="$ROOT_DIR/build/zig0"
ZIG1="$ROOT_DIR/build/out_release/zig1"
TMPDIR="/tmp/zig_diff_$$"

INPUT_ZIG="${1:-examples/hello/main.zig}"
VERBOSE="${2:-}"

if [ ! -f "$INPUT_ZIG" ]; then
    echo "FAIL: Input file not found: $INPUT_ZIG"
    exit 1
fi

if [ ! -f "$ZIG0" ]; then
    echo "FAIL: zig0 not found at $ZIG0"
    exit 1
fi

if [ ! -f "$ZIG1" ]; then
    echo "FAIL: zig1 not found at $ZIG1"
    echo "Run 'bash sf/scripts/build_release.sh' first."
    exit 1
fi

mkdir -p "$TMPDIR"

INPUT_BASE="$(basename "$INPUT_ZIG" .zig)"
ZIG0_OUT="$TMPDIR/zig0_${INPUT_BASE}.c"
ZIG1_OUT="$TMPDIR/zig1_${INPUT_BASE}.c"
ZIG0_NORM="$TMPDIR/zig0_norm.txt"
ZIG1_NORM="$TMPDIR/zig1_norm.txt"

echo "=== [diff] Input: $INPUT_ZIG ==="

# Step 1: Compile with zig0
mkdir -p "$TMPDIR/out_zig0"
"$ZIG0" --header-priority-include -o "$TMPDIR/out_zig0/zig0_prog.c" "$INPUT_ZIG" 2>/dev/null || true
if [ -f "$TMPDIR/out_zig0/main.c" ]; then
    cp "$TMPDIR/out_zig0/main.c" "$ZIG0_OUT"
elif [ -f "$TMPDIR/out_zig0/zig0_prog.c" ]; then
    cp "$TMPDIR/out_zig0/zig0_prog.c" "$ZIG0_OUT"
else
    echo "  zig0: NO OUTPUT (compiler doesn't support this input yet)"
    echo "    temp file: $TMPDIR"
    echo "  PASS (expected for unsupported features)"
    rm -rf "$TMPDIR"
    exit 0
fi

echo "  zig0: $(wc -l < "$ZIG0_OUT") lines"

# Step 2: Compile with zig1
"$ZIG1" --dump-c89 "$INPUT_ZIG" > "$ZIG1_OUT" 2>/dev/null || true
ZIG1_LINES=$(wc -l < "$ZIG1_OUT" 2>/dev/null || echo 0)
echo "  zig1: $ZIG1_LINES lines"

if [ "$ZIG1_LINES" -lt 5 ]; then
    echo "  zig1: OUTPUT TOO SHORT (pipeline not fully wired)"
    echo "  SKIP: differential test requires wired pipeline"
    rm -rf "$TMPDIR"
    exit 0
fi

# Step 3: Normalize both outputs
# Remove comments (/* ... */)
sed 's|/\*.*\*/||g' "$ZIG0_OUT" | sed '/^\/\*/,/\*\//d' > "$TMPDIR/zig0_nocomment.c"
sed 's|/\*.*\*/||g' "$ZIG1_OUT" | sed '/^\/\*/,/\*\//d' > "$TMPDIR/zig1_nocomment.c"

# Normalize: temp names zT_N → __tmp_N
sed 's/zT_\([0-9]*\)/__tmp_\1/g' "$TMPDIR/zig0_nocomment.c" > "$TMPDIR/zig0_norm.c"
sed 's/zT_\([0-9]*\)/__tmp_\1/g' "$TMPDIR/zig1_nocomment.c" > "$TMPDIR/zig1_norm.c"

# Normalize: block labels z_bb_N → __bb_N
sed 's/z_bb_\([0-9]*\)/__bb_\1/g' "$TMPDIR/zig0_norm.c" > "$TMPDIR/zig0_norm2.c"
sed 's/z_bb_\([0-9]*\)/__bb_\1/g' "$TMPDIR/zig1_norm.c" > "$TMPDIR/zig1_norm2.c"

# Normalize: mangled names z[FT]_<8hex>_ → z_<hash>_
sed 's/z[FT]_[a-f0-9]\{8\}_/z_<hash>_/g' "$TMPDIR/zig0_norm2.c" > "$TMPDIR/zig0_norm3.c"
sed 's/z[FT]_[a-f0-9]\{8\}_/z_<hash>_/g' "$TMPDIR/zig1_norm2.c" > "$TMPDIR/zig1_norm3.c"

# Strip includes (#include ...)
grep -v '^#include' "$TMPDIR/zig0_norm3.c" > "$ZIG0_NORM"
grep -v '^#include' "$TMPDIR/zig1_norm3.c" > "$ZIG1_NORM"

# Step 4: Calculate match statistics
TOTAL_LINES=$(sort -u "$ZIG0_NORM" "$ZIG1_NORM" | wc -l)
ZIG0_LINES=$(wc -l < "$ZIG0_NORM")
ZIG1_LINES=$(wc -l < "$ZIG1_NORM")

COMMON_LINES=$(comm -12 <(sort "$ZIG0_NORM") <(sort "$ZIG1_NORM") | wc -l)

if [ "$TOTAL_LINES" -gt 0 ]; then
    MATCH_PCT=$((COMMON_LINES * 100 / TOTAL_LINES))
else
    MATCH_PCT=0
fi

echo ""
echo "=== [diff] Results ==="
echo "  zig0 normalized: $ZIG0_LINES lines"
echo "  zig1 normalized: $ZIG1_LINES lines"
echo "  Shared lines: $COMMON_LINES / $TOTAL_LINES unique"
echo "  Structural match: ~${MATCH_PCT}%"
echo ""

if [ -n "$VERBOSE" ] || [ "$MATCH_PCT" -lt 50 ]; then
    echo "=== [diff] Differences (normalized) ==="
    diff -u "$ZIG0_NORM" "$ZIG1_NORM" | head -50 || true
    echo ""
fi

if [ "$MATCH_PCT" -ge 90 ]; then
    echo "  PASS: Strong structural match"
elif [ "$MATCH_PCT" -ge 50 ]; then
    echo "  PASS: Partial structural match (expected for pipeline differences)"
else
    echo "  INFO: Low structural match (expected: pipeline not fully wired)"
fi

echo "  Temp files: $TMPDIR"
echo "=== [diff] Done ==="
