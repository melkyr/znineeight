#!/usr/bin/env bash
set -euo pipefail
# scripts/check_emit_support.sh [zig1]
#
# Task 4 byte-equality gate: dump a program into a fresh dir with the given zig1
# and `cmp` each emitted support file against its canonical source of truth
# (sf/src/include/* + sf/src/c_exit.c). This NEVER generates the embedded data —
# the bytes are hand-written in sf/src/emit_support.zig; this only verifies what
# the compiler emits.
#
# usage: scripts/check_emit_support.sh [path/to/zig1]
#   zig1 defaults to $ROOT/zig1 if executable.
#
# The compiler locates its std modules at <exe_dir>/lib, so pass a built zig1
# (e.g. one produced by scripts/seed/build_from_seed.sh) whose sibling lib/ holds
# the 8 std *.zig files.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/check_emit_support.sh [path/to/zig1]" >&2
        exit 1
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 1; }

DIR="$(mktemp -d "${TMPDIR:-/tmp}/check_emit_support.XXXXXX")"
trap 'rm -rf "$DIR"' EXIT

( cd "$ROOT" && timeout 120 "$ZIG1" -o "$DIR" examples/z98/hello/main.zig ) \
    || { echo "error: dump failed (zig1 '$ZIG1')" >&2; exit 1; }

fail=0
check() {
    local emitted="$1" canonical="$2"
    if cmp -s "$DIR/$emitted" "$canonical"; then
        echo "[check] emitted $emitted == $canonical"
    else
        echo "[check] FAIL emitted $emitted != $canonical" >&2
        cmp "$DIR/$emitted" "$canonical" >&2 || true
        fail=1
    fi
}

# net_prelude.h is emitted ONLY when std_net is reachable (SPECFIX). We decide
# reachability from the dump itself: net_prelude.h is expected present iff the
# dump contains a std_net_*.c module, and absent otherwise. net_prelude.h is
# not part of the byte-equality set below.
check zig_compat.h  "$ROOT/sf/src/include/zig_compat.h"
check zig_runtime.h "$ROOT/sf/src/include/zig_runtime.h"
check zig_runtime.c "$ROOT/sf/src/include/zig_runtime.c"
check zig_pal.c     "$ROOT/sf/src/include/zig_pal.c"
check c_exit.c      "$ROOT/sf/src/c_exit.c"

net_mod=0
for f in "$DIR"/std_net_*.c; do
    [ -e "$f" ] && net_mod=1
done

if [ "$net_mod" = 1 ]; then
    if [ -e "$DIR/net_prelude.h" ]; then
        echo "[check] net_prelude.h correctly present (std_net reachable)"
    else
        echo "[check] FAIL net_prelude.h missing though a std_net_*.c module was emitted" >&2
        fail=1
    fi
else
    if [ -e "$DIR/net_prelude.h" ]; then
        echo "[check] FAIL net_prelude.h emitted though no std_net module was emitted" >&2
        fail=1
    else
        echo "[check] net_prelude.h correctly absent (std_net not reachable)"
    fi
fi

[ "$fail" = 0 ] || { echo "error: emitted support files differ from canonical" >&2; exit 1; }
echo "[check] OK: 5/5 support files byte-identical to canonical"
