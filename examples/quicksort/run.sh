#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG0="$SCRIPT_DIR/../../zig0"
cd "$SCRIPT_DIR"

echo "Compiling quicksort..."
mkdir -p output
$ZIG0 quicksort.zig -o output/
cd output
gcc -std=c89 -pedantic -Wno-pointer-sign -I. -o quicksort main.c ../../../src/runtime/zig_runtime.c -I../../../src/include
./quicksort
