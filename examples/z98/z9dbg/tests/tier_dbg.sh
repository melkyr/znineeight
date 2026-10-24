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
#     `break: no debug info` message;
#   - pre-entry signal/exit honesty, DWARF 5 notice, missing .cnames and FPO
#     chain warnings, map discovery/ambiguity and PIE-bias warning.
# It also builds the required test set (hello, mud_server, lisp_interpreter_curr,
# z9play) and runs full break/continue/step/backtrace/dump sessions on each,
# then records entry-breakpoint latency + z9dbg RSS under a 32 MB limit.
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
mkdir -p "$OUT/bin" "$OUT/live" "$OUT/live_nodbg" "$OUT/live_fpo" "$OUT/live_dwarf5" \
    "$OUT/earlyexit" "$OUT/crashinit" "$OUT/loopline" "$OUT/hello" "$OUT/mud" "$OUT/lisp" "$OUT/z9play" "$OUT/z9torr"

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

# build_debuggee <name> <entry-rel> <mode:dbg|nodbg|fpo|dwarf5>
build_debuggee() {
    bd_name="$1"; bd_entry="$2"; bd_mode="$3"
    bd_dir="$OUT/$bd_name"
    mkdir -p "$bd_dir"
    if ! ( cd "$ROOT" && timeout 300 "$ZIG" -q $DUMPFLAGS --output-dir "$bd_dir" "$bd_entry" ) \
            >"$bd_dir/zig.log" 2>&1; then
        echo "FAIL: dump $bd_name (see $bd_dir/zig.log)"
        tail -20 "$bd_dir/zig.log" | sed 's/^/       /'
        return 1
    fi
    bd_g="$GCCFLAGS"
    if [ "$bd_mode" = "dbg" ]; then
        bd_g="$bd_g -g -gdwarf-2 -fno-omit-frame-pointer"
    elif [ "$bd_mode" = "fpo" ]; then
        bd_g="-m32 -std=c89 -O2 -g -gdwarf-2 -fomit-frame-pointer -I $ROOT/sf/src/include"
    elif [ "$bd_mode" = "dwarf5" ]; then
        bd_g="$bd_g -g -gdwarf-5 -fno-omit-frame-pointer"
    fi
    if ! ( cd "$bd_dir" && timeout 300 sh -c "gcc $bd_g -c *.c" ) >"$bd_dir/gcc.log" 2>&1; then
        echo "FAIL: gcc $bd_name (see $bd_dir/gcc.log)"
        tail -20 "$bd_dir/gcc.log" | sed 's/^/       /'
        return 1
    fi
    if ! ( cd "$bd_dir" && timeout 120 gcc -m32 *.o -o prog ) >>"$bd_dir/gcc.log" 2>&1; then
        echo "FAIL: link $bd_name (see $bd_dir/gcc.log)"
        tail -20 "$bd_dir/gcc.log" | sed 's/^/       /'
        return 1
    fi
    return 0
}

echo "== building fixtures and test set =="
BUILD_OK=1
build_debuggee live "$LIVE_REL" dbg || BUILD_OK=0
build_debuggee live_nodbg "$LIVE_REL" nodbg || BUILD_OK=0
build_debuggee live_fpo "$LIVE_REL" fpo || BUILD_OK=0
build_debuggee live_dwarf5 "$LIVE_REL" dwarf5 || BUILD_OK=0
build_debuggee earlyexit examples/z98/z9dbg/tests/fixtures/earlyexit/main.zig dbg || BUILD_OK=0
build_debuggee crashinit examples/z98/z9dbg/tests/fixtures/crashinit/main.zig dbg || BUILD_OK=0
build_debuggee loopline examples/z98/z9dbg/tests/fixtures/loopline/main.zig dbg || BUILD_OK=0
build_debuggee hello examples/z98/hello/main.zig dbg || BUILD_OK=0
build_debuggee mud examples/z98/mud_server/main.zig dbg || BUILD_OK=0
build_debuggee lisp examples/z98/lisp_interpreter_curr/main.zig dbg || BUILD_OK=0
build_debuggee z9play examples/z98/z9play/main.zig dbg || BUILD_OK=0
build_debuggee z9torr examples/z98/z9torr/main.zig dbg || BUILD_OK=0
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
               grep -qF "function middle" "$rl_snap" &&
               grep -qF "#1 main at $LIVE_REL:21 (decl)" "$rl_snap"; then
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

