#!/bin/sh
# tier_perf.sh — z9gb P3 performance evidence.
#
# Measures the named homebrew ROM 2048.gb on two paths:
#   host_headless: --headless --frames 600 with audio on (Linux host build)
#   wine_windowed: --windowed --frames 600 with audio on (Win32 build under Wine)
#
# The host built output is compiled at -O2 (the harness compiles the emitted C
# with the optimized flags) so the number measures emulator throughput, not the
# generated -O0 scaffold. The Wine path delegates to tier_win32.sh --perf, which
# builds an -O2 no-CRT exe and times the 600-frame window with a QPC launcher.
# Wine numbers are Wine evidence only; they are never Win98 hardware evidence.
#
# Usage:
#   sh tier_perf.sh [ZIG]
#
# Env:
#   ZIG          compiler (first positional arg, else $ZIG, else seed path)
#   OUT          scratch dir (default /tmp/z9gb_tier_perf)
#   Z9GB_ROM_DIR ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_PERF_MIN_FPS minimum sustained rendered fps (default 59.0)
#
# Missing ROM = SKIP (exit 77); ROM size/hash mismatch = FAIL. A skipped hard
# gate blocks P3 closeout. Estimates are labelled as estimates; measured
# numbers are reported as measured.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9gb_tier_perf}"
PERF_MIN="${Z9GB_PERF_MIN_FPS:-59.0}"

for arg in "$@"; do
    case "$arg" in
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) ZIG="$arg" ;;
    esac
done

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

summary() {
    echo
    echo "== tier_perf summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    if [ "$FAILS" -ne 0 ]; then
        echo "TIER_PERF FAIL"
        exit 1
    fi
    if [ "$SKIPS" -ne 0 ]; then
        echo "TIER_PERF SKIP"
        exit 77
    fi
    echo "TIER_PERF PASS"
    exit 0
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in /usr/bin/time awk sha256sum stat; do
    if ! command -v "$tool" >/dev/null 2>&1 && [ ! -x "$tool" ]; then
        echo "SKIP: required host tool not found: $tool"
        exit 77
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

if [ -n "${Z9GB_ROM_DIR:-}" ]; then
    ROM_DIR="$Z9GB_ROM_DIR"
elif [ -d /tmp/z9gb_roms ]; then
    ROM_DIR=/tmp/z9gb_roms
elif [ -d "$Z9DIR/testdata/roms" ]; then
    ROM_DIR="$Z9DIR/testdata/roms"
else
    ROM_DIR=/tmp/z9gb_roms
fi

ROM=""
for cand in "$ROM_DIR/2048.gb" "$ROM_DIR/homebrew/2048.gb"; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done
if [ -z "$ROM" ]; then
    skip_case "2048.gb under $ROM_DIR"
    summary
fi

want="$(awk '$2 == "2048.gb" { print $1; exit }' \
    "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
rom_bytes="$(stat -c %s "$ROM" 2>/dev/null)"
if [ "$rom_bytes" != "32768" ]; then
    fail_case "2048.gb is ${rom_bytes:-<none>} bytes, expected 32768"
    summary
fi
if [ -z "$want" ]; then
    fail_case "2048.gb manifest row missing"
    summary
fi
got="$(sha256sum "$ROM" | cut -d' ' -f1)"
if [ "$got" != "$want" ]; then
    fail_case "2048.gb sha256 mismatch (got $got, want $want)"
    summary
fi
echo "       2048.gb sha256 $got ($rom_bytes bytes)"

echo
echo "== host headless 2048.gb performance =="
HOST_DIR="$OUT/host"
mkdir -p "$HOST_DIR"
if timeout 300 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$HOST_DIR" \
    "$Z9DIR/main.zig" >"$HOST_DIR/dump.log" 2>&1; then
    pass_case "host build emits"
else
    fail_case "host build emits"
    tail -20 "$HOST_DIR/dump.log" | sed 's/^/       /'
    summary
fi
sed 's/-O0/-O2/g' "$HOST_DIR/build_target.sh" >"$HOST_DIR/build_target.sh.tmp" \
    && mv "$HOST_DIR/build_target.sh.tmp" "$HOST_DIR/build_target.sh"
if sh "$HOST_DIR/build_target.sh" linux "$HOST_DIR/z9gb" \
    >"$HOST_DIR/build.log" 2>&1; then
    pass_case "host build links at -O2"
else
    fail_case "host build links at -O2"
    tail -20 "$HOST_DIR/build.log" | sed 's/^/       /'
    summary
fi

timeout 300 /usr/bin/time -f 'wall=%e cpu_user=%U cpu_sys=%S rss_kb=%M' \
    -o "$HOST_DIR/time.txt" "$HOST_DIR/z9gb" \
    --headless --frames 600 --audio --rom "$ROM" \
    --fb-out "$HOST_DIR/2048.fb" >"$HOST_DIR/run.log" 2>&1
host_rc=$?
wall="$(sed -n 's/.*wall=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time.txt" | tail -1)"
cpu_user="$(sed -n 's/.*cpu_user=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time.txt" | tail -1)"
cpu_sys="$(sed -n 's/.*cpu_sys=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time.txt" | tail -1)"
rss_kb="$(sed -n 's/.*rss_kb=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time.txt" | tail -1)"
host_fps="$(awk -v w="${wall:-0}" \
    'BEGIN { if (w + 0 > 0) printf "%.3f", 600 / w; else print "0" }')"
echo "       host_headless fps=$host_fps wall=${wall:-none}s cpu_user=${cpu_user:-none}s cpu_sys=${cpu_sys:-none}s rss_kb=${rss_kb:-none}"
if [ "$host_rc" -ne 0 ]; then
    fail_case "host headless run rc=$host_rc"
    tail -10 "$HOST_DIR/run.log" | sed 's/^/       /'
elif [ "$(stat -c %s "$HOST_DIR/2048.fb" 2>/dev/null)" != "92160" ]; then
    fail_case "host headless framebuffer is not 92160 bytes"
elif awk -v f="$host_fps" -v m="$PERF_MIN" \
    'BEGIN { exit !(f + 0 >= m + 0) }'; then
    pass_case "host headless sustained $host_fps fps (>= $PERF_MIN)"
else
    fail_case "host headless sustained $host_fps fps (< $PERF_MIN)"
fi

echo
echo "== Wine windowed 2048.gb performance =="
WIN_DIR="$OUT/win32"
mkdir -p "$WIN_DIR"
OUT="$WIN_DIR" Z9GB_ROM_DIR="$ROM_DIR" Z9GB_PERF_MIN_FPS="$PERF_MIN" \
    sh "$SCRIPT_DIR/tier_win32.sh" --perf "$ZIG" >"$OUT/win32.log" 2>&1
win_rc=$?
sed 's/^/       /' "$OUT/win32.log"
if [ "$win_rc" -eq 0 ]; then
    pass_case "tier_win32.sh --perf PASS"
elif [ "$win_rc" -eq 77 ]; then
    skip_case "tier_win32.sh --perf SKIP"
else
    fail_case "tier_win32.sh --perf FAIL (rc=$win_rc)"
fi

summary
