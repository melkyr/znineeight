#!/bin/sh
# measure_rss.sh — z9gb P1 memory + determinism gate.
#
# Builds the headless CLI, creates a deterministic synthetic 8 MiB ROM, runs 60
# frames with it loaded under /usr/bin/time to measure peak RSS (KiB), and runs
# the same command three times to prove the framebuffer dump at /tmp/z9gb_p1.fb
# is byte-identical.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else seed path)
#      OUT  scratch dir (second positional arg, else a fresh mktemp -d)
#
# Usage: measure_rss.sh [ZIG] [OUT] [--cgb]
#        --cgb runs the measured 60-frame headless workload in CGB mode.
#
# Prints: rss_kb=<n>, fb_bytes=<n>, rom_bytes=<n>, cgb=<0|1>
# Exits 77 with a SKIP line when /usr/bin/time is unavailable.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
CGB=0
ZIG_ARG=""
OUT_ARG=""
for arg in "$@"; do
    case "$arg" in
        --cgb) CGB=1 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *)
            if [ -z "$ZIG_ARG" ]; then
                ZIG_ARG="$arg"
            elif [ -z "$OUT_ARG" ]; then
                OUT_ARG="$arg"
            else
                echo "usage: measure_rss.sh [ZIG] [OUT] [--cgb]" >&2
                exit 2
            fi
            ;;
    esac
done
ZIG="${ZIG_ARG:-${ZIG:-/tmp/z9gb_seed/zig1_5_clean}}"
if [ -n "$OUT_ARG" ]; then
    OUT="$OUT_ARG"
else
    OUT="$(mktemp -d)"
fi
CGB_FLAG=""
if [ "$CGB" -eq 1 ]; then
    CGB_FLAG="--cgb"
fi
FB="/tmp/z9gb_p1.fb"
BIN="$OUT/z9gb"
ROM_BYTES=8388608
FB_BYTES_EXPECTED=92160
RSS_LIMIT=12000

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG" >&2
    exit 1
fi

if [ ! -x /usr/bin/time ]; then
    echo "SKIP: /usr/bin/time unavailable"
    exit 77
fi

mkdir -p "$OUT" || exit 1
cd "$ROOT" || exit 1

rm -f "$FB"

if ! timeout 120 "$ZIG" -ffast -o "$OUT" examples/z98/z9gb/main.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: z9gb emit failed" >&2
    tail -20 "$OUT/zig.log" | sed 's/^/       /' >&2
    exit 1
fi
if [ ! -f "$OUT/build_target.sh" ] || ! sh "$OUT/build_target.sh" linux "$BIN" >"$OUT/build.log" 2>&1; then
    echo "FAIL: z9gb link failed" >&2
    [ -f "$OUT/build.log" ] && tail -20 "$OUT/build.log" | sed 's/^/       /' >&2
    exit 1
fi

# Deterministic synthetic ROM so emuLoadRom touches the fixed 8 MiB buffer; the
# RSS bound is only meaningful with the ROM resident.
ROM="$OUT/synthetic_8m.rom"
if ! dd if=/dev/zero of="$ROM" bs=1048576 count=8 >/dev/null 2>&1; then
    echo "FAIL: cannot create synthetic 8 MiB ROM" >&2
    exit 1
fi
rom_size="$(stat -c %s "$ROM")"
if [ "$rom_size" != "$ROM_BYTES" ]; then
    echo "FAIL: synthetic ROM size $rom_size (want $ROM_BYTES)" >&2
    exit 1
fi

run=1
rss1=""
while [ "$run" -le 3 ]; do
    rm -f "$FB"
    if ! timeout 60 /usr/bin/time -f '%M' -o "$OUT/rss.txt" \
        "$BIN" --headless $CGB_FLAG --frames 60 --rom "$ROM" --fb-out "$FB" \
        >"$OUT/run.$run.out" 2>"$OUT/run.$run.err"; then
        echo "FAIL: run $run exited nonzero" >&2
        tail -20 "$OUT/run.$run.err" | sed 's/^/       /' >&2
        exit 1
    fi
    if [ ! -f "$FB" ]; then
        echo "FAIL: run $run produced no framebuffer ($FB)" >&2
        exit 1
    fi
    rss="$(cat "$OUT/rss.txt")"
    case "$rss" in
        ''|*[!0-9]*)
            echo "FAIL: run $run rss_kb not a positive integer: $rss" >&2
            exit 1
            ;;
    esac
    cp "$OUT/rss.txt" "$OUT/rss.$run.txt"
    if [ "$run" -eq 1 ]; then
        rss1="$rss"
        cp "$FB" "$OUT/fb.run1.bin"
    else
        if ! cmp -s "$OUT/fb.run1.bin" "$FB"; then
            echo "FAIL: run $run framebuffer differs from run 1" >&2
            exit 1
        fi
    fi
    run=$((run + 1))
done

if [ "$rss1" -le 0 ]; then
    echo "FAIL: rss_kb is not positive: $rss1" >&2
    exit 1
fi
if [ "$rss1" -ge "$RSS_LIMIT" ]; then
    echo "FAIL: rss_kb=$rss1 not below $RSS_LIMIT" >&2
    exit 1
fi

fb_bytes="$(stat -c %s "$FB")"
if [ "$fb_bytes" != "$FB_BYTES_EXPECTED" ]; then
    echo "FAIL: fb_bytes=$fb_bytes (want $FB_BYTES_EXPECTED)" >&2
    exit 1
fi

echo "rss_kb=$rss1"
echo "fb_bytes=$fb_bytes"
echo "rom_bytes=$ROM_BYTES"
echo "cgb=$CGB"
echo "determinism=identical (3 runs)"
exit 0
