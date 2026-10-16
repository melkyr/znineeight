#!/bin/sh
# tier_cli.sh — z9play M5 Task 4 gate: interactive CLI playback.
#
# Builds examples/z98/z9play/main.zig with the binding seed recipe under -fsafe,
# then drives the built CLI under a pty (`script`) into the hermetic WAV sink
# (`Z9PLAY_WAV_OUT`) and asserts:
#   1. the startup metadata line
#      `z9play: <title-or-path>  <mm:ss>  <ch>ch <rate>Hz` (and that a
#      TITLE-tagged fixture shows its title instead of the path);
#   2. a per-second `\r` status line appears, at `00:00` and again later at
#      `00:01`, proving the once-per-second cadence (not a single frozen line);
#   3. `q` and Ctrl-C stop cleanly (exit 0, `Stopped at mm:ss.`) *before* the
#      end of the 2 s fixture;
#   4. the exact argument/open/decoder exit codes: bad flag -> 1, missing file
#      -> 2, non-OGG -> 3;
#   5. `--quiet` suppresses the status line (the startup + `Stopped at` lines
#      still print);
#   6. the `--dump-c89` md5 of main.zig is recorded and stable over two runs.
#
# Non-vacuous: the exit-code negatives are real failures; the `--quiet` case
# requires the *absence* of the exact status match that the normal case requires
# to be present, so the status check cannot be trivially satisfied; the q/Ctrl-C
# runs must stop before `Stopped at 00:02.` (a missed key lets the fixture run to
# completion); and the status check requires a *second* status (`00:01`), so a
# single line cannot pass.
#
# POSIX sh + coreutils + `script` (pty). Run from anywhere (paths resolved from
# this script).
#
# Env: ZIG  compiler (default the v98 seed-built zig1)
#      OUT  scratch dir (default /tmp/z9play_tier_cli)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9play_seed_v98/zig1_5_clean}"
OUT="${OUT:-/tmp/z9play_tier_cli}"
FIXDIR="$Z9DIR/testdata"

# Relative paths (the script cd's to the repo root) keep the startup line short
# and let the pty `script -qec` command string stay whitespace-free.
FIX_STATUS="examples/z98/z9play/testdata/sine_stereo_44100.ogg"
FIX_TITLE="examples/z98/z9play/testdata/tagged_unicode.ogg"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed_v98"
    exit 1
fi
if ! command -v script >/dev/null 2>&1; then
    echo "FAIL: 'script' (pty) not found; cannot drive the interactive CLI"
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

# key_writer <log> <mode> <delay> — the left side of a pty pipeline. Waits for
# the startup line to appear in <log> (the startup line is `\n`-terminated, so
# the program's line-buffered stdout flushes it even though later status lines
# are `\r`-only), sleeps <delay> seconds (raw mode is installed right after the
# startup line), then sends <mode>'s key: `q`, `ctrlc` (0x03) or `none`. It then
# exits, closing the pipe; `script` keeps running until the program exits.
key_writer() {
    kw_log="$1"
    kw_mode="$2"
    kw_delay="$3"
    kw_i=0
    while [ "$kw_i" -lt 3000 ]; do
        if [ -s "$kw_log" ] && grep -q 'z9play:' "$kw_log" 2>/dev/null; then break; fi
        sleep 0.01
        kw_i=$((kw_i + 1))
    done
    if [ "$kw_mode" != "none" ]; then
        sleep "$kw_delay"
        case "$kw_mode" in
            q) printf 'q' ;;
            ctrlc) printf '\003' ;;
            *) printf '%s' "$kw_mode" ;;
        esac
    fi
}

# status_count <log> — number of per-second status lines (each begins with a
# `\r`, so translate those to newlines first).
status_count() {
    tr '\r' '\n' <"$1" 2>/dev/null | grep -F -c '00:02  vol  80%  [' 2>/dev/null
}

