#!/bin/sh
# tier_dbg.sh — P3-M3 live debugger gate: Linux ptrace backend + DWARF lines.
#
# Builds z9dbg and the live fixture with the binding seed recipe, then runs
# scripted sessions that exercise:
#   - entry stop at the first executable mapped line;
#   - break at a known source line (hit within 100 ms) with the exact display;
#   - empty-line reject and declaration-line snap;
#   - step-into advancing to the next mapped source line;
#   - backtrace listing function names (frame-pointer unwind);
#   - dump variables writes a snapshot then auto-resumes to completion;
#   - quit restores every planted int3 and detaches (debuggee lives);
#   - a -g-less build degrades to function-entry breakpoints with the exact
#     `break: no debug info` message.
# It also builds the required test set (hello, mud_server, lisp_interpreter_curr,
# z9torr) and records entry-breakpoint latency + z9dbg RSS under a 32 MB limit.
#
# Env: ZIG  seed-built zig1_5_clean (required)
#      OUT  scratch dir (default /tmp/z9dbg_tier)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:?set ZIG to the seed-built zig1_5_clean}"
OUT="${OUT:-/tmp/z9dbg_tier}"
EXP="$Z9DIR/tests/expected"
LIVE_REL="examples/z98/z9dbg/tests/fixtures/live/main.zig"
LIVE="$ROOT/$LIVE_REL"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
if ! command -v gcc >/dev/null 2>&1; then
    echo "FAIL: gcc not found"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/live" "$OUT/live_nodbg" "$OUT/hello" "$OUT/mud" "$OUT/lisp" "$OUT/z9torr"

GCCFLAGS="-m32 -std=c89 -O0 -I $ROOT/sf/src/include"
DUMPFLAGS="-d"

echo "== building z9dbg (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT/bin" examples/z98/z9dbg/main.zig >"$OUT/bin/zig.log" 2>&1; then
    echo "FAIL: z9dbg zig compile (see $OUT/bin/zig.log)"
    tail -30 "$OUT/bin/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/bin/build_target.sh" linux "$OUT/bin/prog" >"$OUT/bin/build.log" 2>&1; then
    echo "FAIL: z9dbg target link (see $OUT/bin/build.log)"
    tail -30 "$OUT/bin/build.log" | sed 's/^/       /'
    exit 1
fi
Z9DBG="$OUT/bin/prog"
[ -x "$Z9DBG" ] || { echo "FAIL: $Z9DBG not built"; exit 1; }

# build_debuggee <name> <entry-rel> <with-debug:0|1>
build_debuggee() {
    bd_name="$1"; bd_entry="$2"; bd_dbg="$3"
    bd_dir="$OUT/$bd_name"
    mkdir -p "$bd_dir"
    if ! ( cd "$ROOT" && timeout 300 "$ZIG" -q $DUMPFLAGS --output-dir "$bd_dir" "$bd_entry" ) \
            >"$bd_dir/zig.log" 2>&1; then
        echo "FAIL: dump $bd_name (see $bd_dir/zig.log)"
        tail -20 "$bd_dir/zig.log" | sed 's/^/       /'
        return 1
    fi
    bd_g="$GCCFLAGS"
    if [ "$bd_dbg" = "1" ]; then
        bd_g="$bd_g -g -gdwarf-2 -fno-omit-frame-pointer"
    fi
    if ! ( cd "$bd_dir" && timeout 300 sh -c "gcc $bd_g -c *.c" ) >"$bd_dir/gcc.log" 2>&1; then
        echo "FAIL: gcc $bd_name (see $bd_dir/gcc.log)"
        tail -20 "$bd_dir/gcc.log" | sed 's/^/       /'
        return 1
    fi
    if ! ( cd "$bd_dir" && timeout 120 gcc -m32 -O0 *.o -o prog ) >>"$bd_dir/gcc.log" 2>&1; then
        echo "FAIL: link $bd_name (see $bd_dir/gcc.log)"
        tail -20 "$bd_dir/gcc.log" | sed 's/^/       /'
        return 1
    fi
    return 0
}

echo "== building fixtures and test set =="
BUILD_OK=1
build_debuggee live "$LIVE_REL" 1 || BUILD_OK=0
build_debuggee live_nodbg "$LIVE_REL" 0 || BUILD_OK=0
build_debuggee hello examples/z98/hello/main.zig 1 || BUILD_OK=0
build_debuggee mud examples/z98/mud_server/main.zig 1 || BUILD_OK=0
build_debuggee lisp examples/z98/lisp_interpreter_curr/main.zig 1 || BUILD_OK=0
build_debuggee z9torr examples/z98/z9torr/main.zig 1 || BUILD_OK=0
if [ "$BUILD_OK" -ne 1 ]; then
    echo "TIER_DBG FAIL (build)"
    exit 1
