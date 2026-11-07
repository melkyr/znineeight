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
#      `--dump-c89` md5s match the authoritative 8-pin table (v143 authorized
#      second re-baseline for the std_gpa medium-decommit-failure fix; both
#      modes moved because the dump includes the std_gpa module C):
#        mud  b487f404e4f290d45e348f57867c7293 / 2771a1c69fb548d5db755b1d5eba91f0
#        gol  a5e2a7556f5ab051a26728afa236d77d / 2469bc11d40a2717690251a0e20e1c5a
#        lisp 15ebc406050f3a6f70f70265de226a2f / 98d60a9cc72ebc3a248784443bf2ead3
#        json cc0deb57e2367a9e4482a52a5cb81c41 / 097174bd480867381e133278fdfc26cc
#      (left = `-fsafe`, right = `-ffast`);
#   6. a generated 120-term RUNTIME-VALUED (not literal-folded) left-deep `+`
#      chain compiles rc=0 under `ulimit -s 1024` (Task 2 trampoline) and its
#      `--dump-c89` md5 equals the same source compiled by the BASELINE
#      compiler at 64 MB stack. Each term is a `u32` local seeded via
#      `@intCast(u32, argvc)` where `argvc = getv(7)`, so `lowerFoldedIntConst`
#      cannot fold the chain. 120 terms sits UNDER the semantic-analyzer wall
#      (~139 terms at 1 MB, D9) and under SEMA_GUARD_MAX (130), so this case is
#      green without tripping either. The baseline CANNOT emit the reference at
#      8 MB (measured: 115 terms OK, 118 SEGV -- its pre-Task-2 `lowerExpr`
#      costs ~70 KB/level; 30 the 1 MB threshold), so the reference run uses
#      64 MB. Baseline binary comes from $GATE_BASELINE_ZIG1 (default
#      /tmp/lowerfix_t2base/zig1_5_clean = the pre-change HEAD build; NOT
#      /tmp/lowerfix_base -- that one predates the dense-`ERROR_*` emitter and
#      its dump bytes differ by construction). Recorded reference md5 (stable
#      across 16/32/64 MB baseline runs): C6_REF_MD5 below. When the baseline
#      resolves to no executable, the md5 sub-asserts (cases 6/8/9/10-12) are
#      SKIPPED with a clear message -- never a bogus md5 mismatch -- and the
#      rc/guard/frame-size asserts still run.
#   7. a generated 200-term RUNTIME-VALUED left-deep `+` chain (same shape as
#      case 6) is OVER the semantic-analyzer ceiling (~139 terms at 1 MB) and
#      over SEMA_GUARD_MAX (130). It must fail as a CLEAN `error[3077]`
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
#      SEMA_GUARD_MAX (130).
#   9. an `if` EXPRESSION with 120-term RUNTIME-VALUED `+` chains in both
#      arms (`var r: u32 = if (c) <chain> else <chain>;`, `var c: bool = true;`
#      -- a u32 condition is error[3058]) compiles rc=0 under `ulimit -s 1024`
#      (Task 3 if_expr arm) and its `--dump-c89` md5 equals the BASELINE
#      compiler's emit at 64 MB. Nested if-expressions are parser-blocked at
#      depth 12; the branch-chain shape parses at depth 3.
#  10. 300-deep nested blocks `{ { { ... } } }` as statements compiles rc=0
#      under `ulimit -s 1024` (Task 4 statement trampoline) and its
#      `--dump-c89` md5 equals the BASELINE compiler's emit at 64 MB.
#      Statement nesting is a different axis from the parser's expr_depth>12
#      cap; measured parser C-stack ceiling at 1 MB (syntax-error-at-innermost
#      isolation): blocks ~500, if-statements ~315, mixed labeled/while ~320
#      -- 300 sits under all three. No source-level statement-depth cap exists.
#  11. 300-deep nested `if` STATEMENTS (`if (c) { if (c) { ... } }`, runtime
#      cond `c` seeded via `getb(1)` so comptimeFoldBool cannot fold it) rc=0
#      at 1 MB + md5 == baseline@64MB.
#  12. 300-deep nested labeled/loop statements (alternating `lN: { ... }` /
#      `while (c) { ... }`, 150 of each) rc=0 at 1 MB + md5 ==
#      baseline@64MB. Exercises the labeled_stmt machine and both LoopInfo
#      shapes (is_loop=0 labeled blocks, is_loop=1 while loops).
#  10-12 must never trip error[3077] (SEMA_GUARD_MAX guards EXPRESSION
#  chains, not statement nesting) -- a trip is a STOP, not a fixture to shrink.
#  13. lowerer C frame sizes: emit sf/src/lower.zig with the tested zig1,
#      compile the emitted lowerer C (lower_*.c) with
#      `gcc -m32 -std=c89 -O0 -fstack-usage`, parse the .su files (one .su
#      per emitted C file), and assert the LARGEST lowerer frame is < 8192
#      bytes. Self-contained (no baseline
#      binary needed). RED at T5 start: `lowerExprImpl` measured 65,552 bytes
#      (one C89 frame for every arm local of the fallback chain). Task 5
#      splits it (and `lowerStmtLeafStep` 17,856 / `lowerFnCallStep` 8,944)
#      into per-kind functions so no lowerer frame reaches 8 KB.
#  14. a runtime-valued left-deep `+` chain at SEMA_GUARD_MAX+1 terms (131 at
#      the current cap 130, same shape as case 7) must be rejected by the sema
#      depth guard as a CLEAN limit diagnostic -- rc exactly 2, stderr carries
#      `error[3077] expression nesting too deep for semantic analysis (limit
#      130)`, 0 `.c` emitted, and no `error[3043]`/ICE or signal death
#      (rc>=128). This pins the raised cap and the new limit-family code.
#  15. the folded-terminator/labeled-block regression repro still prints 42/7.
#  16. enum-value machinery under a `-fsafe` compiler built from the same
#      emission (self-contained scratch build): a single member at i64/u63 max
#      compiles rc 0 (the shared walk must not trap on `mval + 1`), and an
#      implicit successor after the declared max OR the i64 storage max (u64)
#      rejects rc 2 with `error[3000]` and NO secondary `error[3062]`.
#  17-18. `enum(u40) { A = 0, B = 4294967297 }` resolves the wide discriminant
#      exactly (shorthand `.B` and qualified `E.B`) at runtime: stdout `8`, rc 0.
#  19-25. parenthesized case items / range endpoints resolve in lowering:
#      `(-1)`, `(- 1)`, `((1))`, `(-5)...(-1)`, `(NEG)`/`((NEG))`, `(true)` on
#      bool, and `((1))` on u32 each emit a real `case` and run to the committed
#      stdout/rc instead of being silently dropped.
#  26-28. negative case items reject with `error[3062]`, rc 2, 0 `.c`:
#      `(-1)` on u32 (pins the pre-existing const-path reject) and bare/paren
#      `-1` on bool (`type 'bool' cannot represent integer value '-1'`).
#  29. bool case items keep the tolerated `true`/`false`/`0`/`1` forms accepted,
#      including parenthesized variants; stdout `101111111`, rc 0.
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
    "b487f404e4f290d45e348f57867c7293" "2771a1c69fb548d5db755b1d5eba91f0" mud_server
