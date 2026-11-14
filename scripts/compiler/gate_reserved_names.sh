#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_reserved_names.sh [zig1]
#
# Reserved DOS device name gate (Task B). Proves:
#   1. CLI: a .zig file whose stem is each reserved name (CON, PRN, AUX, NUL,
#      COM1..COM9, LPT1..LPT9) is rejected with the one clean error line,
#      rc=2, and emits no .c;
#   2. CLI: a legal name still compiles fine (rc=0, .c emitted);
#   3. import: a module importing a reserved name reports the clean
#      error[3048] reserved diagnostic (never the misleading "could not
#      resolve imported file" text) and emits no .c;
#   4. import: a module importing a legal sibling still resolves (rc=0);
#   5. case-insensitivity: AUX.zig / aux.ZIG / CoN.zig are all rejected;
#   6. non-reserved near-misses are accepted: auxx.zig, myaux.zig,
#      auxiliary.zig, console.zig, null.zig, com10.zig, lpt0.zig.
#
# The banner-on-every-run rule still applies: every stderr carries the
# `Z98 Compiler 2026` banner before the checked error line.
#
# `zig1` defaults to $ROOT/zig1.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
if [ -z "$ZIG1" ]; then
    if [ -x "$ROOT/zig1" ]; then
        ZIG1="$ROOT/zig1"
    else
        echo "error: no zig1 given and $ROOT/zig1 not executable" >&2
        echo "usage: scripts/compiler/gate_reserved_names.sh [path/to/zig1]" >&2
        exit 2
    fi
fi
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_reserved_names.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

note() { echo "[gate_reserved_names] $*"; }
bad()  { echo "[gate_reserved_names] FAIL: $*" >&2; fail=1; }

PROG='pub fn main() void { var x: i32 = 1; _ = x; }'
MOD='pub const K: i32 = 7;'

c_count() {
    find "$1" -maxdepth 1 -type f -name '*.c' 2>/dev/null | wc -l | tr -d ' '
}

# expect_cli_rejected <label> <dir> <file-as-passed> <exact-error-line>
expect_cli_rejected() {
    local label="$1" dir="$2" file="$3" want="$4" out rc
    out="$dir/out"
    mkdir -p "$out"
    set +e
    ( cd "$dir" && timeout 120 "$ZIG1" -o "$out" "$file" ) \
        >"$dir/stdout" 2>"$dir/stderr"
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || bad "$label: rc=$rc want 2"
    grep -qxF "$want" "$dir/stderr" || bad "$label: missing exact line '$want' (stderr: $(tr '\n' '|' <"$dir/stderr"))"
    grep -q 'Z98 Compiler 2026' "$dir/stderr" || bad "$label: banner missing (banner-on-every-run rule)"
    [ "$(grep -c '^error:' "$dir/stderr" || true)" -eq 1 ] || bad "$label: expected exactly one clean 'error:' line"
    grep -q 'could not read input file' "$dir/stderr" && bad "$label: misleading 'could not read input file' text present"
    [ "$(c_count "$out")" -eq 0 ] || bad "$label: emitted $(c_count "$out") .c file(s), want 0"
}

# expect_cli_accepted <label> <dir> <file-as-passed>
expect_cli_accepted() {
    local label="$1" dir="$2" file="$3" out rc
    out="$dir/out"
    mkdir -p "$out"
    set +e
    ( cd "$dir" && timeout 120 "$ZIG1" -o "$out" "$file" ) \
        >"$dir/stdout" 2>"$dir/stderr"
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || bad "$label: rc=$rc want 0 (stderr: $(tr '\n' '|' <"$dir/stderr"))"
    [ "$(c_count "$out")" -ge 1 ] || bad "$label: emitted no .c, want >= 1"
}

# expect_import <label> <dir> <import-target> <reject:1|0> <want-error-line or ->]
expect_import() {
    local label="$1" dir="$2" target="$3" reject="$4" want="${5:-}" out rc
    out="$dir/out"
    mkdir -p "$out"
    printf 'const m = @import("%s");\npub fn main() void { var x: i32 = m.K; _ = x; }\n' "$target" >"$dir/main.zig"
    set +e
    ( cd "$dir" && timeout 120 "$ZIG1" -o "$out" "$dir/main.zig" ) \
        >"$dir/stdout" 2>"$dir/stderr"
    rc=$?
    set -e
    if [ "$reject" -eq 1 ]; then
        [ "$rc" -ne 0 ] || bad "$label: rc=0 want nonzero"
        grep -qxF "$want" "$dir/stderr" || bad "$label: missing exact line '$want' (stderr: $(tr '\n' '|' <"$dir/stderr"))"
        grep -q 'could not resolve imported file' "$dir/stderr" \
            && bad "$label: misleading 'could not resolve imported file' text present"
        [ "$(c_count "$out")" -eq 0 ] || bad "$label: emitted $(c_count "$out") .c file(s), want 0"
    else
        [ "$rc" -eq 0 ] || bad "$label: rc=$rc want 0 (stderr: $(tr '\n' '|' <"$dir/stderr"))"
        [ "$(c_count "$out")" -ge 1 ] || bad "$label: emitted no .c, want >= 1"
    fi
}

