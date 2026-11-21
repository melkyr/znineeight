#!/bin/sh
# run_acid2.sh — z9gb dmg-acid2 framebuffer golden gate.
#
# Capture is pinned: DMG palette (BGP/OBP defaults 0xE4 -> the four canonical
# greens), frame 120, 160x144 little-endian RGB32 (92,160 bytes). The output is
# compared byte-for-byte against `testdata/golden/dmg-acid2.fb` and by SHA-256.
#
# A missing ROM or a missing golden is an explicit `SKIP: <path>` (exit 77).
# No golden is invented here.
#
# Env:
#   ZIG                 compiler (or pass it as the first argument)
#   Z9GB_ROM_DIR        ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_BIN            prebuilt CLI (skips the build step)
#   OUT                 scratch dir (default /tmp/z9gb_gate_acid2)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -gt 0 ]; then
    ZIG="$1"
    shift
else
    ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
fi
OUT="${OUT:-/tmp/z9gb_gate_acid2}"
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

ROM="$ROM_DIR/acid2/dmg-acid2.gb"
GOLDEN="$Z9DIR/testdata/golden/dmg-acid2.fb"
GOLDEN_SHA="$Z9DIR/testdata/golden/dmg-acid2.sha256"
FB_SIZE=92160

if [ ! -f "$ROM" ]; then
    echo "SKIP: $ROM"
    exit 77
fi
if [ ! -f "$GOLDEN" ]; then
    echo "SKIP: $GOLDEN"
    exit 77
fi

BIN="${Z9GB_BIN:-}"
if [ -z "$BIN" ]; then
    if [ ! -x "$ZIG" ]; then
        echo "FAIL: compiler not found: $ZIG"
        exit 1
    fi
    mkdir -p "$OUT"
    if ! timeout 300 "$ZIG" -ffast -o "$OUT" "$Z9DIR/main.zig" >"$OUT/build.log" 2>&1; then
        echo "FAIL: build failed (see $OUT/build.log)"
        tail -20 "$OUT/build.log" | sed 's/^/  /' >&2
        exit 1
    fi
    # The emitted build recipe defaults to -O0; optimize the host C so the
    # multi-minute turbo runs are practical. This only touches the scratch tree.
    if [ -f "$OUT/build_target.sh" ]; then
        sed 's/-O0/-O2/g' "$OUT/build_target.sh" >"$OUT/build_target.sh.tmp" && mv "$OUT/build_target.sh.tmp" "$OUT/build_target.sh"
    fi
    if [ ! -f "$OUT/build_target.sh" ] || ! sh "$OUT/build_target.sh" linux "$OUT/z9gb" >>"$OUT/build.log" 2>&1; then
        echo "FAIL: link failed (see $OUT/build.log)"
        tail -20 "$OUT/build.log" | sed 's/^/  /' >&2
        exit 1
    fi
    BIN="$OUT/z9gb"
fi
if [ ! -x "$BIN" ]; then
    echo "FAIL: CLI not executable: $BIN"
    exit 1
fi

mkdir -p "$OUT"
FB="$OUT/dmg-acid2.fb"
if ! timeout 300 "$BIN" --headless --rom "$ROM" --frames 120 --fb-out "$FB" \
    >"$OUT/run.out" 2>"$OUT/run.err"; then
    echo "FAIL: dmg-acid2 emulator run"
    tail -5 "$OUT/run.err" | sed 's/^/  /' >&2
    exit 1
fi

if [ ! -f "$FB" ]; then
    echo "FAIL: dmg-acid2 framebuffer not written"
    exit 1
fi
size="$(stat -c %s "$FB" 2>/dev/null || echo 0)"
if [ "$size" != "$FB_SIZE" ]; then
    echo "FAIL: dmg-acid2 framebuffer size $size (want $FB_SIZE)"
    exit 1
fi

if ! cmp -s "$FB" "$GOLDEN"; then
    echo "FAIL: dmg-acid2 framebuffer differs from golden"
    exit 1
fi

got="$(sha256sum "$FB" | cut -d' ' -f1)"
want="$(sha256sum "$GOLDEN" | cut -d' ' -f1)"
if [ "$got" != "$want" ]; then
    echo "FAIL: dmg-acid2 sha256 $got (want $want)"
    exit 1
fi
if [ -f "$GOLDEN_SHA" ]; then
    pinned="$(cut -d' ' -f1 "$GOLDEN_SHA")"
    if [ -n "$pinned" ] && [ "$pinned" != "$got" ]; then
        echo "FAIL: dmg-acid2 sha256 $got (pinned $pinned)"
        exit 1
    fi
fi

echo "acid2: PASS $got"
exit 0
