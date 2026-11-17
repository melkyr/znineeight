#!/bin/sh
# scripts/compiler/gate_strict_c89.sh <path/to/zig1> <entry.zig>
#
# Strict-C89 declaration-order gate. Emits the given entry with `-osw` into a
# fresh scratch dir, then runs the host gcc in C89 syntax-check mode:
#
#   gcc -std=c89 -pedantic -Werror=declaration-after-statement -fsyntax-only *.c
#
# Only `-Wdeclaration-after-statement` is promoted to an error, so pre-existing
# long-long / pointer-sign warning classes stay informational (and never fail
# the gate). `-pedantic` is likewise informational. A mixed declaration after a
# statement (e.g. the error-union `main` wrapper's `zT_main_result` emitted
# after module-init calls) fails the gate.
#
# usage: scripts/compiler/gate_strict_c89.sh /tmp/zigfix/zig1_5_clean \
#          repro/mi_matrix/main_errunion_init_xmod/main.zig

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
ENTRY="${2:-}"
[ -n "$ZIG1" ] || { echo "usage: scripts/compiler/gate_strict_c89.sh <zig1> <entry.zig>" >&2; exit 2; }
[ -n "$ENTRY" ] || { echo "usage: scripts/compiler/gate_strict_c89.sh <zig1> <entry.zig>" >&2; exit 2; }
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }
case "$ENTRY" in
    /*) ;;
    *) ENTRY="$ROOT/$ENTRY" ;;
esac
[ -f "$ENTRY" ] || { echo "error: entry '$ENTRY' not found" >&2; exit 2; }
ZIG1="$(cd "$(dirname "$ZIG1")" && pwd)/$(basename "$ZIG1")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_strict_c89.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

( cd "$ROOT" && timeout 600 "$ZIG1" -I "$ROOT/sf/src" -osw -o "$WORK" "$ENTRY" ) \
    >"$WORK/emit.log" 2>&1
rc=$?
rm -f "$WORK"/.zig1_*.tmp
if [ "$rc" -ne 0 ]; then
    echo "[strict-c89] FAIL: emission rc=$rc for $ENTRY" >&2
    sed -n '1,40p' "$WORK/emit.log" >&2
    exit 1
fi

n=0
for f in "$WORK"/*.c; do
    [ -e "$f" ] || continue
    n=$((n + 1))
done
if [ "$n" -eq 0 ]; then
    echo "[strict-c89] FAIL: no .c emitted for $ENTRY" >&2
    exit 1
fi

# POSIX sh has no arrays: pass the glob straight through.
gcc -std=c89 -pedantic -Werror=declaration-after-statement -fsyntax-only "$WORK"/*.c \
    >"$WORK/gcc.log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    if grep -q 'declaration-after-statement' "$WORK/gcc.log"; then
        echo "[strict-c89] FAIL: mixed declaration(s) in $ENTRY" >&2
    else
        echo "[strict-c89] FAIL: gcc rc=$rc for $ENTRY" >&2
    fi
    sed -n '1,80p' "$WORK/gcc.log" >&2
    exit 1
fi

echo "[strict-c89] OK: $ENTRY ($n TUs)"
exit 0
