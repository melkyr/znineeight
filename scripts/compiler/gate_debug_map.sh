#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_debug_map.sh [zig1] [baseline_zig1]
#
# Phase 2 P3-M1 debug-map gate. Proves:
#   1. `-d` emits the three sidecar files with the binding magics + version;
#   2. `.syms` carries `main` with a plausible source line;
#   3. three runs produce byte-identical maps (determinism);
#   4. no `-d` creates zero map files and its emitted `.c` set is byte-identical
#      to the pre-change baseline compiler's no-`-d` output;
#   5. `-d` without `--output-dir` exits rc=2 with no C and no map files;
#   6. the banner is `map: on` with `-d`, `map: off` without, and `--quiet`
#      suppresses it.
#
# `zig1` defaults to $ROOT/zig1. `baseline_zig1` defaults to the archived seed
# binary inside release/seed/zig1-seed.tgz (the pre-change compiler).

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_debug_map.sh [path/to/zig1] [path/to/baseline_zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_debug_map.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_debug_map] $*"; }
bad()  { echo "[gate_debug_map] FAIL: $*" >&2; fail=1; }

ENTRY="examples/z98/hello/main.zig"

# ---- baseline compiler (pre-change archived seed) ----
BASELINE="${2:-${BASELINE_ZIG1:-}}"
if [ -z "$BASELINE" ]; then
    SEED_TGZ="$ROOT/release/seed/zig1-seed.tgz"
    if [ -f "$SEED_TGZ" ]; then
        mkdir -p "$WORK/seed"
        tar xzf "$SEED_TGZ" -C "$WORK/seed"
        BASELINE="$WORK/seed/zig1-seed/zig1"
    fi
fi
if [ -z "$BASELINE" ] || [ ! -x "$BASELINE" ]; then
    bad "no executable baseline zig1 (pass arg 2 or set BASELINE_ZIG1)"
    exit 1
fi
note "zig1: $ZIG1"
note "baseline zig1: $BASELINE"

# ---- 1. map emission + banner ----
mkdir -p "$WORK/d1"
set +e
( cd "$ROOT" && timeout 120 "$ZIG1" -d -o "$WORK/d1" "$ENTRY" ) >"$WORK/d1.stdout" 2>"$WORK/d1.stderr"
RC=$?
set -e
[ "$RC" -eq 0 ] || bad "-d compile failed (rc=$RC)"
grep -q 'Z98 Compiler 2026 (map: on)' "$WORK/d1.stderr" || bad "missing 'map: on' banner"

SYMS_CNT=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.syms' | wc -l | tr -d ' ')
LINES_CNT=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.lines' | wc -l | tr -d ' ')
CNAMES_CNT=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.cnames' | wc -l | tr -d ' ')
[ "$SYMS_CNT" -eq 1 ] || bad "expected one .z98dbg.syms, got $SYMS_CNT"
[ "$LINES_CNT" -eq 1 ] || bad "expected one .z98dbg.lines, got $LINES_CNT"
[ "$CNAMES_CNT" -eq 1 ] || bad "expected one .z98dbg.cnames, got $CNAMES_CNT"
if [ "$SYMS_CNT" -ne 1 ] || [ "$LINES_CNT" -ne 1 ] || [ "$CNAMES_CNT" -ne 1 ]; then
    echo "DEBUG_MAP GATE FAILED" >&2
    exit 1
fi

SYMS=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.syms')
LINES=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.lines')
CNAMES=$(find "$WORK/d1" -maxdepth 1 -name '*.z98dbg.cnames')

check_magic() {
    local file="$1" want="$2" got
    got=$(od -An -tc -N8 "$file" | tr -d ' \n')
    [ "$got" = "$want" ] || bad "$(basename "$file") magic '$got' want '$want'"
    got=$(od -An -tu1 -j8 -N4 "$file" | tr -s ' ' | sed 's/^ //;s/ $//')
    [ "$got" = "1 0 0 0" ] || bad "$(basename "$file") version bytes '$got' want '1 0 0 0'"
}
check_magic "$SYMS" "Z98DBGsy"
check_magic "$LINES" "Z98DBGln"
check_magic "$CNAMES" "Z98DBGcn"

