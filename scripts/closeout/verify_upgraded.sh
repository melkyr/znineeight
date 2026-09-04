#!/usr/bin/env bash
# verify_upgraded.sh — single reproducible closeout verification gate (Task 7).
#
# Builds + runs the committed closeout demos of the two upgraded programs and
# asserts canonical byte-identity against their committed goldens:
#   phase A (lisp_interpreter_upgraded):  A1 build  A2 canonical feed  A3 demo
#   feed (masked (address) line)  A4 export symbol gate  A5 zig0 note (echo)
#   phase B (rogue_mud_upgraded):         B1 build  B2 q feed  B3 move feed
#   B4 demo feed  B5 export symbol gates  B6 net variant  B7 zig0 note (echo)
#
# Every dump for the rogue program (and the net variant) runs from the rogue
# program's own directory CWD (its module resolution is CWD-relative — dumping
# demo/net_main.zig from the repo root fails error[3048]). A5/B7 are echo-only
# notes per Global Constraints AMENDMENT 2: NO sf/build/zig0 build is ever
# attempted against an examples/z98 entrypoint.
#
# Usage: bash scripts/closeout/verify_upgraded.sh [<zig1>]
# Defaults: <zig1> = /tmp/fx_subfolder/zig1 (reference compiler).
# Exit 0 on full pass (prints CLOSEOUT OK); exit 1 on first failure
# (prints CLOSEOUT FAILED:<phase>).
set -u

ROOT=/workspace/znineeight
ZIG1=${1:-/tmp/fx_subfolder/zig1}
INCLUDE="$ROOT/sf/src/include"
ZIGRUNTIME="$INCLUDE/zig_runtime.c"
ZIGPAL="$INCLUDE/zig_pal.c"
LISP="$ROOT/examples/z98/lisp_interpreter_upgraded"
ROGUE="$ROOT/examples/z98/rogue_mud_upgraded"
LDEMO="$LISP/demo"
RDEMO="$ROGUE/demo"

W=$(mktemp -d /tmp/verify_upgraded.XXXXXX)
START=$(pwd)

echo "== closeout verification gate =="
echo "   zig1: $ZIG1"
echo "   scratch: $W"

phase_fail() {
    echo "CLOSEOUT FAILED:$1"
    exit 1
}

port4000_listen() {
    awk 'NR>1 { split($2,a,":"); if (a[2] == "0FA0" && $4 == "0A") found=1 }
         END { exit !found }' /proc/net/tcp 2>/dev/null
    local rc=$?
    if [ $rc -ne 0 ]; then
        awk 'NR>1 { split($2,a,":"); if (a[2] == "0FA0" && $4 == "0A") found=1 }
             END { exit !found }' /proc/net/tcp6 2>/dev/null
        return $?
    fi
    return 0
}

