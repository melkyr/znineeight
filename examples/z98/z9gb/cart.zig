const std_time = @import("std_time.zig");

const ROM_CAP: usize = 8 * 1024 * 1024;
const RAM_CAP: usize = 131072;
const ROM_BANK: usize = 0x4000;
const RAM_BANK: usize = 0x2000;
const MIN_ROM: usize = 32768;
const RTC_CYCLE: i64 = 512 * 86400;

pub const Mbc = enum(u8) {
    none = 0,
    mbc1 = 1,
    mbc3 = 3,
    mbc5 = 5,
};

pub const CartError = error{ BadHeader, UnsupportedMbc, RomTooLarge, Io };

// MBC3 real-time clock. Counters are live; reads return `latched` copies.
// `anchor` is the last host timestamp observation and advances only when the
// clock is observed (latch/read/write/save), never per frame. `fixed` replaces
// the host wall clock with `fixed_unix` for deterministic headless runs.
pub const Rtc = struct {
    sec: u8,
    min: u8,
    hour: u8,
    day_lo: u8,
    day_hi: u8,
    day_carry: bool,
    halt: bool,
    latch_prev: u8,
    latched: [5]u8,
    anchor: i64,
    fixed: bool,
    fixed_unix: i64,
    started: bool,
};

pub const Cart = struct {
    rom: []const u8,
    ram: [RAM_CAP]u8,
    title: [16]u8,
    cgb: u8,
    mbc: Mbc,
    rom_size: usize,
    ram_size: usize,
    ram_enable: bool,
    rom_bank_lo: u8,
    bank_hi: u8,
    mode: u8,
    ram_bank: u8,
    has_rtc: bool,
    rtc: Rtc,
    rom0_off: usize,
    romx_off: usize,
    ram_off: usize,
};

pub fn cartInit(c: *Cart) void {
    c.rom = "";
    c.cgb = 0;
    c.mbc = .none;
    c.rom_size = 0;
    c.ram_size = 0;
    c.ram_enable = false;
    c.rom_bank_lo = 1;
    c.bank_hi = 0;
    c.mode = 0;
    c.ram_bank = 0;
    c.has_rtc = false;
    rtcInit(c);
    c.rom0_off = 0;
    c.romx_off = 0;
    c.ram_off = 0;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        c.title[i] = 0;
    }
}

fn rtcInit(c: *Cart) void {
    const r: *Rtc = &c.rtc;
    r.sec = 0;
    r.min = 0;
    r.hour = 0;
    r.day_lo = 0;
    r.day_hi = 0;
    r.day_carry = false;
    r.halt = false;
    r.latch_prev = 0xFF;
    r.anchor = 0;
    r.fixed = false;
    r.fixed_unix = 0;
    r.started = false;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        r.latched[i] = 0;
    }
}

fn romSizeFromCode(code: u8) CartError!usize {
    if (code == 0x00) return 32768;
    if (code == 0x01) return 65536;
    if (code == 0x02) return 131072;
    if (code == 0x03) return 262144;
    if (code == 0x04) return 524288;
    if (code == 0x05) return 1048576;
    if (code == 0x06) return 2097152;
    if (code == 0x07) return 4194304;
    if (code == 0x08) return 8388608;
    return error.BadHeader;
}

fn ramSizeFromCode(code: u8) CartError!usize {
    if (code == 0x00) return 0;
    if (code == 0x01) return 2048;
    if (code == 0x02) return 8192;
    if (code == 0x03) return 32768;
    if (code == 0x04) return 131072;
    if (code == 0x05) return 65536;
    return error.BadHeader;
}

fn mbcKnown(typ: u8) bool {
    if (typ == 0x00) return true;
    if (typ >= 0x01 and typ <= 0x03) return true;
    if (typ >= 0x0F and typ <= 0x13) return true;
    if (typ >= 0x19 and typ <= 0x1E) return true;
    return false;
}

fn mbcFromType(typ: u8) Mbc {
    if (typ == 0x00) return .none;
    if (typ >= 0x01 and typ <= 0x03) return .mbc1;
    if (typ >= 0x0F and typ <= 0x13) return .mbc3;
    if (typ >= 0x19 and typ <= 0x1E) return .mbc5;
    return .none;
}

fn romBankMask(c: *const Cart) u32 {
    const banks: usize = c.rom_size / ROM_BANK;
    if (banks == 0) return 0;
    var mask: u32 = @intCast(u32, banks - 1);
    if (mask > 0x1FF) mask = 0x1FF;
    return mask;
}

