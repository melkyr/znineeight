#!/usr/bin/env bash
# tier_wireguard.sh — Phase 1 M7 integration tier for wireguard_demo.
#
# Far side: a Linux kernel WireGuard interface inside `unshare -Urn`, with the
# repo's mud_server (port 4000) and a tiny A-record DNS responder bound on the
# tunnel network. The demo is the initiator: it performs a real NoiseIK
# handshake against the kernel peer, resolves `mud.test` through the tunnel
# (pump-driven dnsResolve/tcpipPoll), opens the TCP session, prints the banner
# and one `look` reply, then the resource line.
#
# Cases:
#   (a) Linux build, DNS target, exact banner + reply + resource line.
#   (b) Linux build again (deterministic banner/reply; resource line ignored).
#   (c) Wine `-osw` build against the same far side, same assertions.
#   (d) Linux direct-IP target (no DNS config) proving the direct path.
#   (e) RAM: Linux DNS run under `ulimit -v 32768` + `/usr/bin/time -v`.
#   (f) `check_win9x_imports.sh 9x` (KERNEL32+WSOCK32, no msvcrt).
#
# Portable tools are preferred: /tmp/m7_tools (override with M7_TOOLS) before
# host `ip`/`wg`; if neither is usable the tier attempts to extract the
# portable .deb set into OUT. If kernel WireGuard/netns is unavailable, or the
# required build/run tools are missing, it prints a loud SKIP (never a vacuous
# pass) and records M7 integration as pending.
#
# usage: tier_wireguard.sh
# Env: ZIG (seed compiler), OUT (/tmp/tier_wireguard), M7_TOOLS (/tmp/m7_tools)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$DEMO_DIR/../../../.." && pwd)"
ZIG="${ZIG:-/tmp/m6_t3_v118_rotated/zig1_5_clean}"
OUT="${OUT:-/tmp/tier_wireguard}"
M7_TOOLS="${M7_TOOLS:-/tmp/m7_tools}"
ENTRY="$DEMO_DIR/main.zig"
MUD_ENTRY="$ROOT/examples/z98/mud_server/main.zig"

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

loud_skip() {
    echo "SKIP - $1"
    echo "SKIP - M7 integration pending (kernel WireGuard far side not exercised)"
    echo "TIER_WIREGUARD SKIP"
    exit 0
}

tool_ok() { [ -x "$1" ] || command -v "$1" >/dev/null 2>&1; }

# Prefer the verified portable set, then host tools, then extract the portable
# .deb set (no root install).
IP=""
WG=""
PORTABLE_IP="$M7_TOOLS/ip/bin/ip"
PORTABLE_WG="$M7_TOOLS/wg12/usr/bin/wg"
PORTABLE_LIBS="$M7_TOOLS/libs/usr/lib/x86_64-linux-gnu"
if [ -x "$PORTABLE_IP" ] && [ -x "$PORTABLE_WG" ]; then
    IP="$PORTABLE_IP"
    WG="$PORTABLE_WG"
elif command -v ip >/dev/null 2>&1 && command -v wg >/dev/null 2>&1; then
    IP="$(command -v ip)"
    WG="$(command -v wg)"
