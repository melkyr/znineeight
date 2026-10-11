#!/bin/sh
# tier4_wine.sh — z9torr M5 gate: Windows emission + mingw build, then a Wine
# smoke against the host mocks.
#
# POSIX sh. Run from anywhere (paths resolved from this script). Steps:
#   1. emit the Windows tree with `<zig1> -osw -o <dir>` and assert it carries
#      the module .c/.h, the Windows link scripts (build_target.bat,
#      build_owc.bat) and net_prelude.h;
#   2. cross-compile the emitted C for win32 with the committed
#      scripts/win32_cross/cross_build_run.sh recipe (mingw; the link line is
#      unconditional -lwsock32);
#   3. sanity: `file` reports a PE32 executable, and `objdump -p` / `nm` shows
#      the wsock32 import;
#   4. build the -fsafe RUN exe (z9torr_run.exe) with the emitted
#      build_target.sh mingw branch (see the run-half comment);
#   5. 32-bit wine probe (SKIP-with-reason if the runtime is absent);
#   6. build + start the tier2 mocks (mock_tracker + mock_peer via ports.txt);
#   7. download t1_single_1m under wine and assert exit 0 + output SHA-1 ==
#      expected, recording PARITY=OK-style evidence (wine rc, output hash, and
#      the mock's served-byte total as the non-blocking-connect/select check).
#
# Toolchain: the seed compiler, i686-w64-mingw32-gcc, file, objdump, nm, wine,
# winepath.
# SKIP-with-reason (exit 77, distinct from PASS=0 / FAIL=1) if a required tool
# is genuinely unavailable — never a silent pass.
# Exits non-zero and prints a PASS/FAIL summary on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9_m5_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9torr_tier4}"
ENTRY="examples/z98/z9torr/main.zig"

CROSS_GCC="${CROSS_GCC:-i686-w64-mingw32-gcc}"
XBUILD="$ROOT/scripts/win32_cross/cross_build_run.sh"

# Conventional "skipped" status (autotools/automake). Distinct from PASS (0)
# and FAIL (1) so a missing-toolchain no-op can never be mistaken for success.
SKIP_EXIT=77

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

skip() {
    echo
    echo "SKIP: $1"
    echo "TIER4 SKIP"
    exit "$SKIP_EXIT"
}

# --- toolchain presence (SKIP, not FAIL, when genuinely absent) --------------
for _t in "$ZIG" "$CROSS_GCC" file objdump nm wine winepath; do
    if [ -x "$_t" ] || command -v "$_t" >/dev/null 2>&1; then continue; fi
    skip "required tool unavailable: $_t"
done
if [ ! -f "$XBUILD" ]; then
    skip "committed cross recipe missing: $XBUILD"
fi

rm -rf "$OUT"
mkdir -p "$OUT/work"
WIN="$OUT/win"
EXE="$OUT/z9torr.exe"

cd "$ROOT" || { echo "FAIL: cannot cd $ROOT"; exit 1; }

# --- Step 1: emit the Windows tree ------------------------------------------
echo "== step 1: emit the windows tree (-osw -o) =="
mkdir -p "$WIN"
if timeout 120 "$ZIG" -osw -o "$WIN" "$ENTRY" >"$OUT/emit.log" 2>&1; then
    pass_case "windows emit rc=0"
else
    fail_case "windows emit rc=0 (see $OUT/emit.log)"
fi

