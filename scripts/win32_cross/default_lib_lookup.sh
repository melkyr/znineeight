#!/usr/bin/env bash
# default_lib_lookup.sh — win32 regression gate for the default-lib-path lookup
# (Task 5B, AMENDMENT 1; the F half of the Task 5A/5B compiler I/F pair).
#
# Usage:
#   default_lib_lookup.sh [<seed_tgz>] [<workdir>]
#
#   <seed_tgz>  committed seed archive (default release/seed/zig1-seed.tgz)
#   <workdir>   scratch dir (default a fresh mktemp -d); WIPED and rebuilt
#
# What it proves: the compiler's DEFAULT standard-library lookup `<exe_dir>/lib`
# is found on win32. `phase_ImportResolution` (`sf/src/main.zig`) guards that
# path with a directory probe (`pal.dirExists` -> `pal_dir_exists` ->
# GetFileAttributesA on win32 / stat on POSIX). Before Task 5B the guard was
# `pal.fileExists` (`fopen(path,"rb")`), and `fopen` on a DIRECTORY fails on
# win32 (msvcrt), so `<exe_dir>/lib` was never added and a bare
# `@import("std")` failed `error[3048]` unless the user passed `-I lib`. On
# Linux glibc `fopen`s a directory, so the Linux gates cannot discriminate the
# fix — this script is the only real RED/GREEN gate.
#
# Pipeline:
#   1. `scripts/seed/build_from_seed.sh <seed_tgz> <workdir>/seed` — dumps the
#      CURRENT sf/src with the committed seed and gcc-links the Linux fixed
#      point. `<workdir>/seed/gen` is the compiler-under-test's self-emission
#      C89 module set (self-contained: it carries the emitted runtime support).
#   2. mingw-compile `<workdir>/seed/gen/*.c` (-I .) and link `-lwsock32` ->
#      `<workdir>/w32/zig1.exe` (the win32 build of the compiler under test).
#   3. Copy `<workdir>/seed/lib` (the 29 std .zig) beside the exe.
#   4. Run a `@import("std")` program from the exe's own directory with NO `-I`:
#        timeout 120 wine zig1.exe -osw -o out <hello.zig>
#      (the exe dir is the CWD so GetModuleFileNameA resolves `<exe_dir>`).
#   5. Assert rc=0, no `error[3048]`, and the emitted `.c` closure contains a
#      `std_io_*.c` module.
#
# RED evidence (pre-fix, recorded in task-5B-report.md): the same pipeline over
# the seed's OWN pre-fix `gen/` gives `error[3048]: could not resolve imported
# file 'std'`, rc=2, 0 emitted `.c`.
#
# Prints one machine-readable verdict line:  DEFAULT_LIB_LOOKUP=OK | FAIL:<why>
# Exit status mirrors it. Every sub-run is timeout-guarded (dump 120s).
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

[ -f "$SEED" ] || fail "seed-not-found:$SEED"
command -v "$CROSS_GCC" >/dev/null 2>&1 || fail "no-mingw:$CROSS_GCC"
command -v "$WINE" >/dev/null 2>&1 || fail "no-wine"

rm -rf "$WORK"
mkdir -p "$WORK"

# ---- 1. seed rebuild: compiler-under-test's self-emission C + sibling lib/ ----
bash "$ROOT/scripts/seed/build_from_seed.sh" "$SEED" "$WORK/seed" \
    >"$WORK/seed.log" 2>&1 || { tail -20 "$WORK/seed.log"; fail "seed-rebuild"; }
[ -f "$WORK/seed/gen/zig_runtime.c" ] || fail "seed-gen-not-self-contained"
[ -d "$WORK/seed/lib" ] || fail "seed-lib-missing"

# ---- 2. win32 build of the compiler under test --------------------------------
mkdir -p "$WORK/w32"
(
    cd "$WORK/w32" &&
    "$CROSS_GCC" -std=c89 -m32 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
        -Wno-implicit-function-declaration -I "$WORK/seed/gen" \
        -c "$WORK/seed/gen"/*.c &&
    "$CROSS_GCC" -m32 -O0 ./*.o -lwsock32 -o zig1.exe
) >"$WORK/w32.log" 2>&1 || { tail -20 "$WORK/w32.log"; fail "win32-build"; }

# ---- 3. lib/ beside the exe ---------------------------------------------------
cp -r "$WORK/seed/lib" "$WORK/w32/lib"

# ---- 4. std-importing program, NO -I, run from the exe dir --------------------
cat >"$WORK/std_hello.zig" <<'EOF'
const std = @import("std");
pub fn main() void {
    std.debug.print("hi\n", .{});
}
EOF
mkdir -p "$WORK/w32/out"
(
    cd "$WORK/w32" &&
    WINEDEBUG=-all WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
        timeout "$TIMEOUT" "$WINE" zig1.exe -osw -o out "$WORK/std_hello.zig"
) >"$WORK/run.log" 2>&1
RUN_RC=$?

if [ "$RUN_RC" -ne 0 ]; then
    grep -m1 'error\[' "$WORK/run.log" || true
    fail "run-rc$RUN_RC"
fi
if grep -q 'error\[3048\]' "$WORK/run.log"; then
    fail "error-3048"
fi

# ---- 5. emitted closure must include std_io -----------------------------------
N_C=$(ls "$WORK/w32/out"/*.c 2>/dev/null | wc -l)
[ "$N_C" -gt 0 ] || fail "no-emitted-c"
if ! ls "$WORK/w32/out"/std_io_*.c >/dev/null 2>&1; then
    fail "std_io-not-emitted"
fi

echo "win32: no -I, lib/ beside exe -> rc=0, $N_C .c, std_io emitted"
verdict OK
