#!/usr/bin/env bash
# default_lib_lookup.sh — win32 RED/GREEN gate for the default-lib-path lookup
# (Task 5B, AMENDMENT 1; the F half of the Task 5A/5B compiler I/F pair).
#
# Usage:
#   default_lib_lookup.sh [<seed_tgz>] [<workdir>]
#
#   <seed_tgz>  seed archive (default release/seed/zig1-seed.tgz) OR an unpacked
#               zig1-seed/ dir. Supplies the ARCHIVED compiler C (below).
#   <workdir>   scratch dir (default a fresh mktemp -d); WIPED and rebuilt
#
# What it checks: the compiler's DEFAULT standard-library lookup `<exe_dir>/lib`
# is found on win32. `phase_ImportResolution` (`sf/src/main.zig`) guards that
# path with a directory probe (`pal.dirExists` -> `pal_dir_exists` ->
# GetFileAttributesA on win32 / stat on POSIX). Before Task 5B the guard was
# `pal.fileExists` (`fopen(path,"rb")`), and `fopen` on a DIRECTORY fails on
# win32 (msvcrt), so `<exe_dir>/lib` was never added and a bare
# `@import("std")` failed `error[3048]` unless the user passed `-I lib`. On
# Linux glibc `fopen`s a directory, so the Linux gates cannot discriminate the
# fix; this script is the win32 RED/GREEN gate.
#
# It builds the win32 compiler TWICE and reports both outcomes:
#   ARCHIVED side — from the seed archive's OWN `gen/` + `runtime/` C (recipe 2).
#     Which guard the archived C carries is read off the archived
#     `gen/main_*.c`: a `_fileExists` call is the PRE-FIX default-lib guard
#     (expect RED), its absence means the post-fix `dirExists` guard (GREEN).
#     The observed outcome is asserted against that. Passing a pre-fix seed
#     (e.g. the v63 archive recoverable from git history) makes this side a
#     real RED; with the post-fix committed seed it correctly reports GREEN.
#   FORWARD side — from the CURRENT `sf/src` (`build_from_seed.sh` dumps the
#     current source -> a self-contained `gen/`), always asserted GREEN. This is
#     the actual regression gate for the current source.
# Both sides run the same `@import("std")` program from the exe's own directory
# with NO `-I`; the exe dir is the CWD so GetModuleFileNameA resolves
# `<exe_dir>`. A green run must have rc=0, no `error[3048]`, and a `std_io_*.c`
# in the emitted closure; a red run must have rc!=0, `error[3048]`, and 0 `.c`.
#
# Prints machine-readable lines:
#   ARCHIVED_GUARD=fileExists|dirExists
#   ARCHIVED=RED|GREEN
#   FORWARD=GREEN
#   DEFAULT_LIB_LOOKUP=OK | FAIL:<why>
# Exit status mirrors the verdict. Every sub-run is timeout-guarded (dump 120s).
#
# Env overrides: ROOT, CROSS_GCC, WINE, WINEPREFIX, TIMEOUT.
set -u

ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
CROSS_GCC=${CROSS_GCC:-i686-w64-mingw32-gcc}
WINE=${WINE:-wine}
WINEPREFIX=${WINEPREFIX:-$HOME/.wine}
TIMEOUT=${TIMEOUT:-120}

SEED=${1:-$ROOT/release/seed/zig1-seed.tgz}
WORK=${2:-$(mktemp -d /tmp/default_lib_lookup.XXXXXX)}

verdict() { echo "DEFAULT_LIB_LOOKUP=$1"; exit 0; }
fail()    { echo "DEFAULT_LIB_LOOKUP=FAIL:$1"; exit 1; }

[ -f "$SEED" ] || [ -d "$SEED" ] || fail "seed-not-found:$SEED"
command -v "$CROSS_GCC" >/dev/null 2>&1 || fail "no-mingw:$CROSS_GCC"
command -v "$WINE" >/dev/null 2>&1 || fail "no-wine"

rm -rf "$WORK"
mkdir -p "$WORK"

cat >"$WORK/std_hello.zig" <<'EOF'
const std = @import("std");
pub fn main() void {
    std.io.print("hi\n");
}
EOF

# ---- resolve the seed to a zig1-seed/ dir (the ARCHIVED compiler C) -----------
SEEDDIR=""
if [ -d "$SEED" ]; then
    if [ -d "$SEED/zig1-seed/gen" ]; then SEEDDIR="$SEED/zig1-seed"
    elif [ -d "$SEED/gen" ]; then SEEDDIR="$SEED"; fi
elif [ -f "$SEED" ]; then
    mkdir -p "$WORK/seedunpack"
    tar -xzf "$SEED" -C "$WORK/seedunpack" || fail "seed-unpack"
    if [ -d "$WORK/seedunpack/zig1-seed/gen" ]; then SEEDDIR="$WORK/seedunpack/zig1-seed"
    elif [ -d "$WORK/seedunpack/gen" ]; then SEEDDIR="$WORK/seedunpack"; fi
