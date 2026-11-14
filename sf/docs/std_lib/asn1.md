# DER reader — `std_asn1`

| | |
|---|---|
| **Modules** | `std_asn1` |
| **Layers** | `L5` — byte-codec layer: streaming DER (ASN.1) TLV reader |
| **Import (by path)** | `const std_asn1 = @import("std_asn1.zig");` |
| **Consumes** | none |

`std_asn1` is not re-exported through `std`; import it by path.

## Module overview

`std_asn1` is a **pure**, **allocation-free** DER reader. It walks a caller-owned
byte slice and returns one tag-length-value (TLV) at a time. Nothing is copied:
`Tlv.data` and `Tlv.full` point into the input buffer, so the input must outlive
every `Tlv` and the reader. The reader holds only a slice and a cursor, so a
malformed input cannot allocate or leave hidden state.

The parser accepts **DER definite lengths only**. It rejects indefinite length
(`0x80`), non-minimal long-form lengths (a value below 128 written with length
octets), long-form lengths wider than four octets, a leading zero length octet,
truncated headers or bodies, high-tag-number forms that are not minimally
encoded or are narrower than 31, and malformed universal OID contents. All of
these return `error.Corrupt`; there is no other error. The reader is used by
[`std_x509`](x509.md) for certificate parsing and by callers that need to inspect
arbitrary DER without a schema.

The reader is a **streaming** API: `asn1ReadTlv` advances `r.pos` past the whole
TLV (header plus body), and `Tlv.full` is exactly the bytes consumed. To descend
into a constructed value, initialize a second reader over `Tlv.data`; the parent
reader is unaffected and continues after the constructed value.

## Quick start

Read a SEQUENCE, then the OID inside it.

```zig
const std_asn1 = @import("std_asn1.zig");

pub fn main() void {
    // DER: SEQUENCE { OID 1.2.840.113549.1.1.11 }
    var der: []const u8 = "\x30\x0b\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b";

    var r = std_asn1.asn1Init(der);
    const seq = std_asn1.asn1ReadTlv(&r) catch return;
    if (seq.cls != std_asn1.TagClass.universal or seq.tag != 16) return;

    var inner = std_asn1.asn1Init(seq.data);
    const oid = std_asn1.asn1ReadTlv(&inner) catch return;
    if (oid.cls != std_asn1.TagClass.universal or oid.tag != 6) return;

    // oid.data is a slice of `der`, not a copy.
}
```

## API

### `Asn1Error`

**Purpose** — the reader's only error set.

**Signature** — `pub const Asn1Error = error{Corrupt};`

**Errors** — `error.Corrupt` means the bytes are not acceptable DER under the
rules in the module overview.

### `TagClass`

**Purpose** — the two-bit ASN.1 class of a TLV.

**Signature** — `pub const TagClass = enum { universal, application, context, private };`

### `Tlv`

**Purpose** — one parsed tag-length-value.

**Signature** — `pub const Tlv = struct { cls: TagClass, constructed: bool, tag: u32, data: []const u8, full: []const u8 };`

**Fields**
- `cls` — tag class.
- `constructed` — the DER constructed bit.
- `tag` — tag number, including high-tag-number forms (`>= 31`).
- `data` — the value octets, a slice of the reader's input.
- `full` — the complete TLV (identifier, length, and value), a slice of the
  reader's input. Useful when a caller needs the exact signed/encoded bytes.

### `Asn1Reader`

**Purpose** — cursor over a DER buffer.

**Signature** — `pub const Asn1Reader = struct { data: []const u8, pos: usize };`

**Gotchas** — construct it with `asn1Init`; `pos` is a byte offset and is
advanced only by `asn1ReadTlv`. The struct stores no ownership; the input slice
must remain valid.

### `asn1Init`

**Purpose** — creates a reader positioned at the start of `data`.

**When to use** — before reading a top-level TLV or a constructed value's
contents (`asn1Init(seq.data)`).

**Signature** — `pub fn asn1Init(data: []const u8) Asn1Reader`

**Parameters**
- `data` — DER bytes to read. Not copied.

**Returns** — an `Asn1Reader` with `pos = 0`.

**Errors** — none.

**Example**
```zig
var r = std_asn1.asn1Init(der);
```

**Gotchas** — the input must outlive the `Tlv` values returned from this reader.

### `asn1Remaining`

**Purpose** — reports how many bytes are left after the cursor.

**When to use** — to test for trailing data (`asn1Remaining(&r) == 0`) or to
loop (`while (asn1Remaining(&r) != 0)`).

**Signature** — `pub fn asn1Remaining(r: *const Asn1Reader) usize`

**Parameters**
- `r` — reader to inspect; not mutated.

**Returns** — `r.data.len - r.pos`, clamped to `0` when `pos >= data.len`.

**Errors** — none.

**Example**
```zig
while (std_asn1.asn1Remaining(&r) != 0) {
    const t = std_asn1.asn1ReadTlv(&r) catch break;
    _ = t;
}
```

**Gotchas** — a non-zero remainder is not itself an error; callers that require
one exact TLV (as certificate parsing does) must reject leftovers explicitly.

### `asn1ReadTlv`

**Purpose** — reads the next TLV at the cursor and advances past it.

**When to use** — the only parsing primitive: walk a buffer, descend into
`Tlv.data` with a nested reader, or capture `Tlv.full` for exact byte
comparisons/signature input.

**Signature** — `pub fn asn1ReadTlv(r: *Asn1Reader) Asn1Error!Tlv`

**Parameters**
- `r` — cursor; mutated on every call, including failures.

**Returns** — the next `Tlv`. `cls`, `constructed`, `tag`, `data`, and `full`
are filled in; `data`/`full` alias the input buffer.

**Errors**
- `error.Corrupt` — empty/truncated input, malformed identifier or length,
  indefinite or non-minimal length, a length that runs past the buffer, an
  out-of-range high-tag-number form, or invalid universal OID contents.

**Example**
```zig
const t = try std_asn1.asn1ReadTlv(&r);
if (t.cls == std_asn1.TagClass.universal and t.tag == 16 and t.constructed) {
    var inner = std_asn1.asn1Init(t.data);
}
```

**Gotchas**
- Only definite lengths are accepted; BER indefinite-length values are rejected.
- Contents of non-OID primitives are opaque — `std_asn1` does not validate
  INTEGER, BOOLEAN, BIT STRING, or time semantics. `std_x509` layers those
  checks on top.
- On error the cursor may already have moved; do not continue reading after a
  failed `asn1ReadTlv`.

## See also

- [`std_x509`](x509.md) — certificate parsing, chain verification, trust store.
- [`codecs.md`](codecs.md) — base64/hex/UTF-8, number parsing, LZ4.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