elif command -v dpkg-deb >/dev/null 2>&1; then
    mkdir -p "$OUT/portable"
    for deb in "$M7_TOOLS"/*iproute2*.deb "$M7_TOOLS"/*wireguard-tools*.deb \
               "$M7_TOOLS"/*libbpf*.deb "$M7_TOOLS"/*libmnl*.deb; do
        [ -f "$deb" ] && dpkg-deb -x "$deb" "$OUT/portable" >/dev/null 2>&1 || true
    done
    if [ -x "$OUT/portable/usr/sbin/ip" ] || [ -x "$OUT/portable/sbin/ip" ] \
       || [ -x "$OUT/portable/usr/bin/ip" ] || [ -x "$OUT/portable/bin/ip" ]; then
        IP="$(find "$OUT/portable" -type f -name ip -perm -u+x | head -1)"
        WG="$(find "$OUT/portable" -type f -name wg -perm -u+x | head -1)"
        PORTABLE_LIBS="$(dirname "$(find "$OUT/portable" -name 'libbpf.so*' | head -1)")"
    fi
fi
if [ -z "${IP:-}" ] || [ -z "${WG:-}" ]; then
    loud_skip "no usable kernel-WireGuard tools: portable ip/wg, host ip/wg, and .deb extraction all unavailable"
fi

export PATH="$(dirname "$IP"):$(dirname "$WG"):$PATH"
if [ -n "${PORTABLE_LIBS:-}" ] && [ -d "$PORTABLE_LIBS" ]; then
    export LD_LIBRARY_PATH="$PORTABLE_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Outer stage: build, import gate, then re-exec inside the netns.
if [ "${Z98_WG_INNER:-0}" != "1" ]; then
    for t in "$ZIG" "$IP" "$WG" unshare python3 /usr/bin/time timeout \
             i686-w64-mingw32-gcc i686-w64-mingw32-objdump; do
        if ! tool_ok "$t"; then
            loud_skip "required tool unavailable: $t"
        fi
    done
    if ! unshare -Urn true >/dev/null 2>&1; then
        loud_skip "unshare -Urn unavailable: cannot create the WireGuard far-side netns"
    fi
    if ! unshare -Urn env PATH="$PATH" LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" \
        bash -c "'$IP' link add z98wgprobe type wireguard && '$IP' link del z98wgprobe" \
        >/dev/null 2>&1; then
        loud_skip "kernel WireGuard interface creation unavailable in the netns"
    fi
    HAVE_WINE=0
    if command -v wine >/dev/null 2>&1; then HAVE_WINE=1; fi

    rm -rf "$OUT"
    mkdir -p "$OUT"

    echo "== build mud_server (linux) =="
    mkdir -p "$OUT/mud_emit"
    if timeout 240 "$ZIG" -ffast -o "$OUT/mud_emit" "$MUD_ENTRY" \
        >"$OUT/mud_emit.log" 2>&1 \
       && sh "$OUT/mud_emit/build_target.sh" linux "$OUT/mud_server" \
        >>"$OUT/mud_emit.log" 2>&1 && [ -x "$OUT/mud_server" ]; then
        pass_case "linux mud_server build"
    else
        fail_case "linux mud_server build (see $OUT/mud_emit.log)"
        tail -20 "$OUT/mud_emit.log" 2>/dev/null | sed 's/^/       /'
        echo "TIER_WIREGUARD FAIL"
        exit 1
    fi

    echo "== build wireguard_demo (linux, -fsafe) =="
    mkdir -p "$OUT/linux_emit"
    if timeout 240 "$ZIG" -fsafe -o "$OUT/linux_emit" "$ENTRY" \
        >"$OUT/linux_emit.log" 2>&1 \
       && sh "$OUT/linux_emit/build_target.sh" linux "$OUT/wireguard_demo" \
        >>"$OUT/linux_emit.log" 2>&1 && [ -x "$OUT/wireguard_demo" ]; then
        pass_case "linux -fsafe build produced wireguard_demo"
    else
        fail_case "linux -fsafe build (see $OUT/linux_emit.log)"
        tail -20 "$OUT/linux_emit.log" 2>/dev/null | sed 's/^/       /'
        echo "TIER_WIREGUARD FAIL"
        exit 1
    fi

    echo "== targeted config errors =="
    ZERO64="0000000000000000000000000000000000000000000000000000000000000000"
    check_config_exit() {
        local label="$1" conf="$2" want="$3"
        local rc got err
        timeout 10 "$OUT/wireguard_demo" "$conf" \
            >"$OUT/cfg_$label.out" 2>"$OUT/cfg_$label.err"
        rc=$?
        got="$(cat "$OUT/cfg_$label.out" "$OUT/cfg_$label.err" 2>/dev/null)"
        err="$(cat "$OUT/cfg_$label.err" 2>/dev/null)"
        if [ "$rc" -ne 0 ] && [ "$got" = "$want" ]; then
            pass_case "config $label -> $want"
        else
            fail_case "config $label (rc=$rc, got '$got' want '$want', err='$err')"
        fi
    }
    cat >"$OUT/cfg_unknown.conf" <<EOF
private_key = $ZERO64
peer_public_key = $ZERO64
endpoint = 127.0.0.1:1
address = 10.7.0.2/24
mud_ip = 10.7.0.1
bogus_key = 1
EOF
    cat >"$OUT/cfg_missing.conf" <<EOF
private_key = $ZERO64
endpoint = 127.0.0.1:1
address = 10.7.0.2/24
mud_ip = 10.7.0.1
EOF
    cat >"$OUT/cfg_badkey.conf" <<EOF
private_key = definitely-not-a-key
peer_public_key = $ZERO64
endpoint = 127.0.0.1:1
address = 10.7.0.2/24
mud_ip = 10.7.0.1
EOF
    cat >"$OUT/cfg_badvalue.conf" <<EOF
private_key = $ZERO64
peer_public_key = $ZERO64
endpoint = 127.0.0.1:1
address = 10.7.0.2/24
mud_ip = 10.7.0.1
mtu = not-a-number
EOF
    check_config_exit unknown "$OUT/cfg_unknown.conf" "wg: BadConfig"
    check_config_exit missing_required "$OUT/cfg_missing.conf" "wg: BadConfig"
    check_config_exit bad_key "$OUT/cfg_badkey.conf" "wg: BadKey"
    check_config_exit malformed_value "$OUT/cfg_badvalue.conf" "wg: BadConfig"

    echo "== build wireguard_demo (-osw) + Win9x import gate =="
    mkdir -p "$OUT/win_emit"
    EXE="$OUT/wireguard_demo.exe"
    if timeout 240 "$ZIG" -fsafe -osw -o "$OUT/win_emit" "$ENTRY" \
        >"$OUT/osw_emit.log" 2>&1 \
       && sh "$OUT/win_emit/build_target.sh" mingw "$EXE" \
        >>"$OUT/osw_emit.log" 2>&1 && [ -f "$EXE" ]; then
        pass_case "-osw emit + mingw build produced wireguard_demo.exe"
    else
        fail_case "-osw emit/build (see $OUT/osw_emit.log)"
        tail -20 "$OUT/osw_emit.log" 2>/dev/null | sed 's/^/       /'
        echo "TIER_WIREGUARD FAIL"
        exit 1
    fi

    if bash "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$EXE" 9x \
        >"$OUT/imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x whitelist PASS"
        grep -E '^DLL ' "$OUT/imports.log" | sed 's/^/       /'
    else
        fail_case "check_win9x_imports.sh 9x whitelist FAILED"
        tail -15 "$OUT/imports.log" 2>/dev/null | sed 's/^/       /'
        echo "TIER_WIREGUARD FAIL"
        exit 1
    fi

    echo "== enter kernel WireGuard netns =="
    unshare -Urn env \
        Z98_WG_INNER=1 OUT="$OUT" ZIG="$ZIG" IP="$IP" WG="$WG" \
        PATH="$PATH" LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" HAVE_WINE="$HAVE_WINE" \
        bash "$0"
    rc=$?
    if [ "$rc" -ne 0 ]; then echo "TIER_WIREGUARD FAIL"; else echo "TIER_WIREGUARD PASS"; fi
    exit "$rc"
fi

# Inner stage: netns setup + live far side + all demo runs.
DPID=""
MPID=""
WG_UP=0
stop_far_side() {
    [ -n "$DPID" ] && kill "$DPID" 2>/dev/null || true
    [ -n "$MPID" ] && kill "$MPID" 2>/dev/null || true
    [ -n "$DPID" ] && wait "$DPID" 2>/dev/null || true
    [ -n "$MPID" ] && wait "$MPID" 2>/dev/null || true
    if [ "$WG_UP" = "1" ]; then "$IP" link del wg0 >/dev/null 2>&1 || true; fi
}
trap stop_far_side EXIT INT TERM
umask 077

"$IP" link set lo up || { fail_case "netns loopback up"; echo "TIER_WIREGUARD FAIL"; exit 1; }
"$IP" link add wg0 type wireguard || { fail_case "kernel wg0 create"; echo "TIER_WIREGUARD FAIL"; exit 1; }
WG_UP=1

SERVER_KEY="$OUT/server.key"
CLIENT_KEY="$OUT/client.key"
SERVER_PUB="$OUT/server.pub"
CLIENT_PUB="$OUT/client.pub"
"$WG" genkey >"$SERVER_KEY" 2>/dev/null || { fail_case "wg genkey (server)"; exit 1; }
"$WG" pubkey <"$SERVER_KEY" >"$SERVER_PUB" 2>/dev/null || { fail_case "wg pubkey (server)"; exit 1; }
"$WG" genkey >"$CLIENT_KEY" 2>/dev/null || { fail_case "wg genkey (client)"; exit 1; }
"$WG" pubkey <"$CLIENT_KEY" >"$CLIENT_PUB" 2>/dev/null || { fail_case "wg pubkey (client)"; exit 1; }

cat >"$OUT/server.conf" <<EOF
[Interface]
PrivateKey = $(cat "$SERVER_KEY")
ListenPort = 51820

[Peer]
PublicKey = $(cat "$CLIENT_PUB")
AllowedIPs = 10.7.0.0/24
EOF
"$WG" setconf wg0 "$OUT/server.conf" || { fail_case "wg setconf wg0"; exit 1; }
"$IP" addr add 10.7.0.1/24 dev wg0 || { fail_case "ip addr add tunnel far side"; exit 1; }
"$IP" link set mtu 1400 dev wg0 || { fail_case "ip link set mtu"; exit 1; }
"$IP" link set wg0 up || { fail_case "ip link set wg0 up"; exit 1; }

cat >"$OUT/dns.py" <<'PY'
import socket, struct
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('10.7.0.1', 53))
while True:
    d, a = s.recvfrom(2048)
    i = 12
    while i < len(d) and d[i] != 0:
        i += 1 + d[i]
    i += 5
    if i > len(d):
        continue
    q = d[12:i]
    hdr = d[:2] + struct.pack('!HHHHH', 0x8180, 1, 1, 0, 0)
    ans = b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4) + socket.inet_aton('10.7.0.1')
    s.sendto(hdr + q + ans, a)
PY
python3 "$OUT/dns.py" >"$OUT/dns.log" 2>&1 &
DPID=$!
"$OUT/mud_server" >"$OUT/mud.log" 2>&1 &
MPID=$!
sleep 0.4
if ! kill -0 "$DPID" 2>/dev/null; then
    fail_case "tunnel DNS responder failed to start (cannot bind 10.7.0.1:53?)"
    sed 's/^/       /' "$OUT/dns.log" 2>/dev/null | head -5
    echo "== tier_wireguard summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    exit 1
fi
if ! kill -0 "$MPID" 2>/dev/null; then
    fail_case "mud_server failed to start"
    sed 's/^/       /' "$OUT/mud.log" 2>/dev/null | head -5
    echo "== tier_wireguard summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    exit 1
fi

write_client_conf() {
    local path="$1" clock="$2" direct="$3" host="$4"
    cat >"$path" <<EOF
private_key = $(cat "$CLIENT_KEY")
peer_public_key = $(cat "$SERVER_PUB")
endpoint = 127.0.0.1:51820
address = 10.7.0.$host/24
mtu = 1400
clock_override_unix = $clock
command = look
EOF
    if [ "$direct" = "1" ]; then
        echo "mud_ip = 10.7.0.1" >>"$path"
    else
        echo "dns_server = 10.7.0.1" >>"$path"
        echo "mud_host = mud.test" >>"$path"
    fi
    echo "mud_port = 4000" >>"$path"
}

BANNER_TEXT="Welcome to the MUD! Type 'look' to start."
REPLY_TEXT="You are in a dark forest. There is a path to the north."
printf '%s\r\n%s\r\n' "$BANNER_TEXT" "$REPLY_TEXT" >"$OUT/expected.txt"
EXPECTED_LEN="$(wc -c <"$OUT/expected.txt" | tr -d ' ')"

check_output() {
    local label="$1" outfile="$2" prefix="$3"
    local res res_bytes
    res="$(grep '^wireguard_demo ok ' "$outfile" 2>/dev/null | tail -1)"
    if [ ! -s "$outfile" ]; then
        fail_case "$label: no output"
        return 1
    fi
    head -c "$EXPECTED_LEN" "$outfile" >"$OUT/$prefix.prefix" 2>/dev/null || true
    if ! cmp -s "$OUT/expected.txt" "$OUT/$prefix.prefix"; then
        fail_case "$label: banner/reply bytes differ"
        sed -n '1,3p' "$outfile" 2>/dev/null | cat -v | sed 's/^/       /'
        return 1
    fi
    if ! printf '%s\n' "$res" | grep -Eq \
        '^wireguard_demo ok bytes=[0-9]+ arena_peak=[0-9]+ rss_peak=[0-9]+ cpu_ms=[0-9]+$'; then
        fail_case "$label: resource line missing/malformed ('$res')"
        return 1
    fi
    res_bytes="$(printf '%s\n' "$res" | sed -n 's/^wireguard_demo ok bytes=\([0-9][0-9]*\) .*/\1/p')"
    if [ "$res_bytes" != "$EXPECTED_LEN" ]; then
        fail_case "$label: resource bytes=$res_bytes != expected banner+reply bytes=$EXPECTED_LEN"
        return 1
    fi
    return 0
}

