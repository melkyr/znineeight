#!/usr/bin/env python3
"""make_large_ogg.py — deterministic large valid single-stream OGG.

Builds a valid OGG Vorbis file of at least --size bytes from a committed
fixture (default testdata/sine_stereo_44100.ogg, a 2.0 s stream) without any
third-party OGG library.  The fixture's header pages are emitted once and its
audio pages are repeated as a block.  Every emitted page is rebuilt with:

  * a monotonic sequence number (0, 1, 2, ...),
  * the fixture's single logical-stream serial,
  * granule positions advanced by one fixture duration per audio block,
  * the EOS flag on the last page only, and
  * a recomputed OGG CRC-32 (poly 0x04c11db7, init/xorout 0, not reflected).

The audio block boundary is a packet boundary, so page continuation flags stay
valid when the block repeats.  Output is byte-for-byte deterministic (no
timestamps, no randomness).

Usage:
    python3 make_large_ogg.py [--size 64M] [--quiet] FIXTURE.ogg OUTPUT.ogg

--size accepts bytes or an integer with a K/M/G suffix (KiB/MiB/GiB).  The
resulting file is at least that many bytes (a whole audio block is repeated).
Statistics are printed as key=value lines unless --quiet is given.
"""

import argparse
import struct
import sys

OGG_CAPTURE = b"OggS"
CRC_POLY = 0x04C11DB7
NO_GRANULE = 0xFFFFFFFFFFFFFFFF
EOS = 0x04
BOS = 0x02
CONTINUED = 0x01


def make_crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            if r & 0x80000000:
                r = ((r << 1) ^ CRC_POLY) & 0xFFFFFFFF
            else:
                r = (r << 1) & 0xFFFFFFFF
        table.append(r)
    return table


CRC_TABLE = make_crc_table()


def ogg_crc(data):
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ CRC_TABLE[((crc >> 24) ^ b) & 0xFF]
    return crc


def fail(msg):
    sys.stderr.write("make_large_ogg: %s\n" % msg)
    raise SystemExit(1)


class Page(object):
    def __init__(self, raw, header_type, granule, serial, seq, segs, body):
        self.raw = raw
        self.header_type = header_type
        self.granule = granule
        self.serial = serial
        self.seq = seq
        self.segs = segs
        self.body = body


def parse_pages(data, check_crc, what):
    pages = []
    off = 0
    while off < len(data):
        if off + 27 > len(data):
            fail("%s: truncated page header at %d" % (what, off))
        if data[off:off + 4] != OGG_CAPTURE:
            fail("%s: bad capture pattern at %d" % (what, off))
        if data[off + 4] != 0:
            fail("%s: unsupported OGG version at %d" % (what, off))
        header_type = data[off + 5]
        granule = struct.unpack_from("<Q", data, off + 6)[0]
        serial, seq = struct.unpack_from("<II", data, off + 14)
        nseg = data[off + 26]
        if off + 27 + nseg > len(data):
            fail("%s: truncated segment table at %d" % (what, off))
        segs = list(data[off + 27:off + 27 + nseg])
        body_len = sum(segs)
        end = off + 27 + nseg + body_len
        if end > len(data):
            fail("%s: truncated page body at %d" % (what, off))
        raw = data[off:end]
        if check_crc:
            stored = struct.unpack_from("<I", raw, 22)[0]
            zeroed = bytearray(raw)
            zeroed[22:26] = b"\x00\x00\x00\x00"
            if ogg_crc(zeroed) != stored:
                fail("%s: bad CRC at page offset %d" % (what, off))
        body = raw[27 + nseg:]
        pages.append(Page(raw, header_type, granule, serial, seq, segs, body))
        off = end
    if off != len(data):
        fail("%s: trailing bytes after the last page" % what)
    return pages


def build_page(header_type, granule, serial, seq, segs, body):
    if len(segs) > 255:
        fail("page has more than 255 segments")
    if sum(segs) != len(body):
        fail("page segment table does not match body length")
    page = bytearray()
    page += OGG_CAPTURE
    page.append(0)
    page.append(header_type)
    page += struct.pack("<Q", granule)
    page += struct.pack("<I", serial)
    page += struct.pack("<I", seq)
    page += b"\x00\x00\x00\x00"
    page.append(len(segs))
    page += bytes(segs)
    page += body
    struct.pack_into("<I", page, 22, ogg_crc(page))
    return bytes(page)


def parse_size(text):
    s = text.strip().lower()
    suffixes = [
        ("kib", 1024), ("mib", 1024 * 1024), ("gib", 1024 * 1024 * 1024),
        ("kb", 1024), ("mb", 1024 * 1024), ("gb", 1024 * 1024 * 1024),
        ("k", 1024), ("m", 1024 * 1024), ("g", 1024 * 1024 * 1024),
    ]
    mult = 1
    for suffix, m in suffixes:
        if s.endswith(suffix):
            s = s[:-len(suffix)]
            mult = m
            break
    if not s.isdigit():
        fail("--size must be an integer with an optional K/M/G suffix")
    value = int(s) * mult
    if value <= 0:
        fail("--size must be positive")
    return value


