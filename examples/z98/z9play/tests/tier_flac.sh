#!/bin/sh
# tier_flac.sh — z9play M8 Task 3 gate: native FLAC playback + mixed selection.
#
# Builds examples/z98/z9play/main.zig and ui.zig with the binding seed recipe
# under -fsafe, obtains a runnable flac(1) through the no-root
# tests/get_flac_tools.sh, and then:
#
#   1. generates .flac fixture(s) from the existing raw PCM goldens with the
#      T2 recipe (`flac --force-raw-format --endian=little --sign=signed
#      --channels=<n> --bps=16 --sample-rate=<sr>`; channels/rate from the
#      fixture .meta) and decodes each fixture back with `flac -d` to the raw
#      golden used for comparison;
#   2. drives the public z9play Player path (`--wav <in.flac> <out.wav>`) for
#      every fixture: exit 0, `wav: ended ... monotonic=1`, canonical WAV
#      header/size, payload byte-exact against the `flac -d` golden (FLAC is
#      lossless, so the M3 tolerance is not used here), and 3x determinism
#      (identical raw-PCM SHA-1);
#   3. asserts mixed `.ogg`/`.flac` selection through the TUI under a pty: a
#      scratch directory containing both is listed (non-audio filtered), the
#      cursor selects each file, both reach `State: Ended`, and each hermetic
#      WAV sink is complete; the FLAC payload is exact and the OGG payload is
#      within the M3 tolerance (max |delta| <= 2 LSB, RMS <= 0.1 LSB). The
#      volume is raised to 100 first so the mixer is the identity;
#   4. runs the OGG regression tiers (tier_cli 23/0, tier_tui 40/0,
#      tier_audio 27/0) so M8 cannot regress Vorbis;
#   5. emits/builds main.zig for default `-osw` (9x no-CRT) and asserts PE32
#      i386, exactly KERNEL32+WINMM (no msvcrt), and the closed-world
#      scripts/win32_cross/check_win9x_imports.sh 9x whitelist. Real Win98/Me
#      hardware verification is operator-pending and is NOT claimed;
#   6. records the `--dump-c89` md5 for main.zig and ui.zig (stable 2x).
#
# Non-vacuous: fixtures are generated from committed goldens and each `flac -d`
# golden is required to equal its source PCM; each decode must match exactly and
# be deterministic; the mixed TUI run proves both extension/signature arms in
# one session with distinct WAV payloads; the regression summaries require the
# exact historical counts; and the Win9x import set is checked mechanically.
# Exits nonzero on any FAIL.
#
# POSIX sh + coreutils + python3 + file + i686-w64-mingw32-objdump + bash.
# Run from anywhere (paths resolved from this script).
#
# Env: ZIG  seed compiler (default: first of /tmp/z9play_seed/zig1_5_clean,
#           /tmp/m7_t1_seed/zig1_5_clean; rebuilt from release/seed if absent)
#      OUT  scratch dir (default /tmp/z9play_tier_flac)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
OUT="${OUT:-/tmp/z9play_tier_flac}"
EXPDIR="$Z9DIR/testdata/expected"
FIXTURES="sine_mono_44100 sine_stereo_44100 sine_stereo_48000"

MAX_DELTA_BOUND=2
RMS_MILLI_BOUND=100

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

for tool in python3 md5sum sha1sum file cmp timeout dd sed awk tr wc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done
if ! command -v i686-w64-mingw32-objdump >/dev/null 2>&1 \
    || ! command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "FAIL: Win9x cross tools missing (i686-w64-mingw32-gcc/objdump)"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# Seed v102 (fixed point b299b4b4...); rebuild from the committed archive when
# neither the env override nor the conventional scratch build is present.
if [ -z "${ZIG:-}" ] || [ ! -x "${ZIG:-}" ]; then
    ZIG=""
    for cand in /tmp/z9play_seed/zig1_5_clean /tmp/m7_t1_seed/zig1_5_clean \
                /tmp/z9play_seed_v98/zig1_5_clean; do
        if [ -x "$cand" ]; then
            ZIG="$cand"
            break
        fi
    done
