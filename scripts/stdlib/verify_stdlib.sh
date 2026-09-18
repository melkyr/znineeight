#!/usr/bin/env bash
# verify_stdlib.sh — closeout entry for the std-lib runtime gate
# (Plan A hardening Task 2).
#
# Spec: docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md §2.
#
# usage: verify_stdlib.sh <zig1> [<dir>...]
#
#   <zig1>    seed-built `zig1_5_clean` (NEVER a zig0-built compiler).
#   <dir>...  optional explicit fixture dirs, forwarded verbatim to the
#             harness. With no dirs, the harness discovers every
#             `repro/mi_matrix/stdlib_*_xmod/` and every `stdlib_test/*/`.
#
# This is a thin closeout wrapper over scripts/stdlib/run_fixtures.sh: it runs
# the harness over the full discovered std fixture set (each fixture's stdout
# is diffed byte-for-byte to its committed `expected.txt`, and its exit code to
# its committed `expected.rc`, across 3 runs) and turns any harness failure
# into a nonzero closeout exit with a `STDLIB GATE FAILED` line.
#
# In discovery mode (no <dir> args) the harness additionally pins the discovered
# dir set to scripts/stdlib/expected_dirs.txt, so a dropped/renamed fixture
# FAILS the gate instead of silently shrinking coverage. Explicit <dir> runs
# skip the pin.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ZIG1="${1:-/tmp/fx_subfolder/zig1}"
shift || true

if [ ! -x "$ZIG1" ]; then
  echo "STDLIB GATE FAILED: zig1 '$ZIG1' is not executable"
  exit 1
fi

echo "== std-lib runtime gate =="
echo "   zig1: $ZIG1"

bash "$ROOT/scripts/stdlib/run_fixtures.sh" "$ZIG1" "$@"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "STDLIB GATE FAILED (run_fixtures rc=$rc)"
  exit 1
fi
echo "STDLIB GATE OK"
exit 0
