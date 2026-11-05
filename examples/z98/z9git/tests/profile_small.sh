#!/bin/sh
# profile_small.sh -- Task 8p measure-only harness for z9git on a ~1 MB repo.
#
# Env:
#   ZIG        seed-built zig1_5_clean (default /tmp/t8p_build/zig1_5_clean)
#   OUT        scratch dir (default /tmp/z9git_profile_small)
#   URL        remote repo (default jwiegley/git-from-the-bottom-up)
#   NET        1 to fetch/mirror over HTTPS, 0 to reuse an existing mirror
#   RUNS       timed repetitions per configuration (default 3)
#   ARENA_MB   app arena size (default 32)
#   DEEP       1 to run callgrind/gprof/memcheck when installed (default 1)
#
# The harness never edits z9git sources: profile variants are built by putting
# a gcc wrapper that appends -g / -g -pg on PATH while running the emitted
# build_target.sh.  The emitted logic is unchanged.
#
# POSIX sh + coreutils.  Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APP_DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/t8p_build/zig1_5_clean}"
OUT="${OUT:-/tmp/z9git_profile_small}"
URL="${URL:-https://github.com/jwiegley/git-from-the-bottom-up.git}"
API_URL="${API_URL:-https://api.github.com/repos/jwiegley/git-from-the-bottom-up}"
ARCHIVE_URL="${ARCHIVE_URL:-https://codeload.github.com/jwiegley/git-from-the-bottom-up/tar.gz/refs/heads/master}"
NET="${NET:-1}"
RUNS="${RUNS:-3}"
ARENA_MB="${ARENA_MB:-32}"
DEEP="${DEEP:-1}"

TIME_BIN=""
[ -x /usr/bin/time ] && TIME_BIN=/usr/bin/time
HAVE_CALLGRIND=0
HAVE_GPROF=0
HAVE_MEMCHECK=0
HAVE_STRACE=0
HAVE_PERF=0
if command -v valgrind >/dev/null 2>&1 && command -v callgrind_annotate >/dev/null 2>&1; then
    HAVE_CALLGRIND=1
fi
command -v gprof >/dev/null 2>&1 && HAVE_GPROF=1
command -v valgrind >/dev/null 2>&1 && HAVE_MEMCHECK=1
command -v strace >/dev/null 2>&1 && HAVE_STRACE=1
command -v perf >/dev/null 2>&1 && HAVE_PERF=1

die() { echo "error: $*" >&2; exit 1; }
[ -x "$ZIG" ] || die "compiler not found: $ZIG (set ZIG)"
for tool in git gcc awk find; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done
[ -n "$TIME_BIN" ] || die "/usr/bin/time is required for wall+RSS"
[ "$NET" = "1" ] && { command -v curl >/dev/null 2>&1 || die "curl is required (NET=1)"; }

if [ "$NET" = "1" ] || [ ! -d "$OUT/work/mirror" ]; then
    rm -rf "$OUT"
fi
mkdir -p "$OUT/bin" "$OUT/emit" "$OUT/logs" "$OUT/times" "$OUT/work" "$OUT/prof"
: > "$OUT/numbers.tsv"

sumrx() {
    if [ -r /proc/net/dev ]; then
        awk -F'[: ]+' 'NR > 2 && $2 != "lo" { s += $3 } END { print s + 0 }' /proc/net/dev
    else
        echo 0
    fi
}

run_timed() {
    rt_name="$1"
    shift
    rt_time="$OUT/times/$rt_name.time"
    rt_rx0=$(sumrx)
    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v -o "$rt_time" "$@" >"$OUT/logs/$rt_name.log" 2>"$OUT/logs/$rt_name.err"
    else
        "$@" >"$OUT/logs/$rt_name.log" 2>"$OUT/logs/$rt_name.err"
    fi
    rt_rc=$?
    rt_rx1=$(sumrx)
    rt_elapsed=$(awk '/Elapsed \(wall clock\)/ { print $NF }' "$rt_time" 2>/dev/null)
    rt_rss=$(awk '/Maximum resident set size/ { print $6 }' "$rt_time" 2>/dev/null)
    printf '%s\trc=%s\telapsed=%s\trss_kb=%s\trx_bytes=%s\n' \
        "$rt_name" "$rt_rc" "${rt_elapsed:-?}" "${rt_rss:-?}" "$((rt_rx1 - rt_rx0))" \
        | tee -a "$OUT/numbers.tsv"
    return $rt_rc
}