fi
if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "== rebuilding seed v102 from release/seed/zig1-seed.tgz =="
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
if [ "$SEED_MD5" = "b299b4b435e624d0ddbd2edde681cbc3" ]; then
    pass_case "seed v102 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3"
else
    fail_case "seed compiler md5 is not the v102 fixed point (got ${SEED_MD5:-<none>})"
fi

# build_root <name> <src> — -fsafe emit + emitted linux link; prints nothing.
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
UIPROG="$OUT/ui/prog"

echo
echo "== no-root flac tool (tests/get_flac_tools.sh) =="
TOOLS_OUT="$OUT/flac_tools.out"
if TMP="$OUT/flac_tools" timeout 600 sh "$SCRIPT_DIR/get_flac_tools.sh" \
    >"$TOOLS_OUT" 2>"$OUT/flac_tools.err"; then
    FLAC="$(sed -n 's/^flac: //p' "$TOOLS_OUT" | tail -1)"
    FLAC_LD="$(sed -n 's/^LD_LIBRARY_PATH: //p' "$TOOLS_OUT" | tail -1)"
    FLAC_VER="$(sed -n 's/^flac_version: //p' "$TOOLS_OUT" | tail -1)"
    if [ -n "$FLAC" ] && [ -x "$FLAC" ]; then
        pass_case "flac acquired without root ($FLAC_VER)"
    else
        fail_case "get_flac_tools.sh reported no runnable flac"
        exit 1
    fi
else
    fail_case "get_flac_tools.sh failed (see $OUT/flac_tools.err)"
    tail -20 "$OUT/flac_tools.err" | sed 's/^/       /'
    exit 1
fi
echo "flac: $FLAC"
echo "LD_LIBRARY_PATH: $FLAC_LD"

run_flac() { env LD_LIBRARY_PATH="$FLAC_LD" "$FLAC" "$@"; }

# payload <wav> <dest> — write the WAV payload (after the canonical header).
payload() { tail -c +45 "$1" > "$2" 2>/dev/null; }

# tolerance <payload> <golden> — print "max_delta=<n> rms_milli=<n>".
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

echo
echo "== generate .flac fixtures from raw PCM goldens (T2 recipe) =="
FIXDIR="$OUT/fixtures"
mkdir -p "$FIXDIR"
for name in $FIXTURES; do
    meta="$EXPDIR/$name.meta"
    src="$EXPDIR/$name.pcm"
    ch="$(sed -n 's/^channels=//p' "$meta")"
    sr="$(sed -n 's/^sample_rate=//p' "$meta")"
    fix="$FIXDIR/$name.flac"
    gold="$FIXDIR/$name.flac-d.pcm"
    if [ -z "$ch" ] || [ -z "$sr" ] || [ ! -f "$src" ]; then
        fail_case "$name: missing meta/source PCM"
        continue
    fi
    if run_flac -f --force-raw-format --endian=little --sign=signed \
        --channels="$ch" --bps=16 --sample-rate="$sr" \
        -o "$fix" "$src" >"$FIXDIR/$name.encode.log" 2>&1 \
        && [ -s "$fix" ]; then
        pass_case "$name: generated .flac ($ch ch @ ${sr}Hz, $(LC_ALL=C wc -c <"$fix" | tr -d ' ') bytes)"
    else
        fail_case "$name: flac fixture generation failed (see $FIXDIR/$name.encode.log)"
        continue
    fi
    if run_flac -f -d --force-raw-format --endian=little --sign=signed \
        -o "$gold" "$fix" >"$FIXDIR/$name.decode.log" 2>&1 \
        && [ -s "$gold" ]; then
        pass_case "$name: flac -d golden produced"
    else
        fail_case "$name: flac -d golden failed (see $FIXDIR/$name.decode.log)"
        continue
    fi
    if cmp -s "$gold" "$src"; then
        pass_case "$name: flac -d golden is byte-identical to the source golden PCM"
    else
        fail_case "$name: flac -d golden differs from the source golden PCM"
    fi
done

