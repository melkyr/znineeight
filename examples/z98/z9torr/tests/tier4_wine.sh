#!/bin/sh
# tier4_wine.sh — z9torr M5 gate, BUILD half: Windows emission + mingw build.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. emit the Windows tree with `<zig1> -osw -o <dir>` and assert it carries
#      the module .c/.h, the Windows link scripts (build_target.bat,
#      build_owc.bat) and net_prelude.h;
#   2. cross-compile the emitted C for win32 with the committed
#      scripts/win32_cross/cross_build_run.sh recipe (mingw; the link line is
#      unconditional -lwsock32);
#   3. sanity: `file` reports a PE32 executable, and `objdump -p` / `nm` shows
#      the wsock32 import.
# The RUN half (wine smoke against the host mocks) is M5 Task 2 and extends this
# file; this half only proves the artifact builds.
#
# Toolchain: the seed compiler, i686-w64-mingw32-gcc, file, objdump, nm.
# SKIP-with-reason (exit 77, distinct from PASS=0 / FAIL=1) if a required tool
# is genuinely unavailable — never a silent pass.
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m5_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier4}"
ENTRY="examples/z98/z9torr/main.zig"

CROSS_GCC="${CROSS_GCC:-i686-w64-mingw32-gcc}"
XBUILD="$ROOT/scripts/win32_cross/cross_build_run.sh"

# Conventional "skipped" status (autotools/automake). Distinct from PASS (0)
# and FAIL (1) so a missing-toolchain no-op can never be mistaken for success.
SKIP_EXIT=77

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

skip() {
    echo
    echo "SKIP: $1"
    echo "TIER4 SKIP"
    exit "$SKIP_EXIT"
}

# --- toolchain presence (SKIP, not FAIL, when genuinely absent) --------------
for _t in "$ZIG" "$CROSS_GCC" file objdump nm; do
    if [ -x "$_t" ] || command -v "$_t" >/dev/null 2>&1; then continue; fi
    skip "required tool unavailable: $_t"
done
if [ ! -f "$XBUILD" ]; then
    skip "committed cross recipe missing: $XBUILD"
fi

rm -rf "$OUT"
mkdir -p "$OUT/work"
WIN="$OUT/win"
EXE="$OUT/z9torr.exe"

cd "$ROOT" || { echo "FAIL: cannot cd $ROOT"; exit 1; }

# --- Step 1: emit the Windows tree ------------------------------------------
echo "== step 1: emit the windows tree (-osw -o) =="
mkdir -p "$WIN"
if timeout 120 "$ZIG" -osw -o "$WIN" "$ENTRY" >"$OUT/emit.log" 2>&1; then
    pass_case "windows emit rc=0"
else
    fail_case "windows emit rc=0 (see $OUT/emit.log)"
fi

N_C=$(ls "$WIN"/*.c 2>/dev/null | wc -l | tr -d ' ')
N_H=$(ls "$WIN"/*.h 2>/dev/null | wc -l | tr -d ' ')
if [ "$N_C" -gt 0 ] && [ "$N_H" -gt 0 ]; then
    pass_case "emit tree carries module .c/.h ($N_C .c, $N_H .h)"
else
    fail_case "emit tree carries module .c/.h ($N_C .c, $N_H .h)"
fi

for _f in build_target.bat build_owc.bat net_prelude.h; do
    if [ -e "$WIN/$_f" ]; then pass_case "emit tree carries $_f"
    else fail_case "emit tree carries $_f"; fi
done

# --- Step 2: mingw cross-build (committed win32_cross recipe) ---------------
echo "== step 2: mingw cross-build (cross_build_run.sh; -lwsock32) =="
XRUN_LOG="$OUT/xrun.log"
if timeout 600 bash "$XBUILD" "$ZIG" "$ENTRY" "$OUT/cross" "$EXE" >"$XRUN_LOG" 2>&1; then
    XRUNRC=$(sed -n 's/^XRUNRC=//p' "$XRUN_LOG" | tail -1)
    if [ "$XRUNRC" = "0" ] && [ -f "$EXE" ]; then
        pass_case "mingw cross-build produced z9torr.exe (XRUNRC=0)"
    else
        fail_case "mingw cross-build produced z9torr.exe (XRUNRC=$XRUNRC)"
    fi
else
    fail_case "mingw cross-build (see $XRUN_LOG)"
fi

# --- Step 3: PE32 + wsock32 sanity ------------------------------------------
echo "== step 3: PE32 + wsock32 sanity =="
if [ -f "$EXE" ]; then
    FTYPE=$(file "$EXE" 2>/dev/null)
    case "$FTYPE" in
        *PE32*) pass_case "file reports PE32 ($FTYPE)" ;;
        *)      fail_case "file reports PE32 (got: $FTYPE)" ;;
    esac
    if objdump -p "$EXE" 2>/dev/null | grep -qi 'wsock32'; then
        pass_case "objdump -p shows a wsock32 import"
    elif nm "$EXE" 2>/dev/null | grep -qi 'wsock32'; then
        pass_case "nm shows a wsock32 import"
    else
        fail_case "wsock32 import not found (objdump -p / nm)"
    fi
else
    fail_case "z9torr.exe not produced"
fi

# --- summary ----------------------------------------------------------------
echo
echo "== tier4 (build half) summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER4 FAIL"
    exit 1
fi
echo "TIER4 PASS"
exit 0
