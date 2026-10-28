#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_builtin_names.sh
#
# Builtin name-table gate (Phase 2.5 Task 1). Extracts the `"@..."` builtin
# name string literals (whole-literal `"@ident"` form = the name-table entries;
# diagnostic texts embed their names inside longer literals and are excluded;
# bare `"@"` is excluded — the regex requires >= 1 char after `@`) from the
# three independent builtin name tables:
#   sf/src/semantic_analyzer.zig  (sema validation / arity table)
#   sf/src/lower.zig              (lowering dispatch table)
#   sf/src/comptime_eval.zig      (comptime fold table)
# and asserts (controller ruling 2026-10-28, option A):
#   1. sema == lower (exact set equality);
#   2. comptime subset-of sema (every comptime fold name exists in sema).
# exit 0 = agree; nonzero + printed diff = drift. Rationale: a builtin added to
# one table but not the others shifts intern ids, and intern-id shifts move the
# pins. This gate locks the builtin name-table completeness invariant.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_builtin_names.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_builtin_names] $*"; }
bad()  { echo "[gate_builtin_names] FAIL: $*" >&2; fail=1; }

SEMA="$ROOT/sf/src/semantic_analyzer.zig"
LOWER="$ROOT/sf/src/lower.zig"
COMPTIME="$ROOT/sf/src/comptime_eval.zig"
for f in "$SEMA" "$LOWER" "$COMPTIME"; do
    [ -f "$f" ] || { echo "error: missing source file $f" >&2; exit 2; }
done

# extract <file> -> sorted unique bare names (no quotes)
extract() {
    grep -o '"@[A-Za-z][A-Za-z0-9]*"' "$1" | sed 's/^"//; s/"$//' | sort -u
}

extract "$SEMA"    > "$WORK/sema.txt"
extract "$LOWER"   > "$WORK/lower.txt"
extract "$COMPTIME" > "$WORK/comptime.txt"

SEMA_N=$(wc -l < "$WORK/sema.txt" | tr -d ' ')
LOWER_N=$(wc -l < "$WORK/lower.txt" | tr -d ' ')
COMPTIME_N=$(wc -l < "$WORK/comptime.txt" | tr -d ' ')
note "sema names: $SEMA_N"
note "lower names: $LOWER_N"
note "comptime names: $COMPTIME_N"

# ---- 1. sema == lower (exact set equality) ----
if cmp -s "$WORK/sema.txt" "$WORK/lower.txt"; then
    note "ok sema == lower ($SEMA_N names)"
else
    bad "sema vs lower name-set drift:"
    diff "$WORK/sema.txt" "$WORK/lower.txt" >&2 || true
fi

# ---- 2. comptime subset-of sema ----
comm -23 "$WORK/comptime.txt" "$WORK/sema.txt" > "$WORK/comptime_only.txt"
if [ -s "$WORK/comptime_only.txt" ]; then
    bad "comptime name(s) missing from sema:"
    cat "$WORK/comptime_only.txt" >&2
else
    note "ok comptime subset-of sema ($COMPTIME_N of $SEMA_N)"
fi

if [ "$fail" -eq 0 ]; then
    echo "BUILTIN_NAMES GATE OK (sema=$SEMA_N lower=$LOWER_N comptime=$COMPTIME_N subset-ok)"
    exit 0
fi
echo "BUILTIN_NAMES GATE FAILED" >&2
exit 1
