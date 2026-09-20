# Codecs — `std_base64` + `std_hex` + `std_utf8` + `std_crypto` + `std_parse`

| | |
|---|---|
| **Modules** | `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_parse` |
| **Layers** | `L5` — codec layer: base64 and hex text codecs, UTF-8 validation/iteration, streaming hashes plus CRC-32, and number parse/format |
| **Import (by path)** | `const std_base64 = @import("std_base64");`, `const std_hex = @import("std_hex");`, `const std_utf8 = @import("std_utf8");`, `const std_crypto = @import("std_crypto");`, `const std_parse = @import("std_parse");` |

## Module overview

All five modules are L5 and imported by path (not re-exported through `std`).
They split into three shapes.

**Text codecs (`std_base64`, `std_hex`).** Both allocate only their output
through the caller's arena and follow the same input contract. `encode`/`decode`
of empty input is a **valid** empty result (a length-0 slice), distinct from an
invalid one. On decode, any byte outside the alphabet, a wrong length, or
malformed padding is `error.InvalidInput`; whitespace is **not** skipped, and an
invalid decode allocates nothing (`used` unchanged). `std_base64` is RFC 4648 §4
standard padded base64 (`A-Za-z0-9+/`, mandatory `=` out to a multiple of 4).
`std_hex` is two characters per byte, high nybble first; `encodeLower` emits
`0-9a-f`, `encodeUpper` emits `0-9A-F`, and `decode` is case-insensitive.

**Pure validators and hashes (`std_utf8`, `std_crypto`).** Both are pure (no
imports, no allocation) and deterministic (R6). `std_utf8` validates and
iterates UTF-8 per RFC 3629: continuation bytes must be `0x80..0xBF`, and
overlong forms, UTF-16 surrogates (`U+D800..U+DFFF`), and code points above
`U+10FFFF` are rejected. `std_crypto` is a streaming hash suite — SHA-1,
SHA-256, MD5, and CRC-32 — with a caller-provided state: `*Init` returns a
value-type state, `*Update` takes `*State` and may be called any number of times
with any chunk sizes, and `*Final` writes into a caller array (or, for CRC-32,
returns the finished `u32`).

**Number parse/format (`std_parse`).** Pure and allocation-free. Parsing rejects
whitespace, `'+'`, and underscores, and returns `null` on overflow or malformed
input (overflow is detected in `u64` before narrowing, so a bad input never
traps). Formatting writes digits backwards from the end of `buf`; the returned
slice points into `buf`. `ftoa` uses fixed-point notation with round-half-up and
renders non-finite values as text.

## Quick start

A base64 round-trip and a SHA-256 hash of a string.

```zig
const std = @import("std");
const std_base64 = @import("std_base64");
const std_hex = @import("std_hex");
const std_crypto = @import("std_crypto");

var backing: [4096]u8 = undefined;
var arena = std.arena.init(backing[0..]);

pub fn main() void {
    var msg = [_]u8{ 0x5A, 0x39, 0x38, 0x20, 0xC3, 0xA9 };

    const b64 = std_base64.encode(&arena, msg[0..]) catch @panic("b64");
    const back = std_base64.decode(&arena, b64) catch @panic("unb64");
    if (back.len == msg.len) {
        std.io.write("round-trip ok\n");
    }

    var digest: [32]u8 = undefined;
    var sha = std_crypto.sha256Init();
    std_crypto.sha256Update(&sha, msg[0..]);
    std_crypto.sha256Final(&sha, &digest);

    const text = std_hex.encodeLower(&arena, digest[0..]) catch @panic("hex");
    std.io.write(text);
    std.io.writeByte('\n');
    std.arena.reset(&arena);
}
```

## API

### `std_base64`

#### `encodedLen`

**Purpose** — returns the exact encoded size for an `n`-byte input:
`4 * ceil(n / 3)`.

**When to use** — to size an output buffer before encoding; allocation-free.

**Signature** — `pub fn encodedLen(n: usize) usize`

**Parameters**
- `n` — the raw input length in bytes.

**Returns** — the exact number of base64 characters `encode` will produce.

**Errors** — none.

**Example**
```zig
const need = std_base64.encodedLen(raw.len);
```

**Gotchas** — the count includes `=` padding.

#### `decodedLen`

