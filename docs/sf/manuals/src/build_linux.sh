#!/bin/sh
# build_linux.sh - build the manual's Z98 example programs for Linux.
#
# The compiler is rebuilt once per session from the committed seed. Run this
# from the repository root; the relative sf/src path is required:
#
#   bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
#
# usage: sh build_linux.sh [ZIG1]
#   ZIG1  seed-built compiler (default: /tmp/manual_seed/zig1_5_clean)
#
# Every src/vol*/*.z98 is emitted into /tmp/manual_out/<name>/, compiled with
# gcc -m32 by the emitted build_target.sh, and left runnable there.
set -e

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
ZIG1=${1:-${ZIG1:-/tmp/manual_seed/zig1_5_clean}}
OUT_ROOT=${OUT_ROOT:-/tmp/manual_out}

if [ ! -x "$ZIG1" ]; then
    echo "build_linux.sh: compiler not executable: $ZIG1" >&2
    echo "build it from the repository root with:" >&2
    echo "  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed" >&2
    exit 1
fi

for prog in "$SRC_DIR"/vol*/*.z98; do
    [ -e "$prog" ] || continue
    name=$(basename "$prog" .z98)
    out="$OUT_ROOT/$name"
    rm -rf "$out"
    mkdir -p "$out"
    echo "=== $name ==="
    "$ZIG1" -o "$out" "$prog"
    ( cd "$out" && sh build_target.sh linux "$name" )
    echo "built: $out/$name"
done
