#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_lower_depth.sh [path/to/zig1] [known-red]
#
# Depth gate for the iterative-lowering plan (Task 1 infrastructure; Tasks 2-4
# convert the recursive arms). Proves, per case:
#   1. repro/mi_matrix/emission_sibling_payload_xmod/main.zig compiles rc=0
#      under `ulimit -s 1024` (known-red until Task 2: rc=139 SIGSEGV today);
#   2. a generated 200-deep nested-block fixture compiles rc=0 under
#      `ulimit -s 1024` (known-red until Task 4: rc=139 SIGSEGV today);
#   3. a generated 200-deep nested-expression fixture compiles rc=0 under
#      `ulimit -s 1024` (the expression is nested 200 deep in the AST as a
#      left-deep `+` chain and sits in a comptime-untaken `if (false)` arm, so
#      it is legal input that must stay green through the trampoline work;
#      note the parser itself caps live paren/call nesting at 12 — see
#      sf/src/parser.zig parserParseExprPrec — so a chain is the only
#      200-deep expression shape that even parses);
#   4. if the lowering depth guard trips, the run ends in a clean diagnostic
#      (error[...] text on stderr), never a bare signal death. The guard is a
#      safety net (EXPR_GUARD_MAX) that must not fire on legal input; when it
#      does not trip this case passes with a note;
#   5. the four 8-pin entries still emit and their `-fsafe`/`-ffast`
#      `--dump-c89` md5s match the authoritative 8-pin table (post-`ERROR_*`
#      dense-order re-baseline, ruling (iii)):
#        mud  1b259bcd0584256029af931a53a03ae3 / e295d1c85dc837163c5de4898b03b8d4
#        gol  5be7b43b8f5bc5cc454aa1b434819ab1 / 1e091c84f97280d1ae765597a0a61d84
#        lisp 12b75058c92aa866ef9ce99ea2a401dd / 82b721b588adddda63e2dc30e96bbfcb
#        json b5be954dc2d6b7c46c46bd90d910fc95 / 048c2547541c2b1038556564a0706abb
#      (left = `-fsafe`, right = `-ffast`);
#   6. a generated 120-term RUNTIME-VALUED (not literal-folded) left-deep `+`
#      chain compiles rc=0 under `ulimit -s 1024` (Task 2 trampoline) and its
#      `--dump-c89` md5 equals the same source compiled by the BASELINE
#      compiler at 64 MB stack. Each term is a `u32` local seeded via
#      `@intCast(u32, argvc)` where `argvc = getv(7)`, so `lowerFoldedIntConst`
#      cannot fold the chain. 120 terms sits UNDER the semantic-analyzer wall
#      (~135 terms at 1 MB, D9) and under SEMA_GUARD_MAX (128), so this case is
#      green without tripping either. The baseline CANNOT emit the reference at
#      8 MB (measured: 115 terms OK, 118 SEGV -- its pre-Task-2 `lowerExpr`
#      costs ~70 KB/level; 30 the 1 MB threshold), so the reference run uses
#      64 MB. Baseline binary comes from $GATE_BASELINE_ZIG1 (default
#      /tmp/lowerfix_t2base/zig1_5_clean = the pre-change HEAD build; NOT
#      /tmp/lowerfix_base -- that one predates the dense-`ERROR_*` emitter and
#      its dump bytes differ by construction). Recorded reference md5 (stable
#      across 16/32/64 MB baseline runs): C6_REF_MD5 below.
#   7. a generated 200-term RUNTIME-VALUED left-deep `+` chain (same shape as
#      case 6) is OVER the semantic-analyzer ceiling (~135 terms at 1 MB) and
#      over SEMA_GUARD_MAX (128). It must fail as a CLEAN `error[...]`
#      diagnostic (non-zero rc < 128, stderr carries the guard message, 0 `.c`)
#      -- never rc=139/133. Without the depth guard
#      (`semanticAnalyzerResolveExprDepthGuard`, sf/src/semantic_analyzer.zig)
#      this input segfaults at 1 MB (D9).
#   8. a call whose ARGUMENT is a 120-term RUNTIME-VALUED left-deep `+` chain
#      (`sink(a0 + a1 + ...)`, same locals as case 6) compiles rc=0 under
#      `ulimit -s 1024` (Task 3 fn_call arm) and its `--dump-c89` md5 equals
#      the BASELINE compiler's emit at 64 MB. The call-argument shape parses
#      at depth 2; nested `f(g(h(...)))` is parser-blocked at depth 12 and a
#      120-arg call hits MAX_FN_PARAMS (64), so this is the shape that drives
#      the fn_call arm's interleaved prealloc/arg lowering. 120 terms sit under
#      SEMA_GUARD_MAX (128).
#   9. an `if` EXPRESSION with 120-term RUNTIME-VALUED `+` chains in both
#      arms (`var r: u32 = if (c) <chain> else <chain>;`, `var c: bool = true;`
#      -- a u32 condition is error[3058]) compiles rc=0 under `ulimit -s 1024`
#      (Task 3 if_expr arm) and its `--dump-c89` md5 equals the BASELINE
#      compiler's emit at 64 MB. Nested if-expressions are parser-blocked at
#      depth 12; the branch-chain shape parses at depth 3.
#
# With second arg `known-red`, cases 1 and 2 are reported as KNOWN-RED (pending
# Tasks 2/4) and do not fail the gate. Their REAL rc is always printed; the
# gate never hides a failing run.
#
# Fixtures live in a mktemp dir and are cleaned up.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_lower_depth.sh [path/to/zig1] [known-red]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }
MODE="${2:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_lower_depth.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_lower_depth] $*"; }
bad()  { echo "[gate_lower_depth] FAIL: $*" >&2; fail=1; }

