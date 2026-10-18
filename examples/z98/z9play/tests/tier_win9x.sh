#!/bin/sh
# tier_win9x.sh — z9play Win9x default-profile gate: emitted build + Wine smoke.
#
# (a) Emits examples/z98/z9play/main.zig for default `-osw` (9x, no-CRT) and
#     builds it through the *emitted* build_target.sh mingw recipe (NOT the
#     legacy cross_build_run.sh CRT harness). Asserts the recipe is the 9x
#     no-CRT link (-DZIG_NO_CRT, -nostdlib, KERNEL32 + WINMM), the output is a
#     PE32 i386 executable with no unresolved zF_/zT_ program symbols, imports
#     only KERNEL32 + WINMM (never msvcrt), and passes the closed-world
#     scripts/win32_cross/check_win9x_imports.sh 9x whitelist.
#
# (b) Runs the real .exe under Wine with the hermetic WAV sink selected by
#     Z9PLAY_WAV_OUT (so the waveOut device path is never touched) on the
#     sine_stereo_44100 fixture at --volume 100 (the volume mixer is a pure
#     100/100 scale, so the sink is the backend-independent decode payload).
#     The full interactive 2 s playback must exit 0, write a canonical 44-byte
#     WAV whose payload size equals the Linux golden, and match that golden
#     within the M3 tolerance (max |delta| <= 2 LSB, RMS <= 0.1 LSB). A second
#     run must produce byte-identical payload (determinism).
#
# (c) Builds tests/win9x_console_probe.zig for default `-osw` through its own
#     emitted build_target.sh and runs it under Wine inside a pty (`script`),
#     so Wine exposes a console
#     handle. The probe reads the input mode with GetConsoleMode, calls the
#     Win9x console backend's enterRaw -> leaveRaw, and reads the mode back:
#     entered=1, raw_changed=1 (line/echo/processed bits really cleared),
#     restored=1 (the exact original DWORD came back). If Wine provides no
#     console the probe prints nocons=1 and the tier FAILS (does not fake a
#     pass): Wine is present, so this is an unassertable (c), not an absent
#     tool. SKIP-with-reason is only used when wine/mingw is genuinely absent.
#
# Records the `-osw --dump-c89` md5 (stable 2x) in the output.
# Exits non-zero on any failure. POSIX sh + coreutils + python3 + `script`.
# Run from anywhere (paths resolved from this script).
#
# Env: ZIG       compiler (default the M6 post-D1/D2 zig1)
#      OUT       scratch dir (default /tmp/z9play_tier_win9x)
#      WINEPREFIX (default $OUT/wineprefix; Wine creates it on first run)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_win9x}"
FIXNAME="sine_stereo_44100"
FIX="$Z9DIR/testdata/$FIXNAME.ogg"
GOLD="$Z9DIR/testdata/expected/$FIXNAME.pcm"

MAX_DELTA_BOUND=2
RMS_MILLI_BOUND=100

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

normalize_log() {
    nl_esc="$(printf '\033')"
    tr -d '\r' < "$1" 2>/dev/null | sed "s/${nl_esc}\[[0-9;?]*[A-Za-z]//g" | tr -d ' '
}

