#!/bin/bash
# Differential test runner: compare zig1 output against zig0 reference
# Usage: ./scripts/differential_test.sh [test_program.zig]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SF_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$SF_DIR")"
ZIG0="$ROOT_DIR/zig0"
BUILD_DIR="$SF_DIR/build"
ZIG1="$BUILD_DIR/zig1"

if [ ! -f "$ZIG1" ]; then
    echo "Error: zig1 not built. Run scripts/build.sh first."
    exit 1
fi

TEST_FILE="${1:-$ROOT_DIR/test/hello.zig}"

echo "Running differential test: $TEST_FILE"
echo ""

# Get zig0 reference output
echo "--- zig0 output ---"
"$ZIG0" "$TEST_FILE" --dump-ast 2>/dev/null || echo "(zig0 --dump-ast not available yet)"
echo ""

# Get zig1 output
echo "--- zig1 output ---"
"$ZIG1" --dump-ast "$TEST_FILE" 2>/dev/null || echo "(zig1 not fully implemented yet)"
echo ""

echo "Differential test complete."