note "zig1: $ZIG1"
[ -n "$MODE" ] && note "mode: $MODE"

# ---- fixtures (generated, mktemp dir) ----
# Case 2: 200-deep nested blocks: { { { ... } } }
BLOCKS="{ }"
_i=0
while [ "$_i" -lt 199 ]; do BLOCKS="{ $BLOCKS }"; _i=$((_i + 1)); done
cat >"$WORK/block200.zig" <<EOF
pub fn main() void {
    $BLOCKS
}
EOF

# Case 3: 200-deep nested expression: a left-deep 200-term \`+\` chain
# (AST depth 200) in a comptime-untaken arm.
CHAIN="1"
_i=0
while [ "$_i" -lt 199 ]; do CHAIN="$CHAIN + 1"; _i=$((_i + 1)); done
cat >"$WORK/expr200.zig" <<EOF
pub fn main() void {
    if (false) {
        var x: i32 = $CHAIN;
        _ = x;
    }
}
EOF

# run1mb <outname> <src-abs> -> rc in $RC ; logs at $WORK/<outname>.{out,err}
run1mb() {
    local name="$1" src="$2"
    mkdir -p "$WORK/$name"
    set +e
    ( ulimit -s 1024 && timeout 120 "$ZIG1" -ffast -o "$WORK/$name" "$src" ) \
        >"$WORK/$name.out" 2>"$WORK/$name.err"
    RC=$?
    set -e
}

report_case() {
    local n="$1" rc="$2" status="$3"
    echo "case $n: rc=$rc $status"
}

# ---- 1. emission_sibling_payload_xmod at 1 MB stack ----
run1mb c1 "$ROOT/repro/mi_matrix/emission_sibling_payload_xmod/main.zig"
c1rc="$RC"
if [ "$RC" -eq 0 ]; then
    report_case 1 "$RC" "PASS (emission_sibling_payload_xmod @ 1MB)"
elif [ "$MODE" = "known-red" ]; then
    report_case 1 "$RC" "KNOWN-RED (pending Task 2; expect rc=139 today)"
