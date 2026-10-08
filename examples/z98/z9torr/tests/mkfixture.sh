#!/bin/sh
# mkfixture.sh -- generate the z9torr testdata fixtures deterministically.
#
# POSIX sh + awk only (no Python). Produces, under ../testdata/:
#   t1_single_1m.torrent      1 MiB payload, 4 pieces @ 256 KiB
#   t2_single_25m.torrent     25 MiB payload, 100 pieces @ 256 KiB
#   t5_unicode_name.torrent   small payload, UTF-8 info.name
# and the expected hashes under ../testdata/expected/:
#   <name>.sha1       SHA-1 of the full (unencoded) payload, 40 hex
#   <name>.infohash   SHA-1 of the exact `info` dict bytes, 40 hex
#
# The suite does NOT run this script: the fixtures are generated ONCE and
# committed. Regenerating is a deliberate, manual act (a corrupted fixture
# must be caught, not silently recreated).
#
# The payload is a deterministic awk `srand(seed)` byte sequence. The awk
# implementation is part of the generation contract (mawk here); the committed
# bytes -- not the script -- are the source of truth.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TDIR="$Z9DIR/testdata"
EDIR="$TDIR/expected"
WORK="${WORK:-/tmp/z9torr_fixture_work}"
REF="$WORK/ref_check"
CC="${CC:-gcc}"

export LC_ALL=C

rm -rf "$WORK"
mkdir -p "$WORK" "$EDIR"

echo "== building ref_check =="
"$CC" -std=c89 -O0 -Wall -o "$REF" "$Z9DIR/tools/ref_check.c"

# byte length of a string
str_len() {
    printf '%s' "$1" | wc -c | tr -d ' '
}

# hex digits on stdin -> raw bytes on stdout
hex2bin() {
    awk '{
        s = $0
        for (i = 1; i <= length(s); i += 2) {
            hi = index("0123456789abcdef", substr(s, i, 1)) - 1
            lo = index("0123456789abcdef", substr(s, i + 1, 1)) - 1
            printf "%c", hi * 16 + lo
        }
    }'
}

# gen_payload <seed> <size> <out>
gen_payload() {
    awk -v seed="$1" -v size="$2" 'BEGIN {
        srand(seed);
        for (i = 0; i < size; i++) {
            printf "%c", int(rand() * 256);
        }
    }' > "$3"
}

# build_fixture <name> <seed> <size> <piece_length> <display_name>
build_fixture() {
    name="$1"
    seed="$2"
    size="$3"
    plen="$4"
    dname="$5"

    echo "== $name: size=$size piece_length=$plen =="

    payload="$WORK/$name.payload"
    gen_payload "$seed" "$size" "$payload"
    got="$(wc -c < "$payload" | tr -d ' ')"
    if [ "$got" != "$size" ]; then
        echo "FATAL: payload size $got != $size" >&2
        exit 1
    fi

    full_sha="$(sha1sum "$payload" | awk '{print $1}')"

    npieces=$(( (size + plen - 1) / plen ))
    pieces_hex="$WORK/$name.pieces.hex"
    : > "$pieces_hex"
    i=0
    while [ "$i" -lt "$npieces" ]; do
        piece="$WORK/$name.piece"
        dd if="$payload" of="$piece" bs="$plen" skip="$i" count=1 2>/dev/null
        ph="$(sha1sum "$piece" | awk '{print $1}')"
        printf '%s' "$ph" >> "$pieces_hex"
        i=$(( i + 1 ))
    done

    pieces_bin="$WORK/$name.pieces.bin"
    hex2bin < "$pieces_hex" > "$pieces_bin"
    pieces_len="$(wc -c < "$pieces_bin" | tr -d ' ')"
    want_len=$(( npieces * 20 ))
    if [ "$pieces_len" != "$want_len" ]; then
        echo "FATAL: pieces length $pieces_len != $want_len" >&2
        exit 1
    fi

    nlen="$(str_len "$dname")"

    # info dict: keys in canonical (byte-sorted) order.
    info="$WORK/$name.info"
    {
        printf 'd'
        printf '6:lengthi%se' "$size"
        printf '4:name%s:' "$nlen"
        printf '%s' "$dname"
        printf '12:piece lengthi%se' "$plen"
        printf '6:pieces%s:' "$pieces_len"
        cat "$pieces_bin"
        printf 'e'
    } > "$info"

    # tier2/tier4 reach the local mock_tracker (default port 6969; see
    # testdata/ports.txt). `announce` is OUTSIDE the `info` dict, so this does
    # not affect the info_hash or payload SHA-1 goldens.
    announce='http://127.0.0.1:6969/announce'
    alen="$(str_len "$announce")"

    torrent="$TDIR/$name.torrent"
    {
        printf 'd'
        printf '8:announce%s:' "$alen"
        printf '%s' "$announce"
        printf '4:info'
        cat "$info"
        printf 'e'
    } > "$torrent"

    infohash="$("$REF" --infohash "$torrent" | awk '{print $2}')"
    if [ "$(str_len "$infohash")" != 40 ]; then
        echo "FATAL: bad infohash for $name: $infohash" >&2
        exit 1
    fi

    printf '%s\n' "$full_sha" > "$EDIR/$name.sha1"
    printf '%s\n' "$infohash" > "$EDIR/$name.infohash"

    echo "   payload sha1: $full_sha"
    echo "   info_hash:    $infohash"
}

# t1: 1 MiB, 4 x 256 KiB
build_fixture t1_single_1m 1 1048576 262144 "t1.bin"

# t2: 25 MiB, 100 x 256 KiB
build_fixture t2_single_25m 2 26214400 262144 "t2.bin"

# t5: small, UTF-8 info.name (naïve_日本.txt built from octal escapes)
UNI_NAME="$(printf 'na\303\257ve_\346\227\245\346\234\254.txt')"
build_fixture t5_unicode_name 5 30000 16384 "$UNI_NAME"

echo "== done: fixtures in $TDIR =="
