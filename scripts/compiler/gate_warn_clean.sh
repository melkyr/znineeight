#!/usr/bin/env bash
set -uo pipefail
# scripts/compiler/gate_warn_clean.sh [path/to/zig1]
#
# Phase 2.5 Task 9 (T7b): warning-clean emission at the origin.
#
# Compiles, under the project's real 32-bit C89 target, with warnings as
# errors and exactly one suppression (`-Wno-long-long`: C89 has no 64-bit
# integer type, and emitted zig_compat.h maps MSVC->__int64/OWC|gcc->long long;
# the flag is GCC-gate-only and must never appear in shipped MSVC/OWC scripts):
#
#   gcc -m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long -I <dump> -c
#
# Scopes:
#   (a) full self-emission: `zig1 -osw -o DIR sf/src/main.zig` (every .c)
#   (b) shipped runtime C: sf/src/include/{zig_runtime,zig_pal,zig_nocrt}.c
#       and sf/src/c_exit.c
#   (c) representative programs: examples/z98/hello/main.zig, the std-heavy
#       examples/z98/lisp_interpreter_curr/main.zig, and the wide-enum-macro
#       fixtures under repro/mi_matrix/ (every emitted .c)
#
# `-c` is required: `-fsyntax-only` would suppress -Wunused-function.
# zig1 defaults to $ROOT/zig1. Builds must be run sequentially (a zig1 process
# uses CWD-relative `.zig1_*.tmp` spill files).

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_warn_clean.sh [path/to/zig1]" >&2
        exit 1
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 1; }

CFLAGS=(-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long -c)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_warn_clean.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail=0

# compile_tree <label> <dir>
compile_tree() {
    local label="$1" dir="$2"
    local obj="$WORK/obj_$label"
    local log="$WORK/$label.log"
    mkdir -p "$obj"
    : > "$log"
    local f rc
    for f in "$dir"/*.c; do
        [ -e "$f" ] || continue
        gcc "${CFLAGS[@]}" -I "$dir" "$f" -o "$obj/$(basename "${f%.c}").o" >> "$log" 2>&1
        rc=$?
        if [ "$rc" -ne 0 ]; then
            fail=1
        fi
    done
    if [ -s "$log" ]; then
        echo "[warn-clean] $label: diagnostics (compiler=$ZIG1):"
        cat "$log"
        echo "[warn-clean] $label: warning classes:"
        grep -oE '\[-W[a-z0-9=-]+\]' "$log" | sort | uniq -c | sort -rn || true
        echo "[warn-clean] $label: FAIL"
    else
        echo "[warn-clean] $label: OK ($(ls "$obj"/*.o 2>/dev/null | wc -l | tr -d ' ') TUs)"
    fi
}

# (a) full self-emission -----------------------------------------------------
mkdir -p "$WORK/self"
( cd "$ROOT" && timeout 600 "$ZIG1" -osw -o "$WORK/self" sf/src/main.zig ) \
    || { echo "[warn-clean] self-emission dump FAILED" >&2; fail=1; }
if ls "$WORK/self"/*.c >/dev/null 2>&1; then
    compile_tree self "$WORK/self"
else
    echo "[warn-clean] self-emission: no .c emitted" >&2
    fail=1
fi
rm -f "$WORK/self"/.zig1_*.tmp

# (b) shipped runtime C ------------------------------------------------------
mkdir -p "$WORK/runtime"
cp "$ROOT/sf/src/include/zig_compat.h" "$WORK/runtime/"
cp "$ROOT/sf/src/include/zig_runtime.h" "$WORK/runtime/"
cp "$ROOT/sf/src/include/zig_runtime.c" "$WORK/runtime/"
cp "$ROOT/sf/src/include/zig_pal.c" "$WORK/runtime/"
cp "$ROOT/sf/src/include/zig_nocrt.c" "$WORK/runtime/"
cp "$ROOT/sf/src/c_exit.c" "$WORK/runtime/"
compile_tree runtime "$WORK/runtime"

# (c) representative programs ------------------------------------------------
for entry in \
    examples/z98/hello/main.zig \
    examples/z98/lisp_interpreter_curr/main.zig \
    repro/mi_matrix/enum_wide_macro_i64_ok_xmod/main.zig \
    repro/mi_matrix/enum_wide_macro_i40_ok_xmod/main.zig \
    repro/mi_matrix/enum_wide_macro_u40_ok_xmod/main.zig \
    repro/mi_matrix/enum_wide_macro_i63_ok_xmod/main.zig \
    repro/mi_matrix/enum_wide_macro_i64_min_ok_xmod/main.zig; do
    label="$(basename "$(dirname "$entry")")"
    mkdir -p "$WORK/$label"
    ( cd "$ROOT" && timeout 600 "$ZIG1" -osw -o "$WORK/$label" "$entry" ) \
        || { echo "[warn-clean] $label dump FAILED" >&2; fail=1; }
    if ls "$WORK/$label"/*.c >/dev/null 2>&1; then
        compile_tree "$label" "$WORK/$label"
    else
        echo "[warn-clean] $label: no .c emitted" >&2
        fail=1
    fi
    rm -f "$WORK/$label"/.zig1_*.tmp
done

if [ "$fail" -ne 0 ]; then
    echo "[warn-clean] FAILED (gcc -m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long)" >&2
    exit 1
fi
echo "[warn-clean] OK: self-emission + shipped runtime + hello + lisp_interpreter_curr + wide enum macros"
