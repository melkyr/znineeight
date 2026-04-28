#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SF_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$SF_DIR")"
ZIG0="$ROOT_DIR/zig0"
BUILD_DIR="$SF_DIR/build"

echo "=== Building zig1 (Z98 self-hosted compiler) ==="

if [ ! -f "$ZIG0" ]; then
    echo "Bootstrapping zig0 from source..."
    g++ -std=c++98 -Isrc/include "$ROOT_DIR/src/bootstrap/bootstrap_all.cpp" -o "$ZIG0"
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Compiling Z98 to C89..."
(cd "$ROOT_DIR" && "$ZIG0" -o "$WORK_DIR/output.c" sf/src/main.zig) > /dev/null

echo "Compiling C89 to binary..."
mkdir -p "$BUILD_DIR"
gcc -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-unused-but-set-variable \
    -Wno-implicit-function-declaration -I"$ROOT_DIR/include" \
    "$WORK_DIR"/*.c -o "$BUILD_DIR/zig1"

echo "Build complete: $BUILD_DIR/zig1"
echo "Run: $BUILD_DIR/zig1 [input.zig]"
