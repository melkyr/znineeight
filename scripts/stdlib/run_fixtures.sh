#!/usr/bin/env bash
# Runtime gate for the std-lib fixtures (Plan A/B hardening).
#
# Spec: docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md §2.
#
# usage: run_fixtures.sh [--capture] <zig1> [<dir>...]
#
#   --capture  re-capture each fixture's committed golden from the observed run:
#             writes <dir>/expected.txt + <dir>/expected.rc and prints what it
#             wrote. A fixture whose program rc is nonzero AND not already
#             declared in an existing <dir>/expected.rc is REFUSED (a crashing
#             fixture is not silently frozen). ALWAYS review the observed output
#             against the fixture's documented GREEN contract (its main.zig
#             header) before committing a capture.
#   <zig1>    seed-built `zig1_5_clean` (its sibling lib/ resolves the std
#             modules). NEVER pass a zig0-built compiler.
#   <dir>...  optional explicit fixture dirs (repo-relative or absolute). With
#             no dirs, discovery is every `repro/mi_matrix/stdlib_*/` and
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
# Discovery is PINNED to scripts/stdlib/expected_dirs.txt: in discovery mode the
# discovered dir set must equal the pinned baseline exactly (a dropped, renamed,
# or added fixture FAILS the gate), so coverage cannot silently shrink. Update
# the pin intentionally when a band adds/removes fixtures. Explicit `<dir>`
# arguments skip the discovery pin (targeted runs), but an independent guard
# ALWAYS fails if any `repro/mi_matrix/stdlib_*/` or `stdlib_test/*/` dir exists
# that is not in the pin (a std-looking dir cannot silently escape the gate).
#
# Optional `<dir>/ports.txt` (one TCP port per line; `#` comments allowed)
# declares ports the fixture binds. If a LISTEN socket already exists on a
# declared port before the run, the fixture FAILs as `PORT-IN-USE:<port>` with
# a clear message instead of a confusing stdout mismatch.
#
# A missing golden is a FAIL (no silent skips). Prints a per-dir PASS/FAIL
# summary and exits nonzero if any fixture fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT" || exit 2

CAPTURE=0
if [ "${1:-}" = "--capture" ]; then CAPTURE=1; shift; fi

if [ "$#" -lt 1 ]; then
  echo "usage: run_fixtures.sh [--capture] <zig1> [<dir>...]" >&2
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
    | grep -E '^repro/mi_matrix/stdlib_[^/]*/$|^stdlib_test/[^/]*/$'
}

# port_listening <port> — true if a TCP LISTEN socket exists on <port>.
port_listening() {
  local hex
  hex="$(printf '%04X' "$1")"
  awk -v want="$hex" 'NR>1 { split($2,a,":"); if (a[2] == want && $4 == "0A") found=1 }
       END { exit !found }' /proc/net/tcp 2>/dev/null && return 0
  awk -v want="$hex" 'NR>1 { split($2,a,":"); if (a[2] == want && $4 == "0A") found=1 }
       END { exit !found }' /proc/net/tcp6 2>/dev/null && return 0
  return 1
}

# check_ports <dir> — 0 if every port in <dir>/ports.txt is clear; else sets
# BAD_PORT and returns 1.
BAD_PORT=""
check_ports() {
  local pf="$1/ports.txt" line p
  [ -f "$pf" ] || return 0
  while IFS= read -r line; do
    p="${line%%#*}"
    p="$(printf '%s' "$p" | tr -d '[:space:]')"
    [ -n "$p" ] || continue
    if port_listening "$p"; then BAD_PORT="$p"; return 1; fi
  done < "$pf"
  return 0
}

# --- fixture list ---
declare -a DIRS=()
DISCOVERY_MODE=0
if [ "$#" -gt 0 ]; then
  for d in "$@"; do DIRS+=("${d%/}"); done
else
  DISCOVERY_MODE=1
  while IFS= read -r rel; do
    [ -n "$rel" ] && DIRS+=("${rel%/}")
  done < <(discover_dirs)
fi

[ "${#DIRS[@]}" -gt 0 ] || { echo "error: no fixture dirs found" >&2; exit 2; }

# --- discovery pin ---
EXPECTED_DIRS_FILE="$SCRIPT_DIR/expected_dirs.txt"
if [ ! -f "$EXPECTED_DIRS_FILE" ]; then
  echo "FAIL discovery-pin (missing $EXPECTED_DIRS_FILE)" >&2
  exit 1