else
    report_case 1 "$RC" "FAIL (want rc=0; known-red until Task 2)"
    bad "case 1: emission_sibling_payload_xmod rc=$RC want 0 under ulimit -s 1024"
fi

# ---- 2. 200-deep nested blocks at 1 MB stack ----
run1mb c2 "$WORK/block200.zig"
c2rc="$RC"
if [ "$RC" -eq 0 ]; then
    report_case 2 "$RC" "PASS (200-deep nested blocks @ 1MB)"
elif [ "$MODE" = "known-red" ]; then
    report_case 2 "$RC" "KNOWN-RED (pending Task 4; expect rc=139 today)"
else
    report_case 2 "$RC" "FAIL (want rc=0; known-red until Task 4)"
    bad "case 2: 200-deep nested blocks rc=$RC want 0 under ulimit -s 1024"
fi

# ---- 3. 200-deep nested expression at 1 MB stack ----
run1mb c3 "$WORK/expr200.zig"
c3rc="$RC"
if [ "$RC" -eq 0 ]; then
    report_case 3 "$RC" "PASS (200-deep nested expression @ 1MB)"
else
    report_case 3 "$RC" "FAIL (want rc=0)"
    bad "case 3: 200-deep nested expression rc=$RC want 0 under ulimit -s 1024"
fi

# ---- 4. depth-guard trip is a clean diagnostic, never a segfault ----
GUARD_MSG="expression lowering depth limit exceeded"
guard_hit=0
guard_bad=0
check_guard_run() {
    local c="$1" grc="$2"
    grep -q "$GUARD_MSG" "$WORK/$c.err" 2>/dev/null || return 0
    guard_hit=1
    if [ "$grc" -ge 128 ]; then
        bad "case 4: depth guard tripped in $c but run died on signal (rc=$grc)"
        guard_bad=1
    fi
    if ! grep -q "error\[[0-9]*\]" "$WORK/$c.err"; then
        bad "case 4: guard trip in $c has no clean error[...] diagnostic line"
        guard_bad=1
    fi
}
check_guard_run c1 "$c1rc"
check_guard_run c2 "$c2rc"
check_guard_run c3 "$c3rc"
if [ "$guard_bad" -ne 0 ]; then
    echo "case 4: FAIL (guard trip was not a clean diagnostic)"
elif [ "$guard_hit" -eq 0 ]; then
    echo "case 4: PASS (guard did not trip; safety net unused on these inputs)"
else
    echo "case 4: PASS (guard trips reported as clean diagnostics)"
fi

# ---- 5. four 8-pin entries: emit + --dump-c89 md5 pins (safe+fast) ----
pin_check() {
    local entry="$1" want_safe="$2" want_fast="$3" name="$4"
    mkdir -p "$WORK/pin_$name"
    set +e
    ( cd "$ROOT" && timeout 120 "$ZIG1" -ffast -o "$WORK/pin_$name" "$entry" ) \
        >"$WORK/pin_$name.out" 2>"$WORK/pin_$name.err"
    local rco=$?
    set -e
    if [ "$rco" -ne 0 ]; then
        bad "case 5: $name emit rc=$rco want 0"
        echo "case 5: $name rc=$rco FAIL (emit)"
        return
    fi
    local got_safe got_fast rcd
    set +e
    got_safe="$( cd "$ROOT" && timeout 120 "$ZIG1" -fsafe --dump-c89 "$entry" 2>"$WORK/pin_$name.dumperr" | md5sum | cut -d' ' -f1 )"
    rcd=$?
    set -e
    if [ "$rcd" -ne 0 ]; then
        bad "case 5: $name -fsafe --dump-c89 pipeline rc=$rcd"
        echo "case 5: $name rc=$rcd FAIL (dump-c89 safe)"
        return
    fi
    set +e
    got_fast="$( cd "$ROOT" && timeout 120 "$ZIG1" -ffast --dump-c89 "$entry" 2>>"$WORK/pin_$name.dumperr" | md5sum | cut -d' ' -f1 )"
    rcd=$?
    set -e
    if [ "$rcd" -ne 0 ]; then
        bad "case 5: $name -ffast --dump-c89 pipeline rc=$rcd"
        echo "case 5: $name rc=$rcd FAIL (dump-c89 fast)"
        return
    fi
    local ok=1
    if [ "$got_safe" != "$want_safe" ]; then
        bad "case 5: $name -fsafe pin moved: got $got_safe want $want_safe"
        ok=0
    fi
    if [ "$got_fast" != "$want_fast" ]; then
        bad "case 5: $name -ffast pin moved: got $got_fast want $want_fast"
        ok=0
    fi
    if [ "$ok" -eq 1 ]; then
        echo "case 5: $name rc=0 PASS (pins $got_safe / $got_fast)"
    else
        echo "case 5: $name rc=0 FAIL (pin moved)"
    fi
}

