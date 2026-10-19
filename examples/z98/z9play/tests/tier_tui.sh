#!/bin/sh
# tier_tui.sh — z9play M7 Task 4 gate: TUI behavior under a pty + Win9x build.
#
# Builds examples/z98/z9play/ui.zig with the binding seed recipe under -fsafe,
# then drives the TUI under a pty (python3 pty helper) in a throw-away scratch
# directory with an 80x25 frame pinned in the UI and a 100x30 pty window:
#   1. the first screen is a real 80x25 frame: 25 rows of exactly 80 cells,
#      borders at the pinned columns, the scratch path in the directory pane,
#      the synthesized `..`, the `sub/` directory, the `.ogg` files (and no
#      non-audio `notes.txt`), and the now-playing pane showing `No track`;
#   2. `j` moves the selection marker: `> ..` -> `> sub/` -> `> a.ogg`; the
#      target marker was absent before the key, so the checks are not vacuous;
#   3. Enter on `a.ogg` opens it (`Now: a.ogg`), reaches `State: Playing`, then
#      `State: Ended` (generous timeout; -O0 -fsafe decode is not assumed to be
#      real time) and the hermetic WAV sink is the exact short.ogg payload
#      (44 + 26460 = 26504 bytes) after `q` closes/patches the header;
#   4. `a` adds the current track (`Playlist: 1`, no `Playlist: 0` afterwards)
#      and `d` removes it (`Playlist: 0` + `removed from playlist`);
#   5. `q` exits rc 0, shows the cursor, and restores the exact pty termios
#      captured before start (raw mode was proven active during the run, so the
#      restore check cannot pass vacuously);
#   6. Amendment 1 Win9x gate: emit/build ui.zig for default `-osw` (9x no-CRT),
#      assert PE32 i386, no msvcrt import, and the closed-world
#      scripts/win32_cross/check_win9x_imports.sh <exe> 9x gate. Real Win98/Me
#      hardware verification remains operator-pending and is NOT claimed.
#   7. records the `--dump-c89` md5 for ui.zig (single-file stdout recipe),
#      stable over two runs.
#
# Non-vacuous: the first-frame assertions require the exact 80-column rows and
# pinned borders (not just any text); each navigation target is absent before
# its key; the WAV file is absent before Enter and must have the exact decoded
# payload after Ended; the playlist counts must actually change (0->1->0); raw
# mode must be observed active during the run before "restored" is meaningful;
# and the driver exits nonzero if any CHECK is 0.
#
# POSIX sh + coreutils + python3 + file + i686-w64-mingw32-objdump. Run from
# anywhere (paths resolved from this script).
#
# Env: ZIG  seed compiler (default: first of /tmp/m7_t1_seed/zig1_5_clean,
#           /tmp/z9play_seed/zig1_5_clean; rebuilt from release/seed if absent)
#      OUT  scratch dir (default /tmp/z9play_tier_tui)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
OUT="${OUT:-/tmp/z9play_tier_tui}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

for tool in python3 md5sum file bash timeout; do
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

# Seed v101 (fixed point b299b4b4...); rebuild from the committed archive when
# neither the env override nor the conventional scratch build is present.
if [ -z "${ZIG:-}" ] || [ ! -x "${ZIG:-}" ]; then
    ZIG=""
    for cand in /tmp/m7_t1_seed/zig1_5_clean /tmp/z9play_seed/zig1_5_clean \
                /tmp/z9play_seed_v98/zig1_5_clean; do
        if [ -x "$cand" ]; then
            ZIG="$cand"
            break
        fi
    done
fi
if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "== rebuilding seed v101 from release/seed/zig1-seed.tgz =="
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
    pass_case "seed v101 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3"
else
    fail_case "seed compiler md5 is not the v101 fixed point (got ${SEED_MD5:-<none>})"
fi

echo
echo "== building ui.zig (binding recipe, -fsafe) =="
if ! timeout 600 "$ZIG" -fsafe -o "$OUT" examples/z98/z9play/ui.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -20 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/z9play-tui" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
PROG="$OUT/z9play-tui"
if [ ! -x "$PROG" ]; then
    echo "FAIL: $PROG not built"
    exit 1
fi
pass_case "ui.zig -fsafe compile + emitted build_target.sh linux"

# Fresh scratch: parent (`..`), one subdir, two .ogg files (short.ogg: 1ch
# 44100Hz, 0.3 s => 26460 PCM bytes), and a non-audio file that must be filtered.
SCRATCH="$OUT/scratch"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/sub"
cp "$Z9DIR/testdata/short.ogg" "$SCRATCH/a.ogg"
cp "$Z9DIR/testdata/short.ogg" "$SCRATCH/b.ogg"
printf 'not audio\n' >"$SCRATCH/notes.txt"

cat >"$OUT/driver.py" <<'PY'
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