pin_check "examples/z98/game_of_life/main.zig" \
    "a5e2a7556f5ab051a26728afa236d77d" "2469bc11d40a2717690251a0e20e1c5a" game_of_life
pin_check "examples/z98/lisp_interpreter_curr/main.zig" \
    "15ebc406050f3a6f70f70265de226a2f" "98d60a9cc72ebc3a248784443bf2ead3" lisp_interpreter_curr
pin_check "examples/z98/json_parser/main.zig" \
    "cc0deb57e2367a9e4482a52a5cb81c41" "097174bd480867381e133278fdfc26cc" json_parser

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
    echo "case 6: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
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
# ceiling (~139 terms at 1 MB, D9) and over SEMA_GUARD_MAX (130). The guard at
# `semanticAnalyzerResolveExprDepthGuard` (sf/src/semantic_analyzer.zig) must
# stop recursion at the cap and report a clean `error[3077]`; the run must die
# on rc=0-free, signal-free exit with 0 `.c` emitted.
SEMA_GUARD_MSG="expression nesting too deep for semantic analysis"
SEMA_GUARD_CODE="error\\[3077\\]"
SEMA_GUARD_LIMIT="(limit 130)"
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
if ! grep -q "$SEMA_GUARD_CODE" "$WORK/c7.err" 2>/dev/null; then
    c7_ok=0
    bad "case 7: stderr lacks the limit-family diagnostic '$SEMA_GUARD_CODE'"
fi
if ! grep -qF "$SEMA_GUARD_LIMIT" "$WORK/c7.err" 2>/dev/null; then
    c7_ok=0
    bad "case 7: stderr lacks the raised cap '$SEMA_GUARD_LIMIT'"
fi
if grep -q 'error\[3043\]' "$WORK/c7.err" 2>/dev/null; then
    c7_ok=0
    bad "case 7: sema guard still classified as ICE (error[3043])"
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
# lowerFoldedIntConst cannot fold), under SEMA_GUARD_MAX (130). Must compile
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
    echo "case 8: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
    echo "case 9: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
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

