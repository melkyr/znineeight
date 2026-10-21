# Zstd — `std_zstd`

| | |
|---|---|
| **Modules** | `std_zstd` |
| **Layers** | `L4` — byte-codec layer: single-shot zstd frame decoder |
| **Import (by path)** | `const std_zstd = @import("std_zstd");` |

## Module overview

`std_zstd` is a stateless, single-shot decoder for the RFC 8878 zstd frame
format (a documented subset). It expands a complete compressed stream into a
caller-owned destination buffer. There is no heap allocation, no internal output
buffer, and no state carried between calls: history for a back-reference is
always the already-written prefix of `dst`, so the caller must keep the whole
decoded frame contiguous.

The module follows the L4 codec model used by `std_lz4`, not the arena model:
the caller owns both buffers and sizes `dst` for the full decoded payload.
Errors are deliberate and distinct — `error.Corrupt` (malformed, truncated, or
outside the supported subset), `error.OutputTooSmall` (the destination cannot
hold the frame's declared content), and `error.WindowTooBig` (the frame's
window log — or a single-segment content size — exceeds the caller's cap). A
failed call offers no partial-output contract; discard `dst` on any error.

## Quick start

```zig
const std = @import("std");
const std_zstd = @import("std_zstd");

var packed: [4096]u8 = undefined;   // filled offline with a .zst file
var packed_len: usize = 0;         // set to the actual .zst byte count
var plain: [16384]u8 = undefined;  // sized for the decoded payload

pub fn main() void {
    const n = std_zstd.zstdDecompress(
        packed[0..packed_len],
        plain[0..],
        std_zstd.ZSTD_DEFAULT_WINDOW_LOG,
    ) catch |e| {
        if (e == error.WindowTooBig) {
            std.io.write("compressed with a larger window\n");
        } else if (e == error.OutputTooSmall) {
            std.io.write("destination too small\n");
        } else {
            std.io.write("corrupt zstd stream\n");
        }
        return;
    };
    std.io.write(plain[0..@intCast(usize, n)]);
}
```

## API

### `ZSTD_DEFAULT_WINDOW_LOG`

**Purpose** — the default window cap: log2 bytes, `21` (2 MiB). It is the safe
value for the library's 16–32 MB target class.

**When to use** — as `max_window_log` when the producer used the default zstd
window (or any window at most 2 MiB).

**Signature** — `pub const ZSTD_DEFAULT_WINDOW_LOG: u8 = 21;`

**Parameters** — none.

**Returns** — a `u8` constant, `21`.

**Errors** — none.

**Example**
```zig
const n = std_zstd.zstdDecompress(src[0..], dst[0..], std_zstd.ZSTD_DEFAULT_WINDOW_LOG) catch return;
```

**Gotchas** — this is a policy default, not a property of the format. Frames
compressed with `--long=24` (or any window above 2 MiB) are rejected with
`error.WindowTooBig` until the caller passes a larger cap.

### `zstdDecompress`

**Purpose** — decodes a complete zstd stream (one or more standard frames, plus
skippable frames) into `dst`.

**When to use** — to expand data compressed **offline** with the host `zstd`
tool. The decoder is stateless and allocation-free, so it has no runtime
dependency on zstd or on a heap.

**Signature** — `pub fn zstdDecompress(src: []const u8, dst: []u8, max_window_log: u8) !u32`

**Parameters**
- `src` — the complete compressed stream. Standard frames
  (`0xFD2FB528`) are decoded in order; skippable frames (`0x184D2A50` mask) are
  skipped per the RFC and never surfaced.
- `dst` — the destination and the decoder's only history. The caller sizes it
  for the total decoded content. A back-reference never reaches before the
  already-written prefix (or outside the frame's window, whichever is tighter).
- `max_window_log` — the caller's window cap, in log2 bytes. Comparisons happen
  from the frame header before any block is decoded: a frame whose window log is
  greater returns `error.WindowTooBig`. Pass `ZSTD_DEFAULT_WINDOW_LOG` (21) on a
  small box; on a 256 MB machine, `24`–`28` accepts the corresponding
  `zstd --long=...` frames. A single-segment frame (no window descriptor) uses
  its content size as its window, and that size is checked against the same cap.

**Returns** — the total number of bytes written to `dst` (`u32`), across all
decoded standard frames. A stream containing only skippable frames writes
nothing and returns `0`.

**Errors**
- `error.Corrupt` — empty input, bad magic, truncated header/block/table,
  malformed FSE or Huffman data, a back-reference outside the written history
  or the frame window, a content-size mismatch, a checksum mismatch, or a
  feature outside the supported subset (most notably a nonzero dictionary id).
- `error.OutputTooSmall` — a frame declares more content than the remaining
  space in `dst`, or a block would write past `dst.len`.
- `error.WindowTooBig` — the frame's window log exceeds `max_window_log`, or a
  single-segment frame's content size exceeds `2^max_window_log`.

**Example**
```zig
const std_zstd = @import("std_zstd");

var dst: [1 << 20]u8 = undefined;
const n = std_zstd.zstdDecompress(frame[0..], dst[0..], 24) catch |e| {
    if (e == error.WindowTooBig) return;     // raise the cap or recompress
    if (e == error.OutputTooSmall) return;   // caller sized dst too small
    return;                                  // error.Corrupt
};
std.io.write(dst[0..@intCast(usize, n)]);
```

**Gotchas** — no heap and no buffer beyond `dst`: Huffman/FSE tables are
function-local (a few KB of stack). Concatenated standard frames are decoded in
sequence into the same `dst`, and the return value is the sum of their outputs.
Skippable-frame payloads are ignored, including a stream made only of skippable
frames (`0` written). On any error the destination may contain partial output —
there is no partial-output contract, so treat `dst` as invalid and retry into a
fresh buffer after fixing the caller's size/cap or the input.

### Supported subset and boundaries

- Standard zstd frames with raw, RLE, and compressed blocks.
- Huffman literals: raw, RLE, compressed (direct-weight and FSE-compressed tree
  descriptions), and treeless/repeat modes.
- FSE sequence tables: predefined, RLE, and FSE-compressed modes, plus repeat
  modes and repeat offsets.
- Optional content size and content checksum (xxh64 low 32 bits).
- RFC-mandated skippable frames.
- **No dictionaries.** A frame with a nonzero dictionary id is
  `error.Corrupt`; dictionary-compressed data must not be produced for this
  decoder.
- No legacy/magicless frames and no streaming API: input must be a complete
  frame stream and output must fit the caller's `dst` in one call.

### Offline-compress workflow

Compression is never done at runtime by Z98:

1. Compress on the host with the zstd CLI, for example
   `zstd -19 -f input.bin -o input.bin.zst`. Level `-19` raises the window on
   larger inputs (libzstd 1.5.4 uses window log 23 on 10 MiB), and `--long=24`
   (or another window log) raises it further. Either give the decoder a matching
   `max_window_log` (`23`–`24` for `-19` on more than 2 MiB) or constrain the
   producer with `zstd --zstd=wlog=21`. Do **not** use `-D` / dictionaries.
2. Commit the resulting `.zst` as the `.in` fixture/asset and its decoded bytes
   (or the original input) as `.expected`; never regenerate vectors during a
   test run — the committed pair is the frozen agreement.
3. At runtime pass the `.zst` bytes and a `dst` sized for the known decoded
   length to `zstdDecompress`, with `max_window_log` no smaller than the window
   used to produce the frame. Level `-1` output fits the default `21`; level
   `-19` raises the window automatically on larger inputs, so use `23`–`24`
   for `-19` on more than 2 MiB (a 256 MB box can pass `24`–`28`) or constrain
   the producer with `zstd --zstd=wlog=21`.

The repo's vectors follow this path: `scripts/stdlib/vectors/std_zstd/` holds
committed host-zstd frames (text, binary, incompressible data, several window
logs and levels, plus empty content) and their expected decoded bytes.

## See also

- `std_zstd` — the module in this doc.
- [`codecs.md`](codecs.md) — the sibling L4/L5 codecs, including `std_lz4`.
- [`memory.md`](memory.md) — the arena model used by the allocating codecs.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