PROG, SCRATCH, LOG, WAV = sys.argv[1:5]
EXPECTED_DATA = 26460
EXPECTED_WAV = 44 + EXPECTED_DATA

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
before = termios.tcgetattr(slave)

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


def parse_first_frame():
    data = bytes(buf)
    rows = []
    p = 0
    for r0 in range(25):
        marker = ("\x1b[%d;1H" % (r0 + 1)).encode()
        k = data.find(marker, p)
        if k < 0:
            return None
        p = k + len(marker)
        rows.append(data[p:p + 80])
        p += 80
    return rows


def waitstatus_to_exitcode(st):
    if os.WIFEXITED(st):
        return os.WEXITSTATUS(st)
    if os.WIFSIGNALED(st):
        return -os.WTERMSIG(st)
    return -1


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
    return waitstatus_to_exitcode(st)


try:
    rows = None
    end = time.time() + 30
    while time.time() < end:
        rows = parse_first_frame()
        if rows is not None:
            break
        pump(0.1)

    check("first-frame-25-rows", rows is not None and len(rows) == 25)
    if rows is None:
        rows = [b""] * 25
    check("first-frame-80-cols", all(len(r) == 80 for r in rows))

    joined = b"".join(rows)
    check("top-border-80", rows[0][0:1] == b"+" and rows[0][79:80] == b"+"
          and b" z9play " in rows[0])
    body_ok = True
    for idx in (1, 2, 3, 4, 5, 20, 22, 23):
        r = rows[idx]
        if len(r) != 80 or r[0:1] != b"|" or r[79:80] != b"|":
            body_ok = False
    check("pane-borders-pinned", body_ok)
    sep = rows[21]
    check("separator-and-bottom-borders",
          sep[0:1] == b"+" and sep[44:45] == b"+" and sep[79:80] == b"+"
          and rows[24][0:1] == b"+" and rows[24][79:80] == b"+")
    check("dir-pane-shows-current-path", SCRATCH.encode() in rows[1][1:44])
    check("now-playing-shows-no-track", b"No track" in rows[1][45:79])
    check("dir-listing-parent-and-subdir",
          rows[2][1:3] == b"> " and rows[2][3:5] == b".."
          and rows[3][1:3] == b"  " and rows[3][3:7] == b"sub/")
    check("dir-listing-ogg-files",
          rows[4][3:8] == b"a.ogg" and rows[5][3:8] == b"b.ogg")
    check("dir-listing-filters-non-audio", b"notes.txt" not in joined)
    check("now-playing-absent-before-play", b"Now:" not in rows[1])
    check("wav-absent-before-play", not os.path.exists(WAV))

    during = termios.tcgetattr(slave)
    raw_active = (during != before
                  and (during[3] & termios.ECHO) == 0
                  and (during[3] & termios.ICANON) == 0)
    check("enterraw-active-during-run", raw_active)

    mark = len(buf)
    os.write(master, b"j")
    check("nav-down-moves-to-subdir", wait_bytes(b"> sub/", 15, mark))

    mark = len(buf)
    check("ogg-not-selected-before-second-nav",
          b"> a.ogg" not in bytes(buf[:mark]))
    os.write(master, b"j")
    check("nav-down-moves-to-ogg", wait_bytes(b"> a.ogg", 15, mark))

    play_mark = len(buf)
    os.write(master, b"\r")
    check("enter-opens-ogg", wait_bytes(b"Now: a.ogg", 90, play_mark))
    check("play-state-playing", wait_bytes(b"State: Playing", 90, play_mark))
    check("play-reaches-ended", wait_bytes(b"State: Ended", 240, play_mark))

    try:
        wav_size_ended = os.path.getsize(WAV)
    except OSError:
        wav_size_ended = -1
    check("wav-payload-complete-at-ended", wav_size_ended == EXPECTED_WAV)

    check("playlist-empty-before-add",
          b"Playlist: 0" in buf[play_mark:] and b"Playlist: 1" not in buf[play_mark:])

    add_mark = len(buf)
    os.write(master, b"a")
    check("playlist-add-counts-one", wait_bytes(b"Playlist: 1", 15, add_mark))
    check("playlist-add-status", b"added to playlist" in buf[add_mark:])
    check("playlist-add-no-stale-zero", b"Playlist: 0" not in buf[add_mark:])

    rm_mark = len(buf)
    os.write(master, b"d")
    check("playlist-remove-status", wait_bytes(b"removed from playlist", 15, rm_mark))
    check("playlist-remove-counts-zero", wait_bytes(b"Playlist: 0", 15, rm_mark))

    q_mark = len(buf)
    os.write(master, b"q")
    rc = wait_child(30)
    check("q-exits-rc0", rc == 0)

    after = termios.tcgetattr(slave)
    check("termios-restored-exactly", after == before)
    check("cursor-shown-on-exit", b"\x1b[?25h" in buf[q_mark:])
    check("screen-cleared-on-exit", b"\x1b[2J" in buf[q_mark:])

    try:
        data = open(WAV, "rb").read()
    except OSError:
        data = b""
    hdr_ok = (len(data) == EXPECTED_WAV
              and data[0:4] == b"RIFF" and data[8:12] == b"WAVE"
              and data[36:40] == b"data")
    check("wav-canonical-size-header", hdr_ok)
    if len(data) >= 44:
        riff = struct.unpack("<I", data[4:8])[0]
        data_bytes = struct.unpack("<I", data[40:44])[0]
        check("wav-size-fields-patched",
              riff == EXPECTED_WAV - 8 and data_bytes == EXPECTED_DATA)
    else:
        check("wav-size-fields-patched", False)
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
print("DRIVER_CHECKS total=%d passed=%d failed=%d" % (checks, checks - fails, fails))
sys.exit(0 if fails == 0 else 1)
PY

