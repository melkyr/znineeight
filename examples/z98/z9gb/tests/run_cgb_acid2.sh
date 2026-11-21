#!/bin/sh
# run_cgb_acid2.sh — z9gb cgb-acid2 framebuffer golden gate.
#
# Capture is pinned: CGB mode (`--cgb`), frame 120, 160x144 little-endian
# RGB32 (92,160 bytes). The golden is derived from the official
# `mattcurrie/cgb-acid2` v1.1 `img/reference.png` with the CGB 5-bit expansion
# `(c << 3) | (c >> 2)` per channel. The output is compared byte-for-byte
# against `testdata/golden/cgb-acid2.fb` and by SHA-256.
#
# A missing ROM, missing reference image, or missing golden is an explicit
# `SKIP: <path>` (exit 77). No golden is invented here.
#
# Env:
#   ZIG                  compiler (or pass it as the first argument)
#   Z9GB_ROM_DIR         ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_CGB_REFERENCE   official reference.png path (default probe path)
#   Z9GB_BIN             prebuilt CLI (skips the build step)
#   OUT                  scratch dir (default /tmp/z9gb_gate_cgb_acid2)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"

if [ "$#" -gt 0 ]; then
    ZIG="$1"
    shift
else
    ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
fi
OUT="${OUT:-/tmp/z9gb_gate_cgb_acid2}"
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
for cand in "$ROM_DIR/cgb-acid2.gbc" "$ROM_DIR/cgb-acid2/cgb-acid2.gbc"; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done
if [ -z "$ROM" ]; then
    echo "SKIP: $ROM_DIR/cgb-acid2.gbc"
    exit 77
fi

GOLDEN="$Z9DIR/testdata/golden/cgb-acid2.fb"
GOLDEN_SHA="$Z9DIR/testdata/golden/cgb-acid2.sha256"
GOLDEN_WANT="0fba336ce7d7cb4ef76049a4548ff0e7a5147be79fb34bfd266ce7bb71fcf9fd"
FB_SIZE=92160

if [ ! -f "$GOLDEN" ]; then
    echo "SKIP: $GOLDEN"
    exit 77
fi

REFERENCE="${Z9GB_CGB_REFERENCE:-}"
if [ -z "$REFERENCE" ]; then
    for cand in \
        /tmp/phase4_p4_probe/reference/cgb-acid2-reference.png \
        "$Z9DIR/testdata/golden/cgb-acid2-reference.png"
    do
        if [ -f "$cand" ]; then REFERENCE="$cand"; break; fi
    done
fi
if [ -z "$REFERENCE" ] || [ ! -f "$REFERENCE" ]; then
    echo "SKIP: ${REFERENCE:-cgb-acid2-reference.png}"
    exit 77
fi
REFERENCE_SHA="9ea9c262c5383353e77d715d021a0f7c5ccbe438f88082cb225756e50c4fdf01"
if command -v sha256sum >/dev/null 2>&1; then
    ref_got="$(sha256sum "$REFERENCE" | cut -d' ' -f1)"
    if [ "$ref_got" != "$REFERENCE_SHA" ]; then
        echo "FAIL: cgb-acid2 reference sha256 $ref_got (want $REFERENCE_SHA)"
        exit 1
    fi
fi

BIN="${Z9GB_BIN:-}"
if [ -z "$BIN" ]; then
    if [ ! -x "$ZIG" ]; then
        echo "FAIL: compiler not found: $ZIG"
        exit 1
    fi
    mkdir -p "$OUT"
    if ! timeout 300 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$OUT" "$Z9DIR/main.zig" >"$OUT/build.log" 2>&1; then
        echo "FAIL: build failed (see $OUT/build.log)"
        tail -20 "$OUT/build.log" | sed 's/^/  /' >&2
        exit 1
    fi
    # The emitted build recipe defaults to -O0; optimize the host C so the
    # gate is practical. This only touches the scratch tree.
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

FB="$OUT/cgb-acid2.fb"
if ! timeout 300 "$BIN" --headless --cgb --rom "$ROM" --frames 120 --fb-out "$FB" \
    >"$OUT/run.out" 2>"$OUT/run.err"; then
    echo "FAIL: cgb-acid2 emulator run"
    tail -5 "$OUT/run.err" | sed 's/^/  /' >&2
    exit 1
fi

if [ ! -f "$FB" ]; then
    echo "FAIL: cgb-acid2 framebuffer not written"
    exit 1
fi
size="$(stat -c %s "$FB" 2>/dev/null || echo 0)"
if [ "$size" != "$FB_SIZE" ]; then
    echo "FAIL: cgb-acid2 framebuffer size $size (want $FB_SIZE)"
    exit 1
fi

if ! cmp -s "$FB" "$GOLDEN"; then
    echo "FAIL: cgb-acid2 framebuffer differs from golden"
    exit 1
fi

got="$(sha256sum "$FB" | cut -d' ' -f1)"
want="$(sha256sum "$GOLDEN" | cut -d' ' -f1)"
if [ "$got" != "$want" ]; then
    echo "FAIL: cgb-acid2 sha256 $got (want $want)"
    exit 1
fi
if [ "$got" != "$GOLDEN_WANT" ]; then
    echo "FAIL: cgb-acid2 sha256 $got (pinned $GOLDEN_WANT)"
    exit 1
fi
if [ -f "$GOLDEN_SHA" ]; then
    pinned="$(cut -d' ' -f1 "$GOLDEN_SHA")"
    if [ -n "$pinned" ] && [ "$pinned" != "$got" ]; then
        echo "FAIL: cgb-acid2 sha256 $got (pinned $pinned)"
        exit 1
    fi
fi

echo "cgb-acid2: PASS $got"
exit 0