BASE_TS="$(date +%s)"

echo "== (a) Linux demo: DNS through the tunnel =="
write_client_conf "$OUT/client_dns.conf" "$BASE_TS" 0 2
timeout 40 "$OUT/wireguard_demo" "$OUT/client_dns.conf" \
    >"$OUT/linux1.out" 2>"$OUT/linux1.err"
RC=$?
if [ "$RC" -eq 0 ] && check_output "linux DNS run" "$OUT/linux1.out" linux1; then
    pass_case "linux DNS run: exact banner + look reply + resource line"
    grep '^wireguard_demo ok ' "$OUT/linux1.out" | sed 's/^/       /'
else
    fail_case "linux DNS run (rc=$RC; see $OUT/linux1.out / $OUT/linux1.err)"
    sed 's/^/       /' "$OUT/linux1.err" 2>/dev/null | head -5
fi

echo "== (b) Linux demo again: deterministic banner/reply =="
write_client_conf "$OUT/client_dns2.conf" "$((BASE_TS + 1))" 0 3
timeout 40 "$OUT/wireguard_demo" "$OUT/client_dns2.conf" \
    >"$OUT/linux2.out" 2>"$OUT/linux2.err"
RC=$?
if [ "$RC" -eq 0 ] && check_output "linux DNS run 2" "$OUT/linux2.out" linux2; then
    sed '/^wireguard_demo ok /d' "$OUT/linux1.out" >"$OUT/linux1.norm"
    sed '/^wireguard_demo ok /d' "$OUT/linux2.out" >"$OUT/linux2.norm"
    if cmp -s "$OUT/linux1.norm" "$OUT/linux2.norm"; then
        pass_case "linux banner/reply identical 2x"
    else
        fail_case "linux banner/reply differ across 2 runs"
    fi
