#!/usr/bin/env bash
set -euo pipefail
# usage: build_zig1_5.sh [compiler]
# Self-emission dump engine defaults to /tmp/fx_subfolder/zig1 (legacy
# reference). Env COMPILER=... or $1 overrides it (e.g. a seed/rebuilt zig1 per
# the seed model: scripts/seed/build_from_seed.sh). Default output
# (/tmp/zig1_5/{zig1_5_asan,zig1_5_clean}) is byte-unchanged.
COMPILER="${COMPILER:-${1:-/tmp/fx_subfolder/zig1}}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=/tmp/zig1_5
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/lib"
cp "$ROOT"/sf/src/std.zig "$ROOT"/sf/src/std_io.zig "$ROOT"/sf/src/std_arena.zig "$ROOT"/sf/src/std_net.zig "$OUT/lib/"
cd "$ROOT"
timeout 120 "$COMPILER" --dump-c89 --output-dir "$OUT/gen" sf/src/main.zig
# canonical multi-module recipe (QUICK_REF §Multi-Module Build): compile inside DIR, link zig_runtime.c + zig_pal.c.
# Task 4+ dump dirs are self-contained (they now carry zig_runtime.c/zig_pal.c/
# c_exit.c): compile with -I . and link ONLY the emitted objects. Legacy
# (pre-Task-4) dirs keep the repo-include + appended repo trio recipe.
cd "$OUT/gen"
if [ -f "$OUT/gen/zig_runtime.c" ]; then
    gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
        -I . -c *.c
    gcc -m32 -O0 -fsanitize=address *.o -o "$OUT/zig1_5_asan"
    gcc -m32 -O0 *.o -o "$OUT/zig1_5_clean"
else
    gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
        -I "$ROOT/sf/src/include" -c *.c
    gcc -m32 -O0 -fsanitize=address *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" "$ROOT/sf/src/c_exit.c" \
        -o "$OUT/zig1_5_asan"
    gcc -m32 -O0 *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" "$ROOT/sf/src/c_exit.c" \
        -o "$OUT/zig1_5_clean"
fi
echo "=== [zig1_5] Done: $OUT ==="
