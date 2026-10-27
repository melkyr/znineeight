#!/bin/sh
# tier_edit.sh — Phase 2 P4-M2 gate for the GUI-free z9edit headless core.
#
# Builds and runs all six native Linux test drivers with the binding recipe,
# checks every binding case name, reruns the lexer driver 3x for a byte-identical
# dump md5, asserts the six core modules import no std_gfx, and measures the
# Z98 `--dump-c89` max RSS of a driver importing all six modules (< 16 MB).
#
# Env: ZIG  compiler (default /tmp/p4_t1_build/zig1_5_clean)
#      OUT  scratch dir (default /tmp/z9edit_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints a PASS/FAIL summary.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/p4_t1_build/zig1_5_clean}"
OUT="${OUT:-/tmp/z9edit_tier}"
DRIVER_REL="examples/z98/z9edit/tests/_rss_probe.zig"
DRIVER="$ROOT/$DRIVER_REL"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

cleanup() {
    rm -f "$DRIVER"
}
trap cleanup EXIT INT TERM

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p4_t1_build"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

build_test() {
    t="$1"
    mkdir -p "$OUT/$t"
    if ! "$ZIG" -osl --output-dir "$OUT/$t" "examples/z98/z9edit/tests/$t.zig" \
        >"$OUT/$t/zig.log" 2>&1; then
        echo "FAIL: zig compile $t (see $OUT/$t/zig.log)"
        tail -20 "$OUT/$t/zig.log" | sed 's/^/       /'
        return 1
    fi
    if ! sh "$OUT/$t/build_target.sh" linux "$OUT/$t/$t" >"$OUT/$t/build.log" 2>&1; then
        echo "FAIL: target link $t (see $OUT/$t/build.log)"
        tail -20 "$OUT/$t/build.log" | sed 's/^/       /'
        return 1
    fi
    return 0
}

run_test() {
    t="$1"
    "$OUT/$t/$t" >"$OUT/$t/run.log" 2>&1
    rc=$?
    echo "== $t (rc=$rc) =="
    sed 's/^/       /' "$OUT/$t/run.log"
    if [ "$rc" -eq 0 ]; then
        pass_case "$t exit 0"
    else
        fail_case "$t exit 0 (got $rc)"
    fi
}

check_case() {
    t="$1"
    c="$2"
    if grep -qx "ok - $c" "$OUT/$t/run.log" 2>/dev/null; then
        pass_case "$c"
    else
        fail_case "$c"
    fi
}

echo "== z9edit core tests (binding recipe) =="
for t in buffer_test lexer_test idents_test match_test undo_test errtab_test; do
    if ! build_test "$t"; then
        fail_case "$t build"
    else
        run_test "$t"
    fi
done

# Every binding case name must be present and green.
check_case buffer_test insert_delete_roundtrip
check_case buffer_test line_index_after_insert
check_case buffer_test offset_linecol_roundtrip
check_case buffer_test crlf_preserved_noedit
check_case buffer_test lf_preserved
check_case buffer_test crlf_preserved_after_insert
check_case buffer_test load_missing_error

check_case lexer_test keyword_string_comment_number
check_case lexer_test block_comment_state_carry
check_case lexer_test multiline_string_state_carry
check_case lexer_test builtin_and_type
check_case lexer_test errcode_token
check_case lexer_test errcode_at_col

check_case idents_test decl_const_var_fn_collected
check_case idents_test use_without_decl_not_collected

check_case match_test pair_simple
check_case match_test pair_cross_line
check_case match_test nested_ok
check_case match_test unbalanced_opener_line
check_case match_test unbalanced_closer

check_case undo_test undo_insert_inverse
check_case undo_test undo_delete_inverse
check_case undo_test undo_empty_false

check_case errtab_test known_code_message
check_case errtab_test unknown_null

# ---- GUI-free contract -----------------------------------------------------
echo "== GUI-free contract =="
if grep -n "std_gfx\|gfx" examples/z98/z9edit/buffer.zig examples/z98/z9edit/lexer.zig \
    examples/z98/z9edit/idents.zig examples/z98/z9edit/match.zig \
    examples/z98/z9edit/undo.zig examples/z98/z9edit/errtab.zig >"$OUT/gfx_grep.log" 2>&1; then
    fail_case "core modules have zero GUI imports (grep hit, see $OUT/gfx_grep.log)"
else
    pass_case "core modules have zero GUI imports"
fi

