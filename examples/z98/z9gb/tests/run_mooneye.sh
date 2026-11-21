#!/bin/sh
# run_mooneye.sh — z9gb Mooneye magic-breakpoint hard gate.
#
# Each ROM runs with `--mooneye --frames 60000`. The emulator stops when the
# next opcode is `LD B,B` (0x40) and reports the full register signature. PASS
# requires B=3 C=5 D=8 E=13 H=21 L=34; any other state or a missing breakpoint
# before the frame cap is FAIL.
#
# Env:
#   ZIG                 compiler (or pass it as the first argument)
#   Z9GB_ROM_DIR        ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_BIN            prebuilt CLI (skips the build step)
#   OUT                 scratch dir (default /tmp/z9gb_gate_mooneye)
#   Z9GB_MOONEYE_TIMEOUT per-ROM wall-clock seconds (default 300)
#
# A missing ROM prints `SKIP: <path>`; exit 0 = all PASS, 1 = any FAIL,
# 77 = no FAIL but at least one SKIP.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -gt 0 ]; then
    ZIG="$1"
    shift
else
    ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
fi
OUT="${OUT:-/tmp/z9gb_gate_mooneye}"
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

PASS=0
FAIL=0
SKIP=0
PASS_SIG='mooneye: PASS B=3 C=5 D=8 E=13 H=21 L=34'

check_mooneye() {
    rel="$1"
    rom="$ROM_DIR/$rel"
    if [ ! -f "$rom" ]; then
        echo "SKIP: $rom"
        SKIP=$((SKIP + 1))
        return
    fi
    tag="$(echo "$rel" | tr '/' '_')"
    out="$OUT/$tag.out"
    err="$OUT/$tag.err"
    timeout "${Z9GB_MOONEYE_TIMEOUT:-300}" \
        "$BIN" --headless --rom "$rom" --mooneye --frames 60000 \
        >"$out" 2>"$err"
    rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "FAIL: $rel (timeout after ${Z9GB_MOONEYE_TIMEOUT:-300}s)"
        FAIL=$((FAIL + 1))
        return
    fi
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: $rel (emulator rc=$rc)"
        tail -5 "$err" | sed 's/^/  /' >&2
        FAIL=$((FAIL + 1))
        return
    fi
    if grep -qxF "$PASS_SIG" "$out"; then
        echo "PASS: $rel"
        PASS=$((PASS + 1))
        return
    fi
    echo "FAIL: $rel (signature mismatch or no breakpoint)"
    grep -E '^mooneye: ' "$out" | tail -1 | sed 's/^/  /' >&2
    FAIL=$((FAIL + 1))
}

for rel in \
    mooneye/acceptance/timer/div_write.gb \
    mooneye/acceptance/timer/tim00.gb \
    mooneye/acceptance/timer/tim01.gb \
    mooneye/acceptance/timer/tim10.gb \
    mooneye/acceptance/timer/tim11.gb \
    mooneye/emulator-only/mbc1/bits_bank1.gb \
    mooneye/emulator-only/mbc1/bits_bank2.gb \
    mooneye/emulator-only/mbc1/bits_mode.gb \
    mooneye/emulator-only/mbc1/bits_ramg.gb \
    mooneye/emulator-only/mbc1/rom_2Mb.gb \
    mooneye/emulator-only/mbc1/rom_4Mb.gb \
    mooneye/emulator-only/mbc1/ram_256kb.gb \
    mooneye/acceptance/ppu/lcdon_timing-GS.gb \
    mooneye/acceptance/ppu/stat_irq_blocking.gb \
    mooneye/acceptance/oam_dma/basic.gb
do
    check_mooneye "$rel"
done

echo "mooneye: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
if [ "$SKIP" -ne 0 ]; then
    exit 77
fi
exit 0
