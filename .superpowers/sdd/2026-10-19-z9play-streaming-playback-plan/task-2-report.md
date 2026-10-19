# M9 Task 2 report — incremental OGG pages and packets

**Status:** READY — gate PASS, no STOP condition.

**Base:** branch `zig1_improvements`, pre-task HEAD `f7a28b50`
(`docs(sdd): M9 T1 ledger`).

**Seed:** `/tmp/m7_t5_seed2/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`, seed v102 fixed point).

**Scope:** only the two Task 2 files were added:

- `examples/z98/z9play/ogg_stream.zig`
- `examples/z98/z9play/tests/ogg_stream_test.zig`

No frontend, compiler, stdlib, seed, plan, spec, `run.err`, `lin_bin/`, or
`progress.md` changes.

**Commit:** `dc11bc88` `example(z9play): incremental OGG packet stream`
(2 files, 796 insertions).

---

## 1. Interface and constants

`ogg_stream.zig` matches M9 spec §4.2:

```zig
pub const OGG_PAGE_MAX: usize = 27 + 255 + 65025; // 65307
pub const OGG_PAGE_BUF: usize = 65536;
pub const OGG_PACKET_MAX: usize = 1024 * 1024;
pub const TAIL_WINDOW: usize = 256 * 1024;

pub const OggStreamError = error{
    BadCapture, BadVersion, Truncated, Crc, OutOfMemory,
    PacketTooLarge, SerialMismatch,
};

pub const OggStream = struct {
    bf: stream.BufferedFile,
    page: []u8,
    page_len: usize,
    page_seg: usize,
    page_body: usize,
    nseg: usize,
    packet: []u8,
    packet_len: usize,
    serial: u32,
    have_serial: bool,
    pending: bool,
};

pub fn oggStreamOpen(arena, path) OggStreamError!OggStream
pub fn oggStreamClose(s) void
pub fn oggStreamNextPacket(s) OggStreamError!?[]const u8
pub fn oggStreamLastGranule(arena, path, serial) OggStreamError!u64
```

`page_body` is the **page-local** offset of the next body byte; `page_seg` is
the current segment-table index. A zero `page_len` means no page is loaded.

---

## 2. Implementation decisions required by the brief

- **Incremental page read.** `loadPage` reads the 27-byte header, parses `nseg`,
  reads the segment table, sums the laces, reads exactly the body, and requires
  `27 + nseg + body <= OGG_PAGE_BUF`. Capture, version, and exact lengths are
  checked before CRC.
- **CRC.** `ogg.crcOk` is called on the page-local buffer
  `page[0..total]` with a local `ogg.Page` whose `body_start` is
  `27 + nseg`. The CRC field is zeroed by the existing helper's semantics.
- **Page-local offsets.** No absolute file offset is ever stored in the stream
  page state. `ogg.Page.body_start`/`body_len` values passed to `ogg.crcOk` are
  local (`< OGG_PAGE_BUF`), so a file larger than 4 GiB cannot overflow a `u32`.
  The tail scan likewise uses page-local candidates inside its bounded buffer.
- **Serial.** The first successfully loaded page sets `serial` /
  `have_serial`; any later page with a different serial returns
  `SerialMismatch`.
- **Continuation contract.** At a page boundary, `pending` is set when a packet
  is still open (`packet_len != 0`). A non-continuation page while pending and a
  continuation page with no pending packet both return `Truncated`.
- **Packet lifetime.** `oggStreamNextPacket` returns a slice into the fixed
  1 MiB `packet` buffer; it is valid **until the next call**. A `<255` lace
  terminates and resets the packet; `255` continues across segments and pages.
  `packet_len + lace > OGG_PACKET_MAX` returns `PacketTooLarge` before any copy.
- **Clean EOF.** A clean page boundary returns `null`. An open packet at EOF
  returns `Truncated`.
- **Error mapping.** The spec's `OggStreamError` has no I/O variants, so
  `stream.StreamError` open/read/seek/size failures map to `Truncated`, except
  `OutOfMemory`, which is preserved.