# ---- 10. 300-deep nested blocks (Task 4 statement trampoline) ----
# `{ { { ... } } }` 300 deep as STATEMENTS. Statement nesting is a different
# axis from the parser's expr_depth>12 cap; measured parser C-stack ceiling at
# 1 MB (syntax-error-at-innermost isolation): blocks ~500, ifs ~315, mixed
# labeled/while ~320 -- 300 sits under all three, so the fixture parses at
# 1 MB and RED today is pure lowering recursion (18 KB lowerStmt frame x 300).
# Must compile rc=0 at 1 MB and its --dump-c89 md5 must equal the BASELINE
# compiler's emit at 64 MB. SEMA_GUARD_MAX (130) guards EXPRESSION chains;
# these are statements and must never trip error[3077] (a trip is a STOP,
# not a fixture to shrink).
B300="{ }"
_b3=0
while [ "$_b3" -lt 299 ]; do B300="{ $B300 }"; _b3=$((_b3 + 1)); done
cat >"$WORK/block300.zig" <<EOF
pub fn main() void {
    $B300
}
EOF

# ---- 11. 300-deep nested if STATEMENTS ----
# `if (c) { if (c) { ... } }` 300 deep with a runtime cond (`getb(1)`; an ident
# cond never comptime-folds, so the NORMAL if path is exercised, not the fold
# path). rc=0 at 1 MB + md5 == baseline@64MB.
I300="{ }"
_i3=0
while [ "$_i3" -lt 300 ]; do I300="if (c) { $I300 }"; _i3=$((_i3 + 1)); done
cat >"$WORK/if300.zig" <<EOF
fn getb(x: u32) bool { return x != 0; }
pub fn main() void {
    var c: bool = getb(1);
    $I300
}
EOF

# ---- 12. 300-deep nested labeled/loop statements ----
# Alternating `lN: { ... }` / `while (c) { ... }` (300 levels, 150 of each):
# exercises the labeled_stmt machine and BOTH LoopInfo shapes (is_loop=0 for
# labeled blocks, is_loop=1 for while). Runtime cond as case 11. rc=0 at
# 1 MB + md5 == baseline@64MB.
L300="{ }"
_l3=299
while [ "$_l3" -ge 0 ]; do
    if [ $((_l3 % 2)) -eq 0 ]; then L300="l$_l3: { $L300 }"; else L300="while (c) { $L300 }"; fi
    _l3=$((_l3 - 1))
done
cat >"$WORK/lab300.zig" <<EOF
fn getb(x: u32) bool { return x != 0; }
pub fn main() void {
    var c: bool = getb(1);
    $L300
}
EOF

run1mb c10 "$WORK/block300.zig"
c10rc="$RC"
if [ "$c10rc" -ne 0 ]; then
    report_case 10 "$c10rc" "FAIL (want rc=0; 300-deep nested blocks must compile at 1MB)"
    bad "case 10: block300 rc=$c10rc want 0 under ulimit -s 1024"
else
    report_case 10 "$c10rc" "PASS (300-deep nested blocks @ 1MB)"
fi

run1mb c11 "$WORK/if300.zig"
c11rc="$RC"
if [ "$c11rc" -ne 0 ]; then
    report_case 11 "$c11rc" "FAIL (want rc=0; 300-deep nested if statements must compile at 1MB)"
    bad "case 11: if300 rc=$c11rc want 0 under ulimit -s 1024"
else
    report_case 11 "$c11rc" "PASS (300-deep nested if statements @ 1MB)"
fi

run1mb c12 "$WORK/lab300.zig"
c12rc="$RC"
if [ "$c12rc" -ne 0 ]; then
    report_case 12 "$c12rc" "FAIL (want rc=0; 300-deep nested labeled/loop statements must compile at 1MB)"
    bad "case 12: lab300 rc=$c12rc want 0 under ulimit -s 1024"
else
    report_case 12 "$c12rc" "PASS (300-deep nested labeled/loop statements @ 1MB)"
fi

# error[3077] (sema depth guard) is about EXPRESSION chains; cases 10-12 are
# statements and must not trip it. A trip is a STOP signal, not a fixture bug.
for _g in c10 c11 c12; do
    if grep -q 'error\[3077\]' "$WORK/$_g.err" 2>/dev/null; then
        bad "case 10-12: $_g tripped error[3077] (sema guard) on statement nesting -- STOP"
    fi
done

# md5 reference for cases 10-12: the BASELINE compiler at 64 MB (same recipe
# and $GATE_BASELINE_ZIG1 as cases 6/8/9; the pre-T4 recursive lowerStmt needs
# ~5.4 MB at 300 deep). Compare live: new@1MB must equal baseline@64MB.
if [ ! -x "$BASE_ZIG1" ]; then
    echo "case 10: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
    echo "case 11: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
    echo "case 12: md5 SKIP (md5 comparisons require GATE_BASELINE_ZIG1=<path to baseline zig1_5_clean>)"
else
    for _pc in 10 11 12; do
        if [ "$_pc" = "10" ]; then _pf="$WORK/block300.zig"; _pn="c10"
        elif [ "$_pc" = "11" ]; then _pf="$WORK/if300.zig"; _pn="c11"
        else _pf="$WORK/lab300.zig"; _pn="c12"; fi
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

