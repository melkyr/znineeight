#!/bin/sh
# tier_win32.sh — z9gb Win32 backend tier.
#
# Task 1 scope: build the Win32-only std_ddraw probe through the no-CRT mingw
# harness with -osw, pass the closed-world 9x import gate (no static DDRAW.DLL),
# and run the real exe under Wine/Xvfb at --scale 2 --frames 1. The windowed
# framebuffer checksum must equal the headless source checksum and the first
# pixel must be the solid probe colour 0x00123456.
#
# Task 5 adds section (d): build the real z9gb CLI with -osw, pass the 9x import
# gate with no static DSOUND.DLL/DINPUT8.DLL, run --windowed for 120 frames
# under Wine, check rss_kb, and require the windowed framebuffer to match a
# headless run over the same ROM/frame count. `--smoke` runs only section (d).
#
# Task 6 adds section (e): the named homebrew 2048.gb performance gate. It
# builds an -O2 no-CRT Win32 z9gb, runs --windowed --frames 600 with audio on
# under Wine, and measures the rendered-frame window with a QPC launcher.
# `--perf` runs only section (e). Missing/hash-mismatched ROM is SKIP/FAIL;
# Wine numbers are Wine evidence, never Win98.
#
# Env: ZIG       compiler (first positional arg, else $ZIG, else seed path)
#      OUT       scratch dir (default /tmp/z9gb_tier_win32)
#      Z9GB_ROM_DIR ROM root (default /tmp/z9gb_roms, else testdata/roms)
#      Z9GB_PERF_MIN_FPS minimum sustained rendered fps (default 59.0)
#
# Exits non-zero on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
SMOKE_ONLY=0
PERF_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --smoke) SMOKE_ONLY=1 ;;
        --perf) PERF_ONLY=1 ;;
        *) ZIG="$arg" ;;
    esac
done
OUT="${OUT:-/tmp/z9gb_tier_win32}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file md5sum od wine xvfb-run timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
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

if [ "$SMOKE_ONLY" -eq 0 ] && [ "$PERF_ONLY" -eq 0 ]; then

echo "== (a) std_ddraw Win32 probe =="
if OUT="$OUT/ddraw" ZIG="$ZIG" sh "$SCRIPT_DIR/run_ddraw_probe.sh" "$ZIG" \
    >"$OUT/ddraw_probe.log" 2>&1; then
    pass_case "run_ddraw_probe.sh PASS"
else
    fail_case "run_ddraw_probe.sh FAILED (see $OUT/ddraw_probe.log)"
fi
sed 's/^/       /' "$OUT/ddraw_probe.log"

EXE="$OUT/ddraw/ddraw_probe.exe"
if [ -f "$EXE" ]; then
    if bash "$CHECK" "$EXE" 9x >"$OUT/imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (tier re-check)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/imports.log)"
    fi
    DLLS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$DLLS" | grep -qx 'DDRAW.DLL'; then
        fail_case "DDRAW.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DDRAW.DLL import (loaded dynamically)"
    fi
else
    fail_case "ddraw_probe.exe missing"
fi

if grep -q '^DDRAW_PROBE PASS$' "$OUT/ddraw_probe.log" 2>/dev/null; then
    pass_case "probe marker DDRAW_PROBE PASS"
else
    fail_case "probe marker DDRAW_PROBE PASS missing"
fi

if grep -q '^[[:space:]]*readback scale=2 PASS' "$OUT/ddraw_probe.log" 2>/dev/null \
    && grep -q '^[[:space:]]*readback scale=4 PASS' "$OUT/ddraw_probe.log" 2>/dev/null; then
    pass_case "presented surface readback at scale 2 and 4 (GDI GetPixel)"
else
    fail_case "presented surface readback at scale 2/4 missing or failed"
fi

echo
echo "== (b) std_dinput Win32 probe =="
if OUT="$OUT/dinput" ZIG="$ZIG" sh "$SCRIPT_DIR/run_dinput_probe.sh" "$ZIG" \
    >"$OUT/dinput_probe.log" 2>&1; then
    pass_case "run_dinput_probe.sh PASS"
else
    fail_case "run_dinput_probe.sh FAILED (see $OUT/dinput_probe.log)"
fi
sed 's/^/       /' "$OUT/dinput_probe.log"

