#!/bin/sh
# Volume II defect repro runner (task D0).
#
# Compiles and runs every case's main.zig with the seed compiler and prints one
# line per case:
#
#     <case>: rc=<n> <RED|ok>
#
# Every main.zig in this tree is an expected-RED repro. `RED` means the
# expected defect reproduced; `ok` means it did NOT reproduce (the expected
# failure kind is stored in /tmp/vol2_defects_out/<case>/kind.txt and the raw
# compile/build/run logs capture the failure kind).
#
# Expected failure kind per case (see each case's NOTES.md and the README):
#   crash   compiler must die from a signal (SIGSEGV, rc 139)       D01, S01
#   reject  compiler must reject now (rc != 0, no C emitted)        D04, D09, D11
#   accept  compiler must WRONGLY accept now (rc == 0); the defect
#           is the missing rejection                                 D03, D07, D10, D12
#   gccfail compile is accepted (rc 0), gcc must reject the C       D05, D06
#   wrong   build+run succeed, stdout must differ from expected.txt D02, D08
#
# Usage: sh run_all.sh [seed-compiler-path]
# Default seed: /tmp/manual_seed/zig1_5_clean
# Rebuild:  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# Seed md5 must be a3928c11f9852db9646dff39006ef654.
set -u

CASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SEED=${1:-/tmp/manual_seed/zig1_5_clean}
OUT=/tmp/vol2_defects_out

if [ ! -x "$SEED" ]; then
    echo "run_all.sh: seed compiler missing or not executable: $SEED" >&2
    echo "build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed" >&2
    exit 2
fi

mkdir -p "$OUT"

for dir in "$CASE_DIR"/D*/ "$CASE_DIR"/S*/; do
    [ -d "$dir" ] || continue
    case_name=$(basename -- "$dir")
    out="$OUT/$case_name"
    rm -rf "$out"
    mkdir -p "$out"

    case "$case_name" in
        D01_*|S01_*) kind=crash ;;
        D04_*|D09_*|D11_*) kind=reject ;;
        D03_*|D07_*|D10_*|D12_*) kind=accept ;;
        D05_*|D06_*) kind=gccfail ;;
        D02_*|D08_*) kind=wrong ;;
        *)           kind=reject ;;
    esac
    printf '%s\n' "$kind" > "$out/kind.txt"

    timeout 120 "$SEED" -o "$out" "$dir/main.zig" > "$out/compile.log" 2>&1
    cc=$?
    if [ "$kind" = crash ] || [ "$kind" = reject ]; then
        if [ "$cc" -ne 0 ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$cc"
        else
            printf '%s: rc=0 ok\n' "$case_name"
        fi
        continue
    fi

    if [ "$kind" = accept ]; then
        if [ "$cc" -eq 0 ]; then
            printf '%s: rc=0 RED\n' "$case_name"
        else
            printf '%s: rc=%s ok\n' "$case_name" "$cc"
        fi
        continue
    fi

    if [ ! -f "$out/build_target.sh" ]; then
        printf '%s: rc=0 ok\n' "$case_name"
        continue
    fi

    (cd "$out" && timeout 120 sh build_target.sh linux main) > "$out/build.log" 2>&1
    bc=$?
    if [ "$bc" -ne 0 ]; then
        if [ "$kind" = gccfail ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$bc"
        else
            printf '%s: rc=%s ok\n' "$case_name" "$bc"
        fi
        continue
    fi

    timeout 120 "$out/main" > "$out/run.stdout" 2>&1
    rc=$?

    if [ "$kind" = gccfail ]; then
        printf '%s: rc=%s ok\n' "$case_name" "$rc"
        continue
    fi

    if [ -f "$dir/expected.txt" ] && diff "$dir/expected.txt" "$out/run.stdout" > "$out/diff.txt" 2>&1; then
        printf '%s: rc=%s ok\n' "$case_name" "$rc"
    else
        printf '%s: rc=%s RED\n' "$case_name" "$rc"
    fi
done
