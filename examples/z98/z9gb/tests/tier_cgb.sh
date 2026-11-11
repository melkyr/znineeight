#!/bin/sh
# tier_cgb.sh — z9gb P4 CGB unit tests and CLI mode gates.
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else the P2 seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_cgb)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
if [ "$#" -gt 0 ]; then shift; fi
OUT="${OUT:-/tmp/z9gb_tier_cgb}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all) ;;
        *)
            echo "usage: tier_cgb.sh <zig> [--all]" >&2
            exit 2
            ;;
    esac
    shift
done

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

run_unit_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/cgb_test"
    mkdir -p "$OUT/$mode/roms"
    if timeout 120 "$ZIG" "$flag" -I "$ROOT/sf/src" -o "$OUT/$mode" "$Z9DIR/tests/cgb_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "cgb $mode emits"
    else
        fail_case "cgb $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "cgb $mode links"
    else
        fail_case "cgb $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" "$OUT/$mode/roms" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "cgb $mode runs"
    else
        fail_case "cgb $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^cgb ok ' "$OUT/$mode/run.out"; then
        pass_case "cgb $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "cgb $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

echo "== CGB mode, VRAM/WRAM banking, type-driven cart RAM =="
run_unit_mode fast -ffast
run_unit_mode safe -fsafe

echo
echo "== CGB CLI --cgb and CgbRequired reporting =="
CLI_DIR="$OUT/cli"
CLI_BIN="$CLI_DIR/z9gb"
mkdir -p "$CLI_DIR/roms"
if timeout 120 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$CLI_DIR" "$Z9DIR/main.zig" >"$CLI_DIR/zig.log" 2>&1; then
    pass_case "cgb cli emits"
else
    fail_case "cgb cli emits"
    tail -20 "$CLI_DIR/zig.log" | sed 's/^/       /'
fi
if [ -f "$CLI_DIR/build_target.sh" ] && sh "$CLI_DIR/build_target.sh" linux "$CLI_BIN" >"$CLI_DIR/build.log" 2>&1; then
    pass_case "cgb cli links"
else
    fail_case "cgb cli links"
    tail -20 "$CLI_DIR/build.log" 2>/dev/null | sed 's/^/       /'
fi

MINI="$Z9DIR/testdata/synth/minimal.gb"
C0_ROM="$CLI_DIR/roms/flag_c0.gb"
C80_ROM="$CLI_DIR/roms/flag_80.gb"
C00_ROM="$CLI_DIR/roms/flag_00.gb"
cp "$MINI" "$C0_ROM"
cp "$MINI" "$C80_ROM"
cp "$MINI" "$C00_ROM"
printf '\300' | dd of="$C0_ROM" bs=1 seek=323 conv=notrunc status=none
printf '\200' | dd of="$C80_ROM" bs=1 seek=323 conv=notrunc status=none

if [ -x "$CLI_BIN" ]; then
    timeout 60 "$CLI_BIN" --headless --frames 0 --rom "$C0_ROM" >"$CLI_DIR/c0.out" 2>"$CLI_DIR/c0.err"
    rc=$?
    if [ "$rc" -eq 2 ] && grep -qxF 'z9gb: CgbRequired' "$CLI_DIR/c0.out"; then
        pass_case "c0 without --cgb prints CgbRequired and exits 2"
    else
        fail_case "c0 without --cgb prints CgbRequired and exits 2 (rc=$rc, out=$(cat "$CLI_DIR/c0.out"))"
    fi

    if timeout 60 "$CLI_BIN" --headless --cgb --frames 0 --rom "$C0_ROM" >"$CLI_DIR/c0_cgb.out" 2>"$CLI_DIR/c0_cgb.err"; then
        pass_case "c0 with --cgb loads"
    else
        fail_case "c0 with --cgb loads"
        tail -20 "$CLI_DIR/c0_cgb.err" | sed 's/^/       /'
    fi

    if timeout 60 "$CLI_BIN" --headless --cgb --frames 0 --rom "$C80_ROM" >"$CLI_DIR/c80_cgb.out" 2>"$CLI_DIR/c80_cgb.err"; then
        pass_case "c80 with --cgb loads"
    else
        fail_case "c80 with --cgb loads"
        tail -20 "$CLI_DIR/c80_cgb.err" | sed 's/^/       /'
    fi

    if timeout 60 "$CLI_BIN" --headless --frames 0 --rom "$C80_ROM" >"$CLI_DIR/c80.out" 2>"$CLI_DIR/c80.err"; then
        pass_case "c80 without --cgb loads DMG"
    else
        fail_case "c80 without --cgb loads DMG"
        tail -20 "$CLI_DIR/c80.err" | sed 's/^/       /'
    fi

    if timeout 60 "$CLI_BIN" --headless --cgb --frames 0 --rom "$C00_ROM" >"$CLI_DIR/c00_cgb.out" 2>"$CLI_DIR/c00_cgb.err"; then
        pass_case "c00 with --cgb loads as CGB hardware DMG compat"
    else
        fail_case "c00 with --cgb loads as CGB hardware DMG compat"
        tail -20 "$CLI_DIR/c00_cgb.err" | sed 's/^/       /'
    fi
fi

echo
echo "== tier_cgb summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_CGB FAIL"
    exit 1
fi
echo "TIER_CGB PASS"
exit 0
