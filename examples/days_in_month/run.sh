#!/bin/bash
set -e
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG0="$SCRIPT_DIR/../../zig0"
cd "$SCRIPT_DIR"

echo "Compiling days_in_month..."
mkdir -p output
$ZIG0 main.zig -o output/
cd output
gcc -m32 -Wno-long-long -std=c89 -pedantic -Wno-pointer-sign -I. -o days_in_month *.c ../../../src/runtime/zig_runtime.c -I../../../src/include
./days_in_month
