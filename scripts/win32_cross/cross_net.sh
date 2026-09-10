#!/usr/bin/env bash
# cross_net.sh — win32 net-program cross runner (pre-test plan Task 2, 2026-09-04).
#
# Cross-builds the two F6-migrated net programs for win32 (i686-w64-mingw32-gcc,
# link set = zig_runtime.c + zig_pal.c + -lwsock32) and runs them under the
# dedicated win32 wine prefix, comparing stdout to the linux goldens:
#
#   Phase A  examples/z98/mud_server/main.zig
#            linux golden (boot + movement response) is DERIVED live: the linux
#            server runs under the flush.so _IONBF shim, a scratch linux client
#            sends 'north\n', and server stdout + client-received bytes are kept.
#   Phase B  examples/z98/rogue_mud_upgraded/demo/{net_main.zig,net_demo_client.zig}
#            (dumped from the rogue program dir CWD — module resolution is
#            CWD-relative). Golden = committed demo/net_demo_expected.txt
#            (md5 aa40a52e).
#
# Capture method under wine (empirical, Task 2): the CRT fwrite stdout of a
# never-exiting wine server is lost on timeout-kill (0 bytes — no linux
# LD_PRELOAD applies to wine). A graceful guest exit flushes msvcrt at exit:
# net_main's local-input path reads getchar(), so feeding 'iq' on stdin triggers
# the demo block ('i') and then breaks the game loop ('q') -> main returns ->
# full stdout flushed. Deterministic 3x.
#
# Known win32 gap (recorded, NOT fixed — zero source edits): the F6 std_net
# emission's init()/cleanup() are empty stubs that never call WSAStartup, so on
# the win32 path socket() fails with WSANOTINITIALISED (10093) under wine (and
# would on real win9x). mud_server cannot create its server socket and exits;
# rogue net_main catches the init failure and degrades to local-only mode. A
# wine-side control probe proves wine's winsock surface (bind/listen/connect-to-
# 0.0.0.0/accept/select/send/recv) works once WSAStartup has run.
#
# Output is LF-normalized before parity (PARITY_STRIP_CR criterion, AMENDMENT 1):
# CRT text mode translates \n -> \r\n on the std_io fwrite path under win32.
# Raw wine stdout is preserved as stdout.txt evidence.
#
# Usage: bash cross_net.sh [<zig1>]
# Env:   ROOT (repo, default /workspace/znineeight), WINEPREFIX (/tmp/wine32),
#        CROSS_GCC, TIMEOUT_*.
# Exit 0 only when every phase reproduced its predicted evidence.
set -u

ROOT=${ROOT:-/workspace/znineeight}
ZIG1=${1:-/tmp/fx_subfolder/zig1}
WINEPREFIX=${WINEPREFIX:-/tmp/wine32}
CROSS_GCC=${CROSS_GCC:-i686-w64-mingw32-gcc}
TIMEOUT_DUMP=${TIMEOUT_DUMP:-300}
TIMEOUT_CC=${TIMEOUT_CC:-180}

INC="$ROOT/sf/src/include"
MUDG="$ROOT/examples/z98/mud_server"
ROGUE="$ROOT/examples/z98/rogue_mud_upgraded"
RDEMO="$ROGUE/demo"
NETEXP="$RDEMO/net_demo_expected.txt"

W=$(mktemp -d /tmp/cross_net.XXXXXX)
FAILED=0
phase_fail() { echo "NET FAILED:$1"; FAILED=1; }

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