echo
echo "== TUI behavior under a pty (100x30 window, fixed 80x25 frame) =="
WAV="$OUT/tui.wav"
LOG="$OUT/tui.log"
rm -f "$WAV" "$LOG" "$OUT/driver.out" "$OUT/driver.err"
timeout 420 python3 "$OUT/driver.py" "$PROG" "$SCRATCH" "$LOG" "$WAV" \
    >"$OUT/driver.out" 2>"$OUT/driver.err"
DRV_RC=$?
SAW_DONE=0
while IFS= read -r line; do
    case "$line" in
        "CHECK "*)
            body=${line#CHECK }
            name=${body%%=*}
            val=${body##*=}
            if [ "$val" = "1" ]; then
                pass_case "$name"
            else
                fail_case "$name"
            fi
            ;;
        "DRIVER_DONE=1")
            SAW_DONE=1
            ;;
        "DRIVER_CHECKS "*)
            echo "driver: ${line#DRIVER_CHECKS }"
            ;;
        "DRIVER_ERROR "*)
            fail_case "driver: ${line#DRIVER_ERROR }"
            ;;
    esac
done <"$OUT/driver.out"
if [ "$SAW_DONE" -ne 1 ]; then
    fail_case "pty driver completed (rc=$DRV_RC; see $OUT/driver.err)"
fi
echo "pty log: $LOG ($(LC_ALL=C wc -c <"$LOG" 2>/dev/null | tr -d ' ') bytes)"
if [ -s "$OUT/driver.err" ]; then
    tail -10 "$OUT/driver.err" | sed 's/^/       /'
fi

echo
echo "== Win9x gate: -osw TUI emit/build + PE/import check (Amendment 1) =="
WIN_EMIT="$OUT/win_emit"
mkdir -p "$WIN_EMIT"
timeout 900 "$ZIG" -osw -o "$WIN_EMIT" examples/z98/z9play/ui.zig \
    >"$OUT/win_emit.log" 2>&1
WIN_EMIT_RC=$?
if [ "$WIN_EMIT_RC" -eq 0 ] && [ -f "$WIN_EMIT/build_target.sh" ]; then
    pass_case "ui.zig -osw emit produced build_target.sh (default 9x no-CRT)"
else
    fail_case "ui.zig -osw emit failed (rc=$WIN_EMIT_RC; see $OUT/win_emit.log)"
fi
tail -5 "$OUT/win_emit.log" | sed 's/^/       /'

EXE="$OUT/z9play-tui.exe"
if sh "$WIN_EMIT/build_target.sh" mingw "$EXE" >"$OUT/win_build.log" 2>&1 \
    && [ -f "$EXE" ]; then
    pass_case "emitted build_target.sh mingw produced exe ($(LC_ALL=C wc -c <"$EXE" | tr -d ' ') bytes)"
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
echo "== --dump-c89 md5 (ui.zig, single-file stdout recipe) =="
timeout 600 "$ZIG" --dump-c89 examples/z98/z9play/ui.zig \
    >"$OUT/dump1.c89" 2>"$OUT/dump1.err"
DUMP_RC1=$?
timeout 600 "$ZIG" --dump-c89 examples/z98/z9play/ui.zig \
    >"$OUT/dump2.c89" 2>"$OUT/dump2.err"
DUMP_RC2=$?
MD1="$(md5sum "$OUT/dump1.c89" 2>/dev/null | awk '{print $1}')"
MD2="$(md5sum "$OUT/dump2.c89" 2>/dev/null | awk '{print $1}')"
echo "--dump-c89 md5: ${MD1:-<none>}"
if [ "$DUMP_RC1" -eq 0 ] && [ "$DUMP_RC2" -eq 0 ] \
    && [ -n "$MD1" ] && [ "$MD1" = "$MD2" ]; then
    pass_case "--dump-c89 md5 recorded stable 2x: $MD1"
else
    fail_case "--dump-c89 failed/unstable (rc=$DUMP_RC1/$DUMP_RC2 md5=$MD1/$MD2)"
fi

echo
echo "== tier_tui summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_TUI FAIL"
    exit 1
fi
echo "TIER_TUI PASS"
exit 0