note "zig1: $ZIG1"

# ---- 1. CLI: every reserved stem rejected ----
RESERVED=(CON PRN AUX NUL COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9
          LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9)
for name in "${RESERVED[@]}"; do
    d="$WORK/cli_$name"
    mkdir -p "$d"
    printf '%s\n' "$PROG" >"$d/$name.zig"
    expect_cli_rejected "cli $name.zig" "$d" "$name.zig" \
        "error: reserved DOS device name in input file path: $name.zig"
done
note "ok CLI: ${#RESERVED[@]} reserved stems rejected (rc=2, clean line, 0 .c)"

# ---- 1b. CLI: reserved stem with no file on disk is still the reserved error ----
d="$WORK/cli_missing"
mkdir -p "$d"
expect_cli_rejected "cli missing LPT7.zig" "$d" "LPT7.zig" \
    "error: reserved DOS device name in input file path: LPT7.zig"

# ---- 2. CLI: legal name compiles ----
d="$WORK/cli_ok"
mkdir -p "$d"
printf '%s\n' "$PROG" >"$d/hello.zig"
expect_cli_accepted "cli hello.zig" "$d" "hello.zig"
note "ok CLI: legal name compiles (rc=0)"

# ---- 3. import: reserved name rejected ----
for name in AUX NUL COM1; do
    d="$WORK/imp_$name"
    mkdir -p "$d"
    printf '%s\n' "$MOD" >"$d/$name.zig"
    expect_import "import $name.zig (file exists)" "$d" "$name.zig" 1 \
        "error[3048]: reserved DOS device name in import path: $name.zig"
done
d="$WORK/imp_prn_absent"
mkdir -p "$d"
expect_import "import PRN.zig (file absent)" "$d" "PRN.zig" 1 \
    "error[3048]: reserved DOS device name in import path: PRN.zig"
note "ok import: reserved names rejected (clean error[3048], 0 .c)"

# ---- 4. import: legal sibling resolves ----
for name in ok.zig helper.zig auxmod.zig; do
    d="$WORK/imp_ok_${name//./_}"
    mkdir -p "$d"
    printf '%s\n' "$MOD" >"$d/$name"
    expect_import "import $name" "$d" "$name" 0
done
note "ok import: legal siblings resolve (rc=0)"

# ---- 5. case-insensitivity ----
for name in AUX.zig aux.ZIG CoN.zig; do
    d="$WORK/ci_${name//./_}"
    mkdir -p "$d"
    printf '%s\n' "$PROG" >"$d/$name"
    expect_cli_rejected "cli $name" "$d" "$name" \
        "error: reserved DOS device name in input file path: $name"
    d2="$WORK/ci_imp_${name//./_}"
    mkdir -p "$d2"
    printf '%s\n' "$MOD" >"$d2/$name"
    expect_import "import $name" "$d2" "$name" 1 \
        "error[3048]: reserved DOS device name in import path: $name"
done
note "ok case-insensitivity: AUX.zig / aux.ZIG / CoN.zig rejected (CLI + import)"

# ---- 6. near-misses accepted ----
for name in auxx.zig myaux.zig auxiliary.zig console.zig null.zig com10.zig lpt0.zig; do
    d="$WORK/nm_${name//./_}"
    mkdir -p "$d"
    printf '%s\n' "$PROG" >"$d/$name"
    expect_cli_accepted "cli $name" "$d" "$name"
    d2="$WORK/nm_imp_${name//./_}"
    mkdir -p "$d2"
    printf '%s\n' "$MOD" >"$d2/$name"
    expect_import "import $name" "$d2" "$name" 0
done
note "ok near-misses: auxx/myaux/auxiliary/console/null/com10/lpt0 accepted (CLI + import)"

if [ "$fail" -eq 0 ]; then
    echo "RESERVED_NAMES GATE OK"
    exit 0
fi
echo "RESERVED_NAMES GATE FAILED" >&2
exit 1
