#!/usr/bin/env bash
set -uo pipefail
# scripts/compiler/gate_module_member_diag.sh [path/to/zig1]
#
# Task 3b: a missing member on a module alias must be diagnosed as
# error[3060] with Zig's wording ("no field or member function named '...'
# in module"), NOT as error[3042] ("non-value base expression in field
# access") plus warning[3023] ("module used as value expression").
#
# reject fixture: --dump-c89 rc 2, zero `.c`, exactly one error[3060]
#                 carrying "in module", and no error[3042] / warning[3023].
# ok fixture:     --dump-c89 rc 0, at least one `.c`.
#
# Exits 1 on any mismatch.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_module_member_diag.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_module_member_diag.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail=0
note() { echo "[gate_module_member_diag] $*"; }
bad()  { echo "[gate_module_member_diag] FAIL: $*" >&2; fail=1; }

note "zig1: $ZIG1"

REJECT="$ROOT/repro/mi_matrix/module_member_missing_reject_xmod/main.zig"
OK="$ROOT/repro/mi_matrix/module_member_ok_xmod/main.zig"

# ---- reject: missing module member ----
mkdir -p "$WORK/reject"
( cd "$ROOT" && timeout 120 "$ZIG1" --dump-c89 --output-dir "$WORK/reject" "$REJECT" ) \
    >"$WORK/reject.out" 2>"$WORK/reject.err"
rrc=$?

if [ "$rrc" -ne 2 ]; then
    bad "reject rc=$rrc want 2"
fi

c_count=0
while IFS= read -r _c; do
    [ -n "$_c" ] && c_count=$((c_count + 1))
done < <(find "$WORK/reject" -maxdepth 1 -type f -name '*.c' -print 2>/dev/null)
if [ "$c_count" -ne 0 ]; then
    bad "reject emitted $c_count .c want 0"
fi

err3060="$(grep -c 'error\[3060\]' "$WORK/reject.err" 2>/dev/null)"
err3060="${err3060:-0}"
if [ "$err3060" -ne 1 ]; then
    bad "reject has $err3060 error[3060] lines want exactly 1"
fi
if ! grep -qF "error[3060]: no field or member function named 'nope' in module" "$WORK/reject.err"; then
    bad "reject stderr lacks \"error[3060]: no field or member function named 'nope' in module\""
fi
if grep -q 'error\[3042\]' "$WORK/reject.err"; then
    bad "reject stderr still has error[3042]"
fi
if grep -q 'warning\[3023\]' "$WORK/reject.err"; then
    bad "reject stderr still has warning[3023]"
fi

if [ "$fail" -eq 0 ]; then
    note "reject: rc=2, 0 .c, one error[3060] 'in module', no 3042/3023"
else
    note "reject stderr:"
    sed -n '1,40p' "$WORK/reject.err" >&2
fi

# ---- ok: real module member ----
mkdir -p "$WORK/ok"
( cd "$ROOT" && timeout 120 "$ZIG1" --dump-c89 --output-dir "$WORK/ok" "$OK" ) \
    >"$WORK/ok.out" 2>"$WORK/ok.err"
orc=$?

if [ "$orc" -ne 0 ]; then
    bad "ok rc=$orc want 0"
    sed -n '1,40p' "$WORK/ok.err" >&2
fi

ok_c_count=0
while IFS= read -r _c; do
    [ -n "$_c" ] && ok_c_count=$((ok_c_count + 1))
done < <(find "$WORK/ok" -maxdepth 1 -type f -name '*.c' -print 2>/dev/null)
if [ "$ok_c_count" -lt 1 ]; then
    bad "ok emitted no .c"
fi

if [ "$fail" -eq 0 ]; then
    note "ok: rc=0, $ok_c_count .c"
    note "PASS"
    exit 0
fi
note "FAILED"
exit 1
