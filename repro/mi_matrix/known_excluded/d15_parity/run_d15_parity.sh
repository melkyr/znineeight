#!/usr/bin/env bash
# Three-way D15 parity harness.
#
# Usage:
#   ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig \
#   PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean \
#   CUR=/tmp/phase35-d15-i/current-build/zig1_5_clean \
#   ./run_d15_parity.sh
#
# Writes results/results.tsv and results/run.log. All compiler scratch
# (Zig caches, Z98 .c dumps, Z98 .zig1_*.tmp files) stays under /tmp.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ZIG="${ZIG:-/tmp/phase35-d15-i/zig-0.17.1/zig}"
PRE="${PRE:-/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean}"
CUR="${CUR:-/tmp/phase35-d15-i/current-build/zig1_5_clean}"
SCRATCH="${SCRATCH:-/tmp/phase35-d15-i/run}"
RESULTS="$HERE/results"
TSV="$RESULTS/results.tsv"
LOG="$RESULTS/run.log"

mkdir -p "$RESULTS"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/cwd" "$SCRATCH/zig-cache" "$SCRATCH/zig-global" "$SCRATCH/bin" "$SCRATCH/dump"

: > "$TSV"
: > "$LOG"
printf 'probe\tzig_rc\tzig_diag\tzig_errors\tpre_check_rc\tpre_diag\tpre_c\tpre_dump_rc\tcur_check_rc\tcur_diag\tcur_c\tcur_dump_rc\n' >> "$TSV"

log() { printf '%s\n' "$*" >> "$LOG"; }

codes() {
    # $1 = captured text
    printf '%s\n' "$1" | grep -oE 'error\[[0-9]+\]' | sort -u | paste -sd, -
}

first_diag() {
    printf '%s\n' "$1" | grep -m1 -E 'error(\[[0-9]+\])?:|error:' | sed 's/\t/ /g'
}

# z98_check <compiler> <file> -> echoes "rc<TAB>captured"
z98_check() {
    local z="$1" f="$2" err rc
    err=$(cd "$SCRATCH/cwd" && timeout 120 "$z" --check -ffast "$f" 2>&1)
    rc=$?
    printf '%s\t%s\n' "$rc" "$err"
}

# z98_dump <compiler> <file> <tag> -> echoes "rc<TAB>c_count<TAB>captured"
z98_dump() {
    local z="$1" f="$2" tag="$3" outdir err rc c
    outdir="$SCRATCH/dump/$tag"
    rm -rf "$outdir"
    mkdir -p "$outdir"
    err=$(cd "$SCRATCH/cwd" && timeout 120 "$z" --dump-c89 -ffast --output-dir "$outdir" "$f" 2>&1)
    rc=$?
    c=$(find "$outdir" -maxdepth 1 -name '*.c' 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\t%s\t%s\n' "$rc" "$c" "$err"
}

while IFS= read -r f; do
    rel="${f#"$HERE"/}"
    log "=================================================================="
    log "PROBE $rel"
    log "------------------------------------------------------------------"
    log "command: cd $SCRATCH/cwd && $ZIG build-exe $f --cache-dir $SCRATCH/zig-cache --global-cache-dir $SCRATCH/zig-global -femit-bin=$SCRATCH/bin/out"
    zerr=$(cd "$SCRATCH/cwd" && "$ZIG" build-exe "$f" --cache-dir "$SCRATCH/zig-cache" --global-cache-dir "$SCRATCH/zig-global" -femit-bin="$SCRATCH/bin/out" 2>&1)
    zrc=$?
    zcodes=$(codes "$zerr")
    zfirst=$(first_diag "$zerr")
    zcount=$(printf '%s\n' "$zerr" | grep -cE 'error(\[[0-9]+\])?:' || true)
    log "zig rc=$zrc errors=$zcount codes=${zcodes:--}"
    printf '%s\n' "$zerr" | sed -n '1,40p' >> "$LOG"

    pre_check=$(z98_check "$PRE" "$f"); pre_crc=${pre_check%%$'\t'*}; pre_cerr=${pre_check#*$'\t'}
    pre_dump=$(z98_dump "$PRE" "$f" "pre.$(printf '%s' "$rel" | tr '/.' '__')"); pre_dump_first=$(printf '%s\n' "$pre_dump" | head -1); pre_drc=$(printf '%s' "$pre_dump_first" | cut -f1); pre_c=$(printf '%s' "$pre_dump_first" | cut -f2); pre_derr=$(printf '%s' "$pre_dump" | cut -f3-)
    cur_check=$(z98_check "$CUR" "$f"); cur_crc=${cur_check%%$'\t'*}; cur_cerr=${cur_check#*$'\t'}
    cur_dump=$(z98_dump "$CUR" "$f" "cur.$(printf '%s' "$rel" | tr '/.' '__')"); cur_dump_first=$(printf '%s\n' "$cur_dump" | head -1); cur_drc=$(printf '%s' "$cur_dump_first" | cut -f1); cur_c=$(printf '%s' "$cur_dump_first" | cut -f2); cur_derr=$(printf '%s' "$cur_dump" | cut -f3-)

    pcodes=$(codes "$pre_cerr"); ccodes=$(codes "$cur_cerr")
    log "PRE  check rc=$pre_crc codes=${pcodes:--}   dump rc=$pre_drc c=$pre_c"
    printf '%s\n' "$pre_cerr" | sed -n '1,40p' >> "$LOG"
    log "CUR  check rc=$cur_crc codes=${ccodes:--}   dump rc=$cur_drc c=$cur_c"
    printf '%s\n' "$cur_cerr" | sed -n '1,40p' >> "$LOG"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rel" "$zrc" "$zfirst" "$zcount" "$pre_crc" "$pcodes" "$pre_c" "$pre_drc" "$cur_crc" "$ccodes" "$cur_c" "$cur_drc" >> "$TSV"
done < <(find "$HERE/matrix" "$HERE/corpus_adapted" "$HERE/corpus_raw" "$HERE/neg" "$HERE/selectors" -type f -name '*.zig' | sort)