pin_check "examples/z98/mud_server/main.zig" \
    "1b259bcd0584256029af931a53a03ae3" "e295d1c85dc837163c5de4898b03b8d4" mud_server
pin_check "examples/z98/game_of_life/main.zig" \
    "5be7b43b8f5bc5cc454aa1b434819ab1" "1e091c84f97280d1ae765597a0a61d84" game_of_life
pin_check "examples/z98/lisp_interpreter_curr/main.zig" \
    "12b75058c92aa866ef9ce99ea2a401dd" "82b721b588adddda63e2dc30e96bbfcb" lisp_interpreter_curr
pin_check "examples/z98/json_parser/main.zig" \
    "b5be954dc2d6b7c46c46bd90d910fc95" "048c2547541c2b1038556564a0706abb" json_parser

# ---- 6. 120-term runtime-valued left-deep `+` chain (Task 2 RED->GREEN) ----
# Fixture (validated shape): each term is a u32 local seeded through
# `@intCast(u32, argvc)` (argvc from a fn call) so the chain is runtime-valued
# and lowerFoldedIntConst cannot collapse it to one const.
C6_TERMS="a0"
_c6=1
while [ "$_c6" -lt 120 ]; do C6_TERMS="$C6_TERMS + a$_c6"; _c6=$((_c6 + 1)); done
{
    printf '%s\n' 'const std = @import("std");'
    printf '%s\n' 'fn getv(x: u32) u32 { return x; }'
    printf '%s\n' 'pub fn main() void {'
    printf '%s\n' '    var argvc: u32 = getv(7);'
    _c6=0
    while [ "$_c6" -lt 120 ]; do
        printf '    var a%s: u32 = @intCast(u32, argvc);\n' "$_c6"
        _c6=$((_c6 + 1))
    done
    printf '    var r: u32 = %s;\n' "$C6_TERMS"
    printf '%s\n' '    std.io.printInt(@intCast(i32, r));'
    printf '%s\n' '}'
} >"$WORK/chain120.zig"

run1mb c6 "$WORK/chain120.zig"
c6rc="$RC"
if [ "$RC" -ne 0 ]; then
    report_case 6 "$RC" "FAIL (want rc=0; 120-term chain must compile at 1MB)"
    bad "case 6: chain120 rc=$RC want 0 under ulimit -s 1024"
else
    report_case 6 "$RC" "PASS (120-term runtime + chain @ 1MB)"
fi

