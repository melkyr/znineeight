#!/bin/sh
# tier_perf.sh — z9gb Phase 4 performance evidence (P3/P4/P5).
#
# Measures the named homebrew ROM 2048.gb over 600 frames on four paths:
#   host_headless: --headless --no-dynarec --frames 600 --audio (authoritative)
#   host_headless: --headless --dynarec --frames 600 --audio (evidence)
#   wine_windowed: --windowed --no-dynarec --frames 600 --audio (evidence)
#   wine_windowed: --windowed --dynarec --frames 600 --audio (evidence)
#
# The host built output is compiled at -O2 (the harness compiles the emitted C
# with the optimized flags) so the number measures emulator throughput, not the
# generated -O0 scaffold.
#
# Host headless --no-dynarec is the authoritative pass/fail gate
# (>= Z9GB_PERF_MIN_FPS). The dynarec is Win32/x86 only; on *nix `--dynarec`
# truthfully reports `dynarec=disabled reason=unsupported-host` and runs the
# interpreter. The Wine path delegates the build/import/QPC launcher to
# tier_win32.sh --perf, then times explicit --no-dynarec and --dynarec runs.
# A successful Wine run counts as evidence/pass regardless of fps; a genuine
# Wine SKIP (77) stays a SKIP, and a Wine build/run/framebuffer/QPC failure
# still fails. Wine numbers are Wine evidence only; they are never Win98
# hardware evidence.
#
# The 1 MiB code cache is a separate VirtualAlloc/mmap mapping, not BSS and not
# stack. This script prints code_cache_bytes, stack_limit, static_bytes, and the
# Dynarec static-state size to make that accounting inspectable.
#
# Usage:
#   sh tier_perf.sh [ZIG] [--cgb]
#
# Env:
#   ZIG          compiler (first positional arg, else $ZIG, else seed path)
#   OUT          scratch dir (default /tmp/z9gb_tier_perf)
#   Z9GB_ROM_DIR ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   Z9GB_PERF_MIN_FPS host headless minimum sustained rendered fps (default 59.0)
#
# --cgb passes --cgb through to the host headless CLI workload. A missing ROM =
# SKIP (exit 77); ROM size/hash mismatch = FAIL. A skipped P4 hard gate blocks
# P4 closeout. Estimates are labelled as estimates; measured numbers are reported
# as measured. The Wine windowed result is evidence only and never changes the
# host headless gate threshold.


set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9gb_tier_perf}"
PERF_MIN="${Z9GB_PERF_MIN_FPS:-59.0}"
CGB=0

for arg in "$@"; do
    case "$arg" in
        --cgb) CGB=1 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) ZIG="$arg" ;;
    esac
done
CGB_FLAG=""
if [ "$CGB" -eq 1 ]; then
    CGB_FLAG="--cgb"
fi

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

