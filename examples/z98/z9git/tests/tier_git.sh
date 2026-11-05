#!/bin/sh
# tier_git.sh -- Phase 3 Task 7 gate for the z9git local CLI.
#
# Builds examples/z98/z9git/main.zig with a seed-built zig1, then exercises the
# local transports against the committed Task 6 fixtures:
#   - clone packed_repo: copied pack+idx bytes, copied refs/HEAD, worktree
#     matches goldens/packed.lstree, log golden, checkout <branch> golden
#     (tracked-but-absent files removed, untracked files left alone);
#   - clone loose_repo: loose objects copied verbatim (SHA-1 names preserved);
#   - file:// clone, clone-from-worktree source, packed-refs-only source;
#   - -h rc0, bad args rc1, and the not-yet-implemented HTTP transport rc2;
#   - Windows: bare -osw emit, MinGW no-CRT build through the emitted
#     build_target.sh, check_win9x_imports.sh ... 9x PASS, then Wine clone+log
#     on packed_repo. A no-CRT build/run failure is a hard FAIL (never a
#     CRT/nt fallback).
#
# The committed fixture bytes are consumed as-is; gen_repos.sh is dev-time
# only. Git 2.39 is used for goldens/inspection only: the clone itself never
# shells out to git.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG       seed-built zig1_5_clean (default /tmp/p3_t7_base/zig1_5_clean)
#      OUT       scratch dir (default /tmp/z9git_tier)
#      WINEPREFIX default $OUT/wineprefix

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APP_DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/p3_t7_base/zig1_5_clean}"
OUT="${OUT:-/tmp/z9git_tier}"
TD="$APP_DIR/tests/testdata"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
ENTRY="examples/z98/z9git/main.zig"
WINEPREFIX="${WINEPREFIX:-$OUT/wineprefix}"
export WINEPREFIX
export WINEARCH=win32
export WINEDEBUG="${WINEDEBUG:--all}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

