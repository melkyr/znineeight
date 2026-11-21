// packhash.zig -- incremental SHA-1 over a git pack with a 20-byte tail window.
//
// A streamed pack ends with a 20-byte SHA-1 trailer that must not be hashed.
// `packHashFeed` therefore keeps only the last 20 bytes of the stream seen so
// far in `tail` and hashes every earlier byte, batching the updates through
// `pending` instead of calling sha1Update once per input byte.
//
// Tail invariant: while `tail_len < 20` the valid bytes are `tail[0..tail_len]`
// and `tail_pos` is 0.  Once full, the valid bytes form the ring starting at
// `tail_pos`; `packHashFeed` normally leaves `tail_pos == 0` with the bytes in
// stream order.  `pending` is always flushed in order, and `packHashFinal`
// flushes it but never the trailer.
//
// Z98 subset only: no generics, no pointer captures, exhaustive switch, strict
// integer casts.

const crypto = @import("std_crypto.zig");

const PENDING_SIZE: usize = 4096;
const TAIL_SIZE: usize = 20;

pub const PackHash = struct {
    hasher: crypto.Sha1,
    pending: [PENDING_SIZE]u8,
    pending_len: usize,
    tail: [TAIL_SIZE]u8,
    tail_len: usize,
    tail_pos: usize,
};

pub fn packHashInit() PackHash {
    var ph: PackHash = undefined;
    ph.hasher = crypto.sha1Init();
    ph.pending_len = 0;
    ph.tail_len = 0;
    ph.tail_pos = 0;
    return ph;
}

fn flushPending(ph: *PackHash) void {
    if (ph.pending_len != 0) {
        crypto.sha1Update(&ph.hasher, ph.pending[0..ph.pending_len]);
        ph.pending_len = 0;
    }
}

// Feed bytes that are known to be before the trailer.  Small inputs are copied
// into `pending`; once `pending` is empty and the remainder is large enough it
// goes straight to sha1Update.
fn feedHashed(ph: *PackHash, data: []const u8) void {
    var off: usize = 0;
    while (off < data.len) {
        if (ph.pending_len == 0 and data.len - off >= ph.pending.len) {
            crypto.sha1Update(&ph.hasher, data[off..]);
            return;
        }
        var space: usize = ph.pending.len - ph.pending_len;
        var take: usize = data.len - off;
        if (take > space) take = space;
        var i: usize = 0;
        while (i < take) : (i += 1) ph.pending[ph.pending_len + i] = data[off + i];
        ph.pending_len += take;
        off += take;
        if (ph.pending_len == ph.pending.len) flushPending(ph);
    }
}

pub fn packHashFeed(ph: *PackHash, data: []const u8) void {
    var off: usize = 0;

    if (ph.tail_len < TAIL_SIZE) {
        var need: usize = TAIL_SIZE - ph.tail_len;
        var take: usize = data.len;
        if (take > need) take = need;
        var i: usize = 0;
        while (i < take) : (i += 1) ph.tail[ph.tail_len + i] = data[i];
        ph.tail_len += take;
        ph.tail_pos = 0;
        off = take;
        if (off >= data.len) return;
    }

    const rest = data[off..];
    const n = rest.len;

    if (n < TAIL_SIZE) {
        var old: [TAIL_SIZE]u8 = undefined;
        var i: usize = 0;
        while (i < n) : (i += 1) old[i] = ph.tail[(ph.tail_pos + i) % TAIL_SIZE];
        feedHashed(ph, old[0..n]);

        var nt: [TAIL_SIZE]u8 = undefined;
        var j: usize = 0;
        while (j < TAIL_SIZE - n) : (j += 1) {
            nt[j] = ph.tail[(ph.tail_pos + n + j) % TAIL_SIZE];
        }
        i = 0;
        while (i < n) : (i += 1) nt[TAIL_SIZE - n + i] = rest[i];
        i = 0;
        while (i < TAIL_SIZE) : (i += 1) ph.tail[i] = nt[i];
        ph.tail_pos = 0;
    } else {
        var old: [TAIL_SIZE]u8 = undefined;
        var i: usize = 0;
        while (i < TAIL_SIZE) : (i += 1) old[i] = ph.tail[(ph.tail_pos + i) % TAIL_SIZE];
        feedHashed(ph, old[0..TAIL_SIZE]);
        feedHashed(ph, rest[0 .. n - TAIL_SIZE]);

        i = 0;
        while (i < TAIL_SIZE) : (i += 1) ph.tail[i] = rest[n - TAIL_SIZE + i];
        ph.tail_pos = 0;
    }
}

pub fn packHashFinal(ph: *PackHash, digest: *[20]u8) bool {
    flushPending(ph);
    crypto.sha1Final(&ph.hasher, digest);
    return ph.tail_len == TAIL_SIZE;
}
