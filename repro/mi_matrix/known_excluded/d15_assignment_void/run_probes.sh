#!/usr/bin/env bash
# Task 9l probe runner. Requires Z98 (clean HEAD build) and the Zig oracle.
# usage: Z98=/tmp/.../zig1_5_clean ZIG=/tmp/.../zig ./run_probes.sh
set -u
Z98="${Z98:?set Z98 to a clean HEAD zig1_5_clean}"
ZIG="${ZIG:-/tmp/phase35-d15-i/zig-0.17.1/zig}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP="${TMPDIR:-/tmp}/phase35-9l-probes"
rm -rf "$TMP"; mkdir -p "$TMP"
cd "$ROOT/probes"
printf 'probe\tzig_rc\tz98_rc\tz98_c_files\n'
for f in z*.zig; do
  n="${f%.zig}"
  "$ZIG" build-exe "$f" --cache-dir "$TMP/zc" --global-cache-dir "$TMP/zg" \
    -femit-bin="$TMP/$n.out" >/dev/null 2>&1; zrc=$?
  "$Z98" --check -ffast "$f" >/dev/null 2>&1; rc=$?
  mkdir -p "$TMP/$n.d"; "$Z98" --dump-c89 -ffast --output-dir "$TMP/$n.d" "$f" >/dev/null 2>&1
  c=$(find "$TMP/$n.d" -name '*.c' | wc -l)
  printf '%s\t%s\t%s\t%s\n' "$n" "$zrc" "$rc" "$c"
done