fi
[ -n "$SEEDDIR" ] || fail "cannot-resolve-seed"
# canonical archive layout puts c_exit.c at the zig1-seed/ top level
C_EXIT="$SEEDDIR/c_exit.c"
[ -f "$C_EXIT" ] || C_EXIT="$SEEDDIR/runtime/c_exit.c"

# ---- win32 build helper: <gen_dir> <runtime_dir|-> <out_dir> <label> ----------
# A self-contained gen dir (carries the emitted runtime support) -> -I gen, link
# the emitted objects only. A module-only gen dir (an archive) -> -I runtime and
# append the runtime trio (recipe 2).
win32_build() {
    local gendir="$1" rtdir="$2" outdir="$3" label="$4"
    mkdir -p "$outdir"
    if [ -f "$gendir/zig_runtime.c" ]; then
        (
            cd "$outdir" &&
            "$CROSS_GCC" -std=c89 -m32 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
                -Wno-implicit-function-declaration -I "$gendir" -c "$gendir"/*.c &&
            "$CROSS_GCC" -m32 -O0 ./*.o -lwsock32 -o zig1.exe
        ) >"$WORK/${label}_cc.log" 2>&1
    else
        (
            cd "$outdir" &&
            "$CROSS_GCC" -std=c89 -m32 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
                -Wno-implicit-function-declaration -I "$rtdir" \
                -c "$gendir"/*.c "$rtdir"/zig_runtime.c "$rtdir"/zig_pal.c "$C_EXIT" &&
            "$CROSS_GCC" -m32 -O0 ./*.o -lwsock32 -o zig1.exe
        ) >"$WORK/${label}_cc.log" 2>&1
    fi
    [ -x "$outdir/zig1.exe" ] || { tail -20 "$WORK/${label}_cc.log"; return 1; }
    return 0
}

# ---- run helper: <exedir> <label>; sets RUN_RC / RUN_NC / RUN_IO --------------
run_case() {
    local exedir="$1" label="$2"
    mkdir -p "$exedir/out"
    (
        cd "$exedir" &&
        WINEDEBUG=-all WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
            timeout "$TIMEOUT" "$WINE" zig1.exe -osw -o out "$WORK/std_hello.zig"
    ) >"$WORK/${label}_run.log" 2>&1
    RUN_RC=$?
    RUN_NC=$(ls "$exedir/out"/*.c 2>/dev/null | wc -l)
    RUN_IO=0
    ls "$exedir/out"/std_io_*.c >/dev/null 2>&1 && RUN_IO=1
    return 0
}

# ---- ARCHIVED side: the seed's own gen/ + runtime/ ----------------------------
win32_build "$SEEDDIR/gen" "$SEEDDIR/runtime" "$WORK/arch" arch || fail "archived-win32-build"
cp -r "$SEEDDIR/lib" "$WORK/arch/lib"
run_case "$WORK/arch" arch
if [ "$RUN_RC" -ne 0 ] && grep -q 'error\[3048\]' "$WORK/arch_run.log" && [ "$RUN_NC" -eq 0 ]; then
    ARCHIVED=RED
elif [ "$RUN_RC" -eq 0 ] && ! grep -q 'error\[3048\]' "$WORK/arch_run.log" && [ "$RUN_IO" -eq 1 ]; then
    ARCHIVED=GREEN
else
    ARCHIVED=UNEXPECTED
fi

ARCHIVED_GUARD=dirExists
if grep -q '_fileExists' "$SEEDDIR"/gen/main_*.c 2>/dev/null; then ARCHIVED_GUARD=fileExists; fi
if [ "$ARCHIVED_GUARD" = fileExists ]; then WANT_ARCHIVED=RED; else WANT_ARCHIVED=GREEN; fi

echo "ARCHIVED_GUARD=$ARCHIVED_GUARD"
echo "ARCHIVED=$ARCHIVED"
[ "$ARCHIVED" = "$WANT_ARCHIVED" ] || fail "archived-$ARCHIVED-want-$WANT_ARCHIVED"

# ---- FORWARD side: the CURRENT sf/src via the seed (build_from_seed dump) -----
bash "$ROOT/scripts/seed/build_from_seed.sh" "$SEED" "$WORK/forward" \
    >"$WORK/forward.log" 2>&1 || { tail -20 "$WORK/forward.log"; fail "forward-rebuild"; }
[ -f "$WORK/forward/gen/zig_runtime.c" ] || fail "forward-gen-not-self-contained"
win32_build "$WORK/forward/gen" "" "$WORK/fwd" fwd || fail "forward-win32-build"
cp -r "$WORK/forward/lib" "$WORK/fwd/lib"
run_case "$WORK/fwd" fwd
if [ "$RUN_RC" -eq 0 ] && ! grep -q 'error\[3048\]' "$WORK/fwd_run.log" && [ "$RUN_IO" -eq 1 ]; then
    FORWARD=GREEN
else
    FORWARD=UNEXPECTED
fi
echo "FORWARD=$FORWARD"
[ "$FORWARD" = GREEN ] || fail "forward-$FORWARD"

verdict OK

