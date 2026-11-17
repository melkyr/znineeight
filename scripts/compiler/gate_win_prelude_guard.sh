#!/usr/bin/env bash
# scripts/compiler/gate_win_prelude_guard.sh [path/to/zig1]
#
# Windows console-prelude guard gate (Task 3b-H, OWC E1100 hotfix):
#   1. emit repro/mi_matrix/win_prelude_guard_xmod (console builtin + std_net)
#      with `-osw --dump-c89`;
#   2. prove the fixture reproduces the include order
#      module.h -> std_net_*.h -> net_prelude.h -> <windows.h> BEFORE the
#      console block in the module .c;
#   3. assert each of the five console-prelude macros is wrapped by
#      `#ifndef <NAME>` immediately before its `#define` (values unchanged),
#      and that the `#ifdef _WIN32` / `#else stdio` / `#endif` structure and
#      the trailing `extern void std_print_len(...)` declaration are intact;
#   4. compile the emitted module C with i686-w64-mingw32-gcc when available.
#      Plain MinGW only WARNS on the macro redefinitions (rc=0), so it does not
#      reproduce the OpenWatcom E1100 hard error; the textual guard assertions
#      above are the non-vacuous failure signal.
#
# usage: scripts/compiler/gate_win_prelude_guard.sh [path/to/zig1]

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then ZIG1="$ROOT/zig1"; else
        echo "usage: scripts/compiler/gate_win_prelude_guard.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }
ZIG1="$(cd "$(dirname "$ZIG1")" && pwd)/$(basename "$ZIG1")"

ENTRY_REL="repro/mi_matrix/win_prelude_guard_xmod/main.zig"
ENTRY="$ROOT/$ENTRY_REL"
[ -f "$ENTRY" ] || { echo "error: fixture '$ENTRY_REL' not found" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_win_prelude_guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0
ok()  { echo "[win-prelude-guard] OK   $*"; }
bad() { echo "[win-prelude-guard] FAIL $*" >&2; fail=1; }

# ---- 1. emit ---------------------------------------------------------------
mkdir -p "$WORK/emit"
( cd "$ROOT" && timeout 600 "$ZIG1" -osw --dump-c89 --output-dir "$WORK/emit" "$ENTRY_REL" ) \
    >"$WORK/emit.log" 2>&1
rc=$?
rm -f "$WORK"/emit/.zig1_*.tmp
if [ "$rc" -ne 0 ]; then
    bad "fixture emission rc=$rc (see below)"
    sed -n '1,40p' "$WORK/emit.log" >&2
    echo "WIN_PRELUDE_GUARD GATE FAILED" >&2
    exit 1
fi
ok "fixture emission ($ENTRY_REL)"

CONSOLE_C="$(grep -l '#define NTDDI_VERSION' "$WORK"/emit/*.c 2>/dev/null | head -n1 || true)"
if [ -z "$CONSOLE_C" ]; then
    bad "no emitted .c contains the console prelude (NTDDI_VERSION)"
    echo "WIN_PRELUDE_GUARD GATE FAILED" >&2
    exit 1
fi
CONSOLE_H="${CONSOLE_C%.c}.h"
ok "console prelude module: $(basename "$CONSOLE_C")"

# ---- 2. reproduce the conflict include order ------------------------------
hdr_inc="$(sed -n '1p' "$CONSOLE_C")"
case "$hdr_inc" in
    '#include "'*'.h"') ;;
    *) bad "console module .c does not start with its module header: $hdr_inc" ;;
esac
stdnet_h="$(basename "$(grep -o 'std_net_[0-9A-F]*\.h' "$CONSOLE_H" | head -n1)")"
if [ -z "$stdnet_h" ]; then
    bad "console module header does not include a std_net_*.h (fixture lost std_net)"
else
    if grep -q '#include <net_prelude.h>' "$WORK/emit/$stdnet_h"; then
        ok "include order: $hdr_inc -> $stdnet_h -> <net_prelude.h>"
    else
        bad "$stdnet_h does not include <net_prelude.h>"
    fi
fi
if grep -q '#include <windows.h>' "$WORK/emit/net_prelude.h" 2>/dev/null; then
    ok "include order: net_prelude.h -> <windows.h> before console block"