**Purpose** — returns an upper bound on the decoded size for `n` encoded
characters: `(n / 4) * 3`.

**When to use** — to size a decode buffer; allocation-free.

**Signature** — `pub fn decodedLen(n: usize) usize`

**Parameters**
- `n` — the base64 text length in characters.

**Returns** — an upper bound: the exact decoded length depends on trailing
padding, which a length alone cannot reveal.

**Errors** — none.

**Example**
```zig
const cap = std_base64.decodedLen(text.len);
```

**Gotchas** — an over-estimate by up to two bytes; `decode` allocates the exact
length internally.

#### `encode`

**Purpose** — encodes `src` as RFC 4648 standard padded base64 into a freshly
allocated arena buffer.

**When to use** — to produce base64 text. No whitespace or line breaks are
emitted.

**Signature** — `pub fn encode(arena: *arena_mod.Arena, src: []const u8) ![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the bytes to encode; empty input yields an empty result.

**Returns** — a `[]u8` of `encodedLen(src.len)` characters.

**Errors** — `error.OutOfMemory` when the arena cannot provide the output.

**Example**
```zig
const text = std_base64.encode(&arena, raw[0..]) catch @panic("encode");
```

**Gotchas** — allocates only its output; the result is valid until the next
arena `reset`.

#### `decode`

**Purpose** — decodes canonical padded base64 into a freshly allocated arena
buffer.

**When to use** — to recover the bytes from base64 text.

**Signature** — `pub fn decode(arena: *arena_mod.Arena, src: []const u8) DecodeError![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the base64 text. Empty input is valid and returns an empty slice.

**Returns** — a `[]u8` of the decoded bytes.

**Errors**
- `error.OutOfMemory` — the arena cannot provide the output.
- `error.InvalidInput` — `src.len` is not a multiple of 4, a byte is outside the
  alphabet (including whitespace), or `=` is misplaced or malformed.

**Example**
```zig
const bytes = std_base64.decode(&arena, text) catch |e| {
    if (e == error.InvalidInput) return;
    return;
};
```

**Gotchas** — whitespace is **not** skipped; an invalid decode allocates nothing
(`used` unchanged). The decoder validates the alphabet, the length, and padding
placement, but does **not** re-check that the bits under `=` padding are zero, so
some non-canonical trailing bits are accepted.

### `std_hex`

#### `encodeLower`

**Purpose** — encodes `src` as lowercase hexadecimal, two characters per byte,
high nybble first.

**When to use** — to render bytes as `0-9a-f`.

**Signature** — `pub fn encodeLower(arena: *arena_mod.Arena, src: []const u8) ![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the bytes to encode; empty input yields an empty result.

**Returns** — a `[]u8` of `src.len * 2` characters.

**Errors** — `error.OutOfMemory` when the arena cannot provide the output.

**Example**
```zig
const text = std_hex.encodeLower(&arena, bytes[0..]) catch @panic("hex");
```

**Gotchas** — allocates only its output; valid until the next arena `reset`.

#### `encodeUpper`

**Purpose** — encodes `src` as uppercase hexadecimal, two characters per byte,
high nybble first.

**When to use** — to render bytes as `0-9A-F`.

**Signature** — `pub fn encodeUpper(arena: *arena_mod.Arena, src: []const u8) ![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the bytes to encode; empty input yields an empty result.

**Returns** — a `[]u8` of `src.len * 2` characters.

**Errors** — `error.OutOfMemory` when the arena cannot provide the output.

**Example**
```zig
const text = std_hex.encodeUpper(&arena, bytes[0..]) catch @panic("hex");
```

**Gotchas** — allocates only its output; `decode` accepts either case.

#### `decode`

**Purpose** — decodes a hexadecimal string into a freshly allocated arena
buffer.

**When to use** — to recover bytes from hex text.

**Signature** — `pub fn decode(arena: *arena_mod.Arena, src: []const u8) DecodeError![]u8`

**Parameters**
- `arena` — the allocation source for the output.
- `src` — the hex text; must have even length. Empty input is valid and returns
  an empty slice.

**Returns** — a `[]u8` of `src.len / 2` bytes.

**Errors**
- `error.OutOfMemory` — the arena cannot provide the output.
- `error.InvalidInput` — `src.len` is odd, or a byte is outside `[0-9a-fA-F]`
  (including whitespace).

**Example**
```zig
const bytes = std_hex.decode(&arena, text) catch |e| {
    if (e == error.InvalidInput) return;
    return;
};
```

**Gotchas** — case-insensitive; whitespace is **not** skipped. An invalid decode
allocates nothing (`used` unchanged).

### `std_utf8`

#### `Codepoint`

**Purpose** — a decoded Unicode scalar value and its encoded byte length.

**When to use** — as the value returned by `decode`.

**Signature** — `pub const Codepoint = struct { cp: u32, len: u8 };`

**Parameters** (fields)
- `cp` — the code point value (a Unicode scalar, so never a surrogate and never
  above `U+10FFFF`).
- `len` — the number of bytes consumed (`1..4`).

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
if (std_utf8.decode(msg)) |cp| {
    std.io.printInt(@intCast(i32, cp.cp));
}
```

**Gotchas** — Z98 cannot write an anonymous struct type literally, so the
blueprint's `?struct { cp, len }` is declared as this named type with the same
field names, order, and layout.

#### `codepointLen`

**Purpose** — returns the sequence length a lead byte introduces: `1..4`, or `0`
if the byte can never begin a valid sequence.

**When to use** — to advance over a sequence when you only have the lead byte,
or to reject an impossible start cheaply.

**Signature** — `pub fn codepointLen(first_byte: u8) u8`

**Parameters**
- `first_byte` — the first byte of a sequence.

**Returns** — `1` for `0x00..0x7F`, `2` for `0xC2..0xDF`, `3` for `0xE0..0xEF`,
`4` for `0xF0..0xF4`, otherwise `0`.

**Errors** — none.

**Example**
```zig
const n = std_utf8.codepointLen(msg[0]);
```

**Gotchas** — consults only the lead byte; the second-byte constraints (overlong
`E0`/`F0`, surrogate `ED`, `>U+10FFFF` `F4`) are enforced by `decode`. Lead
bytes `0x80..0xBF`, `0xC0`, `0xC1`, and `0xF5..0xFF` return `0`.

#### `decode`

**Purpose** — decodes and validates the first code point of `s`.

**When to use** — to walk a UTF-8 buffer one code point at a time, validating as
you go.

**Signature** — `pub fn decode(s: []const u8) ?Codepoint`

**Parameters**
- `s` — a byte slice starting at a code point boundary.

**Returns** — `?Codepoint`: the first code point, or `null` when `s` is empty or
does not begin with valid UTF-8 (including a truncated sequence).

**Errors** — none; invalidity is the `null` optional.

**Example**
```zig
var i: usize = 0;
while (i < msg.len) {
    if (std_utf8.decode(msg[i..])) |cp| {
        i += @intCast(usize, cp.len);
    } else {
        i += 1;
    }
}
```

**Gotchas** — validates before returning, so it never yields a value outside the
Unicode scalar range: overlong forms, surrogates, and `>U+10FFFF` all return
`null`.

#### `encode`

**Purpose** — writes the UTF-8 encoding of `cp` into `buf`.

**When to use** — to turn a code point value back into bytes.

**Signature** — `pub fn encode(buf: []u8, cp: u32) ?[]u8`

**Parameters**
- `buf` — the destination; must have room for the whole encoding.
- `cp` — the code point to encode.

**Returns** — `?[]u8`: `buf[0..n]`, the encoded bytes, or `null` when `cp` is a
surrogate, is above `U+10FFFF`, or `buf` is too small.

**Errors** — none; failure is the `null` optional.

**Example**
```zig
var buf: [4]u8 = undefined;
if (std_utf8.encode(buf[0..], 233)) |enc| {
    std.io.write(enc);
}
```

**Gotchas** — refuses a buffer smaller than the encoding rather than writing a
partial sequence. Rejects surrogates and code points above `U+10FFFF`.

#### `countCodepoints`

**Purpose** — counts code points in `s` by walking it.

**When to use** — to get a code-point count (not a byte count).

**Signature** — `pub fn countCodepoints(s: []const u8) usize`

**Parameters**
- `s` — the byte slice.

**Returns** — the number of code points: each valid code point counts `1`; a
byte that begins an invalid sequence also counts `1` and advances one byte.

**Errors** — none.

**Example**
```zig
const n = std_utf8.countCodepoints(msg);
```

**Gotchas** — total on any input (never traps or hangs); it does not report
where invalid bytes are. A lone continuation byte counts as one "code point".

### `std_crypto`

#### `Sha1`

**Purpose** — streaming SHA-1 state (RFC 3174): five chaining words plus a
64-byte block buffer, buffered length, and total byte count.

**When to use** — as the value returned by `sha1Init` and passed to
`sha1Update`/`sha1Final`.

**Signature** — `pub const Sha1 = struct { h0: u32, h1: u32, h2: u32, h3: u32, h4: u32, buf: [64]u8, buf_len: usize, total: u64 };`

**Parameters** (fields)
- `h0..h4` — the five chaining words.
- `buf` — the pending 64-byte block.
- `buf_len` — bytes buffered in `buf`.
- `total` — total bytes fed so far.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var s = std_crypto.sha1Init();
```

**Gotchas** — treat the fields as internal; drive it only through the
Init/Update/Final functions. Do not copy a state mid-stream unless you intend to
fork the hash.

#### `sha1Init`

**Purpose** — returns a fresh SHA-1 state with the standard initial constants.

**When to use** — once at the start of a hash.

**Signature** — `pub fn sha1Init() Sha1`

**Parameters** — none.

**Returns** — a `Sha1` ready for `sha1Update`.

**Errors** — none.

**Example**
```zig
var s = std_crypto.sha1Init();
```

**Gotchas** — the state is a value, so it can live on the stack or in a struct.

#### `sha1Update`

**Purpose** — feeds a chunk into the SHA-1 state.

**When to use** — once per chunk; may be called any number of times with any
chunk sizes, including zero.

**Signature** — `pub fn sha1Update(s: *Sha1, data: []const u8) void`

**Parameters**
- `s` — the state to advance.
- `data` — the bytes to absorb.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_crypto.sha1Update(&s, "hello");
std_crypto.sha1Update(&s, " world");
```

**Gotchas** — the hash is the same for any chunking of the same byte sequence.
A zero-length `data` is a no-op.

#### `sha1Final`

**Purpose** — finishes the hash and writes the 20-byte digest into `out`.

**When to use** — once, after the last `sha1Update`.

**Signature** — `pub fn sha1Final(s: *Sha1, out: *[20]u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — the 20-byte destination.

**Returns** — nothing; the digest is written through `out`.

**Errors** — none.

**Example**
```zig
var digest: [20]u8 = undefined;
std_crypto.sha1Final(&s, &digest);
```

**Gotchas** — pads and processes the final block; do not call `sha1Update`
afterwards. The digest is big-endian.

#### `Sha256`

**Purpose** — streaming SHA-256 state (FIPS 180-4): eight chaining words plus a
64-byte block buffer, buffered length, and total byte count.

**When to use** — as the value returned by `sha256Init` and passed to
`sha256Update`/`sha256Final`.

**Signature** — `pub const Sha256 = struct { h: [8]u32, buf: [64]u8, buf_len: usize, total: u64 };`

**Parameters** (fields)
- `h` — the eight chaining words.
- `buf` — the pending 64-byte block.
- `buf_len` — bytes buffered in `buf`.
- `total` — total bytes fed so far.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var s = std_crypto.sha256Init();
```

**Gotchas** — treat the fields as internal; drive it only through the
Init/Update/Final functions.

#### `sha256Init`

**Purpose** — returns a fresh SHA-256 state with the standard initial constants.

**When to use** — once at the start of a hash.

**Signature** — `pub fn sha256Init() Sha256`

**Parameters** — none.

**Returns** — a `Sha256` ready for `sha256Update`.

**Errors** — none.

**Example**
```zig
var s = std_crypto.sha256Init();
```

**Gotchas** — a value type; safe to keep on the stack.

#### `sha256Update`

**Purpose** — feeds a chunk into the SHA-256 state.

**When to use** — once per chunk; any number of calls and chunk sizes.

**Signature** — `pub fn sha256Update(s: *Sha256, data: []const u8) void`

**Parameters**
- `s` — the state to advance.
- `data` — the bytes to absorb.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_crypto.sha256Update(&s, msg);
```

**Gotchas** — chunking-independent; a zero-length `data` is a no-op.

#### `sha256Final`

**Purpose** — finishes the hash and writes the 32-byte digest into `out`.

**When to use** — once, after the last `sha256Update`.

**Signature** — `pub fn sha256Final(s: *Sha256, out: *[32]u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — the 32-byte destination.

**Returns** — nothing; the digest is written through `out`.

**Errors** — none.

**Example**
```zig
var digest: [32]u8 = undefined;
std_crypto.sha256Final(&s, &digest);
```

**Gotchas** — do not call `sha256Update` afterwards. The digest is big-endian.

#### `Md5`

**Purpose** — streaming MD5 state (RFC 1321): four chaining words plus a 64-byte
block buffer, buffered length, and total byte count.

**When to use** — as the value returned by `md5Init` and passed to
`md5Update`/`md5Final`.

**Signature** — `pub const Md5 = struct { h0: u32, h1: u32, h2: u32, h3: u32, buf: [64]u8, buf_len: usize, total: u64 };`

**Parameters** (fields)
- `h0..h3` — the four chaining words.
- `buf` — the pending 64-byte block.
- `buf_len` — bytes buffered in `buf`.
- `total` — total bytes fed so far.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var s = std_crypto.md5Init();
```

**Gotchas** — MD5 is not collision-resistant; use it for checksums and legacy
interop, not for security. Treat the fields as internal.

#### `md5Init`

**Purpose** — returns a fresh MD5 state with the standard initial constants.

**When to use** — once at the start of a hash.

**Signature** — `pub fn md5Init() Md5`

**Parameters** — none.

**Returns** — an `Md5` ready for `md5Update`.

**Errors** — none.

**Example**
```zig
var s = std_crypto.md5Init();
```

**Gotchas** — a value type; safe to keep on the stack.

#### `md5Update`

**Purpose** — feeds a chunk into the MD5 state.

**When to use** — once per chunk; any number of calls and chunk sizes.

**Signature** — `pub fn md5Update(s: *Md5, data: []const u8) void`

**Parameters**
- `s` — the state to advance.
- `data` — the bytes to absorb.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_crypto.md5Update(&s, msg);
```

**Gotchas** — chunking-independent; a zero-length `data` is a no-op.

#### `md5Final`

**Purpose** — finishes the hash and writes the 16-byte digest into `out`.

**When to use** — once, after the last `md5Update`.

**Signature** — `pub fn md5Final(s: *Md5, out: *[16]u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — the 16-byte destination.

**Returns** — nothing; the digest is written through `out`.

**Errors** — none.

**Example**
```zig
var digest: [16]u8 = undefined;
std_crypto.md5Final(&s, &digest);
```

**Gotchas** — do not call `md5Update` afterwards. MD5 emits little-endian
words, unlike SHA-1/SHA-256.

#### `crc32Init`

**Purpose** — returns the initial CRC-32 state (`0xFFFFFFFF`).

**When to use** — once at the start of a CRC-32.

**Signature** — `pub fn crc32Init() u32`

**Parameters** — none.

**Returns** — `0xFFFFFFFF`.

**Errors** — none.

**Example**
```zig
var crc = std_crypto.crc32Init();
```

**Gotchas** — CRC-32 state is a plain `u32`, not a struct; the Init/Update/Final
calls thread it through their return values.

#### `crc32Update`

**Purpose** — folds a chunk into a CRC-32 state.

**When to use** — once per chunk; any number of calls and chunk sizes.

**Signature** — `pub fn crc32Update(state: u32, data: []const u8) u32`

**Parameters**
- `state` — the running state (start from `crc32Init()`).
- `data` — the bytes to fold in.

**Returns** — the updated state.

**Errors** — none.

**Example**
```zig
var crc = std_crypto.crc32Init();
crc = std_crypto.crc32Update(crc, chunk_a);
crc = std_crypto.crc32Update(crc, chunk_b);
```

**Gotchas** — reflected IEEE 802.3 polynomial (`0xEDB88320`). The state is not
final until `crc32Final`.

#### `crc32Final`

**Purpose** — finalizes a CRC-32 state into the digest value.

**When to use** — once, after the last `crc32Update`.

**Signature** — `pub fn crc32Final(state: u32) u32`

**Parameters**
- `state` — the running state.

**Returns** — the finished CRC-32 (the state XOR `0xFFFFFFFF`).

**Errors** — none.

**Example**
```zig
const crc = std_crypto.crc32Final(std_crypto.crc32Update(std_crypto.crc32Init(), msg));
```

**Gotchas** — returns a `u32`, not bytes; format it yourself (e.g. with
`std_hex`). Do not continue updating after finalizing.

### `std_parse`

#### `parseInt`

**Purpose** — parses a decimal string as an `i32`.

**When to use** — to read a signed 32-bit integer from text.

**Signature** — `pub fn parseInt(s: []const u8) ?i32`

**Parameters**
- `s` — the text: an optional leading `-` followed by one or more digits.

**Returns** — `?i32`: the value, or `null` on a malformed string or overflow
(including `-2147483648`, which is accepted, and anything outside the `i32`
range, which is not).

**Errors** — none; failure is the `null` optional.

**Example**
```zig
if (std_parse.parseInt("-1234")) |n| {
    std.io.printInt(n);
}
```

**Gotchas** — rejects whitespace, `'+'`, underscores, and any trailing
character. Overflow is detected in `u64` before narrowing, so it returns `null`
instead of trapping.

#### `parseUint`

**Purpose** — parses a decimal string as a `u32`.

**When to use** — to read an unsigned 32-bit integer from text.

**Signature** — `pub fn parseUint(s: []const u8) ?u32`

**Parameters**
- `s` — the text: one or more digits.

**Returns** — `?u32`: the value, or `null` on a malformed string or overflow
(above `4294967295`).

**Errors** — none; failure is the `null` optional.

**Example**
```zig
if (std_parse.parseUint("4294967295")) |n| {
    std.io.printInt(@intCast(i32, n));
}
```

**Gotchas** — no sign is accepted, including `+`. Whitespace and underscores are
rejected.

#### `parseInt64`

**Purpose** — parses a decimal string as an `i64`.

**When to use** — to read a signed 64-bit integer from text.

**Signature** — `pub fn parseInt64(s: []const u8) ?i64`

**Parameters**
- `s` — the text: an optional leading `-` followed by one or more digits.

**Returns** — `?i64`: the value, or `null` on a malformed string or overflow
(including `-9223372036854775808`, which is accepted).

**Errors** — none; failure is the `null` optional.

**Example**
```zig
if (std_parse.parseInt64("-9223372036854775808")) |n| {
    _ = n;
}
```

**Gotchas** — the negative minimum is handled by two's-complement negation, so
it is accepted; one step below it is `null`.

#### `parseUint64`

**Purpose** — parses a decimal string as a `u64`.

**When to use** — to read an unsigned 64-bit integer from text.

**Signature** — `pub fn parseUint64(s: []const u8) ?u64`

**Parameters**
- `s` — the text: one or more digits.

**Returns** — `?u64`: the value, or `null` on a malformed string or overflow
(above `18446744073709551615`).

**Errors** — none; failure is the `null` optional.

**Example**
```zig
if (std_parse.parseUint64("18446744073709551615")) |n| {
    _ = n;
}
```

**Gotchas** — no sign is accepted. Whitespace and underscores are rejected.

#### `parseFloat`

**Purpose** — parses a decimal string as an `f64` in fixed-point form.

**When to use** — to read a floating-point number from text.

**Signature** — `pub fn parseFloat(s: []const u8) ?f64`

**Parameters**
- `s` — the text: an optional leading `-`, digits, an optional `.` and more
  digits. At least one digit (integer or fractional) is required.

**Returns** — `?f64`: the value, or `null` on a malformed string or when the
result overflows to infinity.

**Errors** — none; failure is the `null` optional.

**Example**
```zig
if (std_parse.parseFloat("-3.5")) |x| {
    _ = x;
}
```

**Gotchas** — no exponent notation, no `'+'`, no whitespace, no underscores, and
no trailing characters (the whole string must be consumed). `.5` and `5.` are
accepted; `.` alone is `null`. Overflow to `+/-inf` returns `null`.

#### `itoa`

**Purpose** — formats an `i32` as decimal text at the end of `buf`.

**When to use** — to turn a signed 32-bit integer into text without allocating.

**Signature** — `pub fn itoa(buf: []u8, v: i32) []u8`

**Parameters**
- `buf` — the destination; digits are written backwards from its end.
- `v` — the value, including `i32` minimum.

**Returns** — a `[]u8` pointing into `buf`, holding the rendered digits
(including a leading `-` when negative).

**Errors** — none.

**Example**
```zig
var buf: [16]u8 = undefined;
const s = std_parse.itoa(buf[0..], -1234);
std.io.write(s);
```

**Gotchas** — there is no size guard; an undersized `buf` traps. Size it at
least 12 bytes for `i32` (sign plus 10 digits). The result is a view into `buf`,
not a new allocation.

#### `utoa`

**Purpose** — formats a `u32` as decimal text at the end of `buf`.

**When to use** — to turn an unsigned 32-bit integer into text without
allocating.

**Signature** — `pub fn utoa(buf: []u8, v: u32) []u8`

**Parameters**
- `buf` — the destination; digits are written backwards from its end.
- `v` — the value.

**Returns** — a `[]u8` pointing into `buf`, holding the rendered digits.

**Errors** — none.

**Example**
```zig
var buf: [16]u8 = undefined;
const s = std_parse.utoa(buf[0..], 4294967295);
```

**Gotchas** — no size guard; size `buf` at least 11 bytes for `u32`.

#### `itoa64`

**Purpose** — formats an `i64` as decimal text at the end of `buf`.

**When to use** — to turn a signed 64-bit integer into text without allocating.

**Signature** — `pub fn itoa64(buf: []u8, v: i64) []u8`

**Parameters**
- `buf` — the destination; digits are written backwards from its end.
- `v` — the value, including `i64` minimum.

**Returns** — a `[]u8` pointing into `buf`, holding the rendered digits.

**Errors** — none.

**Example**
```zig
var buf: [24]u8 = undefined;
const s = std_parse.itoa64(buf[0..], -9223372036854775808);
```

**Gotchas** — no size guard; size `buf` at least 21 bytes for `i64`. The minimum
is rendered correctly.

#### `utoa64`

**Purpose** — formats a `u64` as decimal text at the end of `buf`.

**When to use** — to turn an unsigned 64-bit integer into text without
allocating.

**Signature** — `pub fn utoa64(buf: []u8, v: u64) []u8`

**Parameters**
- `buf` — the destination; digits are written backwards from its end.
- `v` — the value.

**Returns** — a `[]u8` pointing into `buf`, holding the rendered digits.

**Errors** — none.

**Example**
```zig
var buf: [24]u8 = undefined;
const s = std_parse.utoa64(buf[0..], 18446744073709551615);
```

**Gotchas** — no size guard; size `buf` at least 21 bytes for `u64`.

#### `ftoa`

**Purpose** — formats an `f64` in fixed-point notation at the end of `buf`, with
round-half-up to `precision` fraction digits.

**When to use** — to render a floating-point number without exponent notation or
allocation.

**Signature** — `pub fn ftoa(buf: []u8, v: f64, precision: u8) []u8`

**Parameters**
- `buf` — the destination; must hold sign + integer digits + optional `.` +
  `precision`.
- `v` — the value. Non-finite values render as text: `"nan"`, `"inf"`,
  `"-inf"`.
- `precision` — fraction digits, clamped to `17`.

**Returns** — a `[]u8` pointing into `buf`, holding the rendered text, or
`buf[0..0]` (nothing written) when `buf` is too small or the value cannot be
represented in the fixed-point temps.

**Errors** — none; the empty slice is the short-buffer signal.

**Example**
```zig
var buf: [64]u8 = undefined;
const s = std_parse.ftoa(buf[0..], 3.14159, 2);
std.io.write(s);
```

**Gotchas** — no exponent notation. Round-half-up, not round-to-even. Size `buf`
at least 328 bytes to cover every finite `f64`; a shorter buffer can return
`buf[0..0]` for large values. Non-finite inputs always terminate (never hang or
trap). Avoids any `f64 -> int` conversion, so it is portable to the pinned
target.

## See also

- `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_parse` — the modules
  in this doc.
- [`text.md`](text.md) — `std.buf`, the growable byte buffer that pairs with
  these encoders.
- [`memory.md`](memory.md) — the `std.arena` model for the allocating codecs.
- [`collections.md`](collections.md) — `std_rle`, the L4 byte codec alongside
  these L5 codecs.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
