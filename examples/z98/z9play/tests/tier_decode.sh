#!/bin/sh
# tier_decode.sh — z9play M3 gate (Task 5): `z9play --pcm` decode vs golden PCM.
#
# Builds z9play with the binding seed recipe under -fsafe, then for EACH fixture:
#   1. asserts `--pcm <in.ogg> <out.wav>` exits 0 and writes a canonical
#      44-byte-header PCM WAV (RIFF/WAVE, 16-bit, the fixture's channels/rate);
#      the `data` chunk size must equal the golden raw-PCM byte count;
#   2. compares the WAV payload (bytes after the header) to the oggdec golden
#      testdata/expected/<name>.pcm by TOLERANCE (per-sample max |delta| and RMS
#      LSB); PASS at max |delta| <= 2 and RMS <= 0.1 LSB, consistent with the
#      M3 Task 4 decode_test result (max 1 LSB / RMS 0.036);
#   3. asserts 3x determinism: three `--pcm` runs produce byte-identical raw PCM
#      (identical SHA-1);
#   4. reports the exact-match SHA-1 of the payload vs the golden as
#      INFORMATIONAL only (a correct float decoder need not be bit-identical to
#      libvorbis; the plan's Gate Note makes exact equality a stretch target);
#   5. NON-VACUOUS negatives: a malformed argument (missing output path) exits 1,
#      a missing input exits 2, and a truncated / non-OGG input exits 3.
# Exits non-zero on any failure and prints a PASS/FAIL summary.
# POSIX sh + coreutils + python3 (numeric tolerance compare). Run from anywhere
# (paths resolved from this script).
#
# Env: ZIG  compiler (default the v97 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_decode)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_decode}"
FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
FIXTURES="sine_mono_44100 sine_stereo_44100 sine_stereo_48000 tagged_unicode short"

# Tolerance (LSB): Task 4 achieved max |delta| = 1 and RMS 0.036; allow a small
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

echo "== --pcm decode vs golden (tolerance + determinism) =="
for name in $FIXTURES; do
    FIX="$FIXDIR/$name.ogg"
    GOLD="$EXPDIR/$name.pcm"
    WAV="$OUT/$name.wav"
    PCM="$OUT/$name.pcm"

    "$PROG" --pcm "$FIX" "$WAV" >"$OUT/$name.out" 2>"$OUT/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "$name: --pcm exit 0"
    else
        fail_case "$name: --pcm exit 0 (got $rc)"
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
        "$PROG" --pcm "$FIX" "$OUT/$name.$i.wav" >/dev/null 2>&1
        payload "$OUT/$name.$i.wav" "$OUT/$name.$i.pcm"
        hx="$(sha1sum "$OUT/$name.$i.pcm" | awk '{print $1}')"
        [ "$hx" = "$h1" ] || d_ok=0
        i=$((i + 1))
    done
    if [ "$d_ok" -eq 1 ]; then
        pass_case "$name: deterministic 3x (sha1=$h1)"
    else
        fail_case "$name: decoded PCM not deterministic"
    fi

    # informational: exact-match SHA-1 vs golden (never fails).
    hg="$(sha1sum "$GOLD" | awk '{print $1}')"
    if [ "$h1" = "$hg" ]; then
        echo "info - $name: exact SHA-1 == golden ($h1)"
    else
        echo "info - $name: exact SHA-1 != golden (decoded=$h1 golden=$hg)"
    fi
done

echo "== --pcm exact regression pin (pre-streaming output) =="
EXACT_WAV="$OUT/sine_stereo_44100.exact.wav"
EXACT_MD5="e7f24870ec03b924be1b8e55a1962fb3"
EXACT_SIZE=352844
"$PROG" --pcm "$FIXDIR/sine_stereo_44100.ogg" "$EXACT_WAV" >"$OUT/exact.out" 2>"$OUT/exact.err"
rc=$?
wsz=$(LC_ALL=C wc -c < "$EXACT_WAV" 2>/dev/null | tr -d ' ')
hx=$(md5sum "$EXACT_WAV" 2>/dev/null | awk '{print $1}')
if [ "$rc" -eq 0 ] && [ "$wsz" = "$EXACT_SIZE" ] && [ "$hx" = "$EXACT_MD5" ]; then
    pass_case "sine_stereo_44100: --pcm byte-exact pin (md5=$hx size=$wsz)"
else
    fail_case "sine_stereo_44100: --pcm byte-exact pin (rc=$rc size=${wsz:-none} md5=${hx:-none})"
fi

echo "== exit codes: arguments =="
"$PROG" --pcm >"$OUT/noout.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then pass_case "--pcm without output path exit 1"; else fail_case "--pcm without output path exit 1 (got $rc)"; fi

echo "== exit codes: open / decoder (non-vacuous) =="
"$PROG" --pcm "$OUT/missing.ogg" "$OUT/x.wav" >"$OUT/missing.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then pass_case "missing input exit 2"; else fail_case "missing input exit 2 (got $rc)"; fi

dd if="$FIXDIR/short.ogg" of="$OUT/truncated.ogg" bs=1 count=16 2>/dev/null
"$PROG" --pcm "$OUT/truncated.ogg" "$OUT/x.wav" >"$OUT/truncated.out" 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then pass_case "truncated input exit 3"; else fail_case "truncated input exit 3 (got $rc)"; fi

printf 'THIS IS NOT AN OGG FILE\n' >"$OUT/notogg.bin"
"$PROG" --pcm "$OUT/notogg.bin" "$OUT/x.wav" >"$OUT/notogg.out" 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then pass_case "non-OGG input exit 3"; else fail_case "non-OGG input exit 3 (got $rc)"; fi

echo
echo "== tier_decode summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DECODE FAIL"
    exit 1
fi
echo "TIER_DECODE PASS"
exit 0
