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
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

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

audio_close() {
    off="$1"
    on="$2"
    frames="$3"
    [ -n "$off" ] && [ -n "$on" ] || return 1
    [ "$on" -gt 0 ] || return 1
    if [ "$on" -ge "$off" ]; then delta=$((on - off)); else delta=$((off - on)); fi
    limit=$((frames * 16 + 64))
    [ "$delta" -le "$limit" ]
}
have_win_tools() {
    for t in i686-w64-mingw32-gcc wine; do
        command -v "$t" >/dev/null 2>&1 || return 1
    done
    return 0
}
setup_win_parity() {
    WIN_DIR="$OUT/win_parity"
    EXT_EXE="$WIN_DIR/ext.exe"
    mkdir -p "$WIN_DIR"
    ln -sfn "$Z9DIR" "$WIN_DIR/z9gb"
    if ! sh "$SCRIPT_DIR/tier_dynarec.sh" --emit-ext "$WIN_DIR/ext.zig"; then
        fail_case "cgb dynarec ext harness emit"
        return 1
    fi
    cat >"$WIN_DIR/gcc_o2.sh" <<'SH'
#!/bin/sh
exec i686-w64-mingw32-gcc -O2 "$@"
SH
    chmod +x "$WIN_DIR/gcc_o2.sh"
    if ! EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" CROSS_GCC="$WIN_DIR/gcc_o2.sh" \
        DUMP_TARGET="-osw -ffast -I $ROOT/sf/src" \
        bash "$ROOT/scripts/win32_cross/cross_nocrt.sh" "$ZIG" "$WIN_DIR/ext.zig" \
        "$WIN_DIR/work" "$EXT_EXE" >"$WIN_DIR/build.log" 2>&1; then
        fail_case "cgb dynarec ext harness builds"
        tail -10 "$WIN_DIR/build.log" | sed 's/^/       /'
        return 1
    fi
    WIN_HOME="$OUT/winehome"
    mkdir -p "$WIN_HOME"
    printf 'pcm.!default { type null }\nctl.!default { type null }\n' >"$WIN_HOME/.asoundrc"
    HOME="$WIN_HOME"
    export HOME
    WINEPREFIX="$OUT/wineprefix"
    export WINEPREFIX
    WINEARCH=win32
    export WINEARCH
    WINEDEBUG="${WINEDEBUG:--all}"
    export WINEDEBUG
    wineserver -k >/dev/null 2>&1 || true
    wineboot -u >"$OUT/wineboot.log" 2>&1 || true
    return 0
}
check_pair_prefix() {
    label="$1"
    offpre="$2"
    onpre="$3"
    frames="$4"
    for suffix in serial fb ram proto; do
        if cmp -s "$offpre.$suffix" "$onpre.$suffix"; then
            pass_case "$label $suffix parity"
        else
            fail_case "$label $suffix parity"
        fi
    done
    off_audio="$(sed -n 's/.* audio=\([0-9]*\).*/\1/p' "$offpre.log" | head -1)"
    on_audio="$(sed -n 's/.* audio=\([0-9]*\).*/\1/p' "$onpre.log" | head -1)"
    if audio_close "$off_audio" "$on_audio" "$frames"; then
        pass_case "$label audio count parity (off=$off_audio on=$on_audio)"
    else
        fail_case "$label audio count parity (off=$off_audio on=$on_audio)"
    fi
    if grep -q '^dynarec=on blocks=' "$onpre.log"; then
        blocks="$(sed -n 's/^dynarec=on blocks=\([0-9]*\) executed=\([0-9]*\).*/\1/p' "$onpre.log")"
        execd="$(sed -n 's/^dynarec=on blocks=\([0-9]*\) executed=\([0-9]*\).*/\2/p' "$onpre.log")"
        if [ -n "$blocks" ] && [ "$blocks" -gt 0 ] && [ -n "$execd" ] && [ "$execd" -gt 0 ]; then
            pass_case "$label anti-vacuous dynarec=on blocks=$blocks executed=$execd"
        else
            fail_case "$label anti-vacuous counters"
        fi
    else
        fail_case "$label dynarec=on counter line missing"
    fi
}
run_sound_parity() {
    label="$1"
    rom="$2"
    frames="$3"
    cgb="$4"
    dir="$WIN_DIR/runs/$label"
    rm -rf "$dir"
    mkdir -p "$dir"
    if timeout 900 wine "$EXT_EXE" "$rom" "$frames" "$cgb" 0 0 "$dir/off" >"$dir/off.log" 2>&1 \
        && timeout 900 wine "$EXT_EXE" "$rom" "$frames" "$cgb" 1 0 "$dir/on" >"$dir/on.log" 2>&1; then
        check_pair_prefix "$label" "$dir/off" "$dir/on" "$frames"
        off_status="$(sed -n 's/.* protocol_status=\([-0-9]*\).*/\1/p' "$dir/off.log" | head -1)"
        on_status="$(sed -n 's/.* protocol_status=\([-0-9]*\).*/\1/p' "$dir/on.log" | head -1)"
        if [ "$off_status" = "0" ] && [ "$on_status" = "0" ] \
            && grep -q 'Passed' "$dir/off.proto" && grep -q 'Passed' "$dir/on.proto" \
            && ! grep -q 'Failed' "$dir/off.proto" && ! grep -q 'Failed' "$dir/on.proto"; then
            pass_case "$label memory-protocol Passed (off/on status=0)"
        else
            fail_case "$label memory-protocol Passed (off=$off_status on=$on_status)"
        fi
    else
        fail_case "$label parity runs"
    fi
}
run_acid_cgb_parity() {
    rom="$1"
    golden="$Z9DIR/testdata/golden/cgb-acid2.fb"
    dir="$WIN_DIR/runs/cgb_acid2"
    rm -rf "$dir"
    mkdir -p "$dir"
    if timeout 300 wine "$EXT_EXE" "$rom" 120 1 0 0 "$dir/off" >"$dir/off.log" 2>&1 \
        && timeout 300 wine "$EXT_EXE" "$rom" 120 1 1 0 "$dir/on" >"$dir/on.log" 2>&1; then
        check_pair_prefix cgb_acid2 "$dir/off" "$dir/on" 120
        if [ -f "$golden" ] && cmp -s "$dir/off.fb" "$golden" && cmp -s "$dir/on.fb" "$golden"; then
            pass_case "cgb_acid2 framebuffer golden (off/on)"
        else
            fail_case "cgb_acid2 framebuffer golden (off/on)"
        fi
    else
        fail_case "cgb_acid2 parity runs"
    fi
}

