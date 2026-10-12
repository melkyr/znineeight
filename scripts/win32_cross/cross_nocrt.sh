#!/usr/bin/env bash
# cross_nocrt.sh — win32 ZIG_NO_CRT build harness (pre-test plan Task 4, 2026-09-04).
#
# Builds one non-net program as a PE32 console image that imports ONLY kernel32
# (no msvcrt): the zig_pal.c mainCRTStartup stub (compiled under -DZIG_NO_CRT)
# is the entry; mingw's crt objects and default libs are excluded (-nostdlib);
# a tiny generated shim (in <workdir>) implements the handful of libc names the
# emitted std_io/runtime modules reference but which a no-CRT binary cannot get
# from msvcrt (strlen/putchar/getchar/fwrite/__acrt_iob_func/__main) as raw
# Win32 I/O; libgcc covers __udivdi3/__umoddi3/__chkstk_ms.
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
# Link form (determined 2026-09-04, RECORDED):
#   i686-w64-mingw32-gcc -m32 -nostdlib -o <exe_out> <objs> <workdir>/nocrt_shim.o \
#       -Wl,-e,_mainCRTStartup -lgcc -lkernel32
#   - -nostdlib        excludes mingw crt2.o (its mainCRTStartup would collide
#                      with the pal stub) and the default msvcrt libs.
#   - -e,_mainCRTStartup  sets the PE entry to the pal stub (COFF decoration:
#                      C fn mainCRTStartup is the linker symbol _mainCRTStartup).
#   - shim symbols come from nocrt_shim.c generated below.
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
N_C=0
CC_FAIL=""
for f in "$DUMPDIR"/*.c; do
    [ -e "$f" ] || continue
    N_C=$((N_C + 1))
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -DZIG_NO_CRT \
        -Wall -Wno-long-long -Wno-pointer-sign -I "$INCLUDE" \
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
for r in zig_runtime zig_pal; do
    if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -DZIG_NO_CRT \
        -Wall -Wno-long-long -Wno-pointer-sign -I "$INCLUDE" \
        "${EXTRA_DEFS[@]}" -c "$INCLUDE/$r.c" -o "$WORK/$r.o" \
        >>"$DUMPDIR/cc.log" 2>&1; then
        CC_FAIL="$r.c"
        break
    fi
done
if [ -n "$CC_FAIL" ]; then
    echo "cc fail on $CC_FAIL"
    tail -20 "$DUMPDIR/cc.log"
    fail GCCFAIL
fi

# ---- Step 3: no-CRT shim (raw Win32 I/O; generated in scratch workdir) ------
cat > "$WORK/nocrt_shim.c" <<'EOF'
#include <windows.h>
typedef unsigned int size_t;
typedef struct _iobuf FILE;
size_t strlen(const char* s) { const char* p = s; while (*p) p++; return (size_t)(p - s); }
void __main(void) {}
int putchar(int c) {
    char ch = (char)c; DWORD w; HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return -1;
    if (!WriteConsoleA(h, &ch, 1, &w, NULL)) WriteFile(h, &ch, 1, &w, NULL);
    return (unsigned char)c;
}
int getchar(void) {
    char ch; DWORD r; HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return -1;
    if (!ReadFile(h, &ch, 1, &r, NULL) || r == 0) return -1;
    return (unsigned char)ch;
}
size_t fwrite(const void* p, size_t sz, size_t n, FILE* stream) {
    size_t tot = sz * n; DWORD w; HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    (void)stream;
    if (!p || !tot) return 0;
    if (h == INVALID_HANDLE_VALUE || h == NULL) return 0;
    if (!WriteConsoleA(h, p, (DWORD)tot, &w, NULL)) WriteFile(h, p, (DWORD)tot, &w, NULL);
    return (w == (DWORD)tot) ? n : 0;
}
FILE* __acrt_iob_func(unsigned _Ix) { (void)_Ix; return NULL; }
__asm__(".section .data,\"w\"");
__asm__(".globl __imp____acrt_iob_func");
__asm__("__imp____acrt_iob_func:");
__asm__(".long ___acrt_iob_func");
EOF
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -c "$WORK/nocrt_shim.c" \
    -o "$WORK/nocrt_shim.o" >>"$DUMPDIR/cc.log" 2>&1; then
    echo "cc fail on nocrt_shim.c"
    tail -20 "$DUMPDIR/cc.log"
    fail GCCFAIL
fi

# ---- Step 4: mingw no-CRT link (entry = pal mainCRTStartup stub) ------------
if ! timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -nostdlib -o "$EXE_OUT" \
    "$DUMPDIR"/*.o "$WORK/zig_runtime.o" "$WORK/zig_pal.o" \
    "$WORK/nocrt_shim.o" -Wl,-e,_mainCRTStartup -lgcc -lkernel32 \
    >>"$DUMPDIR/ld.log" 2>&1; then
    echo "no-crt link failed (entry -e,_mainCRTStartup, -nostdlib -lgcc -lkernel32)"
    tail -20 "$DUMPDIR/ld.log"
    fail LINKFAIL
fi

echo "dump: rc=$DUMP_RC error_brk=$NERR panic=$NPAN c=$N_C no-crt link ok"
echo "XRUNRC=0"
exit 0
