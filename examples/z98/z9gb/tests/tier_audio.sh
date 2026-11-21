#!/bin/sh
# tier_audio.sh — z9gb P3 APU unit tests and the dmg_sound hard gate.
#
# Usage:
#   sh tier_audio.sh [ZIG]          run the APU unit tests, then the gate
#   sh tier_audio.sh --gate [ZIG]   run only the dmg_sound hard gate
#
# Env:
#   ZIG          compiler (first positional arg, else $ZIG, else the seed path)
#   OUT          scratch dir (default /tmp/z9gb_tier_audio)
#   Z9GB_ROM_DIR ROM root (default /tmp/z9gb_roms, else testdata/roms)
#
# Verdict: the pinned Blargg dmg_sound ROM reports through its documented
# memory protocol ($A000 status, $DE,$B0,$61 signature, $A004 text), not
# through the serial port (the ROM contains no SB/SC accesses). The gate reads
# that protocol directly and requires status 0, a terminal "Passed", and no
# "Failed" before the 200,000-frame cap. A missing ROM is SKIP (exit 77).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9gb_tier_audio}"

MODE=all
while [ "$#" -gt 0 ]; do
    case "$1" in
        --gate) MODE=gate ;;
        --unit) MODE=unit ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) ZIG="$1" ;;
    esac
    shift
done

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
ln -s "$Z9DIR" "$OUT/z9gb"

if [ -n "${Z9GB_ROM_DIR:-}" ]; then
    ROM_DIR="$Z9GB_ROM_DIR"
elif [ -d /tmp/z9gb_roms ]; then
    ROM_DIR=/tmp/z9gb_roms
elif [ -d "$Z9DIR/testdata/roms" ]; then
    ROM_DIR="$Z9DIR/testdata/roms"
else
    ROM_DIR=/tmp/z9gb_roms
fi
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }
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
        fail_case "audio dynarec ext harness emit"
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
        fail_case "audio dynarec ext harness builds"
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
    if [ ! -f "$rom" ]; then
        skip_case "$label (missing $rom)"
        return
    fi
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

run_unit_mode() {

    mode="$1"
    flag="$2"
    bin="$OUT/$mode/apu_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -I "$ROOT/sf/src" -o "$OUT/$mode" "$Z9DIR/tests/apu_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "apu $mode emits"
    else
        fail_case "apu $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "apu $mode links"
    else
        fail_case "apu $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 120 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "apu $mode runs"
    else
        fail_case "apu $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^apu ok ' "$OUT/$mode/run.out"; then
        pass_case "apu $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "apu $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

run_unit() {
    echo "== APU unit tests (-ffast and -fsafe) =="
    run_unit_mode fast -ffast
    run_unit_mode safe -fsafe
}

# Memory-protocol verdict runner (the pinned ROM has no serial output).
cat >"$OUT/gate.zig" <<'ZIG'
const std = @import("std");
const emumod = @import("z9gb/emu.zig");
const mmumod = @import("z9gb/mmu.zig");

var g_emu: emumod.Emu = undefined;
var g_text: [1024]u8 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn readMem(addr: u16) u8 {
    return mmumod.read8(&g_emu.bus, addr);
}

fn hasWord(text: []const u8, word: []const u8) bool {
    if (word.len == 0 or text.len < word.len) return false;
    var i: usize = 0;
    while (i + word.len <= text.len) : (i += 1) {
        var j: usize = 0;
        var ok: bool = true;
        while (j < word.len) : (j += 1) {
            if (text[i + j] != word[j]) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 2) std.os.exit(2);
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = false });
    emumod.emuLoadRom(&g_emu, argAt(argv, 1)) catch {
        std.io.write("GATE_FAIL load\n");
        std.os.exit(1);
    };
    emumod.emuReset(&g_emu);
    var f: u32 = 0;
    while (f < 200000) : (f += 1) {
        _ = emumod.emuRunFrame(&g_emu);
        const magic: bool = readMem(0xA001) == 0xDE and readMem(0xA002) == 0xB0 and readMem(0xA003) == 0x61;
        if (!magic) continue;
        const status: u8 = readMem(0xA000);
        if (status == 0x80 or status == 0xFF) continue;

        var len: usize = 0;
        while (len < g_text.len) : (len += 1) {
            const c: u8 = readMem(@intCast(u16, 0xA004 + len));
            if (c == 0) break;
            g_text[len] = c;
        }
        std.io.write(g_text[0..len]);
        std.io.write("\n");
        const text: []const u8 = g_text[0..len];
        const failed: bool = hasWord(text, "Failed");
        const passed: bool = hasWord(text, "Passed");
        std.io.write("frames=");
        std.io.printInt(@intCast(i32, f & 0x7fffffff));
        std.io.write(" status=");
        std.io.printInt(@intCast(i32, status));
        std.io.write("\n");
        if (status == 0 and passed and !failed) {
            std.io.write("GATE_PASS\n");
            std.os.exit(0);
        }
        std.io.write("GATE_FAIL\n");
        std.os.exit(1);
    }
    std.io.write("GATE_FAIL timeout\n");
    std.os.exit(1);
}
ZIG

