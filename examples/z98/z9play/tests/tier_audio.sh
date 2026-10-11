#!/bin/sh
# tier_audio.sh — z9play M4 gate (Task 4): Player core + audio output layer.
#
# Builds z9play with the binding seed recipe under -fsafe, then, for EACH
# fixture, drives the whole M4 player path — decode -> double-buffer PCM ring ->
# the platform `AudioOut` vtable — into the hermetic WAV sink via
# `z9play --wav <in.ogg> <out.wav>` (a small M4-gate subcommand in main.zig; no
# audio device is touched) and asserts:
#
#   1. `--wav` exits 0 and prints `wav: ended ... monotonic=1`, i.e. the Player
#      reached `ended` with no error and `playerPositionMs` never went backwards;
#   2. the sink is a canonical 44-byte-header PCM WAV whose payload byte count
#      equals the M3 golden testdata/expected/<name>.pcm;
#   3. the sink payload matches that golden by TOLERANCE (per-sample max |delta|
#      and RMS LSB): PASS at max |delta| <= 2 and RMS <= 0.1 LSB, consistent with
#      the M3 Task 4 decode result (max 1 LSB / RMS 0.036) and player_test;
#   4. 3x determinism: three `--wav` runs produce byte-identical raw PCM (equal
#      SHA-1).
#
# It also builds and runs tests/oss_test.zig to assert the OSS `/dev/dsp`
# backend reports `error.OpenFailed` cleanly on this device-less host (and, if a
# device IS present, that it opens without crashing). The OSS backend is
# best-effort; the WAV sink is the hermetic gate backend.
#
# Exits non-zero on any failure and prints a PASS/FAIL summary.
# POSIX sh + coreutils + python3 (numeric tolerance compare). Run from anywhere
# (paths resolved from this script).
#
# Env: ZIG  compiler (default the v97 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_audio)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_audio}"
FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
FIXTURES="sine_mono_44100 sine_stereo_44100 sine_stereo_48000 tagged_unicode short"

# Tolerance (LSB): M3 achieved max |delta| = 1 and RMS 0.036; allow a small
# margin for the other fixtures while still rejecting a wrong decode.
MAX_DELTA_BOUND=2
RMS_MILLI_BOUND=100

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 required for the numeric tolerance compare"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== building z9play (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9play/main.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -20 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
PROG="$OUT/prog"
if [ ! -x "$PROG" ]; then
    echo "FAIL: $PROG not built"
    exit 1
fi

echo "== building oss_test (binding recipe, -fsafe) =="
mkdir -p "$OUT/oss"
if ! timeout 120 "$ZIG" -fsafe -o "$OUT/oss" examples/z98/z9play/tests/oss_test.zig >"$OUT/oss/zig.log" 2>&1; then
    echo "FAIL: zig compile oss_test (see $OUT/oss/zig.log)"
    tail -20 "$OUT/oss/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/oss/build_target.sh" linux "$OUT/oss/prog" >"$OUT/oss/build.log" 2>&1; then
    echo "FAIL: target link oss_test (see $OUT/oss/build.log)"
    tail -20 "$OUT/oss/build.log" | sed 's/^/       /'
    exit 1
fi
OSSPROG="$OUT/oss/prog"
if [ ! -x "$OSSPROG" ]; then
    echo "FAIL: $OSSPROG not built"
    exit 1
fi

# payload <wav> <dest> — write the WAV payload (everything after the 44-byte
# canonical header) to <dest>.
payload() { tail -c +45 "$1" > "$2" 2>/dev/null; }

