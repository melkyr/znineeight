# Deflate — `std_deflate`

| | |
|---|---|
| **Modules** | `std_deflate` |
| **Layers** | `L4` — byte-codec layer: single-shot RFC 1951 DEFLATE / RFC 1950 zlib inflater |
| **Import (by path)** | `const std_deflate = @import("std_deflate");` |

## Module overview

`std_deflate` is a stateless, single-shot **inflater**: it expands a complete
raw DEFLATE stream (`inflateRaw`) or zlib-wrapped stream (`inflateZlib`) into a
caller-owned destination buffer. There is no heap allocation, no internal output
buffer, and no compressor. History for a back-reference is always the
already-written prefix of `dst` (the 32 KiB DEFLATE window is bounded by the
written output), so the caller must keep the whole decoded stream contiguous.

The module follows the L4 codec model used by `std_lz4` and `std_zstd`, not the
arena model: the caller owns both buffers and sizes `dst` for the full decoded
payload. Both entry points take a mandatory `used: *usize` out-parameter that
reports the number of **input bytes consumed**, wrapper bytes included, so a
caller can resume at `src[used..]` for concatenated streams (Git pack data uses
this to find the next object). Errors are deliberate and distinct:
`error.Corrupt` (malformed, truncated, unsupported, or a failed zlib check) and
`error.OutputTooSmall` (the destination cannot hold the decoded content). A
failed call offers no partial-output contract; discard `dst` on any error.

## Quick start

```zig
const std = @import("std");
const std_deflate = @import("std_deflate");

var packed: [4096]u8 = undefined;   // filled with a zlib stream
var packed_len: usize = 0;         // set to the actual byte count
var plain: [16384]u8 = undefined;  // sized for the decoded payload
var used: usize = 0;

pub fn main() void {
    const n = std_deflate.inflateZlib(
        packed[0..packed_len],
        plain[0..],
        &used,
    ) catch |e| {
        if (e == error.OutputTooSmall) {
            std.io.write("destination too small\n");
        } else {
            std.io.write("corrupt zlib stream\n");
        }
        return;
    };
    std.io.write(plain[0..@intCast(usize, n)]);
}
```

## API

### `inflateRaw`

**Purpose** — decodes a complete RFC 1951 raw DEFLATE stream into `dst`, without
a zlib wrapper.

**When to use** — when the surrounding container already carries the stream
extent (for example, a DEFLATE payload whose length is known from elsewhere), or
when you are decoding data that is not zlib-wrapped. Use `inflateZlib` for a
standard zlib stream (`0x78 …` header plus Adler-32 trailer).

**Signature** — `pub fn inflateRaw(src: []const u8, dst: []u8, used: *usize) !u32`

**Parameters**
- `src` — the complete raw DEFLATE stream.
- `dst` — the destination and the decoder's only history. The caller sizes it
  for the total decoded content.
- `used` — out-parameter receiving the number of input bytes consumed on
  success.

**Returns** — the number of bytes written to `dst` (`u32`).

**Errors**
- `error.Corrupt` — empty/truncated input, an invalid block type, a bad stored
  block length check, malformed Huffman tables, a length/distance code outside
  the format, or a back-reference before the start of the output.
- `error.OutputTooSmall` — a block would write past `dst.len`.

**Example**
```zig
const std_deflate = @import("std_deflate");

var dst: [1 << 16]u8 = undefined;
var used: usize = 0;
const n = std_deflate.inflateRaw(raw[0..], dst[0..], &used) catch return;
std.io.write(dst[0..@intCast(usize, n)]);
```

**Gotchas** — no wrapper validation and no checksum in this entry point: the
caller is responsible for any container-level integrity check. Only the bytes
actually consumed are reported; a trailing concatenated stream is left at
`src[used..]`.

### `inflateZlib`

**Purpose** — decodes a complete RFC 1950 zlib-wrapped DEFLATE stream into
`dst`, validating the wrapper and the Adler-32 trailer.

**When to use** — for standard zlib data, including Git loose-object and pack
payloads. It checks the compression method (CM = 8), the window size, the
`CMF`/`FLG` check value (`FCHECK`, `(CMF*256 + FLG) % 31 == 0`), and the
Adler-32 of the decoded bytes.

**Signature** — `pub fn inflateZlib(src: []const u8, dst: []u8, used: *usize) !u32`

**Parameters**
- `src` — the complete zlib stream: two-byte header, DEFLATE data, four-byte
  Adler-32 trailer.
- `dst` — the destination buffer, sized for the decoded content.
- `used` — out-parameter receiving the number of input bytes consumed on
  success (header + DEFLATE data + trailer).

**Returns** — the number of bytes written to `dst` (`u32`).

**Errors**
- `error.Corrupt` — input shorter than the minimum wrapper, a compression
  method other than DEFLATE, an invalid window size, a failed `FCHECK`, a
  preset dictionary (`FDICT`, unsupported), malformed/truncated DEFLATE data, a
  missing or mismatched Adler-32 trailer, or another structural error.
- `error.OutputTooSmall` — a block would write past `dst.len`.

**Example**
```zig
const std_deflate = @import("std_deflate");

var dst: [1 << 16]u8 = undefined;
var used: usize = 0;
const n = std_deflate.inflateZlib(zlib[0..], dst[0..], &used) catch |e| {
    if (e == error.OutputTooSmall) return; // size dst for the payload
    return;                                // error.Corrupt
};
std.io.write(dst[0..@intCast(usize, n)]);
```

**Gotchas** — a preset-dictionary zlib stream (`FDICT` set) is rejected with
`error.Corrupt`; Git never emits one. The Adler-32 is computed over the decoded
output, so a truncated stream or a wrong destination window surfaces as a
corrupt stream. On any error `used` is unspecified and `dst` may contain
partial output.

### Supported subset and boundaries

- RFC 1951 stored, fixed-Huffman, and dynamic-Huffman blocks.
- Length/distance codes with the full 32 KiB window; overlapping matches are
  copied byte by byte.
- RFC 1950 zlib wrapper validation: CM = DEFLATE, CINFO window bound,
  `CMF`/`FLG` `FCHECK`, and the Adler-32 trailer.
- **No preset dictionaries** (`FDICT` → `error.Corrupt`).
- **No compression** and no streaming API: input must be one complete stream
  and output must fit the caller's `dst` in one call. Decode tables are
  function-local fixed arrays; the 32 KiB window is the already-written output.

### Offline-compress workflow

Compression is never done at runtime by Z98. Produce the input with a host tool
(for example `python3 -c 'import zlib,sys; ...'` or `gzip -c` for the raw
stream), commit the compressed bytes as the `.in` fixture/asset and the decoded
bytes as `.expected`, and never regenerate vectors during a test run. At runtime
pass the compressed bytes and a `dst` sized for the known decoded length.

## See also

- `std_deflate` — the module in this doc.
- [`zstd.md`](zstd.md) — the sibling L4 zstd decoder, including dictionaries.
- [`codecs.md`](codecs.md) — the sibling L4/L5 codecs, including `std_lz4`.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
