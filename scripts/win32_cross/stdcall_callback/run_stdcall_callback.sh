#!/usr/bin/env bash
# Phase 3.5 Task 5 ABI evidence: cross-build the Z98 stdcall callbacks with
# i686-w64-mingw32-gcc, show the callee-cleanup epilogue, and run the C host
# under Wine (CreateThread callback + direct stdcall function-pointer calls).
#
# usage: run_stdcall_callback.sh <zig1>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ZIG1="${1:?usage: run_stdcall_callback.sh <zig1>}"
WORK="${WORK:-/tmp/z98_stdcall_callback}"
GCC="${CROSS_GCC:-i686-w64-mingw32-gcc}"
OBJDUMP="${CROSS_OBJDUMP:-i686-w64-mingw32-objdump}"
DUMP="$WORK/dump"
OBJ="$WORK/obj"

rm -rf "$WORK"
mkdir -p "$DUMP" "$OBJ"

cd "$ROOT"
"$ZIG1" -osw -ffast --dump-c89 --output-dir "$DUMP" scripts/win32_cross/stdcall_callback/cb_def.zig

for f in "$DUMP"/*.c; do
    "$GCC" -std=c89 -m32 -Wall -Wno-long-long -Wno-pointer-sign -I "$DUMP" \
        -c "$f" -o "$OBJ/$(basename "${f%.c}").o"
done
"$GCC" -std=c89 -m32 -Wall -Wno-long-long -Wno-pointer-sign \
    -c scripts/win32_cross/stdcall_callback/host.c -o "$OBJ/host.o"
"$GCC" -m32 -o "$WORK/stdcalled.exe" "$OBJ"/*.o

echo "--- cb (1 arg = 4 bytes) ---"
"$OBJDUMP" -d "$WORK/stdcalled.exe" | sed -n '/<_cb@4>:/,/^$/p'
echo "--- cb2 (2 args = 8 bytes) ---"
"$OBJDUMP" -d "$WORK/stdcalled.exe" | sed -n '/<_cb2@8>:/,/^$/p'

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine32}"
export WINEARCH="${WINEARCH:-win32}"
timeout "${TIMEOUT_WINE:-120}" wine "$WORK/stdcalled.exe"