echo "== repo metadata =="
if [ "$NET" = "1" ]; then
    curl -sS --max-time 30 "$API_URL" >"$OUT/work/api.json"
    size_kb=$(grep -o '"size": *[0-9]*' "$OUT/work/api.json" | grep -o '[0-9]*' | head -1)
    echo "url=$URL"
    echo "api_url=$API_URL"
    echo "api_size_kb=${size_kb:-?}"
    echo "archive_url=$ARCHIVE_URL"
else
    echo "url=$URL (NET=0; size/metadata from API skipped)"
fi

MIRROR="$OUT/work/mirror"
if [ "$NET" = "1" ]; then
    echo "== system HTTPS baseline =="
    rm -rf "$OUT/work/sys_https"
    run_timed sys_https_mirror git clone --progress "$URL" "$MIRROR" || true
    run_timed sys_https_clone git clone --progress "$URL" "$OUT/work/sys_https" || true
    run_timed sys_lsremote_https git ls-remote "$URL" || true
    run_timed sys_curl_archive curl -sSL -o "$OUT/work/archive.tar.gz" \
        -w 'http_code=%{http_code} size_download=%{size_download} time_total=%{time_total}\n' \
        "$ARCHIVE_URL" || true
    [ -f "$OUT/work/archive.tar.gz" ] && ls -l "$OUT/work/archive.tar.gz" >"$OUT/work/archive.size"
fi
[ -d "$MIRROR" ] || die "no local mirror at $MIRROR (run with NET=1 first)"

echo "== system local baseline =="
rm -rf "$OUT/work/sys_local"
run_timed sys_local_clone git clone "$MIRROR" "$OUT/work/sys_local" || true
run_timed sys_lsremote_local git ls-remote "$MIRROR" || true
git -C "$MIRROR" count-objects -vH >"$OUT/work/mirror.count" 2>/dev/null || true
du -sh "$MIRROR" >"$OUT/work/mirror.size" 2>/dev/null || true

echo "== build app (-ffast emit; generated build_target.sh) =="
"$ZIG" -ffast -o "$OUT/emit" "$APP_DIR/main.zig" >"$OUT/logs/emit.log" 2>&1 \
    || die "zig -ffast emit failed (see $OUT/logs/emit.log)"
sh "$OUT/emit/build_target.sh" linux "$OUT/bin/prog" >"$OUT/logs/build.log" 2>&1 \
    || die "generated build_target.sh failed (see $OUT/logs/build.log)"
cp "$APP_DIR/../demo/tls_demo/ca_store.bin" "$OUT/bin/ca_store.bin" 2>/dev/null || true

build_variant() {
    bv_name="$1"
    bv_flags="$2"
    bv_dir="$OUT/emit_$bv_name"
    bv_wrap="$OUT/ccwrap_$bv_name"
    rm -rf "$bv_dir" "$bv_wrap"
    cp -a "$OUT/emit" "$bv_dir"
    mkdir -p "$bv_wrap"
    bv_gcc=$(command -v gcc)
    printf '#!/bin/sh\nexec %s %s "$@"\n' "$bv_gcc" "$bv_flags" >"$bv_wrap/gcc"
    chmod +x "$bv_wrap/gcc"
    PATH="$bv_wrap:$PATH" sh "$bv_dir/build_target.sh" linux "$OUT/bin/prog_$bv_name" \
        >"$OUT/logs/build_$bv_name.log" 2>&1
}

echo "== app timed runs =="
i=1
while [ "$i" -le "$RUNS" ]; do
    rm -rf "$OUT/work/app_local_$i" "$OUT/work/app_local16_$i"
    run_timed "app_local_$i" "$OUT/bin/prog" clone "$MIRROR" "$OUT/work/app_local_$i" --arena-mb "$ARENA_MB" || true
    run_timed "app_local16_$i" "$OUT/bin/prog" clone "$MIRROR" "$OUT/work/app_local16_$i" --arena-mb 16 || true
    if [ "$NET" = "1" ]; then
        rm -rf "$OUT/work/app_https_$i" "$OUT/work/app_https16_$i"
        run_timed "app_https_$i" "$OUT/bin/prog" clone "$URL" "$OUT/work/app_https_$i" --arena-mb "$ARENA_MB" || true
        run_timed "app_https16_$i" "$OUT/bin/prog" clone "$URL" "$OUT/work/app_https16_$i" --arena-mb 16 || true
    fi
    i=$((i + 1))
done

if [ "$HAVE_STRACE" = "1" ]; then
    echo "== strace -c (app local) =="
    strace -c -o "$OUT/prof/strace_local.txt" "$OUT/bin/prog" clone "$MIRROR" "$OUT/work/strace_local" --arena-mb "$ARENA_MB" \
        >/dev/null 2>&1 || true
