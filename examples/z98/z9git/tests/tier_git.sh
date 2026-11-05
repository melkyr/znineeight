#!/bin/sh
# tier_git.sh -- Phase 3 Task 7/8 gate for the z9git CLI.
#
# Builds examples/z98/z9git/main.zig with a seed-built zig1, then exercises the
# local transports against the committed Task 6 fixtures plus the Task 8
# smart-HTTP clone:
#   - clone packed_repo: copied pack+idx bytes, copied refs/HEAD, worktree
#     matches goldens/packed.lstree, log golden, checkout <branch> golden
#     (tracked-but-absent files removed, untracked files left alone);
#   - clone loose_repo: loose objects copied verbatim (SHA-1 names preserved);
#   - file:// clone, clone-from-worktree source, packed-refs-only source;
#   - pkt-line unit cases; mocked-transport smart HTTP with request-byte,
#     streaming-pack, >1 MiB sink-split, cleanup and pacing assertions;
#     end-to-end git http-backend over HTTP and HTTPS (>328 refs,
#     tls_demo certs/store), plus an opt-in Z98_NET=1 GitHub probe;
#   - -h rc0, bad args rc1, and a refused HTTP connection rc2 (no side effects);
#   - Windows: bare -osw emit, MinGW no-CRT build through the emitted
#     build_target.sh, check_win9x_imports.sh ... 9x PASS, then Wine clone+log
#     on packed_repo and the mocked-transport HTTP case. A no-CRT build/run
#     failure is a hard FAIL (never a CRT/nt fallback).
#
# The committed fixture bytes are consumed as-is; gen_repos.sh is dev-time
# only. Git 2.39 is used for goldens/inspection, the scripted mocked pack, and
# the e2e server; the clone itself never shells out to git.
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).
#
# Env: ZIG       seed-built zig1_5_clean (default /tmp/p3_t8_base/zig1_5_clean)
#      OUT       scratch dir (default /tmp/z9git_tier)
#      WINEPREFIX default $OUT/wineprefix
#      Z98_NET   set 1 to run the opt-in GitHub HTTPS probe (default skip)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$APP_DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/p3_t8_base/zig1_5_clean}"
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
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t8_base"
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
HAVE_PYTHON=0
HAVE_PYTHON_SSL=0
if command -v python3 >/dev/null 2>&1; then
    HAVE_PYTHON=1
    if python3 -c 'import ssl' >/dev/null 2>&1; then
        HAVE_PYTHON_SSL=1
    fi
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

echo "== build z9git with the seed compiler (-ffast work / -fsafe memory) =="
if ! "$ZIG" -ffast -o "$OUT/bin" "$ENTRY" >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (-ffast; see $OUT/zig.log)"
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
pass_case "Linux build produced $PROG (-ffast)"
mkdir -p "$OUT/bin_safe"
if ! "$ZIG" -fsafe -o "$OUT/bin_safe" "$ENTRY" >"$OUT/zig_safe.log" 2>&1; then
    fail_case "zig -fsafe measurement build (see $OUT/zig_safe.log)"
    tail -40 "$OUT/zig_safe.log" | sed 's/^/       /'
    finish
fi
if ! sh "$OUT/bin_safe/build_target.sh" linux "$OUT/bin_safe/prog" >"$OUT/build_safe.log" 2>&1; then
    fail_case "target link for -fsafe measurement build (see $OUT/build_safe.log)"
    tail -40 "$OUT/build_safe.log" | sed 's/^/       /'
    finish
fi
PROG_SAFE="$OUT/bin_safe/prog"
[ -x "$PROG_SAFE" ] || { echo "FAIL: $PROG_SAFE not built"; exit 1; }
pass_case "Linux build produced $PROG_SAFE (-fsafe for peak-RSS measurement)"

echo "== pkt-line unit =="
PKT_DIR="$OUT/pkt"
mkdir -p "$PKT_DIR"
if ! "$ZIG" -fsafe -o "$PKT_DIR" "$APP_DIR/tests/pkt_test.zig" >"$OUT/pkt_zig.log" 2>&1; then
    fail_case "pkt_test compile (see $OUT/pkt_zig.log)"
    tail -30 "$OUT/pkt_zig.log" | sed 's/^/       /'
    finish
fi
if ! sh "$PKT_DIR/build_target.sh" linux "$PKT_DIR/pkt_test" >"$OUT/pkt_build.log" 2>&1; then
    fail_case "pkt_test link (see $OUT/pkt_build.log)"
    tail -30 "$OUT/pkt_build.log" | sed 's/^/       /'
    finish
fi
"$PKT_DIR/pkt_test" >"$OUT/pkt_run.log" 2>&1
PKT_RC=$?
if [ "$PKT_RC" -eq 0 ]; then
    pass_case "pkt-line encode/decode/flush edge cases"
else
    fail_case "pkt-line unit (rc=$PKT_RC)"
    sed 's/^/       /' "$OUT/pkt_run.log" | tail -25
fi

echo "== mocked-transport smart HTTP clone =="
MOCK_DATA="$OUT/mockdata"
MOCK_DIR="$OUT/mock"
mkdir -p "$MOCK_DATA" "$MOCK_DIR"
if ! git upload-pack --stateless-rpc --advertise-refs "$TD/packed_repo" >"$MOCK_DATA/adv" 2>"$OUT/mock_adv.err"; then
    fail_case "prepare mocked ref advertisement"
    tail -10 "$OUT/mock_adv.err" | sed 's/^/       /'
    finish
fi
{ printf '001e# service=git-upload-pack\n0000'; cat "$MOCK_DATA/adv"; } >"$MOCK_DATA/info_refs"
if ! git --git-dir="$TD/packed_repo" pack-objects --stdout --all >"$MOCK_DATA/pack" 2>"$OUT/mock_pack.err"; then
    fail_case "prepare mocked upload-pack archive"
    tail -10 "$OUT/mock_pack.err" | sed 's/^/       /'
    finish
fi
{ printf '0008NAK\n'; cat "$MOCK_DATA/pack"; } >"$MOCK_DATA/upload"

if ! "$ZIG" -fsafe -o "$MOCK_DIR" "$APP_DIR/tests/mock_http.zig" >"$OUT/mock_zig.log" 2>&1; then
    fail_case "mock_http compile (see $OUT/mock_zig.log)"
    tail -30 "$OUT/mock_zig.log" | sed 's/^/       /'
    finish
fi
if ! sh "$MOCK_DIR/build_target.sh" linux "$MOCK_DIR/mock_http" >"$OUT/mock_build.log" 2>&1; then
    fail_case "mock_http link (see $OUT/mock_build.log)"
    tail -30 "$OUT/mock_build.log" | sed 's/^/       /'
    finish
fi

MOCK_CLONE="$OUT/linux/clone_mock_http"
rm -rf "$MOCK_CLONE"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$MOCK_CLONE" 0 \
    "$MOCK_DATA/info_refs" "$MOCK_DATA/upload" "$OUT/linux/mock_requests.log" \
    >"$OUT/linux/mock_clone.log" 2>&1
MOCK_RC=$?
if [ "$MOCK_RC" -eq 0 ] && [ -f "$MOCK_CLONE/.git/HEAD" ]; then
    pass_case "mocked smart HTTP clone exit 0"
else
    fail_case "mocked smart HTTP clone (rc=$MOCK_RC)"
    tail -15 "$OUT/linux/mock_clone.log" | sed 's/^/       /'
fi

MOCK_REQ="$OUT/linux/mock_requests.log"
MOCK_MASTER=$(git --git-dir="$TD/packed_repo" rev-parse refs/heads/master)
MOCK_REFDELTA=$(git --git-dir="$TD/packed_repo" rev-parse refs/heads/refdelta)
MOCK_TAG=$(git --git-dir="$TD/packed_repo" rev-parse refs/tags/v1)
if grep -q 'GET /r.git/info/refs?service=git-upload-pack HTTP/1.1' "$MOCK_REQ" && \
   grep -q 'POST /r.git/git-upload-pack HTTP/1.1' "$MOCK_REQ" && \
   grep -q 'Content-Type: application/x-git-upload-pack-request' "$MOCK_REQ" && \
   grep -q 'Accept: application/x-git-upload-pack-result' "$MOCK_REQ" && \
   grep -q "want $MOCK_MASTER" "$MOCK_REQ" && \
   grep -q "want $MOCK_REFDELTA" "$MOCK_REQ" && \
   grep -q "want $MOCK_TAG" "$MOCK_REQ" && \
   grep -q '0009done' "$MOCK_REQ"; then
    pass_case "request bytes: info/refs GET, upload-pack POST want/done"
else
    fail_case "request bytes/content types are wrong"
    sed 's/^/       /' "$MOCK_REQ" | head -30
fi