fn mbc1Recompute(c: *Cart) void {
    const mask: u32 = romBankMask(c);
    const hi: u32 = @intCast(u32, c.bank_hi);
    const lo: u32 = @intCast(u32, c.rom_bank_lo);
    const adjusted: u32 = if (lo == 0) 1 else lo;

    var romx_bank: u32 = ((hi << 5) | adjusted) & mask;
    c.romx_off = @intCast(usize, romx_bank) * ROM_BANK;

    if (c.mode != 0) {
        const rom0_bank: u32 = (hi << 5) & mask;
        c.rom0_off = @intCast(usize, rom0_bank) * ROM_BANK;
        c.ram_off = @intCast(usize, hi) * RAM_BANK;
    } else {
        c.rom0_off = 0;
        c.ram_off = 0;
    }
}

fn mbc3Recompute(c: *Cart) void {
    const mask: u32 = romBankMask(c);
    const lo: u32 = @intCast(u32, c.rom_bank_lo & 0x7F);
    const bank: u32 = if (lo == 0) 1 else lo;
    c.rom0_off = 0;
    c.romx_off = @intCast(usize, bank & mask) * ROM_BANK;
    c.ram_off = @intCast(usize, c.ram_bank & 0x0F) * RAM_BANK;
}

fn mbc5Recompute(c: *Cart) void {
    const mask: u32 = romBankMask(c);
    const lo: u32 = @intCast(u32, c.rom_bank_lo);
    const hi: u32 = @intCast(u32, c.bank_hi & 0x01);
    const bank: u32 = lo | (hi << 8);
    c.rom0_off = 0;
    c.romx_off = @intCast(usize, bank & mask) * ROM_BANK;
    c.ram_off = @intCast(usize, c.ram_bank & 0x0F) * RAM_BANK;
}

pub fn cartLoad(c: *Cart, bytes: []const u8) CartError!void {
    if (bytes.len > ROM_CAP) return error.RomTooLarge;
    if (bytes.len < MIN_ROM) return error.BadHeader;
    if (bytes.len < 0x150) return error.BadHeader;

    const rom_size = try romSizeFromCode(bytes[0x0148]);
    if (bytes.len < rom_size) return error.BadHeader;
    const ram_size = try ramSizeFromCode(bytes[0x0149]);
    if (!mbcKnown(bytes[0x0147])) return error.UnsupportedMbc;
    const mbc = mbcFromType(bytes[0x0147]);

    c.rom = bytes;
    c.cgb = bytes[0x0143];
    c.mbc = mbc;
    c.rom_size = rom_size;
    c.ram_size = ram_size;
    c.ram_enable = false;
    c.rom_bank_lo = 1;
    c.bank_hi = 0;
    c.mode = 0;
    c.ram_bank = 0;
    c.has_rtc = bytes[0x0147] == 0x0F or bytes[0x0147] == 0x10;

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        c.title[i] = bytes[0x0134 + i];
    }
    i = 0;
    while (i < RAM_CAP) : (i += 1) {
        c.ram[i] = 0;
    }
    rtcReset(c);

    switch (mbc) {
        .mbc1 => mbc1Recompute(c),
        .mbc3 => mbc3Recompute(c),
        .mbc5 => mbc5Recompute(c),
        else => {
            c.rom0_off = 0;
            c.romx_off = ROM_BANK;
            c.ram_off = 0;
        },
    }
}

fn rtcHostNow(c: *const Cart) i64 {
    if (c.rtc.fixed) return c.rtc.fixed_unix;
    return std_time.wallClockUnix();
}

fn rtcReset(c: *Cart) void {
    const r: *Rtc = &c.rtc;
    r.sec = 0;
    r.min = 0;
    r.hour = 0;
    r.day_lo = 0;
    r.day_hi = 0;
    r.day_carry = false;
    r.halt = false;
    r.latch_prev = 0xFF;
    r.anchor = rtcHostNow(c);
    r.started = true;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        r.latched[i] = 0;
    }
}

// Freeze the RTC host clock. The first call re-anchors the counters; later calls
// only move the frozen epoch so tests can advance time deterministically.
pub fn rtcSetFixed(c: *Cart, unix: i64) void {
    if (!c.rtc.fixed) {
        c.rtc.fixed = true;
        c.rtc.fixed_unix = unix;
        c.rtc.anchor = unix;
        c.rtc.started = true;
    } else {
        c.rtc.fixed_unix = unix;
    }
}