# ---- 3x lexer determinism --------------------------------------------------
echo "== lexer dump 3x determinism =="
MD1=""; MD2=""; MD3=""
if [ -x "$OUT/lexer_test/lexer_test" ]; then
    "$OUT/lexer_test/lexer_test" >"$OUT/lexer_run1.log" 2>&1; RC1=$?
    "$OUT/lexer_test/lexer_test" >"$OUT/lexer_run2.log" 2>&1; RC2=$?
    "$OUT/lexer_test/lexer_test" >"$OUT/lexer_run3.log" 2>&1; RC3=$?
    MD1=$(md5sum "$OUT/lexer_run1.log" | sed 's/ .*//')
    MD2=$(md5sum "$OUT/lexer_run2.log" | sed 's/ .*//')
    MD3=$(md5sum "$OUT/lexer_run3.log" | sed 's/ .*//')
    echo "lexer md5 run1: $MD1 (rc=$RC1)"
    echo "lexer md5 run2: $MD2 (rc=$RC2)"
    echo "lexer md5 run3: $MD3 (rc=$RC3)"
    if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] && [ "$RC3" -eq 0 ] && \
        [ "$MD1" = "$MD2" ] && [ "$MD2" = "$MD3" ] && [ -n "$MD1" ]; then
        pass_case "lexer dump byte-identical 3x ($MD1)"
    else
        fail_case "lexer dump not byte-identical 3x ($MD1 / $MD2 / $MD3)"
    fi
else
    fail_case "lexer_test binary missing for determinism run"
fi

# ---- compile max RSS (< 16 MB) --------------------------------------------
echo "== compile max RSS (six-module driver, --dump-c89) =="
cat >"$DRIVER" <<'EOF'
const arena_mod = @import("std_arena.zig");
const buffer = @import("../buffer.zig");
const lexer = @import("../lexer.zig");
const idents = @import("../idents.zig");
const match = @import("../match.zig");
const undo = @import("../undo.zig");
const errtab = @import("../errtab.zig");

var ab: [65536]u8 = undefined;

pub fn main() void {
    var a = arena_mod.init(ab[0..]);
    const b = buffer.bufInit(&a, 16) catch {
        return;
    };
    buffer.bufInsert(b, 0, "const x = 1; error[3000]") catch {
        return;
    };
    var st = lexer.lexInitState();
    var toks: [32]lexer.Token = undefined;
    _ = lexer.lexLine(&st, "const x = 1;", toks[0..]);
    _ = lexer.lexErrCodeAt("error[3000]", 0);
    const s = idents.identScan(&a, b) catch {
        return;
    };
    _ = idents.identHas(s, "x");
    var m: usize = 0;
    _ = match.matchPairAt(b, 0, &m);
    var ub: match.Unbalance = undefined;
    _ = match.matchUnbalanced(b, &ub);
    const u = undo.undoInit(&a);
    undo.undoRecordInsert(u, 0, "x") catch {
        return;
    };
    _ = undo.undoApply(u, b);
    if (errtab.errtabMessage(3000)) |msg| {
        _ = msg;
    }
}
EOF
mkdir -p "$OUT/rss/out"
COMPILE_RSS="n/a"
if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -v -o "$OUT/rss/time.log" \
        "$ZIG" --dump-c89 --output-dir "$OUT/rss/out" "$DRIVER_REL" \
        >"$OUT/rss/dump.log" 2>&1
    RSS_RC=$?
    COMPILE_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/rss/time.log" | tail -1)
    [ -n "$COMPILE_RSS" ] || COMPILE_RSS="n/a"
    if [ "$RSS_RC" -ne 0 ]; then
        tail -20 "$OUT/rss/dump.log" | sed 's/^/       /'
        fail_case "six-module --dump-c89 probe failed (rc=$RSS_RC)"
    fi
else
    echo "operator-hardware: /usr/bin/time absent; compile RSS not measured"
fi
if [ "$COMPILE_RSS" = "n/a" ]; then
    echo "compile max RSS: not measured"
else
    echo "compile max RSS: ${COMPILE_RSS} KiB"
    if [ "$COMPILE_RSS" -lt 16384 ]; then
        pass_case "compile max RSS < 16 MB (${COMPILE_RSS} KiB)"
    else
        fail_case "compile max RSS >= 16 MB (${COMPILE_RSS} KiB)"
    fi
fi

echo
echo "== tier_edit summary: $PASSES passed, $FAILS failed =="
echo "lexer md5 3x: $MD1 $MD2 $MD3"
echo "compile max RSS: ${COMPILE_RSS} KiB"
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_EDIT FAIL"
    exit 1
fi
echo "TIER_EDIT PASS"
