#!/usr/bin/env bash
# cross_build_run.sh — win32 cross-build+link harness (pre-test plan Task 1, 2026-09-04).
#
# Usage:
#   cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]
#
#   <zig1>    reference compiler binary (e.g. /tmp/fx_subfolder/zig1)
#   <entry>   repo-relative program entry (e.g. examples/z98/game_of_life/main.zig);
#             dumped from the repo root CWD (module resolution is CWD-relative)
#   <workdir> scratch dir; a FRESH <workdir>/dump subdir is created per run
#   <exe_out> path of the resulting PE32 .exe
#   extra args: additional link libs/flags appended to the win32 link line
#
# Pipeline (Task-0 recipe):
#   1. (cd repo-root && <zig1> --dump-c89 --output-dir <workdir>/dump <entry>)
#      gate: rc=0 AND 0 'error[' AND 0 'PANIC'
#   2. i686-w64-mingw32-gcc -std=c89 -m32 -Wall -Wno-long-long -Wno-pointer-sign
#      -I sf/src/include  -c  each emitted .c -> .o
#   3. i686-w64-mingw32-gcc -m32 -o <exe_out> *.o zig_runtime.c zig_pal.c [extra libs]
#
# Prints one machine-readable verdict line:  XRUNRC=<value>
#   <value> 0        build+link OK
#          DUMPFAIL  dump rc!=0 / error[ / PANIC
#          GCCFAIL   a mingw compile failed
#          LINKFAIL  mingw link failed
#          NOC       0 .c emitted
# Exit status mirrors XRUNRC (0 / 1). Every sub-run is timeout-guarded.
#
# Env overrides: ROOT, CROSS_GCC, TIMEOUT_DUMP, TIMEOUT_CC.
set -u

ROOT=${ROOT:-/workspace/znineeight}
CROSS_GCC=${CROSS_GCC:-i686-w64-mingw32-gcc}
TIMEOUT_DUMP=${TIMEOUT_DUMP:-300}
TIMEOUT_CC=${TIMEOUT_CC:-180}

ZIG1=${1:?usage: cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]}
ENTRY=${2:?usage: cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]}
WORK=${3:?usage: cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]}
EXE_OUT=${4:?usage: cross_build_run.sh <zig1> <entry> <workdir> <exe_out> [extra_link_libs...]}
shift 4
EXTRA_LIBS=("$@")

INCLUDE="$ROOT/sf/src/include"
DUMPDIR="$WORK/dump"

rm -rf "$WORK"
mkdir -p "$DUMPDIR"

fail() {
    echo "XRUNRC=$1"
    exit 1
}

# ---- Step 1: dump C89 (fresh dir, repo-root CWD) ---------------------------
(
    cd "$ROOT" && timeout "$TIMEOUT_DUMP" "$ZIG1" --dump-c89 --output-dir "$DUMPDIR" "$ENTRY"
) >"$DUMPDIR/dump.log" 2>&1
DUMP_RC=$?
NERR=$(grep -c 'error\[' "$DUMPDIR/dump.log" 2>/dev/null || true)
NPAN=$(grep -c 'PANIC' "$DUMPDIR/dump.log" 2>/dev/null || true)
if [ "$DUMP_RC" -ne 0 ] || [ "$NERR" -ne 0 ] || [ "$NPAN" -ne 0 ]; then
    echo "dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN"
    sed -n '1,30p' "$DUMPDIR/dump.log"
    fail DUMPFAIL
fi

# ---- Step 2: mingw compile each emitted .c -> .o ---------------------------
N_C=0
CC_FAIL=""
for f in "$DUMPDIR"/*.c; do
    [ -e "$f" ] || continue
    N_C=$((N_C + 1))
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -Wall -Wno-long-long \
        -Wno-pointer-sign -I "$INCLUDE" -c "$f" -o "${f%.c}.o" \
        >>"$DUMPDIR/cc.log" 2>&1; then
        CC_FAIL=$(basename "$f")
        break
    fi
done
if [ "$N_C" -eq 0 ]; then
    echo "0 .c emitted (dump ok)"
    fail NOC
fi
if [ -n "$CC_FAIL" ]; then
    echo "cc fail on $CC_FAIL"
    tail -20 "$DUMPDIR/cc.log"
    fail GCCFAIL
fi

# ---- Step 3: mingw link -> exe ---------------------------------------------
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -o "$EXE_OUT" \
    "$DUMPDIR"/*.o "$INCLUDE/zig_runtime.c" "$INCLUDE/zig_pal.c" \
    "${EXTRA_LIBS[@]}" >>"$DUMPDIR/ld.log" 2>&1; then
    tail -20 "$DUMPDIR/ld.log"
    fail LINKFAIL
fi

echo "dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN c=$N_C link ok"
echo "XRUNRC=0"
exit 0
