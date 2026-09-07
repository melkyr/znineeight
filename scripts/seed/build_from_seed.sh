#!/usr/bin/env bash
set -euo pipefail
# usage:
#   scripts/seed/build_from_seed.sh <seed> <out_dir>
#   scripts/seed/build_from_seed.sh --reconstruct-only <seed> <out_dir>
#
# Rebuild zig1 from the CURRENT sf/src using a bootstrap seed (Task-1/2 recipe
# set verbatim; spec: docs/superpowers/specs/2026-09-07-seed-bootstrap-
# migration-design.md). <seed> is the committed seed archive
# (release/seed/zig1-seed.tgz) OR an unpacked zig1-seed/ directory (the dir
# itself, or a dir containing it).
#
# Default mode (canonical recipe, repo include path):
#   seed zig1 --dump-c89 --output-dir <out>/gen sf/src/main.zig
#     (run from the REPO ROOT with the RELATIVE sf/src/main.zig path — module
#     basename-hash tokens depend on the resolved source path, so the dump MUST
#     mirror build_zig1_5.sh exactly to reproduce the fixed point)
#   cd <out>/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long
#     -Wno-pointer-sign -Wno-implicit-function-declaration
#     -I <repo>/sf/src/include -c *.c
#   gcc -m32 -O0 *.o <repo>/sf/src/include/zig_runtime.c
#     <repo>/sf/src/include/zig_pal.c <repo>/sf/src/c_exit.c
#     -o <out>/zig1_5_clean
#   std lib: 4 std .zig copied into <out>/lib/
# Two-hop fixed-point closure is verified: <out>/zig1_5_clean (hop1) dumps
# sf/src/main.zig again -> gcc -> hop2 binary; md5(hop1) must equal
# md5(hop2) (== recorded fixed point when sf/src matches the seed's era; both
# md5s are printed). Set FIXED_POINT_MD5=<md5> to additionally gate on a known
# fixed point.
#
# If the seed binary is missing, the seed compiler is first rebuilt from the
# seed's own C (self-contained fallback: gcc -c -I <seed>/runtime over
# gen/*.c; link <seed>/runtime/zig_runtime.c + <seed>/runtime/zig_pal.c +
# <seed>/c_exit.c) and that reconstructed compiler is used as the dump engine.
#
# --reconstruct-only: gcc-of-C only — rebuild the seed compiler from the seed's
# own C and write <out>/zig1_5_clean (no sf/src dump; the Task-1/4.2 fallback
# recipe).

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

RECONSTRUCT_ONLY=0
if [ "${1:-}" = "--reconstruct-only" ]; then RECONSTRUCT_ONLY=1; shift; fi
[ "$#" -eq 2 ] || die "usage: build_from_seed.sh [--reconstruct-only] <seed> <out_dir>"
SEED_IN="$1"
OUT="$2"

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/lib"

