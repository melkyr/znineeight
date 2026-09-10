#!/usr/bin/env bash
# Canonical corpus-universe listing (SPECFIX).
#
# Universe rule:
#   - every immediate subdir of repro/mi_matrix/
#   - every immediate subdir of repro/ EXCEPT the containers mi_matrix and slice_matrix
#   - every immediate subdir of examples/z98/
# A candidate dir is kept only if it has a resolvable entry, resolved as:
#   <dir>/main.zig, else <dir>/<basename>.zig, else the first *.zig directly under <dir>.
# Prints sorted repo-relative dir paths, one per line, with a trailing slash.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

emit_dir() {
  local rel="$1" name entry
  name="$(basename "$rel")"
  if [ -f "$rel/main.zig" ]; then
    entry="$rel/main.zig"
  elif [ -f "$rel/$name.zig" ]; then
    entry="$rel/$name.zig"
  else
    local -a zig_files=()
    mapfile -t zig_files < <(find "$rel" -maxdepth 1 -type f -name '*.zig' | LC_ALL=C sort)
    entry="${zig_files[0]:-}"
  fi
  if [ -n "$entry" ]; then
    printf '%s/\n' "$rel"
  fi
}

{
  # A. every immediate subdir of repro/mi_matrix/
  for d in repro/mi_matrix/*/; do
    [ -d "$d" ] || continue
    emit_dir "${d%/}"
  done

  # B. every immediate subdir of repro/ except the containers mi_matrix & slice_matrix
  for d in repro/*/; do
    [ -d "$d" ] || continue
    rel="${d%/}"
    case "$rel" in
      repro/mi_matrix | repro/slice_matrix) continue ;;
    esac
    emit_dir "$rel"
  done

  # C. every immediate subdir of examples/z98/
  for d in examples/z98/*/; do
    [ -d "$d" ] || continue
    emit_dir "${d%/}"
  done
} | LC_ALL=C sort
