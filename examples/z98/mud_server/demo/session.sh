#!/usr/bin/env bash
# session.sh <mud_server_binary> <server_out_file> <client_out_file>
set -u
BIN="$1"; OUT="$2"; COUT="$3"; FEED="$(dirname "$0")/canonical_feed.txt"
port_busy() { awk 'NR>1{split($2,a,":"); if(a[2]=="0FA0" && $4=="0A") f=1} END{exit !f}' /proc/net/tcp 2>/dev/null; }
if port_busy; then echo "port 4000 already listening"; exit 1; fi
"$BIN" >"$OUT" 2>/dev/null &
SRV=$!
sleep 0.3
exec 3<>/dev/tcp/127.0.0.1/4000
# Capture the bytes the server sends to this client (client-received stream).
timeout 5 cat <&3 >"$COUT" &
READER=$!
while IFS= read -r line; do printf '%s\r\n' "$line" >&3; sleep 0.1; done <"$FEED"
sleep 0.3
exec 3>&-
wait "$READER" 2>/dev/null
sleep 0.2
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if port_busy; then echo "port 4000 still listening"; exit 1; fi
exit 0
