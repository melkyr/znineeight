#!/usr/bin/env bash
# cross_compiler.sh — win32 compiler self-host cross harness (pre-test plan Task 4, 2026-09-04).
#
# Dumps the compiler (sf/src/main.zig) with the reference zig1, mingw-cross-
# compiles ALL emitted .c + the compiler link set (zig_runtime.c + zig_pal.c +
# c_exit.c; no net), links a win32 zig1.exe (msvcrt-linked; the compiler's own
# source uses fopen/fread/fwrite/... via pal.zig), then RUNS the win32 zig1.exe
# under the win32 wine prefix to re-compile a small program and compares the
# emitted C89 byte-for-byte with the linux reference compiler's emission.
#
# Lib discovery finding (2026-09-04, RECORDED): the compiler's exe-relative
# default lib path auto-add (main.zig phase_ImportResolution -> pal.fileExists
# on <exe_dir>/lib) NEVER fires on win32, because pal.fileExists probes via
# fopen() which cannot open a DIRECTORY handle on Windows (works on Linux).
# The win32 zig1 therefore cannot find std.zig by itself; the parity runs pass
# the std-lib dir as an explicit search dir (-I sf/src, the compiler's own
# std.zig copy) so the SAME relative search-dir string is used on BOTH sides
# (module-name hashes embed the resolved search path, so identical emitted
# filenames require identical search-dir strings).
#
# Usage:
#   cross_compiler.sh <zig1> <workdir> <exe_out> [parity_entry]
#
#   <zig1>    reference compiler binary (used to dump the compiler AND as the
#             linux reference for the parity emission)
#   <workdir> scratch dir; FRESH <workdir>/gen (compiler dump) per run
#   <exe_out> resulting win32 zig1.exe (a lib/ dir is created next to it)
#   parity_entry (optional)  default examples/z98/hello/main.zig
#
# Prints:
#   XRUNRC=0|DUMPFAIL|GCCFAIL|LINKFAIL
#   COMPILER_PARITY=OK|DIFF  (win32-emitted .c/.h byte-identical to linux ref)
# Exit status 0 only if XRUNRC=0 AND COMPILER_PARITY=OK.
#
# Env overrides: ROOT, CROSS_GCC, WINEPREFIX, WINEARCH, TIMEOUT_*, WINE_WRAP.
set -u