# Reference md5 source: the BASELINE compiler emitting the same 120-term
# fixture. Requested `ulimit -s 8192` cannot work -- the baseline segfaults on
# this fixture at 8 MB (measured: 115 terms OK, 118 SEGV; its pre-Task-2
# `lowerExpr` costs ~70 KB/level). 64 MB is the script's established
# baseline-ref stack (16/32 MB measured working too; all three agree byte for
# byte). C6_REF_MD5 is the recorded reference: re-derived 2026-10-26 from
# $GATE_BASELINE_ZIG1 at 64 MB, stable across repeated runs.
C6_REF_MD5="5cd515cddc41e59d8f03554a20cb5420"
BASE_ZIG1="${GATE_BASELINE_ZIG1:-/tmp/lowerfix_t2base/zig1_5_clean}"
if [ ! -x "$BASE_ZIG1" ]; then
    bad "case 6: baseline zig1 '$BASE_ZIG1' missing (set GATE_BASELINE_ZIG1)"
    echo "case 6: FAIL (no baseline for md5 reference)"
else
    set +e
    ( ulimit -s 65536 && timeout 180 "$BASE_ZIG1" -ffast --dump-c89 "$WORK/chain120.zig" ) \
        >"$WORK/c6_base.c" 2>"$WORK/c6_base.err"
    brc=$?
    set -e
    if [ "$brc" -ne 0 ]; then
        bad "case 6: baseline reference emit rc=$brc at 64MB"
        echo "case 6: FAIL (baseline reference rc=$brc)"
    else
        set +e
        ( ulimit -s 1024 && timeout 180 "$ZIG1" -ffast --dump-c89 "$WORK/chain120.zig" ) \
            >"$WORK/c6_new.c" 2>"$WORK/c6_new.err"
        nrc=$?
        set -e
        if [ "$nrc" -ne 0 ]; then
            bad "case 6: new --dump-c89 rc=$nrc at 1MB"
            echo "case 6: FAIL (dump rc=$nrc)"
        else
            bmd5="$(md5sum <"$WORK/c6_base.c" | cut -d' ' -f1)"
            nmd5="$(md5sum <"$WORK/c6_new.c" | cut -d' ' -f1)"
            if [ "$bmd5" = "$C6_REF_MD5" ] && [ "$nmd5" = "$C6_REF_MD5" ]; then
                echo "case 6: md5 PASS ($nmd5 == baseline@64MB == recorded reference)"
            else
                bad "case 6: dump md5 mismatch: new=$nmd5 baseline=$bmd5 recorded=$C6_REF_MD5"
                echo "case 6: md5 FAIL (new=$nmd5 baseline=$bmd5 recorded=$C6_REF_MD5)"
            fi
        fi
    fi
fi

# ---- 7. sema depth guard: 200-term chain -> clean error[...], no segfault ----
# Same fixture shape as case 6 at 200 terms -- over the semantic-analyzer
# ceiling (~135 terms at 1 MB, D9) and over SEMA_GUARD_MAX (128). The guard at
# `semanticAnalyzerResolveExprDepthGuard` (sf/src/semantic_analyzer.zig) must
# stop recursion at the cap and report a clean `error[...]`; the run must die
# on rc=0-free, signal-free exit with 0 `.c` emitted.
SEMA_GUARD_MSG="expression nesting too deep for semantic analysis"
C7_TERMS="a0"
_c7=1
while [ "$_c7" -lt 200 ]; do C7_TERMS="$C7_TERMS + a$_c7"; _c7=$((_c7 + 1)); done
{
    printf '%s\n' 'const std = @import("std");'
    printf '%s\n' 'fn getv(x: u32) u32 { return x; }'
    printf '%s\n' 'pub fn main() void {'
    printf '%s\n' '    var argvc: u32 = getv(7);'
    _c7=0
    while [ "$_c7" -lt 200 ]; do
        printf '    var a%s: u32 = @intCast(u32, argvc);\n' "$_c7"
        _c7=$((_c7 + 1))
    done
    printf '    var r: u32 = %s;\n' "$C7_TERMS"
    printf '%s\n' '    std.io.printInt(@intCast(i32, r));'
    printf '%s\n' '}'
} >"$WORK/chain200.zig"

run1mb c7 "$WORK/chain200.zig"
c7rc="$RC"
c7_ok=1
if [ "$c7rc" -eq 0 ]; then
    c7_ok=0
    bad "case 7: 200-term chain rc=0 want non-zero (guard must reject it)"
