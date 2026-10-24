#!/bin/sh
# tier_dbg_core.sh — P3-M2 headless gate for the z9dbg map reader + core.
#
# Builds examples/z98/z9dbg/tests/dbg_test.zig with the binding seed recipe and
# checks:
#   1. committed map fixtures parse (header/counts, main rows, basename and
#      path-suffix matching, forward + reverse line rows, cnames);
#   2. breakpoint classification/snap exact strings;
#   3. the scripted command loop exact UX strings (stdin -> stdout);
#   4. the dump writer (registers-unavailable session path + formatted regs);
#   5. corrupt/truncated/missing maps fail cleanly (no crash).
# All compared outputs run 3x and must be byte-identical.
#
# Env: ZIG  seed-built compiler (required)
#      OUT  scratch dir (default /tmp/z9dbg_core_tier)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:?set ZIG to the seed-built zig1_5_clean}"
OUT="${OUT:-/tmp/z9dbg_core_tier}"
FIX="$Z9DIR/tests/fixtures"
EXP="$Z9DIR/tests/expected"
HELLO="$FIX/hello/main_BDA8D6C7"
FIB="$FIX/fibonacci/main_4DFBF9C3"
DUMP1="/tmp/z9dbg_core_snap.txt"
DUMP2="/tmp/z9dbg_core_snap2.txt"
REGS="$OUT/dump_regs.txt"

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
rm -f "$DUMP1" "$DUMP2"

echo "== building dbg_test (binding recipe, -fsafe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9dbg/tests/dbg_test.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -30 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -30 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
H="$OUT/prog"
if [ ! -x "$H" ]; then
    echo "FAIL: $H not built"
    exit 1
fi

# check_mode <name> <expected-file> <mode> <prefix>
check_mode() {
    cm_name="$1"; cm_exp="$2"; cm_mode="$3"; cm_prefix="$4"
    cm_i=1
    while [ "$cm_i" -le 3 ]; do
        if "$H" "$cm_mode" "$cm_prefix" >"$OUT/$cm_name.$cm_i.out" 2>"$OUT/$cm_name.$cm_i.err"; then
            :
        else
            fail_case "$cm_name run $cm_i rc"
            tail -10 "$OUT/$cm_name.$cm_i.err" | sed 's/^/       /'
        fi
        if cmp -s "$cm_exp" "$OUT/$cm_name.$cm_i.out"; then
            :
        else
            fail_case "$cm_name run $cm_i output"
            diff -u "$cm_exp" "$OUT/$cm_name.$cm_i.out" | sed 's/^/       /'
        fi
        if [ "$cm_i" -gt 1 ]; then
            if cmp -s "$OUT/$cm_name.1.out" "$OUT/$cm_name.$cm_i.out"; then
                :
            else
                fail_case "$cm_name run $cm_i determinism"
            fi
        fi
        cm_i=$((cm_i + 1))
    done
    if [ "$FAILS" -eq 0 ]; then
        pass_case "$cm_name 3x"
    fi
}

echo "== map reader fixtures =="
before=$FAILS
check_mode map_hello "$EXP/map_hello.txt" map-hello "$HELLO"
[ "$FAILS" -eq "$before" ] && pass_case "map-hello assertions"
before=$FAILS
check_mode map_fib "$EXP/map_fib.txt" map-fib "$FIB"
[ "$FAILS" -eq "$before" ] && pass_case "map-fib assertions"

echo "== optional .cnames (spec §7.2) =="
NOC="$OUT/nocnames_fixture"
mkdir -p "$NOC"
cp "$FIX/hello/main_BDA8D6C7.z98dbg.syms" "$NOC/"
cp "$FIX/hello/main_BDA8D6C7.z98dbg.lines" "$NOC/"
i=1
while [ "$i" -le 3 ]; do
    if "$H" map-nocnames "$NOC/main_BDA8D6C7" >"$OUT/nocnames.$i.out" 2>"$OUT/nocnames.$i.err"; then
        :
    else
        fail_case "map-nocnames run $i rc"
        tail -10 "$OUT/nocnames.$i.err" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/map_nocnames.txt" "$OUT/nocnames.$i.out"; then
        :
    else
        fail_case "map-nocnames run $i output"
        diff -u "$EXP/map_nocnames.txt" "$OUT/nocnames.$i.out" | sed 's/^/       /'
    fi
    if [ "$i" -gt 1 ]; then
        cmp -s "$OUT/nocnames.1.out" "$OUT/nocnames.$i.out" || fail_case "map-nocnames run $i determinism"
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "map-nocnames 3x"

