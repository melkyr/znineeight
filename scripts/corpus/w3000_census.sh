#!/usr/bin/env bash
# Task 0l pin mechanism — per-directory `warning[3000]` census.
#
# The gcc-based corpus classifier (scripts/corpus/classify) keys on the gcc exit
# code, so a Z98 frontend `warning[3000]` (tolerated, non-fatal) is INVISIBLE to
# it. This script runs the compiler under test and counts the `warning[3000]`
# diagnostics it prints on stderr.
#
# usage: w3000_census.sh <zig1> [pins_file]
#
#   <zig1>       compiler under test (dump runs from the repo root with the
#                relative entry path, so this script cd's to the repo root).
#   [pins_file]  list of corpus-relative dirs whose contract is "NO
#                warning[3000]" (one per line, '#' comments allowed). Defaults to
#                repro/mi_matrix/w3000_fp_pins.list.
#                - With a pins file: scan ONLY those dirs (the Task 0m gate).
#                - With no pins file / an empty arg: scan the whole corpus.
#
# Output: "<dir>\t<count>" for every scanned dir with count > 0, then a summary.
# Exit status: 0 iff every scanned dir has count 0; 1 otherwise.
set -u

if [ "$#" -lt 1 ]; then
  echo "usage: w3000_census.sh <zig1> [pins_file]" >&2
  exit 2
fi

ZIG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

PINS="${2:-repro/mi_matrix/w3000_fp_pins.list}"
[ -f "$PINS" ] || PINS=""

WORK="$(mktemp -d /tmp/w3000_census.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

count_one() {
  local rel="$1" name entry od n
  rel="${rel%/}"
  [ -n "$rel" ] || return 0
  name="$(basename "$rel")"
  if [ -f "$rel/main.zig" ]; then entry="$rel/main.zig";
  elif [ -f "$rel/$name.zig" ]; then entry="$rel/$name.zig";
  else entry="$(find "$rel" -maxdepth 1 -type f -name '*.zig' | LC_ALL=C sort | head -1)"; fi
  [ -n "$entry" ] || return 0
  od="$WORK/$(echo "$rel" | tr '/' '_')"
  mkdir -p "$od"
  timeout 120 "$ZIG" -s0 --dump-c89 --output-dir "$od" "$entry" \
    >"$od/.dump.out" 2>"$od/.dump.err"
  n="$(grep -c 'warning\[3000\]' "$od/.dump.err" 2>/dev/null || true)"
  n="${n:-0}"
  total_warn=$((total_warn + n))
  if [ "$n" -gt 0 ]; then
    printf '%s\t%s\n' "$rel" "$n"
  fi
  if [ "$n" -ne 0 ]; then pin_fail=1; fi
}

total_dirs=0
total_warn=0
pin_fail=0
if [ -n "$PINS" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] || continue
    total_dirs=$((total_dirs + 1))
    count_one "$line"
  done < "$PINS"
else
  while IFS= read -r rel; do
    total_dirs=$((total_dirs + 1))
    count_one "$rel"
  done < <(bash scripts/corpus/list_corpus_dirs.sh)
fi

echo "=== w3000 census: dirs=$total_dirs total_warning3000=$total_warn pin_fail=$pin_fail ==="
exit "$pin_fail"