tolerance() {
    python3 - "$1" "$2" <<'PY'
import sys, struct, math
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
n = min(len(a), len(b)) // 2
if n == 0:
    print("max_delta=999999 rms_milli=999999")
    sys.exit(0)
A = struct.unpack('<%dh' % n, a[:2 * n])
B = struct.unpack('<%dh' % n, b[:2 * n])
md = 0
ss = 0.0
for x, y in zip(A, B):
    d = x - y
    ad = -d if d < 0 else d
    if ad > md:
        md = ad
    ss += float(d) * float(d)
rms = math.sqrt(ss / n)
print("max_delta=%d rms_milli=%d" % (md, int(rms * 1000.0 + 0.5)))
PY
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_m6"
    exit 1
fi

# Absent cross toolchain / Wine is the only SKIP condition in the plan.
MISSING=""
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-nm i686-w64-mingw32-objdump wine; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING="$MISSING $tool"
    fi
done
if [ -n "$MISSING" ]; then
    skip_case "cross toolchain/Wine absent:$MISSING"
    echo
    echo "== tier_win9x summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    echo "TIER_WIN9X SKIP (wine/mingw absent)"
    exit 0
fi

for tool in file script python3 md5sum sha1sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"
WINEPREFIX="${WINEPREFIX:-$OUT/wineprefix}"
export WINEPREFIX

cd "$ROOT" || exit 1

echo "== (a) emit + build z9play (default -osw = 9x no-CRT) =="
EXE="$OUT/z9play.exe"
EMIT="$OUT/emit"
mkdir -p "$EMIT"
timeout 600 "$ZIG" -osw -o "$EMIT" examples/z98/z9play/main.zig \
    >"$OUT/emit.log" 2>&1
EMIT_RC=$?
if [ "$EMIT_RC" -eq 0 ] && [ -f "$EMIT/build_target.sh" ] \
    && grep -q -- '-DZIG_NO_CRT' "$EMIT/build_target.sh" \
    && grep -q -- '-nostdlib' "$EMIT/build_target.sh" \
    && grep -q -- '-lkernel32' "$EMIT/build_target.sh" \
    && grep -q -- '-lwinmm' "$EMIT/build_target.sh"; then
    pass_case "emitted mingw recipe is 9x no-CRT (DZIG_NO_CRT, nostdlib, kernel32+winmm)"
else
    fail_case "emit failed or build_target.sh is not the 9x no-CRT recipe (rc=$EMIT_RC; see $OUT/emit.log)"
fi
tail -5 "$OUT/emit.log" | sed 's/^/       /'

if sh "$EMIT/build_target.sh" mingw "$EXE" >"$OUT/build.log" 2>&1 && [ -f "$EXE" ]; then
    pass_case "emitted build_target.sh mingw produced exe ($(LC_ALL=C wc -c <"$EXE" | tr -d ' ') bytes)"
else
    fail_case "emitted build failed (see $OUT/build.log)"
fi
tail -3 "$OUT/build.log" | sed 's/^/       /'

FILEOUT="$(file "$EXE" 2>/dev/null)"
case "$FILEOUT" in
    *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
    *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
esac

# i386 PE symbols are underscore-prefixed (`U _zF_...`), so allow an optional
# leading `_` or an unresolved program symbol would slip through this filter.
UNDEF="$(i686-w64-mingw32-nm -u "$EXE" 2>/dev/null | awk '{print $NF}' | grep -E '^_?z[FT]_' || true)"
if [ -z "$UNDEF" ]; then
    pass_case "no unresolved zF_/zT_ program symbols"
else
    fail_case "unresolved program symbols: $(printf '%s ' $UNDEF)"
fi

IMPORTS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
    | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p' | tr -d '\r' \
    | tr '[:lower:]' '[:upper:]' | sort -u | tr '\n' ' ')"
if [ "$IMPORTS" = "KERNEL32.DLL WINMM.DLL " ]; then
    pass_case "imports are exactly KERNEL32 + WINMM (no msvcrt)"
else
    fail_case "import set is not exactly KERNEL32+WINMM: $(printf '%s' "$IMPORTS")"
fi

if bash "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$EXE" 9x \
    >"$OUT/imports.log" 2>&1; then
    pass_case "check_win9x_imports.sh 9x whitelist PASS"
else
    fail_case "check_win9x_imports.sh 9x whitelist FAILED (see $OUT/imports.log)"
fi
tail -3 "$OUT/imports.log" | sed 's/^/       /'

echo "== (a) -osw --dump-c89 md5 (stable 2x) =="
timeout 300 "$ZIG" -osw --dump-c89 examples/z98/z9play/main.zig \
    >"$OUT/dump1.c89" 2>"$OUT/dump1.err"
RC1=$?
timeout 300 "$ZIG" -osw --dump-c89 examples/z98/z9play/main.zig \
    >"$OUT/dump2.c89" 2>"$OUT/dump2.err"
RC2=$?
MD1="$(md5sum "$OUT/dump1.c89" 2>/dev/null | awk '{print $1}')"
MD2="$(md5sum "$OUT/dump2.c89" 2>/dev/null | awk '{print $1}')"
echo "--dump-c89 (-osw) md5: ${MD1:-<none>}"
if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] && [ -n "$MD1" ] && [ "$MD1" = "$MD2" ]; then
    pass_case "-osw --dump-c89 md5 recorded stable 2x: $MD1"
else
    fail_case "-osw --dump-c89 failed/unstable (rc=$RC1/$RC2 md5=$MD1/$MD2)"
fi

echo "== (b) Wine: WAV sink vs Linux golden (tolerance + determinism) =="
# `script -c` runs the command through another shell, which would eat the
# backslashes in a `Z:\...` path; `Z:/...` is equally valid to Wine and safe.
if command -v winepath >/dev/null 2>&1; then
    FIXWIN="$(WINEDEBUG=-all winepath -w "$FIX" 2>/dev/null | tr '\\' '/')"
else
    FIXWIN="$FIX"
fi
if [ -z "$FIXWIN" ]; then
    FIXWIN="$FIX"
fi

run_wine_play() {
    rw_wav="$1"
    rw_log="$2"
    if command -v winepath >/dev/null 2>&1; then
        rw_win="$(WINEDEBUG=-all winepath -w "$rw_wav" 2>/dev/null | tr '\\' '/')"
    else
        rw_win="$rw_wav"
    fi
    if [ -z "$rw_win" ]; then
        rw_win="$rw_wav"
    fi
    Z9PLAY_WAV_OUT="$rw_win" WINEDEBUG=-all timeout 120 \
        script -qec "exec wine $EXE --volume 100 $FIXWIN" /dev/null \
        </dev/null >"$rw_log" 2>&1
}

WAV1="$OUT/$FIXNAME.1.wav"
run_wine_play "$WAV1" "$OUT/wine1.log"
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "Wine full playback exit 0"
else
    fail_case "Wine full playback exit 0 (got $rc; see $OUT/wine1.log)"
