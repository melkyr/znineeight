#!/bin/sh
# tier_stream.sh — z9play M9 gate: bounded-memory streaming playback.
#
# Builds main.zig and ui.zig with the binding seed under -fsafe, then:
#   1. generates a deterministic valid single-stream OGG of at least 64 MiB
#      from the committed testdata/sine_stereo_44100.ogg fixture with
#      tests/make_large_ogg.py (no third-party OGG library; repeated audio
#      block, monotonic sequence/granule, EOS on the last page, recomputed
#      CRCs), and checks that a second run is byte-identical;
#   2. runs `z9play --info` on that file under `ulimit -v 65536` KiB (64 MiB)
#      and asserts exit 0 plus the exact channels/sample_rate/duration block.
#      The duration comes from independent libvorbis frame counts (1 block =
#      88,200, +89,216 per additional block), not from the generator's own
#      duration_s line.
#      The same limit is proven to reject a buffer the size of the generated
#      file (Python allocates and touches every 4 KiB page), so this is a real
#      full-file-allocation negative, not a claim. The streaming binary fits:
#      its static arenas are 40.24 MiB (42,191,504 bytes) and its stream
#      buffers are bounded (64 KiB read + 64 KiB page + 1 MiB packet + 256 KiB
#      tail scan);
#   3. runs `z9play --pcm` on testdata/sine_stereo_44100.ogg and compares the
#      whole canonical WAV byte-for-byte with the committed pre-streaming
#      regression pin (md5 e7f24870ec03b924be1b8e55a1962fb3, 352844 bytes);
#   4. optionally, when Z9PLAY_LARGE_OGG names the operator's real track, runs
#      the same `--info` check on it under the same limit. The operator file is
#      never copied into the repo or committed;
#   5. re-runs the existing tiers tier_info (20/0), tier_setup (21/0),
#      tier_cli (23/0), tier_tui (40/0), tier_audio (27/0), tier_flac (59/0).
#
# Non-vacuous: the generator verifies its own output (CRCs, sequence, EOS,
# final granule) and the tier re-parses the file; a full-file allocation is
# demonstrated to fail under the same ulimit; the duration/rate/channels are
# compared exactly; and the streamed --pcm WAV is byte-identical to the
# pre-streaming regression pin. Exits nonzero on any FAIL.
#
# POSIX sh + coreutils + python3 + a pty/wine/FLAC toolchain for the existing
# tiers. Run from anywhere (paths resolved from this script).
#
# Env: ZIG  seed compiler (default: /tmp/m7_t5_seed2/zig1_5_clean, then the
#           conventional scratch builds, else rebuilt from release/seed)
#      OUT  scratch dir (default /tmp/z9play_tier_stream)
#      Z9PLAY_LARGE_OGG  optional operator track for the real-file --info check

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
OUT="${OUT:-/tmp/z9play_tier_stream}"
# Keep the nested tiers' scratch roots short: tier_tui displays the current
# absolute path in a 43-column pane and asserts it is readable.
TIERS="${TMPDIR:-/tmp}/z9s_tiers"
FIXDIR="$Z9DIR/testdata"
LARGE_MIN=$((64 * 1024 * 1024))
VM_KB=65536
# Independent duration oracle for the committed sine_stereo_44100 fixture:
# libvorbis decodes 1 block = 88,200 frames, 2 blocks = 177,416, 3 blocks =
# 266,632 (T6 review measurements). The first block is the fixture's 2.000 s
# trimmed stream; each additional repeated block advances 89,216 frames.
LIB_FIRST_FRAMES=88200
LIB_BLOCK_ADVANCE=89216

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

for tool in python3 md5sum cmp timeout dd tail wc grep awk sed tr sh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# Seed v104 (fixed point 21c95773...); rebuild from the committed archive when
# neither the env override nor a conventional scratch build is present.
if [ -z "${ZIG:-}" ] || [ ! -x "${ZIG:-}" ]; then
    ZIG=""
    for cand in /tmp/m7_t5_seed2/zig1_5_clean \
                /tmp/z9play_seed/zig1_5_clean \
                /tmp/m7_t1_seed/zig1_5_clean \
                /tmp/z9play_seed_v98/zig1_5_clean; do
        if [ -x "$cand" ]; then
            ZIG="$cand"
            break
        fi
    done
