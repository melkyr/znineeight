#!/usr/bin/env bash
# run_upgraded.sh <zig1> <entry> <feed> <out_stdout>
# Builds <entry> with <zig1> into a fresh dir, runs it on <feed>, captures stdout.
set -u
ZIG1="$1"; ENTRY="$2"; FEED="$3"; OUT="$4"
ROOT=/workspace/znineeight
W=$(mktemp -d)
rm -rf "$W"; mkdir -p "$W"
(cd "$ROOT" && "$ZIG1" --dump-c89 --output-dir "$W" "$ENTRY") >"$W/dump.log" 2>&1
if [ $? -ne 0 ]; then echo "RUNRC=DUMPFAIL"; cat "$W/dump.log"; exit 1; fi
if [ -f "$W/zig_runtime.c" ]; then
  for f in "$W"/*.c; do
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$W" -c "$f" -o "${f%.c}.o" || { echo "RUNRC=GCCFAIL"; exit 1; }
  done
  gcc -m32 -o "$W/prog" "$W"/*.o || { echo "RUNRC=LINKFAIL"; exit 1; }
else
  for f in "$W"/*.c; do
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$ROOT/sf/src/include" -c "$f" -o "${f%.c}.o" || { echo "RUNRC=GCCFAIL"; exit 1; }
  done
  gcc -m32 -o "$W/prog" "$W"/*.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" || { echo "RUNRC=LINKFAIL"; exit 1; }
fi
timeout 120 "$W/prog" < "$FEED" > "$OUT" 2>"$W/run.err"
echo "RUNRC=$?"
