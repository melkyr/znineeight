#!/bin/sh
# tier_smoke.sh — z9gb P1 gate: platform table + headless backend.
#
# Task 1 scope: both platform modules must dump cleanly, appear in the emitted
# C, and pull in no Win32/DirectX header. main.zig arrives in Task 2; this
# script is extended there to build the CLI and check the deterministic
# framebuffer.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_smoke)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_tier_smoke}"

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

# Dump one module to stdout (module-only C, no runtime PAL) and assert that
# its entry symbol appears and that it imports no Win32/DirectX header.
dump_module() {
    label="$1"
    src="$2"
    marker="$3"
    dump="$OUT/$label.c"
    if timeout 120 "$ZIG" -ffast --dump-c89 "$src" >"$dump" 2>"$OUT/$label.err"; then
        pass_case "$label dumps (rc=0)"
    else
        fail_case "$label dumps (rc=0)"
        tail -20 "$OUT/$label.err" | sed 's/^/       /'
        return
    fi
    if grep -q "$marker" "$dump"; then
        pass_case "$label appears in the dump ($marker)"
    else
        fail_case "$label appears in the dump ($marker)"
    fi
    if grep -Eq 'windows\.h|ddraw\.h|dsound\.h|dinput\.h|d3d[0-9]*\.h' "$dump"; then
        fail_case "$label imports no Win32/DirectX header"
    else
        pass_case "$label imports no Win32/DirectX header"
    fi
}

cd "$ROOT" || exit 1
dump_module backend examples/z98/z9gb/platform/backend.zig platformNoop
dump_module headless examples/z98/z9gb/platform/headless.zig platformHeadless

# ---- Task 2: deterministic headless frame gate -------------------------
# Build the CLI once it exists (Task 2), run two frames headless, and verify
# the exact 92,160-byte little-endian framebuffer dump. Until main.zig and
# emu.zig exist this section fails, as required.
BIN="$OUT/z9gb"
FB="/tmp/z9gb_p1.fb"
rm -f "$FB"

echo
echo "== building z9gb (headless CLI) =="
if timeout 120 "$ZIG" -ffast -o "$OUT" examples/z98/z9gb/main.zig >"$OUT/z9gb_zig.log" 2>&1; then
    pass_case "z9gb emits (rc=0)"
else
    fail_case "z9gb emits (rc=0)"
    [ -f "$OUT/z9gb_zig.log" ] && tail -20 "$OUT/z9gb_zig.log" | sed 's/^/       /'
fi
if [ -f "$OUT/build_target.sh" ] && sh "$OUT/build_target.sh" linux "$BIN" >"$OUT/z9gb_build.log" 2>&1; then
    pass_case "z9gb links (rc=0)"
else
    fail_case "z9gb links (rc=0)"
    [ -f "$OUT/z9gb_build.log" ] && tail -20 "$OUT/z9gb_build.log" | sed 's/^/       /'
fi

if [ -x "$BIN" ] && timeout 60 "$BIN" --headless --frames 2 --fb-out "$FB" >"$OUT/z9gb_run.out" 2>"$OUT/z9gb_run.err"; then
    pass_case "z9gb --headless --frames 2 --fb-out exits 0"
else
    fail_case "z9gb --headless --frames 2 --fb-out exits 0"
    [ -f "$OUT/z9gb_run.err" ] && tail -20 "$OUT/z9gb_run.err" | sed 's/^/       /'
fi

# check_word <label> <byte-offset> <expected little-endian u32>
check_word() {
    label="$1"
    off="$2"
    want="$3"
    if [ -f "$FB" ]; then
        got="$(od -An -tx4 -j "$off" -N4 "$FB" | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
        if [ "$got" = "$want" ]; then
            pass_case "$label ($got)"
        else
            fail_case "$label (want $want, got $got)"
        fi
    else
        fail_case "$label (missing $FB)"
    fi
}

if [ -f "$FB" ]; then
    size="$(stat -c %s "$FB")"
    if [ "$size" = "92160" ]; then
        pass_case "framebuffer dump is 92160 bytes"
    else
        fail_case "framebuffer dump is 92160 bytes (got $size)"
    fi
    if echo "54c0af1aa8cee3642b6f1c4a24831e89  $FB" | md5sum -c - >"$OUT/z9gb_md5.log" 2>&1; then
        pass_case "framebuffer md5 matches golden"
    else
        fail_case "framebuffer md5 matches golden"
        tail -5 "$OUT/z9gb_md5.log" | sed 's/^/       /'
    fi
else
    fail_case "framebuffer dump is 92160 bytes (missing $FB)"
    fail_case "framebuffer md5 matches golden (missing $FB)"
fi

check_word "first pixel" 0 00010000
check_word "middle pixel" 46400 00014850
check_word "last pixel" 92156 00018F9F

