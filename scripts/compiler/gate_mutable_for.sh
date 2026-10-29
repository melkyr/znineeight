#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_mutable_for.sh [zig1]
#
# Mutable for-capture gate (Phase 2.5 Task 3). Proves the parser/sema half of
# `for (...) |*item|` in sema-only mode (`--check`):
#   (a) mutable_for_slice_ok             `[]u32` + take(x) + x.* = 1  -> rc=0
#   (b) mutable_for_const_elem_reject    `[]const u32` + x.* = 1      -> rc=2, error[3002]
#   (c) mutable_for_range_reject         `for (0..n) |*i|`             -> rc=2, error[3078]
#   (d) mutable_for_const_binding_ok     `const s: []u32` + x.* = 1   -> rc=0
#   (e) mutable_for_index_ok             `for (s) |*x, i|`            -> rc=0
#   (f) mutable_for_array_rvalue_reject  `for (makeArray()) |*x|`     -> rc=2, error[3078]
#   (g) mutable_for_module_array_ok      `for (h.arr) |*x|` (pub var) -> rc=0
#   (h) mutable_for_discard_ok           `for (s) |*_|`               -> rc=0
#   (i) mutable_for_reject_index         `for (0..n) |*i, j|`         -> rc=2, one error[3078], no error[20]
#   (j) mutable_for_for_index_range_ok   `for (s, 0..) |*x, i|`       -> rc=0
#   (k) mutable_for_if_capture_reject    `if (o) |*x|`                -> rc=2 parse error
#   (l) mutable_for_warning              `"\q"` + `|*x|`              -> rc=0 + warning[6]; `-W` -> rc=2
# plus `--check -o <missing>` / `--check --output-dir <missing>` / `--check -d`
# (no output dir) on a positive fixture -> rc=0 (the flags are truly ignored).
#
# Task 4 e2e section (default mode, no `-f`; all timeout-guarded): emit with
# `zig1 -o <dir> <entry>`, build via the emitted `build_target.sh linux`, run,
# and assert exact stdout. Cases (labels name the fixture shape, not the sema
# letters above):
#   (e2e 1) mutable_for_slice_ok             `[]u32` in-place mutation       -> `1 1 1`
#   (e2e 2) mutable_for_row_ptr_ok           `*[3][2]u32` row pointer        -> `1 11 31`
#   (e2e 3) mutable_for_array_ident_ok       `var a: [3]u32`                  -> `11 12 13`
#   (e2e 4) mutable_for_const_binding_ok     `const s: []u32` write           -> `1 1 1`
#   (e2e 5) mutable_for_for_index_range_ok   `for (s, 0..) |*x, i|`           -> `1 1 1`
#   (e2e 6) mutable_for_discard_ok           `|*_|` (rc + stdout only)        -> `0 0 0`
#   (e2e 7) mutable_for_nested_ok            nested distinct-name loops       -> `1 1 1 13 23`
#   (e2e 8) mutable_for_const_u8_row_ok      `[]const [3]u8` + `r.*[0]`       -> `1 4`
#   (e2e 9) mutable_for_const_u8_row_ptr_ok  `*const [3]u8` + `r.*`           -> `24`
#   (e2e 10) mutable_for_array_row_ok        `var m: [3][2]u32` + row write   -> `1 11 31`
#   (e2e 11) mutable_for_module_array_ok     module-member array write        -> `11 12 13`
#   (e2e 12) mutable_for_fnptr_ok            `[]fn(u32)u32` slot mutation     -> `23`
#
# Positives assert `--check` rc=0, no `error[` diagnostic, banner present, and no
# emitted `.c` / `.zig1_lir.tmp` in either the per-case CWD (default spill
# location) or the ignored output dir. Negatives assert rc=2, the exact
# diagnostic, zero `.c`, and the banner. Fixtures live off-corpus under
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

