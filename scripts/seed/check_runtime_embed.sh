#!/usr/bin/env bash
set -euo pipefail
# check_runtime_embed.sh - byte-equality gate for sf/src/runtime_embed.zig.
#
# Task 4 (spec 5.3): the compiler carries the canonical runtime/platform bytes
# as Z98 string constants. This gate fails on drift:
#   1. regenerate the constants from sf/src/include/* + sf/src/c_exit.c and
#      assert the committed sf/src/runtime_embed.zig is byte-identical;
#   2. if a zig1 binary is given, dump examples/z98/hello and cmp every emitted
#      support file against its canonical source.
#
# usage: scripts/seed/check_runtime_embed.sh [zig1_binary]

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d /tmp/check-runtime-embed.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/scripts/seed/gen_runtime_embed.sh" "$TMP/runtime_embed.zig" >/dev/null
if cmp -s "$TMP/runtime_embed.zig" "$ROOT/sf/src/runtime_embed.zig"; then
    echo "[check] embedded constants == canonical files (runtime_embed.zig current)"
else
    echo "error: sf/src/runtime_embed.zig is stale vs sf/src/include/* + sf/src/c_exit.c" >&2
    echo "       rerun scripts/seed/gen_runtime_embed.sh and commit the result" >&2
    exit 1
fi

if [ "$#" -ge 1 ]; then
    ZIG="$1"
    mkdir -p "$TMP/em"
    ( cd "$ROOT" && timeout 120 "$ZIG" -o "$TMP/em" examples/z98/hello/main.zig ) >/dev/null
    for pair in \
        "zig_compat.h:sf/src/include/zig_compat.h" \
        "zig_runtime.h:sf/src/include/zig_runtime.h" \
        "net_prelude.h:sf/src/include/net_prelude.h" \
        "zig_runtime.c:sf/src/include/zig_runtime.c" \
        "zig_pal.c:sf/src/include/zig_pal.c" \
        "c_exit.c:sf/src/c_exit.c"; do
        if cmp -s "$TMP/em/${pair%%:*}" "$ROOT/${pair##*:}"; then
            echo "[check] emitted ${pair%%:*} == ${pair##*:}"
        else
            echo "error: emitted ${pair%%:*} != ${pair##*:}" >&2
            exit 1
        fi
    done
    echo "[check] emitted support files == canonical files (zig1 self-contained)"
fi
