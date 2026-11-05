#!/usr/bin/env bash
# gen_repos.sh -- regenerate the committed z9git fixture object stores.
#
# Run once from anywhere (paths are resolved from this script), then commit the
# result.  The unit tier never calls this script: it consumes the committed
# bytes.  Requires git (fixtures recorded with 2.39) and gcc + zlib for the
# synthetic generator.
#
# Fixtures written under tests/testdata/:
#   packed_repo/        bare repo, history + annotated/lightweight tags.
#                       `git -c pack.useOfsDelta=true gc` produces one pack v2
#                       + idx v2 with an OFS_DELTA chain (depth >= 2).  A
#                       second branch is then written with plumbing and packed
#                       separately with `pack-objects --no-delta-base-offset`,
#                       so that pack's deltas are REF_DELTA.  Loose duplicates
#                       are pruned.  No nested .git.
#   loose_repo/         bare repo, no gc: loose objects only (objects/pack is
#                       removed).
#   hybrid_repo/        SYNTHETIC: real git cannot leave a thin REF_DELTA pack
#                       in an object store (the base must be outside the pack),
#                       so gen_synthetic.c writes the pack v2, a valid idx v2
#                       listing only the delta object, and the loose base
#                       object directly.  The delta is COPY(base) + INSERT.
#   large_offset_repo/  SYNTHETIC: one normal blob whose idx v2 offset field is
#                       0x80000000 (8-byte large-offset slot 0) pointing at the
#                       real offset 12.  Exercises the indirection decoder
#                       without a >2 GiB pack.
#
# Goldens (tests/testdata/goldens/):
#   packed.catfile, loose.catfile   `git cat-file --batch-all-objects --batch`
#   packed.lstree, loose.lstree     `git ls-tree -r HEAD`
#   hybrid.catfile, large_offset.catfile   synthetic cat-file-style records
#
# Dates/identities are fixed so regeneration is reproducible.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TD="$SCRIPT_DIR/testdata"
WORK="${WORK:-/tmp/z9git_fixture_work}"

rm -rf "$WORK" "$TD"
mkdir -p "$WORK" "$TD/goldens"

export GIT_AUTHOR_NAME="z9 fixture"
export GIT_AUTHOR_EMAIL="z9@example.invalid"
export GIT_COMMITTER_NAME="z9 fixture"
export GIT_COMMITTER_EMAIL="z9@example.invalid"
export GIT_AUTHOR_DATE="2005-04-07T22:13:13 +0000"
export GIT_COMMITTER_DATE="2005-04-07T22:13:13 +0000"

# One stable 500-line body; `rev` changes exactly one line so successive
# revisions delta extremely well.
write_big() {
    out="$1"
    rev="$2"
    i=0
    : > "$out"
    while [ "$i" -lt 500 ]; do
        if [ "$i" -eq "$rev" ]; then
            printf 'line %04d: revision marker %s unique change\n' "$i" "$rev" >> "$out"
        else
            printf 'line %04d: shared stable body text for delta chains\n' "$i" >> "$out"
        fi
        i=$((i + 1))
    done
}