# ---- 2. `.syms` contains main with a plausible line ----
od -An -v -tu1 "$SYMS" | awk '
{
    for (i = 1; i <= NF; i++) b[++n] = $i
}
END {
    if (n < 20) { print "TOO_SHORT"; exit 2 }
    rc = b[13] + 256*b[14] + 65536*b[15] + 16777216*b[16]
    off = 21
    found = 0
    for (r = 0; r < rc; r++) {
        kind = b[off]; off += 1
        line = b[off] + 256*b[off+1] + 65536*b[off+2] + 16777216*b[off+3]; off += 4
        nl = b[off] + 256*b[off+1]; off += 2
        name = ""
        for (i = 0; i < nl; i++) { name = name sprintf("%c", b[off]); off += 1 }
        ml = b[off] + 256*b[off+1]; off += 2
        off += ml
        fl = b[off] + 256*b[off+1]; off += 2
        off += fl
        if (name == "main") {
            if (kind == 0 && line >= 1 && line <= 10000) { found = 1 }
            else { print "BAD_MAIN", kind, line; exit 3 }
        }
    }
    if (!found) { print "NO_MAIN"; exit 4 }
    print "MAIN_OK"
}' >"$WORK/syms.check" 2>&1 || true
if ! grep -q '^MAIN_OK$' "$WORK/syms.check"; then
    bad ".syms main row check failed: $(tr '\n' ' ' <"$WORK/syms.check")"
else
    note "ok .syms main row"
fi

# ---- 2b. hoisted declarations are mapped (spec §7.3) ----
# `fibonacci` forces hoisted `zT_*` temporaries. Every contiguous hoisted
# declaration line at the top of an emitted function must be covered by a
# `.lines` run whose src_line is a real line of the probe source.
HOIST_ENTRY="examples/z98/fibonacci/main.zig"
HOIST_SRC="$ROOT/$HOIST_ENTRY"
mkdir -p "$WORK/hoist"
( cd "$ROOT" && timeout 120 "$ZIG1" -q -d -o "$WORK/hoist" "$HOIST_ENTRY" ) \
    >"$WORK/hoist.stdout" 2>"$WORK/hoist.stderr" || bad "hoisted probe -d compile failed"
