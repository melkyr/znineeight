#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_cipher_rodata.sh [zig1]
#
# M2 T2 cipher rodata gate: proves std_cipher's AES T-tables are emitted as
# read-only rodata (not writable .bss) by the current compiler.
#
# usage: scripts/compiler/gate_cipher_rodata.sh [path/to/zig1]
#   zig1 defaults to $ROOT/zig1 if executable.
#
# Steps:
#   1. dump repro/mi_matrix/stdlib_aes_gcm_xmod (it imports std_cipher.zig);
#   2. compile every emitted .c with the canonical gcc -m32 -std=c89 -O0 flags;
#   3. `nm -S` assertions on the real T-table symbols:
#        Te0..Te3 -> type R/r, size 0x400;
#        SBOX     -> type R/r, size 0x100;
#        none of them is B/b (and no symbol is missing).
#
# Fails loudly on any mismatch.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_cipher_rodata.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_cipher_rodata.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_cipher_rodata] $*"; }
bad()  { echo "[gate_cipher_rodata] FAIL: $*" >&2; fail=1; }

OUT="$WORK/aes_gcm"
mkdir -p "$OUT"
note "zig1: $ZIG1"
( cd "$ROOT" && timeout 120 "$ZIG1" -ffast -o "$OUT" \
    repro/mi_matrix/stdlib_aes_gcm_xmod/main.zig ) \
    || { bad "dump failed for repro/mi_matrix/stdlib_aes_gcm_xmod"; exit 1; }
( cd "$OUT" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I . -c *.c ) \
    || { bad "gcc -c failed for repro/mi_matrix/stdlib_aes_gcm_xmod"; exit 1; }

# sym_info <suffix> -> "size type" of the first zG_*_<suffix> symbol, or empty.
sym_info() {
    local suffix="$1"
    { nm -S "$OUT"/*.o 2>/dev/null || true; } | awk -v s="_$suffix" \
        '$NF ~ ("zG_.*" s "$") && !done { print $2, $3; done=1 }'
}

check_symbol() {
    local suffix="$1" want_size="$2"
    local info size type
    info="$(sym_info "$suffix")"
    if [ -z "$info" ]; then
        bad "symbol _${suffix} not found in emitted objects"
        return
    fi
    size="${info%% *}"
    type="${info##* }"
    case "$type" in
        R|r)
            if [ "$((16#$size))" -eq "$want_size" ]; then
                note "ok _${suffix} type '$type' size 0x$(printf '%x' "$want_size")"
            else
                bad "_${suffix} size 0x$(printf '%x' "$((16#$size))") want 0x$(printf '%x' "$want_size")"
            fi ;;
        B|b)
            bad "_${suffix} is writable ('$type'), want R/r rodata" ;;
        *)
            bad "_${suffix} type '$type', want R/r rodata" ;;
    esac
}

check_symbol Te0 $((0x400))
check_symbol Te1 $((0x400))
check_symbol Te2 $((0x400))
check_symbol Te3 $((0x400))
check_symbol SBOX $((0x100))

if [ "$fail" -eq 0 ]; then
    echo "CIPHER_RODATA GATE OK"
    exit 0
fi
echo "CIPHER_RODATA GATE FAILED" >&2
exit 1