echo "== breakpoint classification / snap =="
before=$FAILS
check_mode snap_hello "$EXP/snap_hello.txt" snap "$HELLO"
[ "$FAILS" -eq "$before" ] && pass_case "snap assertions"

echo "== scripted session (exact strings) =="
i=1
while [ "$i" -le 3 ]; do
    rm -f "$DUMP1" "$DUMP2"
    if "$H" session "$HELLO" <"$Z9DIR/tests/session_hello.in" >"$OUT/session.$i.out" 2>"$OUT/session.$i.err"; then
        :
    else
        fail_case "session run $i rc"
        tail -10 "$OUT/session.$i.err" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/session_hello.txt" "$OUT/session.$i.out"; then
        :
    else
        fail_case "session run $i output"
        diff -u "$EXP/session_hello.txt" "$OUT/session.$i.out" | sed 's/^/       /'
    fi
    if [ "$i" -gt 1 ]; then
        cmp -s "$OUT/session.1.out" "$OUT/session.$i.out" || fail_case "session run $i determinism"
    fi
    if cmp -s "$EXP/dump_hello.txt" "$DUMP1"; then
        :
    else
        fail_case "session run $i dump1 content"
        diff -u "$EXP/dump_hello.txt" "$DUMP1" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/dump_hello.txt" "$DUMP2"; then
        :
    else
        fail_case "session run $i dump2 content"
        diff -u "$EXP/dump_hello.txt" "$DUMP2" | sed 's/^/       /'
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "session 3x"
rm -f "$DUMP1" "$DUMP2"

echo "== break is rejected while running =="
i=1
while [ "$i" -le 3 ]; do
    if "$H" session-running "$HELLO" <"$Z9DIR/tests/session_running.in" >"$OUT/running.$i.out" 2>"$OUT/running.$i.err"; then
        :
    else
        fail_case "session-running run $i rc"
        tail -10 "$OUT/running.$i.err" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/session_running.txt" "$OUT/running.$i.out"; then
        :
    else
        fail_case "session-running run $i output"
        diff -u "$EXP/session_running.txt" "$OUT/running.$i.out" | sed 's/^/       /'
    fi
    if [ "$i" -gt 1 ]; then
        cmp -s "$OUT/running.1.out" "$OUT/running.$i.out" || fail_case "session-running run $i determinism"
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "session-running 3x"

echo "== default dump names z98-dump-<n>.txt =="
WORK="$OUT/work"
mkdir -p "$WORK/examples/z98/z9dbg/tests/fixtures/hello"
cp "$FIX/hello/main.zig" "$WORK/examples/z98/z9dbg/tests/fixtures/hello/main.zig"
i=1
while [ "$i" -le 3 ]; do
    rm -f "$WORK/z98-dump-1.txt" "$WORK/z98-dump-2.txt"
    if ( cd "$WORK" && "$H" session "$HELLO" <"$Z9DIR/tests/session_default.in" >"$OUT/default.$i.out" 2>"$OUT/default.$i.err" ); then
        :
    else
        fail_case "session-default run $i rc"
        tail -10 "$OUT/default.$i.err" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/session_default.txt" "$OUT/default.$i.out"; then
        :
    else
        fail_case "session-default run $i output"
        diff -u "$EXP/session_default.txt" "$OUT/default.$i.out" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/dump_hello.txt" "$WORK/z98-dump-1.txt"; then
        :
    else
        fail_case "session-default run $i dump1 content"
    fi
    if cmp -s "$EXP/dump_hello.txt" "$WORK/z98-dump-2.txt"; then
        :
    else
        fail_case "session-default run $i dump2 content"
    fi
    if [ "$i" -gt 1 ]; then
        cmp -s "$OUT/default.1.out" "$OUT/default.$i.out" || fail_case "session-default run $i determinism"
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "session-default 3x"