ROOT=${ROOT:-/workspace/znineeight}
CROSS_GCC=${CROSS_GCC:-i686-w64-mingw32-gcc}
WINEPREFIX=${WINEPREFIX:-/tmp/wine32}
WINEARCH=${WINEARCH:-win32}
TIMEOUT_DUMP=${TIMEOUT_DUMP:-300}
TIMEOUT_CC=${TIMEOUT_CC:-300}
TIMEOUT_WINE=${TIMEOUT_WINE:-120}
WINE_WRAP=${WINE_WRAP:-timeout "$TIMEOUT_WINE" env WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" wine}

ZIG1=${1:?usage: cross_compiler.sh <zig1> <workdir> <exe_out> [parity_entry]}
WORK=${2:?usage: cross_compiler.sh <zig1> <workdir> <exe_out> [parity_entry]}
EXE_OUT=${3:?usage: cross_compiler.sh <zig1> <workdir> <exe_out> [parity_entry]}
PARITY_ENTRY=${4:-examples/z98/hello/main.zig}

INCLUDE="$ROOT/sf/src/include"
GENDIR="$WORK/gen"
LIBDIR="$(dirname "$EXE_OUT")/lib"

rm -rf "$WORK"
mkdir -p "$GENDIR"

fail() {
    echo "XRUNRC=$1"
    exit 1
}

# ---- Step 1: dump the compiler (fresh dir, repo-root CWD) -------------------
(
    cd "$ROOT" && timeout "$TIMEOUT_DUMP" "$ZIG1" --dump-c89 --output-dir "$GENDIR" sf/src/main.zig
) >"$WORK/dump.log" 2>&1
DUMP_RC=$?
NERR=$(grep -c 'error\[' "$WORK/dump.log" 2>/dev/null || true)
NPAN=$(grep -c 'PANIC' "$WORK/dump.log" 2>/dev/null || true)
if [ "$DUMP_RC" -ne 0 ] || [ "$NERR" -ne 0 ] || [ "$NPAN" -ne 0 ]; then
    echo "compiler dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN"
    sed -n '1,30p' "$WORK/dump.log"
    fail DUMPFAIL
fi

# ---- Step 2: mingw compile all emitted .c + compiler link set --------------
N_C=0
CC_FAIL=""
for f in "$GENDIR"/*.c; do
    [ -e "$f" ] || continue
    N_C=$((N_C + 1))
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -Wall -Wno-long-long \
        -Wno-pointer-sign -I "$INCLUDE" -c "$f" -o "${f%.c}.o" \
        >>"$WORK/cc.log" 2>&1; then
        CC_FAIL=$(basename "$f")
        break
    fi
done
if [ "$N_C" -eq 0 ]; then
    echo "0 .c emitted (compiler dump ok)"
    fail NOC
fi
for r in zig_runtime zig_pal; do
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -Wall -Wno-long-long \
        -Wno-pointer-sign -I "$INCLUDE" -c "$INCLUDE/$r.c" -o "$WORK/$r.o" \
        >>"$WORK/cc.log" 2>&1; then
        CC_FAIL="$r.c"
        break
    fi
done
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -Wall -I "$INCLUDE" \
    -c "$ROOT/sf/src/c_exit.c" -o "$WORK/c_exit.o" >>"$WORK/cc.log" 2>&1; then
    CC_FAIL="c_exit.c"
fi
if [ -n "$CC_FAIL" ]; then
    echo "cc fail on $CC_FAIL"
    tail -20 "$WORK/cc.log"
    fail GCCFAIL
fi

# ---- Step 3: mingw link -> zig1.exe (compiler links the CRT; no net) --------
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -o "$EXE_OUT" \
    "$GENDIR"/*.o "$WORK/zig_runtime.o" "$WORK/zig_pal.o" "$WORK/c_exit.o" \
    >>"$WORK/ld.log" 2>&1; then
    tail -20 "$WORK/ld.log"
    fail LINKFAIL
fi

# ---- Step 4: place lib/ next to the win32 zig1 (default-lib rule target) ----
mkdir -p "$LIBDIR"
cp "$ROOT/sf/src/std.zig" "$ROOT/sf/src/std_io.zig" \
   "$ROOT/sf/src/std_arena.zig" "$ROOT/sf/src/std_net.zig" "$LIBDIR/"

# ---- Step 5: parity — win32 zig1 under wine vs linux reference --------------
# Same relative search-dir string (-I sf/src) on both sides so the std* module
# hashes (which embed the resolved search path) match.
echo "compiler dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN c=$N_C link ok"
echo "XRUNRC=0"

mkdir -p "$WORK/ref" "$WORK/win"
(
    cd "$ROOT" && timeout "$TIMEOUT_DUMP" "$ZIG1" -I 'sf/src' \
        --dump-c89 --output-dir "$WORK/ref" "$PARITY_ENTRY"
) >"$WORK/ref.log" 2>&1
REF_RC=$?
(
    cd "$ROOT" && $WINE_WRAP "$EXE_OUT" -I 'sf/src' \
        --dump-c89 --output-dir "$WORK/win" "$PARITY_ENTRY"
) >"$WORK/win.log" 2>&1
WIN_RC=$?
if [ "$REF_RC" -ne 0 ] || [ "$WIN_RC" -ne 0 ]; then
    echo "parity: ref_rc=$REF_RC win_rc=$WIN_RC (dumps must both be rc=0)"
    echo "COMPILER_PARITY=DIFF"
    exit 1
fi
DIFF=0
for f in "$WORK/ref"/*.c "$WORK/ref"/*.h; do
    b=$(basename "$f")
    if [ ! -f "$WORK/win/$b" ]; then
        echo "missing win file: $b"
        DIFF=1
        continue
    fi
    if ! cmp -s "$f" "$WORK/win/$b"; then
        echo "byte diff: $b"
        DIFF=1
    fi
done
if [ "$DIFF" -eq 0 ]; then
    echo "COMPILER_PARITY=OK"
    exit 0
fi
echo "COMPILER_PARITY=DIFF"
exit 1
