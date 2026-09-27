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
#   crash   compiler must die from a signal (SIGSEGV, rc 139)       D01
#   reject  compiler must reject now (rc != 0, no C emitted)        D04, D11
#   accept  compiler must WRONGLY accept now (rc == 0); the defect
#           is the missing rejection                                 D03, D10, D12
#   gccfail compile is accepted (rc 0), gcc must reject the C       D05
#   wrong   build+run succeed, stdout must differ from expected.txt D02, D06, D08
#   runok   compiler must accept now (rc 0), gcc must build, the program must
#           run rc 0 and match the case's expected.txt                  D05
#   fixedreject (FD1) compiler must reject with the exact census in the
#           case's expected_error.txt (`<code> <count>`), no signal,
#           no `.c` emitted                                          D07, D09, D12, S01
#
# FA-a conversion (2026-09-26): D2 (enum range labels) and D3 (mandatory `else`)
# are FIXED on the current compiler. Under the existing kinds this shows up
# naturally as `ok`: D02 (`wrong`) now matches expected.txt, and D03 (`accept`)
# now rejects. Both print `ok` on a post-FA-a compiler; the remaining cases
# still follow the table above.
#
# FG conversion (2026-09-26): D1 (defer-queue corruption) is FIXED on the
# current compiler. D01 (`crash`) now compiles rc 0; because the case ships an
# expected.txt, the crash branch additionally builds + runs main and goldens
# stdout/rc before printing `ok` — a compile-only green cannot mask a wrong or
# crashing run. The remaining cases still follow the table above.
#
# FD1 conversion (2026-09-26): D7 and the S01 print-container cluster are
# FIXED on the current compiler. Both now use the `fixedreject` kind: main.zig
# must reject with the code/count pinned in the case's expected_error.txt,
# emit no `.c`, and never signal (a wrong-code reject or a crash prints RED).
# The historical seed-v88 observations stay in the case NOTES.md.
#
# FE conversion (2026-09-26): D8 (error-set catch capture) and D11 (qualified
# prong captures + the bundled unused-capture SIGSEGV) are FIXED. D08 (`wrong`)
# now builds+runs and matches expected.txt (`rc=0 ok`); D11 (`reject`) now
# compiles rc 0 (`rc=0 ok` at the compile gate; its f32 shapes stay
# gcc-blocked by D6/FF). Extra D11 sibling entries
# (red_enum_capture_{used,unused}.zig) document the enum-capture shapes and
# are exercised outside run_all.sh; the historical seed-v88 observations stay
# in the case NOTES.md.
#
# FF conversion (2026-09-26): D6 (f32 tagged-union payload) and D9 (union
# `@offsetOf`/`@bitOffsetOf`) are FIXED. D06 (`wrong`) now builds+runs and
# matches expected.txt (`f=2`; the sibling shape `red_sibling.zig` is exercised
# outside run_all.sh). D09 (`fixedreject`) now rejects with exactly one
# level-0 `error[3072]` (`expected struct type, found 'Raw'`), rc 2 / 0 `.c`,
# no signal — the former `error[3043]` ICE (rc 3) is gone. The historical
# seed-v88 observations stay in the case NOTES.md.
#
# FC conversion (2026-09-26): D5 (slice -> `[*]T`) and D12 (const-discarding
# coercions) are FIXED. D05 uses the new `runok` kind: main.zig must compile,
# build, run rc 0 and print the expected.txt golden (`mp[1]=20`), proving the
# `.ptr` extraction aliases the slice storage. D12 uses `fixedreject`: main.zig
# must reject with exactly one level-0 `error[3000]` (`cannot implicitly
# discard 'const' qualifier`), rc 2 / 0 `.c`, no signal — the former
# warning-only/silent acceptance is gone. Extra D12 sibling entries
# (red_assign.zig, red_modvar.zig) and the D05 red_*/xmod/control entries are
# exercised outside run_all.sh; the historical seed-v88 observations stay in
# the case NOTES.md.
#
# FB conversion (2026-09-26): D4 (tuple type `struct { T1, T2 }`, `.0`/`._0`
# access and `t[0]` indexing) is FIXED. D04 uses the `runok` kind: main.zig must
# compile, build, run rc 0 and print the expected.txt golden (`p=.{ 3, 4 }`).
# The sibling red_return_type / red_dot0 / red_underscore / red_index entries
# and the controls are exercised outside run_all.sh; the historical seed-v88
# observations stay in the case NOTES.md.
#
# FH conversion (2026-09-27): D10 (single-item-pointer indexing) is FIXED as a
# clean reject. D10 uses the `fixedreject` kind with a multi-code census in
# expected_error.txt (`3066 6` index forms + `3067 5` slice forms + `3000 10`
# void-decl cascades/controls), so the runner now requires every listed code
# count to match. The sibling `reject_slice_02/10/open.zig` +
# `reject_star_paren.zig` rejects, the accepted `control_slice_legal.zig`
# (new `*[0]T`/`*[1]T` result types) and `control_deref.zig` are exercised
# outside run_all.sh; the historical seed-v88 observations stay in the case
# NOTES.md.
#
# FX2 conversion (2026-09-27): the D1 analyzer-traversal extras (defers inside
# switch prongs and bare blocks) are FIXED on the current compiler. D01 stays
# kind `crash` (which now goldens main.zig stdout/rc) and gains the
# `red_switch_block.zig` sibling (plain + switch-prong + bare-block defers:
# compile/build/run rc 0 under FG+FX2, rc 139 under an FX2-only no-FG compiler;
# exercised outside run_all.sh like the other D01 siblings). The historical
# seed-v88 observations stay in the case NOTES.md.

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
        D01_*) kind=crash ;;
        D04_*) kind=runok ;;
        D11_*) kind=reject ;;
        D03_*) kind=accept ;;
        D07_*|D09_*|D10_*|D12_*|S01_*) kind=fixedreject ;;
        D05_*) kind=runok ;;
        D02_*|D06_*|D08_*) kind=wrong ;;
        *)           kind=reject ;;
    esac
    printf '%s\n' "$kind" > "$out/kind.txt"

    timeout 120 "$SEED" -o "$out" "$dir/main.zig" > "$out/compile.log" 2>&1
    cc=$?
    if [ "$kind" = crash ] || [ "$kind" = reject ]; then
        if [ "$cc" -ne 0 ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$cc"
        elif [ "$kind" = crash ] && [ -f "$dir/expected.txt" ] && [ -f "$out/build_target.sh" ]; then
            (cd "$out" && timeout 120 sh build_target.sh linux main) > "$out/build.log" 2>&1
            bc=$?
            if [ "$bc" -ne 0 ]; then
                printf '%s: rc=%s RED\n' "$case_name" "$bc"
            else
                timeout 120 "$out/main" > "$out/run.stdout" 2>&1
                rc=$?
                if [ "$rc" -eq 0 ] && diff "$dir/expected.txt" "$out/run.stdout" > "$out/diff.txt" 2>&1; then
                    printf '%s: rc=%s ok\n' "$case_name" "$rc"
                else
                    printf '%s: rc=%s RED\n' "$case_name" "$rc"
                fi
            fi
        else
            printf '%s: rc=0 ok\n' "$case_name"
        fi
        continue
    fi

    if [ "$kind" = fixedreject ]; then
        # expected_error.txt carries one `<code> <count>` line per rejected
        # code. The earlier conversions pin a single line; D10 (FH) pins the
        # 3066/3067 census plus the 3000 void-decl cascades and controls.
        has_c=0
        set -- "$out"/*.c
        [ -e "$1" ] && has_c=1
        fr_ok=1
        fr_seen=0
        if [ -f "$dir/expected_error.txt" ]; then
            while read -r want_code want_n; do
                [ -n "$want_code" ] || continue
                fr_seen=1
                got_n=$(grep -c "error\[$want_code\]" "$out/compile.log" 2>/dev/null)
                if [ "$got_n" -ne "$want_n" ]; then fr_ok=0; fi
            done < "$dir/expected_error.txt"
        else
            fr_ok=0
        fi
        if [ "$cc" -ge 128 ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$cc"
        elif [ "$cc" -ne 0 ] && [ "$has_c" -eq 0 ] && [ "$fr_seen" -eq 1 ] && [ "$fr_ok" -eq 1 ]; then
            printf '%s: rc=%s ok\n' "$case_name" "$cc"
        else
            printf '%s: rc=%s RED\n' "$case_name" "$cc"
        fi
        continue
    fi

    if [ "$kind" = runok ]; then
        if [ "$cc" -ne 0 ] || [ ! -f "$out/build_target.sh" ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$cc"
            continue
        fi
        (cd "$out" && timeout 120 sh build_target.sh linux main) > "$out/build.log" 2>&1
        bc=$?
        if [ "$bc" -ne 0 ]; then
            printf '%s: rc=%s RED\n' "$case_name" "$bc"
            continue
        fi
        timeout 120 "$out/main" > "$out/run.stdout" 2>&1
        rc=$?
        if [ "$rc" -eq 0 ] && [ -f "$dir/expected.txt" ] && diff "$dir/expected.txt" "$out/run.stdout" > "$out/diff.txt" 2>&1; then
            printf '%s: rc=%s ok\n' "$case_name" "$rc"
        else
            printf '%s: rc=%s RED\n' "$case_name" "$rc"
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
