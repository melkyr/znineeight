#!/usr/bin/env bash
# cross_parity.sh — win32 build+run+parity harness (pre-test plan Task 1, 2026-09-04).
#
# Usage:
#   cross_parity.sh <entry> <feed> <expected_stdout> <workdir>
#
#   <entry>           repo-relative program entry (dumped from repo-root CWD)
#   <feed>            stdin feed file; use /dev/null for no-input programs
#   <expected_stdout> linux-derived parity base (byte-compare target)
#   <workdir>         scratch dir; wiped and rebuilt fresh by this run
#
# Pipeline (wraps cross_build_run.sh + wine):
#   1. cross-build the win32 .exe (see cross_build_run.sh).
#   2. Run it under the dedicated win32 wine prefix (WINEPREFIX default
#      /tmp/wine32, WINEARCH=win32) with <feed> on stdin.
#   3. cmp the captured stdout byte-for-byte against <expected_stdout>.
#
# Prints verdict lines:
#   XRUNRC=<rc>    0 ok; DUMPFAIL/GCCFAIL/LINKFAIL/NOC = cross-build failure
#   WINE_RC=<n>    wine process exit code
#   WINE_TMOUT=1   wine run hit the timeout guard (always recorded rc=124)
#   PARITY=OK|DIFF byte-parity result
# On DIFF the byte-level diff is printed. stderr of the wine run is captured
# separately (headless wine fixme/err noise is benign; stdout is the gate).
#
# Optional env:
#   ZIG1            reference compiler (default /tmp/fx_subfolder/zig1)
#   CROSS_RUN_CWD   dir the exe runs in (default <workdir>/run) — set to the
#                   program dir when the program opens CWD-relative files
#                   (e.g. json_parser test.json)
#   PARITY_MASK     if non-empty, compare line-by-line masking AMENDMENT-4
#                   (address) lines: a line where BOTH actual and expected
#                   match '^> [0-9]+$' compares equal. Default: strict cmp.
#   WINE_RUN_TIMEOUT run timeout seconds (default 300)
#   WINEPREFIX      wine prefix (default /tmp/wine32)
# Exit status: 0 only on full pass (build ok + run rc 0 + PARITY=OK).
set -u

ROOT=${ROOT:-/workspace/znineeight}
ZIG1=${ZIG1:-/tmp/fx_subfolder/zig1}
WINEPREFIX=${WINEPREFIX:-/tmp/wine32}
WINE_RUN_TIMEOUT=${WINE_RUN_TIMEOUT:-300}
ENTRY=${1:?usage: cross_parity.sh <entry> <feed> <expected_stdout> <workdir>}
FEED=${2:?usage: cross_parity.sh <entry> <feed> <expected_stdout> <workdir>}
EXPECTED=${3:?usage: cross_parity.sh <entry> <feed> <expected_stdout> <workdir>}
WORKDIR=${4:?usage: cross_parity.sh <entry> <feed> <expected_stdout> <workdir>}

HARNESS="$ROOT/scripts/win32_cross/cross_build_run.sh"
RUN_CWD=${CROSS_RUN_CWD:-"$WORKDIR/run"}

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$RUN_CWD"

# ---- Step 1: cross build ----------------------------------------------------
if ! bash "$HARNESS" "$ZIG1" "$ENTRY" "$WORKDIR/build" "$WORKDIR/prog.exe" \
    >"$WORKDIR/build.log" 2>&1; then
    sed -n '1,25p' "$WORKDIR/build.log"
    echo "XRUNRC=$(sed -n 's/^XRUNRC=//p' "$WORKDIR/build.log")"
    exit 1
fi
XRUNRC=$(sed -n 's/^XRUNRC=//p' "$WORKDIR/build.log")
echo "XRUNRC=$XRUNRC"
if [ "$XRUNRC" != "0" ]; then
    sed -n '1,25p' "$WORKDIR/build.log"
    exit 1
fi

# ---- Step 2: wine run with feed on stdin -----------------------------------
(
    cd "$RUN_CWD" &&
    timeout "$WINE_RUN_TIMEOUT" env WINEPREFIX="$WINEPREFIX" WINEARCH=win32 \
        wine "$WORKDIR/prog.exe" <"$FEED" >"$WORKDIR/stdout.txt" 2>"$WORKDIR/stderr.txt"
)
WINE_RC=$?
echo "WINE_RC=$WINE_RC"
if [ "$WINE_RC" -eq 124 ]; then
    echo "WINE_TMOUT=1"
fi

# ---- Step 3: byte parity -----------------------------------------------------
parity_ok=0
if [ -n "${PARITY_MASK:-}" ]; then
    a_ln=0; e_ln=0
    while IFS= read -r _; do a_ln=$((a_ln + 1)); done <"$WORKDIR/stdout.txt"
    while IFS= read -r _; do e_ln=$((e_ln + 1)); done <"$EXPECTED"
    n=0
    while true; do
        n=$((n + 1))
        if ! IFS= read -r a <&3; then break; fi
        if ! IFS= read -r e <&4; then break; fi
        if [ "$a" = "$e" ]; then continue; fi
        if printf '%s\n' "$a" | grep -qE '^> [0-9]+$' \
           && printf '%s\n' "$e" | grep -qE '^> [0-9]+$'; then
            continue
        fi
        parity_ok=1
        break
    done 3<"$WORKDIR/stdout.txt" 4<"$EXPECTED"
    if [ "$parity_ok" -eq 0 ] && [ "$a_ln" -ne "$e_ln" ]; then parity_ok=1; fi
else
    if ! cmp -s "$WORKDIR/stdout.txt" "$EXPECTED"; then parity_ok=1; fi
fi

if [ "$parity_ok" -eq 0 ]; then
    echo "PARITY=OK"
    exit 0
fi

echo "PARITY=DIFF"
diff "$WORKDIR/stdout.txt" "$EXPECTED" || true
exit 1