summary() {
    echo
    echo "== tier_perf summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
    if [ "$FAILS" -ne 0 ]; then
        echo "TIER_PERF FAIL"
        exit 1
    fi
    if [ "$SKIPS" -ne 0 ]; then
        echo "TIER_PERF SKIP"
        exit 77
    fi
    echo "TIER_PERF PASS"
    exit 0
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in /usr/bin/time awk sha256sum stat; do
    if ! command -v "$tool" >/dev/null 2>&1 && [ ! -x "$tool" ]; then
        echo "SKIP: required host tool not found: $tool"
        exit 77
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

if [ -n "${Z9GB_ROM_DIR:-}" ]; then
    ROM_DIR="$Z9GB_ROM_DIR"
elif [ -d /tmp/z9gb_roms ]; then
    ROM_DIR=/tmp/z9gb_roms
elif [ -d "$Z9DIR/testdata/roms" ]; then
    ROM_DIR="$Z9DIR/testdata/roms"
else
    ROM_DIR=/tmp/z9gb_roms
fi

ROM=""
for cand in "$ROM_DIR/2048.gb" "$ROM_DIR/homebrew/2048.gb"; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done
if [ -z "$ROM" ]; then
    skip_case "2048.gb under $ROM_DIR"
    summary
fi

want="$(awk '$2 == "2048.gb" { print $1; exit }' \
    "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
rom_bytes="$(stat -c %s "$ROM" 2>/dev/null)"
if [ "$rom_bytes" != "32768" ]; then
    fail_case "2048.gb is ${rom_bytes:-<none>} bytes, expected 32768"
    summary
fi
if [ -z "$want" ]; then
    fail_case "2048.gb manifest row missing"
    summary
fi
got="$(sha256sum "$ROM" | cut -d' ' -f1)"
if [ "$got" != "$want" ]; then
    fail_case "2048.gb sha256 mismatch (got $got, want $want)"
    summary
fi
echo "       2048.gb sha256 $got ($rom_bytes bytes)"

echo
echo "== host build 2048.gb =="
HOST_DIR="$OUT/host"
mkdir -p "$HOST_DIR"
if timeout 300 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$HOST_DIR" \
    "$Z9DIR/main.zig" >"$HOST_DIR/dump.log" 2>&1; then
    pass_case "host build emits"
else
    fail_case "host build emits"
    tail -20 "$HOST_DIR/dump.log" | sed 's/^/       /'
    summary
fi
sed 's/-O0/-O2/g' "$HOST_DIR/build_target.sh" >"$HOST_DIR/build_target.sh.tmp" \
    && mv "$HOST_DIR/build_target.sh.tmp" "$HOST_DIR/build_target.sh"
if sh "$HOST_DIR/build_target.sh" linux "$HOST_DIR/z9gb" \
    >"$HOST_DIR/build.log" 2>&1; then
    pass_case "host build links at -O2"
else
    fail_case "host build links at -O2"
    tail -20 "$HOST_DIR/build.log" | sed 's/^/       /'
    summary
fi

echo
echo "== 1 MiB code cache / stack accounting =="
CODE_CACHE_BYTES=1048576
STACK_LIMIT=1048576
CACHE_SRC="$Z9DIR/dynarec/cache.zig"
static_bytes="$(size "$HOST_DIR/z9gb" 2>/dev/null | awk 'NR==2 { print $2 + $3 }')"
dynarec_state_bytes="$(nm -S --radix=d "$HOST_DIR/z9gb" 2>/dev/null \
    | awk '$4 ~ /_Dynarec$/ { print $2; exit }')"
echo "       code_cache_bytes=$CODE_CACHE_BYTES stack_limit=$STACK_LIMIT static_bytes=${static_bytes:-none} dynarec_state_bytes=${dynarec_state_bytes:-none}"
if [ "${static_bytes:-0}" -gt 0 ] && [ "${dynarec_state_bytes:-0}" -gt 0 ] \
    && [ "$dynarec_state_bytes" -lt "$CODE_CACHE_BYTES" ] \
    && grep -Fq 'mem: [*]u8' "$CACHE_SRC" \
    && grep -Fq 'VirtualAlloc' "$CACHE_SRC" \
    && grep -Fq 'mmap' "$CACHE_SRC"; then
    echo "       cache_alloc=VirtualAlloc(win32)/mmap(*nix) cache_in_bss=no cache_on_stack=no"
    pass_case "code cache is a dynamic 1 MiB mapping (not BSS/stack)"
else
    fail_case "code cache accounting (expected pointer mapping < 1 MiB static state)"
fi

host_perf() {
    mode="$1"
    flag="$2"
    tag="$3"
    timeout 300 /usr/bin/time -f 'wall=%e cpu_user=%U cpu_sys=%S rss_kb=%M' \
        -o "$HOST_DIR/time_$tag.txt" "$HOST_DIR/z9gb" \
        --headless $CGB_FLAG --frames 600 --audio --rom "$ROM" $flag \
        --fb-out "$HOST_DIR/2048.$tag.fb" >"$HOST_DIR/run_$tag.log" 2>&1
    host_rc=$?
    wall="$(sed -n 's/.*wall=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time_$tag.txt" | tail -1)"
    cpu_user="$(sed -n 's/.*cpu_user=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time_$tag.txt" | tail -1)"
    cpu_sys="$(sed -n 's/.*cpu_sys=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time_$tag.txt" | tail -1)"
    rss_kb="$(sed -n 's/.*rss_kb=\([0-9][0-9.]*\).*/\1/p' "$HOST_DIR/time_$tag.txt" | tail -1)"
    host_fps="$(awk -v w="${wall:-0}" \
        'BEGIN { if (w + 0 > 0) printf "%.3f", 600 / w; else print "0" }')"
    echo "       host_headless mode=$mode cgb=$CGB fps=$host_fps wall=${wall:-none}s cpu_user=${cpu_user:-none}s cpu_sys=${cpu_sys:-none}s rss_kb=${rss_kb:-none}"
}