DEXE="$OUT/dinput/dinput_probe.exe"
if [ -f "$DEXE" ]; then
    if bash "$CHECK" "$DEXE" 9x >"$OUT/dinput_imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (dinput)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/dinput_imports.log)"
    fi
    DDLLS="$(i686-w64-mingw32-objdump -p "$DEXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$DDLLS" | grep -qx 'DINPUT8.DLL'; then
        fail_case "DINPUT8.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DINPUT8.DLL import (loaded dynamically)"
    fi
else
    fail_case "dinput_probe.exe missing"
fi

if grep -q '^DINPUT_PROBE PASS$' "$OUT/dinput_probe.log" 2>/dev/null; then
    pass_case "probe marker DINPUT_PROBE PASS"
else
    fail_case "probe marker DINPUT_PROBE PASS missing"
fi

if grep -Eq '^[[:space:]]*dinput=(ok|fallback)$' "$OUT/dinput_probe.log" 2>/dev/null; then
    pass_case "dinput backend line (ok or fallback)"
else
    fail_case "dinput backend line missing"
fi

echo
echo "== (c) std_dsound Win32 probe =="
if OUT="$OUT/dsound" ZIG="$ZIG" sh "$SCRIPT_DIR/run_dsound_probe.sh" "$ZIG" \
    >"$OUT/dsound_probe.log" 2>&1; then
    pass_case "run_dsound_probe.sh PASS"
else
    fail_case "run_dsound_probe.sh FAILED (see $OUT/dsound_probe.log)"
fi
sed 's/^/       /' "$OUT/dsound_probe.log"

SEXE="$OUT/dsound/dsound_probe.exe"
if [ -f "$SEXE" ]; then
    if bash "$CHECK" "$SEXE" 9x >"$OUT/dsound_imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (dsound)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/dsound_imports.log)"
    fi
    SDLLS="$(i686-w64-mingw32-objdump -p "$SEXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    if echo "$SDLLS" | grep -qx 'DSOUND.DLL'; then
        fail_case "DSOUND.DLL imported (must be loaded dynamically)"
    else
        pass_case "no DSOUND.DLL import (loaded dynamically)"
    fi
else
    fail_case "dsound_probe.exe missing"
fi

if grep -q '^DSOUND_PROBE PASS$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "probe marker DSOUND_PROBE PASS"
else
    fail_case "probe marker DSOUND_PROBE PASS missing"
fi

if grep -Eq '^[[:space:]]*backend=(1|2) queued=[0-9]+$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "dsound backend line (DirectSound or waveOut fallback)"
else
    fail_case "dsound backend line missing"
fi

if grep -q '^[[:space:]]*UNDERRUN_PASS$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "DirectSound long-stall underrun regression PASS"
else
    fail_case "DirectSound long-stall underrun regression missing"
fi

if grep -q '^[[:space:]]*STRESS_PASS$' "$OUT/dsound_probe.log" 2>/dev/null; then
    pass_case "waveOut busy-buffer stress regression PASS"
else
    fail_case "waveOut busy-buffer stress regression missing"
fi

fi # SMOKE_ONLY == 0

if [ "$PERF_ONLY" -eq 0 ]; then

echo
echo "== (d) z9gb Win32 windowed smoke =="
Z9GB_DIR="$OUT/z9gb"
Z9GB_EXE="$Z9GB_DIR/z9gb.exe"
mkdir -p "$Z9GB_DIR"

if EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
    DUMP_TARGET="-osw -I $ROOT/sf/src" \
    bash "$CROSS" "$ZIG" examples/z98/z9gb/main.zig "$Z9GB_DIR/work" "$Z9GB_EXE" \
    >"$OUT/z9gb_build.log" 2>&1 && [ -f "$Z9GB_EXE" ]; then
    pass_case "z9gb no-CRT -osw build produced z9gb.exe"
else
    fail_case "z9gb no-CRT -osw build failed (see $OUT/z9gb_build.log)"
fi
tail -5 "$OUT/z9gb_build.log" 2>/dev/null | sed 's/^/       /'