finish() {
    echo
    echo "== tier_git summary: $PASSES passed, $FAILS failed =="
    if [ "$FAILS" -ne 0 ]; then
        echo "TIER_GIT FAIL"
        exit 1
    fi
    echo "TIER_GIT PASS"
    exit 0
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t7_base"
    exit 1
fi
for tool in git cmp find sort wine i686-w64-mingw32-gcc i686-w64-mingw32-objdump; do
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

check_worktree() {
    cw_name="$1"
    cw_dest="$2"
    cw_git="$3"
    cw_lstree="$4"
    cw_files="$OUT/linux/$cw_name.files"
    cw_want="$OUT/linux/$cw_name.want"
    ( cd "$cw_dest" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | sort ) > "$cw_files"
    awk '{print $4}' "$cw_lstree" | sort > "$cw_want"
    if cmp -s "$cw_files" "$cw_want"; then
        pass_case "$cw_name worktree path list matches golden"
    else
        fail_case "$cw_name worktree path list differs from golden"
        diff "$cw_want" "$cw_files" | sed 's/^/       /' | head -20
    fi
    awk '{print $3" "$4}' "$cw_lstree" > "$OUT/linux/$cw_name.blobs"
    while IFS=' ' read -r cw_id cw_path; do
        if git --git-dir="$cw_git" cat-file blob "$cw_id" | cmp -s - "$cw_dest/$cw_path"; then
            pass_case "$cw_name $cw_path contents match git blob"
        else
            fail_case "$cw_name $cw_path contents differ from git blob"
        fi
    done < "$OUT/linux/$cw_name.blobs"
}

echo "== build z9git with the seed compiler =="
if ! "$ZIG" -fsafe -o "$OUT/bin" "$ENTRY" >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -40 "$OUT/zig.log" | sed 's/^/       /'
    FAILS=$((FAILS + 1))
    finish
fi
if ! sh "$OUT/bin/build_target.sh" linux "$OUT/bin/prog" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -40 "$OUT/build.log" | sed 's/^/       /'
    FAILS=$((FAILS + 1))
    finish
fi
PROG="$OUT/bin/prog"
[ -x "$PROG" ] || { echo "FAIL: $PROG not built"; exit 1; }
pass_case "Linux build produced $PROG"

echo "== CLI contract =="
"$PROG" -h >"$OUT/linux/help.out" 2>"$OUT/linux/help.err"
HELP_RC=$?
if [ "$HELP_RC" -eq 0 ] && grep -q 'usage: z9git' "$OUT/linux/help.out"; then
    pass_case "-h exit 0 and prints usage"
else
    fail_case "-h exit 0 and prints usage (rc=$HELP_RC)"
fi

"$PROG" >"$OUT/linux/noargs.out" 2>&1
NOARGS_RC=$?
if [ "$NOARGS_RC" -eq 1 ]; then
    pass_case "bad args (no command) exit 1"
else
    fail_case "bad args (no command) exit 1 (got $NOARGS_RC)"
fi

"$PROG" clone >"$OUT/linux/nocloneargs.out" 2>&1
NOCLONE_RC=$?
if [ "$NOCLONE_RC" -eq 1 ]; then
    pass_case "bad args (clone without url) exit 1"
else
    fail_case "bad args (clone without url) exit 1 (got $NOCLONE_RC)"
fi

"$PROG" checkout >"$OUT/linux/nocheckoutargs.out" 2>&1
NOCHECKOUT_RC=$?
if [ "$NOCHECKOUT_RC" -eq 1 ]; then
    pass_case "bad args (checkout without ref) exit 1"
else
    fail_case "bad args (checkout without ref) exit 1 (got $NOCHECKOUT_RC)"
fi

rm -rf "$OUT/linux/http_clone"
"$PROG" clone http://example.invalid/repo.git "$OUT/linux/http_clone" >"$OUT/linux/http.out" 2>&1
HTTP_RC=$?
if [ "$HTTP_RC" -eq 2 ] && [ ! -e "$OUT/linux/http_clone" ]; then
    pass_case "http:// transport is a clear rc2 error (Task 8)"
else
    fail_case "http:// transport rc2 without side effects (got $HTTP_RC)"
fi

echo "== clone packed_repo =="
PACKED="$OUT/linux/clone_packed"
rm -rf "$PACKED"
"$PROG" clone "$TD/packed_repo" "$PACKED" >"$OUT/linux/clone_packed.log" 2>&1
PACKED_RC=$?
if [ "$PACKED_RC" -eq 0 ]; then
    pass_case "clone packed_repo exit 0"
else
    fail_case "clone packed_repo exit 0 (got $PACKED_RC)"
    tail -10 "$OUT/linux/clone_packed.log" | sed 's/^/       /'
fi

if [ -d "$PACKED/.git/objects/pack" ]; then
    pass_case "clone created .git/objects/pack"
else
    fail_case "clone did not create .git/objects/pack"
fi

PACKED_LAYOUT=1
for f in "$TD/packed_repo"/objects/pack/*.pack "$TD/packed_repo"/objects/pack/*.idx; do
    bn=$(basename "$f")
    if cmp -s "$f" "$PACKED/.git/objects/pack/$bn"; then
        pass_case "packed layout copied $bn verbatim"
    else
        fail_case "packed layout missing/different $bn"
        PACKED_LAYOUT=0
    fi
done
if [ "$(find "$PACKED/.git/objects/pack" -maxdepth 1 -type f | wc -l)" -eq 4 ]; then
    pass_case "packed layout has exactly the 2 fixture packs + 2 idx files"
else
    fail_case "packed layout file count is not 4"
fi

if cmp -s "$TD/packed_repo/HEAD" "$PACKED/.git/HEAD"; then
    pass_case "packed HEAD copied verbatim"
else
    fail_case "packed HEAD differs from source"
fi

if diff -r "$TD/packed_repo/refs" "$PACKED/.git/refs" >/dev/null 2>&1; then
    pass_case "packed refs copied verbatim"
else
    fail_case "packed refs differ from source"
fi

check_worktree packed "$PACKED" "$TD/packed_repo" "$TD/goldens/packed.lstree"

cat > "$OUT/linux/packed_log.want" <<'EOF'
67492fc z9 fixture 2005-04-07T22:13:13+0000 packed revision 6
c2f7b0f z9 fixture 2005-04-07T22:13:13+0000 packed revision 5
8dea519 z9 fixture 2005-04-07T22:13:13+0000 packed revision 4
08a0d1d z9 fixture 2005-04-07T22:13:13+0000 packed revision 3
d5b9a9b z9 fixture 2005-04-07T22:13:13+0000 packed revision 2
c6ce2b1 z9 fixture 2005-04-07T22:13:13+0000 initial packed history
EOF
( cd "$PACKED" && "$PROG" log ) >"$OUT/linux/packed_log.out" 2>"$OUT/linux/packed_log.err"
PACKED_LOG_RC=$?
if [ "$PACKED_LOG_RC" -eq 0 ] && cmp -s "$OUT/linux/packed_log.want" "$OUT/linux/packed_log.out"; then
    pass_case "log golden from cloned packed_repo"
else
    fail_case "log golden from cloned packed_repo (rc=$PACKED_LOG_RC)"
    diff "$OUT/linux/packed_log.want" "$OUT/linux/packed_log.out" | sed 's/^/       /' | head -20
fi

echo "== checkout branch in cloned packed_repo =="
printf 'untracked payload\n' > "$PACKED/untracked.txt"
( cd "$PACKED" && "$PROG" checkout refdelta ) >"$OUT/linux/checkout_refdelta.log" 2>&1
CHECKOUT_RC=$?
if [ "$CHECKOUT_RC" -eq 0 ]; then
    pass_case "checkout refdelta exit 0"
else
    fail_case "checkout refdelta exit 0 (got $CHECKOUT_RC)"
    tail -10 "$OUT/linux/checkout_refdelta.log" | sed 's/^/       /'
fi

printf 'ref: refs/heads/refdelta\n' > "$OUT/linux/head_refdelta.want"
if cmp -s "$OUT/linux/head_refdelta.want" "$PACKED/.git/HEAD"; then
    pass_case "checkout updates HEAD to refs/heads/refdelta"
else
    fail_case "checkout did not update HEAD to refs/heads/refdelta"
fi

for f in ref_a.txt ref_b.txt; do
    if [ -f "$PACKED/$f" ]; then
        pass_case "checkout materialized $f"
    else
        fail_case "checkout did not materialize $f"
    fi
done
for f in big.txt docs/notes.txt; do
    if [ ! -e "$PACKED/$f" ]; then
        pass_case "checkout removed tracked-but-absent $f"
    else
        fail_case "checkout left tracked-but-absent $f"
    fi
done
if [ -f "$PACKED/untracked.txt" ] && [ "$(cat "$PACKED/untracked.txt")" = "untracked payload" ]; then
    pass_case "checkout left untracked.txt untouched"
else
    fail_case "checkout touched/removed untracked.txt"
fi
if git --git-dir="$TD/packed_repo" cat-file blob 4871f733057c0a148fd756edff15c9002956b8b8 | cmp -s - "$PACKED/ref_a.txt"; then
    pass_case "checkout ref_a.txt contents match git blob"
else
    fail_case "checkout ref_a.txt contents mismatch"
fi
if git --git-dir="$TD/packed_repo" cat-file blob 2a34a935fe6c5f07ed6b3ac4505353d63cd3c978 | cmp -s - "$PACKED/ref_b.txt"; then
    pass_case "checkout ref_b.txt contents match git blob"
else
    fail_case "checkout ref_b.txt contents mismatch"
fi

cat > "$OUT/linux/refdelta_log.want" <<'EOF'
6cb6ec0 z9 fixture 2005-04-07T22:13:13+0000 ref delta commit
EOF
( cd "$PACKED" && "$PROG" log ) >"$OUT/linux/refdelta_log.out" 2>&1
if cmp -s "$OUT/linux/refdelta_log.want" "$OUT/linux/refdelta_log.out"; then
    pass_case "log golden from refdelta branch"
else
    fail_case "log golden from refdelta branch"
    diff "$OUT/linux/refdelta_log.want" "$OUT/linux/refdelta_log.out" | sed 's/^/       /' | head -20
fi

( cd "$PACKED" && "$PROG" checkout master ) >"$OUT/linux/checkout_master.log" 2>&1
CHECKOUT_MASTER_RC=$?
printf 'ref: refs/heads/master\n' > "$OUT/linux/head_master.want"
if [ "$CHECKOUT_MASTER_RC" -eq 0 ] && cmp -s "$OUT/linux/head_master.want" "$PACKED/.git/HEAD"; then
    pass_case "checkout master restores HEAD"
else
    fail_case "checkout master restores HEAD (rc=$CHECKOUT_MASTER_RC)"
fi
for f in ref_a.txt ref_b.txt; do
    if [ ! -e "$PACKED/$f" ]; then
        pass_case "checkout master removed tracked-but-absent $f"
    else
        fail_case "checkout master left tracked-but-absent $f"
    fi
done
if [ -f "$PACKED/untracked.txt" ]; then
    pass_case "checkout master left untracked.txt untouched"
else
    fail_case "checkout master removed untracked.txt"
fi
rm -f "$PACKED/untracked.txt"
check_worktree packed_after_master "$PACKED" "$TD/packed_repo" "$TD/goldens/packed.lstree"

echo "== clone loose_repo =="
LOOSE="$OUT/linux/clone_loose"
rm -rf "$LOOSE"
"$PROG" clone "$TD/loose_repo" "$LOOSE" >"$OUT/linux/clone_loose.log" 2>&1
LOOSE_RC=$?
if [ "$LOOSE_RC" -eq 0 ]; then
    pass_case "clone loose_repo exit 0"
else
    fail_case "clone loose_repo exit 0 (got $LOOSE_RC)"
    tail -10 "$OUT/linux/clone_loose.log" | sed 's/^/       /'
fi

( cd "$TD/loose_repo/objects" && find . -type f | sort ) > "$OUT/linux/loose_objects.want"
( cd "$LOOSE/.git/objects" && find . -type f | sort ) > "$OUT/linux/loose_objects.out"
if cmp -s "$OUT/linux/loose_objects.want" "$OUT/linux/loose_objects.out"; then
    pass_case "loose object SHA-1 names copied verbatim"
else
    fail_case "loose object SHA-1 names differ from source"
    diff "$OUT/linux/loose_objects.want" "$OUT/linux/loose_objects.out" | sed 's/^/       /' | head -20
fi
while IFS= read -r obj; do
    if cmp -s "$TD/loose_repo/objects/$obj" "$LOOSE/.git/objects/$obj"; then
        pass_case "loose object $obj bytes match source"
    else
        fail_case "loose object $obj bytes differ from source"
    fi
done < "$OUT/linux/loose_objects.want"
if find "$LOOSE/.git/objects" -type f \( -name '*.pack' -o -name '*.idx' \) | grep -q .; then
    fail_case "loose clone unexpectedly contains pack/idx files"
else
    pass_case "loose clone contains no pack/idx files"
fi

check_worktree loose "$LOOSE" "$TD/loose_repo" "$TD/goldens/loose.lstree"

cat > "$OUT/linux/loose_log.want" <<'EOF'
cb94782 z9 fixture 2005-04-07T22:13:13+0000 second loose revision
ce8a17d z9 fixture 2005-04-07T22:13:13+0000 initial loose history
EOF
( cd "$LOOSE" && "$PROG" log ) >"$OUT/linux/loose_log.out" 2>&1
if cmp -s "$OUT/linux/loose_log.want" "$OUT/linux/loose_log.out"; then
    pass_case "log golden from cloned loose_repo"
else
    fail_case "log golden from cloned loose_repo"
    diff "$OUT/linux/loose_log.want" "$OUT/linux/loose_log.out" | sed 's/^/       /' | head -20
fi

echo "== file:// and worktree sources =="
FILE_CLONE="$OUT/linux/clone_file"
rm -rf "$FILE_CLONE"
"$PROG" clone "file://$TD/packed_repo" "$FILE_CLONE" >"$OUT/linux/clone_file.log" 2>&1
FILE_RC=$?
if [ "$FILE_RC" -eq 0 ] && cmp -s "$TD/packed_repo/HEAD" "$FILE_CLONE/.git/HEAD"; then
    pass_case "file:// clone strips scheme and copies HEAD"
else
    fail_case "file:// clone (rc=$FILE_RC)"
    tail -10 "$OUT/linux/clone_file.log" | sed 's/^/       /'
fi

WORKTREE_CLONE="$OUT/linux/clone_from_worktree"
rm -rf "$WORKTREE_CLONE"
"$PROG" clone "$PACKED" "$WORKTREE_CLONE" >"$OUT/linux/clone_worktree.log" 2>&1
WORKTREE_RC=$?
( cd "$WORKTREE_CLONE" 2>/dev/null && "$PROG" log ) >"$OUT/linux/worktree_log.out" 2>&1
if [ "$WORKTREE_RC" -eq 0 ] && cmp -s "$OUT/linux/packed_log.want" "$OUT/linux/worktree_log.out"; then
    pass_case "clone resolves a worktree source (<path>/.git)"
else
    fail_case "clone from worktree source (rc=$WORKTREE_RC)"
    tail -10 "$OUT/linux/clone_worktree.log" | sed 's/^/       /'
fi

echo "== packed-refs source =="
PR_SRC="$OUT/linux/packed_refs_src"
PR_CLONE="$OUT/linux/clone_packed_refs"
rm -rf "$PR_SRC" "$PR_CLONE"
cp -R "$TD/loose_repo" "$PR_SRC"
git --git-dir="$PR_SRC" pack-refs --all --prune >/dev/null 2>&1
if [ -f "$PR_SRC/packed-refs" ] && [ ! -f "$PR_SRC/refs/heads/master" ]; then
    pass_case "prepared packed-refs-only source"
else
    fail_case "could not prepare packed-refs-only source"
fi
"$PROG" clone "$PR_SRC" "$PR_CLONE" >"$OUT/linux/clone_packedrefs.log" 2>&1
PR_RC=$?
if [ "$PR_RC" -eq 0 ] && cmp -s "$PR_SRC/packed-refs" "$PR_CLONE/.git/packed-refs"; then
    pass_case "packed-refs cloned verbatim"
else
    fail_case "packed-refs clone failed (rc=$PR_RC)"
    tail -10 "$OUT/linux/clone_packedrefs.log" | sed 's/^/       /'
fi
( cd "$PR_CLONE" && "$PROG" log ) >"$OUT/linux/packedrefs_log.out" 2>&1
if cmp -s "$OUT/linux/loose_log.want" "$OUT/linux/packedrefs_log.out"; then
    pass_case "log resolves HEAD through packed-refs"
else
    fail_case "log through packed-refs"
    diff "$OUT/linux/loose_log.want" "$OUT/linux/packedrefs_log.out" | sed 's/^/       /' | head -20
fi
check_worktree packedrefs "$PR_CLONE" "$TD/loose_repo" "$TD/goldens/loose.lstree"

# --- Windows 9x no-CRT smoke ------------------------------------------------
echo "== Windows: bare -osw emit + MinGW no-CRT build =="
timeout 300 "$ZIG" -osw -o "$OUT/emit" "$ENTRY" >"$OUT/emit.log" 2>&1
EMIT_RC=$?
if [ "$EMIT_RC" -ne 0 ]; then
    fail_case "bare -osw emit (rc=$EMIT_RC; see $OUT/emit.log)"
    tail -20 "$OUT/emit.log" | sed 's/^/       /'
    finish
fi
pass_case "bare -osw emit"

if [ -f "$OUT/emit/build_target.sh" ] && \
   grep -q -- '-DZIG_NO_CRT' "$OUT/emit/build_target.sh" && \
   grep -q -- '-nostdlib' "$OUT/emit/build_target.sh" && \
   grep -q -- '-lkernel32' "$OUT/emit/build_target.sh"; then
    pass_case "emitted mingw recipe is 9x no-CRT (DZIG_NO_CRT, nostdlib, kernel32)"
else
    fail_case "emitted build_target.sh is not the 9x no-CRT recipe"
    finish
fi

EXE="$OUT/z9git.exe"
if sh "$OUT/emit/build_target.sh" mingw "$EXE" >"$OUT/win_build.log" 2>&1 && [ -f "$EXE" ]; then
    pass_case "MinGW no-CRT build produced $(basename "$EXE")"
else
    fail_case "MinGW no-CRT build failed (STOP: no CRT/nt fallback)"
    tail -20 "$OUT/win_build.log" | sed 's/^/       /'
    finish
fi

FILEOUT="$(file "$EXE" 2>/dev/null)"
case "$FILEOUT" in
    *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
    *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
esac

if bash "$CHECK" "$EXE" 9x >"$OUT/imports.log" 2>&1; then
    pass_case "check_win9x_imports.sh 9x PASS"
else
    fail_case "check_win9x_imports.sh 9x FAILED (STOP; see $OUT/imports.log)"
    tail -20 "$OUT/imports.log" | sed 's/^/       /'
    finish
fi
tail -3 "$OUT/imports.log" | sed 's/^/       /'

cp -R "$TD/packed_repo" "$OUT/wine/packed_repo"
rm -rf "$OUT/wine/clone_win"
( cd "$OUT/wine" && timeout 180 wine "$EXE" clone packed_repo clone_win ) \
    >"$OUT/wine_clone.log" 2>&1
WIN_CLONE_RC=$?
if [ "$WIN_CLONE_RC" -eq 0 ] && [ -f "$OUT/wine/clone_win/.git/HEAD" ]; then
    pass_case "Wine clone packed_repo exit 0"
else
    fail_case "Wine clone packed_repo exit 0 (got $WIN_CLONE_RC; STOP: see $OUT/wine_clone.log)"
    tail -15 "$OUT/wine_clone.log" | sed 's/^/       /'
    finish
fi
( cd "$OUT/wine/clone_win" && timeout 180 wine "$EXE" log ) \
    >"$OUT/wine_log.out" 2>"$OUT/wine_log.err"
WIN_LOG_RC=$?
if [ "$WIN_LOG_RC" -eq 0 ] && cmp -s "$OUT/linux/packed_log.want" "$OUT/wine_log.out"; then
    pass_case "Wine log golden matches Linux"
else
    fail_case "Wine log golden (rc=$WIN_LOG_RC; STOP: see $OUT/wine_log.err)"
    diff "$OUT/linux/packed_log.want" "$OUT/wine_log.out" | sed 's/^/       /' | head -20
    tail -10 "$OUT/wine_log.err" | sed 's/^/       /'
fi

finish