else
    fail_case "linux DNS run 2 (rc=$RC; see $OUT/linux2.out / $OUT/linux2.err)"
    sed 's/^/       /' "$OUT/linux2.err" 2>/dev/null | head -5
fi

echo "== (c) Wine -osw demo against the same far side =="
if [ "${HAVE_WINE:-0}" = "1" ]; then
    write_client_conf "$OUT/client_wine.conf" "$((BASE_TS + 2))" 0 4
    timeout 90 env WINEDEBUG=-all WINEPREFIX="$OUT/wine" wine \
        "$OUT/wireguard_demo.exe" "$OUT/client_wine.conf" \
        >"$OUT/wine.out" 2>"$OUT/wine.err"
    RC=$?
    if [ "$RC" -eq 0 ] && check_output "wine -osw run" "$OUT/wine.out" wine; then
        pass_case "wine -osw run: exact banner + look reply + resource line"
        grep '^wireguard_demo ok ' "$OUT/wine.out" | sed 's/^/       /'
    else
        fail_case "wine -osw run (rc=$RC; see $OUT/wine.out / $OUT/wine.err)"
        sed 's/^/       /' "$OUT/wine.err" 2>/dev/null | head -8
    fi
else
    skip_case "wine unavailable: -osw demo SKIPPED"
