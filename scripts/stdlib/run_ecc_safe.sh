#!/usr/bin/env bash
# Default-mode (-fsafe) gate for the std_ecc fixtures.
#
# The shared run_fixtures.sh deliberately hardcodes -ffast. This gate emits the
# same fixtures WITHOUT -ffast, so the compiler's default -fsafe checks are in
# force, then builds via the emitted build_target.sh, runs 3x from a scratch
# CWD, and compares rc/stdout against the committed expected.txt/expected.rc.
#
# usage: run_ecc_safe.sh <zig1> [<dir>...]
#
# Default dirs are the two M2 Task 3 std_ecc fixtures. Any trap (SIGTRAP rc 133),
# nonzero rc, or stdout mismatch is a loud FAIL.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

export Z98_SEED=1

if [ "$#" -lt 1 ]; then
  echo "usage: run_ecc_safe.sh <zig1> [<dir>...]" >&2
  exit 2
fi

ZIG1="$1"; shift
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

if [ "$#" -gt 0 ]; then
  declare -a DIRS=()
  for d in "$@"; do DIRS+=("${d%/}"); done
else
  declare -a DIRS=(
    "repro/mi_matrix/stdlib_x25519_xmod"
    "repro/mi_matrix/stdlib_ecc_verify_xmod"
  )
fi

pass=0
fail=0
declare -a FAILED=()

for d in "${DIRS[@]}"; do
  entry="$d/main.zig"
  reason=""
  tmp=""

  if [ ! -f "$entry" ]; then
    reason="MISSING-ENTRY:$entry"
  elif [ ! -f "$d/expected.txt" ] || [ ! -f "$d/expected.rc" ]; then
    reason="MISSING-GOLDEN"
  else
    tmp="$(mktemp -d /tmp/stdlib_ecc_safe.XXXXXX)"

    # 1. Emit with the compiler default (NO -ffast => -fsafe).
    timeout 120 "$ZIG1" -o "$tmp" "$entry" >"$tmp/.emit.out" 2>"$tmp/.emit.err"
    emit_rc=$?
    if [ "$emit_rc" -ne 0 ]; then
      reason="EMIT-RC$emit_rc"
    elif ! ls "$tmp"/*.c >/dev/null 2>&1; then
      reason="NO-EMITTED-C"
    else
      # 2. Build exactly as the fixture harness does.
      ( cd "$tmp" && timeout 120 sh "$tmp/build_target.sh" linux "$tmp/prog" ) \
        >"$tmp/.build.out" 2>"$tmp/.build.err"
      build_rc=$?
      if [ "$build_rc" -ne 0 ] || [ ! -x "$tmp/prog" ]; then
        reason="BUILD-RC$build_rc"
      fi
    fi
  fi

  if [ -z "$reason" ]; then
    expected_rc="$(tr -d '[:space:]' < "$d/expected.rc")"
    mkdir -p "$tmp/cwd"
    run_ok=1
    run_i=0
    while [ "$run_i" -lt 3 ]; do
      run_i=$((run_i + 1))
      ( cd "$tmp/cwd" && timeout 120 "$tmp/prog" ) \
        >"$tmp/run$run_i.out" 2>"$tmp/run$run_i.err"
      rc=$?
      if [ "$rc" -ne "$expected_rc" ]; then
        reason="RUN${run_i}-RC$rc(EXPECTED$expected_rc)"
        run_ok=0
        break
      fi
      if ! cmp -s "$tmp/run$run_i.out" "$d/expected.txt"; then
        reason="RUN${run_i}-STDOUT-MISMATCH"
        run_ok=0
        break
      fi
    done

    if [ "$run_ok" -eq 1 ]; then
      md5="$(md5sum "$tmp/run1.out" | cut -d' ' -f1)"
      echo "PASS $d (md5=$md5 rc=$expected_rc)"
      pass=$((pass + 1))
      rm -rf "$tmp"
    fi
  fi

  if [ -n "$reason" ]; then
    fail=$((fail + 1))
    FAILED+=("$d:$reason")
    echo "FAIL $d ($reason)" >&2
    if [ -n "$tmp" ] && [ -d "$tmp" ]; then
      echo "    scratch: $tmp" >&2
      if [ -s "$tmp/.emit.err" ]; then
        echo "    emit stderr: $(head -n 1 "$tmp/.emit.err")" >&2
      fi
      if [ -s "$tmp/.build.err" ]; then
        echo "    build stderr: $(head -n 1 "$tmp/.build.err")" >&2
      fi
      if [ -s "$tmp/run1.err" ]; then
        echo "    run stderr: $(head -n 1 "$tmp/run1.err")" >&2
      fi
      if [ -f "$tmp/run1.out" ] && [ -f "$d/expected.txt" ]; then
        diff -u "$d/expected.txt" "$tmp/run1.out" 2>/dev/null | head -n 20 | sed 's/^/    /' >&2 || true
      fi
    fi
  fi
done

echo "----------------------------------------"
echo "run_ecc_safe: $pass PASS / $fail FAIL over ${#DIRS[@]} dirs"
if [ "$fail" -ne 0 ]; then
  printf 'failed: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