echo "== startup line + per-second status (full playback, pty, WAV sink) =="
LOG="$OUT/status.log"
WAV="$OUT/status.wav"
rm -f "$LOG" "$WAV"
Z9PLAY_WAV_OUT="$WAV" timeout 60 script -qec "exec $PROG $FIX_STATUS" /dev/null </dev/null >"$LOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "full playback exit 0"
else
    fail_case "full playback exit 0 (got $rc)"
fi
if grep -q 'z9play: .*  00:02  2ch 44100Hz' "$LOG"; then
    pass_case "startup line: $(tr -d '\r' <"$LOG" | sed -n '1p')"
else
    fail_case "startup line missing/misformatted ($(tr -d '\r' <"$LOG" | sed -n '1p'))"
fi
if tr '\r' '\n' <"$LOG" | grep -F -q '00:00 / 00:02  vol  80%  ['; then
    pass_case "status line at t=00:00 present (CR redraw)"
else
    fail_case "no t=00:00 status line"
fi
if tr '\r' '\n' <"$LOG" | grep -F -q '00:01 / 00:02  vol  80%  ['; then
    pass_case "later status line at t=00:01 present (per-second cadence)"
else
    fail_case "no later (00:01) status line"
fi
sc="$(status_count "$LOG")"
if [ -n "$sc" ] && [ "$sc" -ge 2 ]; then
    pass_case "status line drawn $sc times"
else
    fail_case "status line drawn fewer than twice (got ${sc:-0})"
fi
if grep -q 'Stopped at 00:02\.' "$LOG"; then
    pass_case "Stopped at 00:02. on natural end"
else
    fail_case "missing 'Stopped at 00:02.'"
fi
wsz=$(LC_ALL=C wc -c <"$WAV" 2>/dev/null | tr -d ' ')
if [ -n "$wsz" ] && [ "$wsz" -eq 352844 ]; then
    pass_case "hermetic WAV sink written (2.000 s = $wsz bytes)"
else
    fail_case "unexpected WAV sink size (got ${wsz:-none}, want 352844)"
fi

echo "== startup line uses TITLE tag (tagged_unicode, pty) =="
TLOG="$OUT/title.log"
rm -f "$TLOG"
key_writer "$TLOG" q 1 | Z9PLAY_WAV_OUT="$OUT/title.wav" timeout 60 script -qec "exec $PROG $FIX_TITLE" /dev/null >"$TLOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "tagged_unicode quit exit 0"
else
    fail_case "tagged_unicode quit exit 0 (got $rc)"
fi
if grep -q 'z9play: Café déjà vu  00:01  2ch 44100Hz' "$TLOG"; then
    pass_case "startup line shows the TITLE tag"
else
    fail_case "startup line did not show the TITLE tag ($(tr -d '\r' <"$TLOG" | sed -n '1p'))"
fi

echo "== q stops cleanly (pty, WAV sink) =="
QLOG="$OUT/q.log"
rm -f "$QLOG"
key_writer "$QLOG" q 1 | Z9PLAY_WAV_OUT="$OUT/q.wav" timeout 60 script -qec "exec $PROG $FIX_STATUS" /dev/null >"$QLOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "q exit 0"
else
    fail_case "q exit 0 (got $rc)"
fi
if grep -q 'Stopped at ' "$QLOG"; then
    pass_case "q prints 'Stopped at' ($(tr -d '\r' <"$QLOG" | grep 'Stopped at' | tail -1))"
else
    fail_case "q did not print 'Stopped at'"
fi
if grep -q 'Stopped at 00:02\.' "$QLOG"; then
    fail_case "q did not quit early (ran to 00:02)"
else
    pass_case "q quit before the end (non-vacuous)"
fi

