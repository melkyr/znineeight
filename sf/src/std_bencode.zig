// std_bencode.zig — Z98 std lib: BitTorrent bencode decode + dictValueSpan.
//
// Contract (spec 2026-10-08 §4.2): alloc lists/dicts/Value arrays from the
// caller's arena only | errors InvalidToken, Overflow, TooDeep, TooLarge,
// DuplicateKey, OutOfMemory. Imports L1 (`std_arena`) and L5 (`std_parse`).
//
//   decode(arena, bytes) BencodeError!Value   complete top-level value; the
//       whole input must be consumed (a trailing byte is InvalidToken).
//   dictValueSpan(bytes, key) BencodeError!?Span   raw byte span of the
//       top-level dict entry `key`, WITHOUT decoding it and WITHOUT
//       allocating. `null` if the key is absent. Used to capture the exact
//       `info` bytes for info_hash.
//
// Limits: nesting depth 100; 1024 keys/dict; 32 MB/value; 64 MB total.
// Rejects `i04e`, `i-0e`, leading zeros, i64 overflow, duplicate keys, and a
// string length exceeding the remaining input.
//
// The integer tag is `int_val`, not `int`: Z98 emits union tags verbatim as C
// members and `int` is a C keyword (see spec §4.2 comment).

const std = @import("std");
const parse = @import("std_parse.zig");

pub const Value = union(enum) {
    int_val: i64,
    bytes: []const u8,
    list: []Value,
    dict: []Entry,
};
pub const Entry = struct { key: []const u8, value: Value };
pub const Span = struct { start: u32, end: u32 };

pub const BencodeError = error{
    InvalidToken,
    Overflow,
    TooDeep,
    TooLarge,
    DuplicateKey,
    OutOfMemory,
};

const MAX_DEPTH: usize = 100;
const MAX_KEYS: usize = 1024;
const MAX_VALUE_BYTES: usize = 33554432;
const MAX_TOTAL_BYTES: usize = 67108864;

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn allocValues(ar: *std.arena.Arena, n: usize) BencodeError![]Value {
    const p = std.arena.alloc(ar, n * @sizeOf(Value)) catch return error.OutOfMemory;
    return @ptrCast([*]Value, p)[0..n];
}

fn allocEntries(ar: *std.arena.Arena, n: usize) BencodeError![]Entry {
    const p = std.arena.alloc(ar, n * @sizeOf(Entry)) catch return error.OutOfMemory;
    return @ptrCast([*]Entry, p)[0..n];
}

// Read an integer `i<digits>e`; advance *pos past the closing 'e'.
fn readInt(bytes: []const u8, pos: *usize) BencodeError!i64 {
    var i: usize = pos.*;
    if (i >= bytes.len or bytes[i] != 'i') return error.InvalidToken;
    i += 1;
    const num_start: usize = i;
    var neg: bool = false;
    if (i < bytes.len and bytes[i] == '-') {
        neg = true;
        i += 1;
    }
    const digits_start: usize = i;
    while (i < bytes.len and isDigit(bytes[i])) : (i += 1) {}
    const digits_end: usize = i;
    if (digits_end == digits_start) return error.InvalidToken;
    if (i >= bytes.len or bytes[i] != 'e') return error.InvalidToken;
    const dlen: usize = digits_end - digits_start;
    if (dlen > 1 and bytes[digits_start] == '0') return error.InvalidToken;
    if (neg and dlen == 1 and bytes[digits_start] == '0') return error.InvalidToken;
    const text: []const u8 = bytes[num_start..digits_end];
    var parsed = parse.parseInt64(text);
    if (parsed) |val| {
        pos.* = i + 1;
        return val;
    } else {
        return error.Overflow;
    }
}

// Read a byte string `<len>:<data>`; advance *pos past the data, return data.
fn readString(bytes: []const u8, pos: *usize) BencodeError![]const u8 {
    var i: usize = pos.*;
    if (i >= bytes.len) return error.InvalidToken;
    const digits_start: usize = i;
    while (i < bytes.len and isDigit(bytes[i])) : (i += 1) {}
    if (i == digits_start) return error.InvalidToken;
    if (i >= bytes.len or bytes[i] != ':') return error.InvalidToken;
    const dlen: usize = i - digits_start;
    if (dlen > 1 and bytes[digits_start] == '0') return error.InvalidToken;
    const digits: []const u8 = bytes[digits_start..i];
    var maybe_len = parse.parseUint64(digits);
    var vlen_u64: u64 = 0;
    var have_len: bool = false;
    if (maybe_len) |x| {
        vlen_u64 = x;
        have_len = true;
    }
    if (!have_len) return error.TooLarge;
    if (vlen_u64 > @intCast(u64, MAX_VALUE_BYTES)) return error.TooLarge;
    const vlen: usize = @intCast(usize, vlen_u64);
    const data_start: usize = i + 1;
    if (vlen > bytes.len - data_start) return error.InvalidToken;
    const data_end: usize = data_start + vlen;
    const out: []const u8 = bytes[data_start..data_end];
    pos.* = data_end;
    return out;
}

