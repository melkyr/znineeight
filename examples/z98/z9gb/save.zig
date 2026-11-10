// save.zig — battery persistence for z9gb.
//
// `.sav` is the raw cart-RAM prefix. `.rtc` is the 32-byte Z98RTC1 header:
//   0..7   "Z98RTC1\0"
//   8      version = 1
//   9      seconds
//   10     minutes
//   11     hours
//   12     days low
//   13     days high (bit 0)
//   14     flags: bit0 halt, bit1 day carry
//   15     reserved zero
//   16..23 host timestamp anchor (u64 LE unix seconds)
//   24..27 CRC32 of bytes 0..23 (LE)
//   28..31 reserved zero
//
// Writes use the Win9x-safe backup dance (tmp, .bak, MoveFileA) through
// std_file's whitelisted DeleteFileA/MoveFileA bindings; there is no CopyFileA
// or MoveFileExA use. A failed write restores the previous file.

const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("cart.zig");
const emumod = @import("emu.zig");

const PATH_MAX: usize = 512;
const RTC_BYTES: usize = 32;
const RTC_MAGIC: [8]u8 = [8]u8{ 'Z', '9', '8', 'R', 'T', 'C', '1', 0 };

const RtcImage = struct {
    sec: u8,
    min: u8,
    hour: u8,
    day_lo: u8,
    day_hi: u8,
    halt: bool,
    carry: bool,
    anchor: i64,
};

fn copySlice(out: []u8, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) : (i += 1) out[i] = data[i];
}

fn sameSlice(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn appendSuffix(path: []const u8, suffix: []const u8, out: []u8) usize {
    if (path.len > out.len) return 0;
    if (suffix.len > out.len - path.len) return 0;
    copySlice(out, path);
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) out[path.len + i] = suffix[i];
    return path.len + suffix.len;
}

// Replace the final extension (in the last path component) with `ext`. `ext`
// includes the dot. Returns 0 if the result does not fit.
pub fn deriveSavePath(rom: []const u8, ext: []const u8, out: []u8) usize {
    var base_end: usize = rom.len;
    var dot: usize = 0;
    var has_dot: bool = false;
    var i: usize = 0;
    while (i < rom.len) : (i += 1) {
        const c: u8 = rom[i];
        if (c == '/' or c == '\\') {
            has_dot = false;
        } else if (c == '.') {
            has_dot = true;
            dot = i;
        }
    }
    if (has_dot) base_end = dot;
    if (base_end > out.len) return 0;
    if (ext.len > out.len - base_end) return 0;
    i = 0;
    while (i < base_end) : (i += 1) out[i] = rom[i];
    i = 0;
    while (i < ext.len) : (i += 1) out[base_end + i] = ext[i];
    return base_end + ext.len;
}

fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        crc = crc ^ @intCast(u32, data[i]);
        var bit: u8 = 0;
        while (bit < 8) : (bit += 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
        }
    }
    return ~crc;
}

fn putLe32(buf: []u8, off: usize, value: u32) void {
    buf[off] = @intCast(u8, value & 0xFF);
    buf[off + 1] = @intCast(u8, (value >> 8) & 0xFF);
    buf[off + 2] = @intCast(u8, (value >> 16) & 0xFF);
    buf[off + 3] = @intCast(u8, (value >> 24) & 0xFF);
}

fn getLe32(buf: []const u8, off: usize) u32 {
    var v: u32 = @intCast(u32, buf[off]);
    v = v | (@intCast(u32, buf[off + 1]) << 8);
    v = v | (@intCast(u32, buf[off + 2]) << 16);
    v = v | (@intCast(u32, buf[off + 3]) << 24);
    return v;
}

fn putLe64(buf: []u8, off: usize, value: i64) void {
    var u: u64 = 0;
    if (value > 0) u = @intCast(u64, value);
    buf[off] = @intCast(u8, u & 0xFF);
    buf[off + 1] = @intCast(u8, (u >> 8) & 0xFF);
    buf[off + 2] = @intCast(u8, (u >> 16) & 0xFF);
    buf[off + 3] = @intCast(u8, (u >> 24) & 0xFF);
    buf[off + 4] = @intCast(u8, (u >> 32) & 0xFF);
    buf[off + 5] = @intCast(u8, (u >> 40) & 0xFF);
    buf[off + 6] = @intCast(u8, (u >> 48) & 0xFF);
    buf[off + 7] = @intCast(u8, (u >> 56) & 0xFF);
}