def format_ms(ms):
    return "%d.%03d" % (ms // 1000, ms % 1000)


def main():
    ap = argparse.ArgumentParser(
        description="deterministically repeat a committed OGG fixture")
    ap.add_argument("fixture", help="source single-stream OGG fixture")
    ap.add_argument("output", help="destination OGG")
    ap.add_argument("--size", default="64M",
                    help="minimum output size (default 64M = 64 MiB)")
    ap.add_argument("--quiet", action="store_true",
                    help="do not print key=value statistics")
    args = ap.parse_args()

    target = parse_size(args.size)
    try:
        with open(args.fixture, "rb") as f:
            source = f.read()
    except OSError as e:
        fail("cannot read fixture: %s" % e)

    pages = parse_pages(source, True, args.fixture)
    if not pages:
        fail("fixture has no pages")

    serial = pages[0].serial
    for i, p in enumerate(pages):
        if p.serial != serial:
            fail("fixture is multiplexed/chained (serial changes at page %d)" % i)
    if pages[0].header_type & BOS == 0:
        fail("fixture first page is not a BOS page")

    # Walk packet endings to find the first page that contains only audio.
    packet_count = 0
    packet_bytes = bytearray()
    first_packets = []
    third_end_page = -1
    third_end_seg = -1
    for pi, p in enumerate(pages):
        # Walk with an explicit body cursor to record packet boundaries.
        cur = 0
        for si, lace in enumerate(p.segs):
            if packet_count < 3:
                packet_bytes += p.body[cur:cur + lace]
            cur += lace
            if lace < 255:
                if packet_count < 3:
                    first_packets.append(bytes(packet_bytes))
                    packet_bytes = bytearray()
                packet_count += 1
                if packet_count == 3:
                    third_end_page = pi
                    third_end_seg = si

    if packet_count < 3:
        fail("fixture has fewer than three Vorbis header packets")
    if not first_packets[0].startswith(b"\x01vorbis"):
        fail("fixture first packet is not a Vorbis identification header")
    if not first_packets[1].startswith(b"\x03vorbis"):
        fail("fixture second packet is not a Vorbis comment header")
    if not first_packets[2].startswith(b"\x05vorbis"):
        fail("fixture third packet is not a Vorbis setup header")
    if third_end_page < 0 or third_end_seg < 0:
        fail("cannot locate the end of the Vorbis setup header")

    last_page_seg = len(pages[third_end_page].segs) - 1
    if third_end_seg != last_page_seg:
        fail("fixture audio shares page %d with the setup header; "
             "page-level repetition is unsafe" % third_end_page)
    audio_start = third_end_page + 1
    if audio_start >= len(pages):
        fail("fixture has no audio pages")

    audio_pages = pages[audio_start:]
    if audio_pages[0].header_type & CONTINUED:
        fail("fixture first audio page begins with a continued packet")
    for i, p in enumerate(audio_pages):
        if p.header_type & BOS:
            fail("fixture audio page %d carries a BOS flag" % i)

    # The fixture must end on a packet boundary and its audio granules must be
    # monotonic, so a repeated block starts and ends cleanly.
    open_len = 0
    last_granule = 0
    for i, p in enumerate(audio_pages):
        for lace in p.segs:
            open_len += lace
            if lace < 255:
                open_len = 0
        if p.granule != NO_GRANULE:
            if p.granule < last_granule:
                fail("fixture audio granules are not monotonic")
            last_granule = p.granule
    if open_len != 0:
        fail("fixture ends with an unterminated packet")

    block_samples = last_granule
    if block_samples == 0:
        fail("fixture has no audio granule to advance")
    if len(audio_pages) == 0:
        fail("fixture has no audio pages")

    header_pages = pages[:audio_start]
    header_bytes = sum(len(p.raw) for p in header_pages)
    block_bytes = sum(len(p.raw) for p in audio_pages)
    if block_bytes == 0:
        fail("fixture audio block is empty")
    repeats = (target - header_bytes + block_bytes - 1) // block_bytes
    if repeats < 1:
        repeats = 1

    rate = struct.unpack_from("<I", first_packets[0], 12)[0]
    channels = first_packets[0][11]
    if rate == 0:
        fail("fixture identification header has sample rate 0")

    out = bytearray()
    seq = 0
    for p in header_pages:
        if p.header_type & EOS:
            fail("fixture header page carries EOS")
        out += build_page(p.header_type, p.granule, serial, seq, p.segs, p.body)
        seq += 1
    last_audio_page = len(audio_pages) - 1
    for k in range(repeats):
        offset = k * block_samples
        for j, p in enumerate(audio_pages):
            header_type = p.header_type & ~EOS
            if k == repeats - 1 and j == last_audio_page:
                header_type |= EOS
            granule = p.granule
            if granule != NO_GRANULE:
                granule += offset
                if granule > NO_GRANULE - 1:
                    fail("granule position overflow")
            out += build_page(header_type, granule, serial, seq, p.segs, p.body)
            seq += 1

    if len(out) < target:
        fail("internal error: generated %d bytes, wanted at least %d" %
             (len(out), target))

    # Re-parse the emitted stream: this catches a bad CRC, sequence, EOS or
    # granule without trusting the in-memory construction.
    check = parse_pages(out, True, "generated output")
    if len(check) != len(header_pages) + repeats * len(audio_pages):
        fail("generated page count mismatch")
    for i, p in enumerate(check):
        if p.serial != serial:
            fail("generated page %d changed serial" % i)
        if p.seq != i:
            fail("generated page %d has sequence %d" % (i, p.seq))
        has_eos = (p.header_type & EOS) != 0
        if i == len(check) - 1:
            if not has_eos:
                fail("generated last page is missing EOS")
        elif has_eos:
            fail("generated page %d carries an early EOS" % i)
    final = check[-1].granule
    if final != block_samples * repeats:
        fail("generated final granule %d != %d" %
             (final, block_samples * repeats))

    try:
        with open(args.output, "wb") as f:
            f.write(out)
    except OSError as e:
        fail("cannot write output: %s" % e)

    dur_ms = final * 1000 // rate
    if not args.quiet:
        print("size=%d" % len(out))
        print("pages=%d" % len(check))
        print("blocks=%d" % repeats)
        print("channels=%d" % channels)
        print("sample_rate=%d" % rate)
        print("duration_s=%s" % format_ms(dur_ms))


if __name__ == "__main__":
    main()