if [ -f "$Z9GB_EXE" ]; then
    ZFILE="$(file "$Z9GB_EXE" 2>/dev/null)"
    case "$ZFILE" in
        *PE32*Intel\ 80386*) pass_case "z9gb file: $ZFILE" ;;
        *) fail_case "z9gb is not a PE32 i386 executable: ${ZFILE:-<none>}" ;;
    esac
    if bash "$CHECK" "$Z9GB_EXE" 9x >"$OUT/z9gb_imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS (z9gb)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/z9gb_imports.log)"
    fi
    sed 's/^/       /' "$OUT/z9gb_imports.log"
    ZDLLS="$(i686-w64-mingw32-objdump -p "$Z9GB_EXE" 2>/dev/null \
        | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
    echo "$ZDLLS" | sed 's/^/       DLL /'
    if echo "$ZDLLS" | grep -qx 'DSOUND.DLL'; then
        fail_case "z9gb imports DSOUND.DLL (must be loaded dynamically)"
    else
        pass_case "z9gb has no DSOUND.DLL import (loaded dynamically)"
    fi
    if echo "$ZDLLS" | grep -qx 'DINPUT8.DLL'; then
        fail_case "z9gb imports DINPUT8.DLL (must be loaded dynamically)"
    else
        pass_case "z9gb has no DINPUT8.DLL import (loaded dynamically)"
    fi
else
    fail_case "z9gb file checks skipped (build produced no exe)"
fi

if [ -x /usr/bin/time ]; then
    Z9GB_HOME="$Z9GB_DIR/home"
    mkdir -p "$Z9GB_HOME"
    printf 'pcm.!default { type null }\nctl.!default { type null }\n' >"$Z9GB_HOME/.asoundrc"
    HOME="$Z9GB_HOME"
    export HOME
    WINEPREFIX="$Z9GB_DIR/wineprefix"
    export WINEPREFIX
    WINEARCH=win32
    export WINEARCH
    WINEDEBUG="${WINEDEBUG:--all}"
    export WINEDEBUG
    wineserver -k >/dev/null 2>&1 || true
    wineboot -u >"$OUT/z9gb_wineboot.log" 2>&1 || true
    wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f >/dev/null 2>&1 || true

    ROM="$Z9DIR/testdata/synth/minimal.gb"
    WIN_FB="$Z9GB_DIR/windowed.fb"
    HEAD_FB="$Z9GB_DIR/headless.fb"
    Z9GB_OK=0
    ATTEMPT=1
    while [ "$ATTEMPT" -le 3 ]; do
        rm -f "$WIN_FB"
        if timeout 300 /usr/bin/time -f '%M' -o "$OUT/z9gb_rss.txt" \
            xvfb-run -a -s "-screen 0 1024x768x24" \
            wine "$Z9GB_EXE" --windowed --scale 2 --frames 120 --rom "$ROM" --fb-out "$WIN_FB" \
            >"$OUT/z9gb_windowed.log" 2>&1 \
            && [ -s "$WIN_FB" ]; then
            Z9GB_OK=1
            break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        wineserver -k >/dev/null 2>&1 || true
    done
    if [ "$Z9GB_OK" = "1" ]; then
        pass_case "z9gb --windowed --frames 120 exited 0 with non-empty framebuffer (attempt $ATTEMPT)"
    else
        fail_case "z9gb --windowed --frames 120 failed after $ATTEMPT attempts (see $OUT/z9gb_windowed.log)"
    fi
    sed 's/^/       /' "$OUT/z9gb_windowed.log" 2>/dev/null || true
    INPUT_LINES="$(grep -Ec '^z9gb: input=(dinput8|fallback) audio=(dsound|waveout)' "$OUT/z9gb_windowed.log" 2>/dev/null)"
    if [ "$INPUT_LINES" = "1" ]; then
        pass_case "z9gb startup backend line (input/audio)"
    else
        fail_case "z9gb startup backend line missing or repeated (count=${INPUT_LINES:-0})"
    fi

    if [ -f "$WIN_FB" ] && [ "$(stat -c %s "$WIN_FB")" = "92160" ]; then
        pass_case "windowed framebuffer is 92160 bytes"
    else
        fail_case "windowed framebuffer missing or not 92160 bytes"
    fi

    RSS="$(tr -d '[:space:]' <"$OUT/z9gb_rss.txt" 2>/dev/null)"
    case "$RSS" in
        ''|*[!0-9]*)
            fail_case "rss_kb is not a positive integer: ${RSS:-<none>}"
            ;;
        *)
            if [ "$RSS" -gt 0 ]; then
                pass_case "rss_kb=$RSS"
            else
                fail_case "rss_kb is not positive: $RSS"
            fi
            ;;
    esac

    wineserver -k >/dev/null 2>&1 || true
    if [ -x "$Z9GB_EXE" ] && timeout 120 wine "$Z9GB_EXE" \
        --headless --frames 120 --rom "$ROM" --fb-out "$HEAD_FB" \
        >"$OUT/z9gb_headless.log" 2>&1; then
        pass_case "z9gb --headless --frames 120 reference exited 0"
    else
        fail_case "z9gb --headless reference failed (see $OUT/z9gb_headless.log)"
    fi
    sed 's/^/       /' "$OUT/z9gb_headless.log" 2>/dev/null || true

    if [ -f "$WIN_FB" ] && [ -f "$HEAD_FB" ]; then
        WIN_MD5="$(md5sum "$WIN_FB" | cut -d' ' -f1)"
        HEAD_MD5="$(md5sum "$HEAD_FB" | cut -d' ' -f1)"
        echo "       windowed md5 $WIN_MD5"
        echo "       headless md5 $HEAD_MD5"
        if [ "$WIN_MD5" = "$HEAD_MD5" ]; then
            pass_case "windowed framebuffer matches headless (same ROM/frame)"
        else
            fail_case "windowed framebuffer differs from headless (same ROM/frame)"
        fi
    else
        fail_case "framebuffer comparison skipped (missing dump)"
    fi
    wineserver -k >/dev/null 2>&1 || true
