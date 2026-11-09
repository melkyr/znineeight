#!/usr/bin/env bash
# Expected-type sentinel contract probes.
#
# Usage:
#   Z145=/tmp/expected-type-i/v145/zig1-seed/zig1 \
#   Z146=/tmp/expected-type-i/v146/zig1-seed/zig1 \
#   ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig \
#   ./run_expected_type_contract.sh
#
# Z145 is the v145 seed archive binary (md5 cd8d283b...),
# Z146 is the v146 seed archive binary (md5 de5e99b6...).
# The Zig oracle is optional; when absent the zig_* columns are n/a.
# All compiler scratch stays under /tmp.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
Z145="${Z145:-/tmp/expected-type-i/v145/zig1-seed/zig1}"
Z146="${Z146:-/tmp/expected-type-i/v146/zig1-seed/zig1}"
ZIG="${ZIG:-/tmp/phase35-d15-i/zig-0.17.1/zig}"
SCRATCH="${SCRATCH:-/tmp/expected-type-contract-run}"
RESULTS="$HERE/results"
TSV="$RESULTS/results.tsv"
LOG="$RESULTS/run.log"

mkdir -p "$RESULTS"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/cwd" "$SCRATCH/zig-cache" "$SCRATCH/zig-global" "$SCRATCH/bin" "$SCRATCH/dump"

: > "$TSV"
: > "$LOG"
printf 'probe\tzig_rc\tzig_codes\tzig_diag\tv145_check_rc\tv145_codes\tv145_c\tv146_check_rc\tv146_codes\tv146_c\tv146_diag\n' >> "$TSV"

log() { printf '%s\n' "$*" >> "$LOG"; }

codes() {
    printf '%s\n' "$1" | grep -oE 'error\[[0-9]+\]' | sort -u | paste -sd, -
}

first_diag() {
    printf '%s\n' "$1" | grep -m1 -E 'error(\[[0-9]+\])?:|error:' || true
}

z98_check() {
    local z="$1" f="$2" err rc
    err=$(cd "$SCRATCH/cwd" && timeout 120 "$z" --check -ffast "$f" 2>&1)
    rc=$?
    printf '%s\t%s\t%s\n' "$rc" "$(codes "$err")" "$(first_diag "$err")"
}

z98_dump() {
    local z="$1" f="$2" tag="$3" outdir err rc c
    outdir="$SCRATCH/dump/$tag"
    rm -rf "$outdir"
    mkdir -p "$outdir"
    err=$(cd "$SCRATCH/cwd" && timeout 120 "$z" --dump-c89 -ffast --output-dir "$outdir" "$f" 2>&1)
    rc=$?
    c=$(find "$outdir" -maxdepth 1 -name '*.c' 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\t%s\t%s\n' "$rc" "$c" "$(first_diag "$err")"
}

zig_check() {
    local f="$1" err rc
    if [ ! -x "$ZIG" ]; then
        printf 'n/a\tn/a\tn/a\n'
        return
    fi
    err=$(timeout 120 "$ZIG" build-exe "$f" \
        --cache-dir "$SCRATCH/zig-cache" --global-cache-dir "$SCRATCH/zig-global" \
        -femit-bin="$SCRATCH/bin/$(basename "${f%.zig}")" 2>&1)
    rc=$?
    printf '%s\t%s\t%s\n' "$rc" "$(codes "$err")" "$(first_diag "$err")"
}

log "Z145=$Z145"
log "Z146=$Z146"
log "ZIG=$ZIG"

for f in "$HERE"/probes/*.zig; do
    rel="probes/$(basename "$f")"
    log ""
    log "=== $rel"
    zig=$(zig_check "$f")
    log "zig: $zig"
    v145c=$(z98_check "$Z145" "$f")
    log "v145 check: $v145c"
    v145d=$(z98_dump "$Z145" "$f" "v145-$(basename "${f%.zig}")")
    log "v145 dump: $v145d"
    v146c=$(z98_check "$Z146" "$f")
    log "v146 check: $v146c"
    v146d=$(z98_dump "$Z146" "$f" "v146-$(basename "${f%.zig}")")
    log "v146 dump: $v146d"

    v145c_rc=$(printf '%s' "$v145c" | cut -f1)
    v145c_codes=$(printf '%s' "$v145c" | cut -f2)
    v145d_rc=$(printf '%s' "$v145d" | cut -f1)
    v145d_c=$(printf '%s' "$v145d" | cut -f2)
    v146c_rc=$(printf '%s' "$v146c" | cut -f1)
    v146c_codes=$(printf '%s' "$v146c" | cut -f2)
    v146d_rc=$(printf '%s' "$v146d" | cut -f1)
    v146d_c=$(printf '%s' "$v146d" | cut -f2)
    v146c_diag=$(printf '%s' "$v146c" | cut -f3)

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rel" \
        "$(printf '%s' "$zig" | cut -f1)" \
        "$(printf '%s' "$zig" | cut -f2)" \
        "$(printf '%s' "$zig" | cut -f3)" \
        "$v145c_rc" "$v145c_codes" "$v145d_c" \
        "$v146c_rc" "$v146c_codes" "$v146d_c" \
        "$v146c_diag" >> "$TSV"
done

printf 'wrote %s\n' "$TSV"
