const ROM_CAP: usize = 8 * 1024 * 1024;
const RAM_CAP: usize = 131072;
const ROM_BANK: usize = 0x4000;
const RAM_BANK: usize = 0x2000;
const MIN_ROM: usize = 32768;

pub const Mbc = enum(u8) {
    none = 0,
    mbc1 = 1,
    mbc3 = 3,
    mbc5 = 5,
};

pub const CartError = error{ BadHeader, UnsupportedMbc, RomTooLarge, Io };

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
    c.rom0_off = 0;
    c.romx_off = 0;
    c.ram_off = 0;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        c.title[i] = 0;
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
    if (mask > 0x7F) mask = 0x7F;
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

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        c.title[i] = bytes[0x0134 + i];
    }
    i = 0;
    while (i < RAM_CAP) : (i += 1) {
        c.ram[i] = 0;
    }

    mbc1Recompute(c);
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
        .none => return plainRead(c, addr),
        .mbc3 => return plainRead(c, addr),
        .mbc5 => return plainRead(c, addr),
        else => return 0xff,
    }
}

pub fn cartWrite(c: *Cart, addr: u16, value: u8) void {
    switch (c.mbc) {
        .mbc1 => mbc1Write(c, addr, value),
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
