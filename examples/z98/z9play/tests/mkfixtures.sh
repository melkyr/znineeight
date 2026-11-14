#!/bin/sh
# mkfixtures.sh -- generate the z9play OGG testdata fixtures + goldens
# DETERMINISTICALLY.
#
# POSIX sh + python3 (PCM generation) + oggenc/ogginfo/oggdec (vorbis-tools).
# oggenc/ogginfo/oggdec are acquired without root by tests/get_vorbis_tools.sh
# (run automatically if not already present).
#
# Produces, under ../testdata/:
#   sine_mono_44100.ogg       1 ch, 44100 Hz, 1.0 s, 440 Hz
#   sine_stereo_44100.ogg     2 ch, 44100 Hz, 2.0 s, 440/660 Hz
#   sine_stereo_48000.ogg     2 ch, 48000 Hz, 1.0 s, 440/660 Hz
#   tagged_unicode.ogg        2 ch, 44100 Hz, 1.0 s, TITLE/ARTIST/ALBUM (UTF-8)
#   short.ogg                 1 ch, 44100 Hz, 0.3 s, 440 Hz
# and the goldens under ../testdata/expected/:
#   <name>.meta               FIXED line format (key=value, one per line, LF):
#       channels=<decimal>            (from `ogginfo`)
#       sample_rate=<decimal>         (from `ogginfo`)
#       duration_s=<seconds, 3 d.p.>  (from `ogginfo` "Playback length")
#       TITLE=<raw UTF-8 value>       (only when the fixture has the tag)
#       ARTIST=<raw UTF-8 value>      (only when the fixture has the tag)
#       ALBUM=<raw UTF-8 value>       (only when the fixture has the tag)
#     `channels`/`sample_rate`/`duration_s` come from ogginfo; tag lines are
#     parsed from the ACTUAL comment packet stored in the .ogg (uppercase keys,
#     raw bytes, fixed TITLE/ARTIST/ALBUM order, present only when set).
#   <name>.pcm                golden raw PCM (the M3 decode reference):
#     signed 16-bit little-endian interleaved, HEADERLESS (no WAV header).
#     Produced by oggdec (vorbis-tools), invoked EXACTLY as:
#       oggdec -Q -R -b 16 -e 0 -s 1 -o <name>.pcm <name>.ogg
#     i.e. --quiet --raw --bits 16 --endianness 0 (little) --sign 1 (signed);
#     `--raw` suppresses oggdec's default WAV header. Frame count =
#     filesize / (channels * 2); rate/channels/duration live in <name>.meta.
#
# DETERMINISM. Three sources of run-to-run variability are removed:
#   1. samples are computed in Python (no random); the committed `.ogg` bytes,
#      not this script, are the source of truth;
#   2. oggenc's per-run random Ogg bitstream serial is pinned with `-s <serial>`
#      (a fixed serial per fixture), so re-running yields byte-identical .ogg;
#   3. oggdec/libvorbis is deterministic for a fixed input; write_pcm decodes
#      each fixture twice and asserts byte-identical output before committing.
#
# LOCALE. oggenc converts non-ASCII tag arguments using the locale; under a
# non-UTF-8 locale (e.g. C) it substitutes each non-ASCII byte with '#' at
# ENCODE time (corrupting the fixture). The encoder therefore runs under a UTF-8
# locale (auto-detected, "$UTF8_LC"), and the golden tag VALUES are read back
# from the stored comment bytes (not from shell literals, and not from ogginfo,
# which also sanitizes). A self-check asserts the stored bytes round-trip.
#
# The suite does NOT run this script: the fixtures are generated ONCE and
# committed. Regenerating is a deliberate, manual act (a corrupted fixture must
# be caught, not silently recreated). Mirrors z9torr/tests/mkfixture.sh.
#
# Usage:  sh mkfixtures.sh
# Env:    VORBIS_TMP (default /tmp/vorbis)  where get_vorbis_tools.sh extracts
#         OGGENC/OGGINFO/OGGDEC/LD_LIBRARY_PATH   override the acquired binaries
#         UTF8_LC                          force the oggenc locale (optional)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TDIR="$Z9DIR/testdata"
EDIR="$TDIR/expected"
VORBIS_TMP="${VORBIS_TMP:-/tmp/vorbis}"
WORK="${WORK:-/tmp/z9play_fixture_work}"