N_C=$(ls "$WIN"/*.c 2>/dev/null | wc -l | tr -d ' ')
N_H=$(ls "$WIN"/*.h 2>/dev/null | wc -l | tr -d ' ')
if [ "$N_C" -gt 0 ] && [ "$N_H" -gt 0 ]; then
    pass_case "emit tree carries module .c/.h ($N_C .c, $N_H .h)"
else
    fail_case "emit tree carries module .c/.h ($N_C .c, $N_H .h)"
fi

for _f in build_target.bat build_owc.bat net_prelude.h; do
    if [ -e "$WIN/$_f" ]; then pass_case "emit tree carries $_f"
    else fail_case "emit tree carries $_f"; fi
done

# --- Step 2: mingw cross-build (committed win32_cross recipe) ---------------
echo "== step 2: mingw cross-build (cross_build_run.sh; -lwsock32) =="
XRUN_LOG="$OUT/xrun.log"
if timeout 600 bash "$XBUILD" "$ZIG" "$ENTRY" "$OUT/cross" "$EXE" >"$XRUN_LOG" 2>&1; then
    XRUNRC=$(sed -n 's/^XRUNRC=//p' "$XRUN_LOG" | tail -1)
    if [ "$XRUNRC" = "0" ] && [ -f "$EXE" ]; then
        pass_case "mingw cross-build produced z9torr.exe (XRUNRC=0)"
    else
        fail_case "mingw cross-build produced z9torr.exe (XRUNRC=$XRUNRC)"
    fi
else
    fail_case "mingw cross-build (see $XRUN_LOG)"
fi

# --- Step 3: PE32 + wsock32 sanity ------------------------------------------
echo "== step 3: PE32 + wsock32 sanity =="
if [ -f "$EXE" ]; then
    FTYPE=$(file "$EXE" 2>/dev/null)
    case "$FTYPE" in
        *PE32*) pass_case "file reports PE32 ($FTYPE)" ;;
        *)      fail_case "file reports PE32 (got: $FTYPE)" ;;
    esac
    if objdump -p "$EXE" 2>/dev/null | grep -qi 'wsock32'; then
        pass_case "objdump -p shows a wsock32 import"
    elif nm "$EXE" 2>/dev/null | grep -qi 'wsock32'; then
        pass_case "nm shows a wsock32 import"
    else
        fail_case "wsock32 import not found (objdump -p / nm)"
    fi
else
    fail_case "z9torr.exe not produced"
fi

# ===========================================================================
# RUN half (M5 Task 2): smoke the Windows artifact under 32-bit wine against
# the host mocks. Mirrors tier2's harness: same ports (testdata/ports.txt),
# same mock lifecycle (a one-shot peer restarted after every connection plus a
# tracker advertising every declared peer port), same golden payload + SHA-1
# assertion. Wine sees the Linux loopback as 127.0.0.1, so only the torrent
# path argument needs translating to a Wine-visible path (winepath -w).
#
# Build mode: S2 flipped every tier (and mock) build to -fsafe; the example UB
# that used to trap in makePeerId (checked LCG overflow) or read 0xAA poison in
# peer.zig is fixed, so the RUN exe is built the same safe way (via the
# compiler's own emitted build_target.sh mingw branch); Steps 2/3 keep the
# committed-recipe link/PE32/wsock32 evidence.
# ===========================================================================

FIXDIR="$Z9DIR/testdata"
EXPDIR="$FIXDIR/expected"
WORK="$OUT/work"

WINEPREFIX="${WINEPREFIX:-/tmp/wine32}"
WINEARCH="${WINEARCH:-win32}"
WINE_RUN_TIMEOUT="${WINE_RUN_TIMEOUT:-180}"
T1_LEN=1048576

echo "== step 4: build the -fsafe run exe (emitted build_target.sh mingw) =="
RUNWIN="$OUT/runwin"
EXE_RUN="$OUT/z9torr_run.exe"
rm -rf "$RUNWIN"
mkdir -p "$RUNWIN"
if timeout 200 "$ZIG" -fsafe -osw -o "$RUNWIN" "$ENTRY" >"$OUT/runemit.log" 2>&1 \
   && sh "$RUNWIN/build_target.sh" mingw "$EXE_RUN" >"$OUT/runbuild.log" 2>&1 \
   && [ -f "$EXE_RUN" ]; then
    pass_case "-fsafe run exe produced (z9torr_run.exe)"
else
    fail_case "-fsafe run exe produced (see $OUT/runemit.log / $OUT/runbuild.log)"
fi

# --- 32-bit wine runtime probe (SKIP-with-reason, never a silent pass) ------
echo "== step 5: 32-bit wine runtime probe =="
if [ -f "$EXE_RUN" ]; then
    if timeout 60 env WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" \
           wine "$EXE_RUN" --help >"$OUT/wine_probe.out" 2>"$OUT/wine_probe.err"; then
        PROBE_RC=0
    else
        PROBE_RC=$?
    fi
    if [ "$PROBE_RC" -eq 0 ] && grep -q "usage:" "$OUT/wine_probe.out" 2>/dev/null; then
        pass_case "32-bit wine runs the artifact (--help rc=0)"
    else
        echo "  probe stdout:"; sed -n '1,5p' "$OUT/wine_probe.out"
        echo "  probe stderr:"; sed -n '1,5p' "$OUT/wine_probe.err"
        skip "32-bit wine runtime unavailable (probe rc=$PROBE_RC)"
    fi
fi

# --- mock harness (tier2 pattern) -------------------------------------------
P_TRACKER="$(sed -n '1p' "$FIXDIR/ports.txt" | tr -d ' ')"
P_TRACKER="${P_TRACKER:-6969}"
PEER_PORTS="$(sed -n '2,$p' "$FIXDIR/ports.txt" | tr -d ' ')"
if [ -z "$PEER_PORTS" ]; then PEER_PORTS="6970"; fi
P_PEER=""
for _pp in $PEER_PORTS; do P_PEER="$_pp"; break; done
TRACKER_PEERS=""
for _pp in $PEER_PORTS; do
    if [ -z "$TRACKER_PEERS" ]; then TRACKER_PEERS="127.0.0.1:$_pp"
    else TRACKER_PEERS="$TRACKER_PEERS,127.0.0.1:$_pp"; fi
done

# A connect attempt is the only busy-port probe available here (no ss/lsof).
port_busy() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

if port_busy "$P_TRACKER"; then
    echo "FAIL: declared tracker port already in use (tracker=$P_TRACKER)"
    exit 1
fi
for _pp in $PEER_PORTS; do
    if port_busy "$_pp"; then
        echo "FAIL: declared peer port already in use (peer=$_pp)"
        exit 1
    fi
done

TR_PID=""
PEER_PIDS=""
CLIENT_PID=""
cleanup() {
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
    for _pid in $PEER_PIDS; do kill "$_pid" 2>/dev/null; done
    [ -n "$TR_PID" ] && kill "$TR_PID" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

build_bin() {
    _dir="$1"; _entry="$2"; _name="$3"
    mkdir -p "$_dir"
    if ! timeout 120 "$ZIG" -fsafe -o "$_dir" "$_entry" >"$_dir/zig.log" 2>&1; then
        echo "FAIL: zig compile $_name (see $_dir/zig.log)"
        return 1
    fi
    if ! sh "$_dir/build_target.sh" linux "$_dir/prog" >"$_dir/build.log" 2>&1; then
        echo "FAIL: target link $_name (see $_dir/build.log)"
        return 1
    fi
    if [ ! -x "$_dir/prog" ]; then
        echo "FAIL: $_name not built"
        return 1
    fi
    return 0
}

echo "== step 6: build host mocks (mock_tracker, mock_peer) =="
build_bin "$OUT/tr" "$Z9DIR/tools/mock_tracker.zig" mock_tracker || exit 1
build_bin "$OUT/pe" "$Z9DIR/tools/mock_peer.zig" mock_peer || exit 1
TRACKER="$OUT/tr/prog"
PEER="$OUT/pe/prog"

gen_payload() {
    awk -v seed="$1" -v size="$2" \
        'BEGIN { srand(seed); for (i = 0; i < size; i++) printf "%c", int(rand() * 256) }' > "$3"
}
gen_payload 1 "$T1_LEN" "$WORK/t1.payload"
PGOT="$(sha1sum "$WORK/t1.payload" | awk '{print $1}')"
PWANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
if [ "$PGOT" = "$PWANT" ]; then
    pass_case "t1 payload sha1 == expected ($PGOT)"
else
    fail_case "t1 payload sha1 got '$PGOT' want '$PWANT' (awk differs?)"
fi

start_tracker() {
    timeout 300 "$TRACKER" --port "$P_TRACKER" --peers "$TRACKER_PEERS" >"$OUT/tr.log" 2>&1 &
    TR_PID=$!
    _i=0
    while [ "$_i" -lt 50 ]; do
        if port_busy "$P_TRACKER"; then return 0; fi
        if ! kill -0 "$TR_PID" 2>/dev/null; then return 1; fi
        sleep 0.1
        _i=$((_i + 1))
    done
    return 1
}

# mock_peer accepts exactly ONE connection; the client is encrypted-first (its
# MSE probe consumes one connection before a plaintext reconnect). Restart the
# one-shot peer after every connection (tier2 pattern) so the fallback is
# served. The wrapper is killed as a unit (its TERM trap stops the child).
start_peer_port() {
    (
        _child=""
        trap 'if [ -n "$_child" ]; then kill "$_child" 2>/dev/null; fi; exit 0' TERM INT HUP
        while :; do
            timeout 300 "$PEER" --port "$1" --file "$2" --piece-length 262144 --mode "$3" &
            _child=$!
            wait "$_child"
            _child=""
        done
    ) >"$OUT/pe_$1.log" 2>&1 &
    _pid=$!
    PEER_PIDS="$PEER_PIDS $_pid"
    sleep 0.5
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    return 1
}

stop_peers() {
    for _pid in $PEER_PIDS; do kill "$_pid" 2>/dev/null; done
    for _pid in $PEER_PIDS; do wait "$_pid" 2>/dev/null; done
    PEER_PIDS=""
    sleep 0.5
}

echo "== step 7: start mocks (tracker $P_TRACKER, peer $P_PEER) =="
if start_tracker; then
    pass_case "mock_tracker listening on $P_TRACKER"
else
    fail_case "mock_tracker listening on $P_TRACKER (see $OUT/tr.log)"
fi
if start_peer_port "$P_PEER" "$WORK/t1.payload" normal; then
    pass_case "mock_peer listening on $P_PEER"
else
    fail_case "mock_peer listening on $P_PEER"
fi

# --- wine run ---------------------------------------------------------------
echo "== step 8: wine z9torr.exe (t1_single_1m) =="
RUN="$OUT/wine_run"
rm -rf "$RUN"
mkdir -p "$RUN"
WTOR="$(winepath -w "$FIXDIR/t1_single_1m.torrent" 2>/dev/null | tail -n1)"
if [ -z "$WTOR" ]; then WTOR="$FIXDIR/t1_single_1m.torrent"; fi
( cd "$RUN" && timeout "$WINE_RUN_TIMEOUT" env WINEPREFIX="$WINEPREFIX" \
      WINEARCH="$WINEARCH" Z9TORR_SEED=12345 \
      wine "$EXE_RUN" "$WTOR" >"$RUN/out.raw" 2>"$RUN/err.txt" )
WRC=$?
tr -d '\r' <"$RUN/out.raw" >"$RUN/out.norm"
echo "  WINE_RC=$WRC"
echo "  torrent (wine path): $WTOR"
echo "  run dir: $RUN"

if [ "$WRC" -eq 0 ]; then pass_case "wine client exit 0"; else fail_case "wine client exit 0 (got $WRC)"; fi

GOT="$(sha1sum "$RUN/t1.bin" 2>/dev/null | awk '{print $1}')"
WANT="$(cat "$EXPDIR/t1_single_1m.sha1")"
if [ "$GOT" = "$WANT" ]; then
    pass_case "wine output sha1 == expected ($GOT)"
else
    fail_case "wine output sha1 got '$GOT' want '$WANT'"
fi

if grep -q 'z9torr: download complete' "$RUN/out.norm"; then
    pass_case "client reported download complete"
else
    fail_case "client reported download complete"
fi

# Non-blocking connect + checkSoError (spec 12 risk 2): connectToIp sets
# O_NONBLOCK, select-waits for writable, then checkSoError reads SO_ERROR. If
# wine's select reported writable before the connect completed and the client
# mis-detected, the mock peer would never serve a block. The served-byte total
# is the decisive evidence.
FETCHED="$(sed -n 's/^summary: fetched=\([0-9]*\).*/\1/p' "$RUN/out.norm" | head -n1)"
REQS="$(sed -n 's/^summary: fetched=[0-9]* requests=\([0-9]*\).*/\1/p' "$RUN/out.norm" | head -n1)"
if [ "$FETCHED" = "$T1_LEN" ]; then
    pass_case "non-blocking connect: mock peer served fetched=$FETCHED requests=$REQS"
else
    fail_case "non-blocking connect: mock peer served (got fetched='$FETCHED' want $T1_LEN)"
fi

if [ "$WRC" -eq 0 ] && [ "$GOT" = "$WANT" ]; then
    echo "PARITY=OK wine_rc=$WRC output_sha1=$GOT fetched=$FETCHED"
    pass_case "PARITY=OK (LF-normalized stdout: $RUN/out.norm)"
else
    echo "PARITY=DIFF wine_rc=$WRC output_sha1=$GOT want=$WANT"
    fail_case "PARITY=OK"
fi

stop_peers

# --- summary ----------------------------------------------------------------
echo
echo "== tier4 summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER4 FAIL"
    exit 1
fi
echo "TIER4 PASS"
exit 0