fn getLe64(buf: []const u8, off: usize) u64 {
    var v: u64 = @intCast(u64, buf[off]);
    v = v | (@intCast(u64, buf[off + 1]) << 8);
    v = v | (@intCast(u64, buf[off + 2]) << 16);
    v = v | (@intCast(u64, buf[off + 3]) << 24);
    v = v | (@intCast(u64, buf[off + 4]) << 32);
    v = v | (@intCast(u64, buf[off + 5]) << 40);
    v = v | (@intCast(u64, buf[off + 6]) << 48);
    v = v | (@intCast(u64, buf[off + 7]) << 56);
    return v;
}

fn buildRtcHeader(c: *cartmod.Cart, out: []u8) void {
    var i: usize = 0;
    while (i < RTC_BYTES) : (i += 1) out[i] = 0;
    cartmod.rtcSync(c);
    copySlice(out[0..8], RTC_MAGIC[0..]);
    out[8] = 1;
    out[9] = c.rtc.sec;
    out[10] = c.rtc.min;
    out[11] = c.rtc.hour;
    out[12] = c.rtc.day_lo;
    out[13] = c.rtc.day_hi & 0x01;
    var flags: u8 = 0;
    if (c.rtc.halt) flags |= 0x01;
    if (c.rtc.day_carry) flags |= 0x02;
    out[14] = flags;
    out[15] = 0;
    putLe64(out, 16, c.rtc.anchor);
    putLe32(out, 24, crc32(out[0..24]));
    out[28] = 0;
    out[29] = 0;
    out[30] = 0;
    out[31] = 0;
}

fn parseRtcHeader(buf: []const u8) emumod.EmuError!RtcImage {
    if (buf.len != RTC_BYTES) return error.SaveCorrupt;
    if (!sameSlice(buf[0..8], RTC_MAGIC[0..])) return error.SaveCorrupt;
    if (buf[8] != 1) return error.SaveCorrupt;
    if (buf[15] != 0) return error.SaveCorrupt;
    if (buf[28] != 0 or buf[29] != 0 or buf[30] != 0 or buf[31] != 0) return error.SaveCorrupt;
    if (getLe32(buf, 24) != crc32(buf[0..24])) return error.SaveCorrupt;
    if (buf[9] >= 60 or buf[10] >= 60 or buf[11] >= 24) return error.SaveCorrupt;
    if ((buf[13] & 0xFE) != 0) return error.SaveCorrupt;
    if ((buf[14] & 0xFC) != 0) return error.SaveCorrupt;
    const raw_anchor: u64 = getLe64(buf, 16);
    if (raw_anchor > 9223372036854775807) return error.SaveCorrupt;
    return RtcImage{
        .sec = buf[9],
        .min = buf[10],
        .hour = buf[11],
        .day_lo = buf[12],
        .day_hi = buf[13] & 0x01,
        .halt = (buf[14] & 0x01) != 0,
        .carry = (buf[14] & 0x02) != 0,
        .anchor = @intCast(i64, raw_anchor),
    };
}

fn resolveSavPath(e: *emumod.Emu, path: []const u8, out: []u8) usize {
    if (e.save_len != 0 and sameSlice(path, e.save_path[0..e.save_len])) {
        if (path.len > out.len) return 0;
        copySlice(out, path);
        return path.len;
    }
    return deriveSavePath(path, ".sav", out);
}

