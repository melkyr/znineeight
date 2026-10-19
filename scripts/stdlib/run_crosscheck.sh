#!/usr/bin/env bash
# Cross-check gate for std modules: Z98 == C89 reference == committed .expected.
#
# Spec: docs/superpowers/specs/2026-10-19-z98-std-algorithms-design.md §5.
#
# usage: run_crosscheck.sh <zig1> [<module>...]
#
#   <zig1>    seed-built `zig1_5_clean` (its sibling lib/ resolves std modules).
#   <module>  optional module names (e.g. `smoke`). With no modules, discovery
#             is every `scripts/stdlib/ref/<module>/` directory.
#
# Per module:
#   1. build the `stdlib_<module>_cross_xmod` (or legacy `stdlib_cross_<module>_
#      xmod`) driver once: `zig1 -ffast -o <tmp>` -> gcc -> build_target.sh.
#   2. build `scripts/stdlib/ref/<module>/ref.c` once: `gcc -m32 -std=c89 -O0`.
#   3. for every `scripts/stdlib/vectors/<module>/*.in`, feed the bytes to both
#      the driver (`--crosscheck`) and the reference, and compare stdout
#      three ways: Z98 == ref, Z98 == committed .expected, ref == committed .expected.
#      Both processes must exit 0. Text mismatches print a diff; binary
#      mismatches print `cmp -l`.
#
# Z98_SEED is exported fixed on every invocation (harness convention; std code
# itself never reads the environment).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

export Z98_SEED=1

if [ "$#" -lt 1 ]; then
  echo "usage: run_crosscheck.sh <zig1> [<module>...]" >&2
  exit 2
fi

ZIG1="$1"; shift
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

GCC_FLAGS=(-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
           -Wno-implicit-function-declaration)

declare -a MODULES=()
if [ "$#" -gt 0 ]; then
  for m in "$@"; do MODULES+=("${m%/}"); done
