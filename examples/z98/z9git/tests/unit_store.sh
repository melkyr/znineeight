#!/bin/sh
# unit_store.sh -- Phase 3 Task 6 gate for the z9git object store.
#
# Builds examples/z98/z9git/tests/store_test.zig with the seed-built zig1 and
# runs the committed fixture cases (packed cat-file golden, loose cat-file
# golden, OFS_DELTA chain objects, REF_DELTA pack objects, hybrid REF_DELTA
# across pack/loose, synthetic large-offset idx, loose write round-trip,
# NotFound, malformed idx/pack Corrupt, and direct delta copy/insert plus
# out-of-range Corrupt cases).  The test prints a PASS/FAIL count and exits
# nonzero on any failure; this wrapper forwards that status.
#
# The fixture bytes are consumed as-is; gen_repos.sh is dev-time only.
#
# Env: ZIG  seed-built zig1_5_clean (default /tmp/p3_t6_base/zig1_5_clean)
#      OUT  scratch dir (default /tmp/z9git_store_test)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
ZIG="${ZIG:-/tmp/p3_t6_base/zig1_5_clean}"
OUT="${OUT:-/tmp/z9git_store_test}"

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p3_t6_base"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/build" "$OUT/bad_idx/objects/pack" "$OUT/bad_pack/objects/pack"
cp -R "$SCRIPT_DIR/testdata/loose_repo" "$OUT/write_repo"

cd "$ROOT" || exit 1

echo "== build z9git store_test with the seed compiler =="
if ! "$ZIG" -osl --output-dir "$OUT/build" \
    examples/z98/z9git/tests/store_test.zig >"$OUT/zig.log" 2>&1; then
    echo "FAIL: zig compile (see $OUT/zig.log)"
    tail -40 "$OUT/zig.log" | sed 's/^/       /'
    exit 1
fi
if ! sh "$OUT/build/build_target.sh" linux "$OUT/build/store_test" >"$OUT/build.log" 2>&1; then
    echo "FAIL: target link (see $OUT/build.log)"
    tail -40 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi

echo "== run store_test =="
"$OUT/build/store_test" "$SCRIPT_DIR" "$OUT" >"$OUT/run.log" 2>&1
RC=$?
sed 's/^/       /' "$OUT/run.log"
if [ "$RC" -ne 0 ]; then
    echo "UNIT_STORE FAIL"
    exit 1
fi
echo "UNIT_STORE PASS"
