#!/bin/sh
# tier_zstddecomp.sh -- Phase 3 Task 5 gate for the z9zstddecomp CLI.
#
# Builds examples/z98/z9zstddecomp/main.zig with a seed-built zig1, then:
#   - Linux: decodes every committed fixture and checks the exit code plus the
#     exact output md5 (plain, 4-stream literals, RLE, skippable+payload,
#     checksum, magic dictionary, raw dictionary, dict mismatch, truncated);
#   - Linux contract: -h rc 0, bad args rc 1, missing input rc 2, output path a
#     directory rc 4, tiny --max-output rc 5, tiny --max-window-log rc 3;
#   - Windows: -osw nt emit, MinGW CRT build through the emitted
#     build_target.sh, check_win9x_imports.sh ... nt PASS, then Wine runs of
#     plain and magic-dict with the same golden md5s.
# It also records the zig1 compile max RSS (the <16 MiB target).
#
# The committed tests/fixtures/*.zst files are consumed as-is; the tier never
# regenerates them (gen_fixtures.c is dev-time only).
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG       seed-built zig1_5_clean (default /tmp/p3_t5_base/zig1_5_clean)
#      OUT       scratch dir (default /tmp/z9zstddecomp_tier)
#      WINEPREFIX default $OUT/wineprefix

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APP_DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/p3_t5_base/zig1_5_clean}"
OUT="${OUT:-/tmp/z9zstddecomp_tier}"
ENTRY="examples/z98/z9zstddecomp/main.zig"
FIX="$APP_DIR/tests/fixtures"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
WINEPREFIX="${WINEPREFIX:-$OUT/wineprefix}"
export WINEPREFIX
export WINEARCH=win32
export WINEDEBUG="${WINEDEBUG:--all}"

MD5_PLAIN=6d77cc99c2f912f74721e754a1ce0026
MD5_FOURSTREAM=f0c446198196278122febb1749461137
MD5_RLE=7644672d049290f0390d9c993c7d343d
MD5_MAGICDICT=49af6491e19d223cf0fc6c691046140a
MD5_RAWDICT=f13e39810ea096b6eaed2693fe772d02

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t5_base"
    exit 1
fi
for tool in md5sum cmp file wine i686-w64-mingw32-gcc i686-w64-mingw32-objdump; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done
if [ ! -f "$CHECK" ]; then
    echo "FAIL: import gate not found: $CHECK"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/linux" "$OUT/emit" "$OUT/wine"
cd "$ROOT" || exit 1

# --- Linux build + compile RSS ---------------------------------------------
echo "== build z9zstddecomp with the seed compiler =="
COMPILE_RSS="n/a"
if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -v -o "$OUT/zig_time.log" \
        "$ZIG" -fsafe -o "$OUT/bin" "$ENTRY" >"$OUT/zig.log" 2>&1
    BUILD_RC=$?
    COMPILE_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/zig_time.log" | tail -1)
    [ -n "$COMPILE_RSS" ] || COMPILE_RSS="n/a"
else
    "$ZIG" -fsafe -o "$OUT/bin" "$ENTRY" >"$OUT/zig.log" 2>&1
    BUILD_RC=$?
fi
if [ "$BUILD_RC" -ne 0 ]; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -30 "$OUT/zig.log" | sed 's/^/       /'
    echo
    echo "== tier_zstddecomp summary: $PASSES passed, $FAILS failed =="
    echo "TIER_ZSTDDECOMP FAIL"
    exit 1
fi
if ! sh "$OUT/bin/build_target.sh" linux "$OUT/bin/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -30 "$OUT/build.log" | sed 's/^/       /'
    echo
    echo "== tier_zstddecomp summary: $PASSES passed, $FAILS failed =="
    echo "TIER_ZSTDDECOMP FAIL"
    exit 1
fi
PROG="$OUT/bin/prog"
[ -x "$PROG" ] || { echo "FAIL: $PROG not built"; exit 1; }
pass_case "Linux build produced $PROG"

if [ "$COMPILE_RSS" = "n/a" ]; then
    echo "operator-hardware: zig1 compile RSS not measured (/usr/bin/time absent)"
elif [ "$COMPILE_RSS" -lt 16384 ]; then
    pass_case "zig1 compile max RSS < 16 MiB (${COMPILE_RSS} kB)"
else
    fail_case "zig1 compile max RSS >= 16 MiB (${COMPILE_RSS} kB)"
fi