# oggenc converts non-ASCII tag arguments using the locale: under C/ASCII it
# substitutes each non-ASCII byte with '#'. Run the encoder under a UTF-8
# locale (first available); STOP rather than silently write lossy tags.
UTF8_LC="${UTF8_LC:-}"
if [ -z "$UTF8_LC" ]; then
    for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
        if locale -a 2>/dev/null | LC_ALL=C grep -qx "$_loc"; then UTF8_LC="$_loc"; break; fi
    done
fi
[ -n "$UTF8_LC" ] || {
    echo "mkfixtures: no UTF-8 locale available (tried C.UTF-8/C.utf8/en_US.UTF-8/en_US.utf8)" >&2
    exit 1; }


# --- locate (or acquire) oggenc/ogginfo/oggdec ------------------------------
if [ -z "${OGGENC:-}" ] || [ ! -x "${OGGENC:-}" ] || \
   [ -z "${OGGINFO:-}" ] || [ ! -x "${OGGINFO:-}" ] || \
   [ -z "${OGGDEC:-}" ] || [ ! -x "${OGGDEC:-}" ]; then
    echo "== acquiring vorbis-tools (no root) ==" >&2
    _out="$(TMP="$VORBIS_TMP" sh "$SCRIPT_DIR/get_vorbis_tools.sh")"
    OGGENC="$(printf '%s\n' "$_out" | LC_ALL=C awk -F': ' '/^oggenc: /{print $2; exit}')"
    OGGINFO="$(printf '%s\n' "$_out" | LC_ALL=C awk -F': ' '/^ogginfo: /{print $2; exit}')"
    OGGDEC="$(printf '%s\n' "$_out" | LC_ALL=C awk -F': ' '/^oggdec: /{print $2; exit}')"
    LD_LIBRARY_PATH="$(printf '%s\n' "$_out" | LC_ALL=C awk -F': ' '/^LD_LIBRARY_PATH: /{print $2; exit}')"