# ---- 13. lowerer C frame sizes: largest frame < 8192 bytes ----
# Self-contained (no baseline binary): emit sf/src/lower.zig with the tested
# zig1, compile the emitted lowerer C (lower_*.c) with
# `gcc -m32 -std=c89 -O0 -fstack-usage`, parse the .su files (one .su per
# emitted C file), assert the LARGEST lowerer frame is < 8192 bytes. RED at
# T5 start (lowerExprImpl
# 65,552). The .su parse takes the second-to-last whitespace field of each
# line (`file:line:col:func <bytes> <qualifier>`).
mkdir -p "$WORK/c13"
set +e
( cd "$ROOT" && timeout 300 "$ZIG1" -ffast --dump-c89 --output-dir "$WORK/c13" sf/src/lower.zig ) \
    >"$WORK/c13.out" 2>"$WORK/c13.err"
c13rc=$?
set -e
if [ "$c13rc" -ne 0 ]; then
    report_case 13 "$c13rc" "FAIL (want rc=0; emit sf/src/lower.zig)"
    bad "case 13: emit sf/src/lower.zig rc=$c13rc want 0"
else
    set +e
    ( cd "$WORK/c13" && gcc -m32 -std=c89 -O0 -fstack-usage -I . -c lower_*.c ) \
        >"$WORK/c13_gcc.out" 2>"$WORK/c13_gcc.err"
    c13grc=$?
    set -e
    c13su=0
    for c13s in "$WORK/c13"/lower_*.su; do
        if [ -f "$c13s" ]; then c13su=1; fi
    done
    if [ "$c13grc" -ne 0 ] || [ "$c13su" -eq 0 ]; then
        report_case 13 "$c13grc" "FAIL (gcc -fstack-usage on emitted lowerer C)"
        bad "case 13: gcc -c emitted lowerer C rc=$c13grc want 0 + lower_*.su"
    else
        c13max="$(awk '{v=$(NF-1); if (v ~ /^[0-9]+$/ && v+0 > m) m=v+0} END {print m+0}' "$WORK/c13"/lower_*.su)"
        note "case 13 top frames: $(sort -k2,2nr "$WORK/c13"/lower_*.su | head -3 | cut -f1 | cut -d: -f2- | tr '\n' ' ')"
        if [ "$c13max" -lt 8192 ]; then
            report_case 13 0 "PASS (largest lowerer frame $c13max < 8192)"
        else
            report_case 13 1 "FAIL (largest lowerer frame $c13max >= 8192)"
            bad "case 13: largest lowerer frame $c13max >= 8192 (want < 8192)"
        fi
    fi
fi

# ---- 14. sema cap boundary: SEMA_GUARD_MAX+1 -> clean limit diagnostic ----
# 131 terms (the current cap is 130) is the first rejected depth. It must stop
# ONE level above the cap with rc exactly 2, the new limit-family code, the
# raised limit text, no ICE classification and 0 `.c` -- never a SIGSEGV.
C14_TERMS="a0"
_c14=1
while [ "$_c14" -lt 131 ]; do C14_TERMS="$C14_TERMS + a$_c14"; _c14=$((_c14 + 1)); done
{
    printf '%s\n' 'const std = @import("std");'
    printf '%s\n' 'fn getv(x: u32) u32 { return x; }'
    printf '%s\n' 'pub fn main() void {'
    printf '%s\n' '    var argvc: u32 = getv(7);'
    _c14=0
    while [ "$_c14" -lt 131 ]; do
        printf '    var a%s: u32 = @intCast(u32, argvc);\n' "$_c14"
        _c14=$((_c14 + 1))
    done
    printf '    var r: u32 = %s;\n' "$C14_TERMS"
    printf '%s\n' '    std.io.printInt(@intCast(i32, r));'
    printf '%s\n' '}'
} >"$WORK/chain131.zig"

run1mb c14 "$WORK/chain131.zig"
c14rc="$RC"
c14_ok=1
if [ "$c14rc" -ne 2 ]; then
    c14_ok=0
    bad "case 14: 131-term chain rc=$c14rc want exactly 2 (clean limit diagnostic)"
fi
if [ "$c14rc" -ge 128 ]; then
    c14_ok=0
    bad "case 14: 131-term chain died on signal (rc=$c14rc) want clean error[3077]"
fi
if ! grep -q "$SEMA_GUARD_MSG" "$WORK/c14.err" 2>/dev/null; then
    c14_ok=0
    bad "case 14: stderr lacks the sema guard message '$SEMA_GUARD_MSG'"
fi
if ! grep -q "$SEMA_GUARD_CODE" "$WORK/c14.err" 2>/dev/null; then
    c14_ok=0
    bad "case 14: stderr lacks the limit-family diagnostic '$SEMA_GUARD_CODE'"
fi
if ! grep -qF "$SEMA_GUARD_LIMIT" "$WORK/c14.err" 2>/dev/null; then
    c14_ok=0
    bad "case 14: stderr lacks the raised cap '$SEMA_GUARD_LIMIT'"