# tolerance <payload> <golden> — print "max_delta=<n> rms_milli=<n>".
tolerance() {
    python3 - "$1" "$2" <<'PY'
import sys, struct, math
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
n = min(len(a), len(b)) // 2
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

echo "== --wav Player -> WAV sink vs golden (tolerance + determinism) =="
for name in $FIXTURES; do
    FIX="$FIXDIR/$name.ogg"
    GOLD="$EXPDIR/$name.pcm"
    WAV="$OUT/$name.wav"
    PCM="$OUT/$name.pcm"

    timeout 300 "$PROG" --wav "$FIX" "$WAV" >"$OUT/$name.out" 2>"$OUT/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "$name: --wav exit 0"
    else
        fail_case "$name: --wav exit 0 (got $rc)"
    fi

    # Completion + position monotonicity, as reported by the player harness.
    if grep -q 'wav: ended ' "$OUT/$name.out" && grep -q 'monotonic=1' "$OUT/$name.out"; then
        pass_case "$name: player ended + position monotonic ($(cat "$OUT/$name.out"))"
    else
        fail_case "$name: player completion/monotonicity not reported ($(cat "$OUT/$name.out"))"
    fi

    # header + size: canonical 44-byte header, payload == golden byte count.
    hdr_ok=1
    [ "$(dd if="$WAV" bs=1 count=4 2>/dev/null)" = "RIFF" ] || hdr_ok=0
    [ "$(dd if="$WAV" bs=1 skip=8 count=4 2>/dev/null)" = "WAVE" ] || hdr_ok=0
    [ "$(dd if="$WAV" bs=1 skip=36 count=4 2>/dev/null)" = "data" ] || hdr_ok=0
    wsz=$(LC_ALL=C wc -c < "$WAV" 2>/dev/null | tr -d ' ')
    gsz=$(LC_ALL=C wc -c < "$GOLD" 2>/dev/null | tr -d ' ')
    [ -n "$wsz" ] && [ "$wsz" -eq $((44 + gsz)) ] || hdr_ok=0
    if [ "$hdr_ok" -eq 1 ]; then
        pass_case "$name: canonical WAV header + payload size ($wsz bytes)"
    else
        fail_case "$name: bad WAV header / payload size (wav=$wsz golden=$gsz)"
    fi

    payload "$WAV" "$PCM"

    # tolerance vs golden.
    tol="$(tolerance "$PCM" "$GOLD")"
    md="$(printf '%s\n' "$tol" | sed -n 's/.*max_delta=\([0-9][0-9]*\).*/\1/p')"
    rmsm="$(printf '%s\n' "$tol" | sed -n 's/.*rms_milli=\([0-9][0-9]*\).*/\1/p')"
    if [ -n "$md" ] && [ -n "$rmsm" ] && [ "$md" -le "$MAX_DELTA_BOUND" ] && [ "$rmsm" -le "$RMS_MILLI_BOUND" ]; then
        pass_case "$name: tolerance max_delta=$md rms_milli=$rmsm (<= $MAX_DELTA_BOUND / $RMS_MILLI_BOUND)"
    else
        fail_case "$name: tolerance out of bound ($tol)"
    fi

    # determinism: two more runs, identical raw PCM SHA-1.
    h1="$(sha1sum "$PCM" | awk '{print $1}')"
    d_ok=1
    i=2
    while [ "$i" -le 3 ]; do
        timeout 300 "$PROG" --wav "$FIX" "$OUT/$name.$i.wav" >/dev/null 2>&1
        payload "$OUT/$name.$i.wav" "$OUT/$name.$i.pcm"
        hx="$(sha1sum "$OUT/$name.$i.pcm" | awk '{print $1}')"
        [ "$hx" = "$h1" ] || d_ok=0
        i=$((i + 1))
    done
    if [ "$d_ok" -eq 1 ]; then
        pass_case "$name: deterministic 3x (sha1=$h1)"
    else
        fail_case "$name: Player output not deterministic"
    fi
done

echo "== OSS /dev/dsp backend (hermetic: OpenFailed when absent) =="
timeout 60 "$OSSPROG" >"$OUT/oss.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "oss_test exit 0"
else
    fail_case "oss_test exit 0 (got $rc)"
fi
if [ -e /dev/dsp ]; then
    echo "info - /dev/dsp present; OSS open not required to fail"
    if grep -q 'open_dev=present' "$OUT/oss.out"; then
        pass_case "OSS opened the present /dev/dsp without crashing"
    else
        fail_case "OSS present-device probe did not report present ($(cat "$OUT/oss.out"))"
    fi
else
    if grep -q 'open_dev=absent' "$OUT/oss.out"; then
        pass_case "OSS open reports error.OpenFailed cleanly (/dev/dsp absent)"
    else
        fail_case "OSS OpenFailed contract violated ($(cat "$OUT/oss.out"))"
    fi
fi

echo
echo "== tier_audio summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_AUDIO FAIL"
    exit 1
fi
echo "TIER_AUDIO PASS"
exit 0