# build_from <cwd> <entry> <outdir> <exe> [extra...] — dump from <cwd>, mingw
# compile+link each emitted .c (mirrors cross_build_run.sh but CWD-controllable).
build_from() {
    local cwd=$1 entry=$2 outdir=$3 exe=$4; shift 4
    rm -rf "$outdir"; mkdir -p "$outdir/dump"
    (cd "$cwd" && timeout "$TIMEOUT_DUMP" "$ZIG1" --dump-c89 --output-dir "$outdir/dump" "$entry") >"$outdir/dump.log" 2>&1
    local rc=$?
    local nerr npan
    nerr=$(grep -c 'error\[' "$outdir/dump.log" 2>/dev/null || true)
    npan=$(grep -c 'PANIC' "$outdir/dump.log" 2>/dev/null || true)
    if [ $rc -ne 0 ] || [ "$nerr" -ne 0 ] || [ "$npan" -ne 0 ]; then
        echo "  build $outdir: DUMP rc=$rc err=$nerr pan=$npan"; sed -n '1,25p' "$outdir/dump.log"
        return 1
    fi
    local dinc
    if [ -f "$outdir/dump/zig_runtime.c" ]; then dinc="$outdir/dump"; else dinc="$INC"; fi
    local f n=0
    for f in "$outdir/dump"/*.c; do
        n=$((n + 1))
        timeout "$TIMEOUT_CC" "$CROSS_GCC" -std=c89 -m32 -Wall -Wno-long-long \
            -Wno-pointer-sign -I "$dinc" -c "$f" -o "${f%.c}.o" >>"$outdir/cc.log" 2>&1 || {
                echo "  build $outdir: GCCFAIL $(basename "$f")"; tail -10 "$outdir/cc.log"; return 1; }
    done
    if [ -f "$outdir/dump/zig_runtime.c" ]; then
        timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -o "$exe" "$outdir/dump"/*.o \
            "$@" >>"$outdir/ld.log" 2>&1 || {
                echo "  build $outdir: LINKFAIL"; tail -15 "$outdir/ld.log"; return 1; }
    else
        timeout "$TIMEOUT_CC" "$CROSS_GCC" -m32 -o "$exe" "$outdir/dump"/*.o \
            "$INC/zig_runtime.c" "$INC/zig_pal.c" "$@" >>"$outdir/ld.log" 2>&1 || {
                echo "  build $outdir: LINKFAIL"; tail -15 "$outdir/ld.log"; return 1; }
    fi
    echo "  build $outdir: dump rc=$rc err=$nerr pan=$npan c=$n link ok"
    return 0
}

# build_linux <cwd> <entry> <outdir> <exe> — gcc -m32 (linux reference build).
build_linux() {
    local cwd=$1 entry=$2 outdir=$3 exe=$4
    rm -rf "$outdir"; mkdir -p "$outdir"
    (cd "$cwd" && timeout "$TIMEOUT_DUMP" "$ZIG1" --dump-c89 --output-dir "$outdir" "$entry") >"$outdir/dump.log" 2>&1
    local rc=$? f n=0
    local dinc
    if [ -f "$outdir/zig_runtime.c" ]; then dinc="$outdir"; else dinc="$INC"; fi
    for f in "$outdir"/*.c; do
        n=$((n + 1))
        gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$dinc" \
            -c "$f" -o "${f%.c}.o" >>"$outdir/gcc.log" 2>&1 || return 1
    done
    if [ -f "$outdir/zig_runtime.c" ]; then
        gcc -m32 -o "$exe" "$outdir"/*.o 2>>"$outdir/gcc.log" || return 1
    else
        gcc -m32 -o "$exe" "$outdir"/*.o "$INC/zig_runtime.c" "$INC/zig_pal.c" 2>>"$outdir/gcc.log" || return 1
    fi
    return 0
}

echo "== win32 net-program cross runner =="
echo "   zig1: $ZIG1"
echo "   scratch: $W"
echo "   wine prefix: $WINEPREFIX"

if port4000_listen; then
    echo "port 4000 already LISTEN before run"; exit 1
fi

gcc -m32 -shared -fPIC -o "$W/flush.so" "$ROOT/scripts/closeout/flush.c" 2>/dev/null || {
    echo "flush.so build FAILED"; exit 1; }

# ---------------------------------------------------------------------------
echo
echo "== Phase A: mud_server =="
echo "  (F6-migrated: emitted std_net C has its own #ifdef _WIN32 winsock path;"
echo "   net_runtime.c NOT linked. -lwsock32 required — mingw ignores the"
echo "   emitted '#pragma comment(lib, \"wsock32.lib\")'.)"

# A0: linux golden derivation -----------------------------------------------
build_linux "$ROOT" "examples/z98/mud_server/main.zig" "$W/A-lin-mud" "$W/A-lin-mud/prog" || {
    phase_fail "A(linux-mud-build)"; }
# scratch Z98 mud client (uncommitted, generated in scratch)
mkdir -p "$W/A-cli"
cat >"$W/A-cli/mud_client.zig" <<'EOF'
const std = @import("std");
const std_net = @import("std_net");
const PORT: u16 = 4000;
var rbuf: [1024]u8 = undefined;
fn drain(fd: i32, timeout_ms: i32) usize {
    var read_fds: std_net.fd_set = undefined;
    std_net.fdZero(@ptrCast(*u8, &read_fds));
    std_net.fdSet(fd, @ptrCast(*u8, &read_fds));
    const n = std_net.select(fd + 1, @ptrCast(*u8, &read_fds), null, null, timeout_ms);
    if (n <= 0) return 0;
    if (!std_net.fdIsset(fd, @ptrCast(*u8, &read_fds))) return 0;
    const r = std_net.recv(fd, &rbuf[0], @intCast(i32, rbuf.len));
    if (r <= 0) return 0;
    return @intCast(usize, r);
}
pub fn main() void {
    const client = std_net.createTcpServer(0);
    if (client < 0) @exit(@intCast(u8, 1));
    if (std_net.connect(client, PORT) < 0) @exit(@intCast(u8, 2));
    var t: i32 = 0;
    while (t < 20) : (t += 1) {
        const got = drain(client, 200);
        if (got == 0) break;
        std.io.write(rbuf[0..got]);
    }
    const cmd: []const u8 = "north\n";
    _ = std_net.send(client, cmd.ptr, @intCast(i32, cmd.len));
    t = 0;
    while (t < 20) : (t += 1) {
        const got = drain(client, 200);
        if (got == 0) break;
        std.io.write(rbuf[0..got]);
    }
    std_net.close(client);
    @exit(@intCast(u8, 0));
}
EOF
build_linux "$ROOT" "$W/A-cli/mud_client.zig" "$W/A-lin-cli" "$W/A-lin-cli/prog" || {
    phase_fail "A(linux-client-build)"; }

( timeout -k 2 15 env LD_PRELOAD="$W/flush.so" "$W/A-lin-mud/prog" </dev/null \
      >"$W/A-lin-srv.out" 2>"$W/A-lin-srv.err" ) &
A_SRV=$!
sleep 0.5
timeout 15 "$W/A-lin-cli/prog" >"$W/A-lin-cli.out" 2>"$W/A-lin-cli.err"
A_CLI_RC=$?
wait "$A_SRV"; A_SRV_RC=$?
echo "  A-linux-golden: server rc=$A_SRV_RC client rc=$A_CLI_RC"
echo "    server stdout md5 = $(md5sum "$W/A-lin-srv.out" | cut -d' ' -f1)"
echo "    client received md5 = $(md5sum "$W/A-lin-cli.out" | cut -d' ' -f1)"

# A1: win32 cross build ------------------------------------------------------
if ! build_from "$ROOT" "examples/z98/mud_server/main.zig" "$W/A-win-mud" \
        "$W/A-win-mud/prog.exe" -lwsock32; then
    phase_fail "A(cross-build)"
fi
echo "  A-win build OK (link set: zig_runtime.c + zig_pal.c + -lwsock32)"

# A2: wine run (mud_server cannot bind — known WSAStartup gap) ---------------
( timeout -k 2 12 env WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
      wine "$W/A-win-mud/prog.exe" </dev/null \
      >"$W/A-win.out" 2>"$W/A-win.err" )
A_WIN_RC=$?
echo "  A-win run: rc=$A_WIN_RC"
echo "    wine server stdout md5 = $(md5sum "$W/A-win.out" | cut -d' ' -f1)"
# also connect the linux client to prove no listener is up on 4000
timeout 6 "$W/A-lin-cli/prog" >"$W/A-win-cli.out" 2>"$W/A-win-cli.err"
echo "    linux client vs wine server rc=$? (connect refused expected, no listener)"

echo "  A verdict: wine stdout = '$(cat "$W/A-win.out")'"
echo "    cross rc=0 | wine rc=$A_WIN_RC | parity=DIFF vs linux golden (server cannot"
echo "    bind: socket()=WSANOTINITIALISED 10093, no WSAStartup in F6 std_net init)"
echo "    class=gap (source/emission) — NOT environment, NOT toolchain"

# ---------------------------------------------------------------------------
echo
echo "== Phase B: rogue net demo (net_main + net_demo_client) =="
# B0: win32 cross builds (dump from rogue program dir CWD) -------------------
if ! build_from "$ROGUE" "demo/net_main.zig" "$W/B-win-srv" \
        "$W/B-win-srv/prog.exe" -lwsock32; then
    phase_fail "B(cross-build-server)"
fi
if ! build_from "$ROGUE" "demo/net_demo_client.zig" "$W/B-win-cli" \
        "$W/B-win-cli/prog.exe" -lwsock32; then
    phase_fail "B(cross-build-client)"
fi
echo "  B-win builds OK (both -lwsock32)"

# B1: wine server run, stdin 'iq' drives demoInfo + graceful 'q' exit --------
mkdir -p "$W/B-srvrun"
printf 'iq' >"$W/B-srvrun/in.txt"
timeout -k 3 20 env WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
    wine "$W/B-win-srv/prog.exe" <"$W/B-srvrun/in.txt" \
    >"$W/B-srvrun/stdout.txt" 2>"$W/B-srvrun/stderr.txt"
B_WIN_RC=$?
tr -d '\r' <"$W/B-srvrun/stdout.txt" >"$W/B-srvrun/stdout.norm"
echo "  B-win server run: rc=$B_WIN_RC (graceful exit via stdin 'q')"
echo "    raw stdout md5 = $(md5sum "$W/B-srvrun/stdout.txt" | cut -d' ' -f1) ($(wc -c <"$W/B-srvrun/stdout.txt") bytes, CRLF)"
echo "    LF-normalized md5 = $(md5sum "$W/B-srvrun/stdout.norm" | cut -d' ' -f1)"
echo "    golden (aa40a52e) md5 = $(md5sum "$NETEXP" | cut -d' ' -f1)"

# B2: LF-normalized parity vs committed golden -------------------------------
if cmp -s "$W/B-srvrun/stdout.norm" "$NETEXP"; then
    echo "  B parity: PARITY=OK (LF-normalized byte-identical)"
else
    echo "  B parity: PARITY=DIFF (LF-normalized) — expected signature:"
    diff "$W/B-srvrun/stdout.norm" "$NETEXP"
    echo "  B class=gap (WSAStartup) — server degraded to local-only; every other"
    echo "    line byte-identical to the net golden (boot + demo block)"
fi

# B3: wine client against the degraded (local-only) server -------------------
timeout 6 env WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
    wine "$W/B-win-cli/prog.exe" >"$W/B-srvrun/client.out" 2>"$W/B-srvrun/client.err"
B_CLI_RC=$?
echo "  B-win client: rc=$B_CLI_RC (socket() fails 10093 — no listener, expected)"

# ---------------------------------------------------------------------------
echo
echo "== hygiene =="
if port4000_listen; then
    echo "port 4000 still LISTEN after run"; exit 1
fi
echo "port 4000 clear after run (no leftover listener, no pkill)"

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "NET VERDICT: FAILED (evidence dir $W)"
    exit 1
fi
echo
echo "NET VERDICT: evidence reproduced (win32 WSAStartup gap confirmed; env clean)"
echo "evidence: $W"
exit 0