# build_prog <cwd> <entry> <dir-label> — fresh-dir dump+gcc+link from <cwd>.
build_prog() {
    local cwd=$1 entry=$2 label=$3
    local d="$W/$label"
    rm -rf "$d"; mkdir -p "$d"
    local log="$d/dump.log"
    (cd "$cwd" && "$ZIG1" --dump-c89 --output-dir "$d" "$entry") >"$log" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "    build $label: DUMP rc=$rc (non-zero)"
        sed -n '1,40p' "$log"
        phase_fail "$label-build(dump-rc=$rc)"
    fi
    local nerr; nerr=$(grep -c 'error\[' "$log" 2>/dev/null || true)
    local npan; npan=$(grep -c 'PANIC' "$log" 2>/dev/null || true)
    if [ "$nerr" -ne 0 ] || [ "$npan" -ne 0 ]; then
        echo "    build $label: dump errors=$nerr panic=$npan (expected 0/0)"
        sed -n '1,40p' "$log"
        phase_fail "$label-build(diag err=$nerr panic=$npan)"
    fi
    local n_c; n_c=$(ls "$d"/*.c 2>/dev/null | wc -l)
    if [ "$n_c" -eq 0 ]; then
        echo "    build $label: 0 .c emitted"
        phase_fail "$label-build(0-c)"
    fi
    local f
    for f in "$d"/*.c; do
        gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$INCLUDE" \
            -c "$f" -o "${f%.c}.o" 2>>"$d/gcc.log" || {
                echo "    build $label: gcc FAIL on $(basename "$f")"
                tail -20 "$d/gcc.log"
                phase_fail "$label-build(gcc)"; }
    done
    gcc -m32 -o "$d/prog" "$d"/*.o "$ZIGRUNTIME" "$ZIGPAL" 2>>"$d/gcc.log" || {
        echo "    build $label: LINK FAIL"
        tail -20 "$d/gcc.log"
        phase_fail "$label-build(link)"; }
    echo "    build $label: dump rc=$rc errors=$nerr panic=$npan c=$n_c link OK"
}

# assert_export <label> <dir> <symbol> — source-name non-static defn, no zF_.
assert_export() {
    local label=$1 dir=$2 sym=$3
    if ! grep -qE "^[A-Za-z0-9_]+ ${sym}\(" "$dir"/*.c; then
        echo "    $label: exported symbol '$sym' definition NOT found in emitted C"
        phase_fail "$label($sym-defn-missing)"
    fi
    if grep -qE "zF_[A-Za-z0-9_]*${sym}" "$dir"/*.c; then
        echo "    $label: '$sym' appears zF_-mangled (expected source-name export)"
        phase_fail "$label($sym-mangled)"
    fi
    echo "    $label: export gate '$sym' source-name present, no zF_ mangling"
}

# run_lisp_feed <feed> <expected> <out-label> — via Task 1 helper (root CWD).
run_lisp_feed() {
    local feed=$1 expected=$2 label=$3
    local out="$W/$label.out"
    bash "$ROOT/scripts/closeout/run_upgraded.sh" "$ZIG1" \
        "examples/z98/lisp_interpreter_upgraded/main.zig" "$feed" "$out" \
        >"$W/$label.runlog" 2>"$W/$label.runerr"
    local runrc; runrc=$(sed -n 's/^RUNRC=//p' "$W/$label.runlog")
    if [ "$runrc" != "0" ]; then
        echo "    $label: RUNRC=$runrc (expected 0)"
        tail -20 "$W/$label.runerr"
        phase_fail "$label(run-rc=$runrc)"
    fi
    echo "$out"
}

# compare_masked_demo <actual> <expected> — AMENDMENT 4 masked line compare.
compare_masked_demo() {
    local actual=$1 expected=$2
    local a_ln=0 e_ln=0 a_line e_line
    local n=0 addr_idx=0
    while IFS= read -r e_line; do
        e_ln=$((e_ln + 1))
    done <"$expected"
    while IFS= read -r a_line; do
        a_ln=$((a_ln + 1))
    done <"$actual"
    if [ "$a_ln" -ne "$e_ln" ]; then
        echo "    A3: line count actual=$a_ln expected=$e_ln differ"
        return 1
    fi
    n=0
    while true; do
        n=$((n + 1))
        if ! IFS= read -r a_line <&3; then break; fi
        if ! IFS= read -r e_line <&4; then break; fi
        if [ "$n" -eq 15 ]; then
            # (address ...) output line — PIE/ASLR-varying VA sample (AMENDMENT 4).
            if ! printf '%s\n' "$a_line" | grep -qE '^> [0-9]+$' \
               || ! printf '%s\n' "$e_line" | grep -qE '^> [0-9]+$'; then
                return 1
            fi
            addr_idx=$n
            continue
        fi
        if [ "$a_line" != "$e_line" ]; then return 1; fi
    done 3<"$actual" 4<"$expected"
    if [ "$addr_idx" -ne 15 ]; then return 1; fi
    return 0
}

# ---------------------------------------------------------------------------
echo "== phase A: lisp_interpreter_upgraded =="
build_prog "$ROOT" "examples/z98/lisp_interpreter_upgraded/main.zig" A1
echo "PASS A1 (lisp build: rc0, 0 error[, 0 PANIC, gcc+link OK)"

a2_out=$(run_lisp_feed "$LDEMO/canonical_feed.txt" "$LDEMO/canonical_expected.txt" A2)
md5_actual=$(md5sum "$a2_out" | cut -d' ' -f1)
md5_expected=$(md5sum "$LDEMO/canonical_expected.txt" | cut -d' ' -f1)
if [ "$md5_actual" != "$md5_expected" ]; then
    echo "    A2: canonical feed stdout md5 $md5_actual != expected $md5_expected"
    phase_fail "A2(canonical-md5)"
fi
echo "    A2: canonical stdout md5 $md5_actual == demo/canonical_expected.txt"
echo "PASS A2 (canonical feed byte-identity, md5 96654b39)"

a3_out=$(run_lisp_feed "$LDEMO/demo_feed.txt" "$LDEMO/demo_expected.txt" A3)
if ! compare_masked_demo "$a3_out" "$LDEMO/demo_expected.txt"; then
    echo "    A3: demo stdout differs from demo_expected.txt beyond the masked (address) line"
    diff "$a3_out" "$LDEMO/demo_expected.txt"
    phase_fail "A3(demo-masked-compare)"
fi
echo "    A3: demo stdout masked-compare OK (line 15 = (address) positive int; all others byte-equal)"
echo "PASS A3 (demo feed vs demo_expected.txt, AMENDMENT-4 masked compare)"

build_prog "$ROOT" "examples/z98/lisp_interpreter_upgraded/main.zig" A4
assert_export A4 "$W/A4" alloc_value
echo "PASS A4 (export symbol gate: source-name alloc_value, no zF_ mangling)"

echo "    A5 NOTE (echo-only, NO sf/build/zig0 build): Global Constraints AMENDMENT 2 —"
echo "    zig0 compiles ONLY the examples/zig0 set; NO zig0 build is attempted against any"
echo "    examples/z98 entrypoint. lisp_interpreter_upgraded zig1-superset C1 construct"
echo "    sites: eval.zig:45 / builtins.zig:142 (tag ==; would not parse under zig0)."
echo "PASS A5 (documented zig0-incompatibility note)"

# ---------------------------------------------------------------------------
echo "== phase B: rogue_mud_upgraded (dumps from rogue dir CWD) =="
build_prog "$ROGUE" "$ROGUE/main.zig" B1
echo "PASS B1 (rogue build: rc0, 0 error[, 0 PANIC, gcc+link OK)"

run_rogue_feed() {
    local label=$1 feed=$2 expected=$3
    local rd="$W/$label-run"
    rm -rf "$rd"; mkdir -p "$rd"
    timeout 30 "$W/B1/prog" < "$feed" > "$rd/out" 2> "$rd/err"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "    $label: RUNRC=$rc (expected 0)"
        cat "$rd/err"
        phase_fail "$label(run-rc=$rc)"
    fi
    local ma; ma=$(md5sum "$rd/out" | cut -d' ' -f1)
    local me; me=$(md5sum "$expected" | cut -d' ' -f1)
    if [ "$ma" != "$me" ]; then
        echo "    $label: stdout md5 $ma != expected $me"
        phase_fail "$label(md5)"
    fi
    echo "    $label: stdout md5 $ma == expected (byte-identical)"
}

run_rogue_feed B2 "$RDEMO/canonical_feed.txt" "$RDEMO/canonical_expected.txt"
echo "PASS B2 (canonical q feed byte-identity, md5 3fb6709e)"
run_rogue_feed B3 "$RDEMO/canonical_move_feed.txt" "$RDEMO/canonical_move_expected.txt"
echo "PASS B3 (canonical move feed byte-identity, md5 b3c5b0e1)"
run_rogue_feed B4 "$RDEMO/demo_feed.txt" "$RDEMO/demo_expected.txt"
echo "PASS B4 (demo feed byte-identity, md5 7361d248)"

assert_export B5 "$W/B1" saveDungeon
assert_export B5 "$W/B1" loadDungeon
rc_files=$(grep -l 'render_calls' "$W/B1"/*.c 2>/dev/null | wc -l)
if [ "$rc_files" -lt 2 ]; then
    echo "    B5: render_calls appears in $rc_files .c file(s) (need >= 2 for cross-module)"
    phase_fail "B5(render_calls-not-cross-module)"
fi
if ! grep -qE 'zG_[A-Za-z0-9_]+_render_calls' "$W/B1"/*.c; then
    echo "    B5: no zG_…_render_calls storage-global definition in emitted C"
    phase_fail "B5(render_calls-no-global-def)"
fi
if grep -qE 'zF_[A-Za-z0-9_]*render_calls' "$W/B1"/*.c; then
    echo "    B5: render_calls appears zF_-mangled (expected source-name storage global)"
    phase_fail "B5(render_calls-mangled)"
fi
echo "    B5: render_calls cross-module (zG_…_render_calls def + refs in >= 2 modules), no zF_"
echo "PASS B5 (rogue export symbol gates)"

# -- B6: net variant ---------------------------------------------------------
if port4000_listen; then
    echo "    B6: port 4000 already has a LISTEN socket before the run"
    phase_fail "B6(port-4000-preoccupied)"
fi
build_prog "$ROGUE" "$ROGUE/demo/net_main.zig" B6-server
build_prog "$ROGUE" "$ROGUE/demo/net_demo_client.zig" B6-client
gcc -m32 -shared -fPIC -o "$W/flush.so" "$ROOT/scripts/closeout/flush.c" || {
    echo "    B6: flush.so build FAILED"
    phase_fail "B6(flush-build)"; }
echo "    B6: flush.so built (setvbuf _IONBF LD_PRELOAD shim)"

mkdir -p "$W/B6-srvrun"
( cd "$ROGUE" && timeout -k 2 12 env LD_PRELOAD="$W/flush.so" \
        "$W/B6-server/prog" < /dev/null \
        > "$W/B6-srvrun/server.out" 2> "$W/B6-srvrun/server.err" ) &
SRV_PID=$!
sleep 0.3
timeout 10 "$W/B6-client/prog" > "$W/B6-srvrun/client.out" 2> "$W/B6-srvrun/client.err"
echo "    B6: client rc=$? (timeout reap expected under blocking recv)"
wait "$SRV_PID"
SRV_RC=$?
if kill -0 "$SRV_PID" 2>/dev/null; then kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; fi
echo "    B6: server rc=$SRV_RC (timeout kill expected)"

md5_server=$(md5sum "$W/B6-srvrun/server.out" | cut -d' ' -f1)
md5_netexp=$(md5sum "$RDEMO/net_demo_expected.txt" | cut -d' ' -f1)
if [ "$md5_server" != "$md5_netexp" ]; then
    echo "    B6: server stdout md5 $md5_server != demo/net_demo_expected.txt $md5_netexp"
    cat "$W/B6-srvrun/server.err"
    diff "$W/B6-srvrun/server.out" "$RDEMO/net_demo_expected.txt"
    phase_fail "B6(server-out-md5)"
fi
echo "    B6: server stdout md5 $md5_server == demo/net_demo_expected.txt (aa40a52e)"

if port4000_listen; then
    echo "    B6: port 4000 still has a LISTEN socket after the run"
    phase_fail "B6(port-4000-leftover)"
fi
echo "    B6: port 4000 clear after the run (no leftover listener, no pkill)"
echo "PASS B6 (net variant: server stdout golden + port discipline)"

echo "    B7 NOTE (echo-only, NO sf/build/zig0 build): Global Constraints AMENDMENT 2 —"
echo "    zig0 compiles ONLY the examples/zig0 set; NO zig0 build is attempted against any"
echo "    examples/z98 entrypoint. rogue_mud_upgraded zig1-superset C1 construct sites:"
echo "    lib/combat.zig:32 / lib/pathfinding.zig:83 / lib/scenario.zig:241+253 / ui.zig:192+196"
echo "    (tag ==; would not parse under zig0)."
echo "PASS B7 (documented zig0-incompatibility note)"

# ---------------------------------------------------------------------------
echo
echo "== verdict table =="
echo "A1 lisp build ................ PASS"
echo "A2 canonical feed (96654b39) . PASS"
echo "A3 demo feed (masked (addr))  PASS"
echo "A4 export symbol gate ........ PASS"
echo "A5 zig0 note (echo-only) ..... PASS"
echo "B1 rogue build ............... PASS"
echo "B2 canonical q (3fb6709e) .... PASS"
echo "B3 canonical move (b3c5b0e1) . PASS"
echo "B4 demo feed (7361d248) ...... PASS"
echo "B5 export symbol gates ....... PASS"
echo "B6 net variant (aa40a52e) .... PASS"
echo "B7 zig0 note (echo-only) ..... PASS"
echo "CLOSEOUT OK"
exit 0