fi
if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "== rebuilding seed v104 from release/seed/zig1-seed.tgz =="
    if ! timeout 900 bash scripts/seed/build_from_seed.sh \
        release/seed/zig1-seed.tgz "$OUT/seed" >"$OUT/seed.log" 2>&1; then
        echo "FAIL: seed rebuild failed (see $OUT/seed.log)"
        tail -20 "$OUT/seed.log" | sed 's/^/       /'
        exit 1
    fi
    ZIG="$OUT/seed/zig1_5_clean"
fi
if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found/executable: $ZIG"
    exit 1
fi

echo "== seed =="
SEED_MD5="$(md5sum "$ZIG" 2>/dev/null | awk '{print $1}')"
echo "compiler: $ZIG"
echo "md5:      ${SEED_MD5:-<none>}"
if [ "$SEED_MD5" = "21c957730d268f1e7883176fa5413b65" ]; then
    pass_case "seed v104 compiler md5 is the fixed point 21c957730d268f1e7883176fa5413b65"
else
    fail_case "seed compiler md5 is not the v104 fixed point (got ${SEED_MD5:-<none>})"
fi

build_root() {
    br_name="$1"
    br_src="$2"
    br_dir="$OUT/$br_name"
    mkdir -p "$br_dir"
    if ! timeout 600 "$ZIG" -fsafe -o "$br_dir" "$br_src" >"$br_dir/zig.log" 2>&1; then
        return 1
    fi
    if ! sh "$br_dir/build_target.sh" linux "$br_dir/prog" >"$br_dir/build.log" 2>&1; then
        return 1
    fi
    [ -x "$br_dir/prog" ]
}

echo
echo "== building z9play main.zig and ui.zig (binding recipe, -fsafe) =="
if build_root main examples/z98/z9play/main.zig; then
    pass_case "main.zig -fsafe compile + emitted build_target.sh linux"
else
    fail_case "main.zig -fsafe compile/link failed (see $OUT/main/*.log)"
    tail -20 "$OUT/main/zig.log" "$OUT/main/build.log" 2>/dev/null | sed 's/^/       /'
    exit 1
fi
if build_root ui examples/z98/z9play/ui.zig; then
    pass_case "ui.zig -fsafe compile + emitted build_target.sh linux"
else
    fail_case "ui.zig -fsafe compile/link failed (see $OUT/ui/*.log)"
    tail -20 "$OUT/ui/zig.log" "$OUT/ui/build.log" 2>/dev/null | sed 's/^/       /'
    exit 1
fi
PROG="$OUT/main/prog"

echo
echo "== deterministic large OGG from the committed 2 s fixture =="
LARGE="$OUT/large.ogg"
LARGE2="$OUT/large.repeat.ogg"
STATS="$OUT/large.stats"
if python3 "$SCRIPT_DIR/make_large_ogg.py" \
    "$FIXDIR/sine_stereo_44100.ogg" "$LARGE" --size 64M >"$STATS" 2>"$OUT/large.gen.err"; then
    pass_case "make_large_ogg.py generated $LARGE"
else
    fail_case "make_large_ogg.py failed (see $OUT/large.gen.err)"
    tail -20 "$OUT/large.gen.err" | sed 's/^/       /'
    exit 1
fi
if python3 "$SCRIPT_DIR/make_large_ogg.py" \
    "$FIXDIR/sine_stereo_44100.ogg" "$LARGE2" --size 64M --quiet \
    >"$OUT/large2.gen.out" 2>"$OUT/large2.gen.err"; then
    if cmp -s "$LARGE" "$LARGE2"; then
        pass_case "make_large_ogg.py is deterministic (two runs byte-identical)"
    else
        fail_case "make_large_ogg.py output differs between two runs"
    fi
else
    fail_case "second make_large_ogg.py run failed (see $OUT/large2.gen.err)"
fi
rm -f "$LARGE2"

