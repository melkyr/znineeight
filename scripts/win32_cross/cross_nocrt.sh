#!/usr/bin/env bash
# cross_nocrt.sh — win32 ZIG_NO_CRT build harness (pre-test plan Task 4, 2026-09-04).
#
# Builds one non-net program as a PE32 console image that imports ONLY kernel32
# (no msvcrt): the emitted zig_pal.c mainCRTStartup (compiled under
# -DZIG_NO_CRT) is the entry; mingw's crt objects and default libs are excluded
# (-nostdlib); the emitted zig_nocrt.c / zig_runtime.c / c_exit.c shims provide
# the libc names the emitted code references; libgcc covers the 64-bit helpers.
#
# Usage:
#   cross_nocrt.sh <zig1> <entry> <workdir> <exe_out> [extra_gcc_defs...]
#
#   <zig1>    reference compiler binary (e.g. /tmp/fx_subfolder/zig1)
#   <entry>   repo-relative program entry (dumped from repo root CWD)
#   <workdir> scratch dir; FRESH <workdir>/dump created per run
#   <exe_out> path of the resulting PE32 .exe
#   extra args: extra -D defs appended to every compile (e.g. a program flag)
#
# Link form (updated T5.3, RECORDED):
#   i686-w64-mingw32-gcc -m32 -nostdlib -o <exe_out> <all emitted objs> \
#       -Wl,-e,_mainCRTStartup -lgcc -lkernel32
#   - -nostdlib        excludes mingw crt2.o (its mainCRTStartup would collide
#                      with the pal startup) and the default msvcrt libs.
#   - -e,_mainCRTStartup  sets the PE entry to the pal startup (COFF decoration:
#                      C fn mainCRTStartup is the linker symbol _mainCRTStartup).
#   - shim symbols come from the emitted zig_nocrt.c / c_exit.c.
#   - Program choice: the dump MUST be no-CRT-clean. examples/z98/hello is the
#     proven candidate; game_of_life is NOT (its emitted main calls system("cls")
#     -> unresolved msvcrt `system`). See task-WIN32-report.md ## Task 4.
#
# Prints: XRUNRC=<value>  (0 | DUMPFAIL | GCCFAIL | LINKFAIL | NOC) and echoes
# dump summary. Exit status mirrors XRUNRC (0 / 1). Every sub-run is
# timeout-guarded.
#
# Env overrides: ROOT, ZIG1, CROSS_GCC, TIMEOUT_DUMP, TIMEOUT_CC.
set -u

ROOT=${ROOT:-/workspace/znineeight}
CROSS_GCC=${CROSS_GCC:-i686-w64-mingw32-gcc}
TIMEOUT_DUMP=${TIMEOUT_DUMP:-300}
TIMEOUT_CC=${TIMEOUT_CC:-240}

ZIG1=${1:?usage: cross_nocrt.sh <zig1> <entry> <workdir> <exe_out> [extra_gcc_defs...]}
ENTRY=${2:?usage: cross_nocrt.sh <zig1> <entry> <workdir> <exe_out> [extra_gcc_defs...]}
WORK=${3:?usage: cross_nocrt.sh <zig1> <entry> <workdir> <exe_out> [extra_gcc_defs...]}
EXE_OUT=${4:?usage: cross_nocrt.sh <zig1> <entry> <workdir> <exe_out> [extra_gcc_defs...]}
shift 4
EXTRA_DEFS=("$@")

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

# ---- Step 2: mingw compile emitted .c + runtime under -DZIG_NO_CRT ----------
# Task 4+ dump dirs are self-contained (they carry zig_runtime.c/zig_pal.c/
# c_exit.c): compile with -I <dumpdir> and link ONLY the emitted objects.
# Legacy (pre-Task-4) dirs keep -I sf/src/include + the separately compiled repo
# runtime pair (zig_runtime.c + zig_pal.c).
SELFCONTAINED=0
if [ -f "$DUMPDIR/zig_runtime.c" ]; then
    SELFCONTAINED=1
    CC_INC="$DUMPDIR"
    RT_OBJS=()
else
    CC_INC="$INCLUDE"
    RT_OBJS=("$WORK/zig_runtime.o" "$WORK/zig_pal.o" "$WORK/zig_nocrt.o" "$WORK/c_exit.o")
fi
N_C=0
CC_FAIL=""
for f in "$DUMPDIR"/*.c; do
    [ -e "$f" ] || continue
    N_C=$((N_C + 1))
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -DZIG_NO_CRT \
        -Wall -Wno-long-long -Wno-pointer-sign -I "$CC_INC" \
        "${EXTRA_DEFS[@]}" -c "$f" -o "${f%.c}.o" \
        >>"$DUMPDIR/cc.log" 2>&1; then
        CC_FAIL=$(basename "$f")
        break
    fi
done
if [ "$N_C" -eq 0 ]; then
    echo "0 .c emitted (dump ok)"
    fail NOC
fi
if [ "$SELFCONTAINED" -eq 0 ]; then
    for r in zig_runtime zig_pal zig_nocrt c_exit; do
        if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -DZIG_NO_CRT \
            -Wall -Wno-long-long -Wno-pointer-sign -I "$CC_INC" \
            "${EXTRA_DEFS[@]}" -c "$INCLUDE/$r.c" -o "$WORK/$r.o" \
            >>"$DUMPDIR/cc.log" 2>&1; then
            CC_FAIL="$r.c"
            break
        fi
    done
fi
if [ -n "$CC_FAIL" ]; then
    echo "cc fail on $CC_FAIL"
    tail -20 "$DUMPDIR/cc.log"
    fail GCCFAIL
fi

# ---- Step 3: mingw no-CRT link (entry = emitted mainCRTStartup) ------------
# All emitted objects (including c_exit.o and zig_nocrt.o) are linked; the
# emitted shims provide exit/atexit/strlen/memcpy/strncmp/stdio/env/time.
LINK_OBJS=()
for f in "$DUMPDIR"/*.o; do
    [ -e "$f" ] || continue
    LINK_OBJS+=("$f")
done
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -nostdlib -o "$EXE_OUT" \
    "${LINK_OBJS[@]}" "${RT_OBJS[@]}" \
    -Wl,-e,_mainCRTStartup -lgcc -lkernel32 \
    >>"$DUMPDIR/ld.log" 2>&1; then
    echo "no-crt link failed (entry -e,_mainCRTStartup, -nostdlib -lgcc -lkernel32)"
    tail -20 "$DUMPDIR/ld.log"
    fail LINKFAIL
fi

echo "dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN c=$N_C no-crt link ok"
echo "XRUNRC=0"
exit 0
