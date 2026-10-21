#!/bin/sh
# get_zstd_tools.sh -- reproducibly obtain a RUNNABLE zstd(1) with NO root.
#
# Mirrors examples/z98/z9play/tests/get_flac_tools.sh: uses a private,
# writable apt state/cache under $TMP, downloads the `zstd` package (and its
# dependencies) with `apt-get --download-only --no-install-recommends`, and
# unpacks every .deb into an extraction prefix with `dpkg-deb -x`. The
# Dir::State::status redirect lets apt run as an unprivileged user without
# writing to /var/lib/dpkg.
#
# The committed scripts/stdlib/vectors/std_zstd/*.in/.expected pairs are
# GENERATED once by this binary and frozen; nothing here is linked into Z98.
#
# stdout (parseable lines):
#   zstd: <path>
#   LD_LIBRARY_PATH: <colon-separated dirs>   (required to run zstd)
#   zstd_version: <first line of `zstd --version`>
#
# Exits non-zero if zstd cannot be produced or run.
#
# Usage:  TMP=/tmp/zstd sh get_zstd_tools.sh
#         TMP=/tmp/zstd SYS=/tmp/zstd/sys sh get_zstd_tools.sh   # stable prefix
#
# POSIX sh + coreutils/GNU find + dpkg-deb + apt-get (Debian bookworm).

set -eu

TMP="${TMP:-/tmp/zstd}"
W="${W:-$TMP/work}"
SYS="${SYS:-$TMP/sys}"
ARCH="${ARCH:-amd64}"
DIST="${DIST:-bookworm}"

rm -rf "$W" "$SYS"
mkdir -p "$W/state/lists/partial" "$W/cache/archives/partial" "$W/etc/apt"
touch "$W/state/status"
printf 'deb [arch=%s] http://deb.debian.org/debian %s main\n' "$ARCH" "$DIST" \
    > "$W/etc/apt/sources.list"

AO="-o Dir::State=$W/state -o Dir::State::lists=$W/state/lists -o Dir::State::status=$W/state/status -o Dir::Cache=$W/cache -o Dir::Cache::archives=$W/cache/archives -o Dir::Etc::sourcelist=$W/etc/apt/sources.list -o Dir::Etc::sourceparts=/dev/null -o APT::Get::List-Cleanup=0 -o Acquire::Languages=none"

echo "== apt-get update (private state under $W) ==" >&2
apt-get $AO update >&2

echo "== apt-get install --download-only zstd ==" >&2
apt-get $AO install --download-only --no-install-recommends -y zstd >&2

mkdir -p "$SYS"
for d in "$W"/cache/archives/*.deb; do
    [ -f "$d" ] || continue
    dpkg-deb -x "$d" "$SYS"
done

ZSTD="$SYS/usr/bin/zstd"
if [ ! -x "$ZSTD" ]; then
    echo "get_zstd_tools: not produced at $ZSTD" >&2
    exit 1
fi

LD="$(find "$SYS" -name '*.so*' -printf '%h\n' 2>/dev/null | sort -u | tr '\n' ':')"
VER="$(env LD_LIBRARY_PATH="$LD" "$ZSTD" --version 2>&1 | head -n1)"
case "$VER" in
    *zstd*|*Zstandard*) ;;
    *)
        echo "get_zstd_tools: zstd did not run (got '$VER')" >&2
        exit 1
        ;;
esac

echo "zstd: $ZSTD"
echo "LD_LIBRARY_PATH: $LD"
echo "zstd_version: $VER"
