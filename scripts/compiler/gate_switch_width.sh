#!/usr/bin/env bash
set -uo pipefail
# scripts/compiler/gate_switch_width.sh [path/to/zig1]
#
# Task TA detection gate (defect A): a legal Z98 `switch` on a 64-bit integer
# is emitted as a C `switch` whose controlling expression is a 64-bit temp.
# OpenWatcom 1.9 rejects that (`E1078: Invalid type for switch expression`).
#
# For each repro below:
#   1. `zig1 --dump-c89 <entry>` into a fresh temp dir (single-file emission);
#   2. parse every emitted `switch (<expr>)` line and resolve <expr> to the
#      nearest preceding declaration of that name;
#   3. FAIL if any resolved controlling temp is declared as a 64-bit C type
#      (`*_u64`, `*_i64`, `__int64`, `unsigned __int64`, `long long`).
#
# The gate is RED while the defect is present. A repro whose emitted C still
# contains an unresolvable `switch` FAILS; a repro with no `switch` at all
# PASSES (the 64-bit condition was lowered to an if/else chain).
#
# usage: scripts/compiler/gate_switch_width.sh <path/to/zig1>

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_switch_width.sh <path/to/zig1>" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_switch_width.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[switch-width] $*"; }
bad()  { echo "[switch-width] FAIL: $*" >&2; fail=1; }

REPROS=(
    repro/mi_matrix/switch_u64_ok_xmod
    repro/mi_matrix/switch_i64_ok_xmod
)

# PARSE_AWK emits one line per emitted switch:
#   SW64 <line> <expr> <decl-line> <type>
#   SWOK <line> <expr> <decl-line> <type>
#   SWUNRESOLVED <line> <expr>
# and prints NOSWITCH (exit 0) when the file has no switch at all; it exits 2
# when switches exist but none resolve.
read -r -d '' PARSE_AWK <<'AWK'
function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}
{
    line = $0
    # Declaration: <type> <name> ;  (nearest preceding declaration wins).
    if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_ \t\*]*[ \t]+\*?[A-Za-z_][A-Za-z0-9_]*[ \t]*;[ \t]*$/)) {
        s = trim(line)
        sub(/[ \t]*;.*$/, "", s)
        n = split(s, parts, /[ \t]+/)
        name = parts[n]
        gsub(/^\*+/, "", name)
        if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
            typ = s
            sub(/[ \t]*\*?[ \t]*[A-Za-z_][A-Za-z0-9_]*$/, "", typ)
            typ = trim(typ)
            type[name] = typ
            decl_line[name] = NR
        }
    }
    # Switch: `switch (<expr>) {`
    if (match(line, /^[ \t]*switch[ \t]*\(/)) {
        seen++
        rest = line
        sub(/^[^(]*\(/, "", rest)
        # Drop the final closing paren (and optional brace).
        sub(/\)[ \t]*\{[ \t]*$/, "", rest)
        sub(/\)[ \t]*$/, "", rest)
        expr = trim(rest)
        id = expr
        if (match(id, /[A-Za-z_][A-Za-z0-9_]*[ \t]*$/)) {
            id = trim(substr(id, RSTART, RLENGTH))
        } else {
            id = ""
        }
        if (id != "" && (id in type)) {
            is64 = 0
            if (type[id] ~ /(^|[^A-Za-z0-9])(u64|i64)$/) is64 = 1
            if (type[id] ~ /(^|[^A-Za-z0-9])__int64([^A-Za-z0-9]|$)/) is64 = 1
            if (type[id] ~ /(^|[^A-Za-z0-9])unsigned[ \t]+__int64([^A-Za-z0-9]|$)/) is64 = 1
            if (type[id] ~ /(^|[^A-Za-z0-9])long[ \t]+long([^A-Za-z0-9]|$)/) is64 = 1
            if (is64)
                printf("SW64 %d %s %d [%s]\n", NR, expr, decl_line[id], type[id])
            else
                printf("SWOK %d %s %d [%s]\n", NR, expr, decl_line[id], type[id])
            resolved++
        } else {
            printf("SWUNRESOLVED %d %s\n", NR, expr)
        }
    }
}
END {
    if (seen == 0) { print "NOSWITCH"; exit 0 }
    if (resolved == 0) exit 2
    exit 0
}
AWK

check_repro() {
    local rel="$1"
    local tag out rc hits
    tag="$(basename "$rel")"
    out="$WORK/$tag"
    mkdir -p "$out"
    ( cd "$ROOT" && timeout 600 "$ZIG1" --dump-c89 "$rel/main.zig" ) \
        >"$out/emit.c" 2>"$out/emit.err"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$tag: --dump-c89 rc=$rc (see $out/emit.err)"
        return
    fi
    if [ ! -s "$out/emit.c" ]; then
        bad "$tag: --dump-c89 emitted no C"
        return
    fi
    if ! awk "$PARSE_AWK" "$out/emit.c" >"$out/switches.txt"; then
        bad "$tag: emitted C has no resolvable 'switch' controlling expression"
        sed -n '1,20p' "$out/switches.txt" >&2
        return
    fi
    if grep -q '^NOSWITCH$' "$out/switches.txt"; then
        note "$tag: OK (no C switch; 64-bit condition lowered to if/else)"
        return
    fi
    hits="$(grep -c '^SW64 ' "$out/switches.txt" || true)"
    if [ "${hits:-0}" -gt 0 ]; then
        bad "$tag: $hits 64-bit C switch controlling expression(s):"
        sed -n 's/^SW64 /  /p' "$out/switches.txt" >&2
    else
        note "$tag: OK (no 64-bit switch controlling expression)"
    fi
}

note "zig1: $ZIG1"
for rel in "${REPROS[@]}"; do
    check_repro "$rel"
done

if [ "$fail" -ne 0 ]; then
    echo "SWITCH_WIDTH GATE FAILED" >&2
    exit 1
fi
echo "SWITCH_WIDTH GATE OK"
exit 0