# Rewrite refs as loose files and drop packed-refs.  git's packed-refs header
# line carries a trailing space on some versions, which `git diff --check`
# rejects in a committed fixture; the object database does not need packed
# refs either.
unpack_refs() {
    ur_gd="$1"
    git --git-dir="$ur_gd" show-ref > "$WORK/refs_all.txt" || true
    rm -f "$ur_gd/packed-refs"
    while IFS=' ' read -r ur_oid ur_name; do
        case "$ur_name" in
            refs/*) ;;
            *) continue ;;
        esac
        mkdir -p "$(dirname "$ur_gd/$ur_name")"
        printf '%s\n' "$ur_oid" > "$ur_gd/$ur_name"
    done < "$WORK/refs_all.txt"
}

echo "== packed_repo =="
git init -q "$WORK/packed_src"
(
    cd "$WORK/packed_src"
    mkdir -p docs
    write_big big.txt 1
    printf 'packed fixture notes, revision 1\n' > docs/notes.txt
    git add -A
    git commit -q -m "initial packed history"
    r=2
    while [ "$r" -le 6 ]; do
        write_big big.txt "$r"
        printf 'packed fixture notes, revision %s\n' "$r" > docs/notes.txt
        git add -A
        git commit -q -m "packed revision $r"
        r=$((r + 1))
    done
    git tag -a v1 -m "annotated packed tag"
    git tag lightweight
)
git clone --bare --no-hardlinks -q "$WORK/packed_src" "$TD/packed_repo"
git --git-dir="$TD/packed_repo" remote remove origin
git --git-dir="$TD/packed_repo" -c pack.useOfsDelta=true gc --prune=now -q

ofs_idx="$(ls "$TD/packed_repo"/objects/pack/*.idx | head -1)"
git verify-pack -v "$ofs_idx" > "$WORK/ofs_verify.txt"
if ! grep -Eq 'chain length = [2-9]' "$WORK/ofs_verify.txt"; then
    echo "error: gc pack has no OFS_DELTA chain of depth >= 2" >&2
    cat "$WORK/ofs_verify.txt" >&2
    exit 1
fi

# Second, disjoint branch packed with REF_DELTA only.
GD="$TD/packed_repo"
write_big "$WORK/ref_a.txt" 10
write_big "$WORK/ref_b.txt" 20
blob_a="$(git --git-dir="$GD" hash-object -w "$WORK/ref_a.txt")"
blob_b="$(git --git-dir="$GD" hash-object -w "$WORK/ref_b.txt")"
tree="$(printf '100644 blob %s\tref_a.txt\n100644 blob %s\tref_b.txt\n' "$blob_a" "$blob_b" |
    git --git-dir="$GD" mktree)"
commit="$(git --git-dir="$GD" commit-tree "$tree" -m "ref delta commit")"
git --git-dir="$GD" update-ref refs/heads/refdelta "$commit"
printf '%s\n' "$commit" |
    git --git-dir="$GD" pack-objects --revs --no-delta-base-offset \
        --window=50 --depth=50 "$GD/objects/pack/refpack" >/dev/null
ref_pack="$(ls "$GD"/objects/pack/refpack-*.pack | head -1)"
git --git-dir="$GD" index-pack "$ref_pack" >/dev/null
git --git-dir="$GD" prune-packed
ref_idx="$(ls "$GD"/objects/pack/refpack-*.idx | head -1)"
git verify-pack -v "$ref_idx" > "$WORK/ref_verify.txt"
ref_deltas="$(grep -Ec '^[0-9a-f]{40} +(commit|tree|blob|tag) +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9a-f]{40}$' "$WORK/ref_verify.txt" || true)"
if [ "$ref_deltas" -eq 0 ]; then
    echo "error: REF pack has no delta entries" >&2
    cat "$WORK/ref_verify.txt" >&2
    exit 1
fi
ref_delta_ids="$(grep -E '^[0-9a-f]{40} +(commit|tree|blob|tag) +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9a-f]{40}$' "$WORK/ref_verify.txt" | cut -d' ' -f1)"
printf '%s\n' $ref_delta_ids | git --git-dir="$GD" cat-file --batch |
    head -c -1 > "$TD/goldens/packed_ref_deltas.catfile"

git --git-dir="$GD" cat-file --batch-all-objects --batch > "$TD/goldens/packed.catfile"
git --git-dir="$GD" ls-tree -r HEAD > "$TD/goldens/packed.lstree"
ofs_delta_ids="$(grep -E '^[0-9a-f]{40} +(commit|tree|blob|tag) +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9a-f]{40}$' "$WORK/ofs_verify.txt" | cut -d' ' -f1)"
if [ -z "$ofs_delta_ids" ]; then
    echo "error: could not extract OFS_DELTA object ids" >&2
    exit 1
fi
printf '%s\n' $ofs_delta_ids | git --git-dir="$GD" cat-file --batch |
    head -c -1 > "$TD/goldens/packed_ofs_deltas.catfile"

unpack_refs "$GD"
rm -f "$GD/objects/info/packs" "$GD/info/refs"

echo "== loose_repo =="
git init -q "$WORK/loose_src"
(
    cd "$WORK/loose_src"
    mkdir -p docs
    write_big big.txt 3
    printf 'loose fixture notes\n' > docs/notes.txt
    printf 'loose fixture second blob\n' > second.txt
    git add -A
    git commit -q -m "initial loose history"
    write_big big.txt 4
    git add -A
    git commit -q -m "second loose revision"
    git tag -a v1 -m "annotated loose tag"
    git tag lightweight
)
git clone --bare --no-hardlinks -q "$WORK/loose_src" "$TD/loose_repo"
git --git-dir="$TD/loose_repo" remote remove origin
rm -rf "$TD/loose_repo/objects/pack"
if find "$TD/loose_repo/objects" -name '*.pack' -o -name '*.idx' | grep -q .; then
    echo "error: loose_repo unexpectedly contains pack/idx files" >&2
    exit 1
fi
git --git-dir="$TD/loose_repo" cat-file --batch-all-objects --batch > "$TD/goldens/loose.catfile"
git --git-dir="$TD/loose_repo" ls-tree -r HEAD > "$TD/goldens/loose.lstree"
unpack_refs "$TD/loose_repo"
rm -f "$TD/loose_repo/objects/info/packs" "$TD/loose_repo/info/refs"

echo "== synthetic fixtures =="
gcc -O2 -o "$WORK/gen_synthetic" "$SCRIPT_DIR/gen_synthetic.c" -lz
"$WORK/gen_synthetic" "$TD"

# Sanity: Git itself agrees with both synthetic idx offset encodings.
git show-index < "$TD/hybrid_repo/objects/pack/pack-hybrid.idx" >/dev/null
git show-index < "$TD/large_offset_repo/objects/pack/pack-large.idx" >/dev/null

echo "== fixture summary =="
find "$TD" -type f | sort
echo "OK"