run_gate() {
    echo
    echo "== dmg_sound hard gate =="
    rom=""
    for cand in \
        "$ROM_DIR/dmg_sound/dmg_sound.gb" \
        "$ROM_DIR/blargg/dmg_sound/dmg_sound.gb"
    do
        if [ -f "$cand" ]; then rom="$cand"; break; fi
    done
    if [ -z "$rom" ]; then
        echo "SKIP: dmg_sound/dmg_sound.gb under $ROM_DIR"
        SKIPS=$((SKIPS + 1))
        return
    fi
    want="$(awk '$2 == "dmg_sound/dmg_sound.gb" { print $1; exit }' \
        "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
    if [ -z "$want" ]; then
        fail_case "dmg_sound manifest row missing"
        return
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        got="$(sha256sum "$rom" | cut -d' ' -f1)"
        if [ "$got" != "$want" ]; then
            fail_case "dmg_sound sha256 mismatch (got $got, want $want)"
            return
        fi
        echo "       sha256 $got"
    else
        echo "       sha256sum unavailable; hash not re-checked"
    fi
    mkdir -p "$OUT/gate-build"
    if timeout 120 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$OUT/gate-build" "$OUT/gate.zig" >"$OUT/gate_zig.log" 2>&1; then
        pass_case "dmg_sound gate emits"
    else
        fail_case "dmg_sound gate emits"
        tail -20 "$OUT/gate_zig.log" | sed 's/^/       /'
        return
    fi
    if [ -f "$OUT/gate-build/build_target.sh" ]; then
        sed 's/-O0/-O2/g' "$OUT/gate-build/build_target.sh" >"$OUT/gate-build/build_target.sh.tmp" && mv "$OUT/gate-build/build_target.sh.tmp" "$OUT/gate-build/build_target.sh"
    fi
    if [ ! -f "$OUT/gate-build/build_target.sh" ] || ! sh "$OUT/gate-build/build_target.sh" linux "$OUT/gate-build/dmg_sound_gate" >"$OUT/gate_build.log" 2>&1; then
        fail_case "dmg_sound gate links"
        tail -20 "$OUT/gate_build.log" | sed 's/^/       /'
        return
    fi
    if timeout 300 "$OUT/gate-build/dmg_sound_gate" "$rom" >"$OUT/gate.out" 2>"$OUT/gate.err"; then
        grep -E 'GATE_PASS|Passed|status=|frames=' "$OUT/gate.out" | sed 's/^/       /'
        pass_case "dmg_sound Passed"
    else
        rc=$?
        grep -E 'GATE_FAIL|Failed|status=|frames=' "$OUT/gate.out" | sed 's/^/       /'
        if [ "$rc" -eq 124 ]; then
            fail_case "dmg_sound (wall-clock timeout)"
        else
            fail_case "dmg_sound (no terminal Passed before frame cap)"
        fi
        tail -10 "$OUT/gate.err" | sed 's/^/       /'
    fi
}

cd "$ROOT" || exit 1

if [ "$MODE" = "all" ] || [ "$MODE" = "unit" ]; then
    run_unit
fi
if [ "$MODE" = "all" ] || [ "$MODE" = "gate" ]; then
    run_gate
    par_rom=""
    for cand in \
        "$ROM_DIR/dmg_sound/dmg_sound.gb" \
        "$ROM_DIR/blargg/dmg_sound/dmg_sound.gb"
    do
        if [ -f "$cand" ]; then par_rom="$cand"; break; fi
    done
    if [ -n "$par_rom" ]; then
        if ! have_win_tools; then
            skip_case "audio dynarec parity host tools"
        elif setup_win_parity; then
            run_sound_parity dmg_sound "$par_rom" 200000 0
        fi
    fi
    if command -v wineserver >/dev/null 2>&1; then
        wineserver -k >/dev/null 2>&1 || true
    fi
fi

echo
echo "== tier_audio summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_AUDIO FAIL"
    exit 1
fi
if [ "$SKIPS" -ne 0 ]; then
    echo "TIER_AUDIO SKIP"
    exit 77
fi
echo "TIER_AUDIO PASS"
exit 0
