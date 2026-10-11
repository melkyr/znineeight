#!/bin/sh
# tier1.sh — z9torr M1 end-to-end gate (task 4).
#
# Builds z9torr with the binding seed recipe, then:
#   1. per fixture (t1/t2/t5): printed info_hash == testdata/expected and ==
#      ref_check --infohash, and exit 3 — the client now ALWAYS attempts the
#      tracker (spec §8); with no mock_tracker running the announce fails and
#      the spec-correct exit is 3 (tracker/network);
#   2. malformed inputs (truncated / bad piece count / mutated info byte):
#      exit 2 + typed message;
#   3. determinism: each fixture 3x byte-identical stdout.
# Exits non-zero on any failure and prints a PASS/FAIL summary.
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m0_seed/zig1_5_clean}"
CC="${CC:-gcc}"
OUT="${OUT:-/tmp/z9torr_tier1}"

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
FIXTURES="t1_single_1m t2_single_25m t5_unicode_name"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

offset_of() { grep -abo -- "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1; }
mutate_byte() {
    _f="$1"; _off="$2"; _rep="$3"; _out="$4"
    { dd if="$_f" bs=1 count="$_off" 2>/dev/null
      printf '%s' "$_rep"
      dd if="$_f" bs=1 skip=$((_off + 1)) 2>/dev/null
    } >"$_out"
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

# Fail closed if the tracker port is already listening. This gate asserts an
# unreachable tracker (exit 3); a leftover mock_tracker would instead produce a
# peer error (exit 4) and silently misread as a peer failure. Mirrors tier2.sh.
port_busy() {
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}
if port_busy 6969; then
    echo "FAIL: tracker port 127.0.0.1:6969 already in use"
    echo "      tier1 expects the tracker unreachable (exit 3); stop the leftover"
    echo "      mock_tracker and re-run"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== building z9torr (binding recipe) =="
cd "$ROOT" || exit 1
if ! timeout 120 "$ZIG" -fsafe -o "$OUT" examples/z98/z9torr/main.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    exit 1
fi
if ! sh "$OUT/build_target.sh" linux "$OUT/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    exit 1
fi
PROG="$OUT/prog"
if [ ! -x "$PROG" ]; then
    echo "FAIL: $PROG not built"
    exit 1
fi

echo "== building ref_check =="
if ! "$CC" -std=c89 -O0 -Wall -o "$OUT/ref_check" "$Z9DIR/tools/ref_check.c" >"$OUT/refcc.log" 2>&1; then
    echo "FAIL: ref_check build (see $OUT/refcc.log)"
    exit 1
fi
REF="$OUT/ref_check"

for name in $FIXTURES; do
    FIX="$FIXDIR/$name.torrent"
    EXP="$(cat "$EXPDIR/$name.infohash")"
    echo "== fixture $name =="

    "$PROG" "$FIX" >"$OUT/$name.out" 2>"$OUT/$name.err"
    rc=$?
    if [ "$rc" -eq 3 ]; then
        pass_case "$name: z9torr exit 3 (tracker unreachable)"
    else
        fail_case "$name: z9torr exit 3 (tracker unreachable) (got $rc)"
    fi

    GOT="$(awk '/^info_hash: /{print $2}' "$OUT/$name.out" | head -n1)"
    REFH="$("$REF" --infohash "$FIX" | awk '{print $2}')"

    if [ "$GOT" = "$EXP" ]; then
        pass_case "$name: info_hash == expected ($GOT)"
    else
        fail_case "$name: info_hash got '$GOT' want '$EXP'"
    fi
    if [ "$GOT" = "$REFH" ]; then
        pass_case "$name: info_hash == ref_check ($REFH)"
    else
        fail_case "$name: info_hash '$GOT' != ref_check '$REFH'"
    fi

    i=1
    while [ "$i" -le 3 ]; do
        "$PROG" "$FIX" >"$OUT/$name.det.$i.out" 2>/dev/null
        i=$((i + 1))
    done
    if cmp -s "$OUT/$name.det.1.out" "$OUT/$name.det.2.out" &&
       cmp -s "$OUT/$name.det.1.out" "$OUT/$name.det.3.out"; then
        pass_case "$name: deterministic 3x (byte-identical stdout)"
    else
        fail_case "$name: deterministic 3x (stdout differs)"
    fi
done

echo "== malformed inputs =="
T1="$FIXDIR/t1_single_1m.torrent"

expect_exit2() {
    _label="$1"; _file="$2"
    "$PROG" "$_file" >"$OUT/malformed.out" 2>&1
    _rc=$?
    if [ "$_rc" -eq 2 ] && grep -q "z9torr:" "$OUT/malformed.out"; then
        pass_case "$_label: exit 2 + typed message"
    else
        fail_case "$_label: exit 2 + typed message (rc=$_rc)"
    fi
}

sz="$(wc -c < "$T1" | tr -d ' ')"
dd if="$T1" of="$OUT/mal_truncated.torrent" bs=1 count=$((sz - 3)) 2>/dev/null
expect_exit2 "truncated file" "$OUT/mal_truncated.torrent"

loff="$(offset_of "$T1" 'lengthi')"
if [ -n "$loff" ]; then
    mutate_byte "$T1" $((loff + 7)) '9' "$OUT/mal_badpiececount.torrent"
    expect_exit2 "bad piece count" "$OUT/mal_badpiececount.torrent"
else
    fail_case "bad piece count: could not locate length field"
fi

nmoff="$(offset_of "$T1" 't1.bin')"
if [ -n "$nmoff" ]; then
    mutate_byte "$T1" "$nmoff" '/' "$OUT/mal_badname.torrent"
    expect_exit2 "mutated info byte" "$OUT/mal_badname.torrent"
else
    fail_case "mutated info byte: could not locate name field"
fi

echo "== unit harnesses (tier1_unit.sh) =="
if sh "$SCRIPT_DIR/tier1_unit.sh"; then
    pass_case "unit harnesses (ratelimit/scheduler/stats)"
else
    fail_case "unit harnesses (ratelimit/scheduler/stats)"
fi

echo
echo "== tier1 summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER1 FAIL"
    exit 1
fi
echo "TIER1 PASS"
exit 0