// Advance *pos past one value without decoding or allocating.
fn skipValue(bytes: []const u8, pos: *usize, depth: usize) BencodeError!void {
    if (pos.* >= bytes.len) return error.InvalidToken;
    const c: u8 = bytes[pos.*];
    if (c == 'i') {
        _ = try readInt(bytes, pos);
        return;
    } else if (isDigit(c)) {
        _ = try readString(bytes, pos);
        return;
    } else if (c == 'l') {
        if (depth + 1 > MAX_DEPTH) return error.TooDeep;
        pos.* += 1;
        while (true) {
            if (pos.* >= bytes.len) return error.InvalidToken;
            if (bytes[pos.*] == 'e') {
                pos.* += 1;
                return;
            }
            try skipValue(bytes, pos, depth + 1);
        }
    } else if (c == 'd') {
        if (depth + 1 > MAX_DEPTH) return error.TooDeep;
        pos.* += 1;
        var keys: usize = 0;
        while (true) {
            if (pos.* >= bytes.len) return error.InvalidToken;
            if (bytes[pos.*] == 'e') {
                pos.* += 1;
                return;
            }
            _ = try readString(bytes, pos);
            keys += 1;
            if (keys > MAX_KEYS) return error.TooLarge;
            try skipValue(bytes, pos, depth + 1);
        }
    } else {
        return error.InvalidToken;
    }
}

fn decodeValue(ar: *std.arena.Arena, bytes: []const u8, pos: *usize, depth: usize) BencodeError!Value {
    const start: usize = pos.*;
    if (start >= bytes.len) return error.InvalidToken;
    const c: u8 = bytes[start];
    var result: Value = undefined;
    if (c == 'i') {
        const v = try readInt(bytes, pos);
        result = Value{ .int_val = v };
    } else if (isDigit(c)) {
        const s = try readString(bytes, pos);
        result = Value{ .bytes = s };
    } else if (c == 'l') {
        if (depth + 1 > MAX_DEPTH) return error.TooDeep;
        pos.* += 1;
        const save: usize = pos.*;
        var count: usize = 0;
        while (true) {
            if (pos.* >= bytes.len) return error.InvalidToken;
            if (bytes[pos.*] == 'e') break;
            try skipValue(bytes, pos, depth + 1);
            count += 1;
        }
        pos.* = save;
        const items = try allocValues(ar, count);
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            items[idx] = try decodeValue(ar, bytes, pos, depth + 1);
        }
        if (pos.* >= bytes.len or bytes[pos.*] != 'e') return error.InvalidToken;
        pos.* += 1;
        result = Value{ .list = items };
    } else if (c == 'd') {
        if (depth + 1 > MAX_DEPTH) return error.TooDeep;
        pos.* += 1;
        const save: usize = pos.*;
        var count: usize = 0;
        while (true) {
            if (pos.* >= bytes.len) return error.InvalidToken;
            if (bytes[pos.*] == 'e') break;
            _ = try readString(bytes, pos);
            count += 1;
            if (count > MAX_KEYS) return error.TooLarge;
            try skipValue(bytes, pos, depth + 1);
        }
        pos.* = save;
        const entries = try allocEntries(ar, count);
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            const k = try readString(bytes, pos);
            const val = try decodeValue(ar, bytes, pos, depth + 1);
            entries[idx] = Entry{ .key = k, .value = val };
        }
        var a: usize = 0;
        while (a < count) : (a += 1) {
            var b: usize = a + 1;
            while (b < count) : (b += 1) {
                if (eqBytes(entries[a].key, entries[b].key)) return error.DuplicateKey;
            }
        }
        if (pos.* >= bytes.len or bytes[pos.*] != 'e') return error.InvalidToken;
        pos.* += 1;
        result = Value{ .dict = entries };
    } else {
        return error.InvalidToken;
    }
    const end: usize = pos.*;
    if (end - start > MAX_VALUE_BYTES) return error.TooLarge;
    return result;
}

pub fn decode(arena: *std.arena.Arena, bytes: []const u8) BencodeError!Value {
    if (bytes.len > MAX_TOTAL_BYTES) return error.TooLarge;
    var pos: usize = 0;
    const v = try decodeValue(arena, bytes, &pos, 0);
    if (pos != bytes.len) return error.InvalidToken;
    return v;
}

pub fn dictValueSpan(bytes: []const u8, key: []const u8) BencodeError!?Span {
    if (bytes.len > @intCast(usize, 0xFFFFFFFF)) return error.TooLarge;
    var pos: usize = 0;
    if (pos >= bytes.len or bytes[pos] != 'd') return error.InvalidToken;
    pos += 1;
    while (true) {
        if (pos >= bytes.len) return error.InvalidToken;
        if (bytes[pos] == 'e') {
            pos += 1;
            return null;
        }
        const k = try readString(bytes, &pos);
        const vstart: usize = pos;
        try skipValue(bytes, &pos, 0);
        const vend: usize = pos;
        if (eqBytes(k, key)) {
            const s32: u32 = @intCast(u32, vstart);
            const e32: u32 = @intCast(u32, vend);
            return Span{ .start = s32, .end = e32 };
        }
    }
    return null;
}