# --- Linux fixture cases ----------------------------------------------------
run_ok() {
    rk_name="$1"
    rk_md5="$2"
    shift 2
    rk_out="$OUT/linux/$rk_name.out"
    rm -f "$rk_out"
    "$PROG" "$@" >"$OUT/linux/$rk_name.stdout" 2>"$OUT/linux/$rk_name.stderr"
    rk_rc=$?
    if [ "$rk_rc" -eq 0 ]; then
        pass_case "$rk_name exit 0"
    else
        fail_case "$rk_name exit 0 (got $rk_rc)"
        tail -5 "$OUT/linux/$rk_name.stderr" | sed 's/^/       /'
        return
    fi
    if [ ! -f "$rk_out" ]; then
        fail_case "$rk_name wrote output"
        return
    fi
    rk_got=$(md5sum "$rk_out" | awk '{print $1}')
    if [ "$rk_got" = "$rk_md5" ]; then
        pass_case "$rk_name output md5 $rk_got"
    else
        fail_case "$rk_name output md5 got $rk_got want $rk_md5"
    fi
}

echo "== Linux fixture cases =="
run_ok plain "$MD5_PLAIN" "$FIX/plain.zst" "$OUT/linux/plain.out"
run_ok fourstream "$MD5_FOURSTREAM" "$FIX/fourstream.zst" "$OUT/linux/fourstream.out"
run_ok rle "$MD5_RLE" "$FIX/rle.zst" "$OUT/linux/rle.out"
run_ok skippable "$MD5_PLAIN" "$FIX/skippable.zst" "$OUT/linux/skippable.out"
run_ok checksum "$MD5_PLAIN" "$FIX/checksum.zst" "$OUT/linux/checksum.out"
run_ok magic-dict "$MD5_MAGICDICT" "$FIX/magic-dict.zst" "$OUT/linux/magic-dict.out" --dict "$FIX/dict-magic.bin"
run_ok raw-dict "$MD5_RAWDICT" "$FIX/raw-dict.zst" "$OUT/linux/raw-dict.out" --dict "$FIX/dict-raw.bin"

echo "== Linux exit-code contract =="
"$PROG" -h >"$OUT/linux/help.out" 2>"$OUT/linux/help.err"
HELP_RC=$?
if [ "$HELP_RC" -eq 0 ] && grep -q 'usage: z9zstddecomp' "$OUT/linux/help.out"; then
    pass_case "-h exit 0 and prints usage"
else
    fail_case "-h exit 0 and prints usage (rc=$HELP_RC)"
fi

"$PROG" >"$OUT/linux/noargs.out" 2>"$OUT/linux/noargs.err"
NOARGS_RC=$?
if [ "$NOARGS_RC" -eq 1 ]; then
    pass_case "bad args (no operands) exit 1"
else
    fail_case "bad args (no operands) exit 1 (got $NOARGS_RC)"
fi

"$PROG" "$FIX/plain.zst" "$OUT/linux/bogus.out" --bogus >"$OUT/linux/bogus.out.log" 2>&1
BOGUS_RC=$?
if [ "$BOGUS_RC" -eq 1 ]; then
    pass_case "bad args (unknown flag) exit 1"
else
    fail_case "bad args (unknown flag) exit 1 (got $BOGUS_RC)"
fi

rm -f "$OUT/linux/missing.out"
"$PROG" "$FIX/does-not-exist.zst" "$OUT/linux/missing.out" >"$OUT/linux/missing.log" 2>&1
MISSING_RC=$?
if [ "$MISSING_RC" -eq 2 ]; then
    pass_case "missing input exit 2"
else
    fail_case "missing input exit 2 (got $MISSING_RC)"
fi

"$PROG" "$FIX/plain.zst" "$OUT/linux" >"$OUT/linux/dir.log" 2>&1
DIR_RC=$?
if [ "$DIR_RC" -eq 4 ]; then
    pass_case "output path is a directory exit 4"
else
    fail_case "output path is a directory exit 4 (got $DIR_RC)"
fi

rm -f "$OUT/linux/max.out"
"$PROG" "$FIX/plain.zst" "$OUT/linux/max.out" --max-output 16 >"$OUT/linux/max.log" 2>&1
MAX_RC=$?
if [ "$MAX_RC" -eq 5 ]; then
    pass_case "tiny --max-output exit 5"
else
    fail_case "tiny --max-output exit 5 (got $MAX_RC)"
fi

rm -f "$OUT/linux/window.out"
"$PROG" "$FIX/plain.zst" "$OUT/linux/window.out" --max-window-log 10 >"$OUT/linux/window.log" 2>&1
WINDOW_RC=$?
if [ "$WINDOW_RC" -eq 3 ]; then
    pass_case "tiny --max-window-log exit 3"
else
    fail_case "tiny --max-window-log exit 3 (got $WINDOW_RC)"
fi

rm -f "$OUT/linux/mismatch.out"
"$PROG" "$FIX/dict-mismatch.zst" "$OUT/linux/mismatch.out" --dict "$FIX/dict-other.bin" >"$OUT/linux/mismatch.log" 2>&1
MISMATCH_RC=$?
if [ "$MISMATCH_RC" -eq 3 ]; then
    pass_case "dictionary mismatch exit 3"
