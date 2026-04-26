#!/bin/bash
set -e

# This script verifies that the header include order is correct.
# It is used by the CI/regression test suite.

TEMP_DIR="test/regression/temp"
mkdir -p "$TEMP_DIR"

./zig0 test/regression/header_repro.zig -o "$TEMP_DIR/app" > /dev/null 2>&1

HEADER_FILE="$TEMP_DIR/header_repro.h"

if [ ! -f "$HEADER_FILE" ]; then
    echo "FAIL: header_repro.h not found"
    exit 1
fi

INCLUDE_LINE=$(grep -n "include \"header_repro_mod.h\"" "$HEADER_FILE" | cut -d: -f1)
STRUCT_LINE=$(grep -n "struct Optional_zS_.*_Data" "$HEADER_FILE" | head -n 1 | cut -d: -f1)

if [ "$INCLUDE_LINE" -lt "$STRUCT_LINE" ]; then
    echo "PASS: include appears before struct definition ($INCLUDE_LINE < $STRUCT_LINE)"
else
    echo "FAIL: include appears after struct definition ($INCLUDE_LINE >= $STRUCT_LINE)"
    exit 1
fi

gcc -m32 -std=c89 -pedantic -Werror -Wno-long-long -Wno-pointer-sign -c "$TEMP_DIR/header_repro.c" -Isrc/include -I"$TEMP_DIR" -o "$TEMP_DIR/header_repro.o"
echo "PASS: Compiled successfully with gcc -std=c89 -pedantic"

rm -rf "$TEMP_DIR"