fi
if [ "$c7rc" -ge 128 ]; then
    c7_ok=0
    bad "case 7: 200-term chain died on signal (rc=$c7rc) want clean error[...]"
fi
if ! grep -q "$SEMA_GUARD_MSG" "$WORK/c7.err" 2>/dev/null; then
    c7_ok=0
    bad "case 7: stderr lacks the sema guard message '$SEMA_GUARD_MSG'"
fi
if ! grep -q "error\[[0-9]*\]" "$WORK/c7.err" 2>/dev/null; then
    c7_ok=0
    bad "case 7: no clean error[...] diagnostic on stderr"
fi
if [ -n "$(find "$WORK/c7" -name '*.c' -print -quit 2>/dev/null)" ]; then
    c7_ok=0
    bad "case 7: .c emitted despite the guard diagnostic"
fi
if [ "$c7_ok" -eq 1 ]; then
    echo "case 7: rc=$c7rc PASS (clean error, guard message, 0 .c)"
else
    echo "case 7: rc=$c7rc FAIL (want clean non-signal error, 0 .c)"
fi

# ---- 8. call whose argument is a 120-term runtime `+` chain (Task 3) ----
# `sink(a0 + a1 + ... + a119)`: the deep-+-inside-a-call shape parses at depth
# 2 (nested f(g(h(...))) is parser-blocked at depth 12, MAX_FN_PARAMS caps a
# wide call at 64) and drives the `fn_call` arm's interleaved prealloc/arg
# ordering while the arg recurses through the chain. 120 terms, same
# runtime-valued locals as case 6 (seeded through `@intCast(u32, argvc)` so
# lowerFoldedIntConst cannot fold), under SEMA_GUARD_MAX (128). Must compile
# rc=0 at 1 MB and its `--dump-c89` md5 must equal the BASELINE compiler's
# emit at 64 MB.
C8_TERMS="a0"
_c8=1
while [ "$_c8" -lt 120 ]; do C8_TERMS="$C8_TERMS + a$_c8"; _c8=$((_c8 + 1)); done
{
    printf '%s\n' 'const std = @import("std");'
    printf '%s\n' 'fn getv(x: u32) u32 { return x; }'
    printf '%s\n' 'fn sink(x: u32) u32 { return x; }'
    printf '%s\n' 'pub fn main() void {'
    printf '%s\n' '    var argvc: u32 = getv(7);'
    _c8=0
    while [ "$_c8" -lt 120 ]; do
        printf '    var a%s: u32 = @intCast(u32, argvc);\n' "$_c8"
        _c8=$((_c8 + 1))
    done
    printf '    var r: u32 = sink(%s);\n' "$C8_TERMS"
    printf '%s\n' '    std.io.printInt(@intCast(i32, r));'
    printf '%s\n' '}'
} >"$WORK/callchain120.zig"

run1mb c8 "$WORK/callchain120.zig"
c8rc="$RC"
if [ "$RC" -ne 0 ]; then
    report_case 8 "$RC" "FAIL (want rc=0; call(arg=120-term chain) must compile at 1MB)"
    bad "case 8: callchain120 rc=$RC want 0 under ulimit -s 1024"
else
    report_case 8 "$RC" "PASS (call(arg=120-term runtime + chain) @ 1MB)"
fi