# ---- Task 5: --frames defaults to unlimited ----------------------------
# Absent --frames (and --frames 0) must keep running until the process is
# terminated; a finite count still exits 0 after that many frames.
SYNTH="$Z9DIR/testdata/synth/minimal.gb"
echo
echo "== frames default (unlimited) =="
if [ -x "$BIN" ]; then
    timeout 3 "$BIN" --headless --rom "$SYNTH" >"$OUT/frames_absent.out" 2>"$OUT/frames_absent.err"
    rc=$?
    if [ "$rc" -eq 124 ]; then
        pass_case "no --frames runs until terminated (timeout 124)"
    else
        fail_case "no --frames runs until terminated (rc=$rc)"
        tail -20 "$OUT/frames_absent.err" | sed 's/^/       /'
    fi

    timeout 60 "$BIN" --headless --frames 2 --rom "$SYNTH" >"$OUT/frames_two.out" 2>"$OUT/frames_two.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "--frames 2 exits 0"
    else
        fail_case "--frames 2 exits 0 (rc=$rc)"
        tail -20 "$OUT/frames_two.err" | sed 's/^/       /'
    fi

    timeout 3 "$BIN" --headless --frames 0 --rom "$SYNTH" >"$OUT/frames_zero.out" 2>"$OUT/frames_zero.err"
    rc=$?
    if [ "$rc" -eq 124 ]; then
        pass_case "--frames 0 runs until terminated (timeout 124)"
    else
        fail_case "--frames 0 runs until terminated (rc=$rc)"
        tail -20 "$OUT/frames_zero.err" | sed 's/^/       /'
    fi
else
    fail_case "no --frames runs until terminated (missing $BIN)"
    fail_case "--frames 2 exits 0 (missing $BIN)"
    fail_case "--frames 0 runs until terminated (missing $BIN)"
fi

# ---- fix round 1: 8 MiB ROM cap boundary -------------------------------
# emuLoadRom must reject anything above 8 MiB after comparing the full i64 file
# size, before narrowing to the 32-bit usize. The 4 GiB sparse case is the
# regression guard for the truncating narrow (exactly 4 GiB used to become 0).
ROM_OK="$OUT/rom_8m.bin"
ROM_OVER="$OUT/rom_8m_plus1.bin"
ROM_HUGE="$OUT/rom_4g_sparse.bin"
dd if=/dev/zero of="$ROM_OK" bs=1048576 count=8 >/dev/null 2>&1
dd if=/dev/zero of="$ROM_OVER" bs=1048576 count=8 >/dev/null 2>&1
printf 'x' >>"$ROM_OVER"

if [ -x "$BIN" ] && timeout 60 "$BIN" --headless --frames 1 --rom "$ROM_OK" >/dev/null 2>&1; then
    pass_case "exactly 8 MiB ROM accepted"
else
    fail_case "exactly 8 MiB ROM accepted"
fi

if [ -x "$BIN" ] && timeout 60 "$BIN" --headless --frames 1 --rom "$ROM_OVER" >"$OUT/rom_over.err" 2>&1; then
    fail_case "8 MiB + 1 ROM rejected (exited 0)"
else
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q "ROM too large" "$OUT/rom_over.err"; then
        pass_case "8 MiB + 1 ROM rejected (RomTooLarge)"
    else
        fail_case "8 MiB + 1 ROM rejected (rc=$rc)"
    fi
fi

if command -v truncate >/dev/null 2>&1; then
    truncate -s 4294967296 "$ROM_HUGE"
    if [ -x "$BIN" ] && timeout 60 "$BIN" --headless --frames 1 --rom "$ROM_HUGE" >"$OUT/rom_huge.err" 2>&1; then
        fail_case "4 GiB sparse ROM rejected (exited 0)"
    else
        rc=$?
        if [ "$rc" -eq 2 ] && grep -q "ROM too large" "$OUT/rom_huge.err"; then
            pass_case "4 GiB sparse ROM rejected (RomTooLarge)"
        else
            fail_case "4 GiB sparse ROM rejected (rc=$rc)"
        fi
    fi
    rm -f "$ROM_HUGE"
fi

rm -f "$ROM_OK" "$ROM_OVER"

# ---- Task 3: RSS accounting + repeated-run determinism -----------------
# measure_rss.sh builds the CLI, runs 60 headless frames under /usr/bin/time,
# checks rss_kb is positive and below 12000, and checks three framebuffer dumps
# are byte-identical. Exit 77 means /usr/bin/time is unavailable (skip).
echo
echo "== measuring RSS and determinism =="
if sh "$SCRIPT_DIR/measure_rss.sh" "$ZIG" "$OUT/measure_rss" >"$OUT/measure_rss.log" 2>&1; then
    sed 's/^/ok   - /' "$OUT/measure_rss.log"
    PASSES=$((PASSES + 1))
else
    rc=$?
    if [ "$rc" -eq 77 ]; then
        pass_case "measure_rss skipped (/usr/bin/time unavailable)"
    else
        fail_case "measure_rss: rss_kb positive, < 12000, 3 runs identical"
        tail -30 "$OUT/measure_rss.log" | sed 's/^/       /'
    fi
fi

echo
echo "== tier_smoke summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_SMOKE FAIL"
    exit 1
fi
echo "TIER_SMOKE PASS"
exit 0
