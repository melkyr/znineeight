#!/usr/bin/env bash
set -euo pipefail
# usage:
#   scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> <out_tgz> [--update-changelog]
#
# Assemble a fresh zig1-seed/ tree (spec layout: docs/superpowers/specs/
# 2026-09-07-seed-bootstrap-migration-design.md) and pack <out_tgz>. Used at
# every future plan closeout to rotate the committed seed
# (release/seed/zig1-seed.tgz). Idempotent — deterministic given the same
# inputs.
#
# Tree assembled from the given inputs + the repo:
#   zig1        copy of <zig1_binary>
#   gen/        <gen_dir>/*.c + *.h  (the seed's self-emission C89 module set;
#               spill/scratch files are NOT copied, and the six runtime/platform
#               support files the emitter now writes into DIR are excluded —
#               they already live in runtime/ (c_exit.c at top level), and the
#               three support .c would double-link against the runtime trio)
#   c_exit.c    repo sf/src/c_exit.c (top level, per spec layout)
#   runtime/    repo sf/src/include/{zig_compat.h, zig_runtime.h,
#               zig_special_types.h, zig_runtime.c, zig_pal.c}  (net_prelude.h
#               excluded — 0 references in a linux -osl self-emission dump)
#   lib/        repo sf/src/{std.zig, std_io.zig, std_arena.zig, std_net.zig,
#               std_str.zig, std_mem.zig, std_math.zig, std_debug.zig}
#   SEED_README.txt  provenance + rebuild recipes + canonical flag-set rule
#
# Before packing, the archive's C is gcc-rebuilt self-contained in a scratch dir
# (the module gen/ C plus the runtime support sources staged alongside it, one
# alphabetical *.o glob — the same object order build_from_seed.sh uses) — this
# proves the archive is gcc-only rebuildable AND yields the recorded
# self-emission fixed-point md5.
#
# The CHANGELOG.md entry (date, HEAD sha, binary md5, C count, fixed-point md5,
# archive md5) is always printed to stdout. With --update-changelog it is also
# prepended to the rotation changelog (default release/seed/CHANGELOG.md;
# override with env SEED_CHANGELOG for testing) — newest-first, after the
# file's preamble header.

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

UPDATE_CHANGELOG=0
if [ "${4:-}" = "--update-changelog" ]; then UPDATE_CHANGELOG=1; fi
[ "$#" -ge 3 ] || die "usage: archive_seed.sh <zig1_binary> <gen_dir> <out_tgz> [--update-changelog]"
BIN="$1"
GENDIR="$2"
OUTTGZ="$3"