# run_set_case <name> <exe> <input> <expected> <snap> <snap-grep1> <snap-grep2> [args...]
# Test-set session: child stdout/stderr go to /dev/null so the golden is only
# debugger output; a detached debuggee is killed after each run.
run_set_case() {
    rs_name="$1"; rs_exe="$2"; rs_in="$3"; rs_exp="$4"; rs_snap="$5"; rs_g1="$6"; rs_g2="$7"
    shift 7
    sed -e "s|@SNAP@|$rs_snap|g" "$rs_exp" >"$OUT/$rs_name.exp"
    sed -e "s|@SNAP@|$rs_snap|g" "$rs_in" >"$OUT/$rs_name.in"
    rs_i=1
    while [ "$rs_i" -le 2 ]; do
        rm -f "$rs_snap"
        Z9DBG_CHILD_OUT=/dev/null timeout 30 "$Z9DBG" "$rs_exe" "$@" \
            <"$OUT/$rs_name.in" >"$OUT/$rs_name.$rs_i.out" 2>"$OUT/$rs_name.$rs_i.err"
        rs_rc=$?
        [ "$rs_rc" -eq 0 ] || fail_case "$rs_name run $rs_i rc=$rs_rc"
        if cmp -s "$OUT/$rs_name.exp" "$OUT/$rs_name.$rs_i.out"; then
            :
        else
            fail_case "$rs_name run $rs_i output"
            diff -u "$OUT/$rs_name.exp" "$OUT/$rs_name.$rs_i.out" | sed 's/^/       /'
        fi
        if [ -f "$rs_snap" ] && grep -qF "$rs_g1" "$rs_snap" && grep -qF "$rs_g2" "$rs_snap"; then
            :
        else
            fail_case "$rs_name run $rs_i snapshot content"
        fi
        pkill -9 -x prog >/dev/null 2>&1 || true
        sleep 0.1
        if [ "$rs_i" -gt 1 ]; then
            cmp -s "$OUT/$rs_name.1.out" "$OUT/$rs_name.$rs_i.out" || fail_case "$rs_name run $rs_i determinism"
        fi
        rs_i=$((rs_i + 1))
    done
}

