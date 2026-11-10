#!/bin/sh
# tier_win32.sh — z9gb Win32 backend tier.
#
# Task 1 scope: build the Win32-only std_ddraw probe through the no-CRT mingw
# harness with -osw, pass the closed-world 9x import gate (no static DDRAW.DLL),
# and run the real exe under Wine/Xvfb at --scale 2 --frames 1. The windowed
# framebuffer checksum must equal the headless source checksum and the first
# pixel must be the solid probe colour 0x00123456.
#
# Env: ZIG       compiler (first positional arg, else $ZIG, else seed path)
#      OUT       scratch dir (default /tmp/z9gb_tier_win32)
#
# Exits non-zero on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_tier_win32}"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file md5sum od wine xvfb-run timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== (a) std_ddraw Win32 probe =="
if OUT="$OUT/ddraw" ZIG="$ZIG" sh "$SCRIPT_DIR/run_ddraw_probe.sh" "$ZIG" \
    >"$OUT/ddraw_probe.log" 2>&1; then
    pass_case "run_ddraw_probe.sh PASS"
else
    fail_case "run_ddraw_probe.sh FAILED (see $OUT/ddraw_probe.log)"
fi
sed 's/^/       /' "$OUT/ddraw_probe.log"

EXE="$OUT/ddraw/ddraw_probe.exe"
if [ -f "$EXE" ]; then
    if bash "$CHECK" "$EXE" 9x >"$OUT/imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (tier re-check)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/imports.log)"
    fi
    DLLS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$DLLS" | grep -qx 'DDRAW.DLL'; then
        fail_case "DDRAW.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DDRAW.DLL import (loaded dynamically)"
    fi
else
    fail_case "ddraw_probe.exe missing"
fi

if grep -q '^DDRAW_PROBE PASS$' "$OUT/ddraw_probe.log" 2>/dev/null; then
    pass_case "probe marker DDRAW_PROBE PASS"
else
    fail_case "probe marker DDRAW_PROBE PASS missing"
fi

if grep -q '^[[:space:]]*readback scale=2 PASS' "$OUT/ddraw_probe.log" 2>/dev/null \
    && grep -q '^[[:space:]]*readback scale=4 PASS' "$OUT/ddraw_probe.log" 2>/dev/null; then
    pass_case "presented surface readback at scale 2 and 4 (GDI GetPixel)"
else
    fail_case "presented surface readback at scale 2/4 missing or failed"
fi

echo
echo "== (b) std_dinput Win32 probe =="
if OUT="$OUT/dinput" ZIG="$ZIG" sh "$SCRIPT_DIR/run_dinput_probe.sh" "$ZIG" \
    >"$OUT/dinput_probe.log" 2>&1; then
    pass_case "run_dinput_probe.sh PASS"
else
    fail_case "run_dinput_probe.sh FAILED (see $OUT/dinput_probe.log)"
fi
sed 's/^/       /' "$OUT/dinput_probe.log"

DEXE="$OUT/dinput/dinput_probe.exe"
if [ -f "$DEXE" ]; then
    if bash "$CHECK" "$DEXE" 9x >"$OUT/dinput_imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (dinput)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/dinput_imports.log)"
    fi
    DDLLS="$(i686-w64-mingw32-objdump -p "$DEXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$DDLLS" | grep -qx 'DINPUT8.DLL'; then
        fail_case "DINPUT8.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DINPUT8.DLL import (loaded dynamically)"
    fi
else
    fail_case "dinput_probe.exe missing"
fi

if grep -q '^DINPUT_PROBE PASS$' "$OUT/dinput_probe.log" 2>/dev/null; then
    pass_case "probe marker DINPUT_PROBE PASS"
else
    fail_case "probe marker DINPUT_PROBE PASS missing"
fi

if grep -Eq '^[[:space:]]*dinput=(ok|fallback)$' "$OUT/dinput_probe.log" 2>/dev/null; then
    pass_case "dinput backend line (ok or fallback)"
else
    fail_case "dinput backend line missing"
fi

echo
echo "== (c) std_dsound Win32 probe =="
if OUT="$OUT/dsound" ZIG="$ZIG" sh "$SCRIPT_DIR/run_dsound_probe.sh" "$ZIG" \
    >"$OUT/dsound_probe.log" 2>&1; then
    pass_case "run_dsound_probe.sh PASS"
else
    fail_case "run_dsound_probe.sh FAILED (see $OUT/dsound_probe.log)"
fi
sed 's/^/       /' "$OUT/dsound_probe.log"

SEXE="$OUT/dsound/dsound_probe.exe"
if [ -f "$SEXE" ]; then
    if bash "$CHECK" "$SEXE" 9x >"$OUT/dsound_imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (dsound)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/dsound_imports.log)"
    fi
    SDLLS="$(i686-w64-mingw32-objdump -p "$SEXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$SDLLS" | grep -qx 'DSOUND.DLL'; then
        fail_case "DSOUND.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DSOUND.DLL import (loaded dynamically)"
    fi
else
    fail_case "dsound_probe.exe missing"
fi

if grep -q '^DSOUND_PROBE PASS$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "probe marker DSOUND_PROBE PASS"
else
    fail_case "probe marker DSOUND_PROBE PASS missing"
fi

if grep -Eq '^[[:space:]]*backend=(1|2) queued=[0-9]+$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "dsound backend line (DirectSound or waveOut fallback)"
else
    fail_case "dsound backend line missing"
fi

echo
echo "== tier_win32 summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_WIN32 FAIL"
    exit 1
fi
echo "TIER_WIN32 PASS"
exit 0
