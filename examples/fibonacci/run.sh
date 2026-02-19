#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG0="$SCRIPT_DIR/../../zig0"
cd "$SCRIPT_DIR"

echo "Compiling fibonacci..."
mkdir -p output
$ZIG0 main.zig -o output/
cd output
gcc -std=c89 -pedantic -Wno-pointer-sign -I. -o fibonacci main.c ../../../src/runtime/zig_runtime.c -I../../../src/include
./fibonacci