- **Tail scan.** `oggStreamLastGranule` uses its own handle and does not touch a
  decode cursor. It first reads at most `TAIL_WINDOW` (256 KiB) from EOF and
  accepts only a page that ends exactly at the end of the file, has a valid CRC,
  and matches `serial`. If the final page could straddle the window, it retries
  once with `TAIL_WINDOW + OGG_PAGE_MAX` bytes, still bounded by the file size.
  An empty file returns `0`; a non-empty file with no complete final page
  returns `Truncated`.
- **Oracles only.** Production `ogg_stream.zig` imports `ogg` only for
  `crcOk`. It never calls `ogg.reassemble` or `ogg.lastGranule`.

---

## 3. Test coverage

`tests/ogg_stream_test.zig` compares the streaming path against the byte-slice
oracles for all five committed OGG fixtures:

- `examples/z98/z9play/testdata/sine_stereo_44100.ogg`
- `examples/z98/z9play/testdata/sine_mono_44100.ogg`
- `examples/z98/z9play/testdata/sine_stereo_48000.ogg`
- `examples/z98/z9play/testdata/tagged_unicode.ogg`
- `examples/z98/z9play/testdata/short.ogg`

For each fixture:

- every packet from `oggStreamNextPacket` is compared byte-for-byte, in order,
  with `ogg.reassemble`, and the packet counts must match;
- `oggStreamLastGranule` (serial taken from the first page) must equal
  `ogg.lastGranule`.

Synthetic files cover:

1. CRC failure (valid page, body byte corrupted after CRC) → `Crc`.
2. Legal cross-page continuation (255-byte lace carried into a continuation
   page with laces 45 then 3) → exact 300-byte and 3-byte packets, plus a tail
   granule check.
3. Continuation page with no pending packet → `Truncated`.
4. Non-continuation page while a packet is pending → `Truncated`.
5. Serial mismatch on the second page → first packet OK, then `SerialMismatch`.
6. `PacketTooLarge` (17 pages of 255 laces / 65,025 body bytes).
7. EOF in the middle of a page → `Truncated` from both `nextPacket` and the tail
   scan.
8. Empty file → `nextPacket == null`, `lastGranule == 0`.

---

## 4. Build and test evidence

Seed identity:

```
$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
```

Exact commands (from repo root; emitted binding recipe, `-fsafe`):

```
$ rm -rf /tmp/m9_t2_ogg && mkdir -p /tmp/m9_t2_ogg
$ timeout 300 /tmp/m7_t5_seed2/zig1_5_clean -fsafe \
    -o /tmp/m9_t2_ogg examples/z98/z9play/tests/ogg_stream_test.zig
$ sh /tmp/m9_t2_ogg/build_target.sh linux /tmp/m9_t2_ogg/prog
$ /tmp/m9_t2_ogg/prog
```

Exact results:

```
zig_rc=0
Built: /tmp/m9_t2_ogg/prog
build_rc=0
ogg_stream_test: PASS fixtures=5 synthetic=8
test_rc=0
```

The emitted binary is a 32-bit i386 Linux executable. The build log contains
only the standard seed-runtime unused-function warnings; there are no errors or
warnings from `ogg_stream.zig` or `ogg_stream_test.zig`.

---

## 5. Concerns / notes

- **I/O error mapping:** because the spec's `OggStreamError` set has no
  open/read/seek/size errors, all such stream failures map to `Truncated`
  (except `OutOfMemory`). This is deliberate, not a frontend contract change.
- **Tail final-page rule:** the scan requires the final complete page to end at
  EOF. A file truncated in the middle of the final page returns `Truncated`
  rather than the previous page's granule; this matches the brief's
  "or returning `Truncated`" allowance and the synthetic EOF test.
- **Tail expansion:** the first read is exactly the last ≤256 KiB. The one
  straddle retry reads `TAIL_WINDOW + OGG_PAGE_MAX` (≤327,451 bytes), bounded by
  the file size; it never reads the whole file.
- **Size handle:** `oggStreamLastGranule` briefly opens a handle to read the file
  size, closes it, then opens the scanning handle. Neither handle is the decode
  stream, so the decode cursor is untouched.
- **No full-file reads or whole-file allocations** were added. Page and packet
  buffers are fixed; the tail buffer is bounded as described.