fi

render_expected() {
    sed -e "s|@LIVE@|$LIVE_REL|g" -e "s|@SNAP@|$1|g" "$2"
}

# run_live_case <name> <exe> <input> <expected> <done-file> [snap-file]
run_live_case() {
    rl_name="$1"; rl_exe="$2"; rl_in="$3"; rl_exp="$4"; rl_done="$5"; rl_snap="${6:-}"
    render_expected "$rl_snap" "$rl_exp" >"$OUT/$rl_name.exp"
    sed "s|@SNAP@|$rl_snap|g" "$rl_in" >"$OUT/$rl_name.in"
    rl_i=1
    while [ "$rl_i" -le 2 ]; do
        rm -f "$rl_done" "$rl_snap"
        if ! "$Z9DBG" "$rl_exe" "$rl_done" <"$OUT/$rl_name.in" >"$OUT/$rl_name.$rl_i.out" 2>"$OUT/$rl_name.$rl_i.err"; then
            fail_case "$rl_name run $rl_i rc"
            tail -20 "$OUT/$rl_name.$rl_i.err" | sed 's/^/       /'
        fi
        if cmp -s "$OUT/$rl_name.exp" "$OUT/$rl_name.$rl_i.out"; then
            :
        else
            fail_case "$rl_name run $rl_i output"
            diff -u "$OUT/$rl_name.exp" "$OUT/$rl_name.$rl_i.out" | sed 's/^/       /'
        fi
        rl_j=0
        while [ "$rl_j" -lt 40 ] && [ ! -f "$rl_done" ]; do
            sleep 0.05
            rl_j=$((rl_j + 1))
        done
        if [ -f "$rl_done" ]; then
            :
        else
            fail_case "$rl_name run $rl_i debuggee did not complete (int3 not restored?)"
        fi
        if [ -n "$rl_snap" ]; then
            if grep -qF "stopped at $LIVE_REL:17" "$rl_snap" &&
               grep -qF "function middle" "$rl_snap"; then
                :
            else
                fail_case "$rl_name run $rl_i snapshot content"
            fi
        fi
        if [ "$rl_i" -gt 1 ]; then
            cmp -s "$OUT/$rl_name.1.out" "$OUT/$rl_name.$rl_i.out" || fail_case "$rl_name run $rl_i determinism"
        fi
        rl_i=$((rl_i + 1))
    done
}

echo "== live fixture: break / backtrace / empty / declaration =="
before=$FAILS
run_live_case live_break "$OUT/live/prog" "$Z9DIR/tests/session_live_break.in" \
    "$EXP/live_break.txt" "$OUT/live-done-break.txt"
[ "$FAILS" -eq "$before" ] && pass_case "live break+backtrace+snap"

echo "== live fixture: step advances mapped lines =="
before=$FAILS
run_live_case live_step "$OUT/live/prog" "$Z9DIR/tests/session_live_step.in" \
    "$EXP/live_step.txt" "$OUT/live-done-step.txt"
[ "$FAILS" -eq "$before" ] && pass_case "live step+backtrace"

echo "== live fixture: dump variables auto-resumes =="
before=$FAILS
run_live_case live_dump "$OUT/live/prog" "$Z9DIR/tests/session_live_dump.in" \
    "$EXP/live_dump.txt" "$OUT/live-done-dump.txt" "$OUT/live-snap.txt"
[ "$FAILS" -eq "$before" ] && pass_case "live dump+resume"

echo "== live fixture: quit restores bytes and detaches =="
before=$FAILS
run_live_case live_restore "$OUT/live/prog" "$Z9DIR/tests/session_live_restore.in" \
    "$EXP/live_restore.txt" "$OUT/live-done-restore.txt"
[ "$FAILS" -eq "$before" ] && pass_case "live quit restore"

echo "== no-debug-info build degrades to function entry =="
before=$FAILS
run_live_case live_nodbg "$OUT/live_nodbg/prog" "$Z9DIR/tests/session_live_nodbg.in" \
    "$EXP/live_nodbg.txt" "$OUT/live-done-nodbg.txt"
[ "$FAILS" -eq "$before" ] && pass_case "live no-debug-info fallback"