fi
if [ "$HAVE_PERF" = "1" ]; then
    echo "== perf stat (app local) =="
    perf stat -o "$OUT/prof/perf_local.txt" "$OUT/bin/prog" clone "$MIRROR" "$OUT/work/perf_local" --arena-mb "$ARENA_MB" \
        >/dev/null 2>&1 || true
fi

if [ "$DEEP" = "1" ]; then
    if [ "$HAVE_CALLGRIND" = "1" ]; then
        echo "== callgrind (-g variant) =="
        build_variant g "-g" || true
        if [ -x "$OUT/bin/prog_g" ]; then
            rm -rf "$OUT/work/cg_local" "$OUT/work/cg_https"
            valgrind --tool=callgrind --callgrind-out-file="$OUT/prof/callgrind.local.out" \
                "$OUT/bin/prog_g" clone "$MIRROR" "$OUT/work/cg_local" --arena-mb "$ARENA_MB" \
                >"$OUT/logs/cg_local.log" 2>"$OUT/logs/cg_local.err" || true
            if [ "$NET" = "1" ]; then
                valgrind --tool=callgrind --callgrind-out-file="$OUT/prof/callgrind.https.out" \
                    "$OUT/bin/prog_g" clone "$URL" "$OUT/work/cg_https" --arena-mb "$ARENA_MB" \
                    >"$OUT/logs/cg_https.log" 2>"$OUT/logs/cg_https.err" || true
            fi
            for m in local https; do
                [ -f "$OUT/prof/callgrind.$m.out" ] || continue
                callgrind_annotate --inclusive=no --auto=no --threshold=99 --show=Ir \
                    "$OUT/prof/callgrind.$m.out" >"$OUT/prof/top_self.$m.txt" 2>/dev/null || true
                callgrind_annotate --inclusive=yes --auto=no --threshold=99 --show=Ir \
                    "$OUT/prof/callgrind.$m.out" >"$OUT/prof/top_incl.$m.txt" 2>/dev/null || true
            done
        fi
    fi
    if [ "$HAVE_GPROF" = "1" ]; then
        echo "== gprof (-g -pg variant) =="
        build_variant pg "-g -pg" || true
        if [ -x "$OUT/bin/prog_pg" ]; then
            rm -rf "$OUT/work/gp_local" "$OUT/work/gp_https" "$OUT/prof/gmon"*
            GMON_OUT_PREFIX="$OUT/prof/gmon_local" "$OUT/bin/prog_pg" clone "$MIRROR" \
                "$OUT/work/gp_local" --arena-mb "$ARENA_MB" >/dev/null 2>&1 || true
            if [ "$NET" = "1" ]; then
                GMON_OUT_PREFIX="$OUT/prof/gmon_https" "$OUT/bin/prog_pg" clone "$URL" \
                    "$OUT/work/gp_https" --arena-mb "$ARENA_MB" >/dev/null 2>&1 || true
            fi
            for m in local https; do
                gm=$(find "$OUT/prof" -maxdepth 1 -name "gmon_$m.*" -print -quit 2>/dev/null)
                [ -n "$gm" ] || continue
                gprof -b "$OUT/bin/prog_pg" "$gm" >"$OUT/prof/gprof.$m.txt" 2>/dev/null || true
            done
        fi
    fi
    if [ "$HAVE_MEMCHECK" = "1" ]; then
        echo "== valgrind memcheck =="
        rm -rf "$OUT/work/mc_local" "$OUT/work/mc_https"
        valgrind --tool=memcheck --error-exitcode=99 --leak-check=summary \
            "$OUT/bin/prog" clone "$MIRROR" "$OUT/work/mc_local" --arena-mb "$ARENA_MB" \
            >"$OUT/logs/mc_local.log" 2>"$OUT/logs/mc_local.err" || true
        if [ "$NET" = "1" ]; then
            valgrind --tool=memcheck --error-exitcode=99 --leak-check=summary \
                "$OUT/bin/prog" clone "$URL" "$OUT/work/mc_https" --arena-mb "$ARENA_MB" \
                >"$OUT/logs/mc_https.log" 2>"$OUT/logs/mc_https.err" || true
        fi
        grep -E 'ERROR SUMMARY' "$OUT/logs/mc_local.err" "$OUT/logs/mc_https.err" 2>/dev/null \
            >"$OUT/prof/memcheck.txt" || true
    fi
fi

echo
echo "== numbers =="
cat "$OUT/numbers.tsv"
echo
echo "artifacts: $OUT (numbers.tsv, logs/, times/, prof/)"