LSIZE="$(wc -c <"$LARGE" 2>/dev/null | tr -d ' ')"
LCH="$(sed -n 's/^channels=//p' "$STATS" | tail -1)"
LSR="$(sed -n 's/^sample_rate=//p' "$STATS" | tail -1)"
LFRAMES="$(sed -n 's/^frames=//p' "$STATS" | tail -1)"
LBLOCKS="$(sed -n 's/^blocks=//p' "$STATS" | tail -1)"
if [ -n "$LSIZE" ] && [ "$LSIZE" -ge "$LARGE_MIN" ]; then
    pass_case "large OGG size $LSIZE >= $LARGE_MIN bytes (64 MiB)"
else
    fail_case "large OGG too small (got ${LSIZE:-none}, want >= $LARGE_MIN)"
fi

# Duration is derived from the libvorbis oracle constants above and the
# independently parsed block count, not from the generator's duration_s line.
case "${LBLOCKS:-x}${LSR:-x}" in
    *[!0-9]*) LIB_FRAMES=""; LDUR="" ;;
    *)
        LIB_FRAMES=$((LIB_FIRST_FRAMES + (LBLOCKS - 1) * LIB_BLOCK_ADVANCE))
        LIB_MS=$((LIB_FRAMES * 1000 / LSR))
        LDUR="$(printf '%d.%03d' $((LIB_MS / 1000)) $((LIB_MS % 1000)))"
        ;;
esac
if [ "$LCH" = "2" ] && [ "$LSR" = "44100" ] && [ -n "$LDUR" ]; then
    pass_case "independent duration oracle: ${LCH}ch ${LSR}Hz frames=$LIB_FRAMES duration=${LDUR}s blocks=$LBLOCKS"
else
    fail_case "independent duration oracle missing/mismatched (ch=${LCH:-?} rate=${LSR:-?} blocks=${LBLOCKS:-?})"
fi
if [ -n "$LFRAMES" ] && [ "$LFRAMES" = "$LIB_FRAMES" ]; then
    pass_case "generator final frames $LFRAMES match the libvorbis oracle"
else
    fail_case "generator final frames ${LFRAMES:-none} != libvorbis oracle ${LIB_FRAMES:-none}"
fi

echo
echo "== --info on the large OGG under ulimit -v $VM_KB KiB (64 MiB) =="
( ulimit -v "$VM_KB"; exec "$PROG" --info "$LARGE" ) \
    >"$OUT/large.info" 2>"$OUT/large.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "large --info exit 0 under ulimit -v $VM_KB"
else
    fail_case "large --info exit $rc under ulimit -v $VM_KB (see $OUT/large.err)"
    tail -20 "$OUT/large.err" | sed 's/^/       /'
fi
{
    echo "channels=$LCH"
    echo "sample_rate=$LSR"
    echo "duration_s=$LDUR"
} >"$OUT/large.expected"
if cmp -s "$OUT/large.expected" "$OUT/large.info"; then
    pass_case "large --info matches expected channels/sample_rate/duration exactly"
else
    fail_case "large --info block differs from expected"
    diff -u "$OUT/large.expected" "$OUT/large.info" | sed 's/^/       /'
fi

# Prove the limit genuinely rejects a full-file allocation. The probe reads the
# same byte count as the generated file and touches every 4 KiB page.
alloc_probe() {
    python3 - "$1" <<'PY'
import sys
n = int(sys.argv[1])
try:
    b = bytearray(n)
    for i in range(0, n, 4096):
        b[i] = 1
except MemoryError:
    print("alloc-failed")
    sys.exit(1)
print("alloc-ok")
sys.exit(0)
PY
}
if ( ulimit -v "$VM_KB"; alloc_probe "$LSIZE" ) >"$OUT/alloc.out" 2>&1; then
    fail_case "full-file allocation unexpectedly succeeded under ulimit -v $VM_KB"
else
    if grep -qx 'alloc-failed' "$OUT/alloc.out"; then
        pass_case "full-file allocation of $LSIZE bytes fails under the same ulimit"
    else
        fail_case "allocation probe did not run (see $OUT/alloc.out)"
    fi
fi

