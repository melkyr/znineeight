#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
BIN_DIR="$PROJECT_ROOT/bin"

echo "=== RetroZig Clean Environment Setup ==="

# Verify C++98-compatible compiler
if ! g++ --version 2>/dev/null | grep -q "g++ (GCC) [234]\."; then
    echo "INFO: Ensuring -std=c++98 flag is used for compilation."
fi

# Create isolated directories
rm -rf "$BUILD_DIR" "$BIN_DIR"
mkdir -p "$BUILD_DIR/obj" "$BIN_DIR"

# Clean root directory of legacy artifacts
rm -f "$PROJECT_ROOT/zig0" "$PROJECT_ROOT/test_runner_batch"* "$PROJECT_ROOT"/*.o

# Verify kernel32.dll dependency constraint (Linux cross-compile check)
if command -v i686-w64-mingw32-g++ >/dev/null 2>&1; then
    echo "✓ MinGW cross-compiler available for Win32 target validation"
else
    echo "INFO: Native Linux build only (no Win32 validation)"
fi

echo "✓ Build environment initialized at $BUILD_DIR"
echo "✓ Binary output directory: $BIN_DIR"
echo "✓ Ready for compilation."