else
    fail_case "/usr/bin/time unavailable; cannot check rss_kb"
fi

fi # PERF_ONLY == 0

echo
echo "== (e) homebrew 2048.gb Wine performance gate =="
if [ "$SMOKE_ONLY" -eq 0 ]; then
PERF_MIN="${Z9GB_PERF_MIN_FPS:-59.0}"
ROM=""
for cand in "$ROM_DIR/2048.gb" "$ROM_DIR/homebrew/2048.gb"; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done
if [ -z "$ROM" ]; then
    skip_case "2048.gb under $ROM_DIR"
else
    rom_ok=1
    want="$(awk '$2 == "2048.gb" { print $1; exit }' \
        "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
    rom_bytes="$(stat -c %s "$ROM" 2>/dev/null)"
    if [ "$rom_bytes" != "32768" ]; then
        rom_ok=0
        fail_case "2048.gb is ${rom_bytes:-<none>} bytes, expected 32768"
    elif command -v sha256sum >/dev/null 2>&1 && [ -n "$want" ]; then
        got="$(sha256sum "$ROM" | cut -d' ' -f1)"
        if [ "$got" != "$want" ]; then
            rom_ok=0
            fail_case "2048.gb sha256 mismatch (got $got, want $want)"
        fi
    fi

    PERF_DIR="$OUT/perf"
    PERF_EXE="$PERF_DIR/z9gb_o2.exe"
    mkdir -p "$PERF_DIR"
    cat >"$PERF_DIR/gcc_o2.sh" <<'SH'