echo
echo "== host headless 2048.gb --no-dynarec performance =="
host_perf no-dynarec "--no-dynarec" no_dynarec
if [ "$host_rc" -ne 0 ]; then
    fail_case "host headless --no-dynarec run rc=$host_rc"
    tail -10 "$HOST_DIR/run_no_dynarec.log" | sed 's/^/       /'
elif [ "$(stat -c %s "$HOST_DIR/2048.no_dynarec.fb" 2>/dev/null)" != "92160" ]; then
    fail_case "host headless --no-dynarec framebuffer is not 92160 bytes"
elif awk -v f="$host_fps" -v m="$PERF_MIN" \
    'BEGIN { exit !(f + 0 >= m + 0) }'; then
    pass_case "host headless --no-dynarec sustained $host_fps fps (>= $PERF_MIN)"
else
    fail_case "host headless --no-dynarec sustained $host_fps fps (< $PERF_MIN)"
fi

echo
echo "== host headless 2048.gb --dynarec (evidence; Win32/x86 only) =="
host_perf dynarec "--dynarec" dynarec
host_dyn="$(grep '^dynarec=' "$HOST_DIR/run_dynarec.log" | tail -1)"
echo "       host_headless mode=dynarec stats=${host_dyn:-missing}"
if [ "$host_rc" -ne 0 ]; then
    fail_case "host headless --dynarec run rc=$host_rc"
    tail -10 "$HOST_DIR/run_dynarec.log" | sed 's/^/       /'
elif [ "$(stat -c %s "$HOST_DIR/2048.dynarec.fb" 2>/dev/null)" != "92160" ]; then
    fail_case "host headless --dynarec framebuffer is not 92160 bytes"
elif [ -z "$host_dyn" ]; then
    fail_case "host headless --dynarec stats line missing"
else
    pass_case "host headless --dynarec evidence ($host_fps fps; $host_dyn)"
fi

echo
echo "== Wine windowed 2048.gb performance (evidence only) =="
WIN_DIR="$OUT/win32"
mkdir -p "$WIN_DIR"
OUT="$WIN_DIR" Z9GB_ROM_DIR="$ROM_DIR" \
    sh "$SCRIPT_DIR/tier_win32.sh" --perf "$ZIG" >"$OUT/win32.log" 2>&1
win_rc=$?
sed 's/^/       /' "$OUT/win32.log"
if [ "$win_rc" -eq 0 ]; then
    pass_case "tier_win32.sh --perf evidence run PASS (host headless is the gate)"
elif [ "$win_rc" -eq 77 ]; then
    skip_case "tier_win32.sh --perf SKIP"
else
    fail_case "tier_win32.sh --perf FAIL (rc=$win_rc)"
fi