# Task 4 e2e: default-mode emission (no -f), build via the emitted
# build_target.sh, run under a timeout, and assert exact stdout. Any of
# emit/build/run nonzero, a timeout, or wrong stdout fails the case (the
# pre-lowering compiler's `|*` binding is RED by construction).
run_e2e() {
    local label="$1" name="$2" want="$3"
    local dir cwd out prog rc
    dir="$ROOT/repro/mi_matrix/known_excluded/$name"
    cwd="$WORK/e2e-$name"
    out="$WORK/e2e-$name.out"
    prog="$out/prog"
    rm -rf "$cwd" "$out"
    mkdir -p "$cwd" "$out"
    set +e
    ( cd "$cwd" && timeout 120 "$ZIG1" -o "$out" "$dir/main.zig" ) \
        >"$WORK/e2e-$name.emit.out" 2>"$WORK/e2e-$name.emit.err"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        bad "$label: emit rc=$rc (stderr: $(tr '\n' '|' <"$WORK/e2e-$name.emit.err" | head -c 400))"
        return
    fi
    if [ ! -f "$out/build_target.sh" ]; then
        bad "$label: emitted build_target.sh missing"
        return
    fi
    set +e
    ( cd "$out" && timeout 120 sh "$out/build_target.sh" linux "$prog" ) \
        >"$WORK/e2e-$name.build.out" 2>"$WORK/e2e-$name.build.err"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        bad "$label: build rc=$rc (stderr: $(tr '\n' '|' <"$WORK/e2e-$name.build.err" | head -c 400))"
        return
    fi
    set +e
    ( cd "$cwd" && timeout 30 "$prog" ) \
        >"$WORK/e2e-$name.run.out" 2>"$WORK/e2e-$name.run.err"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        bad "$label: run rc=$rc (stderr: $(tr '\n' '|' <"$WORK/e2e-$name.run.err" | head -c 400))"
        return
    fi
    printf '%s\n' "$want" >"$WORK/e2e-$name.want"
    if ! cmp -s "$WORK/e2e-$name.run.out" "$WORK/e2e-$name.want"; then
        bad "$label: stdout '$(tr '\n' '|' <"$WORK/e2e-$name.run.out")' want '$want'"
        return
    fi
    note "$label: ok"
}

# run_check <label> <fixture-name> <want-rc> [extra zig1 args...]
run_check() {
    local label="$1" name="$2" want_rc="$3"; shift 3
    local dir cwd out rc
    dir="$ROOT/repro/mi_matrix/known_excluded/$name"
    cwd="$WORK/$name.cwd"
    out="$WORK/$name.out"
    mkdir -p "$cwd" "$out"
    set +e
    ( cd "$cwd" && timeout 120 "$ZIG1" --check "$@" "$dir/main.zig" ) \
        >"$WORK/$name.stdout" 2>"$WORK/$name.stderr"
    rc=$?
    set -e
    if [ "$rc" -ne "$want_rc" ]; then
        bad "$label: rc=$rc want $want_rc (stderr: $(tr '\n' '|' <"$WORK/$name.stderr"))"
    fi
    grep -q 'Z98 Compiler 2026' "$WORK/$name.stderr" \
        || bad "$label: banner missing (banner-on-every-run rule)"
    [ "$(count_c "$cwd")" -eq 0 ] \
        || bad "$label: emitted $(count_c "$cwd") .c file(s) in CWD, want 0 under --check"
    [ "$(count_c "$out")" -eq 0 ] \
        || bad "$label: emitted $(count_c "$out") .c file(s) in output dir, want 0 under --check"
    [ "$(count_lir "$cwd")" -eq 0 ] \
        || bad "$label: emitted .zig1_lir.tmp in CWD, want none under --check"
    [ "$(count_lir "$out")" -eq 0 ] \
        || bad "$label: emitted .zig1_lir.tmp in output dir, want none under --check"
    if [ "$want_rc" -eq 0 ]; then
        if grep -q 'error\[' "$WORK/$name.stderr"; then
            bad "$label: unexpected error diagnostic (stderr: $(tr '\n' '|' <"$WORK/$name.stderr"))"
        fi
    fi
}

