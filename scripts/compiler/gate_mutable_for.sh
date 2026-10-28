#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_mutable_for.sh [zig1]
#
# Mutable for-capture gate (Phase 2.5 Task 3). Proves the parser/sema half of
# `for (...) |*item|` in sema-only mode (`--check`):
#   (a) mutable_for_slice_ok            `[]u32` + take(x) + x.* = 1  -> rc=0
#   (b) mutable_for_const_elem_reject   `[]const u32` + x.* = 1      -> rc=2, error[3002]
#   (c) mutable_for_range_reject        `for (0..n) |*i|`             -> rc=2, error[3078]
#   (d) mutable_for_const_binding_ok    `const s: []u32` + x.* = 1   -> rc=0
#   (e) mutable_for_index_ok            `for (s) |*x, i|`            -> rc=0
#   (f) mutable_for_array_rvalue_reject `for (makeArray()) |*x|`     -> rc=2, error[3078]
#   (g) mutable_for_module_array_ok     `for (h.arr) |*x|` (pub var) -> rc=0
#
# Positives assert `--check` rc=0, no diagnostics, and no emitted `.c` /
# `.zig1_lir.tmp` (the sema-only contract). Negatives assert rc=2, the exact
# diagnostic prefix, zero `.c`, and the banner. Fixtures live off-corpus under
# repro/mi_matrix/known_excluded/ (skipped by list_corpus_dirs.sh).
#
# `zig1` defaults to $ROOT/zig1.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_mutable_for.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_mutable_for.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_mutable_for] $*"; }
bad()  { echo "[gate_mutable_for] FAIL: $*" >&2; fail=1; }

count_c() {
    find "$1" -maxdepth 1 -type f -name '*.c' 2>/dev/null | wc -l | tr -d ' '
}
count_lir() {
    find "$1" -maxdepth 1 -type f -name '.zig1_lir.tmp' 2>/dev/null | wc -l | tr -d ' '
}

# run_case <label> <fixture-name> <want-rc> <want-error-regex-or-empty>
run_case() {
    local label="$1" name="$2" want_rc="$3" want_err="${4:-}" dir out rc
    dir="$ROOT/repro/mi_matrix/known_excluded/$name"
    out="$WORK/$name.out"
    mkdir -p "$out"
    set +e
    ( cd "$WORK" && timeout 120 "$ZIG1" --check --output-dir "$out" "$dir/main.zig" ) \
        >"$WORK/$name.stdout" 2>"$WORK/$name.stderr"
    rc=$?
    set -e
    if [ "$rc" -ne "$want_rc" ]; then
        bad "$label: rc=$rc want $want_rc (stderr: $(tr '\n' '|' <"$WORK/$name.stderr"))"
    fi
    grep -q 'Z98 Compiler 2026' "$WORK/$name.stderr" \
        || bad "$label: banner missing (banner-on-every-run rule)"
    [ "$(count_c "$out")" -eq 0 ] \
        || bad "$label: emitted $(count_c "$out") .c file(s), want 0 under --check"
    [ "$(count_lir "$out")" -eq 0 ] \
        || bad "$label: emitted .zig1_lir.tmp, want none under --check"
    if [ -n "$want_err" ]; then
        grep -q "$want_err" "$WORK/$name.stderr" \
            || bad "$label: missing diagnostic '$want_err' (stderr: $(tr '\n' '|' <"$WORK/$name.stderr"))"
    else
        if grep -q '^error' "$WORK/$name.stderr"; then
            bad "$label: unexpected diagnostic (stderr: $(tr '\n' '|' <"$WORK/$name.stderr"))"
        fi
    fi
}

note "zig1: $ZIG1"

run_case "a slice ok"            mutable_for_slice_ok            0 ""
run_case "b const elem"          mutable_for_const_elem_reject   2 'error\[3002\]: cannot assign to immutable variable'
run_case "c range"               mutable_for_range_reject        2 'error\[3078\]:'
run_case "d const binding"       mutable_for_const_binding_ok    0 ""
run_case "e index capture"       mutable_for_index_ok            0 ""
run_case "f array rvalue"        mutable_for_array_rvalue_reject 2 'error\[3078\]:'
run_case "g module array"        mutable_for_module_array_ok     0 ""

if [ "$fail" -eq 0 ]; then
    echo "MUTABLE_FOR GATE OK"
    exit 0
fi
echo "MUTABLE_FOR GATE FAILED" >&2
exit 1