fi
# Safe under `set -u` when the caller overrides OGGENC/OGGINFO/OGGDEC without a lib path.
LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH
[ -x "${OGGENC:-}" ] || { echo "mkfixtures: oggenc not runnable: ${OGGENC:-unset}" >&2; exit 1; }
[ -x "${OGGINFO:-}" ] || { echo "mkfixtures: ogginfo not runnable: ${OGGINFO:-unset}" >&2; exit 1; }
[ -x "${OGGDEC:-}" ] || { echo "mkfixtures: oggdec not runnable: ${OGGDEC:-unset}" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mkfixtures: python3 required" >&2; exit 1; }
echo "== locale for oggenc: $UTF8_LC ==" >&2


rm -rf "$WORK"
mkdir -p "$WORK" "$TDIR" "$EDIR"

# --- deterministic PCM -> WAV -----------------------------------------------
# gen_wav <out> <rate> <channels> <seconds> <freq_l> <freq_r>
gen_wav() {
    python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys, struct, math
out = sys.argv[1]
rate = int(sys.argv[2]); ch = int(sys.argv[3])
dur = float(sys.argv[4]); fl = float(sys.argv[5]); fr = float(sys.argv[6])
n = int(round(rate * dur))
buf = bytearray()
for i in range(n):
    a = math.sin(2.0 * math.pi * fl * i / rate)
    if ch == 1:
        buf += struct.pack('<h', int(round(32767 * 0.5 * a)))
    else:
        b = math.sin(2.0 * math.pi * fr * i / rate)
        buf += struct.pack('<hh', int(round(32767 * 0.5 * a)), int(round(32767 * 0.5 * b)))
hdr = b'RIFF' + struct.pack('<I', 36 + len(buf)) + b'WAVE'
hdr += b'fmt ' + struct.pack('<IHHIIHH', 16, 1, ch, rate, rate * ch * 2, ch * 2, 16)
hdr += b'data' + struct.pack('<I', len(buf))
open(out, 'wb').write(hdr + buf)
PY
}

# --- golden .meta: numerics from ogginfo (LC_ALL=C), tags from stored bytes --
# extract_tags <ogg> -- reassemble the Vorbis comment packet straight from the
# OGG bytes and print TITLE/ARTIST/ALBUM as `KEY=value` (uppercase keys, raw
# stored bytes) in fixed order, one per line. This reads the ACTUAL bytes: it is
# independent of locale and of ogginfo/vorbiscomment's tag sanitization.
extract_tags() {
    python3 - "$1" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
acc = {}
packets = []
i = 0
n = len(data)
while i + 27 <= n and data[i:i+4] == b'OggS':
    nseg = data[i + 26]
    segs = data[i + 27:i + 27 + nseg]
    body = i + 27 + nseg
    serial = int.from_bytes(data[i + 14:i + 18], 'little')
    off = body
    acc.setdefault(serial, bytearray())
    for s in segs:
        acc[serial] += data[off:off + s]
        off += s
        if s < 255:
            packets.append((serial, bytes(acc[serial])))
            acc[serial] = bytearray()
    i = body + sum(segs)
want = (b'TITLE', b'ARTIST', b'ALBUM')
found = {}
for _serial, p in packets:
    if p[:7] != b'\x03vorbis':
        continue
    off = 7
    vlen = int.from_bytes(p[off:off + 4], 'little'); off += 4 + vlen
    cnt = int.from_bytes(p[off:off + 4], 'little'); off += 4
    for _ in range(cnt):
        l = int.from_bytes(p[off:off + 4], 'little'); off += 4
        item = p[off:off + l]; off += l
        k, sep, v = item.partition(b'=')
        if sep and k.upper() in want:
            found.setdefault(k.upper(), v)
    break
out = sys.stdout.buffer
for k in want:
    if k in found:
        out.write(k + b'=' + found[k] + b'\n')
PY
}

# write_meta <name> <ogg>
write_meta() {
    _name="$1"; _ogg="$2"
    _info="$(env LC_ALL=C LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$OGGINFO" "$_ogg" 2>/dev/null)"
    _ch="$(printf '%s\n' "$_info" | LC_ALL=C awk -F': ' '/^Channels: /{print $2; exit}')"
    _rate="$(printf '%s\n' "$_info" | LC_ALL=C awk -F': ' '/^Rate: /{print $2; exit}')"
    _dur="$(printf '%s\n' "$_info" | LC_ALL=C sed -n 's/.*Playback length: \([0-9][0-9]*\)m:\([0-9][0-9]*\.[0-9][0-9]*\)s.*/\1 \2/p' | LC_ALL=C awk '{printf "%.3f", $1 * 60 + $2}')"
    [ -n "$_ch" ] && [ -n "$_rate" ] && [ -n "$_dur" ] || {
        echo "mkfixtures: ogginfo gave no channels/rate/duration for $_name" >&2; exit 1; }
    {
        printf 'channels=%s\n' "$_ch"
        printf 'sample_rate=%s\n' "$_rate"
        printf 'duration_s=%s\n' "$_dur"
        extract_tags "$_ogg"
    } > "$EDIR/$_name.meta"
}

# --- golden .pcm: oggdec -> raw s16 LE interleaved, headerless ----------------
# write_pcm <name> <ogg> -- decode the fixture with oggdec to $EDIR/<name>.pcm.
# The flags are pinned so the layout is EXACTLY the documented golden:
#   -Q  --quiet          no console output
#   -R  --raw            headerless output (oggdec writes a WAV header otherwise)
#   -b  --bits 16        signed 16-bit samples
#   -e  --endianness 0   little-endian
#   -s  --sign 1         signed (not unsigned)
# The file is therefore raw signed-16 LE interleaved PCM; its frame count is
# filesize / (channels * 2) and rate/channels/duration live in <name>.meta.
# oggdec/libvorbis is deterministic for a fixed input; a run-twice self-check
# asserts byte-identical output so the committed goldens are reproducible.
write_pcm() {
    _name="$1"; _ogg="$2"
    _pcm="$EDIR/$_name.pcm"
    env LC_ALL=C LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$OGGDEC" \
        -Q -R -b 16 -e 0 -s 1 -o "$_pcm" "$_ogg"
    [ -s "$_pcm" ] || { echo "mkfixtures: $_pcm not produced" >&2; exit 1; }

    _pcm2="$WORK/$_name.pcm.2"
    env LC_ALL=C LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$OGGDEC" \
        -Q -R -b 16 -e 0 -s 1 -o "$_pcm2" "$_ogg"
    cmp -s "$_pcm" "$_pcm2" || {
        echo "mkfixtures: oggdec non-deterministic for $_name" >&2; exit 1; }
    rm -f "$_pcm2"
}