fi
normalize_log "$OUT/wine1.log" >"$OUT/wine1.norm"
if grep -q 'Stoppedat00:02\.' "$OUT/wine1.norm"; then
    pass_case "Wine playback reached the end (Stopped at 00:02.)"
else
    fail_case "Wine playback did not report the expected end (see $OUT/wine1.norm)"
fi

hdr_ok=1
[ "$(dd if="$WAV1" bs=1 count=4 2>/dev/null)" = "RIFF" ] || hdr_ok=0
[ "$(dd if="$WAV1" bs=1 skip=8 count=4 2>/dev/null)" = "WAVE" ] || hdr_ok=0
[ "$(dd if="$WAV1" bs=1 skip=36 count=4 2>/dev/null)" = "data" ] || hdr_ok=0
wsz=$(LC_ALL=C wc -c <"$WAV1" 2>/dev/null | tr -d ' ')
gsz=$(LC_ALL=C wc -c <"$GOLD" 2>/dev/null | tr -d ' ')
[ -n "$wsz" ] && [ "$wsz" -eq $((44 + gsz)) ] || hdr_ok=0
if [ "$hdr_ok" -eq 1 ]; then
    pass_case "canonical WAV header + payload size ($wsz bytes = 44 + $gsz)"
else
    fail_case "bad WAV header / payload size (wav=$wsz golden=$gsz)"
fi

PCM1="$OUT/$FIXNAME.1.pcm"
tail -c +45 "$WAV1" >"$PCM1" 2>/dev/null
tol="$(tolerance "$PCM1" "$GOLD")"
md="$(printf '%s\n' "$tol" | sed -n 's/.*max_delta=\([0-9][0-9]*\).*/\1/p')"
rmsm="$(printf '%s\n' "$tol" | sed -n 's/.*rms_milli=\([0-9][0-9]*\).*/\1/p')"
if [ -n "$md" ] && [ -n "$rmsm" ] && [ "$md" -le "$MAX_DELTA_BOUND" ] && [ "$rmsm" -le "$RMS_MILLI_BOUND" ]; then
    pass_case "Wine WAV parity max_delta=$md rms_milli=$rmsm (<= $MAX_DELTA_BOUND / $RMS_MILLI_BOUND)"
else
    fail_case "Wine WAV parity out of bound ($tol)"
fi

WAV2="$OUT/$FIXNAME.2.wav"
run_wine_play "$WAV2" "$OUT/wine2.log"
rc=$?
PCM2="$OUT/$FIXNAME.2.pcm"
tail -c +45 "$WAV2" >"$PCM2" 2>/dev/null
h1="$(sha1sum "$PCM1" 2>/dev/null | awk '{print $1}')"
h2="$(sha1sum "$PCM2" 2>/dev/null | awk '{print $1}')"
if [ "$rc" -eq 0 ] && [ -n "$h1" ] && [ "$h1" = "$h2" ]; then
    pass_case "Wine output deterministic 2x (sha1=$h1)"
else
    fail_case "Wine output not deterministic (rc=$rc sha1=$h1/$h2)"
fi

echo "== (c) Win9x console raw-mode restore under Wine (probe, pty) =="
PROBE="$OUT/win9x_console_probe.exe"
PROBE_EMIT="$OUT/probe_emit"
mkdir -p "$PROBE_EMIT"
timeout 600 "$ZIG" -osw -o "$PROBE_EMIT" examples/z98/z9play/tests/win9x_console_probe.zig \
    >"$OUT/probe_emit.log" 2>&1
if [ $? -eq 0 ] && [ -f "$PROBE_EMIT/build_target.sh" ] \
    && sh "$PROBE_EMIT/build_target.sh" mingw "$PROBE" >"$OUT/probe_build.log" 2>&1 \
    && [ -f "$PROBE" ]; then
    pass_case "console probe emitted no-CRT build produced exe"
else
    fail_case "console probe emit/build failed (see $OUT/probe_emit.log, $OUT/probe_build.log)"
fi
tail -3 "$OUT/probe_build.log" | sed 's/^/       /'

timeout 90 script -qec "exec wine $PROBE" /dev/null \
    </dev/null >"$OUT/probe.log" 2>&1
rc=$?
normalize_log "$OUT/probe.log" >"$OUT/probe.norm"
if [ "$rc" -eq 0 ] && grep -q 'win9x_console_probe:entered=1,raw_changed=1,restored=1' "$OUT/probe.norm"; then
    line="$(grep -o 'win9x_console_probe:.*' "$OUT/probe.norm" | head -1)"
    pass_case "raw-mode restore asserted under Wine ($line)"
elif grep -q 'win9x_console_probe:nocons=1' "$OUT/probe.norm"; then
    fail_case "Wine provided no console handle; raw-mode restore unassertable (no fake pass)"
else
    fail_case "console probe did not report restore=1 (rc=$rc; see $OUT/probe.norm)"
fi

echo
echo "== tier_win9x summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_WIN9X FAIL"
    exit 1
fi
echo "TIER_WIN9X PASS"
exit 0
