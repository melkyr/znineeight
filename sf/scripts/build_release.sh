#!/usr/bin/env bash
# Build the release binary (zig1) from sf/src/main.zig
# Uses isolated output directory to prevent stale .c/.h contamination.
set -e

SCRIPT_DIR="$(dirname "$0")"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$ROOT_DIR/build/out_release"

echo "=== [release] Building zig0 ==="
mkdir -p "$ROOT_DIR/build"
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o "$ROOT_DIR/build/zig0"

echo "=== [release] Cleaning output dir ==="
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "=== [release] zig0 → C89 ==="
"$ROOT_DIR/build/zig0" --header-priority-include -o "$OUT_DIR/zig1.c" sf/src/main.zig

echo "=== [release] gcc -m32 ==="
gcc -m32 -std=c89 \
    -Wno-long-long \
    -Wno-pointer-sign \
    -Wno-implicit-function-declaration \
    -Iinclude \
    "$OUT_DIR"/*.c \
    -o "$OUT_DIR/zig1"

echo "=== [release] Done: $OUT_DIR/zig1 ==="