# run_plain_case <name> <exe> <input> <expected> [args...]
run_plain_case() {
    rp_name="$1"; rp_exe="$2"; rp_in="$3"; rp_exp="$4"
    shift 4
    rp_i=1
    while [ "$rp_i" -le 2 ]; do
        Z9DBG_CHILD_OUT=/dev/null timeout 30 "$Z9DBG" "$rp_exe" "$@" \
            <"$rp_in" >"$OUT/$rp_name.$rp_i.out" 2>"$OUT/$rp_name.$rp_i.err"
        rp_rc=$?
        [ "$rp_rc" -eq 0 ] || fail_case "$rp_name run $rp_i rc=$rp_rc"
        if cmp -s "$rp_exp" "$OUT/$rp_name.$rp_i.out"; then
            :
        else
            fail_case "$rp_name run $rp_i output"
            diff -u "$rp_exp" "$OUT/$rp_name.$rp_i.out" | sed 's/^/       /'
        fi
        pkill -9 -x prog >/dev/null 2>&1 || true
        sleep 0.1
        if [ "$rp_i" -gt 1 ]; then
            cmp -s "$OUT/$rp_name.1.out" "$OUT/$rp_name.$rp_i.out" || fail_case "$rp_name run $rp_i determinism"
        fi
        rp_i=$((rp_i + 1))
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

echo "== F3: same-line loop breakpoint re-arms =="
before=$FAILS
run_plain_case loopline "$OUT/loopline/prog" "$Z9DIR/tests/session_loopline.in" \
    "$EXP/loopline.txt"
[ "$FAILS" -eq "$before" ] && pass_case "loopline breakpoint re-arm (4 hits)"

echo "== test set session: hello =="
before=$FAILS
run_set_case set_hello "$OUT/hello/prog" "$Z9DIR/tests/session_set_hello.in" \
    "$EXP/set_hello.txt" "$OUT/set-hello.snap" \
    "stopped at examples/z98/hello/greetings.zig:3" "function sayHello"
[ "$FAILS" -eq "$before" ] && pass_case "hello break/continue/step/dump session"

echo "== test set session: mud_server =="
before=$FAILS
run_set_case set_mud "$OUT/mud/prog" "$Z9DIR/tests/session_set_mud.in" \
    "$EXP/set_mud.txt" "$OUT/set-mud.snap" \
    "stopped at examples/z98/mud_server/main.zig:55" "function initRooms"
[ "$FAILS" -eq "$before" ] && pass_case "mud_server break/continue/step/dump session"

echo "== test set session: lisp_interpreter_curr =="
before=$FAILS
run_set_case set_lisp "$OUT/lisp/prog" "$Z9DIR/tests/session_set_lisp.in" \
    "$EXP/set_lisp.txt" "$OUT/set-lisp.snap" \
    "stopped at examples/z98/lisp_interpreter_curr/main.zig:117" "function main"
[ "$FAILS" -eq "$before" ] && pass_case "lisp_interpreter_curr break/continue/step/dump session"

echo "== test set session: z9play (stress) =="
before=$FAILS
run_set_case set_z9play "$OUT/z9play/prog" "$Z9DIR/tests/session_set_z9play.in" \
    "$EXP/set_z9play.txt" "$OUT/set-z9play.snap" \
    "stopped at examples/z98/z9play/main.zig:453" "function main" \
    --info "$ROOT/examples/z98/z9play/testdata/short.ogg"
[ "$FAILS" -eq "$before" ] && pass_case "z9play break/continue/step/dump session"

echo "== entry-stop honesty: pre-entry exit and signal =="
printf 'quit\n' >"$OUT/entryquit.in"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/earlyexit/prog" <"$OUT/entryquit.in" \
    >"$OUT/earlyexit.out" 2>"$OUT/earlyexit.err"
ee_rc=$?
if [ "$ee_rc" -eq 1 ] && grep -qF "z9dbg: debuggee exited before entry stop" "$OUT/earlyexit.out"; then
    pass_case "pre-entry exit reported honestly"
else
    fail_case "pre-entry exit honesty (rc=$ee_rc)"
    cat "$OUT/earlyexit.out" | sed 's/^/       /'
fi
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/crashinit/prog" <"$OUT/entryquit.in" \
    >"$OUT/crashinit.out" 2>"$OUT/crashinit.err"
ci_rc=$?
if [ "$ci_rc" -eq 1 ] &&
   grep -qF "z9dbg: debuggee stopped by signal " "$OUT/crashinit.out" &&
   grep -qF " before entry breakpoint" "$OUT/crashinit.out"; then
    pass_case "pre-entry signal reported honestly"
else
    fail_case "pre-entry signal honesty (rc=$ci_rc)"
    cat "$OUT/crashinit.out" | sed 's/^/       /'
fi

echo "== FPO chain warning =="
printf 'backtrace\nquit\n' >"$OUT/fpo.in"
rm -f "$OUT/fpo-done.txt"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/live_fpo/prog" "$OUT/fpo-done.txt" <"$OUT/fpo.in" \
    >"$OUT/fpo.out" 2>"$OUT/fpo.err"
if grep -qF "backtrace: frame chain unreliable; build with -fno-omit-frame-pointer" "$OUT/fpo.out"; then
    pass_case "FPO frame-chain warning"
else
    fail_case "FPO frame-chain warning missing"
    cat "$OUT/fpo.out" | sed 's/^/       /'
fi

echo "== DWARF 5 unsupported notice =="
printf 'break main.zig:12\ncontinue\nquit\n' >"$OUT/dwarf5.in"
rm -f "$OUT/dwarf5-done.txt"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/live_dwarf5/prog" "$OUT/dwarf5-done.txt" \
    <"$OUT/dwarf5.in" >"$OUT/dwarf5.out" 2>"$OUT/dwarf5.err"
if grep -qF "debug info present but unsupported DWARF version" "$OUT/dwarf5.err" &&
   grep -qF "break: no debug info" "$OUT/dwarf5.out"; then
    pass_case "DWARF 5 notice + function-entry degradation"
else
    fail_case "DWARF 5 notice/degradation"
    cat "$OUT/dwarf5.err" "$OUT/dwarf5.out" | sed 's/^/       /'
fi

echo "== missing .cnames backtrace notice =="
rm -rf "$OUT/live_nocnames"
mkdir -p "$OUT/live_nocnames"
cp "$OUT/live/prog" "$OUT/live_nocnames/prog"
cp "$OUT/live/"*.z98dbg.syms "$OUT/live_nocnames/"
cp "$OUT/live/"*.z98dbg.lines "$OUT/live_nocnames/"
printf 'break main.zig:12\ncontinue\nbacktrace\nquit\n' >"$OUT/nocnames.in"
rm -f "$OUT/nocnames-done.txt"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/live_nocnames/prog" "$OUT/nocnames-done.txt" \
    <"$OUT/nocnames.in" >"$OUT/nocnames.out" 2>"$OUT/nocnames.err"
if grep -qF "backtrace limited: no .cnames" "$OUT/nocnames.out"; then
    pass_case "no-.cnames backtrace notice"
else
    fail_case "no-.cnames notice missing"
    cat "$OUT/nocnames.out" | sed 's/^/       /'
fi

echo "== map discovery: stem preference and ambiguity =="
rm -rf "$OUT/mappref" "$OUT/mapamb"
mkdir -p "$OUT/mappref" "$OUT/mapamb"
cp "$OUT/live/prog" "$OUT/mappref/liveprog"
cp "$OUT/live/"*.z98dbg.syms "$OUT/mappref/liveprog.z98dbg.syms"
cp "$OUT/live/"*.z98dbg.lines "$OUT/mappref/liveprog.z98dbg.lines"
cp "$OUT/live/"*.z98dbg.cnames "$OUT/mappref/liveprog.z98dbg.cnames"
cp "$OUT/live/"*.z98dbg.syms "$OUT/mappref/other.z98dbg.syms"
cp "$OUT/live/"*.z98dbg.lines "$OUT/mappref/other.z98dbg.lines"
cp "$OUT/live/"*.z98dbg.cnames "$OUT/mappref/other.z98dbg.cnames"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/mappref/liveprog" "$OUT/pref-done.txt" \
    <"$OUT/entryquit.in" >"$OUT/pref.out" 2>"$OUT/pref.err"
if grep -qF "Stopped at examples/z98/z9dbg/tests/fixtures/live/main.zig:22" "$OUT/pref.out"; then
    pass_case "map stem preference"
else
    fail_case "map stem preference"
    cat "$OUT/pref.out" "$OUT/pref.err" | sed 's/^/       /'
fi
cp "$OUT/live/prog" "$OUT/mapamb/prog"
cp "$OUT/live/"*.z98dbg.syms "$OUT/mapamb/one.z98dbg.syms"
cp "$OUT/live/"*.z98dbg.lines "$OUT/mapamb/one.z98dbg.lines"
cp "$OUT/live/"*.z98dbg.syms "$OUT/mapamb/two.z98dbg.syms"
cp "$OUT/live/"*.z98dbg.lines "$OUT/mapamb/two.z98dbg.lines"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/mapamb/prog" <"$OUT/entryquit.in" \
    >"$OUT/amb.out" 2>"$OUT/amb.err"
amb_rc=$?
if [ "$amb_rc" -eq 1 ] && grep -qF "ambiguous debug map: 2 .z98dbg.syms candidates" "$OUT/amb.out"; then
    pass_case "ambiguous map reported"
else
    fail_case "ambiguous map reporting (rc=$amb_rc)"
    cat "$OUT/amb.out" "$OUT/amb.err" | sed 's/^/       /'
fi

echo "== PIE bias warning (symlinked exe) =="
rm -rf "$OUT/pielink"
mkdir -p "$OUT/pielink"
ln -s "$OUT/live/prog" "$OUT/pielink/linkprog"
cp "$OUT/live/"*.z98dbg.syms "$OUT/pielink/"
cp "$OUT/live/"*.z98dbg.lines "$OUT/pielink/"
cp "$OUT/live/"*.z98dbg.cnames "$OUT/pielink/"
Z9DBG_CHILD_OUT=/dev/null timeout 20 "$Z9DBG" "$OUT/pielink/linkprog" <"$OUT/entryquit.in" \
    >"$OUT/pie.out" 2>"$OUT/pie.err"
pie_rc=$?
if [ "$pie_rc" -eq 1 ] && grep -qF "cannot resolve PIE load bias" "$OUT/pie.err"; then
    pass_case "PIE bias warning"
else
    fail_case "PIE bias warning (rc=$pie_rc)"
    cat "$OUT/pie.out" "$OUT/pie.err" | sed 's/^/       /'
fi

echo "== source-line breakpoint latency =="
printf 'break main.zig:12\ncontinue\nquit\n' >"$OUT/live_lat.in"
rm -f "$OUT/live-done-lat.txt"
Z9DBG_TIMING=1 "$Z9DBG" "$OUT/live/prog" "$OUT/live-done-lat.txt" <"$OUT/live_lat.in" \
    >"$OUT/live_lat.out" 2>"$OUT/live_lat.err"
lat_us=$(sed -n 's/^z9dbg: breakpoint latency \([0-9][0-9]*\) us$/\1/p' "$OUT/live_lat.err" | tail -1)
if [ -n "$lat_us" ] && [ "$lat_us" -lt 100000 ]; then
    pass_case "source breakpoint latency ${lat_us}us < 100000us"
else
    fail_case "source breakpoint latency (got '${lat_us:-none}')"
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
    Z9DBG_TIMING=1 Z9DBG_CHILD_OUT=/dev/null timeout 20 /usr/bin/time -v sh -c 'ulimit -v 32768; exec "$0" "$@"' \
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
    ss_us=$(sed -n 's/^z9dbg: entry latency \([0-9][0-9]*\) us$/\1/p' "$OUT/$ss_name.err" | tail -1)
    if [ -n "$ss_us" ] && [ "$ss_us" -lt 100000 ]; then
        pass_case "$ss_name latency ${ss_us}us < 100000us"
    else
        fail_case "$ss_name latency (got '${ss_us:-none}')"
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
pkill -9 -x prog >/dev/null 2>&1 || true
sleep 0.1
[ "$FAILS" -eq "$before" ] && pass_case "mud_server test-set"
echo "== test set: lisp_interpreter_curr =="
before=$FAILS
smoke_set lisp "$OUT/lisp/prog"
[ "$FAILS" -eq "$before" ] && pass_case "lisp_interpreter_curr test-set"
echo "== test set: z9torr (stress RSS/latency) =="
before=$FAILS
smoke_set z9torr "$OUT/z9torr/prog"
[ "$FAILS" -eq "$before" ] && pass_case "z9torr test-set"

echo "== Win98/Wine: Debug-API backend + DWARF-in-PE =="
if command -v wine >/dev/null 2>&1 && command -v i686-w64-mingw32-gcc >/dev/null 2>&1 &&
   command -v i686-w64-mingw32-objdump >/dev/null 2>&1; then
    W="$OUT/win98"
    mkdir -p "$W/bin" "$W/live"
    if ( cd "$ROOT" && timeout 180 "$ZIG" -osw -o "$W/bin" examples/z98/z9dbg/main.zig ) \
            >"$W/bin/zig.log" 2>&1 &&
       sh "$W/bin/build_target.sh" mingw "$W/bin/z9dbg.exe" >"$W/bin/build.log" 2>&1; then
        if sh "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$W/bin/z9dbg.exe" 9x >"$W/import.log" 2>&1; then
            pass_case "Win98 import gate (9x)"
        else
            fail_case "Win98 import gate (9x)"
            tail -20 "$W/import.log" | sed 's/^/       /'
        fi
        if ( cd "$ROOT" && timeout 300 "$ZIG" -q -d -osw --output-dir "$W/live" "$LIVE_REL" ) \
                >"$W/live/zig.log" 2>&1 &&
           ( cd "$W/live" && timeout 300 sh -c \
                'i686-w64-mingw32-gcc -m32 -std=c89 -O0 -g -gdwarf-2 -DZIG_NO_CRT -I . -c *.c' ) \
                >"$W/live/gcc.log" 2>&1 &&
           ( cd "$W/live" && timeout 120 i686-w64-mingw32-gcc -m32 -nostdlib \
                -Wl,-e,_mainCRTStartup *.o -o prog.exe -lgcc -lkernel32 ) >>"$W/live/gcc.log" 2>&1; then
            win_case() {
                wc_name="$1"; wc_in="$2"; wc_exp="$3"
                sed "s|@LIVE@|$LIVE_REL|g" "$wc_exp" >"$W/$wc_name.exp"
                wc_i=1
                while [ "$wc_i" -le 2 ]; do
                    ( cd "$ROOT" && WINEDEBUG=-all timeout 90 wine "$W/bin/z9dbg.exe" "$W/live/prog.exe" ) \
                        <"$wc_in" >"$W/$wc_name.$wc_i.out" 2>"$W/$wc_name.$wc_i.err"
                    wc_rc=$?
                    [ "$wc_rc" -eq 0 ] || fail_case "$wc_name run $wc_i rc"
                    if cmp -s "$W/$wc_name.exp" "$W/$wc_name.$wc_i.out"; then
                        :
                    else
                        fail_case "$wc_name run $wc_i output"
                        diff -u "$W/$wc_name.exp" "$W/$wc_name.$wc_i.out" | sed 's/^/       /'
                    fi
                    if [ "$wc_i" -gt 1 ]; then
                        cmp -s "$W/$wc_name.1.out" "$W/$wc_name.$wc_i.out" || fail_case "$wc_name run $wc_i determinism"
                    fi
                    wc_i=$((wc_i + 1))
                done
            }
            before=$FAILS
            win_case win98_break "$Z9DIR/tests/session_live_break.in" "$EXP/live_break.txt"
            [ "$FAILS" -eq "$before" ] && pass_case "Win98 break+backtrace session"
            before=$FAILS
            win_case win98_step "$Z9DIR/tests/session_live_step.in" "$EXP/live_step.txt"
            [ "$FAILS" -eq "$before" ] && pass_case "Win98 step+backtrace session"
        else
            fail_case "Win98 debuggee PE build"
            tail -20 "$W/live/gcc.log" "$W/live/zig.log" | sed 's/^/       /'
        fi
    else
        fail_case "Win98 z9dbg.exe build"
        tail -20 "$W/bin/build.log" "$W/bin/zig.log" | sed 's/^/       /'
    fi
else
    echo "skip - Win98/Wine section (wine or i686-w64-mingw32 toolchain not found)"
fi

# cleanup any detached long-running smoke children
pkill -9 -x prog >/dev/null 2>&1 || true

echo
echo "== tier_dbg summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DBG FAIL"
    exit 1
fi
echo "TIER_DBG PASS"
exit 0
