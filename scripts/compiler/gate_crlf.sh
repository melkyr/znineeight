#!/usr/bin/env bash
set -euo pipefail
# scripts/compiler/gate_crlf.sh <built-zig1>
#
# Windows-facing text artifacts MUST be CRLF; the POSIX build_target.sh MUST be
# LF. This gate checks:
#   1. every tracked repo *.bat file;
#   2. every *.bat emitted by `zig1 -osw` (including the MinGW fallback pair),
#      while build_target.sh stays LF;
#   3. a freshly packed Win9x companion zip's win/*.bat, win/*.lnk, win/*.rsp
#      (the latter two only if present) and README.txt; plus the seed tgz's
#      SEED_README.txt.
#
# The zip is produced in a scratch dir by scripts/seed/archive_seed.sh, so this
# gate exercises the actual pack-time normalization rather than a stale
# committed archive. It never touches the repo or the rotated seed.
#
# usage: scripts/compiler/gate_crlf.sh <path/to/zig1_5_clean>

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ZIG1="${1:-}"
[ -n "$ZIG1" ] || { echo "usage: scripts/compiler/gate_crlf.sh <path/to/zig1>" >&2; exit 1; }
[ -x "$ZIG1" ] || { echo "error: zig1 '$ZIG1' is not executable" >&2; exit 1; }
ZIG1="$(cd "$(dirname "$ZIG1")" && pwd)/$(basename "$ZIG1")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_crlf.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok()   { echo "[crlf] OK   $*"; }
bad()  { echo "[crlf] FAIL $*" >&2; fail=1; }

is_crlf() {
    LC_ALL=C awk '/\r$/{ n++; next } { bad++ } END { exit !(bad == 0 && n > 0) }' "$1"
}

is_lf() {
    ! LC_ALL=C grep -q "$(printf '\r')" "$1"
}

check_crlf() {
    local label="$1" file="$2"
    if is_crlf "$file"; then ok "$label CRLF"; else bad "$label is not CRLF: $file"; fi
}

check_lf() {
    local label="$1" file="$2"
    if is_lf "$file"; then ok "$label LF"; else bad "$label contains CR: $file"; fi
}

# ---- 1. tracked repo batch files -----------------------------------------
cd "$ROOT"
repo_bats=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    repo_bats=$((repo_bats + 1))
    check_crlf "repo $f" "$ROOT/$f"
done < <(git ls-files '*.bat')
[ "$repo_bats" -gt 0 ] || bad "no tracked repo *.bat files found"

# ---- 2. emitted -osw scripts ---------------------------------------------
mkdir -p "$WORK/emit"
( cd "$ROOT" && timeout 300 "$ZIG1" -osw -o "$WORK/emit" sf/src/main.zig ) \
    >"$WORK/emit.log" 2>&1 \
    || { echo "error: emitted -osw dump failed" >&2; sed -n '1,30p' "$WORK/emit.log" >&2; exit 1; }
rm -f "$WORK/emit"/.zig1_*.tmp

for s in build_target_nocrt.bat build_target_crt.bat build_owc_nocrt.bat \
         build_owc_crt.bat build_target.bat build_owc.bat \
         build_mingw_crt.bat build_mingw_nocrt.bat; do
    if [ -f "$WORK/emit/$s" ]; then
        check_crlf "emitted $s" "$WORK/emit/$s"
    else
        bad "emitted script missing: $s"
    fi
done
if [ -f "$WORK/emit/build_target.sh" ]; then
    check_lf "emitted build_target.sh" "$WORK/emit/build_target.sh"
else
    bad "emitted script missing: build_target.sh"
fi

# ---- 3. fresh seed tgz + Win9x zip via archive_seed ----------------------
mkdir -p "$WORK/gen"
( cd "$ROOT" && timeout 300 "$ZIG1" -ffast --dump-c89 --output-dir "$WORK/gen" sf/src/main.zig ) \
    >"$WORK/gen.log" 2>&1 \
    || { echo "error: gen-dir dump failed" >&2; sed -n '1,30p' "$WORK/gen.log" >&2; exit 1; }
rm -f "$WORK/gen"/.zig1_*.tmp

bash "$ROOT/scripts/seed/archive_seed.sh" "$ZIG1" "$WORK/gen" "$WORK/zig1-seed.tgz" \
    --win9x-zip "$WORK/zig1_seed_w9.zip" >"$WORK/archive.log" 2>&1 \
    || { echo "error: archive_seed.sh failed" >&2; tail -30 "$WORK/archive.log" >&2; exit 1; }

# SEED_README.txt (tgz)
seed_readme="$(tar -tzf "$WORK/zig1-seed.tgz" | grep -E '(^|/)SEED_README\.txt$' | head -n 1 || true)"
if [ -n "$seed_readme" ]; then
    tar -xzf "$WORK/zig1-seed.tgz" -O "$seed_readme" >"$WORK/SEED_README.txt"
    check_crlf "seed SEED_README.txt" "$WORK/SEED_README.txt"
else
    bad "SEED_README.txt missing from seed tgz"
fi

# win/*.bat + win/*.lnk + win/*.rsp + README.txt (zip)
zip_entries="$(zipinfo -1 "$WORK/zig1_seed_w9.zip")"
n_zip_bats=0
n_zip_lnk=0
n_zip_rsp=0
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
        */win/*.bat|win/*.bat)
            n_zip_bats=$((n_zip_bats + 1))
            unzip -p "$WORK/zig1_seed_w9.zip" "$entry" >"$WORK/zip_entry"
            check_crlf "zip $entry" "$WORK/zip_entry"
            ;;
        */win/*.lnk|win/*.lnk)
            n_zip_lnk=$((n_zip_lnk + 1))
            unzip -p "$WORK/zig1_seed_w9.zip" "$entry" >"$WORK/zip_entry"
            check_crlf "zip $entry" "$WORK/zip_entry"
            ;;
        */win/*.rsp|win/*.rsp)
            n_zip_rsp=$((n_zip_rsp + 1))
            unzip -p "$WORK/zig1_seed_w9.zip" "$entry" >"$WORK/zip_entry"
            check_crlf "zip $entry" "$WORK/zip_entry"
            ;;
        */README.txt|README.txt)
            unzip -p "$WORK/zig1_seed_w9.zip" "$entry" >"$WORK/zip_entry"
            check_crlf "zip $entry" "$WORK/zip_entry"
            ;;
    esac
done <<EOF
$zip_entries
EOF

[ "$n_zip_bats" -gt 0 ] || bad "zip has no win/*.bat entries"
echo "[crlf] zip win entries: $n_zip_bats .bat, $n_zip_lnk .lnk, $n_zip_rsp .rsp (lnk/rsp are build-time products, absent is normal)"

for s in build_target_crt.bat build_owc_crt.bat build_mingw_crt.bat build_mingw_nocrt.bat; do
    if printf '%s\n' "$zip_entries" | grep -qE "(^|/)win/$s$"; then
        ok "zip ships win/$s"
    else
        bad "zip missing win/$s"
    fi
done

[ "$fail" = 0 ] || { echo "CRLF GATE FAILED" >&2; exit 1; }
echo "CRLF GATE OK"