else
  mapfile -t MODULES < <(find "$SCRIPT_DIR/ref" -mindepth 1 -maxdepth 1 -type d \
                           -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
fi

if [ "${#MODULES[@]}" -eq 0 ]; then
  echo "error: no crosscheck modules (no scripts/stdlib/ref/<module>/ dirs)" >&2
  exit 2
fi

is_binary() {
  LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1" && return 1
  return 0
}

show_mismatch() {
  local label="$1" a="$2" b="$3"
  echo "    $label:"
  if is_binary "$a" || is_binary "$b"; then
    cmp -l "$a" "$b" 2>/dev/null | head -n 10 | sed 's/^/      /' || true
  else
    diff -u "$a" "$b" 2>/dev/null | head -n 40 | sed 's/^/      /' || true
  fi
}

driver_dir_for() {
  local module="$1"
  local short="${module#std_}"
  if [ -d "$ROOT/repro/mi_matrix/stdlib_${module}_cross_xmod" ]; then
    printf '%s' "$ROOT/repro/mi_matrix/stdlib_${module}_cross_xmod"
  elif [ -d "$ROOT/repro/mi_matrix/stdlib_cross_${module}_xmod" ]; then
    printf '%s' "$ROOT/repro/mi_matrix/stdlib_cross_${module}_xmod"
  elif [ "$short" != "$module" ] && [ -d "$ROOT/repro/mi_matrix/stdlib_${short}_cross_xmod" ]; then
    printf '%s' "$ROOT/repro/mi_matrix/stdlib_${short}_cross_xmod"
  fi
}

pass=0; fail=0
declare -a FAILED=()

for module in "${MODULES[@]}"; do
  ref_dir="$SCRIPT_DIR/ref/$module"
  vec_dir="$SCRIPT_DIR/vectors/$module"
  driver_dir="$(driver_dir_for "$module")"
  reason=""

  if [ ! -f "$ref_dir/ref.c" ]; then
    reason="MISSING-REF"
  elif [ ! -d "$vec_dir" ]; then
    reason="MISSING-VECTORS"
  elif [ -z "$driver_dir" ]; then
    reason="MISSING-DRIVER"
  elif [ ! -f "$driver_dir/main.zig" ]; then
    reason="MISSING-DRIVER-ENTRY"
  fi

  if [ -n "$reason" ]; then
    fail=$((fail + 1))
    FAILED+=("$module:$reason")
    echo "FAIL $module ($reason)"
    continue
  fi

  tmp="$(mktemp -d /tmp/stdlib_crosscheck.XXXXXX)"

  timeout 120 "$ZIG1" -ffast -o "$tmp" "$driver_dir/main.zig" >"$tmp/.dumpout" 2>"$tmp/.dumperr"
  drc=$?
  if [ "$drc" -ne 0 ]; then
    reason="DUMP-RC$drc"
  elif ! ls "$tmp"/*.c >/dev/null 2>&1; then
    reason="NO-EMITTED-C"
  else
    gfail=0
    for f in "$tmp"/*.c; do
      ( cd "$tmp" && gcc "${GCC_FLAGS[@]}" -I . -c "$(basename "$f")" -o /dev/null ) \
        >"$tmp/.gccout" 2>"$tmp/.gccerr" || { gfail=1; break; }
    done
    if [ "$gfail" -ne 0 ]; then
      reason="GCCFAIL"
    else
      ( cd "$tmp" && sh "$tmp/build_target.sh" linux "$tmp/prog" ) \
        >"$tmp/.buildout" 2>"$tmp/.builderr"
      brc=$?
      if [ "$brc" -ne 0 ] || [ ! -x "$tmp/prog" ]; then
        reason="BUILD-RC$brc"
      fi
    fi
  fi

  if [ -z "$reason" ]; then
    gcc -m32 -std=c89 -O0 "$ref_dir/ref.c" -o "$tmp/ref" >"$tmp/.refout" 2>"$tmp/.referr"
    rrc_cc=$?
    if [ "$rrc_cc" -ne 0 ] || [ ! -x "$tmp/ref" ]; then
      reason="REF-BUILD-RC$rrc_cc"
    fi
  fi

  if [ -z "$reason" ]; then
    declare -a ins=()
    mapfile -t ins < <(find "$vec_dir" -maxdepth 1 -type f -name '*.in' | LC_ALL=C sort)
    if [ "${#ins[@]}" -eq 0 ]; then
      reason="NO-VECTORS"
    else
      for in_file in "${ins[@]}"; do
        name="$(basename "$in_file" .in)"
        out_file="$vec_dir/$name.expected"
        if [ ! -f "$out_file" ]; then
          reason="MISSING-EXPECTED:$name"
          break
        fi

        timeout 120 "$tmp/prog" --crosscheck <"$in_file" >"$tmp/z.out" 2>"$tmp/z.err"
        zrc=$?
        timeout 120 "$tmp/ref" <"$in_file" >"$tmp/r.out" 2>"$tmp/r.err"
        rrc=$?

        if [ "$zrc" -ne 0 ]; then
          reason="Z98-RC$zrc:$name"
          echo "    z98 stderr: $(head -n 1 "$tmp/z.err")"
          break
        elif [ "$rrc" -ne 0 ]; then
          reason="REF-RC$rrc:$name"
          echo "    ref stderr: $(head -n 1 "$tmp/r.err")"
          break
        elif ! cmp -s "$tmp/z.out" "$tmp/r.out"; then
          reason="Z98-NE-REF:$name"
          show_mismatch "z98 vs ref" "$tmp/z.out" "$tmp/r.out"
          break
        elif ! cmp -s "$tmp/z.out" "$out_file"; then
          reason="Z98-NE-EXPECTED:$name"
          show_mismatch "z98 vs committed .expected" "$tmp/z.out" "$out_file"
          break
        elif ! cmp -s "$tmp/r.out" "$out_file"; then
          reason="REF-NE-EXPECTED:$name"
          show_mismatch "ref vs committed .expected" "$tmp/r.out" "$out_file"
          break
        fi
      done
    fi
  fi

  if [ -z "$reason" ]; then
    pass=$((pass + 1))
    echo "PASS $module (${#ins[@]} vectors)"
  else
    fail=$((fail + 1))
    FAILED+=("$module:$reason")
    echo "FAIL $module ($reason)"
    case "$reason" in
      DUMP-RC*)
        [ -s "$tmp/.dumperr" ] && echo "    dump stderr: $(tail -n 1 "$tmp/.dumperr")"
        ;;
      GCCFAIL)
        [ -s "$tmp/.gccerr" ] && echo "    gcc stderr: $(head -n 1 "$tmp/.gccerr")"
        ;;
      BUILD-RC*)
        [ -s "$tmp/.builderr" ] && echo "    build stderr: $(head -n 1 "$tmp/.builderr")"
        ;;
      REF-BUILD-RC*)
        [ -s "$tmp/.referr" ] && echo "    ref stderr: $(head -n 1 "$tmp/.referr")"
        ;;
    esac
  fi

  rm -rf "$tmp"
done

echo "----------------------------------------"
echo "run_crosscheck: $pass PASS / $fail FAIL over ${#MODULES[@]} modules"
if [ "$fail" -ne 0 ]; then
  printf 'failed: %s\n' "${FAILED[*]}"
  exit 1
fi
exit 0