#!/bin/sh
exec i686-w64-mingw32-gcc -O2 "$@"
SH
    chmod +x "$PERF_DIR/gcc_o2.sh"

    if CROSS_GCC="$PERF_DIR/gcc_o2.sh" \
        EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
        DUMP_TARGET="-osw -I $ROOT/sf/src" \
        bash "$CROSS" "$ZIG" examples/z98/z9gb/main.zig \
        "$PERF_DIR/work" "$PERF_EXE" >"$PERF_DIR/build.log" 2>&1 \
        && [ -f "$PERF_EXE" ]; then
        pass_case "2048 perf: z9gb -O2 no-CRT Win32 build"
    else
        fail_case "2048 perf: Win32 -O2 build failed (see $PERF_DIR/build.log)"
        tail -10 "$PERF_DIR/build.log" 2>/dev/null | sed 's/^/       /'
    fi

    cat >"$PERF_DIR/qpc_launch.c" <<'C'
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    char cmd[4096];
    size_t n = 0;
    int i;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    LARGE_INTEGER f, t0, t1;
    HWND h = NULL;
    DWORD spins = 0;
    DWORD rc = 0;
    double sec;
    if (argc < 2) return 2;
    cmd[0] = 0;
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        size_t al = strlen(a);
        size_t j;
        if (n + al + 4 >= sizeof(cmd)) return 2;
        if (i > 1) cmd[n++] = ' ';
        cmd[n++] = '"';
        for (j = 0; j < al; j++) {
            if (a[j] == '"') cmd[n++] = '\\';
            cmd[n++] = a[j];
        }
        cmd[n++] = '"';
        cmd[n] = 0;
    }
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL,
                        &si, &pi)) {
        printf("QPC_FOUND=0 CREATE_FAIL=%lu\n", (unsigned long)GetLastError());
        return 3;
    }
    QueryPerformanceFrequency(&f);
    while (!h && spins < 60000) {
        h = FindWindowA("z98ddrawwnd", NULL);
        if (!h) Sleep(1);
        spins++;
    }
    if (!h) {
        TerminateProcess(pi.hProcess, 1);
        WaitForSingleObject(pi.hProcess, 1000);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        printf("QPC_FOUND=0 QPC_WAIT_MS=%lu\n", (unsigned long)spins);
        return 4;
    }
    QueryPerformanceCounter(&t0);
    WaitForSingleObject(pi.hProcess, INFINITE);
    QueryPerformanceCounter(&t1);
    GetExitCodeProcess(pi.hProcess, &rc);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    sec = (double)(t1.QuadPart - t0.QuadPart) / (double)f.QuadPart;
    printf("QPC_FOUND=1 QPC_WAIT_MS=%lu QPC_SECONDS=%.6f CHILD_RC=%lu\n",
           (unsigned long)spins, sec, (unsigned long)rc);
    return 0;
}
C

    if i686-w64-mingw32-gcc -O2 -o "$PERF_DIR/qpc_launch.exe" \
        "$PERF_DIR/qpc_launch.c" >"$PERF_DIR/qpc_build.log" 2>&1; then
        pass_case "2048 perf: QPC launcher built"
    else
        fail_case "2048 perf: QPC launcher build failed"
        tail -10 "$PERF_DIR/qpc_build.log" | sed 's/^/       /'
    fi

    if [ -f "$PERF_EXE" ] && [ -f "$PERF_DIR/qpc_launch.exe" ] \
        && [ "$rom_ok" = "1" ]; then
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
        wineserver -k >/dev/null 2>&1 || true
        xvfb-run -a -s "-screen 0 1024x768x24" wineboot -u \
            >"$PERF_DIR/wineboot.log" 2>&1 || true
        wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f \
            >/dev/null 2>&1 || true

        timeout 300 /usr/bin/time -f 'wall=%e cpu_user=%U cpu_sys=%S rss_kb=%M' \
            -o "$PERF_DIR/time.txt" \
            xvfb-run -a -s "-screen 0 1024x768x24" \
            wine "$PERF_EXE" --windowed --scale 2 --frames 600 --audio \
            --rom "$ROM" --fb-out "$PERF_DIR/2048.fb" \
            >"$PERF_DIR/windowed.log" 2>&1
        timed_rc=$?
        if [ "$timed_rc" -eq 0 ] && [ -s "$PERF_DIR/2048.fb" ]; then
            pass_case "2048 perf: Wine --windowed --frames 600 exit 0 with framebuffer"
        else
            fail_case "2048 perf: Wine --windowed --frames 600 failed (rc=$timed_rc)"
        fi

        timeout 300 xvfb-run -a -s "-screen 0 1024x768x24" \
            wine "$PERF_DIR/qpc_launch.exe" "$PERF_EXE" \
            --windowed --scale 2 --frames 600 --audio \
            --rom "$ROM" --fb-out "$PERF_DIR/2048_qpc.fb" \
            >"$PERF_DIR/qpc.log" 2>&1
        qpc_rc=$?
        qpc_sec="$(sed -n 's/.*QPC_SECONDS=\([0-9][0-9.]*\).*/\1/p' \
            "$PERF_DIR/qpc.log" | tail -1)"
        fps="$(awk -v s="${qpc_sec:-0}" \
            'BEGIN { if (s + 0 > 0) printf "%.3f", 600 / s; else print "0" }')"
        time_line="$(cat "$PERF_DIR/time.txt" 2>/dev/null)"
        echo "       wine_windowed fps=$fps qpc_seconds=${qpc_sec:-none} $time_line"
        echo "       (Wine evidence only; not Win98 hardware)"
        if [ "$qpc_rc" -ne 0 ] || [ -z "$qpc_sec" ]; then
            fail_case "2048 perf: QPC window timing missing (rc=$qpc_rc)"
        elif awk -v f="$fps" -v m="$PERF_MIN" \
            'BEGIN { exit !(f + 0 >= m + 0) }'; then
            pass_case "2048 perf: Wine windowed sustained $fps fps (>= $PERF_MIN)"
        else
            fail_case "2048 perf: Wine windowed sustained $fps fps (< $PERF_MIN)"
        fi
        wineserver -k >/dev/null 2>&1 || true
    fi
fi
fi # SMOKE_ONLY == 0

echo
echo "== tier_win32 summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_WIN32 FAIL"
    exit 1
fi
if [ "$SKIPS" -ne 0 ]; then
    echo "TIER_WIN32 SKIP"
    exit 77
fi
echo "TIER_WIN32 PASS"
exit 0