echo
echo "== Player --wav vs flac -d golden (exact) + determinism 3x =="
for name in $FIXTURES; do
    fix="$FIXDIR/$name.flac"
    gold="$FIXDIR/$name.flac-d.pcm"
    [ -f "$fix" ] && [ -f "$gold" ] || continue
    wav="$OUT/$name.wav"
    pcm="$OUT/$name.pcm"

    timeout 300 "$PROG" --wav "$fix" "$wav" >"$OUT/$name.out" 2>"$OUT/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "$name: --wav exit 0"
    else
        fail_case "$name: --wav exit 0 (got $rc)"
    fi
    if grep -q 'wav: ended ' "$OUT/$name.out" && grep -q 'monotonic=1' "$OUT/$name.out"; then
        pass_case "$name: player ended + position monotonic ($(cat "$OUT/$name.out"))"
    else
        fail_case "$name: player completion/monotonicity not reported ($(cat "$OUT/$name.out"))"
    fi

    hdr_ok=1
    [ "$(dd if="$wav" bs=1 count=4 2>/dev/null)" = "RIFF" ] || hdr_ok=0
    [ "$(dd if="$wav" bs=1 skip=8 count=4 2>/dev/null)" = "WAVE" ] || hdr_ok=0
    [ "$(dd if="$wav" bs=1 skip=36 count=4 2>/dev/null)" = "data" ] || hdr_ok=0
    wsz=$(LC_ALL=C wc -c <"$wav" 2>/dev/null | tr -d ' ')
    gsz=$(LC_ALL=C wc -c <"$gold" 2>/dev/null | tr -d ' ')
    [ -n "$wsz" ] && [ "$wsz" -eq $((44 + gsz)) ] || hdr_ok=0
    if [ "$hdr_ok" -eq 1 ]; then
        pass_case "$name: canonical WAV header + payload size ($wsz bytes)"
    else
        fail_case "$name: bad WAV header / payload size (wav=$wsz golden=$gsz)"
    fi

    payload "$wav" "$pcm"
    if cmp -s "$pcm" "$gold"; then
        h1="$(sha1sum "$pcm" | awk '{print $1}')"
        pass_case "$name: payload byte-exact vs flac -d golden (sha1=$h1)"
    else
        fail_case "$name: payload differs from flac -d golden"
    fi

    h1="$(sha1sum "$pcm" 2>/dev/null | awk '{print $1}')"
    d_ok=1
    i=2
    while [ "$i" -le 3 ]; do
        if ! timeout 300 "$PROG" --wav "$fix" "$OUT/$name.$i.wav" \
            >"$OUT/$name.$i.out" 2>"$OUT/$name.$i.err"; then
            d_ok=0
        fi
        payload "$OUT/$name.$i.wav" "$OUT/$name.$i.pcm"
        hx="$(sha1sum "$OUT/$name.$i.pcm" 2>/dev/null | awk '{print $1}')"
        [ -n "$hx" ] && [ "$hx" = "$h1" ] || d_ok=0
        i=$((i + 1))
    done
    if [ "$d_ok" -eq 1 ] && [ -n "$h1" ]; then
        pass_case "$name: deterministic 3x (sha1=$h1)"
    else
        fail_case "$name: Player output not deterministic"
    fi
done

echo
echo "== mixed .ogg/.flac selection through the TUI (pty) =="
SCRATCH="$OUT/mixed"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"
cp "$FIXDIR/sine_stereo_44100.flac" "$SCRATCH/a.flac"
cp "$Z9DIR/testdata/short.ogg" "$SCRATCH/b.ogg"
printf 'not audio\n' >"$SCRATCH/notes.txt"

cat >"$OUT/mixed_driver.py" <<'PY'
import errno
import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import sys
import termios
import time

PROG, SCRATCH, LOG, WAV = sys.argv[1:5]
FLAC_DATA = 352800
OGG_DATA = 26460

checks = 0
fails = 0


def check(name, cond):
    global checks, fails
    checks += 1
    if cond:
        print("CHECK %s=1" % name)
    else:
        fails += 1
        print("CHECK %s=0" % name)
    sys.stdout.flush()


master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))

env = dict(os.environ)
env["Z9PLAY_WAV_OUT"] = WAV

pid = os.fork()
if pid == 0:
    try:
        os.chdir(SCRATCH)
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(master)
        os.close(slave)
        os.execve(PROG, [PROG], env)
    except BaseException:
        os._exit(127)

buf = bytearray()


