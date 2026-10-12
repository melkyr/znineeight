#!/bin/bash
# Memory profiling: verify zig1 stays within 16 MB peak
# Usage: ./scripts/memory_profile.sh [test_program.zig]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SF_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$SF_DIR")"
BUILD_DIR="$SF_DIR/build"
ZIG1="$BUILD_DIR/zig1"

if [ ! -f "$ZIG1" ]; then
    echo "Error: zig1 not built."
    exit 1
fi

TEST_FILE="${1:-$ROOT_DIR/test/hello.zig}"
MAX_MEM="${2:-16777216}"  # 16 MB default

echo "Memory profiling: $TEST_FILE"
echo "Max memory: $((MAX_MEM / 1024 / 1024)) MB"
echo ""

# Use /usr/bin/time -v on Linux for peak RSS
if command -v /usr/bin/time &>/dev/null; then
    /usr/bin/time -v "$ZIG1" --max-mem="$MAX_MEM" "$TEST_FILE" 2>&1 | grep -E "Maximum resident|peak"
else
    echo "/usr/bin/time not available; tracking allocator peak will be used."
    "$ZIG1" --max-mem="$MAX_MEM" --track-memory "$TEST_FILE"
fi

echo ""
echo "Memory profile complete."