HLINES=$(find "$WORK/hoist" -maxdepth 1 -name '*.z98dbg.lines' | head -1)
HC=$(grep -l 'int zT_1;' "$WORK/hoist"/*.c 2>/dev/null | head -1)
if [ -z "$HLINES" ] || [ -z "$HC" ]; then
    bad "hoisted probe did not emit a map file and/or a hoisted-decl C file"
else
    od -An -v -tu1 "$HLINES" | awk '
    { for (i = 1; i <= NF; i++) b[++n] = $i }
    END {
        off = 21
        while (off < n) {
            sl = b[off] + 256*b[off+1]; off += 2; sf = ""
            for (i = 0; i < sl; i++) { sf = sf sprintf("%c", b[off]); off += 1 }
            ol = b[off] + 256*b[off+1]; off += 2; of = ""
            for (i = 0; i < ol; i++) { of = of sprintf("%c", b[off]); off += 1 }
            rn = b[off] + 256*b[off+1] + 65536*b[off+2] + 16777216*b[off+3]; off += 4
            for (r = 0; r < rn; r++) {
                src = b[off] + 256*b[off+1] + 65536*b[off+2] + 16777216*b[off+3]
                os = b[off+4] + 256*b[off+5] + 65536*b[off+6] + 16777216*b[off+7]
                oc = b[off+8] + 256*b[off+9] + 65536*b[off+10] + 16777216*b[off+11]
                off += 12
                print sf "\t" src "\t" of "\t" os "\t" oc
            }
        }
    }' >"$WORK/hoist.rows"
    awk '
    { line[NR] = $0 }
    END {
        infn = 0
        for (ln = 1; ln <= NR; ln++) {
            if (line[ln] ~ /\{[[:space:]]*$/) {
                infn = 1
            } else if (infn == 1) {
                if (line[ln] ~ /zT_[0-9]+/ && line[ln] ~ /;[[:space:]]*$/ &&
                    (line[ln] !~ /=/ || line[ln] ~ /= 0;[[:space:]]*$/ || line[ln] ~ /= \{0\};[[:space:]]*$/)) {
                    print ln
                } else {
                    infn = 0
                }
            }
        }
    }' "$HC" >"$WORK/hoist.decls"
    HOIST_OUT="$(basename "$HC")"
    SRC_LINES=$(awk 'END { print NR }' "$HOIST_SRC")
    DHIT=0
    DMISS=0
    while IFS= read -r dline; do
        [ -n "$dline" ] || continue
        DHIT=$((DHIT + 1))
        awk -F'\t' -v d="$dline" -v of="$HOIST_OUT" -v lim="$SRC_LINES" '
            $3 == of && d >= $4 && d < $4 + $5 && $2 >= 1 && $2 <= lim { ok = 1 }
            END { exit !ok }' "$WORK/hoist.rows" || {
            bad "hoisted declaration line $HOIST_OUT:$dline is not mapped to a plausible src_line"
            DMISS=$((DMISS + 1))
        }
    done <"$WORK/hoist.decls"
    if [ "$DHIT" -eq 0 ]; then
        bad "hoisted probe emitted no hoisted declaration lines to check"
    elif [ "$DMISS" -eq 0 ]; then
        note "ok hoisted declarations mapped ($DHIT lines)"
    fi
fi

# ---- 3. determinism (3x) ----
for i in 2 3; do
    mkdir -p "$WORK/d$i"
    ( cd "$ROOT" && timeout 120 "$ZIG1" -d -o "$WORK/d$i" "$ENTRY" ) \
        >"$WORK/d$i.stdout" 2>"$WORK/d$i.stderr" || bad "determinism run $i failed"
    for ext in syms lines cnames; do
        cmp -s "$WORK/d1"/*.z98dbg.$ext "$WORK/d$i"/*.z98dbg.$ext \
            || bad "run $i .z98dbg.$ext differs from run 1"
    done
done
note "determinism: 3x map byte-identical"

# ---- 4. no-`-d` purity + baseline .c identity ----
mkdir -p "$WORK/base" "$WORK/off"
( cd "$ROOT" && timeout 120 "$BASELINE" -o "$WORK/base" "$ENTRY" ) \
    >"$WORK/base.stdout" 2>"$WORK/base.stderr" || bad "baseline no-'-d' compile failed"
( cd "$ROOT" && timeout 120 "$ZIG1" -o "$WORK/off" "$ENTRY" ) \
    >"$WORK/off.stdout" 2>"$WORK/off.stderr" || bad "no-'-d' compile failed"
grep -q 'Z98 Compiler 2026 (map: off)' "$WORK/off.stderr" || bad "missing 'map: off' banner"

OFF_MAPS=$(find "$WORK/off" -maxdepth 1 -name '*.z98dbg.*' | wc -l | tr -d ' ')
[ "$OFF_MAPS" -eq 0 ] || bad "no-'-d' run created $OFF_MAPS map file(s)"

( cd "$WORK/base" && find . -maxdepth 1 -name '*.c' -printf '%f\n' | LC_ALL=C sort ) >"$WORK/base.c.list"
( cd "$WORK/off" && find . -maxdepth 1 -name '*.c' -printf '%f\n' | LC_ALL=C sort ) >"$WORK/off.c.list"
if ! cmp -s "$WORK/base.c.list" "$WORK/off.c.list"; then
    bad "emitted .c file set differs from baseline"
else
    while IFS= read -r f; do
        cmp -s "$WORK/base/$f" "$WORK/off/$f" || bad "emitted .c differs from baseline: $f"
    done <"$WORK/base.c.list"
fi
if [ "$fail" -eq 0 ]; then note "purity: no-'-d' .c set byte-identical to pre-change baseline"; fi

# ---- 5. -d without --output-dir ----
set +e
( cd "$WORK" && timeout 120 "$ZIG1" --dump-c89 -d "$ROOT/$ENTRY" ) >"$WORK/noout.c" 2>"$WORK/noout.err"
RC=$?
set -e
[ "$RC" -eq 2 ] || bad "-d without --output-dir rc=$RC want 2"
grep -q '^error: --debug/-d requires --output-dir$' "$WORK/noout.err" \
    || bad "missing exact '-d requires --output-dir' error line"
[ ! -s "$WORK/noout.c" ] || bad "-d without --output-dir emitted C to stdout"
NOOUT_MAPS=$(find "$WORK" -maxdepth 1 -name '*.z98dbg.*' | wc -l | tr -d ' ')
[ "$NOOUT_MAPS" -eq 0 ] || bad "-d without --output-dir created $NOOUT_MAPS map file(s)"

# ---- 6. --quiet suppresses only the banner ----
mkdir -p "$WORK/q1" "$WORK/q2"
( cd "$ROOT" && timeout 120 "$ZIG1" -q -d -o "$WORK/q1" "$ENTRY" ) >"$WORK/q1.out" 2>"$WORK/q1.err" \
    || bad "quiet -d compile failed"
( cd "$ROOT" && timeout 120 "$ZIG1" -q -o "$WORK/q2" "$ENTRY" ) >"$WORK/q2.out" 2>"$WORK/q2.err" \
    || bad "quiet no-'-d' compile failed"
grep -q 'Z98 Compiler 2026' "$WORK/q1.err" && bad "--quiet did not suppress banner (-d)"
grep -q 'Z98 Compiler 2026' "$WORK/q2.err" && bad "--quiet did not suppress banner (no -d)"
[ "$(find "$WORK/q1" -maxdepth 1 -name '*.z98dbg.syms' | wc -l | tr -d ' ')" -eq 1 ] \
    || bad "--quiet -d did not emit the map"
[ "$(find "$WORK/q2" -maxdepth 1 -name '*.z98dbg.*' | wc -l | tr -d ' ')" -eq 0 ] \
    || bad "--quiet no-'-d' emitted map files"
note "banner on/off + --quiet suppression ok"

if [ "$fail" -eq 0 ]; then
    echo "DEBUG_MAP GATE OK"
    exit 0
fi
echo "DEBUG_MAP GATE FAILED" >&2
exit 1