fi
if grep -q 'error\[3043\]' "$WORK/c14.err" 2>/dev/null; then
    c14_ok=0
    bad "case 14: sema guard still classified as ICE (error[3043])"
fi
if [ -n "$(find "$WORK/c14" -name '*.c' -print -quit 2>/dev/null)" ]; then
    c14_ok=0
    bad "case 14: .c emitted despite the limit diagnostic"
fi
if [ "$c14_ok" -eq 1 ]; then
    echo "case 14: rc=$c14rc PASS (error[3077] $SEMA_GUARD_LIMIT, 0 .c)"
else
    echo "case 14: rc=$c14rc FAIL (want rc=2 clean limit diagnostic, 0 .c)"
fi

# ---- 15. folded terminating if inside an explicit labeled block ----
# Regression for the E3B folded-arm DCE flag leaking past lowerBlockStmtStep /
# lowerStmtLabeledStep: `outer: { if (c) break :outer; if (true) return 7; }`
# must still emit the post-label `return 42` (run(true) -> 42) and the folded
# return (run(false) -> 7). Compile, build via the emitted linux script, run.
C15_DIR="$ROOT/repro/mi_matrix/known_excluded/folded_terminator_labeled_block_ok"
run1mb c15 "$C15_DIR/main.zig"
c15rc="$RC"
c15_ok=1
if [ "$c15rc" -ne 0 ]; then
    c15_ok=0
    bad "case 15: folded_terminator_labeled_block_ok emit rc=$c15rc want 0"
fi
if [ "$c15_ok" -eq 1 ]; then
    if ! ( cd "$WORK/c15" && timeout 120 sh build_target.sh linux prog ) \
        >"$WORK/c15.build.log" 2>&1; then
        c15_ok=0
        bad "case 15: build_target.sh linux failed (see $WORK/c15.build.log)"
    fi
fi
if [ "$c15_ok" -eq 1 ]; then
    set +e
    ( cd "$WORK/c15" && timeout 10 ./prog </dev/null ) \
        >"$WORK/c15.run.out" 2>"$WORK/c15.run.err"
    c15run="$?"
    set -e
    if ! cmp -s "$WORK/c15.run.out" "$C15_DIR/expected.txt"; then
        c15_ok=0
        bad "case 15: runtime stdout mismatch (want 42/7)"
    fi
    c15want="$(tr -d '\r\n' <"$C15_DIR/expected.rc")"
    if [ "$c15run" -ne "$c15want" ]; then
        c15_ok=0
        bad "case 15: runtime rc=$c15run want $c15want"
    fi
fi
if [ "$c15_ok" -eq 1 ]; then
    report_case 15 "$c15rc" "PASS (folded terminator + labeled block prints 42/7)"
else
    report_case 15 "$c15rc" "FAIL (folded terminator + labeled block regression)"
fi

# ---- 16. -fsafe enum-value machinery: valid max compiles, implicit successor rejects ----
# The normal fast corpus classifier cannot see the i64-max overflow trap: only a
# `-fsafe` compiler traps. Build a safe compiler from the SAME source emission
# (I-B §1 recipe), then:
#   * enum_i64_max_ok_xmod / enum_u63_max_ok_xmod: rc 0, `.c` emitted;
#   * enum_i64_max_implicit_reject_xmod / enum_u63_max_implicit_reject_xmod /
#     enum_u64_max_implicit_reject_xmod: rc 2, 0 `.c`, `error[3000]`, and NO
#     secondary `error[3062]` (`u64` catches the i64 STORAGE max, not the
#     declared u64 width).
# Self-contained scratch build under $WORK; no shared state.
GATE_ZLIB="$(cd "$(dirname "$ZIG1")" && pwd)/lib"
if [ ! -d "$GATE_ZLIB" ]; then GATE_ZLIB="$ROOT/sf/src"; fi
SAFE_ZIG="$WORK/c16_safe/zig1_safe"
mkdir -p "$WORK/c16_safe"
c16_ok=1
set +e
( cd "$ROOT" && timeout 300 "$ZIG1" -fsafe -o "$WORK/c16_safe" --lib-dir "$GATE_ZLIB" sf/src/main.zig ) \
    >"$WORK/c16_safe_emit.out" 2>"$WORK/c16_safe_emit.err"
c16_emit=$?
set -e
if [ "$c16_emit" -ne 0 ]; then
    c16_ok=0
    bad "case 16: -fsafe compiler emit rc=$c16_emit want 0"
elif ! ( cd "$WORK/c16_safe" && timeout 300 sh build_target.sh linux zig1_safe ) \
    >"$WORK/c16_safe_build.log" 2>&1; then
    c16_ok=0
    bad "case 16: -fsafe compiler build_target failed (see $WORK/c16_safe_build.log)"
