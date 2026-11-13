#!/bin/sh
# build.sh — UNDERSANDED M1 dual no-CRT Win9x link configs (spec §26, G15).
#
#   under.exe    WINDOWS_GUI  main.zig         gfxOpen window titled UNDERSANDED
#   undtool.exe  WINDOWS_CUI  main_console.zig gfxOpenMemory + stdout, no window
#
# Both are Z98 -> C89 -> mingw32 no-CRT PE32 images. sample.txt is copied next
# to both exes (installed content is always read from the exe dir, spec §32).
#
# Env: ZIG  compiler (default /tmp/zig1-m1/zig1_5_clean)
#      OUT  output dir (default examples/z98/undersanded/out)
#
# Exits non-zero on any build failure. Run `-fsafe -W` (warnings as errors)
# dumps first so a warning cannot hide behind the cross harness.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/zig1-m1/zig1_5_clean}"
OUT="${OUT:-$SCRIPT_DIR/out}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
FIXTURE="$SCRIPT_DIR/tests/fixtures/sample.txt"
ENTRY_GUI="examples/z98/undersanded/main.zig"
ENTRY_CUI="examples/z98/undersanded/main_console.zig"

fail() {
    echo "BUILD FAILED: $1"
    exit 1
}

[ -x "$ZIG" ] || fail "compiler not found: $ZIG"
[ -f "$CROSS" ] || fail "cross harness not found: $CROSS"
[ -f "$FIXTURE" ] || fail "fixture missing: $FIXTURE"
command -v i686-w64-mingw32-gcc >/dev/null 2>&1 || fail "i686-w64-mingw32-gcc not found"

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || fail "cannot cd to $ROOT"

# ---- warning-clean (-fsafe -W) dumps, one per entry ----------------------
for spec in "gui $ENTRY_GUI" "cui $ENTRY_CUI"; do
    set -- $spec
    name=$1
    entry=$2
    mkdir -p "$OUT/warn_$name"
    if ! timeout 300 "$ZIG" -fsafe -W -osw --dump-c89 \
        --output-dir "$OUT/warn_$name" "$entry" >"$OUT/warn_$name.log" 2>&1; then
        sed -n '1,30p' "$OUT/warn_$name.log"
        fail "$name -fsafe -W dump not clean"
    fi
    echo "ok   - $name -fsafe -W dump clean"
done

# ---- under.exe: GUI subsystem, no CRT ------------------------------------
ROOT="$ROOT" \
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32" \
EXTRA_LDFLAGS="-Wl,--subsystem,windows" \
    bash "$CROSS" "$ZIG" "$ENTRY_GUI" "$OUT/work_gui" "$OUT/under.exe" \
    >"$OUT/build_gui.log" 2>&1
[ $? -eq 0 ] || { tail -20 "$OUT/build_gui.log"; fail "under.exe link"; }
[ -f "$OUT/under.exe" ] || fail "under.exe missing"
echo "ok   - under.exe (GUI, no-CRT)"

# ---- undtool.exe: console subsystem, no CRT ------------------------------
# std_gfx's cell surface is linked even in memory mode, so the same
# GDI32/USER32 import libs are needed; the subsystem stays the console default.
ROOT="$ROOT" \
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32" \
    bash "$CROSS" "$ZIG" "$ENTRY_CUI" "$OUT/work_cui" "$OUT/undtool.exe" \
    >"$OUT/build_cui.log" 2>&1
[ $? -eq 0 ] || { tail -20 "$OUT/build_cui.log"; fail "undtool.exe link"; }
[ -f "$OUT/undtool.exe" ] || fail "undtool.exe missing"
echo "ok   - undtool.exe (CUI, no-CRT)"

# ---- installed content beside both exes ----------------------------------
cp "$FIXTURE" "$OUT/sample.txt" || fail "copy sample.txt"
echo "ok   - sample.txt copied beside both exes"

echo "BUILD OK"
echo "  $OUT/under.exe"
echo "  $OUT/undtool.exe"
