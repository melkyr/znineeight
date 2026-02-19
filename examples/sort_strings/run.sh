#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG0="$SCRIPT_DIR/../../zig0"
cd "$SCRIPT_DIR"

echo "Compiling sort_strings..."
mkdir -p output
$ZIG0 sort_strings.zig -o output/
cd output
gcc -std=c89 -pedantic -Wno-pointer-sign -I. -o sort_strings main.c ../../../src/runtime/zig_runtime.c -I../../../src/include
./sort_strings