echo "== source-line breakpoint latency =="
printf 'break main.zig:12\ncontinue\nquit\n' >"$OUT/live_lat.in"
rm -f "$OUT/live-done-lat.txt"
Z9DBG_TIMING=1 "$Z9DBG" "$OUT/live/prog" "$OUT/live-done-lat.txt" <"$OUT/live_lat.in" \
    >"$OUT/live_lat.out" 2>"$OUT/live_lat.err"
lat_ms=$(sed -n 's/^z9dbg: breakpoint latency \([0-9][0-9]*\) ms$/\1/p' "$OUT/live_lat.err" | tail -1)
if [ -n "$lat_ms" ] && [ "$lat_ms" -lt 100 ]; then
    pass_case "source breakpoint latency ${lat_ms}ms < 100ms"
else
    fail_case "source breakpoint latency (got '${lat_ms:-none}')"
fi
rm -f "$OUT/live-done-lat.txt"

# smoke_set <name> <exe> [args...]
# Runs one entry-stop/quit session, requires the stop display and the timing
# line (<100 ms), and records peak RSS from /usr/bin/time -v under ulimit -v.
smoke_set() {
    ss_name="$1"; ss_exe="$2"; shift 2
    printf 'quit\n' >"$OUT/$ss_name.in"
    if ! command -v /usr/bin/time >/dev/null 2>&1; then
        fail_case "$ss_name /usr/bin/time missing"
        return
    fi
    Z9DBG_TIMING=1 timeout 20 /usr/bin/time -v sh -c 'ulimit -v 32768; exec "$0" "$@"' \
        "$Z9DBG" "$ss_exe" "$@" <"$OUT/$ss_name.in" \
        >"$OUT/$ss_name.out" 2>"$OUT/$ss_name.err"
    ss_rc=$?
    if [ "$ss_rc" -ne 0 ]; then
        fail_case "$ss_name session rc=$ss_rc"
        tail -10 "$OUT/$ss_name.err" | sed 's/^/       /'
        return
    fi
    if grep -qF "Z98 debugger has started..." "$OUT/$ss_name.out" &&
       grep -qE "^Stopped at .+:[0-9]+$" "$OUT/$ss_name.out"; then
        pass_case "$ss_name entry stop"
    else
        fail_case "$ss_name entry stop display"
        head -10 "$OUT/$ss_name.out" | sed 's/^/       /'
    fi
    ss_ms=$(sed -n 's/^z9dbg: entry latency \([0-9][0-9]*\) ms$/\1/p' "$OUT/$ss_name.err" | tail -1)
    if [ -n "$ss_ms" ] && [ "$ss_ms" -lt 100 ]; then
        pass_case "$ss_name latency ${ss_ms}ms < 100ms"
    else
        fail_case "$ss_name latency (got '${ss_ms:-none}')"
    fi
    ss_rss=$(sed -n 's/^[[:space:]]*Maximum resident set size (kbytes): \([0-9][0-9]*\)$/\1/p' "$OUT/$ss_name.err" | tail -1)
    if [ -n "$ss_rss" ] && [ "$ss_rss" -lt 32768 ]; then
        pass_case "$ss_name RSS ${ss_rss}KB < 32768KB"
    else
        fail_case "$ss_name RSS (got '${ss_rss:-none}')"
    fi
}

echo "== test set: hello =="
before=$FAILS
smoke_set hello "$OUT/hello/prog"
[ "$FAILS" -eq "$before" ] && pass_case "hello test-set"
echo "== test set: mud_server =="
before=$FAILS
smoke_set mud "$OUT/mud/prog"
pkill -f "$OUT/mud/prog" >/dev/null 2>&1 || true
[ "$FAILS" -eq "$before" ] && pass_case "mud_server test-set"
echo "== test set: lisp_interpreter_curr =="
before=$FAILS
smoke_set lisp "$OUT/lisp/prog"
[ "$FAILS" -eq "$before" ] && pass_case "lisp_interpreter_curr test-set"
echo "== test set: z9torr (stress) =="
before=$FAILS
smoke_set z9torr "$OUT/z9torr/prog"
[ "$FAILS" -eq "$before" ] && pass_case "z9torr test-set"

# cleanup any detached long-running smoke children
pkill -f "$OUT/mud/prog" >/dev/null 2>&1 || true

echo
echo "== tier_dbg summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DBG FAIL"
    exit 1
fi
echo "TIER_DBG PASS"
exit 0