fi
if [ "$c16_ok" -eq 1 ]; then
    for _c16v in enum_i64_max_ok_xmod enum_u63_max_ok_xmod; do
        mkdir -p "$WORK/c16_valid_$_c16v"
        set +e
        ( cd "$WORK/c16_valid_$_c16v" && timeout 120 "$SAFE_ZIG" --dump-c89 \
            -o "$WORK/c16_valid_$_c16v" --lib-dir "$GATE_ZLIB" \
            "$ROOT/repro/mi_matrix/$_c16v/main.zig" ) \
            >"$WORK/c16_valid_$_c16v.out" 2>"$WORK/c16_valid_$_c16v.err"
        _c16rc=$?
        set -e
        if [ "$_c16rc" -ne 0 ]; then
            c16_ok=0
            bad "case 16: -fsafe $_c16v rc=$_c16rc want 0"
        elif [ -z "$(find "$WORK/c16_valid_$_c16v" -name '*.c' -print -quit 2>/dev/null)" ]; then
            c16_ok=0
            bad "case 16: -fsafe $_c16v emitted no .c"
        fi
    done
    for _c16r in enum_i64_max_implicit_reject_xmod enum_u63_max_implicit_reject_xmod enum_u64_max_implicit_reject_xmod; do
        mkdir -p "$WORK/c16_reject_$_c16r"
        set +e
        ( cd "$WORK/c16_reject_$_c16r" && timeout 120 "$SAFE_ZIG" --dump-c89 \
            -o "$WORK/c16_reject_$_c16r" --lib-dir "$GATE_ZLIB" \
            "$ROOT/repro/mi_matrix/$_c16r/main.zig" ) \
            >"$WORK/c16_reject_$_c16r.out" 2>"$WORK/c16_reject_$_c16r.err"
        _c16rc=$?
        set -e
        if [ "$_c16rc" -ne 2 ]; then
            c16_ok=0
            bad "case 16: -fsafe $_c16r rc=$_c16rc want 2"
        fi
        if ! grep -q 'error\[3000\]' "$WORK/c16_reject_$_c16r.err" 2>/dev/null; then
            c16_ok=0
            bad "case 16: -fsafe $_c16r missing error[3000]"
        fi
        if grep -q 'error\[3062\]' "$WORK/c16_reject_$_c16r.err" 2>/dev/null; then
            c16_ok=0
            bad "case 16: -fsafe $_c16r has secondary error[3062]"
        fi
        if [ -n "$(find "$WORK/c16_reject_$_c16r" -name '*.c' -print -quit 2>/dev/null)" ]; then
            c16_ok=0
            bad "case 16: -fsafe $_c16r emitted .c despite the reject"
        fi
    done
fi
if [ "$c16_ok" -eq 1 ]; then
    report_case 16 "$c16_emit" "PASS (-fsafe: max enums ok, implicit successor rejects)"
else
    report_case 16 "$c16_emit" "FAIL (-fsafe enum-value machinery)"
fi

# ---- 17-18. wide unsigned enum discriminants resolve exactly (runtime) ----
# `enum(u40) { A = 0, B = 4294967297 }`: the u32 `enum_value_table` truncates
# both the shorthand `.B` value and the `.A`/`.B` case labels to 0/1. The exact
# member walk must resolve them. Each case emits, builds, and runs; stdout must
# equal the committed expected.txt and rc the committed expected.rc (8).
_c16idx=17
for _c16w in switch_enum_u40_wide_ok_xmod switch_enum_u40_wide_qualified_ok_xmod; do
    _c16dn="c${_c16idx}_$_c16w"
    mkdir -p "$WORK/$_c16dn"
    set +e
    ( cd "$WORK/$_c16dn" && timeout 120 "$ZIG1" -ffast -o "$WORK/$_c16dn" \
        "$ROOT/repro/mi_matrix/$_c16w/main.zig" ) \
        >"$WORK/$_c16dn.out" 2>"$WORK/$_c16dn.err"
    _c16rc=$?
    set -e
    _c16ok=1
    if [ "$_c16rc" -ne 0 ]; then
        _c16ok=0
        bad "case $_c16idx: $_c16w emit rc=$_c16rc want 0"
    elif ! ( cd "$WORK/$_c16dn" && timeout 120 sh build_target.sh linux prog ) \
        >"$WORK/$_c16dn.build.log" 2>&1; then
        _c16ok=0
        bad "case $_c16idx: $_c16w build_target failed (see $WORK/$_c16dn.build.log)"
    else
        set +e
        ( cd "$WORK/$_c16dn" && timeout 10 ./prog </dev/null ) \
            >"$WORK/$_c16dn.run.out" 2>"$WORK/$_c16dn.run.err"
        _c16run=$?
        set -e
        if ! cmp -s "$WORK/$_c16dn.run.out" "$ROOT/repro/mi_matrix/$_c16w/expected.txt"; then
            _c16ok=0
            bad "case $_c16idx: $_c16w runtime stdout mismatch (want 8)"
        fi
        _c16want="$(tr -d '\r\n' <"$ROOT/repro/mi_matrix/$_c16w/expected.rc")"
        if [ "$_c16run" -ne "$_c16want" ]; then
            _c16ok=0
            bad "case $_c16idx: $_c16w runtime rc=$_c16run want $_c16want"
        fi
    fi
    if [ "$_c16ok" -eq 1 ]; then
        report_case "$_c16idx" "$_c16rc" "PASS ($_c16w runtime stdout 8)"
    else
        report_case "$_c16idx" "$_c16rc" "FAIL ($_c16w runtime)"
    fi
    _c16idx=$((_c16idx + 1))