fi
expected_list="$(grep -vE '^[[:space:]]*(#|$)' "$EXPECTED_DIRS_FILE" | LC_ALL=C sort)"

# Independent guard (both modes): a std-looking dir that exists on disk but is
# not in the pin must fail loudly, even if it has no resolvable entry (so it
# would otherwise be invisible to discovery and silently escape the gate).
unpinned=""
for d in repro/mi_matrix/stdlib_*/ stdlib_test/*/; do
  [ -d "$d" ] || continue
  rel="${d%/}"
  if ! printf '%s\n' "$expected_list" | grep -qxF "$rel"; then
    unpinned="$rel"
    break
  fi
done
if [ -n "$unpinned" ]; then
  echo "FAIL unpinned-stdlib-dir ($unpinned exists but is not in $EXPECTED_DIRS_FILE)" >&2
  exit 1
fi

# discovery pin (skipped for explicit <dir> runs)
if [ "$DISCOVERY_MODE" = 1 ]; then
  actual_list="$(printf '%s\n' "${DIRS[@]}" | LC_ALL=C sort)"
  if [ "$actual_list" != "$expected_list" ]; then
    echo "FAIL discovery-pin (discovered std fixture set differs from $EXPECTED_DIRS_FILE)" >&2
    diff <(printf '%s\n' "$expected_list") <(printf '%s\n' "$actual_list") >&2 || true
    echo "discovered=${#DIRS[@]} pinned=$(printf '%s\n' "$expected_list" | grep -c .)" >&2
    exit 1
  fi
fi

pass=0; fail=0
declare -a FAILED=()

for d in "${DIRS[@]}"; do
  reason=""
  entry="$(resolve_entry "$d")"
  if [ -z "$entry" ]; then
    reason="NOENTRY"
  elif [ "$CAPTURE" = 0 ] && { [ ! -f "$d/expected.txt" ] || [ ! -f "$d/expected.rc" ]; }; then
    reason="MISSING-GOLDEN"
  elif ! check_ports "$d"; then
    reason="PORT-IN-USE:$BAD_PORT"
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
          elif [ "$CAPTURE" = 1 ]; then
            # --capture: write the observed golden. Refuse a nonzero rc that is
            # not already declared in an existing expected.rc — a crashing
            # fixture must not be silently frozen (a probe declares its rc first).
            want_rc=""
            [ -f "$d/expected.rc" ] && want_rc="$(tr -d '[:space:]' < "$d/expected.rc")"
            if [ "$rc1" != 0 ] && [ "$rc1" != "$want_rc" ]; then
              reason="CAPTURE-REFUSED-RC$rc1(undeclared)"
            else
              cp "$tmp/.run1.out" "$d/expected.txt"
              printf '%s\n' "$rc1" > "$d/expected.rc"
              reason="CAPTURED"
            fi
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
    if [ "$reason" = "CAPTURED" ]; then
      pass=$((pass + 1))
      echo "CAPTURED $d (stdout $(wc -c < "$d/expected.txt" | tr -d '[:space:]') bytes, rc $(tr -d '[:space:]' < "$d/expected.rc"))"
    elif [ -z "$reason" ]; then
      pass=$((pass + 1))
      echo "PASS $d"
    else
      fail=$((fail + 1))
      FAILED+=("$d")
      echo "FAIL $d ($reason)"
      if [ -s "$tmp/.dumperr" ]; then
        echo "    dump stderr: $(tail -n 1 "$tmp/.dumperr")"
      fi
      case "$reason" in
        GCCFAIL)
          [ -s "$tmp/.gccerr" ] && echo "    gcc stderr: $(head -n 1 "$tmp/.gccerr")"
          ;;
        BUILD-RC*)
          [ -s "$tmp/.builderr" ] && echo "    build stderr: $(head -n 1 "$tmp/.builderr")"
          ;;
      esac
    fi
    rm -rf "$tmp"
  fi
  case "$reason" in
    NOENTRY|MISSING-GOLDEN|PORT-IN-USE:*)
      fail=$((fail + 1))
      FAILED+=("$d")
      echo "FAIL $d ($reason)"
      ;;
  esac
done

echo "----------------------------------------"
[ "$CAPTURE" = 1 ] && echo "run_fixtures: --capture mode (goldens written; review before committing)"
echo "run_fixtures: $pass PASS / $fail FAIL over ${#DIRS[@]} dirs"
if [ "$fail" -ne 0 ]; then
  printf 'failed: %s\n' "${FAILED[*]}"
  exit 1
fi
exit 0
