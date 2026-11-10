#!/bin/sh
# run_blargg.sh — z9gb Blargg serial-verdict hard gate.
#
# Each ROM runs with `--serial --turbo --frames 200000`. PASS requires a
# terminal serial line exactly `Passed` and no `Failed`; hitting the frame cap
# (or the wall-clock timeout) without that verdict is FAIL, never PASS.
#
# Env:
#   ZIG                 compiler (or pass it as the first argument)
#   Z9GB_ROM_DIR        ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_BIN            prebuilt CLI (skips the build step)
#   OUT                 scratch dir (default /tmp/z9gb_gate_blargg)
#   Z9GB_BLARGG_TIMEOUT per-ROM wall-clock seconds (default 900)
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
OUT="${OUT:-/tmp/z9gb_gate_blargg}"
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

check_blargg() {
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
    timeout "${Z9GB_BLARGG_TIMEOUT:-900}" \
        "$BIN" --headless --rom "$rom" --serial --turbo --frames 200000 \
        >"$out" 2>"$err"
    rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "FAIL: $rel (timeout after ${Z9GB_BLARGG_TIMEOUT:-900}s)"
        FAIL=$((FAIL + 1))
        return
    fi
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: $rel (emulator rc=$rc)"
        tail -5 "$err" | sed 's/^/  /' >&2
        FAIL=$((FAIL + 1))
        return
    fi
    clean="$OUT/$tag.clean"
    tr -d '\r' <"$out" >"$clean"
    if grep -qx 'Failed' "$clean"; then
        echo "FAIL: $rel (terminal Failed)"
        FAIL=$((FAIL + 1))
        return
    fi
    if grep -qx 'Passed' "$clean"; then
        echo "PASS: $rel"
        PASS=$((PASS + 1))
        return
    fi
    echo "FAIL: $rel (no terminal Passed before frame cap)"
    FAIL=$((FAIL + 1))
}

for rel in \
    blargg/cpu_instrs/cpu_instrs.gb \
    blargg/instr_timing/instr_timing.gb \
    blargg/mem_timing/mem_timing.gb \
    blargg/interrupt_time/interrupt_time.gb
do
    check_blargg "$rel"
done

echo "blargg: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
if [ "$SKIP" -ne 0 ]; then
    exit 77
fi
exit 0
