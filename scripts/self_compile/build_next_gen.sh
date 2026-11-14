#!/usr/bin/env bash
set -euo pipefail
# usage: build_next_gen.sh <compiler> <out_dir>
# <compiler> = the dump engine (zig0-built reference, a seed zig1, or a
# build_from_seed.sh output). Canonical recipe: full flag set incl -Wall + link
# trio zig_runtime.c/zig_pal.c/c_exit.c (matches build_zig1_5.sh / seed model).
COMPILER="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/lib"
cp "$ROOT"/sf/src/std.zig "$ROOT"/sf/src/std_io.zig "$ROOT"/sf/src/std_arena.zig "$ROOT"/sf/src/std_net.zig "$OUT/lib/"
cd "$ROOT"
timeout 120 "$COMPILER" -ffast --dump-c89 --output-dir "$OUT/gen" sf/src/main.zig
# Task 4+ dump dirs are self-contained (they carry zig_runtime.c/zig_pal.c/
# c_exit.c): compile with -I . and link ONLY the emitted objects; legacy
# (pre-Task-4) dirs keep the repo-include + appended repo trio recipe.
cd "$OUT/gen"
if [ -f "$OUT/gen/zig_runtime.c" ]; then
    gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
        -I . -c *.c
    gcc -m32 -O0 *.o -o "$OUT/zig1_5_clean"
else
    gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
        -I "$ROOT/sf/src/include" -c *.c
    gcc -m32 -O0 *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" "$ROOT/sf/src/c_exit.c" \
        -o "$OUT/zig1_5_clean"
fi
echo "=== [next-gen] Done: $OUT ==="