[ -x "$BIN" ] || die "zig1 binary '$BIN' not found or not executable"
[ -d "$GENDIR" ] || die "gen dir '$GENDIR' not found"
C_COUNT=$(ls "$GENDIR"/*.c 2>/dev/null | wc -l)
H_COUNT=$(ls "$GENDIR"/*.h 2>/dev/null | wc -l)
[ "$C_COUNT" -gt 0 ] || die "no *.c in gen dir '$GENDIR'"
[ "$H_COUNT" -gt 0 ] || die "no *.h in gen dir '$GENDIR'"

DATE=$(date +%Y-%m-%d)
HEAD=$(git -C "$ROOT" rev-parse --short HEAD)
BIN_MD5=$(md5sum "$BIN" | cut -d' ' -f1)

STAGE=$(mktemp -d /tmp/zig1-seed-archive.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
SEED="$STAGE/zig1-seed"
mkdir -p "$SEED/gen" "$SEED/runtime" "$SEED/lib"

cp "$BIN" "$SEED/zig1"
chmod +x "$SEED/zig1"
cp "$GENDIR"/*.c "$GENDIR"/*.h "$SEED/gen/"
# The emitter now copies its runtime/platform support into DIR (emit_support):
# zig_runtime.c/zig_pal.c/c_exit.c + zig_compat.h/zig_runtime.h/net_prelude.h.
# Those already live in runtime/ (c_exit.c at top level); the three support .c
# MUST NOT be duplicated into gen/ or the archive C double-links against the
# runtime trio (Phase-1 reproduced: link rc=1 multiple definition of std_panic).
# Keep gen/ = the module emission only (net_prelude.h is deliberately not part
# of the seed — see SEED_README.txt).
for f in zig_runtime.c zig_pal.c c_exit.c zig_compat.h zig_runtime.h net_prelude.h; do
    rm -f "$SEED/gen/$f"
done
C_COUNT=$(ls "$SEED/gen"/*.c 2>/dev/null | wc -l)
H_COUNT=$(ls "$SEED/gen"/*.h 2>/dev/null | wc -l)
[ "$C_COUNT" -gt 0 ] || die "gen dir '$GENDIR' has no module *.c after support exclusion"
[ "$H_COUNT" -gt 0 ] || die "gen dir '$GENDIR' has no module *.h after support exclusion"
cp "$ROOT/sf/src/c_exit.c" "$SEED/c_exit.c"
for f in zig_compat.h zig_runtime.h zig_special_types.h zig_runtime.c zig_pal.c; do
    cp "$ROOT/sf/src/include/$f" "$SEED/runtime/"
done
for f in std.zig std_io.zig std_arena.zig std_net.zig std_str.zig std_mem.zig std_math.zig std_debug.zig; do
    cp "$ROOT/sf/src/$f" "$SEED/lib/"
done

GEN_BYTES=$(stat -c '%s' "$SEED"/gen/*.c "$SEED"/gen/*.h | awk '{s += $1} END {print s}')

# --- self-contained gcc-of-C rebuild of the assembled tree (fixed point) ---
mkdir -p "$STAGE/check"
cp "$SEED"/gen/*.c "$SEED"/gen/*.h "$STAGE/check/"
# gen/ holds the module emission only; stage the runtime support sources next to
# it and compile/link everything with one alphabetical *.o glob — the same
# object order build_from_seed.sh uses — so the recorded fixed point is the true
# self-emission fixed point (the support sources live in runtime/ + top level).
cp "$SEED"/runtime/zig_runtime.c "$SEED"/runtime/zig_pal.c "$SEED/c_exit.c" "$STAGE/check/"
( cd "$STAGE/check" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I "$SEED/runtime" -c *.c ) \
    || die "archive C gcc -c failed"
( cd "$STAGE/check" && gcc -m32 -O0 *.o -o "$STAGE/check/zig1_fromC" ) \
    || die "archive C gcc link failed"
FP_MD5=$(md5sum "$STAGE/check/zig1_fromC" | cut -d' ' -f1)
echo "[archive] gcc-only rebuild of archive C md5 (fixed point): $FP_MD5"

# --- SEED_README.txt ---
cat > "$SEED/SEED_README.txt" <<EOF
SEED - zig1 bootstrap seed (zig0-independent rebuild path)
==========================================================

Pinned HEAD: $HEAD
Capture date: $DATE
Spec: docs/superpowers/specs/2026-09-07-seed-bootstrap-migration-design.md

Purpose: rebuild zig1 with ONLY gcc, never zig0. zig0 stays in-tree and active;
this archive is the committed safety net, rotated once per completed plan.

Contents
--------
zig1-seed/zig1        seed binary (md5 $BIN_MD5)
zig1-seed/gen/        the seed's own self-emission C89 ($C_COUNT .c + $H_COUNT
                      .h incl. zig_special_types.h, emitted from sf/src/main.zig
                      at HEAD $HEAD; $GEN_BYTES bytes)
zig1-seed/c_exit.c    link source (sf/src/c_exit.c, top level per spec layout)
zig1-seed/runtime/    link/include sources needed to compile gen/:
                      zig_compat.h, zig_runtime.h, zig_special_types.h
                      (canonical 87-B copy), zig_runtime.c, zig_pal.c
zig1-seed/lib/        the 8 std .zig (std.zig, std_io.zig, std_arena.zig,
                      std_net.zig, std_str.zig, std_mem.zig, std_math.zig,
                      std_debug.zig)
zig1-seed/SEED_README.txt  this file

(net_prelude.h / net_runtime.h / net_runtime.c / optstar_repro.h are NOT
included: 0 references in any emitted gen/*.c|*.h for a linux -osl gcc-only
rebuild.) sf/src .zig sources are NOT duplicated in the archive - the pinned
HEAD sha in release/seed/CHANGELOG.md identifies the source; the source lives
in git.

Binary vs fixed point (provenance)
----------------------------------
The archived binary md5 $BIN_MD5 and the self-emission fixed point $FP_MD5
(gcc of the archive's gen/ C, verified at creation) represent the SAME compiler
state at HEAD $HEAD. A gcc-only rebuild of the archive's C must reproduce
$FP_MD5.

Rebuild recipe 1 (primary, forward path) - from the seed binary
----------------------------------------------------------------
From the repo root (current sf/src):

  timeout 120 ./zig1-seed/zig1 --dump-c89 --output-dir <fresh-dir> sf/src/main.zig

  (run from the repo root with the RELATIVE sf/src/main.zig path: module
  basename-hash tokens depend on the resolved source path; --output-dir must
  already exist. Exclude the .zig1_*.tmp spill scratch the dump writes into the
  output dir.)

  cd <fresh-dir>
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I <repo>/sf/src/include -c *.c
  gcc -m32 -O0 *.o <repo>/sf/src/include/zig_runtime.c \
      <repo>/sf/src/include/zig_pal.c <repo>/sf/src/c_exit.c -o zig1_next

Verify two-hop fixed-point closure: dump sf/src/main.zig with zig1_next into a
fresh dir, gcc the same way, link -> binary md5 must equal the fixed point
$FP_MD5. (scripts/seed/build_from_seed.sh automates this.)

Rebuild recipe 2 (fallback) - seed binary lost, rebuild from C only
-------------------------------------------------------------------
Self-contained; no repo include path, no zig0. Run from a scratch copy of the
unpacked archive (gcc -c writes *.o next to the sources):

  cd zig1-seed
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I zig1-seed/runtime -c zig1-seed/gen/*.c
  gcc -m32 -O0 *.o zig1-seed/runtime/zig_runtime.c zig1-seed/runtime/zig_pal.c \
      zig1-seed/c_exit.c -o zig1_fromC

Binary md5 must equal the fixed point $FP_MD5.

std install: the produced binary needs the std lib next to it (lib/ with the 8
std .zig) - copied from zig1-seed/lib/ or the binary's lib-dir.

CRITICAL FLAG SET RULE (operator amendment 2026-09-07)
------------------------------------------------------
Every gcc -c command MUST carry the FULL canonical flag set, INCLUDING -Wall:

  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I <inc> -c ...

The fixed point reproduces ONLY with -Wall present. Without -Wall the
deterministic result differs (cosmetic only: assembler local-label numbering,
.text instruction-identical), so the recorded fixed point is not reproduced.

Link rule: self-emission C89 links zig_runtime.c + zig_pal.c + c_exit.c.
zig_pal.c alone is insufficient (undefined std_panic + c_exit).

Archive inventory (sizes from sf/src at HEAD $HEAD):
  runtime/: zig_compat.h, zig_runtime.h, zig_special_types.h (canonical 87-B
  copy; during a from-gen rebuild the emitted gen/zig_special_types.h shadows
  it), zig_runtime.c, zig_pal.c. c_exit.c is at archive top level (separate
  from runtime/), per spec layout. Emitted gen set: $C_COUNT .c + $H_COUNT .h
  = $GEN_BYTES bytes.
EOF

rm -f "$OUTTGZ"
tar -czf "$OUTTGZ" -C "$STAGE" zig1-seed
ARCHIVE_MD5=$(md5sum "$OUTTGZ" | cut -d' ' -f1)
echo "[archive] wrote $OUTTGZ (archive md5 $ARCHIVE_MD5)"

# --- CHANGELOG entry (printed always; prepended with --update-changelog) ---
CHANGELOG="${SEED_CHANGELOG:-$ROOT/release/seed/CHANGELOG.md}"
NEXT=0
if [ -f "$CHANGELOG" ]; then
    CUR=$(grep -oE 'seed v[0-9]+' "$CHANGELOG" | grep -oE '[0-9]+' | sort -n | tail -1) || true
    if [ -n "$CUR" ]; then NEXT=$((CUR + 1)); fi
fi
ENTRY="$STAGE/changelog_entry.txt"
cat > "$ENTRY" <<EOF
## $DATE — seed v$NEXT (HEAD $HEAD)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
\`zig1-seed/\` with \`zig1\`, \`gen/\` ($C_COUNT \`.c\` + $H_COUNT \`.h\` incl.
emitted \`zig_special_types.h\`, $GEN_BYTES bytes), \`c_exit.c\` (top level),
\`runtime/\`, \`lib/\`, \`SEED_README.txt\`.

| field | value |
|---|---|
| date | $DATE |
| HEAD | \`$HEAD\` |
| seed binary md5 | \`$BIN_MD5\` |
| self-emission C | $C_COUNT \`.c\` + $H_COUNT \`.h\` ($GEN_BYTES bytes) |
| fixed point | \`$FP_MD5\` |
| archive md5 | \`$ARCHIVE_MD5\` |

Provenance note: the archived binary (md5 $BIN_MD5) was captured by
scripts/seed/archive_seed.sh at HEAD $HEAD; gcc of the archive's self-emission
C reproduces the self-emission fixed point \`$FP_MD5\` — both are the same
compiler state at HEAD $HEAD. Rebuild recipes + full canonical flag-set
requirement (\`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration\`; the fixed point reproduces ONLY with
\`-Wall\` present) are recorded in \`zig1-seed/SEED_README.txt\`.
EOF

echo "--- CHANGELOG entry ---"
cat "$ENTRY"

if [ "$UPDATE_CHANGELOG" = 1 ]; then
    [ -f "$CHANGELOG" ] || die "release/seed/CHANGELOG.md not found (refusing --update-changelog)"
    TMPC=$(mktemp)
    awk -v entry="$ENTRY" '
        NR == FNR { buf = buf $0 "\n"; next }
        /^## / && !done { printf "%s", buf; done = 1 }
        { print }
    ' "$ENTRY" "$CHANGELOG" > "$TMPC"
    mv "$TMPC" "$CHANGELOG"
    echo "[archive] prepended entry to $CHANGELOG"
fi
