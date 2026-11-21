#!/usr/bin/env python3
"""make_large_ogg.py — deterministic large valid single-stream OGG.

Builds a valid OGG Vorbis file of at least --size bytes from a committed
fixture (default testdata/sine_stereo_44100.ogg, a 2.0 s stream) without any
third-party OGG library.  The fixture's header pages are emitted once and its
audio pages are repeated as a block.  Every emitted page is rebuilt with:

  * a monotonic sequence number (0, 1, 2, ...),
  * the fixture's single logical-stream serial,
  * sample-accurate granule positions derived from each audio packet's Vorbis
    block size (the previous/current overlap contribution, plus the trimmed
    fixture tail and the block-boundary overlap),
  * the EOS flag on the last page only, and
  * a recomputed OGG CRC-32 (poly 0x04c11db7, init/xorout 0, not reflected).

The audio block boundary is a packet boundary, so page continuation flags stay
valid when the block repeats.  The setup header is walked only to recover each
mode's block flag; no third-party OGG/Vorbis library is used.  As an
independent oracle, the computed running sample totals must reproduce the
committed fixture's non-final page granules (written by libvorbis/oggenc).
Output is byte-for-byte deterministic (no timestamps, no randomness).

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


# --- minimal Vorbis setup/mode accounting (no third-party OGG library) -----
#
# Sample-accurate granules need each audio packet's block size.  The packet's
# first bit is 0 (audio), followed by the mode number in ilog(mode_count-1)
# LSB-first bits; the mode's blockflag selects blocksize_0 or blocksize_1 from
# the identification header.  Reaching the modes requires walking the setup
# header's codebooks, floors, residues and mappings, which is what this small
# reader does.  It only consumes fields; it does not allocate tables.

class BitReader(object):
    def __init__(self, data):
        self.data = data
        self.nbits = len(data) * 8
        self.pos = 0

    def read(self, n):
        if self.pos + n > self.nbits:
            fail("Vorbis setup/audio packet is truncated")
        v = 0
        for i in range(n):
            b = (self.data[self.pos >> 3] >> (self.pos & 7)) & 1
            v |= b << i
            self.pos += 1
        return v

    def skip(self, n):
        if self.pos + n > self.nbits:
            fail("Vorbis setup/audio packet is truncated")
        self.pos += n


def ilog(x):
    n = 0
    while x > 0:
        n += 1
        x >>= 1
    return n


def lookup1_values(entries, dims):
    r = 0
    while r < entries:
        prod = 1
        for _ in range(dims):
            prod *= r + 1
            if prod > entries:
                break
        if prod > entries:
            break
        r += 1
    return r


def parse_setup_modes(packet, channels):
    if not packet.startswith(b"\x05vorbis"):
        fail("setup packet signature is not \\x05vorbis")
    br = BitReader(packet)
    br.skip(7 * 8)

    codebooks = br.read(8) + 1
    for _ in range(codebooks):
        if br.read(24) != 0x564342:
            fail("bad Vorbis codebook sync")
        dims = br.read(16)
        entries = br.read(24)
        ordered = br.read(1)
        if ordered:
            br.read(5)
            ce = 0
            while ce < entries:
                ce += br.read(ilog(entries - ce))
        else:
            sparse = br.read(1)
            for _e in range(entries):
                if sparse:
                    if br.read(1):
                        br.read(5)
                else:
                    br.read(5)
        lookup = br.read(4)
        if lookup > 2:
            fail("bad Vorbis codebook lookup type")
        if lookup == 1 or lookup == 2:
            br.skip(32)
            br.skip(32)
            value_bits = br.read(4) + 1
            br.read(1)
            if lookup == 1:
                lv = lookup1_values(entries, dims)
            else:
                lv = entries * dims
            br.skip(lv * value_bits)

    for _ in range(br.read(6) + 1):
        if br.read(16) != 0:
            fail("unsupported Vorbis time-domain transform")

    floor_count = br.read(6) + 1
    for _ in range(floor_count):
        ftype = br.read(16)
        if ftype == 0:
            br.skip(8 + 16 + 16 + 6 + 8)
            br.skip((br.read(4) + 1) * 8)
        elif ftype == 1:
            partitions = br.read(5)
            pclass = []
            maxclass = -1
            for _p in range(partitions):
                v = br.read(4)
                pclass.append(v)
                if v > maxclass:
                    maxclass = v
            cdim = []
            for _c in range(maxclass + 1):
                cdim.append(br.read(3) + 1)
                subclasses = br.read(2)
                if subclasses > 0:
                    br.read(8)
                br.skip((1 << subclasses) * 8)
            br.read(2)
            rangebits = br.read(4)
            for p in range(partitions):
                br.skip(cdim[pclass[p]] * rangebits)
        else:
            fail("unsupported Vorbis floor type")

    residue_count = br.read(6) + 1
    for _ in range(residue_count):
        if br.read(16) > 2:
            fail("unsupported Vorbis residue type")
        br.skip(24 + 24 + 24)
        classes = br.read(6) + 1
        br.read(8)
        cascade = []
        for _c in range(classes):
            low = br.read(3)
            flag = br.read(1)
            high = br.read(5) if flag else 0
            cascade.append(high * 8 + low)
        for c in range(classes):
            for j in range(8):
                if cascade[c] & (1 << j):
                    br.read(8)

    mapping_count = br.read(6) + 1
    for _ in range(mapping_count):
        if br.read(16) != 0:
            fail("unsupported Vorbis mapping type")
        submaps = 1
        if br.read(1):
            submaps = br.read(4) + 1
        if br.read(1):
            steps = br.read(8) + 1
            br.skip(steps * ilog(channels - 1) * 2)
        if br.read(2) != 0:
            fail("unsupported Vorbis mapping submap type")
        if submaps > 1:
            br.skip(channels * 4)
        for _s in range(submaps):
            br.skip(8 + 8 + 8)

    modes = []
    for _ in range(br.read(6) + 1):
        blockflag = br.read(1)
        if br.read(16) != 0 or br.read(16) != 0:
            fail("unsupported Vorbis window/transform type")
        br.read(8)
        modes.append(blockflag == 1)
    if br.read(1) != 1:
        fail("Vorbis setup framing bit missing")
    if not modes:
        fail("Vorbis setup has no modes")
    return modes


def packet_blocksize(packet, modes, block0, block1):
    mbits = ilog(len(modes) - 1)
    br = BitReader(packet)
    if br.read(1) != 0:
        fail("audio packet has a non-zero packet type")
    mode = br.read(mbits) if mbits > 0 else 0
    if mode >= len(modes):
        fail("audio packet mode is out of range")
    return block1 if modes[mode] else block0


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

    rate = struct.unpack_from("<I", first_packets[0], 12)[0]
    channels = first_packets[0][11]
    if rate == 0:
        fail("fixture identification header has sample rate 0")

    # Sample-accurate Vorbis accounting.  A packet's output contribution is
    # (previous_blocksize + current_blocksize) / 4 after the first audio packet
    # (which has no previous block); page granules are the running total of
    # those contributions.  Both block sizes come from the identification
    # header and each packet's mode bit in the setup header.
    modes = parse_setup_modes(first_packets[2], channels)
    blocksize = first_packets[0][28]
    block0 = 1 << (blocksize & 0x0F)
    block1 = 1 << (blocksize >> 4)
    if block0 < 64 or block1 < block0:
        fail("fixture has invalid Vorbis block sizes")

    audio_packets = []
    pending = bytearray()
    for j, p in enumerate(audio_pages):
        cur = 0
        for lace in p.segs:
            pending += p.body[cur:cur + lace]
            cur += lace
            if lace < 255:
                audio_packets.append((bytes(pending), j))
                pending = bytearray()
    if pending:
        fail("fixture ends with an unterminated audio packet")
    if not audio_packets:
        fail("fixture has no audio packets")

    cum_at_page = [0] * len(audio_pages)
    cum = 0
    prev_bs = None
    for packet, page_index in audio_packets:
        bs = packet_blocksize(packet, modes, block0, block1)
        if prev_bs is not None:
            cum += (prev_bs + bs) // 4
        prev_bs = bs
        cum_at_page[page_index] = cum

    # Independent oracle: the committed fixture's non-final page granules were
    # produced by libvorbis/oggenc.  The accounting above must reproduce them
    # exactly.  Only the final page may be trimmed by the encoder, so its
    # stored granule may be below the computed total.
    for j in range(len(audio_pages) - 1):
        stored = audio_pages[j].granule
        if stored == NO_GRANULE:
            continue
        if cum_at_page[j] != stored:
            fail("sample accounting mismatch on fixture page %d: "
                 "computed %d, stored %d" % (j, cum_at_page[j], stored))
    untrimmed_total = cum_at_page[-1]
    if last_granule > untrimmed_total:
        fail("fixture final granule exceeds the decoded sample total")
    trim = untrimmed_total - last_granule
    if trim != 0 and not (audio_pages[-1].header_type & EOS):
        fail("fixture has a trimmed final granule without EOS")
    if untrimmed_total == 0:
        fail("fixture has no decoded audio samples")

    first_bs = packet_blocksize(audio_packets[0][0], modes, block0, block1)
    last_bs = packet_blocksize(audio_packets[-1][0], modes, block0, block1)
    boundary = (last_bs + first_bs) // 4
    block_advance = boundary + untrimmed_total
    if block_advance <= 0:
        fail("fixture block does not advance the granule")

    header_pages = pages[:audio_start]
    header_bytes = sum(len(p.raw) for p in header_pages)
    block_bytes = sum(len(p.raw) for p in audio_pages)
    if block_bytes == 0:
        fail("fixture audio block is empty")
    repeats = (target - header_bytes + block_bytes - 1) // block_bytes
    if repeats < 1:
        repeats = 1

    out = bytearray()
    seq = 0
    for p in header_pages:
        if p.header_type & EOS:
            fail("fixture header page carries EOS")
        out += build_page(p.header_type, p.granule, serial, seq, p.segs, p.body)
        seq += 1
    last_audio_page = len(audio_pages) - 1
    for k in range(repeats):
        for j, p in enumerate(audio_pages):
            header_type = p.header_type & ~EOS
            if k == repeats - 1 and j == last_audio_page:
                header_type |= EOS
            granule = p.granule
            if granule != NO_GRANULE:
                if k == 0:
                    # The fixture's first block keeps its libvorbis-written
                    # granules, including the final-page trim.
                    granule = p.granule
                else:
                    # Continuation position after trimming the previous block,
                    # plus the boundary overlap and this page's internal total.
                    granule = (last_granule + (k - 1) * block_advance
                               + boundary + cum_at_page[j])
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
    expected_final = last_granule + (repeats - 1) * block_advance
    if final != expected_final:
        fail("generated final granule %d != %d" %
             (final, expected_final))

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
        print("frames=%d" % final)
        print("block_advance=%d" % block_advance)
        print("trim=%d" % trim)
        print("channels=%d" % channels)
        print("sample_rate=%d" % rate)
        print("duration_s=%s" % format_ms(dur_ms))


if __name__ == "__main__":
    main()