def pump(timeout):
    try:
        r, _, _ = select.select([master], [], [], timeout)
    except InterruptedError:
        return False
    if not r:
        return False
    try:
        d = os.read(master, 65536)
    except OSError as e:
        if e.errno == errno.EIO:
            return False
        raise
    if not d:
        return False
    buf.extend(d)
    return True


def wait_bytes(needle, timeout, start=0):
    end = time.time() + timeout
    while time.time() < end:
        if needle in buf[start:]:
            return True
        pump(min(0.2, max(0.0, end - time.time())))
    return needle in buf[start:]


def wait_child(timeout):
    end = time.time() + timeout
    st = None
    while time.time() < end:
        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            st = status
            break
        pump(0.1)
    if st is None:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        return None
    for _ in range(20):
        if not pump(0.05):
            break
    if os.WIFEXITED(st):
        return os.WEXITSTATUS(st)
    if os.WIFSIGNALED(st):
        return -os.WTERMSIG(st)
    return -1


try:
    listed = wait_bytes(b"b.ogg", 30) and wait_bytes(b"a.flac", 5)
    check("mixed-listing-both", listed)
    check("mixed-initial-selection-parent", b"> .." in bytes(buf))
    check("mixed-filters-non-audio", b"notes.txt" not in bytes(buf))
    check("mixed-wav-absent-before-play", not os.path.exists(WAV))

    os.write(master, b"++++")

    mark = len(buf)
    os.write(master, b"j")
    check("mixed-select-flac", wait_bytes(b"> a.flac", 15, mark))

    play = len(buf)
    os.write(master, b"\r")
    check("mixed-opens-flac", wait_bytes(b"Now: a.flac", 90, play))
    check("mixed-flac-volume-100", wait_bytes(b"vol 100%", 90, play))
    check("mixed-flac-playing", wait_bytes(b"State: Playing", 90, play))
    check("mixed-flac-ended", wait_bytes(b"State: Ended", 240, play))
    try:
        flac_size = os.path.getsize(WAV)
    except OSError:
        flac_size = -1
    check("mixed-flac-wav-complete", flac_size == 44 + FLAC_DATA)
    try:
        shutil.copyfile(WAV, WAV + ".flac")
        copied = True
    except OSError:
        copied = False
    check("mixed-flac-wav-copied", copied)

    mark = len(buf)
    os.write(master, b"j")
    check("mixed-select-ogg", wait_bytes(b"> b.ogg", 15, mark))

    play = len(buf)
    os.write(master, b"\r")
    check("mixed-opens-ogg", wait_bytes(b"Now: b.ogg", 90, play))
    check("mixed-ogg-playing", wait_bytes(b"State: Playing", 90, play))
    check("mixed-ogg-ended", wait_bytes(b"State: Ended", 240, play))
    try:
        ogg_size = os.path.getsize(WAV)
    except OSError:
        ogg_size = -1
    check("mixed-ogg-wav-complete", ogg_size == 44 + OGG_DATA)
    try:
        shutil.copyfile(WAV, WAV + ".ogg")
        copied = True
    except OSError:
        copied = False
    check("mixed-ogg-wav-copied", copied)

    os.write(master, b"q")
    check("mixed-q-exits-rc0", wait_child(30) == 0)
finally:
    try:
        open(LOG, "wb").write(bytes(buf))
    except OSError:
        pass
    try:
        os.close(master)
    except OSError:
        pass
    try:
        os.close(slave)
    except OSError:
        pass

print("DRIVER_DONE=1")
print("DRIVER_CHECKS total=%d passed=%d failed=%d"
      % (checks, checks - fails, fails))
sys.exit(0 if fails == 0 else 1)
PY

MIXWAV="$OUT/mixed.wav"
MIXLOG="$OUT/mixed.log"
rm -f "$MIXWAV" "$MIXWAV.flac" "$MIXWAV.ogg" "$MIXLOG" "$OUT/mixed_driver.out"
timeout 420 python3 "$OUT/mixed_driver.py" "$UIPROG" "$SCRATCH" "$MIXLOG" "$MIXWAV" \
    >"$OUT/mixed_driver.out" 2>"$OUT/mixed_driver.err"