wine_perf() {
    mode="$1"
    flag="$2"
    tag="$3"
    timeout 300 /usr/bin/time -f 'wall=%e cpu_user=%U cpu_sys=%S rss_kb=%M' \
        -o "$PERF_DIR/$tag.time.txt" \
        xvfb-run -a -s "-screen 0 1024x768x24" \
        wine "$PERF_EXE" --windowed $flag --scale 2 --frames 600 --audio \
        --rom "$ROM" --fb-out "$PERF_DIR/$tag.fb" \
        >"$PERF_DIR/$tag.direct.log" 2>&1
    direct_rc=$?
    wine_wall="$(sed -n 's/.*wall=\([0-9][0-9.]*\).*/\1/p' "$PERF_DIR/$tag.time.txt" | tail -1)"
    wine_cpu_user="$(sed -n 's/.*cpu_user=\([0-9][0-9.]*\).*/\1/p' "$PERF_DIR/$tag.time.txt" | tail -1)"
    wine_cpu_sys="$(sed -n 's/.*cpu_sys=\([0-9][0-9.]*\).*/\1/p' "$PERF_DIR/$tag.time.txt" | tail -1)"
    wine_rss_kb="$(sed -n 's/.*rss_kb=\([0-9][0-9.]*\).*/\1/p' "$PERF_DIR/$tag.time.txt" | tail -1)"
    timeout 300 xvfb-run -a -s "-screen 0 1024x768x24" \
        wine "$PERF_DIR/qpc_launch.exe" "$PERF_EXE" \
        --windowed $flag --scale 2 --frames 600 --audio \
        --rom "$ROM" --fb-out "$PERF_DIR/$tag.qpc.fb" \
        >"$PERF_DIR/$tag.qpc.log" 2>&1
    qpc_rc=$?
    qpc_sec="$(sed -n 's/.*QPC_SECONDS=\([0-9][0-9.]*\).*/\1/p' \
        "$PERF_DIR/$tag.qpc.log" | tail -1)"
    qpc_child_rc="$(sed -n 's/.*CHILD_RC=\([0-9][0-9]*\).*/\1/p' \
        "$PERF_DIR/$tag.qpc.log" | tail -1)"
    wine_fps="$(awk -v s="${qpc_sec:-0}" \
        'BEGIN { if (s + 0 > 0) printf "%.3f", 600 / s; else print "0" }')"
    wine_dyn="$(grep '^dynarec=' "$PERF_DIR/$tag.direct.log" | tail -1)"
    echo "       wine_windowed mode=$mode fps=$wine_fps qpc_seconds=${qpc_sec:-none} child_rc=${qpc_child_rc:-none} wall=${wine_wall:-none}s cpu_user=${wine_cpu_user:-none}s cpu_sys=${wine_cpu_sys:-none}s rss_kb=${wine_rss_kb:-none} ${wine_dyn:-dynarec=not-reported} (Wine evidence only; not Win98)"
    if [ "$direct_rc" -ne 0 ]; then
        fail_case "Wine $mode: direct run rc=$direct_rc"
    elif [ "$qpc_rc" -ne 0 ] || [ -z "$qpc_sec" ]; then
        fail_case "Wine $mode: QPC window timing missing (rc=$qpc_rc)"
    elif [ -z "$qpc_child_rc" ] || [ "$qpc_child_rc" -ne 0 ]; then
        fail_case "Wine $mode: child exit status ${qpc_child_rc:-missing}"
    elif [ "$(stat -c %s "$PERF_DIR/$tag.fb" 2>/dev/null)" != "92160" ] \
        || [ "$(stat -c %s "$PERF_DIR/$tag.qpc.fb" 2>/dev/null)" != "92160" ]; then
        fail_case "Wine $mode: framebuffer is not 92160 bytes"
    elif [ "$mode" = "dynarec" ] \
        && ! echo "$wine_dyn" | grep -q '^dynarec=on blocks='; then
        fail_case "Wine $mode: dynarec did not enable (${wine_dyn:-no stats line})"
    else
        pass_case "Wine windowed $mode sustained $wine_fps fps (evidence only; host headless is the gate)"
    fi
}


if [ "$win_rc" -eq 0 ]; then
    PERF_DIR="$WIN_DIR/perf"
    PERF_EXE="$PERF_DIR/z9gb_o2.exe"
    if [ -f "$PERF_EXE" ] && [ -f "$PERF_DIR/qpc_launch.exe" ]; then
        PERF_HOME="$PERF_DIR/home"
        mkdir -p "$PERF_HOME"
        printf 'pcm.!default { type null }\nctl.!default { type null }\n' \
            >"$PERF_HOME/.asoundrc"
        HOME="$PERF_HOME"
        export HOME
        WINEPREFIX="$PERF_DIR/wineprefix"
        export WINEPREFIX
        WINEARCH=win32
        export WINEARCH
        WINEDEBUG="${WINEDEBUG:--all}"
        export WINEDEBUG
        if command -v wineserver >/dev/null 2>&1; then
            wineserver -k >/dev/null 2>&1 || true
        fi
        xvfb-run -a -s "-screen 0 1024x768x24" wineboot -u \
            >"$PERF_DIR/wineboot_perf.log" 2>&1 || true
        wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f \
            >/dev/null 2>&1 || true
        wine_perf no-dynarec "--no-dynarec" no_dynarec
        wine_perf dynarec "--dynarec" dynarec
        if command -v wineserver >/dev/null 2>&1; then
            wineserver -k >/dev/null 2>&1 || true
        fi
    else
        fail_case "Wine perf artifacts missing for explicit on/off measurements"
    fi
fi

summary
