#!/usr/bin/env bash
set -uo pipefail
# scripts/compiler/gate_win_compat.sh [path/to/zig1] [--exe <operator-exe>] [--skip-cross]
#
# Win9x truth gate (Task TE hotfix):
#   1. emit the compiler's own -osw C dump;
#   2. fail on any MSVC 6 / OpenWatcom reserved identifier in an emitted
#      module .c/.h (runtime/support files are excluded: they legitimately
#      contain Z98_STDCALL / __stdcall / __cdecl template text);
#   3. prove the reserved-word escape happened (z_cdecl);
#   4. lint every emitted .bat against the command.com-safe rules:
#        no setlocal/endlocal, no %ERRORLEVEL%, no &&/||, no exit /b,
#        no goto :eof, no %~/%*/%1, no parenthesised if, no "if not"
#        (CL_EXE/LINK_EXE set lines are the only allowed `set`);
#        :z98_fail + if errorlevel 1 goto z98_fail + BUILD FAILED on the
#        fail path; Built: only on the success path; non-REM lines <= 260;
#        hardcoded prog.exe; MSVC CL_EXE/LINK_EXE overrides; flag parity;
#        MSVC/OWC CRT link via *.obj; MinGW via @z98_link.rsp;
#   5. optional MinGW cross compile of every emitted .c (skip with
#      --skip-cross or when i686-w64-mingw32-gcc is absent);
#   6. optional 9x import gate with --exe <operator-exe>.
#
# This gate proves emitted TEXT locally. It cannot replace the operator VM:
# real cl.exe/wcc386/wlink/command.com behavior, environment space, long
# names, and the static-CRT zig1_w32.exe remain VM-only (Task TE Step 8).
#
# usage: scripts/compiler/gate_win_compat.sh [zig1] [--exe <pe>] [--skip-cross]

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1=""
EXE=""
SKIP_CROSS=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --exe)
            [ "$#" -ge 2 ] || { echo "error: --exe requires a path" >&2; exit 2; }
            EXE="$2"; shift 2 ;;
        --skip-cross)
            SKIP_CROSS=1; shift ;;
        -*)
            echo "error: unknown option '$1'" >&2; exit 2 ;;
        *)
            if [ -z "$ZIG1" ]; then ZIG1="$1"; else
                echo "error: unexpected argument '$1'" >&2; exit 2
            fi
            shift ;;
    esac
done
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then ZIG1="$ROOT/zig1"; else
        echo "usage: scripts/compiler/gate_win_compat.sh [path/to/zig1] [--exe <pe>] [--skip-cross]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }
ZIG1="$(cd "$(dirname "$ZIG1")" && pwd)/$(basename "$ZIG1")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_win_compat.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0
ok()  { echo "[win-compat] OK   $*"; }
bad() { echo "[win-compat] FAIL $*" >&2; fail=1; }

# Tier A documented-reserved list (I-1 report), bare self deliberately absent.
RESERVED='cdecl|near|far|huge|pascal|fortran|interrupt|stdcall|fastcall|asm|inline|based|int8|int16|int32|int64|leave|_asm|_based|_cdecl|_declspec|_emit|_except|_export|_far|_far16|_fastcall|_finally|_fortran|_huge|_inline|_int8|_int16|_int32|_int64|_interrupt|_leave|_loadds|_near|_pascal|_saveregs|_segment|_segname|_self|_stdcall|_syscall|_try|__asm|__based|__cdecl|__declspec|__emit|__except|__export|__far|__far16|__fastcall|__finally|__fortran|__huge|__inline|__int8|__int16|__int32|__int64|__interrupt|__leave|__loadds|__near|__pascal|__saveregs|__segment|__segname|__self|__stdcall|__syscall|__try|__unaligned|__watcall|__ptr32|__ptr64|_Cdecl|_Except|_Export|_Far16|_Fastcall|_Finally|_Leave|_Packed|_Pascal|_Seg16|_Syscall|_System|_Try'

is_support_file() {
    case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
        zig_compat.h|zig_runtime.h|zig_runtime.c|zig_pal.c|zig_nocrt.c|c_exit.c|net_prelude.h|std_os_prelude.h|std_time_prelude.h)
            return 0 ;;
    esac
    return 1
}