MIX_RC=$?
SAW_DONE=0
while IFS= read -r line; do
    case "$line" in
        "CHECK "*)
            body=${line#CHECK }
            cname=${body%%=*}
            val=${body##*=}
            if [ "$val" = "1" ]; then
                pass_case "$cname"
            else
                fail_case "$cname"
            fi
            ;;
        "DRIVER_DONE=1")
            SAW_DONE=1
            ;;
        "DRIVER_CHECKS "*)
            echo "driver: ${line#DRIVER_CHECKS }"
            ;;
    esac
done <"$OUT/mixed_driver.out"
if [ "$SAW_DONE" -ne 1 ]; then
    fail_case "mixed pty driver completed (rc=$MIX_RC; see $OUT/mixed_driver.err)"
fi
echo "mixed pty log: $MIXLOG ($(LC_ALL=C wc -c <"$MIXLOG" 2>/dev/null | tr -d ' ') bytes)"
if [ -s "$OUT/mixed_driver.err" ]; then
    tail -10 "$OUT/mixed_driver.err" | sed 's/^/       /'
fi

MIXFLAC="$OUT/mixed.flac.pcm"
MIXOGG="$OUT/mixed.ogg.pcm"
payload "$MIXWAV.flac" "$MIXFLAC"
payload "$MIXWAV.ogg" "$MIXOGG"
FLAC_GOLD="$FIXDIR/sine_stereo_44100.flac-d.pcm"
OGG_GOLD="$EXPDIR/short.pcm"
if [ -s "$MIXFLAC" ] && cmp -s "$MIXFLAC" "$FLAC_GOLD"; then
    pass_case "mixed TUI FLAC payload byte-exact vs flac -d golden"
else
    fail_case "mixed TUI FLAC payload differs from flac -d golden"
fi
tol="$(tolerance "$MIXOGG" "$OGG_GOLD")"
md="$(printf '%s\n' "$tol" | sed -n 's/.*max_delta=\([0-9][0-9]*\).*/\1/p')"
rmsm="$(printf '%s\n' "$tol" | sed -n 's/.*rms_milli=\([0-9][0-9]*\).*/\1/p')"
if [ -n "$md" ] && [ -n "$rmsm" ] && [ "$md" -le "$MAX_DELTA_BOUND" ] \
    && [ "$rmsm" -le "$RMS_MILLI_BOUND" ]; then
    pass_case "mixed TUI OGG payload tolerance max_delta=$md rms_milli=$rmsm (<= $MAX_DELTA_BOUND / $RMS_MILLI_BOUND)"
else
    fail_case "mixed TUI OGG payload out of bound ($tol)"
fi

echo
echo "== OGG regression tiers =="
run_ogg_tier() {
    rt_name="$1"
    rt_want="$2"
    rt_dir="$OUT/r/${rt_name#tier_}"
    ZIG="$ZIG" OUT="$rt_dir" timeout 1800 sh "$SCRIPT_DIR/$rt_name.sh" \
        >"$OUT/$rt_name.log" 2>&1
    rt_rc=$?
    rt_line="$(grep "== $rt_name summary:" "$OUT/$rt_name.log" | tail -1)"
    echo "$rt_name: ${rt_line:-<no summary>} (rc=$rt_rc)"
    if [ "$rt_rc" -eq 0 ] \
        && printf '%s\n' "$rt_line" | grep -F -q "== $rt_name summary: $rt_want passed, 0 failed =="; then
        pass_case "$rt_name green ($rt_want passed, 0 failed)"
    else
        fail_case "$rt_name not green (rc=$rt_rc; ${rt_line:-<no summary>})"
        tail -15 "$OUT/$rt_name.log" | sed 's/^/       /'
    fi
}
run_ogg_tier tier_cli 23
run_ogg_tier tier_tui 40
run_ogg_tier tier_audio 27

echo
echo "== Win9x gate: main.zig -osw emit/build + PE/import check =="
WIN_EMIT="$OUT/win_emit"
mkdir -p "$WIN_EMIT"
timeout 900 "$ZIG" -osw -o "$WIN_EMIT" examples/z98/z9play/main.zig \
    >"$OUT/win_emit.log" 2>&1