echo "== Ctrl-C stops cleanly (pty, WAV sink) =="
CLOG="$OUT/ctrlc.log"
rm -f "$CLOG"
key_writer "$CLOG" ctrlc 1 | Z9PLAY_WAV_OUT="$OUT/ctrlc.wav" timeout 60 script -qec "exec $PROG $FIX_STATUS" /dev/null >"$CLOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "Ctrl-C exit 0 (script rc)"
else
    fail_case "Ctrl-C exit 0 (got $rc)"
fi
if grep -q 'Stopped at ' "$CLOG"; then
    pass_case "Ctrl-C prints 'Stopped at' ($(tr -d '\r' <"$CLOG" | grep 'Stopped at' | tail -1))"
else
    fail_case "Ctrl-C did not print 'Stopped at'"
fi
if grep -q 'Stopped at 00:02\.' "$CLOG"; then
    fail_case "Ctrl-C did not quit early (ran to 00:02)"
else
    pass_case "Ctrl-C quit before the end (non-vacuous)"
fi

echo "== --quiet suppresses the status line (pty) =="
XLOG="$OUT/quiet.log"
rm -f "$XLOG"
key_writer "$XLOG" q 2 | Z9PLAY_WAV_OUT="$OUT/quiet.wav" timeout 60 script -qec "exec $PROG --quiet $FIX_STATUS" /dev/null >"$XLOG" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass_case "--quiet exit 0"
else
    fail_case "--quiet exit 0 (got $rc)"
fi
if grep -q 'z9play: .*  00:02  2ch 44100Hz' "$XLOG"; then
    pass_case "--quiet still prints the startup line"
else
    fail_case "--quiet dropped the startup line"
fi
if grep -q 'Stopped at ' "$XLOG"; then
    pass_case "--quiet still prints 'Stopped at'"
else
    fail_case "--quiet dropped 'Stopped at'"
fi
qc="$(status_count "$XLOG")"
if [ -n "$qc" ] && [ "$qc" -eq 0 ]; then
    pass_case "--quiet: status line absent (0 occurrences)"
else
    fail_case "--quiet: status line leaked (${qc:-?} occurrences)"
fi

echo "== exit codes: arguments / open / decoder (hermetic) =="
Z9PLAY_WAV_OUT="$OUT/neg.wav" "$PROG" --bogus >"$OUT/badflag.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
    pass_case "bad flag exit 1"
else
    fail_case "bad flag exit 1 (got $rc)"
fi
Z9PLAY_WAV_OUT="$OUT/neg.wav" "$PROG" "$OUT/missing.ogg" >"$OUT/missing.out" 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
    pass_case "missing file exit 2"
else
    fail_case "missing file exit 2 (got $rc)"
fi
printf 'THIS IS NOT AN OGG FILE\n' >"$OUT/notogg.bin"
Z9PLAY_WAV_OUT="$OUT/neg.wav" "$PROG" "$OUT/notogg.bin" >"$OUT/notogg.out" 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
    pass_case "non-OGG file exit 3"
else
    fail_case "non-OGG file exit 3 (got $rc)"
fi

echo "== --dump-c89 md5 (main.zig) =="
timeout 120 "$ZIG" --dump-c89 examples/z98/z9play/main.zig >"$OUT/dump1.c89" 2>"$OUT/dump1.err"
md1="$(md5sum "$OUT/dump1.c89" 2>/dev/null | awk '{print $1}')"
timeout 120 "$ZIG" --dump-c89 examples/z98/z9play/main.zig >"$OUT/dump2.c89" 2>"$OUT/dump2.err"
md2="$(md5sum "$OUT/dump2.c89" 2>/dev/null | awk '{print $1}')"
echo "--dump-c89 md5: ${md1:-<none>}"
if [ -n "$md1" ] && [ "$md1" = "$md2" ]; then
    pass_case "--dump-c89 md5 recorded (stable 2x): $md1"
else
    fail_case "--dump-c89 md5 unstable/empty ($md1 vs $md2)"
fi

echo
echo "== tier_cli summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_CLI FAIL"
    exit 1
fi
echo "TIER_CLI PASS"
exit 0