done

# ---- 19-25. parenthesized case items resolve in lowering (Task 6b) ----
# A `paren_expr` wrapper around a case item / range endpoint must be unwrapped
# iteratively before dispatch: `(-1)`, `(- 1)`, `((1))`, `(-5)...(-1)`,
# `(NEG)`/`((NEG))`, `(true)` on bool, and `((1))` on u32 all resolve to a real
# `case` label instead of being silently dropped (only `default:`).
_c6b_case=19
for _c6b_ok in \
    switch_neg_paren_i32_ok_xmod \
    switch_neg_paren_space_ok_xmod \
    switch_paren_double_ok_xmod \
    switch_neg_paren_range_ok_xmod \
    switch_paren_named_const_ok_xmod \
    switch_bool_paren_ok_xmod \
    switch_u32_paren_ok_xmod; do
    _c6b_dn="c${_c6b_case}_$_c6b_ok"
    mkdir -p "$WORK/$_c6b_dn"
    set +e
    ( cd "$WORK/$_c6b_dn" && timeout 120 "$ZIG1" -ffast -o "$WORK/$_c6b_dn" \
        "$ROOT/repro/mi_matrix/$_c6b_ok/main.zig" ) \
        >"$WORK/$_c6b_dn.out" 2>"$WORK/$_c6b_dn.err"
    _c6b_rc=$?
    set -e
    _c6b_okflag=1
    if [ "$_c6b_rc" -ne 0 ]; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_ok emit rc=$_c6b_rc want 0"
    elif ! ( cd "$WORK/$_c6b_dn" && timeout 120 sh build_target.sh linux prog ) \
        >"$WORK/$_c6b_dn.build.log" 2>&1; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_ok build_target failed (see $WORK/$_c6b_dn.build.log)"
    else
        set +e
        ( cd "$WORK/$_c6b_dn" && timeout 10 ./prog </dev/null ) \
            >"$WORK/$_c6b_dn.run.out" 2>"$WORK/$_c6b_dn.run.err"
        _c6b_run=$?
        set -e
        if ! cmp -s "$WORK/$_c6b_dn.run.out" "$ROOT/repro/mi_matrix/$_c6b_ok/expected.txt"; then
            _c6b_okflag=0
            bad "case $_c6b_case: $_c6b_ok runtime stdout mismatch"
        fi
        _c6b_want="$(tr -d '\r\n' <"$ROOT/repro/mi_matrix/$_c6b_ok/expected.rc")"
        if [ "$_c6b_run" -ne "$_c6b_want" ]; then
            _c6b_okflag=0
            bad "case $_c6b_case: $_c6b_ok runtime rc=$_c6b_run want $_c6b_want"
        fi
    fi
    if [ "$_c6b_okflag" -eq 1 ]; then
        report_case "$_c6b_case" "$_c6b_rc" "PASS ($_c6b_ok runtime)"
    else
        report_case "$_c6b_case" "$_c6b_rc" "FAIL ($_c6b_ok runtime)"
    fi
    _c6b_case=$((_c6b_case + 1))
done

# ---- 26-28. negative case items reject (Task 6b) ----
# `(-1)` on u32 already rejected via the const evaluator; bare and
# parenthesized `-1` on bool are now rejected by the same `error[3062]` gate.
# All three must be rc 2 with 0 `.c` and the exact type/message span.
for _c6b_rej in \
    switch_u32_paren_neg_reject_xmod \
    switch_bool_neg_reject_xmod \
    switch_bool_paren_neg_reject_xmod; do
    _c6b_dn="c${_c6b_case}_$_c6b_rej"
    mkdir -p "$WORK/$_c6b_dn"
    set +e
    ( cd "$WORK/$_c6b_dn" && timeout 120 "$ZIG1" -ffast --dump-c89 \
        -o "$WORK/$_c6b_dn" "$ROOT/repro/mi_matrix/$_c6b_rej/main.zig" ) \
        >"$WORK/$_c6b_dn.out" 2>"$WORK/$_c6b_dn.err"
    _c6b_rc=$?
    set -e
    _c6b_okflag=1
    if [ "$_c6b_rc" -ne 2 ]; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_rej rc=$_c6b_rc want 2"
    fi
    if ! grep -q 'error\[3062\]' "$WORK/$_c6b_dn.err" 2>/dev/null; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_rej missing error[3062]"
    fi
    case "$_c6b_rej" in
        switch_u32_paren_neg_reject_xmod)
            _c6b_msg="type 'u32' cannot represent integer value '-1'" ;;
        *)
            _c6b_msg="type 'bool' cannot represent integer value '-1'" ;;
    esac
    if ! grep -qF "$_c6b_msg" "$WORK/$_c6b_dn.err" 2>/dev/null; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_rej missing message: $_c6b_msg"
    fi
    if [ -n "$(find "$WORK/$_c6b_dn" -name '*.c' -print -quit 2>/dev/null)" ]; then
        _c6b_okflag=0
        bad "case $_c6b_case: $_c6b_rej emitted .c despite reject"
    fi
    if [ "$_c6b_okflag" -eq 1 ]; then
        report_case "$_c6b_case" "$_c6b_rc" "PASS ($_c6b_rej error[3062], 0 .c)"
    else
        report_case "$_c6b_case" "$_c6b_rc" "FAIL ($_c6b_rej reject)"
    fi
    _c6b_case=$((_c6b_case + 1))
