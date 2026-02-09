#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
BIN_DIR="$PROJECT_ROOT/bin"

echo "=== Post-Compilation Cleanup ==="

# Preserve only the final compiler binary in BIN_DIR if it exists
# Also check for zig0 in root for legacy compatibility
if [ -f "$BIN_DIR/zig0" ]; then
    find "$BIN_DIR" -type f ! -name "zig0" -delete 2>/dev/null || true
fi

# Remove object files
find "$BUILD_DIR/obj" -type f -name "*.o" -delete 2>/dev/null || true
rm -f "$PROJECT_ROOT"/*.o

# Verify no accidental stdlib dependencies in final binary
if command -v ldd >/dev/null 2>&1; then
    TARGET_BIN=""
    if [ -f "$BIN_DIR/zig0" ]; then
        TARGET_BIN="$BIN_DIR/zig0"
    elif [ -f "$PROJECT_ROOT/zig0" ]; then
        TARGET_BIN="$PROJECT_ROOT/zig0"
    fi

    if [ -n "$TARGET_BIN" ]; then
        if ldd "$TARGET_BIN" | grep -q "libc.so\|libstdc++"; then
            echo "WARNING: Final binary might have forbidden C/C++ runtime dependencies!"
        fi
    fi
fi

echo "✓ Intermediate artifacts removed"
echo "✓ Memory measurement ready for next run"