echo "== step-into next mapped line + dump resume state =="
STEPDUMP="/tmp/z9dbg_step_dump.txt"
i=1
while [ "$i" -le 3 ]; do
    rm -f "$STEPDUMP"
    if "$H" session-step "$HELLO" <"$Z9DIR/tests/session_step.in" >"$OUT/step.$i.out" 2>"$OUT/step.$i.err"; then
        :
    else
        fail_case "session-step run $i rc"
        tail -10 "$OUT/step.$i.err" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/session_step.txt" "$OUT/step.$i.out"; then
        :
    else
        fail_case "session-step run $i output"
        diff -u "$EXP/session_step.txt" "$OUT/step.$i.out" | sed 's/^/       /'
    fi
    if cmp -s "$EXP/dump_step.txt" "$STEPDUMP"; then
        :
    else
        fail_case "session-step run $i dump content"
        diff -u "$EXP/dump_step.txt" "$STEPDUMP" | sed 's/^/       /'
    fi
    if [ "$i" -gt 1 ]; then
        cmp -s "$OUT/step.1.out" "$OUT/step.$i.out" || fail_case "session-step run $i determinism"
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "session-step 3x"
rm -f "$STEPDUMP"

echo "== dump writer with formatted registers =="
i=1
while [ "$i" -le 3 ]; do
    rm -f "$REGS"
    if "$H" dump-regs "$HELLO" "$REGS" >"$OUT/dumpregs.$i.out" 2>"$OUT/dumpregs.$i.err"; then
        :
    else
        fail_case "dump-regs run $i rc"
    fi
    if cmp -s "$EXP/dump_regs_hello.txt" "$REGS"; then
        :
    else
        fail_case "dump-regs run $i content"
        diff -u "$EXP/dump_regs_hello.txt" "$REGS" | sed 's/^/       /'
    fi
    i=$((i + 1))
done
[ "$FAILS" -eq 0 ] && pass_case "dump-regs 3x"

echo "== standalone z9dbg binary (map discovery + session) =="
BINOUT="$OUT/z9dbg_bin"
mkdir -p "$BINOUT"
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$BINOUT" examples/z98/z9dbg/main.zig >"$BINOUT/zig.log" 2>&1; then
    fail_case "z9dbg zig compile"
    tail -30 "$BINOUT/zig.log" | sed 's/^/       /'
else
    if ! sh "$BINOUT/build_target.sh" linux "$BINOUT/prog" >"$BINOUT/build.log" 2>&1; then
        fail_case "z9dbg target link"
        tail -30 "$BINOUT/build.log" | sed 's/^/       /'
    else
        EXEDIR="$OUT/exedir"
        mkdir -p "$EXEDIR"
        cp "$BINOUT/prog" "$EXEDIR/prog"
        cp "$FIX/hello/"*.z98dbg.* "$EXEDIR/"
        i=1
        while [ "$i" -le 3 ]; do
            rm -f "$DUMP1" "$DUMP2"
            if Z9DBG_STUB=1 "$EXEDIR/prog" "$EXEDIR/prog" <"$Z9DIR/tests/session_hello.in" >"$OUT/bin_session.$i.out" 2>"$OUT/bin_session.$i.err"; then
                :
            else
                fail_case "z9dbg binary session run $i rc"
                tail -10 "$OUT/bin_session.$i.err" | sed 's/^/       /'
            fi
            if cmp -s "$EXP/session_hello.txt" "$OUT/bin_session.$i.out"; then
                :
            else
                fail_case "z9dbg binary session run $i output"
                diff -u "$EXP/session_hello.txt" "$OUT/bin_session.$i.out" | sed 's/^/       /'
            fi
            if [ "$i" -gt 1 ]; then
                cmp -s "$OUT/bin_session.1.out" "$OUT/bin_session.$i.out" || fail_case "z9dbg binary session run $i determinism"
            fi
            if cmp -s "$EXP/dump_hello.txt" "$DUMP1"; then
                :
            else
                fail_case "z9dbg binary session run $i dump content"
            fi
            i=$((i + 1))
        done
        [ "$FAILS" -eq 0 ] && pass_case "z9dbg binary session 3x"
        rm -f "$DUMP1" "$DUMP2"

        EXEDIR_NC="$OUT/exedir_nocnames"
        mkdir -p "$EXEDIR_NC"
        cp "$BINOUT/prog" "$EXEDIR_NC/prog"
        cp "$FIX/hello/main_BDA8D6C7.z98dbg.syms" "$EXEDIR_NC/"
        cp "$FIX/hello/main_BDA8D6C7.z98dbg.lines" "$EXEDIR_NC/"
        rm -f "$DUMP1" "$DUMP2"
        if Z9DBG_STUB=1 "$EXEDIR_NC/prog" "$EXEDIR_NC/prog" <"$Z9DIR/tests/session_hello.in" >"$OUT/bin_nocnames.out" 2>"$OUT/bin_nocnames.err"; then
            :
        else
            fail_case "z9dbg binary no-cnames session rc"
            tail -10 "$OUT/bin_nocnames.err" | sed 's/^/       /'
        fi
        if cmp -s "$EXP/session_hello.txt" "$OUT/bin_nocnames.out"; then
            pass_case "z9dbg binary no-cnames session"
        else
            fail_case "z9dbg binary no-cnames session output"
            diff -u "$EXP/session_hello.txt" "$OUT/bin_nocnames.out" | sed 's/^/       /'
        fi
        if cmp -s "$EXP/dump_hello.txt" "$DUMP1"; then
            :
        else
            fail_case "z9dbg binary no-cnames dump content"
        fi
        rm -f "$DUMP1" "$DUMP2"
    fi