echo
echo "== --pcm exact regression pin (pre-streaming WAV) =="
PCMWAV="$OUT/sine_stereo_44100.exact.wav"
PCM_MD5="e7f24870ec03b924be1b8e55a1962fb3"
PCM_SIZE=352844
"$PROG" --pcm "$FIXDIR/sine_stereo_44100.ogg" "$PCMWAV" >"$OUT/pcm.out" 2>"$OUT/pcm.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "--pcm sine_stereo_44100 exit 0"
else
    fail_case "--pcm sine_stereo_44100 exit $rc (see $OUT/pcm.err)"
fi
PSIZE="$(wc -c <"$PCMWAV" 2>/dev/null | tr -d ' ')"
if [ -n "$PSIZE" ] && [ "$PSIZE" -eq "$PCM_SIZE" ]; then
    pass_case "--pcm canonical WAV size $PCM_SIZE"
else
    fail_case "unexpected --pcm WAV size (got ${PSIZE:-none}, want $PCM_SIZE)"
fi
PCM_GOT="$(md5sum "$PCMWAV" 2>/dev/null | awk '{print $1}')"
if [ "$PCM_GOT" = "$PCM_MD5" ]; then
    pass_case "--pcm byte-exact pin (md5=$PCM_GOT)"
else
    fail_case "--pcm byte-exact pin (got ${PCM_GOT:-none}, want $PCM_MD5)"
fi

echo
echo "== optional operator track (Z9PLAY_LARGE_OGG) =="
if [ -n "${Z9PLAY_LARGE_OGG:-}" ]; then
    if [ ! -r "$Z9PLAY_LARGE_OGG" ]; then
        fail_case "Z9PLAY_LARGE_OGG is set but not readable: $Z9PLAY_LARGE_OGG"
    else
        OPSIZE="$(wc -c <"$Z9PLAY_LARGE_OGG" | tr -d ' ')"
        ( ulimit -v "$VM_KB"; exec "$PROG" --info "$Z9PLAY_LARGE_OGG" ) \
            >"$OUT/operator.info" 2>"$OUT/operator.err"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            pass_case "operator track --info exit 0 under ulimit -v $VM_KB (size $OPSIZE)"
        else
            fail_case "operator track --info exit $rc (see $OUT/operator.err)"
        fi
        if grep -q '^channels=' "$OUT/operator.info" \
            && grep -q '^sample_rate=' "$OUT/operator.info" \
            && grep -q '^duration_s=' "$OUT/operator.info"; then
            pass_case "operator --info has channels/sample_rate/duration ($(tr '\n' ' ' <"$OUT/operator.info"))"
        else
            fail_case "operator --info block is incomplete"
        fi
    fi
else
    echo "skip - Z9PLAY_LARGE_OGG not set (operator track not checked)"
fi

echo
echo "== existing tiers (green baselines) =="
run_tier() {
    rt_name="$1"
    rt_want="$2"
    rt_dir="$TIERS/$rt_name"
    rt_log="$OUT/tiers/$rt_name.log"
    mkdir -p "$OUT/tiers" "$rt_dir"
    ZIG="$ZIG" OUT="$rt_dir" timeout 3600 sh "$SCRIPT_DIR/tier_$rt_name.sh" \
        >"$rt_log" 2>&1
    rt_rc=$?
    rt_line="$(grep "== tier_$rt_name summary:" "$rt_log" | tail -1)"
    echo "$rt_name: ${rt_line:-<no summary>} (rc=$rt_rc)"
    if [ "$rt_rc" -eq 0 ] \
        && printf '%s\n' "$rt_line" | grep -F -q "== tier_$rt_name summary: $rt_want passed, 0 failed =="; then
        pass_case "$rt_name $rt_want/0"
    else
        fail_case "$rt_name not green (rc=$rt_rc; ${rt_line:-<no summary>}; see $rt_log)"
    fi
}

run_tier info 20
run_tier setup 21
run_tier cli 23
run_tier tui 40
run_tier audio 27
run_tier flac 59

echo
echo "== tier_stream summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_STREAM FAIL"
    exit 1
fi
echo "TIER_STREAM PASS"
exit 0