fn rtcAddSeconds(c: *Cart, elapsed: i64) void {
    const sec: i64 = @intCast(i64, c.rtc.sec);
    const min: i64 = @intCast(i64, c.rtc.min);
    const hour: i64 = @intCast(i64, c.rtc.hour);
    const day: i64 = (@intCast(i64, c.rtc.day_hi & 0x01) << 8) | @intCast(i64, c.rtc.day_lo);
    var total: i64 = sec + min * 60 + hour * 3600 + day * 86400 + elapsed;
    total = total % RTC_CYCLE;
    if (total < 0) total += RTC_CYCLE;
    const d: i64 = total / 86400;
    const rem: i64 = total % 86400;
    const rem2: i64 = rem % 3600;
    c.rtc.day_lo = @intCast(u8, d & 0xFF);
    c.rtc.day_hi = @intCast(u8, (d >> 8) & 0x01);
    c.rtc.hour = @intCast(u8, rem / 3600);
    c.rtc.min = @intCast(u8, rem2 / 60);
    c.rtc.sec = @intCast(u8, rem2 % 60);
}

// Add host-elapsed whole seconds and re-anchor. A halt freezes accumulation but
// still re-anchors, so the halted interval is discarded on resume.
fn rtcObserve(c: *Cart) void {
    const now: i64 = rtcHostNow(c);
    if (!c.rtc.started) {
        c.rtc.anchor = now;
        c.rtc.started = true;
        return;
    }
    if (c.rtc.halt) {
        c.rtc.anchor = now;
        return;
    }
    var elapsed: i64 = now - c.rtc.anchor;
    if (elapsed < 0) elapsed = 0;
    if (elapsed != 0) rtcAddSeconds(c, elapsed);
    c.rtc.anchor = now;
}

pub fn rtcSync(c: *Cart) void {
    rtcObserve(c);
}

pub fn rtcRelatch(c: *Cart) void {
    const r: *Rtc = &c.rtc;
    r.latched[0] = r.sec;
    r.latched[1] = r.min;
    r.latched[2] = r.hour;
    r.latched[3] = r.day_lo;
    var dh: u8 = r.day_hi & 0x01;
    if (r.halt) dh |= 0x40;
    if (r.day_carry) dh |= 0x80;
    r.latched[4] = dh;
}

pub fn rtcLatch(c: *Cart, value: u8) void {
    rtcObserve(c);
    if (c.rtc.latch_prev == 0x00 and value == 0x01) rtcRelatch(c);
    c.rtc.latch_prev = value;
}

pub fn rtcRead(c: *Cart, reg: u8) u8 {
    rtcObserve(c);
    if (reg > 4) return 0xFF;
    return c.rtc.latched[@intCast(usize, reg)];
}

pub fn rtcWrite(c: *Cart, reg: u8, value: u8) void {
    rtcObserve(c);
    if (reg == 0) {
        c.rtc.sec = value & 0x3F;
    } else if (reg == 1) {
        c.rtc.min = value & 0x3F;
    } else if (reg == 2) {
        c.rtc.hour = value & 0x1F;
    } else if (reg == 3) {
        c.rtc.day_lo = value;
    } else if (reg == 4) {
        c.rtc.day_hi = value & 0x01;
        c.rtc.halt = (value & 0x40) != 0;
        c.rtc.day_carry = (value & 0x80) != 0;
    }
}

// Restore live RTC state from a validated .rtc header. The anchor is preserved
// so the next observation accumulates time elapsed since the save.
pub fn rtcLoadState(c: *Cart, sec: u8, min: u8, hour: u8, day_lo: u8, day_hi: u8, halt: bool, carry: bool, anchor: i64) void {
    c.rtc.sec = sec & 0x3F;
    c.rtc.min = min & 0x3F;
    c.rtc.hour = hour & 0x1F;
    c.rtc.day_lo = day_lo;
    c.rtc.day_hi = day_hi & 0x01;
    c.rtc.halt = halt;
    c.rtc.day_carry = carry;
    c.rtc.anchor = anchor;
    c.rtc.started = true;
    c.rtc.latch_prev = 0xFF;
    rtcRelatch(c);
}

fn mbc1Read(c: *Cart, addr: u16) u8 {
    if (addr < 0x4000) {
        const off: usize = c.rom0_off + @intCast(usize, addr);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr < 0x8000) {
        const off: usize = c.romx_off + @intCast(usize, addr - 0x4000);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr >= 0xa000 and addr < 0xc000) {
        if (!c.ram_enable or c.ram_size == 0) return 0xff;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) return c.ram[off];
        return 0xff;
    }
    return 0xff;
}