# ---- 1. emit ---------------------------------------------------------------
mkdir -p "$WORK/emit"
( cd "$ROOT" && timeout 600 "$ZIG1" -osw -o "$WORK/emit" sf/src/main.zig ) \
    >"$WORK/emit.log" 2>&1
emit_rc=$?
rm -f "$WORK/emit"/.zig1_*.tmp
if [ "$emit_rc" -ne 0 ]; then
    bad "self-emission dump rc=$emit_rc (see $WORK/emit.log)"
else
    ok "self-emission dump"
fi
if ! ls "$WORK/emit"/*.c >/dev/null 2>&1; then
    bad "no .c emitted"
fi

# ---- 2. reserved-identifier scan (module files only) -----------------------
scan_files=()
for f in "$WORK/emit"/*.c "$WORK/emit"/*.h; do
    [ -e "$f" ] || continue
    is_support_file "$f" && continue
    scan_files+=("$f")
done
strip_c_literals() {
    # Blank out C string/char literal bodies and comments, preserving line
    # numbers. emit_support_*.c embeds the runtime C as string literals and
    # diagnostic strings mention __stdcall/etc; those are template text, not
    # emitted identifiers.
    awk '
        BEGIN { dq=sprintf("%c",34); sq=sprintf("%c",39); bs=sprintf("%c",92); inb=0 }
        {
            line=$0; out=""; n=length(line); i=1; ins=0; inc=0;
            while (i<=n) {
                c=substr(line,i,1); d=substr(line,i+1,1);
                if (inb) {
                    if (c=="*" && d=="/") { inb=0; out=out "  "; i+=2 }
                    else { out=out " "; i++ }
                    continue
                }
                if (ins) {
                    if (c==bs) { out=out "  "; i+=2 }
                    else if (c==dq) { ins=0; out=out dq; i++ }
                    else { out=out " "; i++ }
                    continue
                }
                if (inc) {
                    if (c==bs) { out=out "  "; i+=2 }
                    else if (c==sq) { inc=0; out=out sq; i++ }
                    else { out=out " "; i++ }
                    continue
                }
                if (c=="/" && d=="*") { inb=1; out=out "  "; i+=2; continue }
                if (c=="/" && d=="/") { out=out " "; i=n+1; continue }
                if (c==dq) { ins=1; out=out dq; i++; continue }
                if (c==sq) { inc=1; out=out sq; i++; continue }
                out=out c; i++
            }
            print out
        }
    ' "$1"
}
if [ "${#scan_files[@]}" -eq 0 ]; then
    bad "reserved scan: no module files"
else
    hits="$WORK/reserved_hits.txt"
    : >"$hits"
    for f in "${scan_files[@]}"; do
        strip_c_literals "$f" \
            | grep -nE "(^|[^A-Za-z0-9_])($RESERVED)([^A-Za-z0-9_]|\$)" \
            | sed "s|^|$f:|" >>"$hits" || true
    done
    if [ -s "$hits" ]; then
        bad "reserved identifier(s) in emitted module C/H:"
        sed -n '1,40p' "$hits" >&2
    else
        ok "reserved-identifier scan (${#scan_files[@]} module files)"
    fi
fi

# Positive proof: the failing self-source local `cdecl` became `z_cdecl`.
if grep -qE '(^|[^A-Za-z0-9_])z_cdecl([^A-Za-z0-9_]|$)' "$WORK"/emit/main_*.c 2>/dev/null; then
    ok "escape proof: z_cdecl present in main_*.c"
else
    bad "escape proof: z_cdecl absent from emitted main_*.c"
fi

# Export/function-name probe: a reserved `export fn` keeps its raw ABI symbol
# (documented escape bypass), while a non-export function is hash-prefixed and
# must not be raw-escaped to z_<keyword>.
mkdir -p "$WORK/exportprobe"
cat >"$WORK/export_probe.zig" <<'Z98'
const std = @import("std");

export fn cdecl(n: i32) i32 {
    return n;
}

fn near(n: i32) i32 {
    return n + 1;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, cdecl(1) + near(1)));
    std.io.writeByte('\n');
}
Z98
if timeout 120 "$ZIG1" -osw -o "$WORK/exportprobe" "$WORK/export_probe.zig" >"$WORK/exportprobe.log" 2>&1; then
    rm -f "$WORK/exportprobe"/.zig1_*.tmp
    if grep -qE '(^|[^A-Za-z0-9_])z_cdecl[[:space:]]*\(' "$WORK/exportprobe"/*.c 2>/dev/null; then
        bad "reserved export fn 'cdecl' was escaped to z_cdecl"
    elif grep -qE '(^|[^A-Za-z0-9_])cdecl[[:space:]]*\(' "$WORK/exportprobe"/*.c 2>/dev/null; then
        echo "[win-compat] NOTE reserved export fn kept raw ABI symbol: cdecl"
    else
        bad "reserved export fn 'cdecl' is absent from the probe emission"
    fi
    if grep -qE '(^|[^A-Za-z0-9_])z_near[[:space:]]*\(' "$WORK/exportprobe"/*.c 2>/dev/null; then
        bad "non-export fn 'near' was raw-escaped to z_near"
    elif grep -qE 'zF_[0-9A-F]+_near' "$WORK/exportprobe"/*.c 2>/dev/null; then
        ok "non-export fn 'near' is hash-prefixed (zF_<hash>_near)"
    else
        bad "non-export fn 'near' has no hash-prefixed emission"
    fi
else
    bad "reserved-export probe dump failed (see $WORK/exportprobe.log)"
fi

# ---- 3. command.com-safe batch lint ---------------------------------------
MAX_LINE="${MAX_LINE:-260}"
lint_bat() {
    local bat="$1" name lf line_no setline is_alias fail_before
    name="$(basename "$bat")"
    lf="$WORK/lint_$name"
    tr -d '\r' <"$bat" >"$lf"
    fail_before=$fail
    is_alias=0
    case "$name" in
        build_target.bat|build_owc.bat)
            is_alias=1
            if ! grep -qE '^[[:space:]]*call[[:space:]]+build_(target|owc)_(crt|nocrt)\.bat[[:space:]]*$' "$lf"; then
                bad "$name: alias does not call a build_*_(crt|nocrt).bat"
            fi
            ;;
    esac

    # Forbidden constructs (case-insensitive).
    if grep -inE '(^|[[:space:]])setlocal([[:space:]]|$)|(^|[[:space:]])endlocal([[:space:]]|$)|%ERRORLEVEL%|exit[[:space:]]+/b|goto[[:space:]]+:eof|%~|%\*|[[:space:]]&&[[:space:]]|[[:space:]]\|\|[[:space:]]|if[[:space:]]+not[[:space:]]+"|if[[:space:]]*\(' "$lf" >"$WORK/bad_constructs"; then
        bad "$name: forbidden command.com construct(s):"
        sed -n '1,20p' "$WORK/bad_constructs" >&2
    fi

    # Only CL_EXE/LINK_EXE `set` lines are allowed.
    while IFS= read -r setline; do
        [ -n "$setline" ] || continue
        line_no="${setline%%:*}"
        case "${setline#*:}" in
            [Ss][Ee][Tt]\ [Cc][Ll]_[Ee][Xx][Ee]=*|[Ss][Ee][Tt]\ [Ll][Ii][Nn][Kk]_[Ee][Xx][Ee]=*) ;;
            *) bad "$name:$line_no: disallowed set line: ${setline#*:}" ;;
        esac
    done < <(grep -nE '^[[:space:]]*[Ss][Ee][Tt][[:space:]]+' "$lf" || true)

    if [ "$is_alias" -eq 0 ]; then
    # No argument handling; hardcode prog.exe.
    if grep -nE '%[0-9]' "$lf" >"$WORK/args"; then
        bad "$name: %N argument handling is forbidden:"
        sed -n '1,10p' "$WORK/args" >&2
    fi
    if ! grep -qE '(^|[^A-Za-z0-9_])prog\.exe([^A-Za-z0-9_]|$)' "$lf"; then
        bad "$name: does not hardcode prog.exe"
    fi

    # Fail path and success path.
    if ! grep -qE '^[[:space:]]*:z98_fail[[:space:]]*$' "$lf"; then
        bad "$name: missing :z98_fail label"
    fi
    if ! grep -qE '^[[:space:]]*if[[:space:]]+errorlevel[[:space:]]+1[[:space:]]+goto[[:space:]]+z98_fail[[:space:]]*$' "$lf"; then
        bad "$name: missing 'if errorlevel 1 goto z98_fail'"
    fi
    if ! grep -qE '^[[:space:]]*:z98_done[[:space:]]*$' "$lf"; then
        bad "$name: missing :z98_done label"
    fi
    fail_line=$(grep -nE '^[[:space:]]*:z98_fail[[:space:]]*$' "$lf" | head -n1 | cut -d: -f1)
    fail_line="${fail_line:-0}"
    if [ "$fail_line" -gt 0 ]; then
        if ! tail -n +"$fail_line" "$lf" | grep -qE '^[[:space:]]*echo[[:space:]]+BUILD FAILED[[:space:]]*$'; then
            bad "$name: fail path does not echo BUILD FAILED"
        fi
        if tail -n +"$fail_line" "$lf" | grep -qE 'Built:'; then
            bad "$name: prints Built: on the fail path"
        fi
    fi
    built_line=$(grep -n 'Built:' "$lf" | head -n1 | cut -d: -f1)
    built_line="${built_line:-0}"
    if [ "$built_line" -eq 0 ]; then
        bad "$name: no Built: success line"
    elif [ "$fail_line" -gt 0 ] && [ "$built_line" -ge "$fail_line" ]; then
        bad "$name: Built: is not on the success branch"
    elif ! sed -n "${built_line},\$p" "$lf" | grep -qE '^[[:space:]]*goto[[:space:]]+z98_done[[:space:]]*$'; then
        # `goto z98_done` must follow the success echo and precede :z98_fail.
        if ! head -n "$fail_line" "$lf" | tail -n +"$built_line" | grep -qE '^[[:space:]]*goto[[:space:]]+z98_done[[:space:]]*$'; then
            bad "$name: success path lacks goto z98_done after Built:"
        fi
    fi
    fi

    # Line length (REM lines exempt).
    if awk -v m="$MAX_LINE" 'length($0) > m && $0 !~ /^[[:space:]]*[Rr][Ee][Mm]([[:space:]]|$)/ { print NR ":" length($0); bad=1 } END { exit bad ? 0 : 1 }' "$lf" >"$WORK/long_lines"; then
        bad "$name: non-REM line(s) longer than $MAX_LINE chars:"
        sed -n '1,10p' "$WORK/long_lines" >&2
    fi

    # Per-toolchain shape / flag parity.
    case "$name" in
        build_target_crt.bat|build_target_nocrt.bat)
            grep -qE '^[[:space:]]*[Ss][Ee][Tt][[:space:]]+CL_EXE=cl[[:space:]]*$' "$lf" || bad "$name: missing 'set CL_EXE=cl'"
            grep -qE '^[[:space:]]*[Ss][Ee][Tt][[:space:]]+LINK_EXE=link[[:space:]]*$' "$lf" || bad "$name: missing 'set LINK_EXE=link'"
            grep -q '%CL_EXE%' "$lf" || bad "$name: compile lines do not use %CL_EXE%"
            grep -q '%LINK_EXE%' "$lf" || bad "$name: link line does not use %LINK_EXE%"
            if grep '%CL_EXE%' "$lf" | grep -qv '/c '; then
                bad "$name: %CL_EXE% compile line lacks /c"
            fi
            grep -q '/nologo' "$lf" || bad "$name: missing /nologo"
            grep -q '/O2' "$lf" || bad "$name: missing /O2"
            grep -q '/DWINVER=0x0410' "$lf" || bad "$name: missing /DWINVER=0x0410"
            grep -q '/D_WIN32_WINNT=0x0410' "$lf" || bad "$name: missing /D_WIN32_WINNT=0x0410"
            grep -q '/D_CRT_SECURE_NO_WARNINGS' "$lf" || bad "$name: missing /D_CRT_SECURE_NO_WARNINGS"
            grep -q '/D_CRT_NONSTDC_NO_DEPRECATE' "$lf" || bad "$name: missing /D_CRT_NONSTDC_NO_DEPRECATE"
            ;;
        build_owc_crt.bat|build_owc_nocrt.bat)
            grep -q '/d_WIN32' "$lf" || bad "$name: missing /d_WIN32"
            grep -q '/dWINVER=0x0410' "$lf" || bad "$name: missing /dWINVER=0x0410"
            grep -q '/d_CRT_SECURE_NO_WARNINGS' "$lf" || bad "$name: missing /d_CRT_SECURE_NO_WARNINGS"
            grep -q '/d_CRT_NONSTDC_NO_DEPRECATE' "$lf" || bad "$name: missing /d_CRT_NONSTDC_NO_DEPRECATE"
            grep -q '/ox' "$lf" || bad "$name: missing /ox"
            grep -qE '^wcc386 .*\.c$' "$lf" || bad "$name: no wcc386 compile line"
            if grep -E '^wcc386 ' "$lf" | grep -qvE '\.c$'; then
                bad "$name: wcc386 line is not compile-only (.c)"
            fi
            ;;
        build_mingw_crt.bat|build_mingw_nocrt.bat)
            grep -q -- '-m32' "$lf" || bad "$name: missing -m32"
            grep -q -- '-mconsole' "$lf" || bad "$name: missing -mconsole"
            grep -q -- '-static-libgcc' "$lf" || bad "$name: missing -static-libgcc"
            grep -q -- '-DWINVER=0x0410' "$lf" || bad "$name: missing -DWINVER=0x0410"
            grep -q -- '-D_WIN32_WINNT=0x0410' "$lf" || bad "$name: missing -D_WIN32_WINNT=0x0410"
            grep -q -- '-D_CRT_SECURE_NO_WARNINGS' "$lf" || bad "$name: missing -D_CRT_SECURE_NO_WARNINGS"
            grep -q -- '-D_CRT_NONSTDC_NO_DEPRECATE' "$lf" || bad "$name: missing -D_CRT_NONSTDC_NO_DEPRECATE"
            grep -q -- '-D_WIN32' "$lf" || bad "$name: missing -D_WIN32"
            grep -q -- '@z98_link.rsp' "$lf" || bad "$name: link does not use @z98_link.rsp"
            if grep -E '^gcc .*\.c$' "$lf" | grep -qv ' -c '; then
                bad "$name: gcc compile line lacks -c"
            fi
            ;;
    esac
    case "$name" in
        build_target_crt.bat|build_owc_crt.bat)
            grep -q '\*\.obj' "$lf" || bad "$name: CRT link does not use *.obj"
            ;;
    esac
    if [ "$fail" -eq "$fail_before" ]; then
        ok "$name lint"
    else
        echo "[win-compat] FAIL $name lint (see above)" >&2
    fi
}

for s in build_target_nocrt.bat build_target_crt.bat build_owc_nocrt.bat \
         build_owc_crt.bat build_target.bat build_owc.bat \
         build_mingw_crt.bat build_mingw_nocrt.bat; do
    if [ -f "$WORK/emit/$s" ]; then
        lint_bat "$WORK/emit/$s"
    else
        bad "emitted script missing: $s"
    fi
done

# ---- 4. optional MinGW cross compile --------------------------------------
if [ "$SKIP_CROSS" -eq 0 ] && command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
    cross="$WORK/cross"
    mkdir -p "$cross"
    : >"$WORK/cross.log"
    cross_fail=0
    for f in "$WORK/emit"/*.c; do
        [ -e "$f" ] || continue
        i686-w64-mingw32-gcc -m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long \
            -I "$WORK/emit" -c "$f" -o "$cross/$(basename "${f%.c}").o" >>"$WORK/cross.log" 2>&1 \
            || cross_fail=1
    done
    if [ "$cross_fail" -ne 0 ]; then
        bad "MinGW cross compile failed:"
        sed -n '1,40p' "$WORK/cross.log" >&2
    else
        ok "MinGW cross compile ($(ls "$cross"/*.o 2>/dev/null | wc -l | tr -d ' ') TUs)"
    fi
elif [ "$SKIP_CROSS" -eq 0 ]; then
    echo "[win-compat] SKIP MinGW cross compile (i686-w64-mingw32-gcc absent)"
else
    echo "[win-compat] SKIP MinGW cross compile (--skip-cross)"
fi

# ---- 5. optional import gate ----------------------------------------------
if [ -n "$EXE" ]; then
    if [ ! -f "$EXE" ]; then
        bad "import gate: '$EXE' not found"
    elif bash "$ROOT/scripts/win32_cross/check_win9x_imports.sh" "$EXE" 9x; then
        ok "9x import gate"
    else
        bad "9x import gate failed"
    fi
else
    echo "[win-compat] SKIP import gate (VM-only; pass --exe <operator-built PE>)"
fi

if [ "$fail" -ne 0 ]; then
    echo "WIN_COMPAT GATE FAILED" >&2
    exit 1
fi
echo "WIN_COMPAT GATE OK"
exit 0