fi

echo "== corrupt / truncated / missing maps fail cleanly =="
PREP="$OUT/corrupt"
mkdir -p "$PREP"
mk_case() {
    mk_case_dir="$PREP/$1"
    mkdir -p "$mk_case_dir"
    cp "$FIX/hello/main_BDA8D6C7.z98dbg.syms" "$mk_case_dir/"
    cp "$FIX/hello/main_BDA8D6C7.z98dbg.lines" "$mk_case_dir/"
    cp "$FIX/hello/main_BDA8D6C7.z98dbg.cnames" "$mk_case_dir/"
}
check_bad() {
    bad_name="$1"; bad_prefix="$2"
    if "$H" open-error "$bad_prefix" >"$OUT/$bad_name.out" 2>"$OUT/$bad_name.err"; then
        if grep -q '^ok - open rejected$' "$OUT/$bad_name.out"; then
            pass_case "$bad_name clean error"
        else
            fail_case "$bad_name accepted"
            cat "$OUT/$bad_name.out" | sed 's/^/       /'
        fi
    else
        fail_case "$bad_name crashed (rc != 0)"
        tail -10 "$OUT/$bad_name.err" | sed 's/^/       /'
    fi
}

mk_case trunc
head -c 10 "$FIX/hello/main_BDA8D6C7.z98dbg.syms" >"$PREP/trunc/main_BDA8D6C7.z98dbg.syms"
check_bad trunc "$PREP/trunc/main_BDA8D6C7"

mk_case magic
printf 'X' | dd of="$PREP/magic/main_BDA8D6C7.z98dbg.syms" bs=1 seek=0 conv=notrunc 2>/dev/null
check_bad magic "$PREP/magic/main_BDA8D6C7"

mk_case version
printf '\002\000\000\000' | dd of="$PREP/version/main_BDA8D6C7.z98dbg.syms" bs=1 seek=8 conv=notrunc 2>/dev/null
check_bad version "$PREP/version/main_BDA8D6C7"

mk_case count
printf '\377\377\377\377' | dd of="$PREP/count/main_BDA8D6C7.z98dbg.syms" bs=1 seek=12 conv=notrunc 2>/dev/null
check_bad count "$PREP/count/main_BDA8D6C7"

mk_case total
printf '\000\000\000\000' | dd of="$PREP/total/main_BDA8D6C7.z98dbg.syms" bs=1 seek=16 conv=notrunc 2>/dev/null
check_bad total "$PREP/total/main_BDA8D6C7"

mk_case str
printf '\377\377' | dd of="$PREP/str/main_BDA8D6C7.z98dbg.syms" bs=1 seek=25 conv=notrunc 2>/dev/null
check_bad str "$PREP/str/main_BDA8D6C7"

mk_case linetrunc
head -c 10 "$FIX/hello/main_BDA8D6C7.z98dbg.lines" >"$PREP/linetrunc/main_BDA8D6C7.z98dbg.lines"
check_bad linetrunc "$PREP/linetrunc/main_BDA8D6C7"

mk_case cnamemagic
printf 'X' | dd of="$PREP/cnamemagic/main_BDA8D6C7.z98dbg.cnames" bs=1 seek=0 conv=notrunc 2>/dev/null
check_bad cnamemagic "$PREP/cnamemagic/main_BDA8D6C7"

mkdir -p "$PREP/missing"
check_bad missing "$PREP/missing/main_BDA8D6C7"

echo
echo "== tier_dbg_core summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DBG_CORE FAIL"
    exit 1
fi
echo "TIER_DBG_CORE PASS"
exit 0