# --- emit: WAV -> oggenc (fixed serial, UTF-8 locale) + golden + self-check --
# emit <name> <serial> <rate> <ch> <seconds> <freq_l> <freq_r> [title artist album]
# Title/artist/album are passed as separate positional args (not KEY=value) so
# quoting is exact; all three are required together (only tagged_unicode here).
# oggenc runs under "$UTF8_LC" so non-ASCII tag bytes are stored verbatim.
emit() {
    _name="$1"; _serial="$2"; _rate="$3"; _ch="$4"; _dur="$5"; _fl="$6"; _fr="$7"
    _title="${8:-}"; _artist="${9:-}"; _album="${10:-}"
    _wav="$WORK/$_name.wav"
    gen_wav "$_wav" "$_rate" "$_ch" "$_dur" "$_fl" "$_fr"

    _ogg="$TDIR/$_name.ogg"
    if [ -n "$_title" ]; then
        env LC_ALL="$UTF8_LC" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$OGGENC" \
            -Q -s "$_serial" -t "$_title" -a "$_artist" -c "ALBUM=$_album" \
            -o "$_ogg" "$_wav"
    else
        env LC_ALL="$UTF8_LC" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$OGGENC" \
            -Q -s "$_serial" -o "$_ogg" "$_wav"
    fi
    [ -s "$_ogg" ] || { echo "mkfixtures: $_ogg not produced" >&2; exit 1; }

    # Golden tags are read back from the ACTUAL stored comment packet.
    write_meta "$_name" "$_ogg"

    # Golden raw PCM (M3 decode reference) + its run-twice determinism check.
    write_pcm "$_name" "$_ogg"

    # Self-check: the stored bytes must round-trip to the requested values, and
    # the non-ASCII TITLE must appear verbatim in the file (guards the
    # encode-time "#" substitution regression).
    if [ -n "$_title" ]; then
        _want="$(printf 'TITLE=%s\nARTIST=%s\nALBUM=%s\n' "$_title" "$_artist" "$_album")"
        _got="$(extract_tags "$_ogg")"
        if [ "$_got" != "$_want" ]; then
            echo "mkfixtures: tag round-trip FAILED for $_name" >&2
            printf '  want: %s\n  got:  %s\n' "$_want" "$_got" >&2
            exit 1
        fi
        if ! LC_ALL=C grep -aqF "$_title" "$_ogg"; then
            echo "mkfixtures: $_name missing verbatim TITLE bytes" >&2; exit 1
        fi
    fi
    echo "== $_name: $(LC_ALL=C wc -c < "$_ogg" | tr -d ' ') ogg bytes, $(LC_ALL=C wc -c < "$EDIR/$_name.pcm" | tr -d ' ') pcm bytes, $(cat "$EDIR/$_name.meta" | tr '\n' ' ')" >&2
}

# UTF-8 tag values as explicit octal escapes (locale-independent).
UNI_TITLE="$(printf 'Caf\303\251 d\303\251j\303\240 vu')"      # "Cafe<accent> deja<accent> vu"
UNI_ARTIST="$(printf 'Na\303\257ve \346\227\245\346\234\254')"  # "Naive<diaeresis> <CJK>"
UNI_ALBUM="$(printf '\303\234n\303\257cod\303\251')"            # "U<diaeresis>nicode<acute>"

echo "== generating z9play fixtures ==" >&2
emit sine_mono_44100   1001 44100 1 1.0 440 440
emit sine_stereo_44100 1002 44100 2 2.0 440 660
emit sine_stereo_48000 1003 48000 2 1.0 440 660
emit tagged_unicode    1004 44100 2 1.0 440 660 "$UNI_TITLE" "$UNI_ARTIST" "$UNI_ALBUM"
emit short             1005 44100 1 0.3 440 440

echo "== done: fixtures in $TDIR, goldens in $EDIR ==" >&2
