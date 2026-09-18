#!/usr/bin/env bash
# Runtime gate for the std-lib fixtures (Plan A hardening Task 1).
#
# Spec: docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md §2.
#
# usage: run_fixtures.sh <zig1> [<dir>...]
#
#   <zig1>    seed-built `zig1_5_clean` (its sibling lib/ resolves the std
#             modules). NEVER pass a zig0-built compiler.
#   <dir>...  optional explicit fixture dirs (repo-relative or absolute). With
#             no dirs, discovery is every `repro/mi_matrix/stdlib_*_xmod/` and
#             every `stdlib_test/*/` in the corpus universe (the same
#             `emit_dir` entry-resolution rule as scripts/corpus/list_corpus_dirs.sh).
#
# Per fixture:
#   1. `zig1 -ffast -o <tmp> <entry>` (standard per-program emission).
#   2. compile every emitted `.c` with the binding gcc flag-set.
#   3. `sh <tmp>/build_target.sh linux <tmp>/prog`.
#   4. run under `timeout 120`, 3x; stdout must be byte-identical across runs.
#   5. diff stdout bytes to `<dir>/expected.txt` and the exit code to
#      `<dir>/expected.rc`.
#
# A missing golden is a FAIL (no silent skips). Prints a per-dir PASS/FAIL
# summary and exits nonzero if any fixture fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

if [ "$#" -lt 1 ]; then
  echo "usage: run_fixtures.sh <zig1> [<dir>...]" >&2
  exit 2
fi

ZIG1="$1"; shift
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

GCC_FLAGS=(-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
           -Wno-implicit-function-declaration)

# emit_dir entry rule (mirrors scripts/corpus/list_corpus_dirs.sh).
resolve_entry() {
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
  printf '%s' "$entry"
}

discover_dirs() {
  bash "$ROOT/scripts/corpus/list_corpus_dirs.sh" \
    | grep -E '^repro/mi_matrix/stdlib_[^/]*_xmod/$|^stdlib_test/[^/]*/$'
}

# --- fixture list ---
declare -a DIRS=()
if [ "$#" -gt 0 ]; then
  for d in "$@"; do DIRS+=("${d%/}"); done
else
  while IFS= read -r rel; do
    [ -n "$rel" ] && DIRS+=("${rel%/}")
  done < <(discover_dirs)
fi

[ "${#DIRS[@]}" -gt 0 ] || { echo "error: no fixture dirs found" >&2; exit 2; }

pass=0; fail=0
declare -a FAILED=()

for d in "${DIRS[@]}"; do
  reason=""
  entry="$(resolve_entry "$d")"
  if [ -z "$entry" ]; then
    reason="NOENTRY"
  elif [ ! -f "$d/expected.txt" ] || [ ! -f "$d/expected.rc" ]; then
    reason="MISSING-GOLDEN"
  else
    tmp="$(mktemp -d /tmp/stdlib_run_fixtures.XXXXXX)"
    # 1. emit
    timeout 120 "$ZIG1" -ffast -o "$tmp" "$entry" >"$tmp/.dumpout" 2>"$tmp/.dumperr"
    drc=$?
    if [ "$drc" -ne 0 ]; then
      reason="DUMP-RC$drc"
    elif ! ls "$tmp"/*.c >/dev/null 2>&1; then
      reason="NO-EMITTED-C"
    else
      # 2. compile every emitted .c with the binding flag-set
      gfail=0
      for f in "$tmp"/*.c; do
        ( cd "$tmp" && gcc "${GCC_FLAGS[@]}" -I . -c "$(basename "$f")" -o /dev/null ) \
          >"$tmp/.gccout" 2>"$tmp/.gccerr" || { gfail=1; break; }
      done
      if [ "$gfail" -ne 0 ]; then
        reason="GCCFAIL"
      else
        # 3. link via the emitted companion script
        ( cd "$tmp" && sh "$tmp/build_target.sh" linux "$tmp/prog" ) \
          >"$tmp/.buildout" 2>"$tmp/.builderr"
        brc=$?
        if [ "$brc" -ne 0 ] || [ ! -x "$tmp/prog" ]; then
          reason="BUILD-RC$brc"
        else
          # 4. run 3x under timeout 120, from a scratch CWD
          run_cwd="$(mktemp -d /tmp/stdlib_run_cwd.XXXXXX)"
          : >"$tmp/.run1.out"; : >"$tmp/.run2.out"; : >"$tmp/.run3.out"
          rc1=0; rc2=0; rc3=0
          ( cd "$run_cwd" && timeout 120 "$tmp/prog" ) >"$tmp/.run1.out" 2>"$tmp/.run1.err"; rc1=$?
          ( cd "$run_cwd" && timeout 120 "$tmp/prog" ) >"$tmp/.run2.out" 2>"$tmp/.run2.err"; rc2=$?
          ( cd "$run_cwd" && timeout 120 "$tmp/prog" ) >"$tmp/.run3.out" 2>"$tmp/.run3.err"; rc3=$?
          if ! cmp -s "$tmp/.run1.out" "$tmp/.run2.out" || ! cmp -s "$tmp/.run1.out" "$tmp/.run3.out"; then
            reason="NONDETERMINISTIC"
          elif ! cmp -s "$tmp/.run1.out" "$d/expected.txt"; then
            reason="STDOUT-MISMATCH"
          else
            want_rc="$(tr -d '[:space:]' < "$d/expected.rc")"
            if [ "$rc1" != "$want_rc" ]; then
              reason="RC-MISMATCH(got $rc1 want $want_rc)"
            fi
          fi
          rm -rf "$run_cwd"
        fi
      fi
    fi
    if [ -z "$reason" ]; then
      pass=$((pass + 1))
      echo "PASS $d"
    else
      fail=$((fail + 1))
      FAILED+=("$d")
      echo "FAIL $d ($reason)"
      if [ -s "$tmp/.dumperr" ]; then
        echo "    dump stderr: $(tail -n 1 "$tmp/.dumperr")"
      fi
    fi
    rm -rf "$tmp"
  fi
  if [ -n "$reason" ] && { [ "$reason" = "NOENTRY" ] || [ "$reason" = "MISSING-GOLDEN" ]; }; then
    fail=$((fail + 1))
    FAILED+=("$d")
    echo "FAIL $d ($reason)"
  fi
done

echo "----------------------------------------"
echo "run_fixtures: $pass PASS / $fail FAIL over ${#DIRS[@]} dirs"
if [ "$fail" -ne 0 ]; then
  printf 'failed: %s\n' "${FAILED[*]}"
  exit 1
fi
exit 0