WIN_EMIT_RC=$?
if [ "$WIN_EMIT_RC" -eq 0 ] && [ -f "$WIN_EMIT/build_target.sh" ] \
    && grep -q -- '-DZIG_NO_CRT' "$WIN_EMIT/build_target.sh" \
    && grep -q -- '-nostdlib' "$WIN_EMIT/build_target.sh" \
    && grep -q -- '-lkernel32' "$WIN_EMIT/build_target.sh" \
    && grep -q -- '-lwinmm' "$WIN_EMIT/build_target.sh"; then
    pass_case "main.zig -osw emit is the 9x no-CRT recipe (DZIG_NO_CRT, nostdlib, kernel32+winmm)"
else
    fail_case "main.zig -osw emit failed/not the 9x no-CRT recipe (rc=$WIN_EMIT_RC; see $OUT/win_emit.log)"
fi
tail -5 "$OUT/win_emit.log" | sed 's/^/       /'

EXE="$OUT/z9play.exe"
if sh "$WIN_EMIT/build_target.sh" mingw "$EXE" >"$OUT/win_build.log" 2>&1 \
    && [ -f "$EXE" ]; then
    pass_case "emitted Win9x build produced exe ($(LC_ALL=C wc -c <"$EXE" | tr -d ' ') bytes)"
else
    fail_case "emitted Win9x build failed (see $OUT/win_build.log)"
fi
tail -3 "$OUT/win_build.log" | sed 's/^/       /'

FILEOUT="$(file "$EXE" 2>/dev/null)"
case "$FILEOUT" in
    *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
    *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
esac

IMPORTS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
    | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p' | tr -d '\r' \
    | tr '[:lower:]' '[:upper:]' | sort -u | tr '\n' ' ')"
echo "imports: ${IMPORTS:-<none>}"
if [ "$IMPORTS" = "KERNEL32.DLL WINMM.DLL " ]; then
    pass_case "imports are exactly KERNEL32 + WINMM (no msvcrt)"
else
    fail_case "import set is not exactly KERNEL32+WINMM: $(printf '%s' "$IMPORTS")"
fi
if [ -n "$IMPORTS" ] && ! printf '%s' "$IMPORTS" | grep -q 'MSVCRT'; then
    pass_case "no msvcrt import"
else
    fail_case "msvcrt import present/imports empty: ${IMPORTS:-<none>}"
fi

if bash "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$EXE" 9x \
    >"$OUT/imports.log" 2>&1; then
    pass_case "check_win9x_imports.sh 9x whitelist PASS"
else
    fail_case "check_win9x_imports.sh 9x whitelist FAILED (see $OUT/imports.log)"
fi
tail -4 "$OUT/imports.log" | sed 's/^/       /'
echo "note: real Win98/Me hardware verification is operator-pending (not claimed)"

echo
echo "== --dump-c89 md5 (main.zig, ui.zig; stable 2x) =="
for root in main ui; do
    timeout 600 "$ZIG" --dump-c89 "examples/z98/z9play/$root.zig" \
        >"$OUT/dump_$root.1.c89" 2>"$OUT/dump_$root.1.err"
    drc1=$?
    timeout 600 "$ZIG" --dump-c89 "examples/z98/z9play/$root.zig" \
        >"$OUT/dump_$root.2.c89" 2>"$OUT/dump_$root.2.err"
    drc2=$?
    dmd1="$(md5sum "$OUT/dump_$root.1.c89" 2>/dev/null | awk '{print $1}')"
    dmd2="$(md5sum "$OUT/dump_$root.2.c89" 2>/dev/null | awk '{print $1}')"
    echo "--dump-c89 $root.zig md5: ${dmd1:-<none>}"
    if [ "$drc1" -eq 0 ] && [ "$drc2" -eq 0 ] \
        && [ -n "$dmd1" ] && [ "$dmd1" = "$dmd2" ]; then
        pass_case "--dump-c89 $root.zig md5 recorded stable 2x: $dmd1"
    else
        fail_case "--dump-c89 $root.zig failed/unstable (rc=$drc1/$drc2 md5=$dmd1/$dmd2)"
    fi
done

echo
echo "== tier_flac summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_FLAC FAIL"
    exit 1
fi
echo "TIER_FLAC PASS"
exit 0