fn writeAtomic(path: []const u8, data: []const u8) emumod.EmuError!void {
    var tmp_buf: [PATH_MAX]u8 = undefined;
    const tlen: usize = appendSuffix(path, ".tmp", tmp_buf[0..]);
    if (tlen == 0) return error.Io;
    const tmp_path: []const u8 = tmp_buf[0..tlen];
    filemod.writeAll(tmp_path, data) catch {
        filemod.remove(tmp_path) catch {};
        return error.Io;
    };

    var bak_buf: [PATH_MAX]u8 = undefined;
    const blen: usize = appendSuffix(path, ".bak", bak_buf[0..]);
    if (blen == 0) {
        filemod.remove(tmp_path) catch {};
        return error.Io;
    }
    const bak_path: []const u8 = bak_buf[0..blen];
    filemod.remove(bak_path) catch {};

    if (filemod.exists(path)) {
        filemod.rename(path, bak_path) catch {
            filemod.remove(tmp_path) catch {};
            return error.Io;
        };
        filemod.rename(tmp_path, path) catch {
            filemod.rename(bak_path, path) catch {};
            filemod.remove(tmp_path) catch {};
            return error.Io;
        };
        filemod.remove(bak_path) catch {};
    } else {
        filemod.rename(tmp_path, path) catch {
            filemod.remove(tmp_path) catch {};
            return error.Io;
        };
    }
}

fn readExact(path: []const u8, out: []u8) emumod.EmuError!void {
    var arena_buf: [1]u8 = undefined;
    var arena = std.arena.init(arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch return error.Io;
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        return error.Io;
    };
    if (sz != @intCast(i64, out.len)) {
        filemod.close(&f);
        return error.SaveCorrupt;
    }
    var got: usize = 0;
    while (got < out.len) {
        const r = filemod.read(&f, out[got..out.len]) catch {
            filemod.close(&f);
            return error.Io;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    if (got != out.len) return error.Io;
}

pub fn saveBattery(e: *emumod.Emu, rom_path: []const u8) emumod.EmuError!void {
    var sav_buf: [PATH_MAX]u8 = undefined;
    const slen: usize = resolveSavPath(e, rom_path, sav_buf[0..]);
    if (slen == 0) return error.Io;
    const sav_path: []const u8 = sav_buf[0..slen];

    if (e.cart.ram_size != 0) {
        const ram: []const u8 = cartmod.cartSaveRam(&e.cart);
        try writeAtomic(sav_path, ram);
    }

    if (e.cart.has_rtc) {
        var rtc_buf: [PATH_MAX]u8 = undefined;
        const rlen: usize = deriveSavePath(sav_path, ".rtc", rtc_buf[0..]);
        if (rlen == 0) return error.Io;
        var hdr: [RTC_BYTES]u8 = undefined;
        buildRtcHeader(&e.cart, hdr[0..]);
        try writeAtomic(rtc_buf[0..rlen], hdr[0..]);
    }
}

pub fn loadBattery(e: *emumod.Emu, rom_path: []const u8) emumod.EmuError!void {
    var sav_buf: [PATH_MAX]u8 = undefined;
    const slen: usize = resolveSavPath(e, rom_path, sav_buf[0..]);
    if (slen == 0) return error.Io;
    const sav_path: []const u8 = sav_buf[0..slen];

    var image: RtcImage = undefined;
    if (e.cart.has_rtc) {
        var rtc_buf: [PATH_MAX]u8 = undefined;
        const rlen: usize = deriveSavePath(sav_path, ".rtc", rtc_buf[0..]);
        if (rlen == 0) return error.Io;
        var hdr: [RTC_BYTES]u8 = undefined;
        try readExact(rtc_buf[0..rlen], hdr[0..]);
        image = try parseRtcHeader(hdr[0..]);
    }

    const ram_size: usize = e.cart.ram_size;
    if (ram_size != 0) {
        var arena_buf: [1]u8 = undefined;
        var arena = std.arena.init(arena_buf[0..]);
        var f = filemod.open(&arena, sav_path, filemod.Mode.Read) catch return error.Io;
        const sz = filemod.size(&f) catch {
            filemod.close(&f);
            return error.Io;
        };
        if (sz != @intCast(i64, ram_size)) {
            filemod.close(&f);
            return error.SaveCorrupt;
        }
        var got: usize = 0;
        while (got < ram_size) {
            const r = filemod.read(&f, e.cart.ram[got..ram_size]) catch {
                filemod.close(&f);
                return error.Io;
            };
            if (r == 0) break;
            got += r;
        }
        filemod.close(&f);
        if (got != ram_size) return error.Io;
    }

    if (e.cart.has_rtc) {
        cartmod.rtcLoadState(&e.cart, image.sec, image.min, image.hour, image.day_lo, image.day_hi, image.halt, image.carry, image.anchor);
    }
}