else
    bad "net_prelude.h does not include <windows.h>"
fi

console_line="$(grep -n '#define NTDDI_VERSION' "$CONSOLE_C" | head -n1 | cut -d: -f1)"
if [ -n "$stdnet_h" ] && grep -q "$stdnet_h" "$CONSOLE_H"; then
    if [ -n "$console_line" ]; then
        ok "console block follows the std_net header include"
    else
        bad "console block not found"
    fi
fi

# ---- 3. five macros guarded ----------------------------------------------
guarded_ok=1
for name in WINVER _WIN32_WINDOWS _WIN32_WINNT NTDDI_VERSION WIN32_LEAN_AND_MEAN; do
    found=0
    while IFS=: read -r ln _; do
        [ -n "$ln" ] || continue
        next="$(sed -n "$((ln + 1))p" "$CONSOLE_C")"
        case "$next" in
            "#define $name"|"#define $name "*)
                if [ "$found" -eq 0 ]; then
                    found=1
                    ok "$name guarded (#ifndef immediately before #define)"
                fi
                ;;
        esac
    done < <(grep -nE "^#ifndef ${name}$" "$CONSOLE_C" || true)
    if [ "$found" -eq 0 ]; then
        bad "$name is not guarded by '#ifndef $name' immediately before '#define'"
        guarded_ok=0
    fi
done
if [ "$guarded_ok" -eq 1 ]; then
    ok "all five console-prelude macros guarded"
fi

# Values unchanged.
grep -qx '#define WINVER 0x0410' "$CONSOLE_C" || bad "WINVER value changed"
grep -qx '#define _WIN32_WINDOWS 0x0410' "$CONSOLE_C" || bad "_WIN32_WINDOWS value changed"
grep -qx '#define _WIN32_WINNT 0x0400' "$CONSOLE_C" || bad "_WIN32_WINNT value changed"
grep -qx '#define NTDDI_VERSION 0x04000000' "$CONSOLE_C" || bad "NTDDI_VERSION value changed"
grep -qx '#define WIN32_LEAN_AND_MEAN' "$CONSOLE_C" || bad "WIN32_LEAN_AND_MEAN value changed"

# Structure unchanged: #ifdef _WIN32 / #else stdio / #endif + trailing decl.
grep -qx '#ifdef _WIN32' "$CONSOLE_C" || bad "missing '#ifdef _WIN32'"
grep -qx '#else' "$CONSOLE_C" || bad "missing '#else'"
grep -qx '#include <stdio.h>' "$CONSOLE_C" || bad "missing '#include <stdio.h>'"
grep -qx '#endif' "$CONSOLE_C" || bad "missing '#endif'"
grep -qx 'extern void std_print_len(const char\* s, unsigned int len);' "$CONSOLE_C" \
    || bad "missing trailing std_print_len declaration"
if [ "$fail" -eq 0 ]; then
    ok "console prelude structure unchanged"
fi

# ---- 4. MinGW cross compile (guarded emission must build) ------------------
if command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
    if i686-w64-mingw32-gcc -m32 -std=c89 -I "$WORK/emit" -c "$CONSOLE_C" \
        -o "$WORK/console.o" >"$WORK/mingw.log" 2>&1; then
        if grep -q '"NTDDI_VERSION" redefined' "$WORK/mingw.log"; then
            bad "MinGW still reports a NTDDI_VERSION redefinition"
        else
            ok "MinGW -m32 -std=c89 -c (no macro redefinition warnings)"
        fi
    else
        bad "MinGW -m32 -std=c89 -c failed"
        sed -n '1,40p' "$WORK/mingw.log" >&2
    fi
    echo "[win-prelude-guard] NOTE plain MinGW only warns on the unguarded macros (rc=0);"
    echo "[win-prelude-guard]      OWC E1100 is not reproduced by this compiler, so the"
    echo "[win-prelude-guard]      textual #ifndef assertions carry the non-vacuity."
else
    echo "[win-prelude-guard] SKIP MinGW cross compile (i686-w64-mingw32-gcc absent)"
fi

if [ "$fail" -ne 0 ]; then
    echo "WIN_PRELUDE_GUARD GATE FAILED" >&2
    exit 1
fi
echo "WIN_PRELUDE_GUARD GATE OK"
exit 0
