#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_const_rodata.sh [zig1]
#
# M2 T1C-F rodata gate (non-vacuous core): proves file-scope `const` values
# are emitted as C89 const rodata and that the `.bss` fallback class is
# preserved. Probe sources: repro/mi_matrix/const_rodata_gate/.
#
# usage: scripts/compiler/gate_const_rodata.sh [path/to/zig1]
#   zig1 defaults to $ROOT/zig1 if executable.
#
# Steps:
#   1. dump+gcc the two probes (`value_shapes.zig` / `runtime_shapes.zig`);
#   2. `nm -S` section-class assertions:
#        value shapes  -> R/r (value-only) or D/d (address-bearing), never B/b/C;
#        runtime shapes -> B/b/C (non-constant const, undefined const,
#                          STOP-1 non-first-member union const, var), never R/r;
#   3. `__module_init` stores the S19/rs symbols and never the const symbols;
#   4. header/definition text: `extern ... const` present for pub consts
#      (const_rodata_xmod_xmod/leaf), absent for private (value_shapes); the
#      private definition is `static ... const`;
#   5. value fixture repro/mi_matrix/stdlib_const_rodata_xmod runs green
#      (scripts/stdlib/run_fixtures.sh targeted).
#
# Non-vacuity (mutations) are performed at closeout and recorded in the
# task report, not by this script: stub the emitter's const_init branch to
# `.bss` -> step 2 FAILS; force a non-constant const to the const path ->
# the runtime-shape negative FAILS.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_const_rodata.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_const_rodata.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_const_rodata] $*"; }
bad()  { echo "[gate_const_rodata] FAIL: $*" >&2; fail=1; }

build_probe() {
    local src="$1" out="$2"
    mkdir -p "$out"
    ( cd "$ROOT" && timeout 120 "$ZIG1" -ffast -o "$out" "$src" ) \
        || { bad "dump failed for $src"; return 1; }
    ( cd "$out" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
        -Wno-implicit-function-declaration -I . -c *.c ) \
        || { bad "gcc -c failed for $src"; return 1; }
    return 0
}

# nm class of the first symbol whose name ends in "_<suffix>"
nm_class() {
    local objdir="$1" suffix="$2"
    { nm -S "$objdir"/*.o 2>/dev/null || true; } | awk -v s="_$suffix" \
        '$NF ~ ("zG_.*" s "$") && !done { print $3; done=1 }'
    return 0
}

check_class() {
    local objdir="$1" suffix="$2" want="$3"
    local got
    got="$(nm_class "$objdir" "$suffix")"
    if [ -z "$got" ]; then
        bad "symbol _${suffix} not found in $objdir"
        return
    fi
    case "$want" in
        ro)
            case "$got" in
                R|r|D|d) note "ok _${suffix} class '$got' (ro/reloc)" ;;
                *) bad "_${suffix} class '$got' want R/r/D/d" ;;
            esac ;;
        ro_exact)
            case "$got" in
                R|r) note "ok _${suffix} class '$got' (R/r)" ;;
                *) bad "_${suffix} class '$got' want R/r" ;;
            esac ;;
        bss)
            case "$got" in
                B|b|C) note "ok _${suffix} class '$got' (bss)" ;;
                *) bad "_${suffix} class '$got' want B/b/C" ;;
            esac ;;
    esac
}

# ---- 1-2: probes + nm -------------------------------------------------
note "zig1: $ZIG1"
build_probe "repro/mi_matrix/const_rodata_gate/value_shapes.zig" "$WORK/v" || true
build_probe "repro/mi_matrix/const_rodata_gate/runtime_shapes.zig" "$WORK/r" || true

if [ -d "$WORK/v" ]; then
    # value-only shapes: exactly R/r
    for s in vs_scalar vs_neg vs_expr vs_float vs_bool vs_arr1d vs_arr2d \
             vs_struc vs_tup vs_union vs_nested; do
        check_class "$WORK/v" "$s" ro_exact
    done
    # address-bearing shapes: never .bss
    for s in vs_slice vs_many vs_parr; do
        check_class "$WORK/v" "$s" ro
    done
fi
if [ -d "$WORK/r" ]; then
    for s in rs_nonconst rs_undef rs_union rs_var rs_seed; do
        check_class "$WORK/r" "$s" bss
    done
fi

# ---- 3: __module_init stores ------------------------------------------
if ls "$WORK/r"/*.c >/dev/null 2>&1; then
    if grep -aq 'zG_.*_rs_nonconst = ' "$WORK"/r/*.c; then
        note "ok S19 rs_nonconst IS stored in __module_init"
    else
        bad "rs_nonconst not stored (S19 negative-of-negative)"
    fi
    if grep -aq 'zG_.*_rs_union = ' "$WORK"/r/*.c; then
        note "ok STOP-1 rs_union IS stored (fallback values)"
    else
        bad "rs_union not stored (STOP-1 fallback broken)"
    fi
fi
if ls "$WORK/v"/*.c >/dev/null 2>&1; then
    if grep -aqE '^[[:space:]]+zG_[A-Za-z0-9_]+_vs_[a-z0-9]+ = ' "$WORK"/v/*.c; then
        bad "a value-shape const is stored from __module_init"
    else
        note "ok no value-shape const is stored"
    fi
fi

# ---- 4: header / definition text --------------------------------------
if ls "$WORK/v"/*.h >/dev/null 2>&1; then
    if grep -aqE 'extern .* const zG_.*_vs_' "$WORK"/v/*.h; then
        bad "private const appears in a header (extern)"
    else
        note "ok private consts absent from headers"
    fi
fi
if ls "$WORK/v"/*.c >/dev/null 2>&1; then
    if grep -aqE 'static .* const zG_.*_vs_scalar = ' "$WORK"/v/*.c; then
        note "ok private const definition is 'static ... const'"
    else
        bad "private const definition missing 'static ... const'"
    fi
fi
XOUT="$WORK/x"
build_probe "repro/mi_matrix/const_rodata_xmod_xmod/main.zig" "$XOUT" || true
if ls "$XOUT"/*.h >/dev/null 2>&1; then
    if grep -aq 'extern unsigned int const zG_' "$XOUT"/*.h; then
        note "ok pub const header row is 'extern ... const'"
    else
        bad "pub const header row missing 'extern ... const'"
    fi
fi

# ---- 5: value fixture -------------------------------------------------
if [ "$fail" -eq 0 ]; then
    if bash "$ROOT/scripts/stdlib/run_fixtures.sh" "$ZIG1" \
        repro/mi_matrix/stdlib_const_rodata_xmod; then
        note "ok value fixture stdlib_const_rodata_xmod"
    else
        bad "value fixture stdlib_const_rodata_xmod failed"
    fi
else
    note "skipping value fixture (probe failures above)"
fi

if [ "$fail" -eq 0 ]; then
    echo "CONST_RODATA GATE OK"
    exit 0
fi
echo "CONST_RODATA GATE FAILED" >&2
exit 1