done

# ---- 29. bool case items keep true/false/0/1 accepted (including parens) ----
# The new bool-negative reject must not reject the pre-existing tolerated
# positive forms. Every function selects the 1-prong; expected stdout is the
# digit string `101111111`.
cat >"$WORK/bool_case_matrix.zig" <<'EOF'
const std = @import("std");

fn t1(b: bool) i32 { return switch (b) { true => 1, else => 0 }; }
fn t2(b: bool) i32 { return switch (b) { false => 1, else => 0 }; }
fn t3(b: bool) i32 { return switch (b) { 0 => 1, else => 0 }; }
fn t4(b: bool) i32 { return switch (b) { 1 => 1, else => 0 }; }
fn p1(b: bool) i32 { return switch (b) { (true) => 1, else => 0 }; }
fn p2(b: bool) i32 { return switch (b) { ((false)) => 1, else => 0 }; }
fn p3(b: bool) i32 { return switch (b) { (0) => 1, else => 0 }; }
fn p4(b: bool) i32 { return switch (b) { ((1)) => 1, else => 0 }; }

pub fn main() void {
    std.io.printInt(t1(true));
    std.io.printInt(t1(false));
    std.io.printInt(t2(false));
    std.io.printInt(t3(false));
    std.io.printInt(t4(true));
    std.io.printInt(p1(true));
    std.io.printInt(p2(false));
    std.io.printInt(p3(false));
    std.io.printInt(p4(true));
    std.io.writeByte('\n');
}
EOF
printf '101111111\n' >"$WORK/bool_case_matrix.expected"
_c6b_dn="c${_c6b_case}_bool_case_matrix"
mkdir -p "$WORK/$_c6b_dn"
set +e
( cd "$WORK/$_c6b_dn" && timeout 120 "$ZIG1" -ffast -o "$WORK/$_c6b_dn" \
    "$WORK/bool_case_matrix.zig" ) \
    >"$WORK/$_c6b_dn.out" 2>"$WORK/$_c6b_dn.err"
_c6b_rc=$?
set -e
_c6b_okflag=1
if [ "$_c6b_rc" -ne 0 ]; then
    _c6b_okflag=0
    bad "case $_c6b_case: bool_case_matrix emit rc=$_c6b_rc want 0"
elif ! ( cd "$WORK/$_c6b_dn" && timeout 120 sh build_target.sh linux prog ) \
    >"$WORK/$_c6b_dn.build.log" 2>&1; then
    _c6b_okflag=0
    bad "case $_c6b_case: bool_case_matrix build_target failed (see $WORK/$_c6b_dn.build.log)"
else
    set +e
    ( cd "$WORK/$_c6b_dn" && timeout 10 ./prog </dev/null ) \
        >"$WORK/$_c6b_dn.run.out" 2>"$WORK/$_c6b_dn.run.err"
    _c6b_run=$?
    set -e
    if ! cmp -s "$WORK/$_c6b_dn.run.out" "$WORK/bool_case_matrix.expected"; then
        _c6b_okflag=0
        bad "case $_c6b_case: bool_case_matrix runtime stdout mismatch (want 101111111)"
    fi
    if [ "$_c6b_run" -ne 0 ]; then
        _c6b_okflag=0
        bad "case $_c6b_case: bool_case_matrix runtime rc=$_c6b_run want 0"
    fi
fi
if [ "$_c6b_okflag" -eq 1 ]; then
    report_case "$_c6b_case" "$_c6b_rc" "PASS (bool true/false/0/1 + parens accepted)"
else
    report_case "$_c6b_case" "$_c6b_rc" "FAIL (bool positive matrix)"
fi

if [ "$fail" -eq 0 ]; then
    echo "LOWER_DEPTH GATE OK"
    exit 0
fi
echo "LOWER_DEPTH GATE FAILED" >&2
exit 1