# expect_err <label> <fixture-name> <regex>
expect_err() {
    grep -q "$3" "$WORK/$2.stderr" \
        || bad "$1: missing diagnostic '$3' (stderr: $(tr '\n' '|' <"$WORK/$2.stderr"))"
}

note "zig1: $ZIG1"

run_check "a slice ok"               mutable_for_slice_ok            0
run_check "b const elem"             mutable_for_const_elem_reject   2
expect_err "b const elem"            mutable_for_const_elem_reject   'error\[3002\]: cannot assign to immutable variable'
run_check "c range"                  mutable_for_range_reject        2
expect_err "c range"                 mutable_for_range_reject        'error\[3078\]:'
run_check "d const binding"          mutable_for_const_binding_ok    0
run_check "e index capture"          mutable_for_index_ok            0
run_check "f array rvalue"           mutable_for_array_rvalue_reject 2
expect_err "f array rvalue"          mutable_for_array_rvalue_reject 'error\[3078\]:'
run_check "g module array"           mutable_for_module_array_ok     0
run_check "h discard"                mutable_for_discard_ok          0
run_check "i reject + index"         mutable_for_reject_index        2
expect_err "i reject + index"        mutable_for_reject_index        'error\[3078\]:'
n3078=$(grep -c 'error\[3078\]' "$WORK/mutable_for_reject_index.stderr" || true)
[ "$n3078" -eq 1 ] || bad "i reject + index: error[3078] count=$n3078 want exactly 1"
if grep -q 'error\[20\]' "$WORK/mutable_for_reject_index.stderr"; then
    bad "i reject + index: index 'j' was not registered (found error[20])"
fi
run_check "j for_index_range"        mutable_for_for_index_range_ok  0
run_check "k if capture reject"      mutable_for_if_capture_reject   2
expect_err "k if capture reject"     mutable_for_if_capture_reject   'error\[2000\]'
run_check "l warning"                mutable_for_warning             0
expect_err "l warning"               mutable_for_warning             'warning\[6\]'
run_check "l warning -W"             mutable_for_warning             2 -W
expect_err "l warning -W"            mutable_for_warning             'warning\[6\]'
run_check "flag -o missing"          mutable_for_slice_ok            0 -o /nonexistent/t3_gate_missing
run_check "flag --output-dir missing" mutable_for_slice_ok           0 --output-dir /nonexistent/t3_gate_missing
run_check "flag -d without output"   mutable_for_slice_ok            0 -d

# Task 4 e2e: lowering + build + run. Values prove the `|*` capture aliases
# the source storage (in-place mutation observed in the caller's buffer).
# Labels name the fixture shape; they do not reuse the sema-case letters.
note "--- e2e (default mode, build_target.sh linux) ---"
run_e2e "e2e slice []u32"                  mutable_for_slice_ok           "1 1 1"
run_e2e "e2e row ptr *[3][2]u32"           mutable_for_row_ptr_ok         "1 11 31"
run_e2e "e2e array ident [3]u32"           mutable_for_array_ident_ok     "11 12 13"
run_e2e "e2e const binding []u32"          mutable_for_const_binding_ok   "1 1 1"
run_e2e "e2e for_index_range"              mutable_for_for_index_range_ok "1 1 1"
run_e2e "e2e discard |*_|"                 mutable_for_discard_ok         "0 0 0"
run_e2e "e2e nested"                       mutable_for_nested_ok          "1 1 1 13 23"
run_e2e "e2e const u8 row []const [3]u8"   mutable_for_const_u8_row_ok    "1 4"
run_e2e "e2e const u8 row ptr *const [3]u8" mutable_for_const_u8_row_ptr_ok "24"
run_e2e "e2e array row [3][2]u32"          mutable_for_array_row_ok       "1 11 31"
run_e2e "e2e module array"                 mutable_for_module_array_ok    "11 12 13"
run_e2e "e2e fn ptr []fn(u32)u32"          mutable_for_fnptr_ok           "23"

if [ "$fail" -eq 0 ]; then
    echo "MUTABLE_FOR GATE OK"
    exit 0
fi
echo "MUTABLE_FOR GATE FAILED" >&2
exit 1