MOCK_IDX=$(find "$MOCK_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' | head -1)
if [ -n "$MOCK_IDX" ] && git verify-pack -v "$MOCK_IDX" >"$OUT/linux/mock_verify.log" 2>&1; then
    pass_case "git verify-pack accepts streamed+synthesized idx"
else
    fail_case "git verify-pack rejected mocked clone idx"
    tail -10 "$OUT/linux/mock_verify.log" 2>/dev/null | sed 's/^/       /'
fi
if [ "$MOCK_RC" -eq 0 ] && git --git-dir="$MOCK_CLONE/.git" fsck --full --no-dangling >"$OUT/linux/mock_fsck.log" 2>&1; then
    pass_case "git fsck accepts mocked clone"
else
    fail_case "git fsck rejected mocked clone"
    tail -10 "$OUT/linux/mock_fsck.log" 2>/dev/null | sed 's/^/       /'
fi

if cmp -s "$TD/packed_repo/HEAD" "$MOCK_CLONE/.git/HEAD"; then
    pass_case "mocked clone HEAD matches source"
else
    fail_case "mocked clone HEAD differs"
fi
git --git-dir="$TD/packed_repo" for-each-ref --format='%(objectname) %(refname)' >"$OUT/linux/mock_refs.want"
git --git-dir="$MOCK_CLONE/.git" for-each-ref --format='%(objectname) %(refname)' >"$OUT/linux/mock_refs.out"
if cmp -s "$OUT/linux/mock_refs.want" "$OUT/linux/mock_refs.out"; then
    pass_case "mocked clone refs match source"
else
    fail_case "mocked clone refs differ"
    diff "$OUT/linux/mock_refs.want" "$OUT/linux/mock_refs.out" | sed 's/^/       /' | head -20
fi
check_worktree mock_http "$MOCK_CLONE" "$TD/packed_repo" "$TD/goldens/packed.lstree"

echo "== disk preflight uses Content-Length and PACK count before committing =="
PF_DATA="$MOCK_DATA/preflight"
PF_DEST="$OUT/linux/clone_mock_preflight"
mkdir -p "$PF_DATA"
printf '0008NAK\n\120\101\103\113\000\000\000\002\377\377\377\377' >"$PF_DATA/upload"
rm -rf "$PF_DEST"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$PF_DEST" 0 \
    "$MOCK_DATA/info_refs" "$PF_DATA/upload" "$OUT/linux/mock_preflight_requests.log" \
    >"$OUT/linux/mock_preflight.log" 2>&1
PF_RC=$?
if [ "$PF_RC" -eq 5 ] && grep -q 'disk full' "$OUT/linux/mock_preflight.log"; then
    pass_case "oversized PACK count fails disk preflight (rc5)"
else
    fail_case "oversized PACK count did not fail disk preflight (rc=$PF_RC)"
    tail -10 "$OUT/linux/mock_preflight.log" | sed 's/^/       /'
fi
PF_LEFTOVER=$(find "$PF_DEST/.git/objects/pack" -maxdepth 1 \
    \( -name '*.pack' -o -name '*.idx' -o -name 'tmp_http_pack.*' \) -print 2>/dev/null)
if [ -z "$PF_LEFTOVER" ]; then
    pass_case "disk preflight failure leaves no final pack/idx or temp pack"
else
    fail_case "disk preflight failure left files behind"
    echo "$PF_LEFTOVER" | sed 's/^/       /'
fi

echo "== mocked-transport refs/pull/* filter =="
PULL_SRC="$OUT/mock_pull_src"
PULL_REPO="$OUT/mock_pull.git"
PULL_DATA="$MOCK_DATA/pull"
rm -rf "$PULL_SRC" "$PULL_REPO" "$PULL_DATA"
mkdir -p "$PULL_DATA"
if ! (
    git init -q "$PULL_SRC" &&
    cd "$PULL_SRC" &&
    git config user.name "z9 fixture" &&
    git config user.email "z9@example.invalid" &&
    printf 'base\n' >main.txt &&
    git add main.txt &&
    git commit -q -m "pull filter base" &&
    PULL_BASE=$(git symbolic-ref --short HEAD) &&
    git checkout -q --orphan pullreq &&
    git rm -q -rf . &&
    printf 'pull only\n' >pull.txt &&
    git add pull.txt &&
    git commit -q -m "pull request only commit" &&
    git update-ref refs/pull/1/head refs/heads/pullreq &&
    git checkout -q "$PULL_BASE"
) >"$OUT/mock_pull_build.log" 2>&1; then
    fail_case "prepare refs/pull fixture"
    tail -10 "$OUT/mock_pull_build.log" | sed 's/^/       /'
    finish
fi
if ! git clone --bare --no-hardlinks -q "$PULL_SRC" "$PULL_REPO" >>"$OUT/mock_pull_build.log" 2>&1; then
    fail_case "prepare refs/pull bare fixture"
    tail -10 "$OUT/mock_pull_build.log" | sed 's/^/       /'
    finish
fi
if ! git --git-dir="$PULL_REPO" update-ref refs/pull/1/head refs/heads/pullreq >>"$OUT/mock_pull_build.log" 2>&1 || \
   ! git --git-dir="$PULL_REPO" update-ref -d refs/heads/pullreq >>"$OUT/mock_pull_build.log" 2>&1; then
    fail_case "prepare refs/pull advertisement"
    tail -10 "$OUT/mock_pull_build.log" | sed 's/^/       /'
    finish
fi
if ! git upload-pack --stateless-rpc --advertise-refs "$PULL_REPO" >"$PULL_DATA/adv" 2>"$OUT/mock_pull_adv.err"; then
    fail_case "prepare refs/pull ref advertisement"
    tail -10 "$OUT/mock_pull_adv.err" | sed 's/^/       /'
    finish
fi
{ printf '001e# service=git-upload-pack\n0000'; cat "$PULL_DATA/adv"; } >"$PULL_DATA/info_refs"
if ! git --git-dir="$PULL_REPO" rev-list --objects --all --not refs/pull/1/head | \
     git --git-dir="$PULL_REPO" pack-objects --stdout >"$PULL_DATA/pack" 2>"$OUT/mock_pull_pack.err"; then
    fail_case "prepare refs/pull upload-pack archive"
    tail -10 "$OUT/mock_pull_pack.err" | sed 's/^/       /'
    finish
fi
{ printf '0008NAK\n'; cat "$PULL_DATA/pack"; } >"$PULL_DATA/upload"
PULL_ID=$(git --git-dir="$PULL_REPO" rev-parse refs/pull/1/head)
PULL_MASTER=$(git --git-dir="$PULL_REPO" rev-parse refs/heads/master)
PULL_CLONE="$OUT/linux/clone_mock_pull"
PULL_REQ="$OUT/linux/mock_pull_requests.log"
rm -rf "$PULL_CLONE"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$PULL_CLONE" 0 \
    "$PULL_DATA/info_refs" "$PULL_DATA/upload" "$PULL_REQ" \
    >"$OUT/linux/mock_pull.log" 2>&1
PULL_RC=$?
if [ "$PULL_RC" -eq 0 ] && [ -f "$PULL_CLONE/.git/HEAD" ]; then
    pass_case "refs/pull clone exit 0"
else
    fail_case "refs/pull clone (rc=$PULL_RC)"
    tail -15 "$OUT/linux/mock_pull.log" | sed 's/^/       /'
fi
if [ "$PULL_RC" -eq 0 ] && ! grep -q "want $PULL_ID" "$PULL_REQ"; then
    pass_case "refs/pull clone request omits want <pull-ref>"
else
    fail_case "refs/pull clone requested the pull ref"
    [ -f "$PULL_REQ" ] && grep "want $PULL_ID" "$PULL_REQ" | sed 's/^/       /' | head -5
fi
if [ "$PULL_RC" -eq 0 ] && grep -q "want $PULL_MASTER" "$PULL_REQ"; then
    pass_case "refs/pull clone request keeps non-pull wants"
else
    fail_case "refs/pull clone lost the master want"
    [ -f "$PULL_REQ" ] && sed 's/^/       /' "$PULL_REQ" | head -20
fi
git --git-dir="$PULL_REPO" for-each-ref --format='%(objectname) %(refname)' | grep -v ' refs/pull/' >"$OUT/linux/mock_pull_refs.want"
git --git-dir="$PULL_CLONE/.git" for-each-ref --format='%(objectname) %(refname)' >"$OUT/linux/mock_pull_refs.out" 2>/dev/null
if [ "$PULL_RC" -eq 0 ] && ! grep -q ' refs/pull/' "$OUT/linux/mock_pull_refs.out" && \
   cmp -s "$OUT/linux/mock_pull_refs.want" "$OUT/linux/mock_pull_refs.out"; then
    pass_case "refs/pull clone installs only non-pull refs"
else
    fail_case "refs/pull clone ref list is wrong"
    diff "$OUT/linux/mock_pull_refs.want" "$OUT/linux/mock_pull_refs.out" | sed 's/^/       /' | head -20
fi
PULL_IDX=$(find "$PULL_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
if [ "$PULL_RC" -eq 0 ] && [ -n "$PULL_IDX" ] && git verify-pack -v "$PULL_IDX" >"$OUT/linux/mock_pull_verify.log" 2>&1; then
    pass_case "git verify-pack accepts refs/pull clone idx"
else
    fail_case "git verify-pack rejected refs/pull clone idx"
    tail -10 "$OUT/linux/mock_pull_verify.log" 2>/dev/null | sed 's/^/       /'
fi
if [ "$PULL_RC" -eq 0 ] && git --git-dir="$PULL_CLONE/.git" fsck --full --no-dangling >"$OUT/linux/mock_pull_fsck.log" 2>&1; then
    pass_case "git fsck accepts refs/pull clone"
else
    fail_case "git fsck rejected refs/pull clone"
    tail -10 "$OUT/linux/mock_pull_fsck.log" 2>/dev/null | sed 's/^/       /'
fi
if [ "$PULL_RC" -eq 0 ] && cmp -s "$PULL_REPO/HEAD" "$PULL_CLONE/.git/HEAD"; then
    pass_case "refs/pull clone HEAD matches source"
else
    fail_case "refs/pull clone HEAD differs"
fi
PULL_MAIN_ID=$(git --git-dir="$PULL_REPO" rev-parse refs/heads/master:main.txt)
if [ "$PULL_RC" -eq 0 ] && [ ! -e "$PULL_CLONE/pull.txt" ] && \
   git --git-dir="$PULL_REPO" cat-file blob "$PULL_MAIN_ID" | cmp -s - "$PULL_CLONE/main.txt"; then
    pass_case "refs/pull clone worktree matches source"
else
    fail_case "refs/pull clone worktree differs"
fi

echo "== mocked-transport pacing (independent of python3/e2e) =="
MOCK_PACED="$OUT/linux/clone_mock_paced"
rm -rf "$MOCK_PACED"
PACE_T0=$(date +%s)
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$MOCK_PACED" 1024 \
    "$MOCK_DATA/info_refs" "$MOCK_DATA/upload" "$OUT/linux/mock_requests_paced.log" \
    >"$OUT/linux/mock_paced.log" 2>&1
MOCK_PACED_RC=$?
PACE_T1=$(date +%s)
MOCK_PACE_ELAPSED=$((PACE_T1 - PACE_T0))
if [ "$MOCK_PACED_RC" -eq 0 ] && [ "$MOCK_PACE_ELAPSED" -ge 2 ] && [ -f "$MOCK_PACED/.git/HEAD" ]; then
    pass_case "mock sink pacing floor 1024 B/s (${MOCK_PACE_ELAPSED}s >= 2s)"
else
    fail_case "mock sink pacing floor (rc=$MOCK_PACED_RC elapsed=${MOCK_PACE_ELAPSED}s)"
    tail -10 "$OUT/linux/mock_paced.log" | sed 's/^/       /'
fi

echo "== mocked-transport failure cleanup and status classification =="
MOCK_404="$OUT/linux/clone_mock_404"
rm -rf "$MOCK_404"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$MOCK_404" 0 \
    "$MOCK_DATA/info_refs" "$MOCK_DATA/upload" "$OUT/linux/mock_404_requests.log" 404 \
    >"$OUT/linux/mock_404.log" 2>&1
MOCK_404_RC=$?
if [ "$MOCK_404_RC" -eq 2 ] && [ ! -e "$MOCK_404/.git/objects/pack/tmp_http_pack.pack" ]; then
    pass_case "POST 404 is rc2 and removes tmp pack"
else
    fail_case "POST 404 classification/cleanup (rc=$MOCK_404_RC)"
    tail -10 "$OUT/linux/mock_404.log" | sed 's/^/       /'
fi

head -c 256 "$MOCK_DATA/upload" >"$MOCK_DATA/upload_trunc"
MOCK_TRUNC="$OUT/linux/clone_mock_trunc"
rm -rf "$MOCK_TRUNC"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$MOCK_TRUNC" 0 \
    "$MOCK_DATA/info_refs" "$MOCK_DATA/upload_trunc" "$OUT/linux/mock_trunc_requests.log" \
    >"$OUT/linux/mock_trunc.log" 2>&1
MOCK_TRUNC_RC=$?
if [ "$MOCK_TRUNC_RC" -eq 3 ] && [ ! -e "$MOCK_TRUNC/.git/objects/pack/tmp_http_pack.pack" ]; then
    pass_case "truncated pack is rc3 and removes tmp pack"
else
    fail_case "truncated pack classification/cleanup (rc=$MOCK_TRUNC_RC)"
    tail -10 "$OUT/linux/mock_trunc.log" | sed 's/^/       /'
fi

echo "== mocked-transport >1 MiB pack (sink split) =="
BIG_SRC="$OUT/mock_big_src"
BIG_REPO="$OUT/mock_big.git"
BIG_DATA="$MOCK_DATA/big"
rm -rf "$BIG_SRC" "$BIG_REPO"
mkdir -p "$BIG_SRC" "$BIG_DATA"
if ! (
    cd "$BIG_SRC" || exit 1
    git init -q
    git config user.name "z9 fixture"
    git config user.email "z9@example.invalid"
    head -c 1572864 /dev/urandom >big.bin
    git add big.bin
    git commit -q -m "large streaming payload"
) >"$OUT/mock_big_build.log" 2>&1; then
    fail_case "prepare >1 MiB repository"
    tail -10 "$OUT/mock_big_build.log" | sed 's/^/       /'
    finish
fi
if ! git clone --bare --no-hardlinks -q "$BIG_SRC" "$BIG_REPO" >>"$OUT/mock_big_build.log" 2>&1; then
    fail_case "prepare >1 MiB bare repository"
    tail -10 "$OUT/mock_big_build.log" | sed 's/^/       /'
    finish
fi
git upload-pack --stateless-rpc --advertise-refs "$BIG_REPO" >"$BIG_DATA/adv" 2>>"$OUT/mock_big_build.log"
{ printf '001e# service=git-upload-pack\n0000'; cat "$BIG_DATA/adv"; } >"$BIG_DATA/info_refs"
git --git-dir="$BIG_REPO" pack-objects --stdout --all >"$BIG_DATA/pack" 2>>"$OUT/mock_big_build.log"
{ printf '0008NAK\n'; cat "$BIG_DATA/pack"; } >"$BIG_DATA/upload"
BIG_PACK_SIZE=$(wc -c <"$BIG_DATA/pack" | tr -d ' ')
if [ "$BIG_PACK_SIZE" -gt 1048576 ]; then
    pass_case "prepared >1 MiB scripted pack ($BIG_PACK_SIZE bytes)"
else
    fail_case "scripted pack is not >1 MiB ($BIG_PACK_SIZE bytes)"
fi
BIG_CLONE="$OUT/linux/clone_mock_big"
rm -rf "$BIG_CLONE"
"$MOCK_DIR/mock_http" "http://mock.invalid/r.git" "$BIG_CLONE" 0 \
    "$BIG_DATA/info_refs" "$BIG_DATA/upload" "$OUT/linux/mock_big_requests.log" \
    >"$OUT/linux/mock_big.log" 2>&1
BIG_RC=$?
BIG_IDX=$(find "$BIG_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
BIG_PACK=$(find "$BIG_CLONE/.git/objects/pack" -maxdepth 1 -name '*.pack' 2>/dev/null | head -1)
if [ "$BIG_RC" -eq 0 ] && [ -n "$BIG_IDX" ] && [ -n "$BIG_PACK" ] && cmp -s "$BIG_DATA/pack" "$BIG_PACK"; then
    pass_case "streamed >1 MiB pack byte-identical across sink flushes"
else
    fail_case "streamed >1 MiB pack (rc=$BIG_RC)"
    tail -15 "$OUT/linux/mock_big.log" | sed 's/^/       /'
fi
if [ -n "$BIG_IDX" ] && git verify-pack -v "$BIG_IDX" >"$OUT/linux/mock_big_verify.log" 2>&1; then
    pass_case "git verify-pack accepts >1 MiB idx"
else
    fail_case "git verify-pack rejected >1 MiB idx"
    tail -10 "$OUT/linux/mock_big_verify.log" 2>/dev/null | sed 's/^/       /'
fi
if [ "$BIG_RC" -eq 0 ] && git --git-dir="$BIG_CLONE/.git" fsck --full --no-dangling >"$OUT/linux/mock_big_fsck.log" 2>&1; then
    pass_case "git fsck accepts >1 MiB clone"
else
    fail_case "git fsck rejected >1 MiB clone"
    tail -10 "$OUT/linux/mock_big_fsck.log" 2>/dev/null | sed 's/^/       /'
fi

echo "== end-to-end smart HTTP (git http-backend) =="
E2E_PID=""
cleanup_e2e() {
    if [ -n "${E2E_PID:-}" ]; then
        kill "$E2E_PID" 2>/dev/null
        wait "$E2E_PID" 2>/dev/null
        E2E_PID=""
    fi
}
if [ "$HAVE_PYTHON" -eq 1 ] && [ -x "$(git --exec-path)/git-http-backend" ]; then
    trap cleanup_e2e EXIT
    E2E="$OUT/e2e"
    mkdir -p "$E2E/www"
    cp -R "$TD/packed_repo" "$E2E/www/r.git"
    rm -f "$E2E/port"
    python3 "$APP_DIR/tests/git_http_server.py" "$E2E/www" "$E2E/port" \
        >"$E2E/server.log" 2>&1 &
    E2E_PID=$!
    E2E_WAIT=0
    while [ ! -s "$E2E/port" ] && [ "$E2E_WAIT" -lt 100 ]; do
        sleep 0.1
        E2E_WAIT=$((E2E_WAIT + 1))
    done
    E2E_PORT=$(cat "$E2E/port" 2>/dev/null)
    if [ -z "$E2E_PORT" ]; then
        fail_case "start git http-backend CGI server"
        tail -10 "$E2E/server.log" 2>/dev/null | sed 's/^/       /'
    else
        pass_case "started git http-backend CGI server on 127.0.0.1:$E2E_PORT"
        E2E_FILE="$E2E/file_golden"
        E2E_HTTP="$E2E/http_clone"
        rm -rf "$E2E_FILE" "$E2E_HTTP"
        "$PROG" clone "file://$TD/packed_repo" "$E2E_FILE" >"$E2E/file.log" 2>&1
        E2E_FILE_RC=$?
        "$PROG" clone "http://127.0.0.1:$E2E_PORT/r.git" "$E2E_HTTP" >"$E2E/http.log" 2>&1
        E2E_HTTP_RC=$?
        if [ "$E2E_FILE_RC" -eq 0 ] && [ "$E2E_HTTP_RC" -eq 0 ] && [ -f "$E2E_HTTP/.git/HEAD" ]; then
            pass_case "clone http://127.0.0.1:<port>/r.git exit 0"
        else
            fail_case "end-to-end HTTP clone (file rc=$E2E_FILE_RC http rc=$E2E_HTTP_RC)"
            tail -15 "$E2E/http.log" | sed 's/^/       /'
        fi
        if [ "$E2E_FILE_RC" -eq 0 ] && [ "$E2E_HTTP_RC" -eq 0 ] && \
           diff -r --exclude=.git "$E2E_FILE" "$E2E_HTTP" >"$E2E/worktree.diff" 2>&1; then
            pass_case "HTTP worktree identical to file:// clone"
        else
            fail_case "HTTP worktree differs from file:// clone"
            head -20 "$E2E/worktree.diff" 2>/dev/null | sed 's/^/       /'
        fi
        if [ "$E2E_HTTP_RC" -eq 0 ] && cmp -s "$E2E_FILE/.git/HEAD" "$E2E_HTTP/.git/HEAD"; then
            pass_case "HTTP HEAD matches file:// clone"
        else
            fail_case "HTTP HEAD differs from file:// clone"
        fi
        if [ "$E2E_HTTP_RC" -eq 0 ] && diff -r "$E2E_FILE/.git/refs" "$E2E_HTTP/.git/refs" >"$E2E/refs.diff" 2>&1; then
            pass_case "HTTP refs match file:// clone"
        else
            fail_case "HTTP refs differ from file:// clone"
            head -20 "$E2E/refs.diff" 2>/dev/null | sed 's/^/       /'
        fi
        E2E_IDX=$(find "$E2E_HTTP/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
        if [ -n "$E2E_IDX" ] && git verify-pack -v "$E2E_IDX" >"$E2E/verify.log" 2>&1; then
            pass_case "git verify-pack accepts e2e idx"
        else
            fail_case "git verify-pack rejected e2e idx"
            tail -10 "$E2E/verify.log" 2>/dev/null | sed 's/^/       /'
        fi
        if [ "$E2E_HTTP_RC" -eq 0 ] && git --git-dir="$E2E_HTTP/.git" fsck --full --no-dangling >"$E2E/fsck.log" 2>&1; then
            pass_case "git fsck accepts e2e clone"
        else
            fail_case "git fsck rejected e2e clone"
            tail -10 "$E2E/fsck.log" 2>/dev/null | sed 's/^/       /'
        fi

        E2E_PACED="$E2E/http_paced"
        rm -rf "$E2E_PACED"
        PACE_T0=$(date +%s)
        "$PROG" clone "http://127.0.0.1:$E2E_PORT/r.git" "$E2E_PACED" --max-down 1 >"$E2E/paced.log" 2>&1
        E2E_PACED_RC=$?
        PACE_T1=$(date +%s)
        PACE_ELAPSED=$((PACE_T1 - PACE_T0))
        if [ "$E2E_PACED_RC" -eq 0 ] && [ "$PACE_ELAPSED" -ge 2 ] && [ -f "$E2E_PACED/.git/HEAD" ]; then
            pass_case "--max-down 1 pacing floor (${PACE_ELAPSED}s >= 2s)"
        else
            fail_case "--max-down 1 pacing floor (rc=$E2E_PACED_RC elapsed=${PACE_ELAPSED}s)"
            tail -10 "$E2E/paced.log" | sed 's/^/       /'
        fi
    fi
    cleanup_e2e
    trap - EXIT
else
    if [ "$HAVE_PYTHON" -eq 0 ]; then
        echo "SKIP - end-to-end smart HTTP: python3 not installed; mocked transport/pacing cases above still ran"
    else
        echo "SKIP - end-to-end smart HTTP: git http-backend not installed; mocked transport/pacing cases above still ran"
    fi
fi

echo "== end-to-end HTTPS smart HTTP (>328 refs) =="
TLS_CERTS="$ROOT/examples/z98/demo/tls_demo/tests/certs"
TLS_STORE="$TLS_CERTS/store.bin"
if [ "$HAVE_PYTHON_SSL" -eq 1 ] && [ -x "$(git --exec-path)/git-http-backend" ] && \
   [ -f "$TLS_CERTS/localhost.pem" ] && [ -f "$TLS_CERTS/localhost.key" ] && [ -f "$TLS_STORE" ]; then
    trap cleanup_e2e EXIT
    HTTPS="$OUT/https"
    rm -rf "$HTTPS"
    mkdir -p "$HTTPS/www"
    cp -R "$TD/packed_repo" "$HTTPS/www/r.git"
    cp "$TLS_STORE" "$HTTPS/ca_store.bin"
    if ! (
        export GIT_AUTHOR_NAME="z9 fixture"
        export GIT_AUTHOR_EMAIL="z9@example.invalid"
        export GIT_COMMITTER_NAME="z9 fixture"
        export GIT_COMMITTER_EMAIL="z9@example.invalid"
        gd="$HTTPS/www/r.git"
        tree=$(git --git-dir="$gd" rev-parse "refs/heads/master^{tree}") || exit 1
        parent=$(git --git-dir="$gd" rev-parse refs/heads/master) || exit 1
        i=1
        while [ "$i" -le 340 ]; do
            parent=$(printf 'refs count %s\n' "$i" | git --git-dir="$gd" commit-tree "$tree" -p "$parent") || exit 1
            git --git-dir="$gd" update-ref "refs/heads/count$i" "$parent" || exit 1
            i=$((i + 1))
        done
    ) >"$HTTPS/refs_build.log" 2>&1; then
        fail_case "prepare >328-reference HTTPS repository"
        tail -10 "$HTTPS/refs_build.log" | sed 's/^/       /'
    else
        HTTPS_REF_COUNT=$(git --git-dir="$HTTPS/www/r.git" for-each-ref | wc -l | tr -d ' ')
        if [ "$HTTPS_REF_COUNT" -ge 329 ]; then
            pass_case "prepared $HTTPS_REF_COUNT HTTPS refs (>328)"
        else
            fail_case "HTTPS repository has only $HTTPS_REF_COUNT refs"
        fi
        rm -f "$HTTPS/port" "$HTTPS/requests.log"
        GIT_HTTP_REQUEST_LOG="$HTTPS/requests.log" \
            python3 "$APP_DIR/tests/git_http_server.py" "$HTTPS/www" "$HTTPS/port" \
            "$TLS_CERTS/localhost.pem" "$TLS_CERTS/localhost.key" \
            >"$HTTPS/server.log" 2>&1 &
        E2E_PID=$!
        HTTPS_WAIT=0
        while [ ! -s "$HTTPS/port" ] && [ "$HTTPS_WAIT" -lt 100 ]; do
            sleep 0.1
            HTTPS_WAIT=$((HTTPS_WAIT + 1))
        done
        HTTPS_PORT=$(cat "$HTTPS/port" 2>/dev/null)
        if [ -z "$HTTPS_PORT" ]; then
            fail_case "start HTTPS git http-backend CGI server"
            tail -10 "$HTTPS/server.log" 2>/dev/null | sed 's/^/       /'
        else
            pass_case "started HTTPS git http-backend CGI server on 127.0.0.1:$HTTPS_PORT"
            HTTPS_CLONE="$HTTPS/clone"
            ( cd "$HTTPS" && timeout 240 "$PROG" clone "https://localhost:$HTTPS_PORT/r.git" "$HTTPS_CLONE" ) \
                >"$HTTPS/clone.log" 2>&1
            HTTPS_RC=$?
            if [ "$HTTPS_RC" -eq 0 ] && [ -f "$HTTPS_CLONE/.git/HEAD" ]; then
                pass_case "HTTPS clone with >328 refs exit 0"
            else
                fail_case "HTTPS clone with >328 refs (rc=$HTTPS_RC)"
                tail -20 "$HTTPS/clone.log" | sed 's/^/       /'
            fi
            HTTPS_POST_LEN=$(awk '$1 == "POST" && $2 ~ /git-upload-pack/ { print $3 }' "$HTTPS/requests.log" 2>/dev/null | sort -nr | head -1)
            if [ -n "$HTTPS_POST_LEN" ] && [ "$HTTPS_POST_LEN" -gt 16384 ]; then
                pass_case "HTTPS want-list request body spans TLS records ($HTTPS_POST_LEN > 16384 bytes)"
            else
                fail_case "HTTPS want-list body was not >16 KiB (${HTTPS_POST_LEN:-missing})"
            fi
            HTTPS_IDX=$(find "$HTTPS_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
            if [ -n "$HTTPS_IDX" ] && git verify-pack -v "$HTTPS_IDX" >"$HTTPS/verify.log" 2>&1; then
                pass_case "git verify-pack accepts HTTPS idx"
            else
                fail_case "git verify-pack rejected HTTPS idx"
                tail -10 "$HTTPS/verify.log" 2>/dev/null | sed 's/^/       /'
            fi
            if [ "$HTTPS_RC" -eq 0 ] && git --git-dir="$HTTPS_CLONE/.git" fsck --full --no-dangling >"$HTTPS/fsck.log" 2>&1; then
                pass_case "git fsck accepts HTTPS clone"
            else
                fail_case "git fsck rejected HTTPS clone"
                tail -10 "$HTTPS/fsck.log" 2>/dev/null | sed 's/^/       /'
            fi
            if [ "$HTTPS_RC" -eq 0 ] && cmp -s "$TD/packed_repo/HEAD" "$HTTPS_CLONE/.git/HEAD"; then
                pass_case "HTTPS HEAD matches source"
            else
                fail_case "HTTPS HEAD differs from source"
            fi
            if [ "$HTTPS_RC" -eq 0 ]; then
                check_worktree https "$HTTPS_CLONE" "$TD/packed_repo" "$TD/goldens/packed.lstree"
            fi
        fi
    fi
    cleanup_e2e
    trap - EXIT
else
    echo "SKIP - end-to-end HTTPS smart HTTP: missing python3+ssl, git http-backend, or tls_demo certs/store"
fi

echo "== opt-in GitHub HTTPS probe =="
if [ "${Z98_NET:-0}" = "1" ]; then
    GITHUB_CLONE="$OUT/github_hello"
    rm -rf "$GITHUB_CLONE"
    if timeout 300 "$PROG" clone "https://github.com/octocat/Hello-World.git" "$GITHUB_CLONE" \
        >"$OUT/github_clone.log" 2>&1 && [ -d "$GITHUB_CLONE" ]; then
        pass_case "GitHub octocat/Hello-World clone exit 0"
        GITHUB_IDX=$(find "$GITHUB_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
        if [ -n "$GITHUB_IDX" ] && git verify-pack -v "$GITHUB_IDX" >"$OUT/github_verify.log" 2>&1; then
            pass_case "GitHub clone idx verifies"
        else
            fail_case "GitHub clone idx failed verify-pack"
            tail -10 "$OUT/github_verify.log" 2>/dev/null | sed 's/^/       /'
        fi
    else
        fail_case "GitHub probe (Z98_NET=1; see $OUT/github_clone.log)"
        tail -20 "$OUT/github_clone.log" | sed 's/^/       /'
    fi
else
    echo "SKIP - GitHub HTTPS probe: set Z98_NET=1 to enable the network test"
fi

echo "== CLI contract =="
"$PROG" -h >"$OUT/linux/help.out" 2>"$OUT/linux/help.err"
HELP_RC=$?
if [ "$HELP_RC" -eq 0 ] && grep -q 'usage: z9git' "$OUT/linux/help.out"; then
    pass_case "-h exit 0 and prints usage"
else
    fail_case "-h exit 0 and prints usage (rc=$HELP_RC)"
fi
if grep -q 'arena: --arena-mb <N> default 32' "$OUT/linux/help.out" && \
   grep -q 'minimum 16' "$OUT/linux/help.out"; then
    pass_case "-h documents --arena-mb (default 32, minimum 16)"
else
    fail_case "-h missing the --arena-mb policy"
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

rm -rf "$OUT/linux/http_refused"
"$PROG" clone http://127.0.0.1:1/repo.git "$OUT/linux/http_refused" >"$OUT/linux/http_refused.out" 2>&1
HTTP_RC=$?
if [ "$HTTP_RC" -eq 2 ] && [ ! -e "$OUT/linux/http_refused" ]; then
    pass_case "http:// connection failure is rc2 without side effects"
else
    fail_case "http:// connection failure rc2 without side effects (got $HTTP_RC)"
fi

echo "== arena flag contract =="
"$PROG" clone "$TD/packed_repo" "$OUT/linux/arena64" --arena-mb 64 >"$OUT/linux/arena64.log" 2>&1
ARENA64_RC=$?
if [ "$ARENA64_RC" -eq 0 ] && [ -f "$OUT/linux/arena64/.git/HEAD" ]; then
    pass_case "--arena-mb 64 (no hard upper bound) clone exit 0"
else
    fail_case "--arena-mb 64 clone (rc=$ARENA64_RC)"
    tail -10 "$OUT/linux/arena64.log" | sed 's/^/       /'
fi
"$PROG" clone "$TD/packed_repo" "$OUT/linux/arena15" --arena-mb 15 >"$OUT/linux/arena15.log" 2>&1
ARENA15_RC=$?
if [ "$ARENA15_RC" -eq 1 ] && grep -q 'usage: z9git' "$OUT/linux/arena15.log"; then
    pass_case "--arena-mb 15 (below minimum) is a usage error rc1"
else
    fail_case "--arena-mb 15 below minimum (rc=$ARENA15_RC)"
fi
"$PROG" clone "$TD/packed_repo" "$OUT/linux/arenamissing" --arena-mb >"$OUT/linux/arenamissing.log" 2>&1
ARENAMISS_RC=$?
if [ "$ARENAMISS_RC" -eq 1 ]; then
    pass_case "--arena-mb without a value is rc1"
else
    fail_case "--arena-mb without a value (rc=$ARENAMISS_RC)"
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

echo "== checkout untracked-collision preflight =="
COLL="$OUT/linux/clone_collision"
rm -rf "$COLL"
"$PROG" clone "$TD/packed_repo" "$COLL" >"$OUT/linux/clone_collision.log" 2>&1
printf 'keep me\n' > "$COLL/ref_a.txt"
cp "$COLL/big.txt" "$OUT/linux/collision_big.want"
printf 'ref: refs/heads/master\n' > "$OUT/linux/collision_head.want"
( cd "$COLL" && "$PROG" checkout refdelta ) >"$OUT/linux/collision.log" 2>&1
COLL_RC=$?
if [ "$COLL_RC" -eq 3 ] && grep -qi 'untracked' "$OUT/linux/collision.log"; then
    pass_case "checkout refuses an untracked target path with rc3"
else
    fail_case "checkout untracked collision (rc=$COLL_RC)"
    cat "$OUT/linux/collision.log" | sed 's/^/       /'
fi
if [ "$(cat "$COLL/ref_a.txt")" = "keep me" ]; then
    pass_case "collision left untracked ref_a.txt intact"
else
    fail_case "collision modified untracked ref_a.txt"
fi
if cmp -s "$OUT/linux/collision_big.want" "$COLL/big.txt" && [ -f "$COLL/docs/notes.txt" ]; then
    pass_case "collision left tracked worktree unchanged"
else
    fail_case "collision changed tracked worktree files"
fi
if cmp -s "$OUT/linux/collision_head.want" "$COLL/.git/HEAD" && [ ! -e "$COLL/ref_b.txt" ]; then
    pass_case "collision left HEAD and target-only files untouched"
else
    fail_case "collision changed HEAD or materialized target-only files"
fi

echo "== local idx synthesis (pack without idx) =="
SYNTH_SRC="$OUT/linux/synth_src"
SYNTH_CLONE="$OUT/linux/clone_synth"
rm -rf "$SYNTH_SRC" "$SYNTH_CLONE"
cp -R "$TD/packed_repo" "$SYNTH_SRC"
rm -f "$SYNTH_SRC"/objects/pack/*.idx
before_idx=$(find "$SYNTH_SRC/objects/pack" -name '*.idx' | wc -l)
"$PROG" clone "$SYNTH_SRC" "$SYNTH_CLONE" >"$OUT/linux/clone_synth.log" 2>&1
SYNTH_RC=$?
if [ "$before_idx" -eq 0 ] && [ "$SYNTH_RC" -eq 0 ]; then
    pass_case "clone synthesizes missing pack idx (rc0)"
else
    fail_case "clone with missing idx (before=$before_idx rc=$SYNTH_RC)"
    tail -10 "$OUT/linux/clone_synth.log" | sed 's/^/       /'
fi
SYNTH_OK=1
for pack in "$SYNTH_SRC"/objects/pack/*.pack; do
    bn=$(basename "$pack" .pack)
    idx="$SYNTH_CLONE/.git/objects/pack/$bn.idx"
    if [ -f "$idx" ] && git verify-pack -v "$idx" >"$OUT/linux/verify_$bn.log" 2>&1; then
        pass_case "git verify-pack accepts synthesized $bn.idx"
    else
        fail_case "git verify-pack rejected synthesized $bn.idx"
        tail -10 "$OUT/linux/verify_$bn.log" 2>/dev/null | sed 's/^/       /'
        SYNTH_OK=0
    fi
    orig_idx="$TD/packed_repo/objects/pack/$bn.idx"
    if cmp -s "$orig_idx" "$idx"; then
        pass_case "synthesized $bn.idx is byte-identical to the fixture idx"
    else
        fail_case "synthesized $bn.idx differs from the fixture idx"
        SYNTH_OK=0
    fi
done
if [ "$SYNTH_OK" -eq 1 ]; then
    check_worktree synth "$SYNTH_CLONE" "$TD/packed_repo" "$TD/goldens/packed.lstree"
    ( cd "$SYNTH_CLONE" && "$PROG" log ) >"$OUT/linux/synth_log.out" 2>&1
    if cmp -s "$OUT/linux/packed_log.want" "$OUT/linux/synth_log.out"; then
        pass_case "log golden from synthesized-idx clone"
    else
        fail_case "log golden from synthesized-idx clone"
    fi
fi

echo "== large synthetic external-memory idx (100k objects) =="
if [ "$HAVE_PYTHON" -eq 1 ]; then
    LARGE="$OUT/large_synth"
    rm -rf "$LARGE"
    if ! python3 "$APP_DIR/tests/gen_large_pack.py" "$LARGE" 100000 >"$OUT/large_gen.log" 2>&1; then
        fail_case "generate 100k-object synthetic pack"
        tail -10 "$OUT/large_gen.log" | sed 's/^/       /'
    else
        LARGE_BYTES=$(wc -c <"$LARGE/objects/pack/pack-large.pack" | tr -d ' ')
        pass_case "prepared 100000-object synthetic pack ($LARGE_BYTES bytes)"
        TIME_BIN=""
        if [ -x /usr/bin/time ]; then TIME_BIN="/usr/bin/time"; fi

        LARGE_CLONE="$OUT/linux/clone_large"
        rm -rf "$LARGE_CLONE"
        if [ -n "$TIME_BIN" ]; then
            "$TIME_BIN" -v "$PROG" clone "$LARGE" "$LARGE_CLONE" \
                >"$OUT/linux/large_clone.log" 2>"$OUT/linux/large_clone.time"
        else
            "$PROG" clone "$LARGE" "$LARGE_CLONE" \
                >"$OUT/linux/large_clone.log" 2>"$OUT/linux/large_clone.time"
        fi
        LARGE_RC=$?
        if [ "$LARGE_RC" -eq 0 ] && [ -f "$LARGE_CLONE/.git/HEAD" ]; then
            pass_case "clone 100k-object pack within the default 32 MiB arena (rc0)"
        else
            fail_case "clone 100k-object pack at default arena (rc=$LARGE_RC)"
            tail -15 "$OUT/linux/large_clone.log" | sed 's/^/       /'
        fi
        LARGE_IDX=$(find "$LARGE_CLONE/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
        if [ -n "$LARGE_IDX" ] && git verify-pack -v "$LARGE_IDX" >"$OUT/linux/large_verify.log" 2>&1; then
            pass_case "git verify-pack accepts the 100k-object synthesized idx"
        else
            fail_case "git verify-pack rejected the 100k-object idx"
            tail -10 "$OUT/linux/large_verify.log" 2>/dev/null | sed 's/^/       /'
        fi
        if [ "$LARGE_RC" -eq 0 ] && git --git-dir="$LARGE_CLONE/.git" fsck --full --no-dangling >"$OUT/linux/large_fsck.log" 2>&1; then
            pass_case "git fsck accepts the 100k-object clone"
        else
            fail_case "git fsck rejected the 100k-object clone"
            tail -10 "$OUT/linux/large_fsck.log" 2>/dev/null | sed 's/^/       /'
        fi
        if printf 'hello from the z9git large synthetic pack\n' | cmp -s - "$LARGE_CLONE/hello.txt"; then
            pass_case "100k-object clone worktree matches the source blob"
        else
            fail_case "100k-object clone worktree differs"
        fi
        if [ -n "$TIME_BIN" ]; then
            LARGE_FAST_ELAPSED=$(awk '/Elapsed \(wall clock\)/ {print $NF}' "$OUT/linux/large_clone.time" 2>/dev/null)
            pass_case "100k-object clone -ffast wall time ${LARGE_FAST_ELAPSED:-?}"
        fi
        LARGE_SAFE="$OUT/linux/clone_large_safe"
        rm -rf "$LARGE_SAFE"
        if [ -n "$TIME_BIN" ]; then
            "$TIME_BIN" -v "$PROG_SAFE" clone "$LARGE" "$LARGE_SAFE" \
                >"$OUT/linux/large_safe.log" 2>"$OUT/linux/large_safe.time"
        else
            "$PROG_SAFE" clone "$LARGE" "$LARGE_SAFE" \
                >"$OUT/linux/large_safe.log" 2>"$OUT/linux/large_safe.time"
        fi
        LARGE_SAFE_RC=$?
        if [ "$LARGE_SAFE_RC" -eq 0 ] && [ -f "$LARGE_SAFE/.git/HEAD" ]; then
            pass_case "100k-object -fsafe measurement clone exit 0"
        else
            fail_case "100k-object -fsafe measurement clone (rc=$LARGE_SAFE_RC)"
            tail -15 "$OUT/linux/large_safe.log" | sed 's/^/       /'
        fi
        if [ -n "$TIME_BIN" ]; then
            LARGE_RSS=$(awk '/Maximum resident set size/ {print $6}' "$OUT/linux/large_safe.time" 2>/dev/null)
            LARGE_SAFE_ELAPSED=$(awk '/Elapsed \(wall clock\)/ {print $NF}' "$OUT/linux/large_safe.time" 2>/dev/null)
            if [ -n "$LARGE_RSS" ]; then
                pass_case "100k-object -fsafe peak RSS ${LARGE_RSS} kB (elapsed ${LARGE_SAFE_ELAPSED:-?})"
                if [ "$LARGE_RSS" -lt 131072 ]; then
                    pass_case "100k-object -fsafe peak RSS is below 128 MiB"
                else
                    fail_case "100k-object -fsafe peak RSS ${LARGE_RSS} kB exceeds 128 MiB"
                fi
            else
                fail_case "could not read peak RSS from $OUT/linux/large_safe.time"
            fi
        else
            echo "SKIP - 100k-object peak RSS: /usr/bin/time not available"
        fi

        LARGE_CLONE16="$OUT/linux/clone_large_16"
        rm -rf "$LARGE_CLONE16"
        "$PROG" clone "$LARGE" "$LARGE_CLONE16" --arena-mb 16 \
            >"$OUT/linux/large_clone16.log" 2>"$OUT/linux/large_clone16.time"
        LARGE16_RC=$?
        if [ "$LARGE16_RC" -eq 0 ] && [ -f "$LARGE_CLONE16/.git/HEAD" ]; then
            pass_case "clone 100k-object pack with --arena-mb 16 (minimum)"
        else
            fail_case "clone 100k-object pack with --arena-mb 16 (rc=$LARGE16_RC)"
            tail -15 "$OUT/linux/large_clone16.log" | sed 's/^/       /'
        fi
        LARGE16_IDX=$(find "$LARGE_CLONE16/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
        if [ -n "$LARGE16_IDX" ] && git verify-pack -v "$LARGE16_IDX" >"$OUT/linux/large16_verify.log" 2>&1; then
            pass_case "git verify-pack accepts the --arena-mb 16 synthesized idx"
        else
            fail_case "git verify-pack rejected the --arena-mb 16 idx"
            tail -10 "$OUT/linux/large16_verify.log" 2>/dev/null | sed 's/^/       /'
        fi
        if [ "$LARGE16_RC" -eq 0 ] && git --git-dir="$LARGE_CLONE16/.git" fsck --full --no-dangling >"$OUT/linux/large16_fsck.log" 2>&1; then
            pass_case "git fsck accepts the --arena-mb 16 clone"
        else
            fail_case "git fsck rejected the --arena-mb 16 clone"
            tail -10 "$OUT/linux/large16_fsck.log" 2>/dev/null | sed 's/^/       /'
        fi
    fi
else
    echo "SKIP - large synthetic external-memory idx: python3 not installed"
fi

echo "== real remote melonDS (HTTPS, default 32 MiB) =="
if [ "${Z98_NET:-0}" = "1" ]; then
    MELON_URL="https://github.com/melonDS-emu/melonDS.git"
    MELON="$OUT/linux/clone_melon"
    rm -rf "$MELON"
    TIME_BIN=""
    if [ -x /usr/bin/time ]; then TIME_BIN="/usr/bin/time"; fi
    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v timeout 1800 "$PROG" clone "$MELON_URL" "$MELON" \
            >"$OUT/linux/melon.log" 2>"$OUT/linux/melon.time"
    else
        timeout 1800 "$PROG" clone "$MELON_URL" "$MELON" \
            >"$OUT/linux/melon.log" 2>"$OUT/linux/melon.time"
    fi
    MELON_RC=$?
    if [ "$MELON_RC" -eq 0 ] && [ -f "$MELON/.git/HEAD" ]; then
        pass_case "melonDS real HTTPS clone exit 0 (default 32 MiB arena)"
    else
        fail_case "melonDS real HTTPS clone (rc=$MELON_RC)"
        tail -20 "$OUT/linux/melon.log" | sed 's/^/       /'
    fi
    MELON_IDX=$(find "$MELON/.git/objects/pack" -maxdepth 1 -name '*.idx' 2>/dev/null | head -1)
    if [ -n "$MELON_IDX" ] && git verify-pack -v "$MELON_IDX" >"$OUT/linux/melon_verify.log" 2>&1; then
        pass_case "git verify-pack accepts the melonDS synthesized idx"
    else
        fail_case "git verify-pack rejected the melonDS idx"
        tail -10 "$OUT/linux/melon_verify.log" 2>/dev/null | sed 's/^/       /'
    fi
    if [ "$MELON_RC" -eq 0 ] && git --git-dir="$MELON/.git" fsck --full --no-dangling >"$OUT/linux/melon_fsck.log" 2>&1; then
        pass_case "git fsck accepts the melonDS clone"
    else
        fail_case "git fsck rejected the melonDS clone"
        tail -10 "$OUT/linux/melon_fsck.log" 2>/dev/null | sed 's/^/       /'
    fi
    MELON_REMOTE_HEAD=$(timeout 120 git ls-remote "$MELON_URL" HEAD 2>/dev/null | awk '{print $1}' | head -1)
    MELON_LOCAL_HEAD=$(git --git-dir="$MELON/.git" rev-parse HEAD 2>/dev/null)
    if [ -n "$MELON_REMOTE_HEAD" ] && [ "$MELON_REMOTE_HEAD" = "$MELON_LOCAL_HEAD" ]; then
        pass_case "melonDS HEAD matches the remote ($MELON_LOCAL_HEAD)"
    else
        fail_case "melonDS HEAD mismatch (remote=${MELON_REMOTE_HEAD:-?} local=${MELON_LOCAL_HEAD:-?})"
    fi
    if [ "$MELON_RC" -eq 0 ]; then
        git --git-dir="$MELON/.git" ls-tree -r HEAD | awk '$1 != "120000" && $1 != "160000"' >"$OUT/linux/melon.lstree"
        check_worktree melon "$MELON" "$MELON/.git" "$OUT/linux/melon.lstree"
    fi
    if [ -n "$TIME_BIN" ]; then
        MELON_ELAPSED=$(awk '/Elapsed \(wall clock\)/ {print $NF}' "$OUT/linux/melon.time" 2>/dev/null)
        pass_case "melonDS -ffast wall time ${MELON_ELAPSED:-?}"
    fi

    MELON_SAFE="$OUT/linux/clone_melon_safe"
    MELON_SAFE_SRC="$OUT/linux/melon_safe_src"
    rm -rf "$MELON_SAFE" "$MELON_SAFE_SRC"
    mkdir -p "$MELON_SAFE_SRC/objects/pack"
    for mp in "$MELON/.git/objects/pack"/*.pack; do
        [ -f "$mp" ] && ln "$mp" "$MELON_SAFE_SRC/objects/pack/"
    done
    cp -R "$MELON/.git/refs" "$MELON_SAFE_SRC/refs"
    cp "$MELON/.git/HEAD" "$MELON_SAFE_SRC/"
    if [ -f "$MELON/.git/packed-refs" ]; then
        cp "$MELON/.git/packed-refs" "$MELON_SAFE_SRC/"
    fi
    if [ -n "$(find "$MELON_SAFE_SRC/objects/pack" -name '*.pack' -print -quit)" ]; then
        pass_case "prepared melonDS local idx-synthesis source for -fsafe RSS"
    else
        fail_case "could not prepare melonDS local -fsafe source"
    fi
    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v timeout 1800 "$PROG_SAFE" clone "$MELON_SAFE_SRC" "$MELON_SAFE" \
            >"$OUT/linux/melon_safe.log" 2>"$OUT/linux/melon_safe.time"
    else
        timeout 1800 "$PROG_SAFE" clone "$MELON_SAFE_SRC" "$MELON_SAFE" \
            >"$OUT/linux/melon_safe.log" 2>"$OUT/linux/melon_safe.time"
    fi
    MELON_SAFE_RC=$?
    if [ "$MELON_SAFE_RC" -eq 0 ] && [ -f "$MELON_SAFE/.git/HEAD" ]; then
        pass_case "melonDS -fsafe measurement clone exit 0"
    else
        fail_case "melonDS -fsafe measurement clone (rc=$MELON_SAFE_RC)"
        tail -20 "$OUT/linux/melon_safe.log" | sed 's/^/       /'
    fi
    if [ -n "$TIME_BIN" ]; then
        MELON_RSS=$(awk '/Maximum resident set size/ {print $6}' "$OUT/linux/melon_safe.time" 2>/dev/null)
        MELON_SAFE_ELAPSED=$(awk '/Elapsed \(wall clock\)/ {print $NF}' "$OUT/linux/melon_safe.time" 2>/dev/null)
        if [ -n "$MELON_RSS" ]; then
            pass_case "melonDS -fsafe peak RSS ${MELON_RSS} kB (elapsed ${MELON_SAFE_ELAPSED:-?})"
            if [ "$MELON_RSS" -lt 131072 ]; then
                pass_case "melonDS -fsafe peak RSS is below 128 MiB"
            else
                fail_case "melonDS -fsafe peak RSS ${MELON_RSS} kB exceeds 128 MiB"
            fi
        else
            fail_case "could not read melonDS peak RSS"
        fi
    else
        echo "SKIP - melonDS peak RSS: /usr/bin/time not available"
    fi
else
    echo "SKIP - real remote melonDS: set Z98_NET=1 to enable the network test"
fi

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

echo "== 40 MiB loose object at the default 32 MiB arena =="
LOOSE_BIG_SRC="$OUT/loose_big_src"
LOOSE_BIG="$OUT/linux/clone_loose_big"
rm -rf "$LOOSE_BIG_SRC" "$LOOSE_BIG"
if ! (
    git init -q "$LOOSE_BIG_SRC" &&
    cd "$LOOSE_BIG_SRC" &&
    git config user.name "z9 fixture" &&
    git config user.email "z9@example.invalid" &&
    head -c 40000000 /dev/urandom >big.bin &&
    printf 'small loose\n' >small.txt &&
    git add big.bin small.txt &&
    git commit -q -m "40 MiB loose blob"
) >"$OUT/loose_big_build.log" 2>&1; then
    fail_case "prepare 40 MiB loose fixture"
    tail -10 "$OUT/loose_big_build.log" | sed 's/^/       /'
else
    "$PROG" clone "$LOOSE_BIG_SRC" "$LOOSE_BIG" >"$OUT/linux/clone_loose_big.log" 2>&1
    LOOSE_BIG_RC=$?
    if [ "$LOOSE_BIG_RC" -eq 0 ] && cmp -s "$LOOSE_BIG_SRC/big.bin" "$LOOSE_BIG/big.bin"; then
        pass_case "40 MiB loose blob clone matches at default arena"
    else
        fail_case "40 MiB loose blob clone failed (rc=$LOOSE_BIG_RC)"
        tail -10 "$OUT/linux/clone_loose_big.log" | sed 's/^/       /'
    fi
    if find "$LOOSE_BIG/.git" -name 'z9big-*' -print | grep -q .; then
        fail_case "40 MiB loose clone left a z9big temp file"
    else
        pass_case "40 MiB loose clone left no z9big temp file"
    fi
fi

echo "== checkout preflight/removal bounded at the default 32 MiB arena =="
TREE_SRC="$OUT/tree_src"
TREE_CLONE="$OUT/linux/clone_tree_4k"
rm -rf "$TREE_SRC" "$TREE_CLONE"
TREE_PAD=$(printf '%0200d' 0)
if ! (
    git init -q "$TREE_SRC" &&
    cd "$TREE_SRC" &&
    git config user.name "z9 fixture" &&
    git config user.email "z9@example.invalid" &&
    d=0 && while [ "$d" -lt 100 ]; do
        mkdir "d$d"
        f=0 && while [ "$f" -lt 40 ]; do
            printf 'A\n' >"d$d/f_${d}_${f}_${TREE_PAD}"
            f=$((f + 1))
        done
        d=$((d + 1))
    done &&
    git add -A && git commit -q -m A && git branch brA &&
    d=0 && while [ "$d" -lt 100 ]; do
        f=0 && while [ "$f" -lt 40 ]; do
            rm "d$d/f_${d}_${f}_${TREE_PAD}"
            printf 'B\n' >"d$d/g_${d}_${f}_${TREE_PAD}"
            f=$((f + 1))
        done
        d=$((d + 1))
    done &&
    git add -A && git commit -q -m B && git branch brB &&
    git repack -adq && git prune-packed
) >"$OUT/tree_build.log" 2>&1; then
    fail_case "prepare 4k/deep-tree checkout fixture"
    tail -10 "$OUT/tree_build.log" | sed 's/^/       /'
else
    "$PROG" clone "$TREE_SRC" "$TREE_CLONE" >"$OUT/linux/clone_tree_4k.log" 2>&1
    TREE_CLONE_RC=$?
    if [ "$TREE_CLONE_RC" -eq 0 ]; then
        pass_case "4k/deep-tree clone exit 0 at default arena"
    else
        fail_case "4k/deep-tree clone failed (rc=$TREE_CLONE_RC)"
        tail -10 "$OUT/linux/clone_tree_4k.log" | sed 's/^/       /'
    fi
    ( cd "$TREE_CLONE" && "$PROG" checkout brA ) >"$OUT/linux/tree_checkout_a.log" 2>&1
    TREE_CO_A=$?
    TREE_A_N=$(find "$TREE_CLONE" -path "$TREE_CLONE/.git" -prune -o -type f -name 'f_*' -print | wc -l)
    if [ "$TREE_CO_A" -eq 0 ] && [ "$TREE_A_N" -eq 4000 ]; then
        pass_case "4k/deep-tree checkout/removal brA completes at default arena"
    else
        fail_case "4k/deep-tree checkout brA failed (rc=$TREE_CO_A files=$TREE_A_N)"
        tail -10 "$OUT/linux/tree_checkout_a.log" | sed 's/^/       /'
    fi
    ( cd "$TREE_CLONE" && "$PROG" checkout brB ) >"$OUT/linux/tree_checkout_b.log" 2>&1
    TREE_CO_B=$?
    TREE_B_N=$(find "$TREE_CLONE" -path "$TREE_CLONE/.git" -prune -o -type f -name 'g_*' -print | wc -l)
    if [ "$TREE_CO_B" -eq 0 ] && [ "$TREE_B_N" -eq 4000 ]; then
        pass_case "4k/deep-tree checkout/removal brB completes at default arena"
    else
        fail_case "4k/deep-tree checkout brB failed (rc=$TREE_CO_B files=$TREE_B_N)"
        tail -10 "$OUT/linux/tree_checkout_b.log" | sed 's/^/       /'
    fi
fi

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

echo "== directory -> file transition =="
DF_SRC="$OUT/linux/dirfile_src"
DF_BARE="$OUT/linux/dirfile_bare.git"
DF_WORK="$OUT/linux/clone_dirfile"
rm -rf "$DF_SRC" "$DF_BARE" "$DF_WORK"
mkdir -p "$DF_SRC"
(
    cd "$DF_SRC" || exit 1
    git init -q
    git config user.name "z9 fixture"
    git config user.email "z9@example.invalid"
    printf 'keep\n' > keep.txt
    mkdir pkg
    printf 'inside\n' > pkg/inside.txt
    git add -A
    git commit -q -m "branch A directory"
    git branch A
    git checkout -q -b B
    git rm -q -r pkg
    printf 'now a file\n' > pkg
    git add pkg
    git commit -q -m "branch B file"
    git checkout -q A
) >"$OUT/linux/dirfile_build.log" 2>&1
git clone --bare --no-hardlinks -q "$DF_SRC" "$DF_BARE" >>"$OUT/linux/dirfile_build.log" 2>&1
"$PROG" clone "$DF_BARE" "$DF_WORK" >"$OUT/linux/dirfile_clone.log" 2>&1
DF_CLONE_RC=$?
if [ "$DF_CLONE_RC" -eq 0 ] && [ -f "$DF_WORK/pkg/inside.txt" ]; then
    pass_case "dir->file fixture cloned on branch A"
else
    fail_case "dir->file fixture clone (rc=$DF_CLONE_RC)"
    tail -10 "$OUT/linux/dirfile_build.log" | sed 's/^/       /'
fi
cp "$DF_WORK/.git/HEAD" "$OUT/linux/dirfile_head.want"
( cd "$DF_WORK" && "$PROG" checkout B ) >"$OUT/linux/dirfile_checkout.log" 2>&1
DF_RC=$?
if [ "$DF_RC" -eq 3 ] && grep -qi 'directory' "$OUT/linux/dirfile_checkout.log"; then
    pass_case "dir->file checkout refuses before mutating (rc3)"
else
    fail_case "dir->file checkout refusal (rc=$DF_RC)"
    cat "$OUT/linux/dirfile_checkout.log" | sed 's/^/       /'
fi
if [ -d "$DF_WORK/pkg" ] && [ "$(cat "$DF_WORK/pkg/inside.txt")" = "inside" ] && \
   [ -f "$DF_WORK/keep.txt" ] && cmp -s "$OUT/linux/dirfile_head.want" "$DF_WORK/.git/HEAD"; then
    pass_case "dir->file refusal left tree and HEAD unchanged"
else
    fail_case "dir->file refusal mutated the worktree or HEAD"
fi

echo "== linked-worktree gitfile source =="
LW_MAIN="$OUT/linux/linked_main.git"
LW_WT="$OUT/linux/linked_wt"
LW_CLONE="$OUT/linux/clone_linked"
rm -rf "$LW_MAIN" "$LW_WT" "$LW_CLONE"
cp -R "$TD/loose_repo" "$LW_MAIN"
git --git-dir="$LW_MAIN" worktree add -q "$LW_WT" master >"$OUT/linux/linked_add.log" 2>&1
if [ -f "$LW_WT/.git" ] && grep -q '^gitdir: ' "$LW_WT/.git"; then
    pass_case "prepared linked worktree with a .git gitfile"
else
    fail_case "could not prepare linked worktree"
    tail -10 "$OUT/linux/linked_add.log" | sed 's/^/       /'
fi
"$PROG" clone "$LW_WT" "$LW_CLONE" >"$OUT/linux/clone_linked.log" 2>&1
LW_RC=$?
( cd "$LW_CLONE" 2>/dev/null && "$PROG" log ) >"$OUT/linux/linked_log.out" 2>&1
if [ "$LW_RC" -eq 0 ] && cmp -s "$OUT/linux/loose_log.want" "$OUT/linux/linked_log.out"; then
    pass_case "clone resolves linked-worktree gitfile + commondir"
else
    fail_case "clone from linked-worktree gitfile (rc=$LW_RC)"
    tail -10 "$OUT/linux/clone_linked.log" | sed 's/^/       /'
fi

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

mkdir -p "$WINEPREFIX"
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

echo "== Windows: mocked smart HTTP under Wine =="
mkdir -p "$OUT/mock_emit"
timeout 300 "$ZIG" -osw -o "$OUT/mock_emit" "$APP_DIR/tests/mock_http.zig" >"$OUT/mock_emit.log" 2>&1
MOCK_EMIT_RC=$?
if [ "$MOCK_EMIT_RC" -ne 0 ]; then
    fail_case "mock_http bare -osw emit (rc=$MOCK_EMIT_RC; STOP)"
    tail -20 "$OUT/mock_emit.log" | sed 's/^/       /'
    finish
fi
pass_case "mock_http bare -osw emit"

if [ -f "$OUT/mock_emit/build_target.sh" ] && \
   grep -q -- '-DZIG_NO_CRT' "$OUT/mock_emit/build_target.sh" && \
   grep -q -- '-nostdlib' "$OUT/mock_emit/build_target.sh" && \
   grep -q -- '-lkernel32' "$OUT/mock_emit/build_target.sh"; then
    pass_case "mock_http emitted recipe is 9x no-CRT"
else
    fail_case "mock_http emitted build_target.sh is not the 9x no-CRT recipe (STOP)"
    finish
fi

MOCK_EXE="$OUT/mock_http.exe"
if sh "$OUT/mock_emit/build_target.sh" mingw "$MOCK_EXE" >"$OUT/mock_win_build.log" 2>&1 && [ -f "$MOCK_EXE" ]; then
    pass_case "MinGW no-CRT build produced mock_http.exe"
else
    fail_case "MinGW no-CRT mock_http build failed (STOP: no CRT/nt fallback)"
    tail -20 "$OUT/mock_win_build.log" | sed 's/^/       /'
    finish
fi
if bash "$CHECK" "$MOCK_EXE" 9x >"$OUT/mock_imports.log" 2>&1; then
    pass_case "mock_http check_win9x_imports.sh 9x PASS"
else
    fail_case "mock_http import gate FAILED (STOP; see $OUT/mock_imports.log)"
    tail -20 "$OUT/mock_imports.log" | sed 's/^/       /'
    finish
fi

cp "$MOCK_DATA/info_refs" "$OUT/wine/info_refs"
cp "$MOCK_DATA/upload" "$OUT/wine/upload"
rm -rf "$OUT/wine/clone_mock_win"
( cd "$OUT/wine" && timeout 180 wine "$MOCK_EXE" "http://mock.invalid/r.git" clone_mock_win 0 info_refs upload mock_requests_win.log ) \
    >"$OUT/wine_mock.log" 2>&1
WIN_MOCK_RC=$?
if [ "$WIN_MOCK_RC" -eq 0 ] && [ -f "$OUT/wine/clone_mock_win/.git/HEAD" ]; then
    pass_case "Wine mocked-transport clone exit 0"
else
    fail_case "Wine mocked-transport clone (got $WIN_MOCK_RC; STOP: see $OUT/wine_mock.log)"
    tail -15 "$OUT/wine_mock.log" | sed 's/^/       /'
    finish
fi
WIN_MOCK_IDX=$(find "$OUT/wine/clone_mock_win/.git/objects/pack" -maxdepth 1 -name '*.idx' | head -1)
if [ -n "$WIN_MOCK_IDX" ] && git verify-pack -v "$WIN_MOCK_IDX" >"$OUT/wine_mock_verify.log" 2>&1; then
    pass_case "Wine mocked clone idx verifies"
else
    fail_case "Wine mocked clone idx failed verify-pack"
    tail -10 "$OUT/wine_mock_verify.log" 2>/dev/null | sed 's/^/       /'
    finish
fi
if cmp -s "$TD/packed_repo/HEAD" "$OUT/wine/clone_mock_win/.git/HEAD"; then
    pass_case "Wine mocked clone HEAD matches source"
else
    fail_case "Wine mocked clone HEAD differs (STOP)"
    finish
fi

finish