# ---- 9. if expression with 120-term runtime `+` chains in both arms (T3) ----
# `var r: u32 = if (c) <chain> else <chain>;` with `var c: bool = true;` (a
# u32 condition is error[3058]) and the same runtime-valued locals as case 6.
# Nested if-expressions are parser-blocked at depth 12; the branch-chain shape
# parses at depth 3 and drives the `if` arm's interleaved cond/branch lowering.
# 120 terms per branch, under SEMA_GUARD_MAX. rc=0 at 1 MB, `--dump-c89` md5
# equals the BASELINE compiler's emit at 64 MB.
{
    printf '%s\n' 'const std = @import("std");'
    printf '%s\n' 'fn getv(x: u32) u32 { return x; }'
    printf '%s\n' 'pub fn main() void {'
    printf '%s\n' '    var argvc: u32 = getv(7);'
    _c8=0
    while [ "$_c8" -lt 120 ]; do
        printf '    var a%s: u32 = @intCast(u32, argvc);\n' "$_c8"
        _c8=$((_c8 + 1))
    done
    printf '%s\n' '    var c: bool = true;'
    printf '    var r: u32 = if (c) %s else %s;\n' "$C8_TERMS" "$C8_TERMS"
    printf '%s\n' '    std.io.printInt(@intCast(i32, r));'
    printf '%s\n' '}'
} >"$WORK/ifchain120.zig"

run1mb c9 "$WORK/ifchain120.zig"
c9rc="$RC"
if [ "$RC" -ne 0 ]; then
    report_case 9 "$RC" "FAIL (want rc=0; if-expr with 120-term chain arms must compile at 1MB)"
    bad "case 9: ifchain120 rc=$RC want 0 under ulimit -s 1024"
else
    report_case 9 "$RC" "PASS (if-expr chain arms @ 1MB)"
fi

# md5 reference for cases 8/9: the BASELINE compiler at 64 MB (same recipe and
# $GATE_BASELINE_ZIG1 as case 6; its pre-Task-2 lowerExpr needs >8 MB on these
# fixtures). Compare live: new@1MB must equal baseline@64MB.
if [ ! -x "$BASE_ZIG1" ]; then
    bad "cases 8/9: baseline zig1 '$BASE_ZIG1' missing (set GATE_BASELINE_ZIG1)"
    echo "case 8: md5 FAIL (no baseline)"; echo "case 9: md5 FAIL (no baseline)"
else
    for _pc in 8 9; do
        if [ "$_pc" = "8" ]; then _pf="$WORK/callchain120.zig"; _pn="c8"; else _pf="$WORK/ifchain120.zig"; _pn="c9"; fi
        set +e
        ( ulimit -s 65536 && timeout 180 "$BASE_ZIG1" -ffast --dump-c89 "$_pf" ) \
            >"$WORK/${_pn}_base.c" 2>"$WORK/${_pn}_base.err"
        brc=$?
        set -e
        if [ "$brc" -ne 0 ]; then
            bad "case $_pc: baseline reference emit rc=$brc at 64MB"
            echo "case $_pc: md5 FAIL (baseline reference rc=$brc)"
        else
            set +e
            ( ulimit -s 1024 && timeout 180 "$ZIG1" -ffast --dump-c89 "$_pf" ) \
                >"$WORK/${_pn}_new.c" 2>"$WORK/${_pn}_new.err"
            nrc=$?
            set -e
            if [ "$nrc" -ne 0 ]; then
                bad "case $_pc: new --dump-c89 rc=$nrc at 1MB"
                echo "case $_pc: md5 FAIL (dump rc=$nrc)"
            else
                bmd5="$(md5sum <"$WORK/${_pn}_base.c" | cut -d' ' -f1)"
                nmd5="$(md5sum <"$WORK/${_pn}_new.c" | cut -d' ' -f1)"
                if [ "$bmd5" = "$nmd5" ]; then
                    echo "case $_pc: md5 PASS ($nmd5 == baseline@64MB)"
                else
                    bad "case $_pc: dump md5 mismatch: new=$nmd5 baseline=$bmd5"
                    echo "case $_pc: md5 FAIL (new=$nmd5 baseline=$bmd5)"
                fi
            fi
        fi
    done
fi

if [ "$fail" -eq 0 ]; then
    echo "LOWER_DEPTH GATE OK"
    exit 0
fi
echo "LOWER_DEPTH GATE FAILED" >&2
exit 1