# --- resolve <seed> to a zig1-seed/ dir (tgz unpacked into <out>/_unpack) ---
# A seed dir is recognized structurally (gen/ present) so the missing-binary
# gcc-of-C fallback resolves; an executable zig1 is NOT required at this stage.
seed_dir_ok() {
    [ -d "$1/gen" ] && ls "$1"/gen/*.c >/dev/null 2>&1 && \
        { [ -x "$1/zig1" ] || [ -f "$1/runtime/zig_runtime.c" ]; }
}
SEED=
if seed_dir_ok "$SEED_IN"; then
    SEED="$SEED_IN"
elif [ -d "$SEED_IN/zig1-seed" ] && seed_dir_ok "$SEED_IN/zig1-seed"; then
    SEED="$SEED_IN/zig1-seed"
elif [ -f "$SEED_IN" ]; then
    mkdir -p "$OUT/_unpack"
    tar -xzf "$SEED_IN" -C "$OUT/_unpack"
    if seed_dir_ok "$OUT/_unpack/zig1-seed"; then
        SEED="$OUT/_unpack/zig1-seed"
    elif seed_dir_ok "$OUT/_unpack"; then
        SEED="$OUT/_unpack"
    fi
fi
[ -n "$SEED" ] || die "cannot resolve a seed from '$SEED_IN' (want zig1-seed.tgz, a zig1-seed/ dir, or a dir containing one)"
[ -d "$SEED/gen" ] || die "seed dir '$SEED' has no gen/"

# --- canonical one-hop: dump current sf/src -> gcc -c -> link ---
build_hop() {
    local compiler="$1" dumpdir="$2" binout="$3"
    mkdir -p "$dumpdir"
    ( cd "$ROOT" && timeout 120 "$compiler" --dump-c89 --output-dir "$dumpdir" sf/src/main.zig ) \
        || die "self-emission dump failed (compiler '$compiler')"
    ( cd "$dumpdir" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
        -Wno-implicit-function-declaration -I "$ROOT/sf/src/include" -c *.c ) \
        || die "gcc -c failed (hop dir '$dumpdir')"
    ( cd "$dumpdir" && gcc -m32 -O0 *.o "$ROOT/sf/src/include/zig_runtime.c" \
        "$ROOT/sf/src/include/zig_pal.c" "$ROOT/sf/src/c_exit.c" -o "$binout" ) \
        || die "gcc link failed (hop dir '$dumpdir')"
}

# --- self-contained fallback: rebuild the seed compiler from its own C ---
reconstruct_seed() {
    local outbin="$1"
    [ -d "$SEED/runtime" ] || die "seed dir '$SEED' has no runtime/"
    [ -f "$SEED/runtime/zig_runtime.c" ] || die "seed dir '$SEED' has no runtime/zig_runtime.c"
    [ -f "$SEED/runtime/zig_pal.c" ] || die "seed dir '$SEED' has no runtime/zig_pal.c"
    [ -f "$SEED/c_exit.c" ] || die "seed dir '$SEED' has no top-level c_exit.c"
    echo "[seed] rebuilding seed compiler from its own C (self-contained, -I <seed>/runtime)"
    rm -rf "$OUT/rec"
    mkdir -p "$OUT/rec"
    cp "$SEED"/gen/*.c "$SEED"/gen/*.h "$OUT/rec/"
    ( cd "$OUT/rec" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
        -Wno-implicit-function-declaration -I "$SEED/runtime" -c *.c ) \
        || die "reconstruct gcc -c failed"
    ( cd "$OUT/rec" && gcc -m32 -O0 *.o "$SEED/runtime/zig_runtime.c" \
        "$SEED/runtime/zig_pal.c" "$SEED/c_exit.c" -o "$outbin" ) \
        || die "reconstruct gcc link failed"
    echo "[seed] reconstructed binary md5: $(md5sum "$outbin" | cut -d' ' -f1)"
}

if [ "$RECONSTRUCT_ONLY" = 1 ]; then
    reconstruct_seed "$OUT/zig1_5_clean"
    echo "=== [seed] Done: $OUT ==="
    exit 0
fi

DUMP_COMPILER="$SEED/zig1"
if [ ! -x "$DUMP_COMPILER" ]; then
    echo "[seed] seed binary missing — falling back to gcc-of-C reconstruction"
    reconstruct_seed "$OUT/zig1_seed_rebuilt"
    DUMP_COMPILER="$OUT/zig1_seed_rebuilt"
fi

# std lib for the produced compiler (binary-relative lib/)
cp "$ROOT"/sf/src/std.zig "$ROOT"/sf/src/std_io.zig "$ROOT"/sf/src/std_arena.zig "$ROOT"/sf/src/std_net.zig "$OUT/lib/"

build_hop "$DUMP_COMPILER" "$OUT/gen" "$OUT/zig1_5_clean"
HOP1_MD5=$(md5sum "$OUT/zig1_5_clean" | cut -d' ' -f1)
echo "[seed] hop1 binary md5: $HOP1_MD5"

build_hop "$OUT/zig1_5_clean" "$OUT/hop2" "$OUT/hop2/zig1_hop2"
HOP2_MD5=$(md5sum "$OUT/hop2/zig1_hop2" | cut -d' ' -f1)
echo "[seed] hop2 binary md5: $HOP2_MD5"

if [ "$HOP1_MD5" = "$HOP2_MD5" ]; then
    echo "[seed] two-hop closure OK: hop1 == hop2 == $HOP1_MD5"
else
    die "two-hop closure FAILED: hop1 '$HOP1_MD5' != hop2 '$HOP2_MD5'"
fi
if [ -n "${FIXED_POINT_MD5:-}" ]; then
    [ "$HOP1_MD5" = "$FIXED_POINT_MD5" ] \
        && echo "[seed] recorded fixed point OK: $HOP1_MD5" \
        || die "fixed-point mismatch: got '$HOP1_MD5', want '$FIXED_POINT_MD5'"
fi

echo "=== [seed] Done: $OUT ==="
