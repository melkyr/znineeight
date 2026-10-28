#!/usr/bin/env bash
set -euo pipefail
# scripts/gen_emit_support.sh <built-zig1>
#
# Refresh the canonical runtime support sources from the compiler's own emitted
# `-osw` output. `sf/src/emit_support.zig` is the ONLY hand-edited source; the
# files copied here are generated snapshots and must never be hand-edited.
#
# Mapping (identical to scripts/check_emit_support.sh):
#   emitted zig_compat.h      -> sf/src/include/zig_compat.h
#   emitted zig_runtime.h     -> sf/src/include/zig_runtime.h
#   emitted zig_runtime.c     -> sf/src/include/zig_runtime.c
#   emitted zig_pal.c         -> sf/src/include/zig_pal.c
#   emitted zig_nocrt.c       -> sf/src/include/zig_nocrt.c
#   emitted c_exit.c          -> sf/src/c_exit.c
#   emitted net_prelude.h     -> sf/src/include/net_prelude.h
#   emitted std_os_prelude.h  -> sf/src/include/std_os_prelude.h
#   emitted std_time_prelude.h-> sf/src/include/std_time_prelude.h
#
# The compiler's own sf/src/main.zig exercises the core support; the three
# conditional preludes are emitted only for programs that reach their module, so
# one small fixture per prelude supplies them. The copy is byte-for-byte and
# uses no generated timestamps, so repeated runs are deterministic.
#
# usage: scripts/gen_emit_support.sh <path/to/zig1>
# The compiler locates lib/ beside the executable (pass a built zig1_5_clean).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG1="${1:-}"
[ -n "$ZIG1" ] || { echo "usage: scripts/gen_emit_support.sh <path/to/zig1>" >&2; exit 1; }
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 1; }
ZIG1="$(cd "$(dirname "$ZIG1")" && pwd)/$(basename "$ZIG1")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gen_emit_support.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

probe() {
    local label="$1" entry="$2"
    mkdir -p "$WORK/$label"
    ( cd "$ROOT" && timeout 300 "$ZIG1" -osw -o "$WORK/$label" "$entry" ) \
        || { echo "error: probe emission failed ($label: $entry)" >&2; exit 1; }
    rm -f "$WORK/$label"/.zig1_*.tmp
}

# Core support: the compiler's own Windows-target self-emission.
probe main sf/src/main.zig
# Conditional preludes: one reachable fixture each.
probe net  repro/mi_matrix/net_bind_startup_xmod/main.zig
probe os   repro/mi_matrix/stdlib_os_cwd_xmod/main.zig
probe time repro/mi_matrix/stdlib_time_monotonic_xmod/main.zig

copy_one() {
    local emitted="$1" canonical="$2"
    [ -f "$emitted" ] || { echo "error: expected emitted support file missing: $emitted" >&2; exit 1; }
    cp "$emitted" "$canonical"
    echo "[gen] $emitted -> $canonical"
}

copy_one "$WORK/main/zig_compat.h"  "$ROOT/sf/src/include/zig_compat.h"
copy_one "$WORK/main/zig_runtime.h" "$ROOT/sf/src/include/zig_runtime.h"
copy_one "$WORK/main/zig_runtime.c" "$ROOT/sf/src/include/zig_runtime.c"
copy_one "$WORK/main/zig_pal.c"     "$ROOT/sf/src/include/zig_pal.c"
copy_one "$WORK/main/zig_nocrt.c"   "$ROOT/sf/src/include/zig_nocrt.c"
copy_one "$WORK/main/c_exit.c"      "$ROOT/sf/src/c_exit.c"
copy_one "$WORK/net/net_prelude.h"  "$ROOT/sf/src/include/net_prelude.h"
copy_one "$WORK/os/std_os_prelude.h" "$ROOT/sf/src/include/std_os_prelude.h"
copy_one "$WORK/time/std_time_prelude.h" "$ROOT/sf/src/include/std_time_prelude.h"

echo "[gen] canonical runtime support refreshed from $ZIG1"