else
    fail_case "dictionary mismatch exit 3 (got $MISMATCH_RC)"
fi

rm -f "$OUT/linux/truncated.out"
"$PROG" "$FIX/truncated.zst" "$OUT/linux/truncated.out" >"$OUT/linux/truncated.log" 2>&1
TRUNC_RC=$?
if [ "$TRUNC_RC" -eq 3 ]; then
    pass_case "truncated frame exit 3"
else
    fail_case "truncated frame exit 3 (got $TRUNC_RC)"
fi

# --- Windows 9x/NT CRT smoke -----------------------------------------------
echo "== Windows: -osw nt emit + MinGW CRT build =="
timeout 300 "$ZIG" -osw nt -o "$OUT/emit" "$ENTRY" >"$OUT/emit.log" 2>&1
EMIT_RC=$?
if [ "$EMIT_RC" -ne 0 ]; then
    fail_case "-osw nt emit (rc=$EMIT_RC; see $OUT/emit.log)"
    tail -20 "$OUT/emit.log" | sed 's/^/       /'
else
    pass_case "-osw nt emit"
fi
if [ -f "$OUT/emit/build_target.sh" ] && grep -q -- '-DZIG_WIN_NT' "$OUT/emit/build_target.sh"; then
    pass_case "emitted build_target.sh carries -DZIG_WIN_NT (CRT profile)"
else
    fail_case "emitted build_target.sh missing -DZIG_WIN_NT"
fi

EXE="$OUT/z9zstddecomp.exe"
if sh "$OUT/emit/build_target.sh" mingw "$EXE" >"$OUT/win_build.log" 2>&1 && [ -f "$EXE" ]; then
    pass_case "MinGW CRT build produced $(basename "$EXE")"
else
    fail_case "MinGW CRT build failed (see $OUT/win_build.log)"
    tail -20 "$OUT/win_build.log" | sed 's/^/       /'
fi

if [ -f "$EXE" ]; then
    FILEOUT="$(file "$EXE" 2>/dev/null)"
    case "$FILEOUT" in
        *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
        *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
    esac

    if bash "$CHECK" "$EXE" nt >"$OUT/imports.log" 2>&1; then
        pass_case "check_win9x_imports.sh nt PASS"
    else
        fail_case "check_win9x_imports.sh nt FAILED (see $OUT/imports.log)"
    fi
    tail -3 "$OUT/imports.log" | sed 's/^/       /'

    cp "$FIX/plain.zst" "$FIX/magic-dict.zst" "$FIX/dict-magic.bin" "$OUT/wine/"
    rm -f "$OUT/wine/plain.out" "$OUT/wine/magic.out"

    ( cd "$OUT/wine" && timeout 180 wine "$EXE" plain.zst plain.out ) \
        >"$OUT/wine_plain.log" 2>&1
    WPLAIN_RC=$?
    if [ "$WPLAIN_RC" -eq 0 ]; then
        pass_case "Wine plain exit 0"
    else
        fail_case "Wine plain exit 0 (got $WPLAIN_RC; see $OUT/wine_plain.log)"
        tail -10 "$OUT/wine_plain.log" | sed 's/^/       /'
    fi
    if [ -f "$OUT/wine/plain.out" ] && \
       [ "$(md5sum "$OUT/wine/plain.out" | awk '{print $1}')" = "$MD5_PLAIN" ]; then
        pass_case "Wine plain output md5 $MD5_PLAIN"
    else
        fail_case "Wine plain output md5 mismatch"
    fi

    ( cd "$OUT/wine" && timeout 180 wine "$EXE" magic-dict.zst magic.out --dict dict-magic.bin ) \
        >"$OUT/wine_magic.log" 2>&1
    WMAGIC_RC=$?
    if [ "$WMAGIC_RC" -eq 0 ]; then
        pass_case "Wine magic-dict exit 0"
    else
        fail_case "Wine magic-dict exit 0 (got $WMAGIC_RC; see $OUT/wine_magic.log)"
        tail -10 "$OUT/wine_magic.log" | sed 's/^/       /'
    fi
    if [ -f "$OUT/wine/magic.out" ] && \
       [ "$(md5sum "$OUT/wine/magic.out" | awk '{print $1}')" = "$MD5_MAGICDICT" ]; then
        pass_case "Wine magic-dict output md5 $MD5_MAGICDICT"
    else
        fail_case "Wine magic-dict output md5 mismatch"
    fi
else
    fail_case "Windows executable not produced; Wine cases not run"
fi

echo
echo "== tier_zstddecomp summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_ZSTDDECOMP FAIL"
    exit 1
fi
echo "TIER_ZSTDDECOMP PASS"
exit 0