fi

echo "== (d) Linux demo: direct-IP target (no DNS config) =="
write_client_conf "$OUT/client_direct.conf" "$((BASE_TS + 3))" 1 5
if grep -q '^dns_server' "$OUT/client_direct.conf"; then
    fail_case "direct config unexpectedly contains dns_server"
else
    timeout 40 "$OUT/wireguard_demo" "$OUT/client_direct.conf" \
        >"$OUT/direct.out" 2>"$OUT/direct.err"
    RC=$?
    if [ "$RC" -eq 0 ] && check_output "linux direct-IP run" "$OUT/direct.out" direct; then
        pass_case "linux direct-IP run: exact banner + look reply + resource line"
    else
        fail_case "linux direct-IP run (rc=$RC; see $OUT/direct.out / $OUT/direct.err)"
        sed 's/^/       /' "$OUT/direct.err" 2>/dev/null | head -5
    fi
fi

echo "== (e) RAM: ulimit -v 32768 + /usr/bin/time -v peak =="
write_client_conf "$OUT/client_ram.conf" "$((BASE_TS + 4))" 0 6
( ulimit -v 32768; /usr/bin/time -v "$OUT/wireguard_demo" "$OUT/client_ram.conf" ) \
    >"$OUT/ram.out" 2>"$OUT/ram.err"
RC=$?
RAM_PEAK="$(sed -n 's/.*Maximum resident set size (kbytes): *\([0-9][0-9]*\).*/\1/p' "$OUT/ram.err" 2>/dev/null | tail -1)"
if [ "$RC" -eq 0 ] && check_output "RAM run" "$OUT/ram.out" ram \
   && [ -n "$RAM_PEAK" ] && [ "$RAM_PEAK" -gt 0 ]; then
    pass_case "RAM ceiling ok: peak RSS=${RAM_PEAK} kB (ulimit -v 32768)"
    echo "       peak_rss_kb=$RAM_PEAK"
else
    fail_case "RAM ceiling run (rc=$RC, peak='${RAM_PEAK:-none}')"
    head -10 "$OUT/ram.err" 2>/dev/null | sed 's/^/       /'
fi

echo
echo "== tier_wireguard summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    exit 1
fi
exit 0
