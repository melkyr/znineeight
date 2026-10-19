#!/bin/sh
# get_flac_tools.sh -- reproducibly obtain a RUNNABLE flac(1) with NO root.
#
# Mirrors get_vorbis_tools.sh: uses a private, writable apt state/cache under
# $TMP, downloads the `flac` package (and its dependencies) with
# `apt-get --download-only --no-install-recommends`, and unpacks every .deb
# into an extraction prefix with `dpkg-deb -x`. The `Dir::State::status`
# redirect lets apt run as an unprivileged user without writing to /var/lib/dpkg.
#
# The M8 T2 fixture (sine_stereo_44100.flac) is GENERATED from the existing raw
# PCM golden with this binary; nothing here is linked into the Z98 example.
#
# stdout (parseable lines):
#   flac: <path>
#   LD_LIBRARY_PATH: <colon-separated dirs>   (required to run flac)
#   flac_version: <first line of `flac --version`>
#
# Exits non-zero if flac cannot be produced or run.
#
# Usage:  TMP=/tmp/flac sh get_flac_tools.sh
#         TMP=/tmp/flac SYS=/tmp/flac/sys sh get_flac_tools.sh   # stable prefix
#
# POSIX sh + coreutils/GNU find + dpkg-deb + apt-get (Debian bookworm).

set -eu

TMP="${TMP:-/tmp/flac}"
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

echo "== apt-get install --download-only flac ==" >&2
apt-get $AO install --download-only --no-install-recommends -y flac >&2

mkdir -p "$SYS"
for d in "$W"/cache/archives/*.deb; do
    [ -f "$d" ] || continue
    dpkg-deb -x "$d" "$SYS"
done

FLAC="$SYS/usr/bin/flac"
if [ ! -x "$FLAC" ]; then
    echo "get_flac_tools: not produced at $FLAC" >&2
    exit 1
fi

LD="$(find "$SYS" -name '*.so*' -printf '%h\n' 2>/dev/null | sort -u | tr '\n' ':')"
VER="$(env LD_LIBRARY_PATH="$LD" "$FLAC" --version 2>&1 | head -n1)"
case "$VER" in
    *flac*) ;;
    *)
        echo "get_flac_tools: flac did not run (got '$VER')" >&2
        exit 1
        ;;
esac

echo "flac: $FLAC"
echo "LD_LIBRARY_PATH: $LD"
echo "flac_version: $VER"