fn mbc1Write(c: *Cart, addr: u16, value: u8) void {
    if (addr < 0x2000) {
        c.ram_enable = (value & 0x0F) == 0x0A;
    } else if (addr < 0x4000) {
        c.rom_bank_lo = value & 0x1F;
        mbc1Recompute(c);
    } else if (addr < 0x6000) {
        c.bank_hi = value & 0x03;
        mbc1Recompute(c);
    } else if (addr < 0x8000) {
        c.mode = value & 0x01;
        mbc1Recompute(c);
    } else if (addr >= 0xa000 and addr < 0xc000) {
        if (!c.ram_enable or c.ram_size == 0) return;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) c.ram[off] = value;
    }
}

fn mbc3Read(c: *Cart, addr: u16) u8 {
    if (addr < 0x4000) {
        const off: usize = c.rom0_off + @intCast(usize, addr);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr < 0x8000) {
        const off: usize = c.romx_off + @intCast(usize, addr - 0x4000);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr >= 0xa000 and addr < 0xc000) {
        if (c.ram_bank >= 8) {
            if (!c.ram_enable) return 0xff;
            return rtcRead(c, c.ram_bank - 8);
        }
        if (!c.ram_enable or c.ram_size == 0) return 0xff;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) return c.ram[off];
        return 0xff;
    }
    return 0xff;
}

fn mbc3Write(c: *Cart, addr: u16, value: u8) void {
    if (addr < 0x2000) {
        c.ram_enable = (value & 0x0F) == 0x0A;
    } else if (addr < 0x4000) {
        c.rom_bank_lo = value & 0x7F;
        mbc3Recompute(c);
    } else if (addr < 0x6000) {
        c.ram_bank = value & 0x0F;
        mbc3Recompute(c);
    } else if (addr < 0x8000) {
        rtcLatch(c, value);
    } else if (addr >= 0xa000 and addr < 0xc000) {
        if (c.ram_bank >= 8) {
            if (!c.ram_enable) return;
            rtcWrite(c, c.ram_bank - 8, value);
            return;
        }
        if (!c.ram_enable or c.ram_size == 0) return;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) c.ram[off] = value;
    }
}

fn mbc5Read(c: *Cart, addr: u16) u8 {
    if (addr < 0x4000) {
        const off: usize = @intCast(usize, addr);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr < 0x8000) {
        const off: usize = c.romx_off + @intCast(usize, addr - 0x4000);
        if (off < c.rom_size) return c.rom[off];
        return 0xff;
    }
    if (addr >= 0xa000 and addr < 0xc000) {
        if (!c.ram_enable or c.ram_size == 0) return 0xff;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) return c.ram[off];
        return 0xff;
    }
    return 0xff;
}

fn mbc5Write(c: *Cart, addr: u16, value: u8) void {
    if (addr < 0x2000) {
        c.ram_enable = (value & 0x0F) == 0x0A;
    } else if (addr < 0x3000) {
        c.rom_bank_lo = value;
        mbc5Recompute(c);
    } else if (addr < 0x4000) {
        c.bank_hi = value & 0x01;
        mbc5Recompute(c);
    } else if (addr < 0x6000) {
        c.ram_bank = value & 0x0F;
        mbc5Recompute(c);
    } else if (addr >= 0xa000 and addr < 0xc000) {
        if (!c.ram_enable or c.ram_size == 0) return;
        const off: usize = c.ram_off + @intCast(usize, addr - 0xa000);
        if (off < c.ram_size) c.ram[off] = value;
    }
}

fn plainRead(c: *Cart, addr: u16) u8 {
    if (addr < 0x8000) {
        const off: usize = @intCast(usize, addr);
        if (off < c.rom_size) return c.rom[off];
    }
    return 0xff;
}

pub fn cartRead(c: *Cart, addr: u16) u8 {
    switch (c.mbc) {
        .mbc1 => return mbc1Read(c, addr),
        .mbc3 => return mbc3Read(c, addr),
        .mbc5 => return mbc5Read(c, addr),
        .none => return plainRead(c, addr),
        else => return 0xff,
    }
}

pub fn cartWrite(c: *Cart, addr: u16, value: u8) void {
    switch (c.mbc) {
        .mbc1 => mbc1Write(c, addr, value),
        .mbc3 => mbc3Write(c, addr, value),
        .mbc5 => mbc5Write(c, addr, value),
        else => {},
    }
}

pub fn cartRamSize(c: *const Cart) usize {
    return c.ram_size;
}

pub fn cartSaveRam(c: *const Cart) []const u8 {
    return c.ram[0..c.ram_size];
}

pub fn cartLoadRam(c: *Cart, bytes: []const u8) bool {
    if (bytes.len != c.ram_size) return false;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        c.ram[i] = bytes[i];
    }
    return true;
}
