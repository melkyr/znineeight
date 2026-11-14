#!/bin/sh
# get_aria2.sh -- reproducibly obtain a RUNNABLE aria2c with NO root.
#
# Uses a private, writable apt state/cache under $TMP, downloads aria2 + its
# dependencies with `apt-get --download-only --no-install-recommends`, and
# unpacks every .deb into an extraction prefix with `dpkg-deb -x`. The
# `Dir::State::status` redirect lets apt run as an unprivileged user without
# writing to /var/lib/dpkg.
#
# stdout (three parseable lines):
#   aria2c: <path>
#   LD_LIBRARY_PATH: <colon-separated dirs>
#   aria2_version: aria2 version <x.y.z>
#
# Exits non-zero if aria2c cannot be produced or run.
#
# Usage:  TMP=/tmp/aria2 sh get_aria2.sh
#         TMP=/tmp/aria2 SYS=/tmp/aria2/sys sh get_aria2.sh   # stable prefix
#
# POSIX sh + coreutils/GNU find + dpkg-deb + apt-get (DEBIAN bookworm).

set -eu

TMP="${TMP:-/tmp/aria2}"
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

echo "== apt-get install --download-only aria2 ==" >&2
apt-get $AO install --download-only --no-install-recommends -y aria2 >&2

mkdir -p "$SYS"
for d in "$W"/cache/archives/*.deb; do
    [ -f "$d" ] || continue
    dpkg-deb -x "$d" "$SYS"
done

ARIA="$SYS/usr/bin/aria2c"
if [ ! -x "$ARIA" ]; then
    echo "get_aria2: aria2c not produced at $ARIA" >&2
    exit 1
fi

LD="$(find "$SYS" -name '*.so*' -printf '%h\n' 2>/dev/null | sort -u | tr '\n' ':')"

VER="$(env LD_LIBRARY_PATH="$LD" "$ARIA" --version 2>/dev/null | head -n1)"
case "$VER" in
    aria2\ version\ *) ;;
    *)
        echo "get_aria2: aria2c did not run (got '$VER')" >&2
        exit 1
        ;;
esac

echo "aria2c: $ARIA"
echo "LD_LIBRARY_PATH: $LD"
echo "aria2_version: $VER"
