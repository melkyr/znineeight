#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIG0="$SCRIPT_DIR/../../zig0"
cd "$SCRIPT_DIR"

echo "Compiling func_ptr_return..."
mkdir -p output
$ZIG0 func_ptr_return.zig -o output/
cd output
gcc -m32 -Wno-long-long -std=c89 -pedantic -Wno-pointer-sign -I. -o app *.c ../../../src/runtime/zig_runtime.c -I../../../src/include -Wno-error=implicit-function-declaration
./app