run_cgb_gate() {
    label="$1"
    script="$2"
    gate_out="$OUT/gates/$label"
    mkdir -p "$gate_out"
    if OUT="$gate_out" Z9GB_ROM_DIR="$ROM_DIR" sh "$SCRIPT_DIR/$script" "$ZIG"; then
        pass_case "$label"
    else
        rc=$?
        if [ "$rc" -eq 77 ]; then
            skip_case "$label"
        else
            fail_case "$label"
        fi
    fi
}

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
echo "== P4 CGB hard gates =="
run_cgb_gate cgb-acid2 run_cgb_acid2.sh
run_cgb_gate cgb_sound run_cgb_sound.sh
run_cgb_gate cgb-interrupt-time run_cgb_interrupt_time.sh

echo
echo "== P4 dynarec on/off parity (Win32/Wine) =="
acid_rom=""
for cand in "$ROM_DIR/cgb-acid2.gbc" "$ROM_DIR/cgb-acid2/cgb-acid2.gbc"; do
    if [ -f "$cand" ]; then acid_rom="$cand"; break; fi
done
sound_rom="$ROM_DIR/cgb_sound/cgb_sound.gb"
itime_rom="$ROM_DIR/blargg/interrupt_time/interrupt_time.gb"
par_any=0
[ -n "$acid_rom" ] && par_any=1
[ -f "$sound_rom" ] && par_any=1
[ -f "$itime_rom" ] && par_any=1
if [ "$par_any" = "1" ]; then
    if ! have_win_tools; then
        skip_case "cgb dynarec parity host tools"
    elif setup_win_parity; then
        if [ -n "$acid_rom" ]; then
            run_acid_cgb_parity "$acid_rom"
        fi
        if [ -f "$sound_rom" ]; then
            run_sound_parity cgb_sound "$sound_rom" 200000 1
        fi
        if [ -f "$itime_rom" ]; then
            run_sound_parity cgb_interrupt_time "$itime_rom" 200000 1
        fi
    fi
    if command -v wineserver >/dev/null 2>&1; then
        wineserver -k >/dev/null 2>&1 || true
    fi
fi

echo
echo "== tier_cgb summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_CGB FAIL"
    exit 1
fi
if [ "$SKIPS" -ne 0 ]; then
    echo "TIER_CGB SKIP"
    exit 77
fi
echo "TIER_CGB PASS"
exit 0
